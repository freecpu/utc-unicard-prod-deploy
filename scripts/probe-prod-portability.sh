#!/bin/bash
# ============================================================================
# probe-prod-portability.sh — 只读探测：把测试机上验过的脚本搬到生产前，
#                            先确认生产环境的三个移植性前提
#
# 为什么需要它（2026-11-05 实测触发）：
#   在生产上跑 run-jar-cmp.sh 时发现 `systemctl show -p MainPID --value` 报
#   `systemctl: unrecognized option '--value'` —— 生产 systemd 版本比测试机老。
#   同一个坑我在 probe-threeants-config.sh 里早就写过注释，却又踩了一次。
#   结论：**凡是用了新 systemd 语法或依赖 root 权限读 /proc 的判据，搬到生产
#   之前必须逐条实测**，否则会静默取空值 → 判定退化成假阴性。
#
# 本脚本要回答的三件事：
#   ① systemd 版本；`--value` 与 `NRestarts` 这两个新特性在不在
#   ② 以当前登录用户（生产是非 root 的 runyd）能不能读 root 进程的
#      /proc/<pid>/cmdline —— verify-d-injection.sh 用它取 cmdline_has_agent_flow_D，
#      读不到就会假阴性报 0
#   ③ 单元的 Restart 策略（生产是 Restart=always + RestartUSec=100ms +
#      StartLimitBurst=5，注入错值会疯狂重启并停在 failed，回滚必须含 reset-failed）
#
# 安全边界：**全程只读**。不改 unit、不重启任何服务。
#           **完全不打印 cmdline 正文**（正文里可能含 -D 传入的值），
#           只打印 systemd 属性、文件权限位、以及 cmdline 里指定 -D 键的命中计数。
# 用法： bash probe-prod-portability.sh <unit名>
# 依赖： systemctl、ls、cat、sudo（可选）
# ============================================================================
set -uo pipefail

UNIT="${1:-ryd-unicard-official}"

SUDO="sudo -n"
$SUDO true 2>/dev/null || SUDO=""

echo "==== 环境 ===="
echo "host            = $(hostname)"
echo "login_user      = $(id -un)  (uid=$(id -u))"
echo "sudo_available  = $([ -n "$SUDO" ] && echo yes || echo no)"
echo "systemd_version = $(systemctl --version 2>&1 | head -1)"

echo ""
echo "==== ① 新特性可用性（不可用时必须退回 -p KEY | cut -d= -f2）===="
V="$($SUDO systemctl show "$UNIT" -p MainPID --value 2>&1)"
case "$V" in
  *unrecognized*|*Unknown*) echo "show_--value      = UNSUPPORTED（生产须用 cut -d= -f2）" ;;
  '')                       echo "show_--value      = EMPTY（同样不可用）" ;;
  *)                        echo "show_--value      = SUPPORTED (MainPID=$V)" ;;
esac
V2="$($SUDO systemctl show "$UNIT" -p MainPID 2>&1 | cut -d= -f2)"
echo "MainPID(cut法)    = ${V2}"
NR="$($SUDO systemctl show "$UNIT" -p NRestarts 2>&1)"
if [ -z "$NR" ]; then
  echo "NRestarts         = ABSENT（此 systemd 无该属性，脚本里此项会为空，属信息缺失非假阴性）"
else
  echo "NRestarts         = ${NR}"
fi

echo ""
echo "==== ② 以当前用户读 root 进程 /proc/<pid>/cmdline 的能力 ===="
PID="$V2"
if [ -z "$PID" ] || [ "$PID" = "0" ]; then
  echo "FATAL: 取不到 MainPID，无法判断。0/空不可当作「读得到」。" >&2
  exit 5
fi
echo "target_pid        = ${PID}"
echo "proc_owner        = $($SUDO stat -c '%U' "/proc/$PID" 2>&1)"
echo "cmdline_perm      = $(ls -l "/proc/$PID/cmdline" 2>&1 | awk '{print $1, $3, $4}')"
# 不带 sudo 直接读，看当前用户到底能不能读到
NOSUDO_LEN="$(cat "/proc/$PID/cmdline" 2>/dev/null | wc -c | tr -d ' ')"
SUDO_LEN="$($SUDO cat "/proc/$PID/cmdline" 2>/dev/null | wc -c | tr -d ' ')"
echo "read_len_nosudo   = ${NOSUDO_LEN:-0}"
echo "read_len_sudo     = ${SUDO_LEN:-0}"
if [ "${NOSUDO_LEN:-0}" = "0" ] && [ "${SUDO_LEN:-0}" != "0" ]; then
  echo "VERDICT           = MUST_USE_SUDO  ★ 关键结论"
  echo "  → 形如 \`sudo tr '\\0' ' ' < /proc/PID/cmdline\` 的写法在生产上会取到空值："
  echo "    重定向由**当前 shell**（非 root）打开文件，sudo 对它无效。"
  echo "    必须改成 \`sudo cat /proc/PID/cmdline | tr '\\0' ' '\`。"
  echo "    否则 cmdline_has_agent_flow_D 会假阴性报 0，POS 判定不可信。"
elif [ "${NOSUDO_LEN:-0}" != "0" ]; then
  echo "VERDICT           = READABLE_WITHOUT_SUDO（两种写法都能工作）"
else
  echo "VERDICT           = FATAL 两种都读不到，需人工排查" >&2
  exit 6
fi
# 只报布尔计数，不打印正文（避免把 -D 里的值/凭据带进证据文件）
echo "cmdline_len_used  = $([ "${SUDO_LEN:-0}" != "0" ] && echo "$SUDO_LEN" || echo "$NOSUDO_LEN")"
echo "has_agent_flow_D  = $($SUDO cat "/proc/$PID/cmdline" 2>/dev/null | tr '\0' '\n' | grep -c 'utc.agent-flow')"

echo ""
echo "==== ③ 重启策略（决定注入错值后的失败形态与回滚步骤）===="
for k in Type Restart RestartUSec StartLimitBurst StartLimitIntervalUSec ExecMainStartTimestamp; do
  val="$($SUDO systemctl show "$UNIT" -p "$k" 2>&1 | cut -d= -f2-)"
  printf '%-24s= %s\n' "$k" "${val:-<ABSENT>}"
done
echo ""
echo "  ★ 若 Restart=always 且 RestartUSec 很小：注入无法绑定的值会让单元以该间隔"
echo "    疯狂重启，迅速撞 StartLimitBurst 变成 failed 并**停在那里**，"
echo "    回滚后必须额外执行 systemctl reset-failed 才能重新拉起。"

echo ""
echo "==== 结论汇总（供 SOP 引用）===="
echo "unit              = ${UNIT}"
echo "is_active         = $($SUDO systemctl is-active "$UNIT" 2>&1)"
echo "PROBE_DONE"
