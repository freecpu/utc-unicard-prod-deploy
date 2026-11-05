#!/bin/bash
# ============================================================================
# inspect-jar-manifest.sh — 检查清单是否**真有判别力**
#
# 为什么需要它：compare-jar-manifest.sh 的空清单 FATAL 只挡住「0 条目」。
#   但实测测试机 fat jar 只得 291 条目，对 93MB 的包偏少。若 awk 的列判定把
#   BOOT-INF/lib/ 下的模块 jar 过滤掉了，那么两边哈希相同也**不能**说明代码相同
#   —— 这是比空清单更隐蔽的假阳性。所以必须先看清单构成。
#
#   关键判据：BOOT-INF/lib/ 的条目数必须 > 0，且能看到 unicard-*.jar
#   （UtcProperties 就在其中某个模块 jar 里，这是本次比对真正关心的对象）。
#
# 用法： bash inspect-jar-manifest.sh <清单文件>
# 安全边界：只读。清单里只有长度/CRC/条目名，不含配置值与凭据。
# ============================================================================
set -uo pipefail

F="${1:-}"
[ -n "$F" ] && [ -r "$F" ] || { echo "用法: bash inspect-jar-manifest.sh <清单文件>" >&2; exit 2; }

total="$(wc -l < "$F" | tr -d ' ')"
cls="$(grep -c 'BOOT-INF/classes/' "$F")"
lib="$(grep -c 'BOOT-INF/lib/' "$F")"
meta="$(grep -c 'META-INF/' "$F")"
dirs="$(awk '$3 ~ /\/$/ {c++} END{print c+0}' "$F")"

echo "==== 清单构成 ===="
echo "manifest_file        = $F"
echo "total_entries        = $total"
echo "bootinf_classes      = $cls"
echo "bootinf_lib          = $lib"
echo "meta_inf             = $meta"
echo "directory_entries    = $dirs"
echo "file_entries         = $((total - dirs))"

echo ""
echo "==== BOOT-INF/lib/ 下的自有模块 jar（本次比对真正关心的对象）===="
# ★ 不能写 `grep ... | sort || echo 无命中`：|| 只绑到最后一个命令 sort，
#   而 sort 恒成功，所以「无命中」永远打不出来 —— 空段落会被误读成「脚本漏跑」。
OWN="$(grep -o 'BOOT-INF/lib/[^ ]*' "$F" | grep -Ei 'unicard|ryd|utc' | sort)"
if [ -n "$OWN" ]; then printf '%s\n' "$OWN"; else echo "（无命中：lib 里没有自有模块 jar，判别力存疑）"; fi

echo ""
echo "==== 判别力判定 ===="
# ★ lib=0 就是致命的：说明清单没覆盖到模块 jar，两边哈希相同也不能下结论。
if [ "${lib:-0}" = "0" ]; then
  echo "MANIFEST_NO_POWER: BOOT-INF/lib/ 条目数为 0，清单未覆盖模块 jar。"
  echo "  这种情况下 manifest_sha256 相同**不能**证明代码相同（假阳性）。"
  echo "  需检查 unzip -v 的列格式是否被 awk 的 NR/NF/正则判定误过滤。"
  exit 7
fi
if [ "${total:-0}" -lt 50 ]; then
  echo "MANIFEST_SUSPECT: 条目数仅 $total，对 fat jar 偏少，需人工确认列解析是否漏条目。"
  exit 8
fi
# ★ 光有 BOOT-INF/lib/ 还不够：本次要比的是 UtcProperties，它在自有模块 jar 里。
#   若 lib 里全是第三方依赖、没有 unicard/ryd/utc 模块 jar，那么清单相同也只能
#   证明「依赖树相同」，证明不了自有代码相同。
if [ -z "$OWN" ]; then
  echo "MANIFEST_NO_POWER: BOOT-INF/lib/ 有 $lib 条目但没有自有模块 jar（unicard/ryd/utc）。"
  echo "  清单相同只能证明依赖树相同，**不能**证明自有代码相同。"
  exit 9
fi
echo "MANIFEST_HAS_POWER: 覆盖 $total 条目（含 $lib 个 BOOT-INF/lib/、$(printf '%s\n' "$OWN" | wc -l | tr -d ' ') 个自有模块 jar），比对结果可采信。"

echo ""
echo "==== 前 5 行样本（人工复核列对齐：长度 CRC 名字）===="
head -5 "$F"
