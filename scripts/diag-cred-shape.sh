#!/bin/bash
# ============================================================================
# diag-cred-shape.sh — 诊断 audit-tmp-creds.sh 的命中到底是真凭据还是误报
#
# 背景：audit 报出 60 处 "HARDCODED"，但 value_len 全是 1 或 2，
#       与真实密码长度不符，怀疑是引号/占位符导致的误报。
#       误报与真凭据的处置完全不同（前者只需改工具，后者须立刻清理并轮换），
#       所以必须看清命中处的**形状**再决定。
#
# 安全边界：只读。值一律掩成 <MASKED>，另用 od 只报首字符的 ASCII 码，
#           **任何凭据值都不会出现在输出里**。
#
# 用法： bash diag-cred-shape.sh [目录，默认 /tmp] [最多看几个文件，默认 6]
#        audit 报 ACTION_REQUIRED 时用它安全地看命中上下文（值已掩码）
# ============================================================================
set -uo pipefail

DIR="${1:-/tmp}"
LIMIT="${2:-6}"

PAT='(^|[^A-Za-z0-9])(password|passwd|pwd|pw|secret|token|appkey|appid|accesskey)[[:space:]]*[:=]'
MASK='s/((password|passwd|pwd|pw|secret|token|appkey|appid|accesskey)[[:space:]]*[:=][[:space:]]*)[^[:space:]]*/\1<MASKED>/Ig'

SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"
FILES="$(grep -rlEi "$PAT" "$DIR" 2>/dev/null | grep -vxF "$SELF" | head -"$LIMIT")"
[ -n "$FILES" ] || { echo "${DIR} 下无命中文件"; exit 0; }

while IFS= read -r F; do
  [ -f "$F" ] || continue
  echo "==== $F ===="
  echo "-- 命中行（值已掩码，最多 3 行）--"
  grep -nEi "$PAT" "$F" 2>/dev/null | sed -E "$MASK" | head -3
  echo "-- 命中处值的形状（长度 + 首字符 ASCII 码，不输出值）--"
  grep -ohEi "${PAT}[[:space:]]*[^[:space:]]*" "$F" 2>/dev/null \
    | sed -E 's/^.*[:=][[:space:]]*//' | head -3 \
    | while IFS= read -r v; do
        ord="$(printf '%s' "$v" | head -c1 | od -An -tu1 | tr -d ' ')"
        printf '   value_len=%s first_char_ord=%s\n' "${#v}" "${ord:-none}"
      done
  echo ""
done <<< "$FILES"

echo "==== 首字符 ASCII 码对照（便于判读，不含任何真实值）===="
echo "  34=双引号  39=单引号  36=\$ 变量  45=连字符  46=句点  61=等号  91=左方括号  123=左花括号"
