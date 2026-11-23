#!/bin/bash
# ============================================================================
# deploy/_lib.sh — 部署脚本公共基础设施（★ 不含任何项目业务步骤）
#
# 这里只提供四类能力：
#   1) 锚文件读取与形状校验（anchors/*.env）
#   2) 只读 ssh 通道 ro_ssh（内置写动作黑名单 + 强制 -n）
#   3) 写动作闸门 wr_guard（APPLY=1 + 按动作授权串）
#   4) 证据目录 evi_new（变更留痕/<日期>-<GROUP>-<project>/）
#
# 设计取舍：
#   ★ anchors/*.env 一律「逐行解析」，绝不 source。
#     原因：值里存在 <date>、含空格的 GAP= 行、-Dkey=value 这类内容，
#     source 会被 shell 当成重定向符／命令分隔，轻则变量被截断，重则执行意外命令。
#   ★ ssh 一律 -n：脚本经管道传入时（tr -d '\r' < x.sh | bash），
#     首次 ssh 会吞掉后续脚本行，表现为「备份后静默中断、后续步骤未执行」。
#   ★ 只读与写动作分两个函数：ro_ssh 带黑名单，写动作必须过 wr_guard。
#     这样即使脚本写错，也不可能在没有授权串时写到生产。
#
# 用法：
#   bash deploy/_lib.sh lint [project|all]      # 锚形状校验（只读）
#   bash deploy/_lib.sh show <project>          # 打印锚（脱敏：本仓锚无凭据）
#   bash deploy/_lib.sh evi <GROUP> <project>   # 建本次证据目录
#   source deploy/_lib.sh                       # 在项目脚本里复用函数
# ============================================================================
set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$LIB_DIR/.." && pwd)"
ANCHOR_DIR="$ROOT/anchors"
TODAY="$(date +%Y%m%d)"

log()  { printf '%s\n' "$*"; }
ok()   { printf '[OK] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
err()  { printf '[FAIL] %s\n' "$*"; }
die()  { printf '[FATAL] %s\n' "$*" >&2; exit 2; }

# ---------------------------------------------------------------------------
# 1) 锚读取
# ---------------------------------------------------------------------------
# 单值：取该 KEY 的最后一次出现（同名 KEY 后续覆盖前者）
anchor_val() {
  awk -F'=' -v k="$2" '$1==k { sub(/^[^=]*=/,""); v=$0 } END { if (v!="") print v }' "$1" \
    | sed -e 's/^"//' -e 's/"$//'
}

# 多值：同名 KEY 全部输出（GAP= 可能多行）
anchor_all() {
  awk -F'=' -v k="$2" '$1==k { sub(/^[^=]*=/,""); gsub(/^"|"$/,""); print }' "$1"
}

# 键是否存在（区分「写漏了键」与「显式声明为空值」——后者合法）
anchor_present() {
  awk -F'=' -v k="$2" '$1==k { found=1 } END { print found+0 }' "$1"
}

# 把白名单键导出为 shell 变量（供项目脚本使用）
anchor_load() {
  local p="${1:-}" f k v line
  [ -n "$p" ] || die "anchor_load 需要项目名"
  f="$ANCHOR_DIR/$p.env"
  [ -f "$f" ] || die "锚文件不存在：$f"
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    k="${line%%=*}"
    v="${line#*=}"
    v="${v#\"}"; v="${v%\"}"
    case "$k" in
      PROJECT|GROUP|SOP|MODE|HOST_ALIAS|HOST_ROLE|STATUS|DEPLOY_ROOT|PRIMARY_FILE|\
UNIT|UNIT_FILE|UNIT_SHA|UNIT_BYTES|PORT|RESTART|BACKUP_DIR|BACKUP_NAMING|\
PROBE|LOG_FILE|VHOST_FILE|VHOST_SHA|CURRENT_FILES|ROLLBACK_FILES|IMMUTABLE_FILES|\
HARD_PREREQ|RESTART_WINDOW_FORBID|PRE_RESTART_STEP|POST_STEP)
        export "$k=$v" ;;
    esac
  done < "$f"
}

# ---------------------------------------------------------------------------
# 2) 锚形状校验
# ---------------------------------------------------------------------------
SHA_RE='^[0-9a-f]{64}$'
REQUIRED_KEYS='PROJECT GROUP SOP MODE HOST_ALIAS STATUS DEPLOY_ROOT PRIMARY_FILE CURRENT_FILES ROLLBACK_FILES IMMUTABLE_FILES RESTART PROBE JUDGE_REQUIRED'

# 三元组字段：空格分隔的 name=sha:bytes；bytes 可为 ? （=未采，计 GAP）
check_triples() {
  local file="$1" key="$2" raw seg name sha bytes bad=0
  raw="$(anchor_val "$file" "$key")"
  [ -n "$raw" ] || return 0
  for seg in $raw; do
    case "$seg" in *=*:*) ;; *) err "  $key 段形状错（缺 = 或 :）：$seg"; bad=$((bad+1)); continue ;; esac
    name="${seg%%=*}"
    sha="${seg#*=}"; sha="${sha%%:*}"
    bytes="${seg##*:}"
    if [ "$sha" != "?" ] && ! printf '%s' "$sha" | grep -Eq "$SHA_RE"; then
      err "  $key/$name sha 非 64 位小写 hex：$sha"; bad=$((bad+1))
    fi
    case "$bytes" in
      ''|*[!0-9?]*) err "  $key/$name bytes 非数字且非 ?：$bytes"; bad=$((bad+1)) ;;
    esac
    case "$name" in */*|*.*) ;; *) warn "  $key/$name 文件名形态可疑（无扩展名/无路径）" ;; esac
  done
  return $bad
}

lint_one() {
  local p="${1:-}" f k v status gap=0 bad=0 n n_unset
  [ -n "$p" ] || die "lint 需要项目名或 all"
  f="$ANCHOR_DIR/$p.env"
  [ -f "$f" ] || { err "$p：锚文件不存在 $f"; return 1; }
  status="$(anchor_val "$f" STATUS)"

  log "== lint: $p =="
  # 必填＝键必须出现在文件里；值允许为空（显式声明无该项，如静态 dist 无禁动文件）
  for k in $REQUIRED_KEYS; do
    if [ "$(anchor_present "$f" "$k")" = "0" ]; then
      err "  $k 键缺失（整行没写）"; bad=$((bad+1)); continue
    fi
    v="$(anchor_val "$f" "$k")"
    [ -n "$v" ] && continue
    case "$k" in
      CURRENT_FILES|ROLLBACK_FILES)
        if [ "$status" = "BLOCKED" ]; then warn "  $k 为空（STATUS=BLOCKED，允许）"
        else err "  $k 键存在但值为空（READY 项目必须有锚）"; bad=$((bad+1)); fi ;;
      *)
        warn "  $k 显式为空（允许：由单项字段或 VHOST_SHA 等替代）" ;;
    esac
  done

  check_triples "$f" CURRENT_FILES   || bad=$((bad+$?))
  check_triples "$f" ROLLBACK_FILES  || bad=$((bad+$?))
  check_triples "$f" IMMUTABLE_FILES || bad=$((bad+$?))

  for k in UNIT_SHA VHOST_SHA; do
    v="$(anchor_val "$f" "$k")"
    [ -n "$v" ] || continue
    if [ "$v" = "?" ]; then gap=$((gap+1)); continue; fi
    printf '%s' "$v" | grep -Eq "$SHA_RE" || { err "  $k 非 64 位小写 hex：$v"; bad=$((bad+1)); }
  done

  # 未采项一律 ? → 计 GAP；apply 阶段必须清零
  n_unset="$(grep -c '=?$' "$f" 2>/dev/null)"; [ -n "$n_unset" ] || n_unset=0
  gap=$((gap + n_unset))
  n="$(grep -c '^GAP=' "$f" 2>/dev/null)"; [ -n "$n" ] || n=0

  if [ "$status" = "BLOCKED" ]; then
    warn "  STATUS=BLOCKED：$(anchor_val "$f" BLOCKED_REASON)"
  fi
  log "  GAP 条目=$n  未采字段=? 项=$gap  硬错=$bad"
  if [ "$bad" -eq 0 ]; then ok "  $p 形状通过（GAP $n 条待补采：不阻断 dry-run，阻断 apply）"; else err "  $p 形状不过：$bad 处"; fi
  return $bad
}

lint_all() {
  local f p total=0 pass=0 fail=0
  for f in "$ANCHOR_DIR"/*.env; do
    [ -f "$f" ] || die "anchors/ 下无 .env"
    p="$(basename "$f" .env)"
    total=$((total+1))
    if lint_one "$p"; then pass=$((pass+1)); else fail=$((fail+1)); fi
  done
  log "=============================================="
  log "LINT_RESULT total=$total pass=$pass fail=$fail"
  [ "$fail" -eq 0 ] || return 1
}

# ---------------------------------------------------------------------------
# 3) 只读 ssh 通道（写动作黑名单）
# ---------------------------------------------------------------------------
RO_DENY='(^|[^a-z-])(mv|rm|cp|chmod|chown|truncate|dd|tee|mkdir|touch|ln|install|useradd|usermod)([^a-z-]|$)'
RO_DENY_SVC='systemctl[[:space:]]+(restart|start|stop|reload|enable|disable|mask|daemon-reload)|service[[:space:]]+[^[:space:]]+[[:space:]]+(start|stop|restart)|nginx[[:space:]]+-s|docker[[:space:]]+(run|rm|start|stop|restart|compose|exec)|sed[[:space:]]+-i'

assert_ro() {
  local cmd="${1:-}" s
  printf '%s' "$cmd" | grep -Eq "$RO_DENY" && die "只读通道拒绝：命令含文件写动作 → $cmd"
  printf '%s' "$cmd" | grep -Eq "$RO_DENY_SVC" && die "只读通道拒绝：命令含服务/容器写动作 → $cmd"
  s="${cmd//2>\/dev\/null/}"; s="${s//>\/dev\/null/}"; s="${s//2>\&1/}"
  printf '%s' "$s" | grep -q '>' && die "只读通道拒绝：命令含输出重定向 → $cmd"
  printf '%s' "$s" | grep -q '>>' && die "只读通道拒绝：命令含追加重定向 → $cmd"
  return 0
}

# 只读远程执行：固定 -n（禁 stdin 吞脚本）、BatchMode（禁交互卡死）
ro_ssh() {
  local host="${1:-}" cmd="${2:-}"
  [ -n "$host" ] && [ -n "$cmd" ] || die "ro_ssh 需要 host 与 cmd"
  assert_ro "$cmd"
  ssh -n -o BatchMode=yes -o ConnectTimeout=8 "$host" "$cmd"
}

# ---------------------------------------------------------------------------
# 4) 写动作闸门 + 证据目录
# ---------------------------------------------------------------------------
# 写阶段必须同时满足：APPLY=1 且 CONFIRM=<GROUP>-<phase>-<YYYYMMDD>
# 授权串与当次动作/日期绑定，无法跨次复用，替代「靠记性守纪律」。
WR_REQUIRED_ENV='APPLY CONFIRM'

wr_guard() {
  local phase="${1:-}" want
  [ -n "${GROUP:-}" ] || die "wr_guard 前必须先 anchor_load <project>"
  [ "${APPLY:-0}" = "1" ] || die "默认只读：未设 APPLY=1，不执行任何写动作（先跑 dry-run）"
  want="${GROUP}-${phase}-${TODAY}"
  [ "${CONFIRM:-}" = "$want" ] || die "写动作需授权串 CONFIRM=$want（按动作授权，不可复用）"
  ok "写授权通过：$want"
}

evi_new() {
  local group="${1:-}" project="${2:-}" dir
  [ -n "$group" ] && [ -n "$project" ] || die "evi_new 需要 GROUP 与 project"
  dir="$ROOT/变更留痕/${TODAY}-${group}-${project}"
  [ -e "$dir" ] && dir="${dir}-b"
  mkdir -p "$dir" || die "证据目录创建失败：$dir"
  printf '%s\n' "$dir"
}

# ---------------------------------------------------------------------------
# 5) 自检：证明 lint 与只读黑名单确实能检出真阳性（否则「全绿」是假阴性）
# ---------------------------------------------------------------------------
_A64='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'

_mk_anchor() { # $1=目标文件 $2=模式：ok|bad_sha|bad_bytes|ready_empty
  local f="$1" mode="$2" sha="$_A64" cur='index.html='"$_A64"':1'
  case "$mode" in
    bad_sha)     sha='0123456789abcdef0123456789abcdef01234567' ;;
    bad_bytes)   cur='index.html='"$_A64"':xyz' ;;
    ready_empty) cur='' ;;
  esac
  cat > "$f" <<EOF
PROJECT=t
GROUP=GX
SOP=sop/x.md
MODE=static-dist
HOST_ALIAS=host
STATUS=READY
DEPLOY_ROOT=/x
PRIMARY_FILE=index.html
CURRENT_FILES="$cur"
ROLLBACK_FILES="index.html=$_A64:1"
IMMUTABLE_FILES=""
RESTART=no
PROBE=p
JUDGE_REQUIRED=j
UNIT_SHA=$sha
EOF
}

selftest() {
  local d rc=0 old_anchor
  d="$(mktemp -d)" || die "mktemp 失败"
  old_anchor="$ANCHOR_DIR"
  _mk_anchor "$d/ok.env" ok
  _mk_anchor "$d/bad_sha.env" bad_sha
  _mk_anchor "$d/bad_bytes.env" bad_bytes
  _mk_anchor "$d/ready_empty.env" ready_empty
  ANCHOR_DIR="$d"

  log "== selftest：锚校验正控/负控 =="
  # 负控：合法锚必须通过（证明工具不是无脑报错）
  if lint_one ok >/dev/null 2>&1; then ok "负控 PASS：合法锚被判通过"; else err "负控 FAIL：合法锚被误判"; rc=1; fi
  # 正控 1~3：三类形状错误必须各自被判不通过
  local n
  for n in bad_sha bad_bytes ready_empty; do
    if lint_one "$n" >/dev/null 2>&1; then err "正控 FAIL：$n 未被检出（工具瞎了）"; rc=1
    else ok "正控 PASS：$n 被判不通过"; fi
  done

  log "== selftest：只读通道黑名单正控/负控 =="
  # 正控 4~5：写动作必须被拦
  if ( assert_ro 'mv /a /b' ) >/dev/null 2>&1; then err "正控 FAIL：mv 未被拦"; rc=1; else ok "正控 PASS：mv 被拒"; fi
  if ( assert_ro 'sudo systemctl restart ryd-utc-admin' ) >/dev/null 2>&1; then err "正控 FAIL：systemctl restart 未被拦"; rc=1; else ok "正控 PASS：systemctl restart 被拒"; fi
  # 负控 6：常见只读命令必须放行
  if ( assert_ro 'sha256sum /data/x.jar; df -h /data; systemctl show -p MainPID x | cut -d= -f2-' ) >/dev/null 2>&1; then
    ok "负控 PASS：只读命令被放行"
  else err "负控 FAIL：只读命令被误拦"; rc=1; fi

  ANCHOR_DIR="$old_anchor"
  rm -rf "$d"
  if [ "$rc" -eq 0 ]; then log "SELFTEST_OK"; else log "SELFTEST_FAIL"; fi
  return "$rc"
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
main() {
  local sub="${1:-}"
  case "$sub" in
    lint)  shift; if [ "${1:-all}" = "all" ]; then lint_all; else lint_one "${1:-}"; fi ;;
    selftest) selftest ;;
    show)  shift; anchor_load "${1:-}"; anchor_val "$ANCHOR_DIR/${1}.env" CURRENT_FILES; anchor_val "$ANCHOR_DIR/${1}.env" ROLLBACK_FILES ;;
    evi)   shift; evi_new "${1:-}" "${2:-}" ;;
    "")    sed -n '2,30p' "$0" ;;
    *)     die "未知子命令：$sub（可用 lint|selftest|show|evi）" ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
