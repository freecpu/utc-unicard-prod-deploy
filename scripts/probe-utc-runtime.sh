#!/bin/bash
# ============================================================================
# probe-utc-runtime.sh — UTC (ryd-utc-admin) 运行态探针
#
# 用途：判定「新包是否真的上线了」以及「重启后服务是否真的健康」。
#       与 probe-utc-http.sh 配套：本脚本看进程/产物，那个脚本看接口行为。
#
# 判据来源（四项运行态探针，缺一即判"未部署"）：
#   ① 现役 jar 的 sha256/字节数 = 新包
#   ② systemd ExecMainStartTimestamp 晚于新包生成时刻
#   ③ 监听 8001 的 pid = 当前 MainPID
#   ④ 产物级反证：jar 内 class 清单含目标类（C 线新增类）
#
# 冒烟三判据（判"健康"而非只看 is-active）：
#   ⑤ info 日志出现 Started UtcAdminApp in N seconds
#   ⑥ ss -ltn 命中 :8001
#   ⑦ 重启时刻之后的 error 日志 0 个新增 Exception（既有噪声须逐条分类）
#
# 安全边界：全程只读。不改配置、不重启、不写业务库。
#           唯一写入是 /tmp 下的探针输出文件。
#           日志内容只取"计数"与"固定英文标记"，不外发任何凭据/卡号/手机号。
#
# 用法： bash probe-utc-runtime.sh <label>
#        label 取 before / after / adhoc
# 依赖： systemctl、ss、sha256sum、unzip、grep；sudo（读 root 属主的日志与目录）
# ============================================================================
set -uo pipefail

LABEL="${1:-adhoc}"
UNIT="${UTC_UNIT:-ryd-utc-admin}"
PORT="${UTC_PORT:-8001}"
APP_DIR="${UTC_APP_DIR:-/data/apps/ryd-utc-admin}"
JAR_NAME="${UTC_JAR:-ryd-utc-admin.jar}"
OUT="${OUT_DIR:-/tmp}/utc-runtime-${LABEL}.txt"

SUDO="sudo -n"
$SUDO true 2>/dev/null || SUDO=""

emit() { printf '%s=%s\n' "$1" "$2" >> "$OUT"; }

: > "$OUT"
emit probe_label "$LABEL"
emit probe_ts "$(date -Is)"
emit host "$(hostname)"

# ---- ① systemd 状态 ----
emit unit_is_active "$(systemctl is-active "$UNIT" 2>&1)"
emit unit_main_pid "$(systemctl show "$UNIT" -p MainPID --value 2>&1)"
emit unit_exec_start "$(systemctl show "$UNIT" -p ExecMainStartTimestamp --value 2>&1)"
emit unit_type "$(systemctl show "$UNIT" -p Type --value 2>&1)"
emit unit_pid_file "$(systemctl show "$UNIT" -p PIDFile --value 2>&1)"

# ---- ② 进程与端口 ----
MAIN_PID="$(systemctl show "$UNIT" -p MainPID --value 2>&1)"
emit port_listen_count "$($SUDO ss -ltn 2>/dev/null | grep -c ":${PORT} " || echo 0)"
LISTEN_PID="$($SUDO ss -ltnp 2>/dev/null | grep ":${PORT} " | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2)"
emit port_listen_pid "${LISTEN_PID:-none}"
if [ -n "${LISTEN_PID:-}" ] && [ "$LISTEN_PID" = "$MAIN_PID" ]; then
  emit probe_pid_match "YES"
else
  emit probe_pid_match "NO"
fi

# 进程实际命令行：确认 -Dspring.profiles.active=prod 没丢
# ★ 守卫用 $SUDO test -r，不用 shell 的 [ -r ]：实际读取走的是 sudo，
#   判据必须与实际读取能力一致。生产以非 root 的 runyd 登录，若该文件是 root-only，
#   [ -r ] 会误判 UNREADABLE（假阴性）。
# ★ 读取用 `$SUDO cat | tr`，不用 `$SUDO tr < /proc/...`：重定向由**当前 shell**
#   打开文件，sudo 对它无效。
if [ -n "$MAIN_PID" ] && [ "$MAIN_PID" != "0" ] && $SUDO test -r "/proc/$MAIN_PID/cmdline" 2>/dev/null; then
  CMDLINE="$($SUDO cat "/proc/$MAIN_PID/cmdline" 2>/dev/null | tr '\0' ' ')"
  # ★ CMDLINE 取空时下面两条会各自输出 MISSING，而 MISSING 与「真的没有该参数」
  #   无法区分。显式给出长度，让读的人能判断这个 MISSING 可不可采信。
  emit proc_cmdline_len "${#CMDLINE}"
  emit proc_cmdline_profile "$(printf '%s' "$CMDLINE" | grep -o 'spring.profiles.active=[a-z]*' || echo MISSING)"
  emit proc_cmdline_jar "$(printf '%s' "$CMDLINE" | grep -o '[A-Za-z0-9._-]*\.jar' | head -1 || echo MISSING)"
  emit proc_etimes_sec "$($SUDO ps -o etimes= -p "$MAIN_PID" 2>/dev/null | tr -d ' ' || echo NA)"
  emit proc_owner "$($SUDO ps -o user= -p "$MAIN_PID" 2>/dev/null | tr -d ' ' || echo NA)"
else
  emit proc_cmdline_profile "UNREADABLE"
fi

# ---- ③ 现役 jar 指纹 ----
JAR="${APP_DIR}/${JAR_NAME}"
if [ -r "$JAR" ] || $SUDO test -r "$JAR" 2>/dev/null; then
  emit jar_path "$JAR"
  emit jar_bytes "$($SUDO stat -c %s "$JAR" 2>/dev/null)"
  emit jar_mtime "$($SUDO stat -c %y "$JAR" 2>/dev/null)"
  emit jar_sha256 "$($SUDO sha256sum "$JAR" 2>/dev/null | cut -d' ' -f1)"
  emit jar_md5 "$($SUDO md5sum "$JAR" 2>/dev/null | cut -d' ' -f1)"

  # ---- ④ class 清单（产物级反证）----
  # ⚠ 关键：本工程是 Maven 多模块聚合，业务类几乎全在嵌套的
  #   BOOT-INF/lib/utc-{common,system,stock,mall,unicome,job}-*.jar 里，
  #   外层 BOOT-INF/classes/ 只有 utc-admin 自己的 49 个类。
  #   所以对外层 jar 做 `unzip -l | grep ClassName` 恒为 0，是**结构性假阴性**。
  #   必须先把内层 lib 解出来再列。判据同时保留「六个内层 lib 的字节数」——
  #   这是区分"没上线"与"实现有缺陷"的最快手法，且无需解包即可比对。
  TMPD="$(mktemp -d)"
  $SUDO cp "$JAR" "$TMPD/p.jar" 2>/dev/null && $SUDO chown "$(id -u):$(id -g)" "$TMPD/p.jar" 2>/dev/null
  if [ -r "$TMPD/p.jar" ]; then
    CLS_OUTER="$(unzip -l "$TMPD/p.jar" 'BOOT-INF/classes/*' 2>/dev/null | grep -c '\.class$')"
    emit class_count_outer_classes "${CLS_OUTER:-0}"

    # 六个内层 lib 的字节数指纹（换包后这六个数必须整体变化）
    INNER_FP="$(unzip -l "$TMPD/p.jar" 2>/dev/null | grep 'BOOT-INF/lib/utc-' \
                | awk '{printf "%s=%s;", $NF, $1}')"
    emit inner_lib_bytes "$INNER_FP"

    # 下钻内层 lib，检查 C 线关键类是否真的在包内（1=在，0=不在）
    mkdir -p "$TMPD/inner"
    ( cd "$TMPD/inner" && unzip -q -o "$TMPD/p.jar" 'BOOT-INF/lib/utc-*.jar' >/dev/null 2>&1 )
    for c in FlowAccountCancelListener FlowAccountRemoveTerminalListener CycleUpdatedHandler \
             FlowAccountEvent CacheInitRunner TerminalStatusListener; do
      HIT=0
      for j in "$TMPD"/inner/BOOT-INF/lib/utc-*.jar; do
        [ -e "$j" ] || continue
        N="$(unzip -l "$j" 2>/dev/null | grep -c "/${c}\.class")"
        HIT=$(( HIT + N ))
      done
      emit "cline_class_${c}" "$HIT"
    done
    emit inner_lib_files_seen "$(ls -1 "$TMPD"/inner/BOOT-INF/lib/ 2>/dev/null | wc -l | tr -d ' ')"
  else
    emit class_probe "SKIPPED_COPY_FAILED"
  fi
  rm -rf "$TMPD"
else
  emit jar_path "NOT_FOUND:${JAR}"
fi

# ---- ⑤⑥⑦ 日志判据 ----
# 实测目录形态：LOG_DIR 下还有一层同名子目录才是真正的 info/error 日志所在，
# 上一层只有 stdout.log(12GB+)/stderr.log/pid。故两级都要找。
LOG_DIR_GUESS="$($SUDO grep -h '^LOG_DIR=' "${APP_DIR}/custom.env" 2>/dev/null | cut -d= -f2)"
LOG_ROOT="${UTC_LOG_DIR:-${LOG_DIR_GUESS:-/data/logs/ryd-utc-admin}}"
emit log_root "$LOG_ROOT"
INFO_LOG="$($SUDO find "$LOG_ROOT" -maxdepth 2 -name '*info*.log' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
ERR_LOG="$($SUDO find "$LOG_ROOT" -maxdepth 2 -name '*error*.log' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
emit info_log "${INFO_LOG:-none}"
emit error_log "${ERR_LOG:-none}"

if [ -n "${INFO_LOG:-}" ]; then
  emit started_marker_count "$($SUDO grep -c 'Started UtcAdminApp in' "$INFO_LOG" 2>/dev/null)"
  emit started_last_line "$($SUDO grep 'Started UtcAdminApp in' "$INFO_LOG" 2>/dev/null | tail -1 | cut -c1-160)"
  emit active_profiles_line "$($SUDO grep -o 'profiles are active: [a-z]*' "$INFO_LOG" 2>/dev/null | tail -1)"
  emit info_log_lines "$($SUDO wc -l < "$INFO_LOG" 2>/dev/null | tr -d ' ')"
  emit info_log_last_ts "$($SUDO tail -1 "$INFO_LOG" 2>/dev/null | cut -c1-24)"
fi
if [ -n "${ERR_LOG:-}" ]; then
  # error 计数是「增长型」判据：before 记下基数，after 只允许按既有噪声速率增长，
  # 不得出现新的异常类型。绝对值本身无意义（本机 error 日志常年有 IoT 噪声：
  # 实测 2026-11-04 全天 2624 个事件，其中 CellSafetyClient 占 2420、
  # 单 01:00 一小时就爆发 2301）。
  emit error_total_lines "$($SUDO wc -l < "$ERR_LOG" 2>/dev/null | tr -d ' ')"
  emit error_exception_count "$($SUDO grep -c 'Exception' "$ERR_LOG" 2>/dev/null)"
  # ★ 正则必须要求至少一个前导字母：'[A-Za-z.]*Exception' 允许零长前缀，
  #   会从 undertow 堆栈里的 " Exception"、"(Exception" 这类文本里抽出一个
  #   裸的 "Exception" 伪类型。实测就因此误报了一次：换包后 distinct_types
  #   “新增 Exception”，实际是 8 次 GET /no/such/path 堆栈文本的假阳性。
  #   判“是否新增类型”请用 analyze-error-delta.sh（按时间切片 + 逐行归属）。
  emit error_distinct_types "$($SUDO grep -oE '[A-Za-z][A-Za-z0-9_.]*Exception' "$ERR_LOG" 2>/dev/null | sort -u | tr '\n' ',' | cut -c1-300)"
  emit error_last_line "$($SUDO tail -1 "$ERR_LOG" 2>/dev/null | cut -c1-160)"
fi

# ---- 磁盘余量（换包会新增一份备份 jar，约 108MB）----
emit disk_avail "$($SUDO df -h --output=avail "$APP_DIR" 2>/dev/null | tail -1 | tr -d ' ')"

# ---- 换包时机风险窗口 ----
# stdout.log 实测 12GB+，禁止 grep 全文件（会拖垮磁盘 IO 并污染 before/after 时序）。
# 只取 info 日志尾部若干行判断当下是否有定时任务在跑。
if [ -n "${INFO_LOG:-}" ]; then
  emit job_tail_hits "$($SUDO tail -2000 "$INFO_LOG" 2>/dev/null | grep -cE 'xxl-job|JobThread|CycleUpdated|FlowUpdated')"
  emit job_tail_last "$($SUDO tail -2000 "$INFO_LOG" 2>/dev/null | grep -oE 'xxl-job|JobThread|CycleUpdated|FlowUpdated' | tail -1)"
fi

echo "---- 运行态探针（${LABEL}）----"
cat "$OUT"
echo "---- 已写入 ${OUT} ----"
