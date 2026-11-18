#!/bin/bash
# ============================================================================
# probe-threeants-http.sh — threeants (unicard-official, 7003) HTTP 回归探针
#
# 用途：G3 换包前后各跑一次，逐字段 diff，证明「基础功能没被弄坏」。
#       与 probe-utc-http.sh 同构（sha_norm 判读口径一致）。
#       预期 after 差异只有一类：卡详情响应新增 statusDesc 键（REQ-20261113-01）。
#
# 三条硬边界（违反任一条即不得在生产执行）：
#   1) 零写库：只调 GET 查询端点。ICCID 入参一律用假卡号
#      89860000000000000001（命中 0 行）。
#      ★ 严禁加入任何 POST 探针：/api/web/iccid/{id}/active（激活，改库）、
#      /api/web/recharge/iccid（建订单）、/api/web/pay（下单）、
#      /api/web/agent/recharge（扣池）均为写操作（业务契约 §4 已核实）。
#   2) 零凭据：不带 openId/JWT；T05 正是利用「缺身份必然被拒/空」的确定性行为。
#   3) 只在本机回环：默认 127.0.0.1:7003，必须 ssh 到 threeants 机执行。
#
# 用法： bash probe-threeants-http.sh <label>
#        label 取 before / after / adhoc；输出写 /tmp/ta-http-<label>.txt
# 判读： diff before after。**一致性判据是 sha_norm 列**（错误体内嵌时间戳时
#        原文 sha 恒变）；statusDesc 新键导致的 shape/sha 变化＝预期增量，
#        须逐条人工归因，其余列任何 diff 都不可接受。
# 依赖： curl（必需）、jq（可选，缺失降级 NON_JSON 粗粒度）、sha256sum、sed
#        ⚠ threeants 机工具面与 UTC 机不同（无 ss）；jq 是否存在以首跑
#        "# jq=" 元行为准，before/after 必须同为 1 或同为 0，否则不可对照。
# ============================================================================
set -uo pipefail

LABEL="${1:-adhoc}"
HOST="${TA_HOST:-127.0.0.1}"
PORT="${TA_PORT:-7003}"
CTX="${TA_CTX:-/api/web}"
BASE="http://${HOST}:${PORT}${CTX}"
OUT="${OUT_DIR:-/tmp}/ta-http-${LABEL}.txt"
FAKE_ICCID="89860000000000000001"

command -v curl >/dev/null 2>&1 || { echo "FATAL: curl 不存在" >&2; exit 3; }
HAVE_JQ=1
command -v jq >/dev/null 2>&1 || HAVE_JQ=0

: > "$OUT"
{
  echo "# ta-http-probe"
  echo "# label=${LABEL}"
  echo "# base=${BASE}"
  echo "# jq=${HAVE_JQ}"
  echo "# cols: id  http  bytes  sha256  sha_norm  code  message  datalen  shape"
} >> "$OUT"

# probe <id> <method> <path>
probe() {
  local id="$1" method="$2" path="$3"
  local tmp http raw bytes sha shan code msg dlen shape
  tmp="$(mktemp)"

  http="$(curl -s -m 25 -o "$tmp" -w '%{http_code}' -X "$method" "${BASE}${path}" 2>/dev/null)"

  raw="$(cat "$tmp" 2>/dev/null)"
  rm -f "$tmp"

  bytes="$(printf '%s' "$raw" | wc -c | tr -d ' ')"
  sha="$(printf '%s' "$raw" | sha256sum | cut -d' ' -f1)"
  # 归一化：ISO-8601 带引号字符串形式（与 probe-utc-http.sh 同一实测口径，
  # 不要改回 epoch 数字模式）。
  shan="$(printf '%s' "$raw" | sed 's/"timestamp":"[^"]*"/"timestamp":"T"/' | sha256sum | cut -d' ' -f1)"

  if [ "$HAVE_JQ" = "1" ] && printf '%s' "$raw" | jq -e . >/dev/null 2>&1; then
    code="$(printf '%s' "$raw" | jq -r 'if (type=="object" and has("code")) then (.code|tostring) else "-" end')"
    msg="$(printf '%s' "$raw" | jq -r 'if (type=="object" and has("message")) then (.message|tostring) else "-" end')"
    dlen="$(printf '%s' "$raw" | jq -r '
      if (type=="object" and has("data")) then
        ( .data
          | if type=="array" then "arr:" + (length|tostring)
            elif type=="object" then "obj:" + ((keys|length)|tostring)
            elif . == null then "null"
            else type end )
      else "-" end')"
    shape="$(printf '%s' "$raw" | jq -r '[paths | join(".") ] | unique | join("|")' | cut -c1-200)"
  else
    code="-"
    msg="NON_JSON"
    dlen="-"
    shape="$(printf '%s' "$raw" | tr -d '\n' | cut -c1-100)"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$id" "$http" "$bytes" "$sha" "$shan" "$code" "$msg" "$dlen" "$shape" >> "$OUT"
}

# ---- A 组：卡详情（本 REQ statusDesc 增量的目标端点，只读）----
# T01 假卡号 → R1 实测基线 HTTP 800 / 23B（业务错误码形态）
probe T01 GET "/iccid/${FAKE_ICCID}"
# T02 短卡号（R1 冒烟同款入参 123456）→ 确定性校验失败形态
probe T02 GET "/iccid/123456"

# ---- B 组：套餐列表（只读；iccid 必传，业务契约 §4.6 根因条款）----
# T03 假卡号 → 期望「未找到卡信息」类业务错误（证明 UTC 库存查通路）
probe T03 GET "/rateplan?iccid=${FAKE_ICCID}&page=1&pageSize=1"
# T04 缺 iccid → 期望参数校验失败（S11 根因形态，确定性）
probe T04 GET "/rateplan?page=1&pageSize=1"

# ---- C 组：身份/框架层 ----
# T05 名下卡列表，不带 openId 身份 → 期望被拒或空（鉴权链装配正常；
#     参数名 page/size 为已核实形态；LIST 走 ModelGroup.LIST 只出三键，
#     statusDesc 键缺席属已知降级 non_null，不在本探针判据内）
probe T05 GET "/iccid?page=1&size=1"
# T06 不存在路径 → 期望 404（若错误体含 timestamp 走 sha_norm）
probe T06 GET "/no-such-endpoint"

echo "---- 结果（${LABEL}）----"
cat "$OUT"
echo "---- 已写入 ${OUT} ----"

# 自检 1：探针数量必须为 6
N="$(grep -c '^T' "$OUT")"
if [ "$N" -ne 6 ]; then
  echo "FATAL: 探针数 ${N} != 6，结果不可用于对照" >&2
  exit 6
fi

# 自检 2：归一化生效条数（sha != sha_norm 的条目只能按 sha_norm 对照）
DIFFN="$(awk -F'\t' '/^T/ && $4 != $5 { c++ } END { print c+0 }' "$OUT")"
RAWONLY="$(awk -F'\t' '/^T/ && $4 != $5 { print $1 }' "$OUT" | tr '\n' ',')"
echo "OK: 6 条探针全部返回"
echo "OK: 归一化生效条数=${DIFFN}: ${RAWONLY:-none}"
echo "NOTE: before/after 的 jq 元行必须一致；statusDesc 新键 diff 须逐条归因"