#!/bin/bash
# ============================================================================
# compare-jar-class.sh — 比对两个 jar 内指定 class 的 sha256，判断是否同一份代码
#
# 为什么需要它（2026-11-05 实测触发）：
#   生产与测试机的 unicard-official-1.0.0.jar **字节数完全相同（93,135,977）
#   但整包 sha256 不同**。同尺寸不同哈希，最可能是同一份源码两次构建
#   （ZIP 逐条目时间戳不同、而时间戳字段定宽，故总尺寸不变），
#   但也可能是等长的不同代码。
#
#   整包哈希在这里没有判别力，必须下沉到 class 级别：
#   测试机上验出的「-Dutc.agent-flow-coefficient 能绑定到 UtcProperties 的
#   Integer 字段」这个结论，只有在**生产 jar 里的 UtcProperties.class 与测试机
#   逐字节相同**时才能外推到生产。否则就是拿 A 的证据给 B 背书。
#
# 做法：只解出目标 class 到临时目录，算 sha256，立即清理。不解整包。
#
# 安全边界：只读。不打印任何配置值；class 文件只算哈希，不反编译、不外传。
# 用法： bash compare-jar-class.sh <jar路径> [class通配，默认 UtcProperties.class]
# 依赖： sudo、unzip、sha256sum
# ============================================================================
set -uo pipefail

JAR="${1:-}"
PAT="${2:-UtcProperties.class}"
[ -n "$JAR" ] || { echo "用法: bash compare-jar-class.sh <jar路径> [class通配]" >&2; exit 2; }
[ -r "$JAR" ] || { echo "FATAL: 读不到 $JAR" >&2; exit 3; }

SUDO="sudo -n"
$SUDO true 2>/dev/null || SUDO=""
command -v unzip >/dev/null 2>&1 || { echo "FATAL: 本机无 unzip" >&2; exit 4; }

WORK="/tmp/jarclass.$$"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK"

echo "==== jar 整体指纹 ===="
echo "jar_path = $JAR"
$SUDO sha256sum "$JAR" | cut -d' ' -f1 | sed 's/^/jar_sha256 = /'
$SUDO stat -c 'jar_bytes = %s   jar_mtime = %y' "$JAR"

echo ""
echo "==== 包内匹配 ${PAT} 的条目 ===="
# 先列条目，确认到底匹配到几个（0 个就必须报出来，不能静默当成"相同"）
$SUDO unzip -l "$JAR" "*${PAT}" 2>/dev/null | awk 'NR>3 && $4 != "" {print $1"\t"$4}' | head -10
N="$($SUDO unzip -l "$JAR" "*${PAT}" 2>/dev/null | awk 'NR>3 && $4 != "" {c++} END{print c+0}')"
echo "matched_entries = ${N}"
if [ "${N:-0}" = "0" ]; then
  echo "FATAL: 包内没有匹配 ${PAT} 的条目。0 命中**不可**当作「两边相同」，"
  echo "       这只会让比对静默失效。请检查 class 名或 jar 是否为同一模块。" >&2
  exit 5
fi

echo ""
echo "==== 逐条目 sha256（解到临时目录，退出即清理）===="
$SUDO unzip -o -q "$JAR" "*${PAT}" -d "$WORK" >/dev/null 2>&1
$SUDO chown -R "$(id -u):$(id -g)" "$WORK" 2>/dev/null
find "$WORK" -type f -name '*.class' -printf '%P\n' 2>/dev/null | sort | while IFS= read -r rel; do
  sz="$(stat -c '%s' "$WORK/$rel")"
  h="$(sha256sum "$WORK/$rel" | cut -d' ' -f1)"
  printf 'class_path = %s\nclass_bytes = %s\nclass_sha256 = %s\n' "$rel" "$sz" "$h"
done

echo ""
echo "==== 判读方法 ===="
echo "  在两台机器各跑一次本脚本，比对 class_sha256："
echo "    相同 → 该 class 逐字节一致，测试机上关于它的结论可外推到生产"
echo "    不同 → 不可外推，必须在生产自身重新验证（且需相应授权）"
echo "  注意：jar_sha256 不同但 class_sha256 相同，是「同源两次构建」的正常表现，"
echo "        差异来自 ZIP 条目时间戳，不来自代码。"
