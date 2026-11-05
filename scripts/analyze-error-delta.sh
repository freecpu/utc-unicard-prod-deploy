#!/bin/bash
# ============================================================================
# analyze-error-delta.sh — error 日志增量归因（换包后必做）
#
# 为什么需要它：
#   「error 计数涨了」本身不能判定是不是换包引入的问题。本机 error 日志常年有
#   IoTGatewayException（联通侧「无短信记录」）等既有噪声，且**回归探针自己就会
#   制造异常**（H03 触发 HttpMediaTypeNotSupportedException、H12 触发
#   NestedServletException、H11 触发 RydException）。若 before 的计数取在 HTTP
#   探针之前、after 的取在之后，delta 就会被探针自身污染，得出假阳性结论。
#
#   本脚本按时间切片 + 按异常类型分类 + 给出每类的首末出现时刻，
#   使「哪些是探针造的、哪些是既有的、哪些是新增的」可判定。
#
# 安全边界：只读。只输出异常类型名、计数、时间戳；不输出日志正文，
#           因此不会把 ICCID / 手机号 / 任何业务数据带回终端。
#
# 用法： bash analyze-error-delta.sh <YYYY-MM-DD> <HH:MM:SS> [label]
#        例： bash analyze-error-delta.sh 2026-11-04 12:38:56 after
#        日期与时刻分开传，由脚本内部拼空格——规避 PowerShell→ssh 剥双引号后
#        含空格的参数被断词（本脚本第一版用 sed /date.time/ 切片，因 error 日志里
#        根本没有以该分钟开头的时间戳行而静默返回 1 行，是假阴性）。
#        输出写 /tmp/utc-errdelta-<label>.txt
# ============================================================================
set -uo pipefail

DATE="${1:-}"
TIME="${2:-}"
LABEL="${3:-adhoc}"
if [ -z "$DATE" ] || [ -z "$TIME" ]; then
  echo "用法: bash analyze-error-delta.sh <YYYY-MM-DD> <HH:MM:SS> [label]" >&2
  exit 2
fi

LOG_ROOT="${UTC_LOG_DIR:-/data/logs/ryd-utc-admin}"
OUT="${OUT_DIR:-/tmp}/utc-errdelta-${LABEL}.txt"

SUDO="sudo -n"
$SUDO true 2>/dev/null || SUDO=""

ERR_LOG="$($SUDO find "$LOG_ROOT" -maxdepth 2 -name '*error*.log' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
[ -n "$ERR_LOG" ] || { echo "FATAL: 找不到 error 日志" >&2; exit 3; }

: > "$OUT"
{
  echo "# error-delta label=${LABEL} since=${DATE} ${TIME}"
  echo "# log=${ERR_LOG}"
  echo "# ts=$(date -Is)"
} >> "$OUT"

# 切片语义：以日期开头的行按 HH:MM:SS >= TIME 更新标志位；
# 其余行（堆栈续行、Caused by、at xxx）继承当前标志位。
# 这样既不会漏掉无时间戳的续行，也不会把 since 之前的异常算进来。
SLICE="$($SUDO awk -v D="$DATE" -v T="$TIME" 'substr($0,1,10)==D { f = (substr($0,12,8) >= T) } f' "$ERR_LOG" 2>/dev/null)"

# 诊断：切片前先看该日志里各分钟的时间戳行分布，确认 since 之后确实有行。
# 若这里为空而 error 总行数在涨，说明增长全是无时间戳的续行，须改按总行数判定。
emit_block() {
  local title="$1"
  echo "---- ${title} ----" >> "$OUT"
}

emit_block "timestamped_lines_per_minute_since"
printf '%s\n' "$SLICE" | grep -oE "^${DATE} [0-9]{2}:[0-9]{2}" | uniq -c >> "$OUT"

emit_block "slice_total_lines"
printf '%s\n' "$SLICE" | wc -l | tr -d ' ' >> "$OUT"

emit_block "exception_type_counts"
printf '%s\n' "$SLICE" | grep -oE '[A-Za-z][A-Za-z0-9_.]*Exception' | sort | uniq -c | sort -rn >> "$OUT"

# ★ 与 probe-utc-runtime.sh 的 error_distinct_types 对齐。
# 那个探针用的是 '[A-Za-z.]*Exception'（**允许零长前缀**），所以会从
# "…handle Exception”、"(Exception" 这类文本里抽出一个裸的 "Exception"；
# 而本脚本上面的 '[A-Za-z][A-Za-z0-9_.]*Exception' 结构上不可能产出裸 Exception。
# 两个正则不同 → 两份输出不可比。实测就因此踩了一次：runtime 探针 after
# 报告新增了裸 "Exception" 类型，而本脚本的切片里根本没这个类型。
# 故下面用 runtime 探针的原正则重算一遍，并对裸 Exception 命中只打印
# **前 24 个字符**（足以看出它是什么词的一部分，又不会带回日志正文）。
RUNTIME_RE='[A-Za-z.]*Exception'
emit_block "exception_type_counts_runtime_regex"
printf '%s\n' "$SLICE" | grep -oE "$RUNTIME_RE" | sort | uniq -c | sort -rn >> "$OUT"

emit_block "bare_exception_preceding_char"
# 只统计“裸 Exception”（前面不是字母也不是点）的**前一个字符是什么**，带计数。
# 两个取舍：
#  a) 用 awk 而不是 grep -oE ".{0,24}(^|[^A-Za-z.])Exception"：后者把 ^ 放进
#     中段 alternation，在 GNU grep 里行为不可靠（实测匹不到东西，是静默假阴性）。
#  b) **只取 1 个字符，不取上下文窗口**。取 20 字上下文虽然更好认，但会把
#     日志正文片段带进输出，违反“不外发业务数据”边界；而前一字符已足以
#     判定它是 "(Exception" / " Exception" / ":Exception" 中的哪一种。
printf '%s\n' "$SLICE" | awk '{
  s=$0;
  while ((p=index(s,"Exception"))>0) {
    prev = (p==1 ? "<BOL>" : substr(s,p-1,1));
    if (prev !~ /[A-Za-z.]/) printf "prev=[%s]\n", prev;
    s = substr(s, p+9);
  }
}' | sort | uniq -c | sort -rn >> "$OUT"
emit_block "bare_exception_line_count"
printf '%s\n' "$SLICE" | grep -cE '(^|[^A-Za-z.])Exception' >> "$OUT"

emit_block "timestamped_line_index"
# 对切片里**每一条带时间戳的行**，只打印：时间戳(前19字) + 本行出现的异常类名 +
# 本行是否含探针特征串。目的是把“某分钟涨了 N 行”落到“这 N 行分别是什么”，
# 否则只知道计数不知道归属（实测就出现过 12:41 有 3 行无法归属的情况）。
# 不打印日志正文，因此不会带回 ICCID / 手机号 / 任何业务数据。
printf '%s\n' "$SLICE" | awk -v D="$DATE" '
  substr($0,1,10)==D {
    ts=substr($0,1,19);
    types="";
    s=$0;
    while (match(s, /[A-Za-z][A-Za-z0-9_.]*Exception/)) {
      t=substr(s, RSTART, RLENGTH);
      if (index(types, t)==0) types = types t ",";
      s=substr(s, RSTART+RLENGTH);
    }
    probe="";
    if (index($0,"/no/such/path")>0)      probe = probe "H12,";
    if (index($0,"no-such-endpoint")>0)     probe = probe "H10,";
    if (index($0,"JwtToken")>0)             probe = probe "H11,";
    if (index($0,"octet-stream")>0)         probe = probe "H03,";
    if (index($0,"mall/terminal")>0)        probe = probe "H11path,";
    printf "%s\ttypes=%s\tprobe=%s\n", ts, (types==""?"-":types), (probe==""?"-":probe);
  }' >> "$OUT"

emit_block "first_last_occurrence_per_type"
for t in $(printf '%s\n' "$SLICE" | grep -oE '[A-Za-z][A-Za-z0-9_.]*Exception' | sort -u); do
  FIRST="$(printf '%s\n' "$SLICE" | grep -F "$t" | head -1 | cut -c1-19)"
  LAST="$(printf '%s\n' "$SLICE" | grep -F "$t" | tail -1 | cut -c1-19)"
  N="$(printf '%s\n' "$SLICE" | grep -cF "$t")"
  printf '%s\tcount=%s\tfirst=%s\tlast=%s\n' "$t" "$N" "$FIRST" "$LAST" >> "$OUT"
done

# 探针自身的特征串：出现即证明该异常由回归探针制造，不是业务回归
emit_block "probe_attribution_markers"
for m in 'no-such-endpoint' '/no/such/path' 'octet-stream' 'JwtToken' 'Not Found'; do
  N="$(printf '%s\n' "$SLICE" | grep -cF "$m")"
  printf '%s=%s\n' "$m" "$N" >> "$OUT"
done

# 按分钟统计已并入上方 timestamped_lines_per_minute_since

echo "---- error 增量归因（${LABEL}, since=${DATE} ${TIME}）----"
cat "$OUT"
echo "---- 已写入 ${OUT} ----"
