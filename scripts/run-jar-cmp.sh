#!/bin/bash
# ============================================================================
# run-jar-cmp.sh — 薄封装：从 systemd unit 里解析出 jar 路径，再调 compare-jar-manifest.sh
#
# 为什么要有它：两台机器的 jar 路径不同（生产 /usr/local/ryd-unicard/bin/，
#   测试机另一个前缀），且解析过程含 $(...) 与竖线。按纪律不写内联 ssh
#   （PowerShell 会本地求值 $()、吃掉 awk 的 $N），一律落成脚本上传执行。
#
# 用法： bash run-jar-cmp.sh <unit名> [hash|dump]
#   例： bash run-jar-cmp.sh ryd-unicard-official hash
#        bash run-jar-cmp.sh unicard-test-threeants-official hash
# 安全边界：只读。不改 unit、不解包、不落盘 jar 内容。
# 依赖： sudo、systemctl、compare-jar-manifest.sh（同目录）
# ============================================================================
set -uo pipefail

UNIT="${1:-}"
MODE="${2:-hash}"
[ -n "$UNIT" ] || { echo "用法: bash run-jar-cmp.sh <unit名> [hash|dump]" >&2; exit 2; }

HERE="$(cd "$(dirname "$0")" && pwd)"

SUDO="sudo -n"
$SUDO true 2>/dev/null || SUDO=""

# ★ 不要用 `systemctl show -p KEY --value`：生产机 systemd 版本较老，实测报
#   `systemctl: unrecognized option '--value'`，会静默取到空值。
#   （同一个坑 probe-threeants-config.sh 里早已写过注释，此处曾重复踩。）
#   统一用 -p KEY 再 cut，两台机器都能工作。
sysd() { $SUDO systemctl show "$UNIT" -p "$1" 2>/dev/null | cut -d= -f2-; }

echo "==== unit 侧取证 ===="
echo "host          = $(hostname)"
echo "unit          = ${UNIT}"
echo "unit_is_active= $($SUDO systemctl is-active "$UNIT" 2>/dev/null)"
echo "unit_main_pid = $(sysd MainPID)"

# 从 /proc/<pid>/cmdline 取 jar 路径：NUL 分隔，找出以 .jar 结尾的那个参数。
# 用 cmdline 而不是 ExecStart 原文，是因为 cmdline 是**运行期真实生效**的路径，
# 万一 unit 里写了变量或有多行 ExecStart，cmdline 不会骗人。
# ★ 不能用 `< /proc/$PID/cmdline` 重定向：重定向是由**当前 shell**（生产上是
#   非 root 的 runyd）打开文件的，$SUDO 对它无效。root 进程的 cmdline 若对
#   普通用户受限就会读到空。必须让 sudo 自己去读（cat），再从管道出来。
PID="$(sysd MainPID)"
JAR=""
if [ -n "${PID:-}" ] && [ "$PID" != "0" ]; then
  JAR="$($SUDO cat "/proc/$PID/cmdline" 2>/dev/null | tr '\0' '\n' | grep -E '\.jar$' | head -1)"
  [ -n "$JAR" ] || echo "note          = /proc/$PID/cmdline 取不到 jar，退回 ExecStart 解析"
fi

# 兜底：进程读不到时退回 unit 文件的 ExecStart
if [ -z "$JAR" ]; then
  JAR="$($SUDO systemctl cat "$UNIT" 2>/dev/null \
         | grep -E '^[[:space:]]*ExecStart=' \
         | grep -oE '[^[:space:]"]+\.jar' | head -1)"
fi

if [ -z "$JAR" ]; then
  echo "FATAL: 解析不出 jar 路径。0 命中不可当作「两边相同」，禁止据此下结论。" >&2
  exit 5
fi

# ★ jar 可能是**相对路径**（实测测试机就是 bin/unicard-official-1.0.0.jar，
#   靠 unit 的 WorkingDirectory 解析）。相对路径直接 -r 测试必然失败，
#   必须用 WorkingDirectory 拼成绝对路径。生产是绝对路径，拼接对其无副作用。
case "$JAR" in
  /*) : ;;
  *)  WD="$(sysd WorkingDirectory)"
      if [ -z "$WD" ] || [ "$WD" = "/" ]; then
        echo "FATAL: jar 是相对路径 ($JAR) 但 unit 无 WorkingDirectory，无法定位。" >&2
        exit 6
      fi
      JAR="${WD%/}/$JAR"
      echo "note          = 相对路径已用 WorkingDirectory 拼接"
      ;;
esac

echo "jar_resolved  = ${JAR}"
# ★ 用 $SUDO test -r 而不是 shell 的 [ -r ]：生产上以非 root 的 runyd 登录，
#   而实际读取（sha256sum/unzip）走的是 sudo。用当前用户的权限去测会得到
#   「读不到」的假阴性，判据必须与实际读取能力一致。
$SUDO test -r "$JAR" || { echo "FATAL: jar 不可读（已用 sudo 测）: $JAR" >&2; exit 3; }

echo ""
bash "$HERE/compare-jar-manifest.sh" "$JAR" "$MODE"
