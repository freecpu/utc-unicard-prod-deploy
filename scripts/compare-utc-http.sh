#!/bin/bash
# ============================================================================
# compare-utc-http.sh — 换包前后 HTTP 基线对照，输出 PASS/FAIL
#
# 为什么需要它（不要退回「人眼看 diff」）：
#   probe-utc-http.sh 的输出里，sha256 列是响应体**原文**指纹。H10/H12 的错误页
#   体内嵌 ISO-8601 时间串，每次调用必变，所以直接 diff 两份基线**恒定会报 2 行
#   差异**。人眼看 diff 时很容易把「预期内的 2 行」和「真的坏了 1 行」混在一起，
#   也容易在 12 行里漏看某一列。本脚本把判定固化成规则并给出单一结论。
#
# 判定规则（逐列，缺一即 FAIL）：
#   ① 两份文件的探针行数都必须为 12
#   ② 探针 id 集合必须完全一致（防止某条探针静默消失）
#   ③ 对每条探针，比较 http / bytes / sha_norm / code / message / datalen / shape
#      七列（即除 sha256 原文列外的全部列），必须逐字相同
#   ④ sha256 原文列不参与判定，但差异条数会被报告出来——
#      只允许出现在 H10/H12 这两条已知含时间戳的探针上，出现在别处即 FAIL
#
# 安全边界：只读两个本地文本文件，不联网、不连生产。
#           输出不含任何业务数据（基线文件本身就只有计数与指纹）。
#
# 用法： bash compare-utc-http.sh <before.txt> <after.txt>
# 退出码： 0=PASS  1=FAIL  2=用法/文件错误
# ============================================================================
set -uo pipefail

B="${1:-}"
A="${2:-}"
if [ -z "$B" ] || [ -z "$A" ] || [ ! -r "$B" ] || [ ! -r "$A" ]; then
  echo "用法: bash compare-utc-http.sh <before.txt> <after.txt>" >&2
  exit 2
fi

# 已知「原文 sha 每次必变」的探针白名单：错误页含 timestamp。
# 若将来新增含时间戳/随机数的端点，必须显式加进这里，否则会误报 FAIL。
TIMESTAMP_VOLATILE="H10 H12"

FAIL=0
note() { printf '%s\n' "$*"; }
bad()  { printf 'FAIL: %s\n' "$*"; FAIL=1; }

note "==== compare-utc-http ===="
note "before = $B"
note "after  = $A"
note "volatile_whitelist = ${TIMESTAMP_VOLATILE}"
note ""

# ---- ① 行数 ----
NB="$(grep -c '^H' "$B")"
NA="$(grep -c '^H' "$A")"
note "probe_count: before=${NB} after=${NA} (expect 12/12)"
[ "$NB" -eq 12 ] || bad "before 探针数 ${NB} != 12"
[ "$NA" -eq 12 ] || bad "after  探针数 ${NA} != 12"

# ---- ② id 集合 ----
IDS_B="$(awk -F'\t' '/^H/{print $1}' "$B" | sort | tr '\n' ' ')"
IDS_A="$(awk -F'\t' '/^H/{print $1}' "$A" | sort | tr '\n' ' ')"
if [ "$IDS_B" != "$IDS_A" ]; then
  bad "探针 id 集合不一致: before=[${IDS_B}] after=[${IDS_A}]"
else
  note "probe_id_set: MATCH (${IDS_B})"
fi
note ""

# ---- ③④ 逐条逐列比较 ----
# 列序：1=id 2=http 3=bytes 4=sha256 5=sha_norm 6=code 7=message 8=datalen 9=shape
# 参与判定的列：2,3,5,6,7,8,9（跳过 4=原文 sha）
COLNAMES="_ http bytes sha256 sha_norm code message datalen shape"
note "id      verdict  differing_columns"
for id in $(awk -F'\t' '/^H/{print $1}' "$B" | sort); do
  LB="$(awk -F'\t' -v k="$id" '$1==k' "$B" | head -1)"
  LA="$(awk -F'\t' -v k="$id" '$1==k' "$A" | head -1)"
  if [ -z "$LA" ]; then
    bad "${id} 在 after 中缺失"
    printf '%s\tMISSING\t-\n' "$id"
    continue
  fi

  DIFFCOLS=""
  i=0
  for cn in $COLNAMES; do
    i=$(( i + 1 ))
    [ "$i" -eq 1 ] && continue                     # id 本身
    [ "$i" -eq 4 ] && continue                     # 原文 sha256 不参与判定
    vb="$(printf '%s' "$LB" | cut -f"$i")"
    va="$(printf '%s' "$LA" | cut -f"$i")"
    if [ "$vb" != "$va" ]; then
      DIFFCOLS="${DIFFCOLS}${cn}(${vb}=>${va}) "
    fi
  done

  # 原文 sha 列单独看
  RAW_B="$(printf '%s' "$LB" | cut -f4)"
  RAW_A="$(printf '%s' "$LA" | cut -f4)"
  RAW_DIFF="no"
  [ "$RAW_B" != "$RAW_A" ] && RAW_DIFF="yes"

  VOLATILE="no"
  for v in $TIMESTAMP_VOLATILE; do [ "$v" = "$id" ] && VOLATILE="yes"; done

  if [ -z "$DIFFCOLS" ]; then
    if [ "$RAW_DIFF" = "yes" ]; then
      if [ "$VOLATILE" = "yes" ]; then
        printf '%s\tPASS\t(sha256_raw_differs_expected_timestamp)\n' "$id"
      else
        bad "${id} 七列全同但原文 sha 变了，且不在时间戳白名单里 —— 说明归一化规则不完整（有未识别的可变字段），不得当 PASS"
        printf '%s\tSUSPECT\tsha256_raw_differs_not_whitelisted\n' "$id"
      fi
    else
      printf '%s\tPASS\t-\n' "$id"
    fi
  else
    bad "${id} 列不一致: ${DIFFCOLS}"
    printf '%s\tFAIL\t%s\n' "$id" "$DIFFCOLS"
  fi
done

note ""
if [ "$FAIL" -eq 0 ]; then
  note "RESULT: PASS —— 除原文 sha256（H10/H12 时间戳）外，全部探针的全部列逐字相同"
  exit 0
else
  note "RESULT: FAIL —— 见上方 FAIL 行；未定位原因前不得判定换包成功"
  exit 1
fi
