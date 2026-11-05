#!/bin/bash
# ============================================================================
# probe-threeants-config.sh — 生产 threeants (ryd-unicard-official) 配置源取证
#
# 为什么需要它：
#   要判定「某个 yml 是不是死文件」，不能只看它放在哪个目录，必须先看进程的
#   **完整启动命令行**里有没有 --spring.config.additional-location /
#   --spring.config.location 指向那个目录。若有，该目录下的 yml 就是活的，
#   重命名会直接改生产行为。本脚本把这条判定固化下来。
#
#   实测教训：测试机的 ExecStart 带 --spring.config.additional-location=file:./etc/，
#   所以测试机 etc/application-dev.yml 是活配置；若照搬到生产而不先查，
#   就会把「死文件」和「活文件」判反。
#
# 安全边界：只读。Environment 与 cmdline 里的 token/password 一律用 sed 抹成
#           REDACTED 后才输出，**任何凭据值都不落终端、不落文件**。
#
# 用法： bash probe-threeants-config.sh [label]
# 依赖： systemctl、sudo、sed、grep、ss
# ============================================================================
set -uo pipefail

LABEL="${1:-adhoc}"
UNIT="${TA_UNIT:-ryd-unicard-official}"
PORT="${TA_PORT:-7003}"
APP_DIR="${TA_APP_DIR:-/usr/local/ryd-unicard}"
OUT="${OUT_DIR:-/tmp}/threeants-config-${LABEL}.txt"

SUDO="sudo -n"
$SUDO true 2>/dev/null || SUDO=""

emit() { printf '%s=%s\n' "$1" "$2" >> "$OUT"; }

: > "$OUT"
emit probe_label "$LABEL"
emit probe_ts "$(date -Is)"
emit host "$(hostname)"
emit unit "$UNIT"

# ---- 进程与端口 ----
PID="$(systemctl show "$UNIT" -p MainPID 2>/dev/null | cut -d= -f2)"
emit unit_is_active "$(systemctl is-active "$UNIT" 2>&1)"
emit unit_main_pid "${PID:-none}"
# 注意：本机 systemd 版本较老，systemctl show 不支持 --value，
# 必须用 -p KEY 再 cut -d= -f2（照搬 UTC 机器上写的 --value 会直接报错）。
emit unit_exec_start "$(systemctl show "$UNIT" -p ExecMainStartTimestamp 2>/dev/null | cut -d= -f2-)"
emit unit_workdir "$(systemctl show "$UNIT" -p WorkingDirectory 2>/dev/null | cut -d= -f2)"
emit port_listen_pid "$($SUDO ss -ltnp 2>/dev/null | grep ":${PORT} " | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2)"

# ---- 完整启动命令行（脱敏后）----
if [ -n "${PID:-}" ] && [ "$PID" != "0" ]; then
  # ★ 不要用 `$SUDO tr ... < /proc/$PID/cmdline`：重定向由**当前 shell**打开文件，
  #   sudo 对它无效。生产以非 root 的 runyd 登录时，若该文件不是世界可读就会静默取空。
  #   （2026-11-05 实测生产该文件是 -r--r--r-- root root，两种写法都能工作，
  #    但判据必须与实际读取能力一致，不能依赖「碰巧世界可读」。）
  CMD="$($SUDO cat "/proc/$PID/cmdline" 2>/dev/null | tr '\0' ' ')"
  # ★★ 下面的 has_additional_location / has_config_location 都是**否定性判据**（期望 0）。
  #   CMD 取空时它们同样会是 0 —— 「读到 0」与「真的没有」无法区分，
  #   而「生产 threeants 无外置配置目录」这条结论正是建立在这些 0 上。
  #   所以必须先显式标记 CMD 是否真的读到了内容，否则 0 不可采信。
  emit proc_cmdline_len "${#CMD}"
  if [ -z "$CMD" ]; then
    # 只 emit 一次：再 emit 空值会把这一行覆盖掉，标记就白打了。
    emit proc_cmdline "FATAL_EMPTY_CMDLINE（读不到 /proc/$PID/cmdline，下面所有 0 计数均不可采信）"
  else
    SAFE="$(printf '%s' "$CMD" | sed -e 's/TOKEN=[^ ]*/TOKEN=REDACTED/g' -e 's/password=[^ ]*/password=REDACTED/g' -e 's/secret=[^ ]*/secret=REDACTED/g')"
    emit proc_cmdline "$SAFE"
  fi
  emit proc_etimes "$($SUDO ps -o etimes= -p "$PID" 2>/dev/null | tr -d ' ')"
  emit proc_owner "$($SUDO ps -o user= -p "$PID" 2>/dev/null | tr -d ' ')"

  # ---- 关键判定：有没有外置配置路径 ----
  emit has_additional_location "$(printf '%s' "$CMD" | grep -c 'spring.config.additional-location')"
  emit has_config_location "$(printf '%s' "$CMD" | grep -c 'spring.config.location')"
  emit additional_location_value "$(printf '%s' "$CMD" | grep -o 'spring.config.additional-location=[^ ]*' | head -1)"
  emit profile_arg "$(printf '%s' "$CMD" | grep -o -e 'spring.profiles.active=[A-Za-z]*' -e '\-\-spring.profiles.active=[A-Za-z]*' | head -1)"
  emit d_system_props "$(printf '%s' "$CMD" | grep -o '\-D[A-Za-z0-9._-]*' | tr '\n' ',')"
fi

# ---- systemd Environment（脱敏）----
emit unit_environment "$(systemctl show "$UNIT" -p Environment 2>/dev/null | sed -e 's/TOKEN=[^ ]*/TOKEN=REDACTED/g' -e 's/PASSWORD=[^ ]*/PASSWORD=REDACTED/g' -e 's/SECRET=[^ ]*/SECRET=REDACTED/g' | cut -c1-300)"

# ---- Spring Boot 默认搜索路径实况 ----
# 相对 WorkingDirectory 解析：file:./config/ 与 file:./ 两条。
WD="$(systemctl show "$UNIT" -p WorkingDirectory 2>/dev/null | cut -d= -f2)"
WD="${WD:-$APP_DIR}"
# ★ 用 $SUDO test -d 而不是 shell 的 [ -d ]：下面两条 find 走的是 sudo，
#   判据必须与实际读取能力一致。生产以非 root 的 runyd 登录时，
#   若目录不可由 runyd stat，[ -d ] 会误报 ABSENT —— 而「无外置配置目录」
#   正是本脚本要下的结论之一，误报 ABSENT 会变成假阳性支持。
emit search_path_config_dir "$($SUDO test -d "$WD/config" && echo EXISTS || echo ABSENT)"
emit search_path_toplevel_yml "$($SUDO find "$WD" -maxdepth 1 -name 'application*' 2>/dev/null | wc -l | tr -d ' ')"

# ---- 待判定的候选 yml 清单（含指纹，用于事后证明内容未变）----
emit candidate_yml_list "$($SUDO find "$APP_DIR" -maxdepth 3 -name 'application*.yml' -not -path '*/target/*' -printf '%p;%s;%TY-%Tm-%Td %TH:%TM\n' 2>/dev/null | tr '\n' '|')"

echo "---- threeants 配置源取证（${LABEL}）----"
cat "$OUT"
echo "---- 已写入 ${OUT} ----"
