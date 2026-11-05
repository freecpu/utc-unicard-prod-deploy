#!/bin/bash
# ============================================================================
# probe-utc-traffic.sh — UTC 真实业务流量存活探针（换包后必做）
#
# 为什么需要它（不要只靠自造探针下结论）：
#   probe-utc-http.sh 打的是**我自己造的假卡号请求**，只能证明「服务能应答」。
#   它证明不了「上游调用方还在正常拿到数据」——例如 agent-mp 每分钟调 N4
#   /openapi/agent/list 取经销商列表，若换包后 token 校验、序列化、DB 通路
#   任何一环坏了，我的探针（故意不带 token）依然会得到"准入校验失败"这个
#   **预期响应**，从而看不出问题。
#   本探针改看 info 日志里的**真实业务流量**：调用方、端点、结果条数、定时任务。
#   真实流量恢复 = 链路真的通了，这是自造探针给不出的证据。
#
# 三项判据：
#   ① openapi N4 在换包后仍有成功记录，且「结果数」与换包前同量级
#   ② xxl-job 的 JobThread 在换包后的整点仍触发（每小时 HH:00 / HH:01）
#   ③ 换包后 info 日志无 ERROR 级新增、无「准入校验失败」激增
#
# 安全边界：只读。**只输出计数、分钟戳、结果条数**；
#           grep 出的行一律先 cut 掉 " - " 之后的 message 正文，
#           因此不会把 ICCID / 手机号 / 经销商名称带回终端。
#
# 用法： bash probe-utc-traffic.sh <HH:MM:SS> [label] [UNTIL_HH:MM:SS]
#        例： bash probe-utc-traffic.sh 12:43:14 after-swap
#             bash probe-utc-traffic.sh 11:43:14 pre-swap 12:43:14
#        第3参可选，用于取一个**换包前的对照窗口**。必须取对照窗：
#        “换包后 N4 有 60 次”本身不是判据，得知道换包前同长度窗口本来多少次。
#        输出写 /tmp/utc-traffic-<label>.txt
# 依赖： sudo、grep、awk、sort、uniq
# ============================================================================
set -uo pipefail

SINCE="${1:-}"
LABEL="${2:-adhoc}"
UNTIL="${3:-}"
if [ -z "$SINCE" ]; then
  echo "用法: bash probe-utc-traffic.sh <HH:MM:SS> [label] [UNTIL_HH:MM:SS]" >&2
  exit 2
fi

LOG_ROOT="${UTC_LOG_DIR:-/data/logs/ryd-utc-admin}"
OUT="${OUT_DIR:-/tmp}/utc-traffic-${LABEL}.txt"

SUDO="sudo -n"
$SUDO true 2>/dev/null || SUDO=""

INFO_LOG="$($SUDO find "$LOG_ROOT" -maxdepth 2 -name '*info*.log' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
[ -n "$INFO_LOG" ] || { echo "FATAL: 找不到 info 日志" >&2; exit 3; }

DATE="$(date +%F)"
emit() { printf '%s=%s\n' "$1" "$2" >> "$OUT"; }

# 只取今天、且时刻 >= SINCE 的行。info 日志量大（今日已 20MB+），
# 故先按日期前缀过滤再进内存，不整文件读入变量。
TMP="$(mktemp)"
if [ -n "$UNTIL" ]; then
  $SUDO grep -E "^${DATE} " "$INFO_LOG" 2>/dev/null \
    | awk -v T="$SINCE" -v U="$UNTIL" 'substr($0,12,8) >= T && substr($0,12,8) < U' > "$TMP"
else
  $SUDO grep -E "^${DATE} " "$INFO_LOG" 2>/dev/null | awk -v T="$SINCE" 'substr($0,12,8) >= T' > "$TMP"
fi

: > "$OUT"
emit probe_label "$LABEL"
emit probe_ts "$(date -Is)"
emit window "${SINCE} ~ ${UNTIL:-now}"
emit info_log "$INFO_LOG"
emit info_log_bytes "$($SUDO stat -c %s "$INFO_LOG" 2>/dev/null)"
emit slice_lines "$(wc -l < "$TMP" | tr -d ' ')"
emit slice_first_ts "$(head -1 "$TMP" | cut -c1-19)"
emit slice_last_ts "$(tail -1 "$TMP" | cut -c1-19)"

# ---- ① openapi 真实调用（N1-N4）----
emit openapi_lines "$(grep -c 'openapi' "$TMP")"
# OpenapiReadService 的成功记录形如：… - openapi N4 page=0，size=200，结果数=65，tot…
# 只抽「端点代号 + 结果数」，不抽正文其余部分。
emit openapi_by_endpoint "$(grep -oE 'openapi N[0-9]' "$TMP" | sort | uniq -c | tr '\n' ';')"
emit openapi_result_counts "$(grep -oE 'openapi N[0-9].{0,40}' "$TMP" | grep -oE '结果数=[0-9]+' | sort | uniq -c | sort -rn | head -8 | tr '\n' ';')"
emit openapi_minutes_active "$(grep 'openapi N' "$TMP" | grep -oE "^${DATE} [0-9]{2}:[0-9]{2}" | sort -u | wc -l | tr -d ' ')"
emit openapi_first_last "$(grep 'openapi N' "$TMP" | head -1 | cut -c12-19)-$(grep 'openapi N' "$TMP" | tail -1 | cut -c12-19)"
# 准入校验失败 = 上游 token 不对。换包后若激增，说明 token 注入链路断了。
emit openapi_auth_fail "$(grep -c '准入校验失败' "$TMP")"

# ---- ② xxl-job 定时任务 ----
emit xxl_lines "$(grep -c -e 'xxl-job' -e 'JobThread' "$TMP")"
emit xxl_minutes "$(grep -e 'xxl-job' -e 'JobThread' "$TMP" | grep -oE "^${DATE} [0-9]{2}:[0-9]{2}" | sort | uniq -c | tr '\n' ';')"

# ---- ③ 关键业务动作计数（换包后若全为 0 且换包前也 0，则属正常无业务）----
for k in recharge allocate Cancel CycleUpdated FlowPackage FlowUpdated Terminal UserRecharge; do
  emit "biz_${k}" "$(grep -c "$k" "$TMP")"
done

# ---- ④ ERROR 级行（info 日志里不该有；有则说明 appender 配置或级别异常）----
emit error_level_in_info "$(grep -c '\[ERROR\]' "$TMP")"

# ---- ⑤ 日志量归因（换包后必查）----
# 为什么需要：实测出现过换包后同长度窗口 info 行数从 72 暴涨到 7011（100 倍）。
# 这种量差可能是三种完全不同的东西，不得笼统归为“正常”：
#   a) 启动日志集中在重启那一分钟（无害，会自然回落）
#   b) 新包把某个 logger 提到了 DEBUG/TRACE（有害，会很快写爆磁盘：
#      本机 stdout.log 已经 12.7GB 未轮转）
#   c) 真实业务量恢复（无害，但得能说出是哪个 logger）
# 下面按分钟 + 按 logger 两个维度拆开，使三者可区分。
printf '%s\n---- 按分钟 info 行数 ----' >> "$OUT"
grep -oE "^${DATE} [0-9]{2}:[0-9]{2}" "$TMP" | uniq -c | sort -rn | head -12 >> "$OUT"
printf '%s\n---- 按 logger 类名计数（前 15）----' >> "$OUT"
# 只取 " - " 之前的类名；message 正文一律不取（那里才会有 ICCID/手机号）。
awk '{
  s=$0; p=index(s,"] ");
  while (p>0) { s=substr(s,p+2); p=index(s,"] "); }
  q=index(s," - ");
  if (q>1) print substr(s,1,q-1); else print "UNPARSED";
}' "$TMP" | sort | uniq -c | sort -rn | head -15 >> "$OUT"
printf '%s\n---- 按日志级别计数 ----' >> "$OUT"
grep -oE '\[(INFO|WARN|ERROR|DEBUG|TRACE) *\]' "$TMP" | sort | uniq -c | sort -rn >> "$OUT"

rm -f "$TMP"
echo "---- 真实业务流量存活（${LABEL}, window=${SINCE}~${UNTIL:-now}）----"
cat "$OUT"
echo "---- 已写入 ${OUT} ----"
