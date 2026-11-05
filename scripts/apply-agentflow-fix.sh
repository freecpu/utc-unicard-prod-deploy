#!/bin/bash
# ============================================================================
# apply-agentflow-fix.sh — 生产 threeants 预划拨 fail-closed 修复执行脚本（方案 A）
#
# 修的缺陷：
#   生产 threeants 自 2026-10-28 起预划拨 100% 抛「经销商流量池不存在」。
#   根因：jar 内 application-prod.yml 的 utc.agent-flow-coefficient /
#   utc.agent-flow-recharge-min 两个键**被注释掉**，而 threeants 无任何外置配置目录，
#   故运行期这两个属性为 null → AgentServiceImpl L371 的 isNull 判定命中 → fail-closed。
#
# ★ 为什么只注入这两个键（2026-11-05 读源码确认，不是推断）：
#   unicard-data/.../AgentServiceImpl.java L369-373：
#     Integer poolCoefficient = utcProperties.getAgentFlowCoefficient();
#     Integer poolRechargeMin = utcProperties.getAgentFlowRechargeMin();
#     if (Objects.isNull(poolCoefficient) || Objects.isNull(poolRechargeMin)) {
#         throw ENTITY_NOT_FOUND.newInstance().withMessage("经销商流量池不存在");
#     }
#   —— 判定只看这两个配置项。`utcProperties.getAgentFlowId()` 在整个 threeants
#   源码树的引用数为 **0**（L486 的 getAgentFlowId() 是 DTO 上的方法，与配置无关）。
#   REQ-20261022-03 #24 的改造注释明写「**替代**直读 UTC t_agent_flow(getAgentFlowById)」。
#   报错文案「经销商流量池不存在」是**沿用旧代码未改的字符串**，它误导人以为缺的是池 id。
#   且 application-prod.yml L52 的 `agentFlowId: 130820039822` 本来就是**未注释**的。
#
# 注入值来源：生产库自身 `ryd_utc.t_agent_flow WHERE id = 130820039822`
#   → coefficient = 50，recharge_min = 0
#   取证见 变更留痕/20261105-S4-D注入通路验证/agentflow-prod-query.txt
#   （scripts/read-prod-agentflow.sh，凭据不回显不落盘）。
#   ★ 不是从测试机夹具 application-dev.yml 抄的 —— prod yml 注释里
#     「杜绝误搬测试机 50/0」的顾虑是对的，只是生产实数恰好也是 50/0。
#
# 与 verify-d-injection.sh 的分工（不要混用）：
#   verify-d-injection.sh = **通路验证**工具，带 neg/neg2/neg3 负控，注入的是
#                           NOT_A_NUMBER / 99 这类**验证用值**，跑在测试机。
#   本脚本              = **生产修复执行**，注入真实值 50/0，只跑 pos 类路径。
#   生产上不跑 neg 类模式的依据见 指纹台账.md §7（jar 同源性逐字节证明）。
#
# 安全边界：
#   preflight / verify 模式**全程只读**。
#   apply / rollback 模式会改 unit 文件并重启服务（约 16 秒 7003 端口不可用），
#   **必须先取得用户对该动作的显式授权**。
#
# 用法：
#   bash apply-agentflow-fix.sh preflight     # 只读：核对现状与前置条件
#   bash apply-agentflow-fix.sh apply         # 写：备份 → 注入 → reload → restart → 验收
#   bash apply-agentflow-fix.sh verify        # 只读：复核修复后状态
#   bash apply-agentflow-fix.sh rollback      # 写：从备份还原并重启
#
#   生产上必须带 TA_LOG（否则日志判定不可信，脚本会拒绝下结论）：
#     TA_UNIT=ryd-unicard-official \
#     TA_LOG=/usr/local/ryd-unicard/var/official.log \
#     bash apply-agentflow-fix.sh apply
#
# 依赖： systemctl、sudo、ss、sed、sha256sum、stat、grep、diff
# ============================================================================
set -uo pipefail

MODE="${1:-preflight}"
case "$MODE" in preflight|apply|verify|rollback) ;; *)
  echo "FATAL: 未知模式 '${MODE}'（可选 preflight|apply|verify|rollback）" >&2; exit 2 ;;
esac

UNIT="${TA_UNIT:-ryd-unicard-official}"
PORT="${TA_PORT:-7003}"
UNIT_FILE="/etc/systemd/system/${UNIT}.service"
BAK="${TA_BAK:-/tmp/${UNIT}.bak-agentflow-fix}"

# ---- 注入值（可用环境变量覆盖，但覆盖时必须显式，防止误用默认值）----
COEF="${FIX_COEFFICIENT:-50}"
RMIN="${FIX_RECHARGE_MIN:-0}"
INJECT="-Dutc.agent-flow-coefficient=${COEF} -Dutc.agent-flow-recharge-min=${RMIN} "

# ---- 注入锚点 ----
# ★ 选在 `-Dfinance-refund.enabled=true ` 之后、jar 路径之前。
#   依据：生产现役 cmdline 已证明该位置上的 -D 生效（profiles.active=prod 就在这个区域）。
#   规则不是「必须在 -jar 之前」，而是「**必须在 jar 文件名之前**」——
#   生产 ExecStart 里 -jar 在最前面，三个 -D 全在其后且生效。
# ★ 这个锚点还能天然避开 unit L15 的注释变体：L15 用的是双横线程序参数形式
#   `--finance-refund.enabled=true`，不含 `-Dfinance-refund`，故不会被误匹配。
ANCHOR='-Dfinance-refund\.enabled=true '
ANCHOR_LITERAL='-Dfinance-refund.enabled=true '

# ---- 期望的改前 unit 指纹（指纹台账.md §5）----
# ★ 不匹配就停手：说明有人在本脚本之外改过 unit，此时按旧认知注入是不安全的。
EXPECT_UNIT_SHA="${EXPECT_UNIT_SHA:-ad1acd4d7fbb3aa63b4d6e7edda896c08c51130c45448b13bc09ff386e03570d}"

SUDO="sudo -n"
$SUDO true 2>/dev/null || SUDO=""

# ★ 生产 systemd 是 219（CentOS 7）：`systemctl show -p KEY --value` **不支持**
#   （报 unrecognized option 并静默取空），NRestarts 属性不存在，
#   StartLimitIntervalUSec 在 219 里叫 StartLimitInterval。一律用 cut。
sysd() { $SUDO systemctl show "$UNIT" -p "$1" 2>/dev/null | cut -d= -f2-; }

# ★ 读 root 进程的 /proc/<pid>/cmdline 一律用 `$SUDO cat | tr`，不用 `sudo tr < file`：
#   重定向由**当前 shell**（生产是非 root 的 runyd）打开文件，sudo 对它无效。
proc_cmdline() { $SUDO cat "/proc/$1/cmdline" 2>/dev/null | tr '\0' ' '; }

# ★ Type=simple + Restart=always 下 is-active 恒定不可作健康判据：
#   systemd 在 exec 成功那一刻就记 active，之后应用绑定失败、JVM 退出、100ms 后再拉起，
#   is-active 会在 active/activating 间跳。硬信号只有端口 LISTEN 与日志里点名的属性名。
port_up() { $SUDO ss -ltn 2>/dev/null | grep -c ":${PORT} "; }

wait_port() {
  local n="${1:-90}" i=0
  while [ "$i" -lt "$n" ]; do
    [ "$(port_up)" != "0" ] && { echo "$i"; return 0; }
    sleep 2; i=$((i+2))
  done
  echo "TIMEOUT_${n}s"; return 1
}

# ---- 日志源：生产 journal 为空，全靠 official.log 的字节偏移增量读 ----
# ExecStart 是 /bin/sh -c "exec java ... > official.log 2>&1"，重定向在 sh **内部**完成，
# systemd 收不到任何输出。只读 journal 会让命中数恒为 0，把「日志源是死的」
# 当成「没有绑定异常」→ 假阳性。official.log 实测已 522MB 且仍在涨，整读不可接受。
LOGFILE="${TA_LOG:-}"
LOG_OFFSET=0

log_snapshot_offset() {
  [ -n "$LOGFILE" ] || { LOG_OFFSET=0; echo "log_source=journal-only（未设 TA_LOG）"; return 0; }
  if ! $SUDO test -e "$LOGFILE"; then
    LOG_OFFSET=0; echo "log_source=${LOGFILE}（当前不存在，偏移记 0）"; return 0
  fi
  LOG_OFFSET="$($SUDO stat -c '%s' "$LOGFILE" 2>/dev/null | tr -d ' ')"
  [ -n "$LOG_OFFSET" ] || LOG_OFFSET=0
  echo "log_source=${LOGFILE}"
  echo "log_offset_before=${LOG_OFFSET}"
}

log_new_text() {
  $SUDO journalctl -u "$UNIT" --since "$1" --no-pager 2>/dev/null
  if [ -n "$LOGFILE" ] && $SUDO test -e "$LOGFILE"; then
    local cur off
    cur="$($SUDO stat -c '%s' "$LOGFILE" 2>/dev/null | tr -d ' ')"
    off="${LOG_OFFSET:-0}"
    # 观测期内被轮转/截断时 cur < off，tail -c +N 会输出空 → 又退化成假阳性，
    # 故显式警告并退回整读（此时文件已变小，整读可接受）。
    if [ -n "$cur" ] && [ "$cur" -lt "$off" ]; then
      echo "WARN: ${LOGFILE} 在观测期内被轮转/截断（${off} → ${cur}），改为整读" >&2
      $SUDO cat "$LOGFILE" 2>/dev/null
    else
      $SUDO tail -c "+$((off + 1))" "$LOGFILE" 2>/dev/null
    fi
  fi
}

unit_sha() { $SUDO sha256sum "$UNIT_FILE" 2>/dev/null | cut -d' ' -f1; }

echo "==== mode=${MODE} unit=${UNIT} host=$(hostname) ===="
echo "ts=$(date -Is)"

# ---------------------------------------------------------------- preflight
# 只读核对：现状 + 前置条件。不满足就停手，不进 apply。
if [ "$MODE" = "preflight" ] || [ "$MODE" = "apply" ] || [ "$MODE" = "verify" ]; then
  echo "== 只读现状 =="
  echo "systemd_version=$($SUDO systemctl --version 2>/dev/null | head -1)"
  echo "unit_type=$(sysd Type)"
  echo "restart_policy=$(sysd Restart) / $(sysd RestartUSec)"
  echo "start_limit=$(sysd StartLimitBurst) / $(sysd StartLimitInterval)"
  echo "is_active=$($SUDO systemctl is-active "$UNIT" 2>&1)  (Type=simple 下不可作健康判据)"
  PID_NOW="$(sysd MainPID)"
  echo "MainPID=${PID_NOW}"
  echo "ExecMainStartTimestamp=$(sysd ExecMainStartTimestamp)"
  echo "port_listen=$(port_up)"
  echo "unit_sha256=$(unit_sha)"
  echo "unit_bytes=$($SUDO stat -c '%s' "$UNIT_FILE" 2>/dev/null)"
  CMD_NOW="$(proc_cmdline "${PID_NOW:-0}")"
  # ★ 显式给出 cmdline 长度：HAS_D=0 是**否定性判据**（fail-closed 的运行期证据），
  #   而 CMD 取空时它同样是 0 —— 「读到 0」与「真的没有」必须能区分。
  echo "proc_cmdline_len=${#CMD_NOW}"
  echo "has_agent_flow_D=$(printf '%s' "$CMD_NOW" | grep -c 'agent-flow')"
  echo "current_ExecStart:"
  $SUDO grep -n '^ExecStart' "$UNIT_FILE" 2>/dev/null | sed 's/^/  /'
  echo "anchor_match_count=$($SUDO grep -c -- "$ANCHOR_LITERAL" "$UNIT_FILE" 2>/dev/null)"
fi

if [ "$MODE" = "preflight" ]; then
  echo "== 前置条件判定 =="
  US="$(unit_sha)"
  AC="$($SUDO grep -c -- "$ANCHOR_LITERAL" "$UNIT_FILE" 2>/dev/null)"
  OK=1
  if [ "$US" = "$EXPECT_UNIT_SHA" ]; then
    echo "  [PASS] unit sha256 与指纹台账 §5 一致"
  else
    echo "  [FAIL] unit sha256 = ${US}"
    echo "         期望       = ${EXPECT_UNIT_SHA}"
    echo "         → unit 已被本脚本之外的人改过，不得按旧认知注入。先查清改了什么。"
    OK=0
  fi
  if [ "${AC:-0}" = "1" ]; then
    echo "  [PASS] 注入锚点唯一匹配（${AC} 处）—— 不会误伤 L15 的注释变体"
  else
    echo "  [FAIL] 注入锚点匹配 ${AC:-0} 处，期望恰好 1 处。sed 会改错行或改多行，停手。"
    OK=0
  fi
  if [ "$(printf '%s' "$CMD_NOW" | grep -c 'agent-flow')" = "0" ] && [ "${#CMD_NOW}" -gt 0 ]; then
    echo "  [PASS] 现役 cmdline 无任何 -Dutc.agent-flow-* → fail-closed 成立（缺陷未被人修过）"
  elif [ "${#CMD_NOW}" = "0" ]; then
    echo "  [FAIL] 读不到 /proc/${PID_NOW}/cmdline（长度 0）→ has_agent_flow_D=0 不可采信，停手"
    OK=0
  else
    echo "  [WARN] 现役 cmdline 已含 agent-flow → 可能已被人修过，先确认再决定是否 apply"
  fi
  if [ -n "$LOGFILE" ] && $SUDO test -e "$LOGFILE"; then
    echo "  [PASS] TA_LOG=${LOGFILE} 存在（$($SUDO stat -c '%s' "$LOGFILE" 2>/dev/null) B）"
  else
    echo "  [FAIL] TA_LOG 未设或文件不存在（当前='${LOGFILE:-<未设>}'）"
    echo "         生产 journal 为空，没有 TA_LOG 就无法判定绑定异常 → apply 会拒绝下结论。"
    OK=0
  fi
  echo "== 注入内容预览（尚未写入）=="
  echo "  锚点   : ${ANCHOR_LITERAL}"
  echo "  追加   : ${INJECT}"
  echo "  备份到 : ${BAK}"
  [ "$OK" = "1" ] && echo "PREFLIGHT_OK: 前置条件全部满足，可进 apply（须用户显式授权重启）" \
                  || echo "PREFLIGHT_FAIL: 有前置条件不满足，禁止 apply"
  exit 0
fi

# ---------------------------------------------------------------- apply
if [ "$MODE" = "apply" ]; then
  echo "== 前置闸门 =="
  US="$(unit_sha)"
  AC="$($SUDO grep -c -- "$ANCHOR_LITERAL" "$UNIT_FILE" 2>/dev/null)"
  if [ "$US" != "$EXPECT_UNIT_SHA" ]; then
    echo "FATAL: unit sha256 与台账不符（实=${US} 期望=${EXPECT_UNIT_SHA}），拒绝改动。" >&2; exit 3
  fi
  if [ "${AC:-0}" != "1" ]; then
    echo "FATAL: 锚点匹配 ${AC:-0} 处（期望 1），拒绝改动。" >&2; exit 3
  fi
  if [ -z "$LOGFILE" ]; then
    echo "FATAL: 未设 TA_LOG。生产 journal 为空，改完无法判定是否绑定成功，拒绝执行。" >&2
    echo "       用法：TA_LOG=/usr/local/ryd-unicard/var/official.log bash $0 apply" >&2; exit 3
  fi
  # 值合法性：必须是纯数字。注入非数字会让服务起不来（这正是 neg 模式证明过的）。
  case "$COEF" in ''|*[!0-9]*) echo "FATAL: FIX_COEFFICIENT='${COEF}' 不是纯数字，拒绝注入。" >&2; exit 3 ;; esac
  case "$RMIN" in ''|*[!0-9]*) echo "FATAL: FIX_RECHARGE_MIN='${RMIN}' 不是纯数字，拒绝注入。" >&2; exit 3 ;; esac
  echo "  [PASS] unit 指纹、锚点唯一性、TA_LOG、注入值均为纯数字"

  echo "== 备份 =="
  if [ -e "$BAK" ]; then
    echo "FATAL: 备份 ${BAK} 已存在。不覆盖——避免把已注入的版本当原始版本。" >&2
    echo "       若确认它是旧残留，先人工核对其 sha256 是否等于 ${EXPECT_UNIT_SHA} 再手工移走。" >&2
    exit 4
  fi
  $SUDO cp -p "$UNIT_FILE" "$BAK"
  BAK_SHA="$($SUDO sha256sum "$BAK" 2>/dev/null | cut -d' ' -f1)"
  echo "backup_created=${BAK}"
  echo "backup_sha256=${BAK_SHA}"
  if [ "$BAK_SHA" != "$EXPECT_UNIT_SHA" ]; then
    echo "FATAL: 备份 sha256 与改前 unit 不符，备份不可信，拒绝继续。" >&2; exit 4
  fi
  echo "  [PASS] 备份 sha256 == 改前 unit sha256 == 台账值"

  echo "== 注入 =="
  echo "改前 ExecStart:"; $SUDO grep '^ExecStart' "$UNIT_FILE" | sed 's/^/  /'
  # 用 # 作 sed 分隔符，避免与 -D 里的 . 和路径里的 / 冲突；锚点里的 . 已转义。
  $SUDO sed -i "s#${ANCHOR}#${ANCHOR_LITERAL}${INJECT}#" "$UNIT_FILE"
  SED_RC=$?
  echo "sed_rc=${SED_RC}"
  # ★ sed 无匹配时静默不改（rc 仍为 0），是典型假阴性 → 必须自检注入是否真落进去。
  if ! $SUDO grep -q 'utc.agent-flow-coefficient' "$UNIT_FILE"; then
    echo "FATAL: 注入没生效（unit 里找不到 agent-flow-coefficient）。已从备份还原。" >&2
    $SUDO cp -f "$BAK" "$UNIT_FILE"; $SUDO systemctl daemon-reload; exit 5
  fi
  echo "改后 ExecStart:"; $SUDO grep '^ExecStart' "$UNIT_FILE" | sed 's/^/  /'
  # ★ 改动面核对：必须**只有 ExecStart 那一行**变了。多改一行就说明 sed 打歪了。
  DIFF_LINES="$($SUDO diff "$BAK" "$UNIT_FILE" 2>/dev/null | grep -c '^[<>]')"
  echo "diff_changed_lines=${DIFF_LINES}  (期望 2 = 一行旧 + 一行新)"
  if [ "${DIFF_LINES:-0}" != "2" ]; then
    echo "FATAL: 改动面不是恰好一行（diff 计数=${DIFF_LINES}）。已还原，须人工排查。" >&2
    $SUDO diff "$BAK" "$UNIT_FILE" 2>&1 | sed 's/^/  /'
    $SUDO cp -f "$BAK" "$UNIT_FILE"; $SUDO systemctl daemon-reload; exit 5
  fi
  echo "  [PASS] 改动面恰好一行"
  echo "new_unit_sha256=$(unit_sha)   ← 记入指纹台账"

  echo "== 重启 =="
  $SUDO systemctl daemon-reload
  SINCE="$(date '+%Y-%m-%d %H:%M:%S')"
  log_snapshot_offset
  PID_BEFORE="$(sysd MainPID)"
  echo "PID_before=${PID_BEFORE}"
  # ★ 必须 reset-failed：Restart=always + RestartUSec=100ms + StartLimitBurst=5
  #   + StartLimitInterval=10s。注入后若启动失败，可能撞进限流把单元钉在 failed，
  #   此时 restart 会被直接拒掉。单元没进 failed 时本命令是无害空操作。
  #   注意：失败形态究竟是哪一种**无法断言**（单轮启动到绑定失败约需数秒，
  #   测试机完整启动实测 16s，而窗口也是 10s）—— 两种结果都是服务持续 DOWN。
  $SUDO systemctl reset-failed "$UNIT" 2>/dev/null
  $SUDO systemctl restart "$UNIT"
  echo "restart_rc=$?"
  echo "restart_since=${SINCE}"
  echo "port_up_after_secs=$(wait_port 90)"

  echo "== 结果 =="
  PID_AFTER="$(sysd MainPID)"
  echo "is_active=$($SUDO systemctl is-active "$UNIT" 2>&1)  (不可作健康判据)"
  echo "PID_after=${PID_AFTER}"
  echo "ExecMainStartTimestamp=$(sysd ExecMainStartTimestamp)"
  PL="$(port_up)"
  echo "port_listen=${PL}"
  CMD_AFTER="$(proc_cmdline "${PID_AFTER:-0}")"
  echo "proc_cmdline_len=${#CMD_AFTER}"
  # 逐个值核对，不只看「有没有 agent-flow」：注入了错的值同样算失败。
  printf '%s' "$CMD_AFTER" | tr ' ' '\n' | grep -o 'agent-flow[a-z.-]*=[^ ]*' | sed 's/^/cmdline_/'
  CD_COEF="$(printf '%s' "$CMD_AFTER" | grep -c -- "-Dutc.agent-flow-coefficient=${COEF}")"
  CD_RMIN="$(printf '%s' "$CMD_AFTER" | grep -c -- "-Dutc.agent-flow-recharge-min=${RMIN}")"
  echo "cmdline_coef_exact_match=${CD_COEF}   cmdline_rmin_exact_match=${CD_RMIN}"
  # profile 不能被改坏（sed 打歪的最可能后果之一）
  echo "cmdline_profile=$(printf '%s' "$CMD_AFTER" | grep -o 'spring.profiles.active=[a-z]*' || echo MISSING)"

  JTXT="$(log_new_text "$SINCE")"
  LOG_LINES="$(printf '%s' "$JTXT" | grep -c .)"
  LOG_ALIVE="$(printf '%s' "$JTXT" | grep -cE 'Started .*Application|Starting .*Application|Spring Boot|Tomcat started|JVM running')"
  echo "log_lines_seen=${LOG_LINES}"
  echo "log_source_alive_markers=${LOG_ALIVE}"
  # 只取属性名与异常类名，不打印完整堆栈（避免带出配置值与其它敏感内容）
  printf '%s' "$JTXT" \
    | grep -oE "(utc\.agent-flow-[a-z-]+|agentFlowCoefficient|agentFlowRechargeMin|BindException|ConversionFailedException|ConverterNotFoundException|Failed to bind)" \
    | sort | uniq -c | sed 's/^/  /'
  KEYCNT="$(printf '%s' "$JTXT" | grep -cE 'utc\.agent-flow-[a-z-]+|BindException|Failed to bind')"
  echo "binding_error_lines=${KEYCNT}"

  echo "== 判定 =="
  # ★★ 总闸放在所有分支之前：日志源没读到任何行时，binding_error_lines=0 只说明
  #   日志源是死的，不说明没有绑定异常。少了这道闸，静默失效会伪装成修复成功。
  if [ "${LOG_LINES:-0}" = "0" ]; then
    echo "LOG_SOURCE_DEAD: 从 journal 与 ${LOGFILE} 都没读到任何日志行。"
    echo "        所有基于日志的判定无效。服务当前 port_listen=${PL}、PID=${PID_AFTER}。"
    echo "        先确认 TA_LOG 指向的是 ExecStart 里重定向的那个文件，再重跑 verify。"
    echo "        **不得据此宣称修复成功。** 如需退回：bash $0 rollback"
    exit 7
  fi
  if [ "${PL:-0}" != "0" ] && [ "${CD_COEF:-0}" != "0" ] && [ "${CD_RMIN:-0}" != "0" ] \
     && [ "${KEYCNT:-0}" = "0" ] && [ "${LOG_ALIVE:-0}" != "0" ]; then
    echo "APPLY_OK: 端口 ${PORT} 已 LISTEN；cmdline 含两个 -D 且值精确匹配 ${COEF}/${RMIN}；"
    echo "          日志源确认存活（${LOG_LINES} 行、${LOG_ALIVE} 个启动特征串）且无绑定异常。"
    echo "          → 两个属性已非 null，AgentServiceImpl L371 的 isNull 分支不再命中。"
    echo "  仍须补的一环：预划拨**真实业务调用**成功。本脚本不制造业务数据，"
    echo "          须由业务侧发起一次真实预划拨确认不再抛「经销商流量池不存在」。"
  elif [ "${PL:-0}" = "0" ]; then
    echo "APPLY_FAIL: 端口 ${PORT} 未 LISTEN —— 服务没起来。"
    echo "          立刻回滚：bash $0 rollback   （备份在 ${BAK}）"
    exit 8
  else
    echo "APPLY_INCONCLUSIVE: 端口起来了但判据未全过"
    echo "          port_listen=${PL} coef_match=${CD_COEF:-0} rmin_match=${CD_RMIN:-0}"
    echo "          binding_error_lines=${KEYCNT:-0} alive_markers=${LOG_ALIVE:-0}"
    echo "          须人工核对。如需退回：bash $0 rollback"
    exit 9
  fi
  exit 0
fi

# ---------------------------------------------------------------- verify
if [ "$MODE" = "verify" ]; then
  echo "== 修复后复核（只读）=="
  PID_V="$(sysd MainPID)"
  CMD_V="$(proc_cmdline "${PID_V:-0}")"
  echo "proc_cmdline_len=${#CMD_V}"
  echo "coef_exact=$(printf '%s' "$CMD_V" | grep -c -- "-Dutc.agent-flow-coefficient=${COEF}")"
  echo "rmin_exact=$(printf '%s' "$CMD_V" | grep -c -- "-Dutc.agent-flow-recharge-min=${RMIN}")"
  echo "unit_sha256=$(unit_sha)"
  echo "backup_exists=$([ -e "$BAK" ] && echo YES || echo NO)"
  [ -e "$BAK" ] && echo "backup_sha256=$($SUDO sha256sum "$BAK" 2>/dev/null | cut -d' ' -f1)"
  PL_V="$(port_up)"
  echo "port_listen=${PL_V}"
  # 运行时长：用于证明服务自修复后未再重启（Restart=always 下反复重启会归零）
  echo "proc_etimes_sec=$($SUDO ps -o etimes= -p "${PID_V:-0}" 2>/dev/null | tr -d ' ')"
  if [ "${PL_V:-0}" != "0" ] \
     && [ "$(printf '%s' "$CMD_V" | grep -c -- "-Dutc.agent-flow-coefficient=${COEF}")" != "0" ] \
     && [ "$(printf '%s' "$CMD_V" | grep -c -- "-Dutc.agent-flow-recharge-min=${RMIN}")" != "0" ]; then
    echo "VERIFY_OK: 注入值在运行期生效、端口 LISTEN"
  else
    echo "VERIFY_FAIL: 见上面各项计数"
    exit 8
  fi
  exit 0
fi

# ---------------------------------------------------------------- rollback
if [ "$MODE" = "rollback" ]; then
  echo "== 回滚 =="
  [ -e "$BAK" ] || { echo "FATAL: 找不到备份 ${BAK}，无法自动回滚，须人工处理。" >&2; exit 4; }
  BAK_SHA="$($SUDO sha256sum "$BAK" 2>/dev/null | cut -d' ' -f1)"
  echo "backup_sha256=${BAK_SHA}"
  if [ "$BAK_SHA" != "$EXPECT_UNIT_SHA" ]; then
    echo "FATAL: 备份 sha256 不等于改前 unit 的台账值 ${EXPECT_UNIT_SHA}。" >&2
    echo "       回滚到一个来历不明的文件比不回滚更危险，停手人工核对。" >&2; exit 4
  fi
  echo "改前 ExecStart:"; $SUDO grep '^ExecStart' "$UNIT_FILE" | sed 's/^/  /'
  $SUDO cp -f "$BAK" "$UNIT_FILE"
  $SUDO systemctl daemon-reload
  $SUDO systemctl reset-failed "$UNIT" 2>/dev/null
  $SUDO systemctl restart "$UNIT"
  echo "restart_rc=$?"
  echo "port_up_after_secs=$(wait_port 90)"
  echo "改后 ExecStart:"; $SUDO grep '^ExecStart' "$UNIT_FILE" | sed 's/^/  /'
  echo "unit_sha256=$(unit_sha)  (应回到 ${EXPECT_UNIT_SHA})"
  PID_R="$(sysd MainPID)"
  CMD_R="$(proc_cmdline "${PID_R:-0}")"
  HAS_D="$(printf '%s' "$CMD_R" | grep -c 'agent-flow')"
  echo "PID_after=${PID_R}  proc_cmdline_len=${#CMD_R}  cmdline_has_agent_flow_D=${HAS_D}"
  echo "port_listen=$(port_up)"
  if [ "$(port_up)" != "0" ] && [ "${HAS_D:-0}" = "0" ] && [ "$(unit_sha)" = "$EXPECT_UNIT_SHA" ] \
     && [ "${#CMD_R}" -gt 0 ]; then
    echo "ROLLBACK_OK: unit 指纹已回到台账值、无 -D 残留、端口 ${PORT} LISTEN"
    echo "        注意：回滚意味着 fail-closed 缺陷**重新生效**，须另行安排修复。"
  else
    echo "ROLLBACK_FAIL: 须人工介入。备份在 ${BAK}"
    exit 8
  fi
  exit 0
fi
