#!/bin/bash
# ============================================================================
# compare-jar-manifest.sh — 用 (长度, CRC-32, 条目名) 全清单比对两个 jar 是否同码
#
# 为什么需要它（2026-11-05 实测触发）：
#   生产与测试机的 unicard-official-1.0.0.jar **字节数完全相同（93,135,977）
#   但整包 sha256 不同**：
#     生产   bd24267b…2b05   mtime 2026-10-28 00:58
#     测试机 56fcc758…afba   mtime 2026-10-24 23:48
#   同尺寸不同哈希，最可能是同源两次构建（ZIP 逐条目时间戳不同、时间戳字段定宽
#   故总尺寸不变），但也可能是等长的不同代码。**整包哈希在此没有判别力。**
#
#   为什么不能只比某个 class：UtcProperties 在 BOOT-INF/lib/ 下的嵌套模块 jar 里，
#   fat jar 外层 unzip 看不到（实测 matched_entries=0）。要解嵌套 jar 再解 class，
#   步骤多、易错，而且只覆盖一个类。
#
#   改用全清单比对：ZIP 每个条目都自带 CRC-32，覆盖条目内容。
#   把 (长度, CRC-32, 条目名) 排序后整体算 sha256 —— 时间戳不参与，
#   所以「同源两次构建」会得到**相同**的清单哈希，而任何代码差异都会暴露，
#   并且能精确指出是哪几个条目不同。一次比对覆盖全部 4 万+ 条目，比逐类比对更强。
#
# 安全边界：只读。不解包、不落盘任何 jar 内容；清单里只有长度/CRC/条目名，
#           不含配置值与凭据。临时文件退出即清理。
#
# 用法： bash compare-jar-manifest.sh <jar路径>          # 打印清单哈希
#        bash compare-jar-manifest.sh <jar路径> dump      # 另存完整清单到 /tmp 供 diff
# 依赖： sudo、unzip、sha256sum、awk、sort
# ============================================================================
set -uo pipefail

JAR="${1:-}"
MODE="${2:-hash}"
[ -n "$JAR" ] || { echo "用法: bash compare-jar-manifest.sh <jar路径> [hash|dump]" >&2; exit 2; }
command -v unzip >/dev/null 2>&1 || { echo "FATAL: 本机无 unzip" >&2; exit 4; }

SUDO="sudo -n"
$SUDO true 2>/dev/null || SUDO=""

# ★ 用 $SUDO test -r 而不是 shell 的 [ -r ]：生产上以非 root 的 runyd 登录，
#   而实际读取（sha256sum/unzip）走的是 sudo。用当前用户的权限去测会得到
#   「读不到」的假阴性，判据必须与实际读取能力一致。
$SUDO test -r "$JAR" || { echo "FATAL: 读不到（已用 sudo 测） $JAR" >&2; exit 3; }

WORK="/tmp/jarmfst.$$"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK"

echo "==== jar 整体指纹 ===="
echo "jar_path   = $JAR"
echo "jar_sha256 = $($SUDO sha256sum "$JAR" | cut -d' ' -f1)"
$SUDO stat -c 'jar_bytes  = %s   jar_mtime = %y' "$JAR"

# unzip -v 列格式： Length Method Size Cmpr Date Time CRC-32 Name
# → $1=长度  $7=CRC-32  $8..=条目名（名字理论上可含空格，故取 $8 到行尾）
# 前 3 行是表头（Archive: / 列名 / 分隔线），末尾 2 行是合计与分隔线，都要剔掉。
$SUDO unzip -v "$JAR" 2>/dev/null \
  | awk 'NR>3 && NF>=8 && $1 ~ /^[0-9]+$/ && $7 ~ /^[0-9a-fA-F]+$/ {
           name=$8; for(i=9;i<=NF;i++) name=name" "$i;
           printf "%s %s %s\n", $1, $7, name
         }' \
  | LC_ALL=C sort > "$WORK/manifest.txt"

N="$(wc -l < "$WORK/manifest.txt" | tr -d ' ')"
H="$(sha256sum "$WORK/manifest.txt" | cut -d' ' -f1)"

echo ""
echo "==== 条目清单指纹（不含时间戳，故同源两次构建应当相同）===="
echo "entry_count      = ${N}"
echo "manifest_sha256  = ${H}"

# ★ 0 条目必须报出来：unzip 失败/格式变化时会得到空清单，
#   两边都是空清单 → 哈希相同 → 会误判成「同一个 jar」。这是典型假阳性。
if [ "${N:-0}" = "0" ]; then
  echo "FATAL: 清单为空。可能是 unzip 版本输出格式不同或 jar 不可读。" >&2
  echo "       空清单比对会得出「两边相同」的**假阳性**，禁止据此下结论。" >&2
  exit 5
fi

echo ""
echo "==== 判读方法 ===="
echo "  两台机器各跑一次，比 manifest_sha256："
echo "    相同 → 全部 ${N} 个条目的长度与 CRC-32 逐条一致 → 同一份代码，"
echo "           测试机上的验证结论可外推到生产（jar_sha256 不同只来自时间戳）"
echo "    不同 → 不可外推。用 dump 模式各存一份清单，再 diff 定位到具体条目"

if [ "$MODE" = "dump" ]; then
  OUT="/tmp/jar-manifest-$(basename "$JAR").txt"
  cp "$WORK/manifest.txt" "$OUT"
  echo ""
  echo "已存完整清单： ${OUT}（${N} 行）"
fi
