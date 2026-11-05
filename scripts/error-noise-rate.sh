#!/bin/bash
# ============================================================================
# error-noise-rate.sh — error 日志「既有背景噪声速率」画像
#
# 为什么需要它：
#   换包后看到某类异常，第一反应不能是「新包引入的」。本机 error 日志常年有
#   IoTGatewayException（联通侧「无短信记录」）等背景噪声，也有外部调用方打进来
#   的 RydException。要判定「是不是换包引入」，必须知道**换包之前这类异常本来
#   就以什么速率在发生**。本脚本给出全天按小时的速率画像，使「背景 vs 新增」可判定。
#
#   实测教训：只在换包后取一次 error 计数，会把「本来就在发生的噪声」误判成
#   「换包引入的回归」（本轮就出现过：after 报告新增 NestedServletException，
#   实为回归探针自己打的 8 次 GET /no/such/path）。
#
# 安全边界：只读。**只输出时间戳、计数、异常类名**，不输出日志正文，
#           因此不会把 ICCID / 手机号 / 任何业务数据带回终端。
#
# 用法： bash error-noise-rate.sh [YYYY-MM-DD] [HH:MM:SS]
#        第1参缺省用今天；第2参可选，传入后额外给出「该时刻之后」的
#        logger 分布与按分钟事件数（用于换包后定位新增噪声来源）。
#        输出写 /tmp/utc-noiserate-<date>.txt
# 依赖： sudo（读 root 属主日志）、grep、awk、sort、uniq
# ============================================================================
set -uo pipefail

DATE="${1:-$(date +%F)}"
LOG_ROOT="${UTC_LOG_DIR:-/data/logs/ryd-utc-admin}"
OUT="${OUT_DIR:-/tmp}/utc-noiserate-${DATE}.txt"

SUDO="sudo -n"
$SUDO true 2>/dev/null || SUDO=""

ERR_LOG="$($SUDO find "$LOG_ROOT" -maxdepth 2 -name "*error*${DATE}*.log" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
if [ -z "$ERR_LOG" ]; then
  ERR_LOG="$($SUDO find "$LOG_ROOT" -maxdepth 2 -name '*error*.log' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
fi
[ -n "$ERR_LOG" ] || { echo "FATAL: 找不到 error 日志" >&2; exit 3; }

: > "$OUT"
{
  echo "# error-noise-rate date=${DATE}"
  echo "# log=${ERR_LOG}"
  echo "# log_bytes=$($SUDO stat -c %s "$ERR_LOG" 2>/dev/null)"
  echo "# ts=$(date -Is)"
} >> "$OUT"

# 所有「带时间戳的行」= 一次异常事件的头部。续行（at xxx / Caused by）不算事件。
EVENTS="$($SUDO grep -E "^${DATE} [0-9]{2}:[0-9]{2}:[0-9]{2}" "$ERR_LOG" 2>/dev/null)"

echo "---- 事件总数（带时间戳的行）----" >> "$OUT"
printf '%s\n' "$EVENTS" | grep -c . >> "$OUT"

echo "---- 按小时分布 ----" >> "$OUT"
printf '%s\n' "$EVENTS" | grep -oE "^${DATE} [0-9]{2}" | uniq -c >> "$OUT"

echo "---- 按小时 × 异常类名 ----" >> "$OUT"
# 事件头行里通常带异常类名；不带的（如 advice 只记 message）归为 NO_TYPE。
printf '%s\n' "$EVENTS" | awk -v D="$DATE" '{
  hh = substr($0, 12, 2);
  t = "NO_TYPE";
  if (match($0, /[A-Za-z][A-Za-z0-9_.]*Exception/)) t = substr($0, RSTART, RLENGTH);
  printf "%s %s:00  %s\n", D, hh, t;
}' | sort | uniq -c | sort -k2 >> "$OUT"

echo "---- logger 类名分布（全天）----" >> "$OUT"
# 实测行形：2026-11-04 13:01:43,123 [ERROR] [thread] com.ryd.xxx.Yyy - message
# 只取方括号后、" - " 前的类名。类名不是业务数据，可安全外发；
# 而 " - " 之后的 message **一律不取**（那里才会有 ICCID/手机号）。
# 为什么需要：全天 2624 个事件里绝大多数是 NO_TYPE（行内没异常类名），
# 单看异常类名分布会把主体噪声归为未知，无法判定“是不是换包引入”。
printf '%s\n' "$EVENTS" | awk '{
  s=$0; p=index(s,"] ");
  while (p>0) { s=substr(s,p+2); p=index(s,"] "); }
  q=index(s," - ");
  if (q>1) print substr(s,1,q-1); else print "UNPARSED";
}' | sort | uniq -c | sort -rn | head -20 >> "$OUT"

echo "---- logger 类名分布（换包后，仅当传入第2参时）----" >> "$OUT"
SINCE="${2:-}"
if [ -n "$SINCE" ]; then
  printf '%s\n' "$EVENTS" | awk -v T="$SINCE" 'substr($0,12,8) >= T' | awk '{
    s=$0; p=index(s,"] ");
    while (p>0) { s=substr(s,p+2); p=index(s,"] "); }
    q=index(s," - ");
    if (q>1) print substr(s,1,q-1); else print "UNPARSED";
  }' | sort | uniq -c | sort -rn | head -20 >> "$OUT"
  echo "---- 按分钟事件数（since ${SINCE}）----" >> "$OUT"
  printf '%s\n' "$EVENTS" | awk -v T="$SINCE" 'substr($0,12,8) >= T' \
    | grep -oE "^${DATE} [0-9]{2}:[0-9]{2}" | uniq -c >> "$OUT"
else
  echo "(未传第2参 HH:MM:SS，跳过)" >> "$OUT"
fi

echo "---- 各异常类名全天计数与首末时刻 ----" >> "$OUT"
for t in $(printf '%s\n' "$EVENTS" | grep -oE '[A-Za-z][A-Za-z0-9_.]*Exception' | sort -u); do
  N="$(printf '%s\n' "$EVENTS" | grep -cF "$t")"
  F="$(printf '%s\n' "$EVENTS" | grep -F "$t" | head -1 | cut -c12-19)"
  L="$(printf '%s\n' "$EVENTS" | grep -F "$t" | tail -1 | cut -c12-19)"
  printf '%-52s count=%-6s first=%s last=%s\n' "$t" "$N" "$F" "$L" >> "$OUT"
done

echo "---- 已写入 ${OUT} ----"
cat "$OUT"
