#!/bin/bash
# ============================================================================
# probe-statusdesc.sh — threeants 7003 卡详情 statusDesc 实证探针（G4 硬前置）
#
# 用途：G3 换包后，用真实生产卡号实证 GET /api/web/iccid/{iccid} 返回
#       非空 statusDesc（REQ-20261113-01 目标增量），供主管核验后解锁 G4。
#
# ★ PII 红线（本脚本存在的意义就是守住它）：
#   1) 真实卡号只作运行时第 1 参传入，严禁写进脚本/命令行历史留档/git；
#      建议执行时用 `read -s ICCID` 读入再 `bash probe-statusdesc.sh "$ICCID"`。
#   2) 出参只带掩码卡号（前4后4）＋status＋statusDesc 文本；
#      完整响应体只在 mktemp 临时文件停留，用毕即 rm，绝不落盘留存。
#   3) message 等自由文本里若内嵌长数字串（≥12位）一律掩码后才输出。
#   4) 只读 GET，零写库；只打本机回环 127.0.0.1:7003。
#
# 用法： bash probe-statusdesc.sh <真实iccid> [期望statusDesc文本]
#        第 2 参可选：传入则做逐字比对（如「预清除」），不传只验非空。
# 输出： 终端＋/tmp/ta-statusdesc.txt（仅掩码行，可归档出机）
# 判定： STATUSDESC_OK（非空且可选比对过）/ STATUSDESC_ABSENT（键缺席或空）
#        / HTTP_FAIL（非 200 或业务失败，实证不成立）
# 依赖： curl（必需）、jq（可选，缺失降级 grep 抽取）、sha256sum 不需要
# ============================================================================
set -uo pipefail

ICCID="${1:-}"
EXPECT="${2:-}"
HOST="${TA_HOST:-127.0.0.1}"
PORT="${TA_PORT:-7003}"
OUT="${OUT_DIR:-/tmp}/ta-statusdesc.txt"

[ -n "$ICCID" ] || { echo "FATAL: 缺第 1 参（真实 iccid，运行时传入）" >&2; exit 3; }
command -v curl >/dev/null 2>&1 || { echo "FATAL: curl 不存在" >&2; exit 3; }
HAVE_JQ=1
command -v jq >/dev/null 2>&1 || HAVE_JQ=0

# 掩码函数：前4后4，中间一律 ****（长度不足 9 的入参整体打码）
mask() {
  local s="$1"
  if [ "${#s}" -ge 9 ]; then
    printf '%s****%s' "${s:0:4}" "${s: -4}"
  else
    printf '****'
  fi
}
# 自由文本脱敏：≥12 位连续数字串整体替换为 [MASKED]
sanitize() {
  sed 's/[0-9]\{12,\}/[MASKED]/g'
}

MASKED="$(mask "$ICCID")"
tmp="$(mktemp)"
http="$(curl -s -m 25 -o "$tmp" -w '%{http_code}' \
  "http://${HOST}:${PORT}/api/web/iccid/${ICCID}" 2>/dev/null)"

status="-"; sdesc="-"; sdesc_present=0; code="-"; msg="-"
if [ "$HAVE_JQ" = "1" ] && jq -e . < "$tmp" >/dev/null 2>&1; then
  code="$(jq -r 'if has("code") then (.code|tostring) else "-" end' < "$tmp")"
  msg="$(jq -r 'if has("message") then (.message|tostring) else "-" end' < "$tmp" | sanitize)"
  status="$(jq -r '.data.status // "-"' < "$tmp" 2>/dev/null)"
  sdesc_present="$(jq -r 'if (.data|type=="object") and (.data|has("statusDesc")) then 1 else 0 end' < "$tmp" 2>/dev/null)"
  sdesc="$(jq -r '.data.statusDesc // "-"' < "$tmp" 2>/dev/null | sanitize)"
else
  # 降级：grep 抽取（不解析 JSON，只找键；抽取后同样脱敏）
  msg="NON_JSON_OR_NO_JQ"
  status="$(grep -o '"status"[[:space:]]*:[[:space:]]*"\{0,1\}[0-9A-Za-z_]*' "$tmp" | head -1 | sed 's/.*[:"]\([0-9A-Za-z_]*\)$/\1/')"
  if grep -q '"statusDesc"' "$tmp"; then
    sdesc_present=1
    sdesc="$(grep -o '"statusDesc"[[:space:]]*:[[:space:]]*"[^"]*"' "$tmp" | head -1 | sed 's/.*:[[:space:]]*"\(.*\)"$/\1/' | sanitize)"
  fi
fi
rm -f "$tmp"   # ★ 完整响应体即毁，不留存

verdict="HTTP_FAIL"
if [ "$http" = "200" ] && [ "$sdesc_present" = "1" ] && [ -n "$sdesc" ] && [ "$sdesc" != "-" ] && [ "$sdesc" != "null" ]; then
  verdict="STATUSDESC_OK"
  if [ -n "$EXPECT" ] && [ "$sdesc" != "$EXPECT" ]; then
    verdict="STATUSDESC_MISMATCH"
  fi
elif [ "$http" = "200" ]; then
  verdict="STATUSDESC_ABSENT"
fi

{
  echo "# ta-statusdesc-probe ts=$(date '+%Y-%m-%dT%H:%M:%S%z')"
  echo "# iccid_masked=${MASKED} jq=${HAVE_JQ}"
  printf 'http=%s code=%s status=%s statusDesc_present=%s statusDesc=%s message=%s\n' \
    "$http" "$code" "$status" "$sdesc_present" "$sdesc" "$msg"
  [ -n "$EXPECT" ] && echo "# expect=${EXPECT}"
  echo "VERDICT=${verdict}"
} | tee "$OUT"

case "$verdict" in
  STATUSDESC_OK) exit 0 ;;
  *) exit 5 ;;
esac