#!/bin/bash
# ============================================================================
# watch-cline.sh — C 线（撤销充值 / 退订进 UTC）次日观察脚本
#
# 为什么需要它：
#   C 线的两个监听器已在 20261104 换包时静态验收入包（class 计数 0→1），
#   但「监听器是否真的被事件触发并正确处理」只能等真实业务发生时才知道——
#   生产不允许为了验收而制造真实的撤销/退订数据。
#   本脚本让次日（或任意事后时刻）**一次跑完**就能判定，不必人肉翻日志。
#
# 五项判据：
#   ① 监听器/处理器类名在 info 日志里出现的次数（0 = 尚无真实事件到达，属正常）
#   ② 这些类是否在 error 日志里留下异常（出现即须人工看，可能是真缺陷）
#   ③ 相关 MQ 消费者的量级是否与换包前同量级（防止「事件到了但没被消费」）
#   ④ 换包后是否出现过任何换包前不存在的 logger（新增 logger = 新代码路径被执行）
#   ⑤ 定时任务（FlowUpdatedHandler / CycleUpdatedHandler）是否按整点照常触发
#
# 判读口径（重要，别误读）：
#   ① 为 0 **不是失败**。它只说明「观察窗口内没有真实撤销/退订业务发生」。
#      C 线的正确性判据是 ②③④⑤ 全部无异常 + 一旦 ① 非 0 时 ② 仍为 0。
#   ② 非 0 才是必须立刻上报的信号。
#
# 安全边界：只读。**只输出计数、类名、分钟戳、时间戳**；
#           一律不输出 " - " 之后的 message 正文，
#           因此不会把 ICCID / 手机号 / 经销商名称 / 金额带回终端。
#
# 用法： bash watch-cline.sh [SINCE_HH:MM:SS] [label]
#        缺省 SINCE=00:00:00（今天全天）。换包日应传 12:43:14。
#        例： bash watch-cline.sh 12:43:14 day1
#        输出写 /tmp/utc-cline-<label>.txt
# 依赖： sudo、grep、awk、sort、uniq
# ============================================================================
set -uo pipefail

SINCE="${1:-00:00:00}"
LABEL="${2:-adhoc}"

LOG_ROOT="${UTC_LOG_DIR:-/data/logs/ryd-utc-admin}"
OUT="${OUT_DIR:-/tmp}/utc-cline-${LABEL}.txt"

SUDO="sudo -n"
$SUDO true 2>/dev/null || SUDO=""

DATE="$(date +%F)"
INFO_LOG="$($SUDO find "$LOG_ROOT" -maxdepth 2 -name '*info*.log' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
ERR_LOG="$($SUDO find "$LOG_ROOT" -maxdepth 2 -name '*error*.log' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
[ -n "$INFO_LOG" ] || { echo "FATAL: 找不到 info 日志" >&2; exit 3; }

emit() { printf '%s=%s\n' "$1" "$2" >> "$OUT"; }
block() { printf '%s\n---- %s ----\n' "" "$1" >> "$OUT"; }

# C 线相关类名。取自交付物 class 清单（probe-utc-runtime.sh 的 cline_* 六项），
# 不要凭记忆增删——改这里必须同步改 runtime 探针，否则两边判据不一致。
CLINE_CLASSES="FlowAccountCancelListener FlowAccountRemoveTerminalListener CycleUpdatedHandler FlowAccountEvent FlowUpdatedHandler"
MQ_CONSUMERS="CardFlowQueryConsumer CardStatusUpdateConsumer CardNotifyConsumer"

TMP="$(mktemp)"
$SUDO grep -E "^${DATE} " "$INFO_LOG" 2>/dev/null | awk -v T="$SINCE" 'substr($0,12,8) >= T' > "$TMP"

: > "$OUT"
emit watch_label "$LABEL"
emit watch_ts "$(date -Is)"
emit window "${DATE} ${SINCE} ~ now"
emit info_log "$INFO_LOG"
emit error_log "${ERR_LOG:-none}"
emit slice_lines "$(wc -l < "$TMP" | tr -d ' ')"
emit slice_first_ts "$(head -1 "$TMP" | cut -c1-19)"
emit slice_last_ts "$(tail -1 "$TMP" | cut -c1-19)"

# ---- ① C 线类在 info 日志里的出现次数 ----
block "① C线类出现次数（0=窗口内无真实事件，非失败）"
for c in $CLINE_CLASSES; do
  N="$(grep -c "$c" "$TMP")"
  FIRST="$(grep "$c" "$TMP" | head -1 | cut -c12-19)"
  LAST="$(grep "$c" "$TMP" | tail -1 | cut -c12-19)"
  printf '%-40s count=%-6s first=%s last=%s\n' "$c" "$N" "${FIRST:--}" "${LAST:--}" >> "$OUT"
done

# ---- ② C 线类是否在 error 日志里留异常（非 0 即须立刻上报）----
block "② C线类在 error 日志中的出现次数（非0=须人工核查）"
if [ -n "${ERR_LOG:-}" ]; then
  ETMP="$(mktemp)"
  $SUDO grep -E "^${DATE} " "$ERR_LOG" 2>/dev/null | awk -v T="$SINCE" 'substr($0,12,8) >= T' > "$ETMP"
  emit error_slice_lines "$(wc -l < "$ETMP" | tr -d ' ')"
  for c in $CLINE_CLASSES; do
    printf '%-40s error_count=%s\n' "$c" "$(grep -c "$c" "$ETMP")" >> "$OUT"
  done
  # 换包后 error 里出现的全部 logger（用于发现任何新代码路径的异常）
  block "②b error 日志 logger 分布（窗口内全部）"
  awk '{
    s=$0; p=index(s,"] ");
    while (p>0) { s=substr(s,p+2); p=index(s,"] "); }
    q=index(s," - ");
    if (q>1) print substr(s,1,q-1); else print "UNPARSED";
  }' "$ETMP" | sort | uniq -c | sort -rn | head -15 >> "$OUT"
  rm -f "$ETMP"
else
  emit error_slice_lines "NO_ERROR_LOG"
fi

# ---- ③ MQ 消费者量级 ----
block "③ MQ 消费者计数（与换包前窗口对照，量级应一致）"
for m in $MQ_CONSUMERS; do
  printf '%-40s count=%s\n' "$m" "$(grep -c "$m" "$TMP")" >> "$OUT"
done

# ---- ④ 窗口内全部 logger（人工比对是否出现换包前不存在的类）----
block "④ info 日志 logger 分布（前 20；出现陌生类名=新代码路径被执行）"
awk '{
  s=$0; p=index(s,"] ");
  while (p>0) { s=substr(s,p+2); p=index(s,"] "); }
  q=index(s," - ");
  if (q>1) print substr(s,1,q-1); else print "UNPARSED";
}' "$TMP" | sort | uniq -c | sort -rn | head -20 >> "$OUT"

# ---- ⑤ 定时任务触发时刻 ----
block "⑤ xxl-job / JobThread 触发分钟（应每小时 HH:00 与 HH:01 各若干次）"
grep -e 'xxl-job' -e 'JobThread' -e 'XxlJobExecutor' "$TMP" \
  | grep -oE "^${DATE} [0-9]{2}:[0-9]{2}" | sort | uniq -c >> "$OUT"

# ---- ⑥ 按分钟 info 行数（识别整点 MQ 批量峰值是否正常出现）----
block "⑥ 按分钟 info 行数（前 12）"
grep -oE "^${DATE} [0-9]{2}:[0-9]{2}" "$TMP" | uniq -c | sort -rn | head -12 >> "$OUT"

rm -f "$TMP"
echo "---- C 线观察（${LABEL}, window=${DATE} ${SINCE}~now）----"
cat "$OUT"
echo "---- 已写入 ${OUT} ----"
