#!/bin/bash
# ============================================================================
# probe-xxljob-admin.sh — xxl-job-admin（调度中心）只读基线采集
#
# 用途：为一个此前从未建档的部署单元建立第一份基线锚。
#   2026-11-23 之前本仓对它的全部认知只有三件事：在 /data/apps/xxl-job-admin、
#   监听 8082、PID 89942 自 2023-02-18 未重启。连 jar 的 sha256 都没有。
#
# 安全边界（★ 本脚本严格只读，且刻意「能看文件名，绝不看内容」）：
#   - 不 cat / 不 grep / 不 base64 任何配置文件与启动脚本的正文
#     （start.sh 含明文数据库口令；application.properties 可能含 accessToken。
#      只采 sha256 / 字节 / mtime / mode —— 指纹足以判「有没有被改过」）
#   - 不读 /proc/<pid>/environ（环境变量里就是 start.sh export 的口令）
#   - 不连数据库、不登录调度中心（无登录态，也不该有）
#   - cmdline 只提取白名单片段（-Xmx / jar 名 / -D 的**键名**），不输出整条命令行
#   - 日志只取计数、文件名、大小、固定英文标记与时间戳前缀，不输出日志正文
#   - 唯一写入＝/tmp 下的探针输出文件
#
# 用法： bash probe-xxljob-admin.sh [label]
# 依赖： sha256sum、ls、stat、ps、ss、df、readlink、find(GNU)、grep、awk；sudo 可选
# ============================================================================
set -uo pipefail

LABEL="${1:-adhoc}"
APP_DIR="${XXL_DIR:-/data/apps/xxl-job-admin}"
PORT="${XXL_PORT:-8082}"
CTX="${XXL_CTX:-/xxl-job-admin}"
OUT="${OUT_DIR:-/tmp}/xxljob-admin-${LABEL}.txt"

SUDO="sudo -n"
$SUDO true 2>/dev/null || SUDO=""

emit() { printf '%s=%s\n' "$1" "$2" >> "$OUT"; }
: > "$OUT"

emit probe_label "$LABEL"
emit probe_ts "$(date -Is)"
emit host "$(hostname)"
emit app_dir "$APP_DIR"

# ---------------------------------------------------------------------------
# ① 进程面（先定 PID，后面依赖它）
# ---------------------------------------------------------------------------
MAIN_PID="$($SUDO ss -ltnp 2>/dev/null | grep ":${PORT} " | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2)"
[ -n "${MAIN_PID:-}" ] || MAIN_PID="$($SUDO pgrep -f 'xxl-job-admin.*\.jar' 2>/dev/null | head -1)"
emit main_pid "${MAIN_PID:-none}"

PRIMARY_JAR=""
if [ -n "${MAIN_PID:-}" ]; then
  emit pid_user "$($SUDO ps -o user= -p "$MAIN_PID" 2>/dev/null | tr -d ' ')"
  ET="$($SUDO ps -o etimes= -p "$MAIN_PID" 2>/dev/null | tr -d ' ')"
  emit pid_etimes_sec "${ET:-NA}"
  [ -n "${ET:-}" ] && emit pid_uptime_days "$(( ET / 86400 ))"
  emit pid_lstart "$($SUDO ps -o lstart= -p "$MAIN_PID" 2>/dev/null | sed 's/  */ /g')"
  emit pid_ppid "$($SUDO ps -o ppid= -p "$MAIN_PID" 2>/dev/null | tr -d ' ')"
  emit pid_cwd "$($SUDO readlink "/proc/$MAIN_PID/cwd" 2>/dev/null)"

  # cmdline：只取白名单片段，绝不整条输出
  if $SUDO test -r "/proc/$MAIN_PID/cmdline" 2>/dev/null; then
    CMD="$($SUDO cat "/proc/$MAIN_PID/cmdline" 2>/dev/null | tr '\0' ' ')"
    emit cmdline_len "${#CMD}"
    emit cmdline_xmx "$(printf '%s' "$CMD" | grep -o '\-Xmx[0-9A-Za-z]*' | head -1)"
    emit cmdline_xms "$(printf '%s' "$CMD" | grep -o '\-Xms[0-9A-Za-z]*' | head -1)"
    emit cmdline_jar "$(printf '%s' "$CMD" | grep -o '[A-Za-z0-9._-]*\.jar' | head -1)"
    emit cmdline_dflag_keys "$(printf '%s' "$CMD" | grep -oE '\-D[A-Za-z0-9._]+=' | sed 's/=$//' | sort -u | tr '\n' ',')"
    PRIMARY_JAR="$(printf '%s' "$CMD" | grep -o '[A-Za-z0-9._-]*\.jar' | head -1)"
  else
    emit cmdline_len "UNREADABLE"
  fi
else
  emit pid_user "NO_PID"
fi

emit systemd_unit_hit "$(systemctl list-unit-files 2>/dev/null | grep -ci 'xxl')"

# ---------------------------------------------------------------------------
# ② 端口与只读 HTTP
# ---------------------------------------------------------------------------
emit port_listen_count "$($SUDO ss -ltn 2>/dev/null | grep -c ":${PORT} " || echo 0)"
emit port_bind_scope "$($SUDO ss -ltn 2>/dev/null | grep ":${PORT} " | awk '{print $4}' | head -1)"
emit http_toLogin_code "$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:${PORT}${CTX}/toLogin" 2>/dev/null)"

# ---------------------------------------------------------------------------
# ③ 产物面（只看指纹与清单）
# ---------------------------------------------------------------------------
if $SUDO test -d "$APP_DIR" 2>/dev/null; then
  emit app_dir_owner_mode "$($SUDO stat -c '%U:%G %a' "$APP_DIR" 2>/dev/null)"
  emit top_entries "$($SUDO ls -1a "$APP_DIR" 2>/dev/null | grep -v '^\.\{1,2\}$' | tr '\n' ',')"
  emit subdirs "$($SUDO find "$APP_DIR" -maxdepth 1 -mindepth 1 -type d -printf '%f,' 2>/dev/null)"
  emit jar_count "$($SUDO find "$APP_DIR" -maxdepth 1 -type f -name '*.jar' 2>/dev/null | wc -l | tr -d ' ')"
  emit jar_list "$($SUDO find "$APP_DIR" -maxdepth 1 -type f -name '*.jar' -printf '%f=%s,' 2>/dev/null)"

  [ -n "$PRIMARY_JAR" ] || PRIMARY_JAR="$($SUDO find "$APP_DIR" -maxdepth 1 -type f -name '*.jar' -printf '%s %f\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
  if [ -n "$PRIMARY_JAR" ] && $SUDO test -f "$APP_DIR/$PRIMARY_JAR" 2>/dev/null; then
    emit primary_jar "$PRIMARY_JAR"
    emit jar_bytes "$($SUDO stat -c %s "$APP_DIR/$PRIMARY_JAR" 2>/dev/null)"
    emit jar_mtime "$($SUDO stat -c %y "$APP_DIR/$PRIMARY_JAR" 2>/dev/null)"
    emit jar_sha256 "$($SUDO sha256sum "$APP_DIR/$PRIMARY_JAR" 2>/dev/null | cut -d' ' -f1)"
  else
    emit primary_jar "UNRESOLVED"
  fi

  # 启动脚本与配置文件：只登记指纹，正文一律不读
  for f in start.sh application.properties application.yml logback.xml; do
    if $SUDO test -f "$APP_DIR/$f" 2>/dev/null; then
      emit "meta_${f}_sha256" "$($SUDO sha256sum "$APP_DIR/$f" 2>/dev/null | cut -d' ' -f1)"
      emit "meta_${f}_bytes" "$($SUDO stat -c %s "$APP_DIR/$f" 2>/dev/null)"
      emit "meta_${f}_mode" "$($SUDO stat -c %a "$APP_DIR/$f" 2>/dev/null)"
      emit "meta_${f}_mtime" "$($SUDO stat -c %y "$APP_DIR/$f" 2>/dev/null)"
    fi
  done

  if $SUDO test -d "$APP_DIR/lib" 2>/dev/null; then
    emit lib_file_count "$($SUDO ls -1 "$APP_DIR/lib" 2>/dev/null | wc -l | tr -d ' ')"
    emit lib_total_bytes "$($SUDO du -sb "$APP_DIR/lib" 2>/dev/null | cut -f1)"
  fi
else
  emit app_dir_owner_mode "NOT_FOUND"
fi

# ---------------------------------------------------------------------------
# ④ 日志面（只取计数/文件名/大小/标记，不输出正文）
# ---------------------------------------------------------------------------
LOG_DIR=""
for d in "$APP_DIR/logs" "$APP_DIR/log"; do
  $SUDO test -d "$d" 2>/dev/null && { LOG_DIR="$d"; break; }
done
emit log_dir "${LOG_DIR:-NOT_FOUND}"

if [ -n "$LOG_DIR" ]; then
  emit log_top_count "$($SUDO ls -1 "$LOG_DIR" 2>/dev/null | wc -l | tr -d ' ')"
  emit log_top_entries "$($SUDO ls -1 "$LOG_DIR" 2>/dev/null | head -15 | tr '\n' ',')"
  emit log_top_total_bytes "$($SUDO find "$LOG_DIR" -maxdepth 1 -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END{printf "%d", s+0}')"
  emit log_file_count_m2 "$($SUDO find "$LOG_DIR" -maxdepth 2 -type f -name '*.log*' 2>/dev/null | wc -l | tr -d ' ')"
  emit logrotate_hits "$($SUDO ls -1 /etc/logrotate.d/ 2>/dev/null | grep -ci 'xxl' || true)"

  NEWEST="$($SUDO find "$LOG_DIR" -maxdepth 2 -type f -name '*.log*' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
  emit log_newest "${NEWEST:-none}"
  if [ -n "${NEWEST:-}" ]; then
    emit log_newest_bytes "$($SUDO stat -c %s "$NEWEST" 2>/dev/null)"
    emit log_newest_mtime "$($SUDO stat -c %y "$NEWEST" 2>/dev/null)"
    emit log_newest_lines "$($SUDO wc -l < "$NEWEST" 2>/dev/null | tr -d ' ')"
    emit log_last_ts_prefix "$($SUDO tail -1 "$NEWEST" 2>/dev/null | cut -c1-23)"
    emit log_tail_registry_hits "$($SUDO tail -3000 "$NEWEST" 2>/dev/null | grep -ci 'registry' || true)"
    emit log_tail_trigger_hits "$($SUDO tail -3000 "$NEWEST" 2>/dev/null | grep -ci 'trigger' || true)"
    emit log_tail_error_hits "$($SUDO tail -3000 "$NEWEST" 2>/dev/null | grep -c ' ERROR ' || true)"
  fi

  # 执行日志按天存放的目录（验证「单日执行日志 27 件」这类台账数据）
  JD_DIR="$($SUDO find "$LOG_DIR" -maxdepth 3 -type d -name 'jobhandler' 2>/dev/null | head -1)"
  emit jobhandler_dir "${JD_DIR:-none}"
  if [ -n "$JD_DIR" ]; then
    emit jobhandler_day_count "$($SUDO ls -1 "$JD_DIR" 2>/dev/null | wc -l | tr -d ' ')"
    emit jobhandler_newest_day "$($SUDO ls -1t "$JD_DIR" 2>/dev/null | head -1)"
    emit jobhandler_today_files "$($SUDO ls -1 "$JD_DIR/$(date +%Y-%m-%d)" 2>/dev/null | wc -l | tr -d ' ')"
  fi
fi

# ---------------------------------------------------------------------------
# ⑤ 磁盘与其他
# ---------------------------------------------------------------------------
emit mysql_client "$(command -v mysql 2>/dev/null || echo none)"
emit disk_avail "$($SUDO df -h --output=avail "$APP_DIR" 2>/dev/null | tail -1 | tr -d ' ')"
emit disk_use_pct "$($SUDO df -h --output=pcent "$APP_DIR" 2>/dev/null | tail -1 | tr -d ' ')"
emit large_files_m2 "$($SUDO find "$APP_DIR" -maxdepth 2 -type f -size +50M -printf '%f=%s,' 2>/dev/null | head -c 400)"

echo "---- xxl-job-admin 只读基线（${LABEL}）----"
cat "$OUT"
echo "---- 已写入 ${OUT} ----"
