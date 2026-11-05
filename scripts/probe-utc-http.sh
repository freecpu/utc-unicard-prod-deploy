#!/bin/bash
# ============================================================================
# probe-utc-http.sh — UTC (ryd-utc-admin) HTTP 回归探针
#
# 用途：换包前后各跑一次，逐字段 diff，证明「基础功能没被弄坏」。
#       回答的是"通信正常 + 老功能正常"，不回答"新业务逻辑正确"。
#
# 三条硬边界（违反任一条即不得在生产执行）：
#   1) 零写库：只调只读端点。所有 ICCID 入参一律用不存在的假卡号
#      89860000000000000001，命中 0 行 → 不产生 INSERT/UPDATE，
#      也不会把真实卡数据打进终端或日志。
#   2) 零凭据：不需要 JWT、不需要 OPENAPI_TOKEN。H08/H11/H12 正是利用
#      「缺凭据必然被拒」这一确定性行为，来验证鉴权链是否正常装配。
#   3) 只在本机回环：默认 127.0.0.1，必须 ssh 到 UTC 机器上执行，
#      不从外网打裸端口，避免网络抖动污染 before/after 对照。
#
# ⚠ 已核实的危险入参（脚本内已规避，改动时勿引入）：
#   POST /openapi/iccid 的 mapper（FlowAccountMapper.xml#queryTerminal）为
#   `where 1=1 <if iccids 非空> and std.iccid in (...) </if> order by std.iccid`，
#   **无分页**。若 iccids 传空数组或不传，SQL 退化为全表扫
#   store_terminal_detail（生产 2 万+行）+ left join，会打生产库。
#   故 H09 强制携带非空 iccids，且本脚本不提供任何空列表探针。
#
# 用法： bash probe-utc-http.sh <label>
#        label 取 before / after / adhoc；输出同时写 /tmp/utc-http-<label>.txt
# 判读： diff before after 两份文件。**一致性判据是 sha_norm 列，不是 sha256 列。**
#        sha256 是响应体原文指纹；H10/H12 的错误页体内嵌 ISO-8601 时间串，
#        每次调用都不同，会让原文 sha 恒定失配（假阳性）。
#        sha_norm 在算指纹前先把 "timestamp":"<ISO-8601>" 归一为 "timestamp":T，
#        于是「只有时间戳在变」与「真的变了」可以区分开。
#        终判：除 sha256 与 label 元行外，其余列（含 sha_norm）必须逐字相同。
# 依赖： curl（必需）、jq（可选，缺失时降级为 NON_JSON 粗粒度）、sha256sum、sed
# ============================================================================
set -uo pipefail

LABEL="${1:-adhoc}"
HOST="${UTC_HOST:-127.0.0.1}"
PORT="${UTC_PORT:-8001}"
CTX="${UTC_CTX:-/manage}"
BASE="http://${HOST}:${PORT}${CTX}"
OUT="${OUT_DIR:-/tmp}/utc-http-${LABEL}.txt"
FAKE_ICCID="89860000000000000001"

command -v curl >/dev/null 2>&1 || { echo "FATAL: curl 不存在" >&2; exit 3; }
HAVE_JQ=1
command -v jq >/dev/null 2>&1 || HAVE_JQ=0

: > "$OUT"
{
  echo "# utc-http-probe"
  echo "# label=${LABEL}"
  echo "# base=${BASE}"
  echo "# jq=${HAVE_JQ}"
  echo "# cols: id  http  bytes  sha256  sha_norm  code  message  datalen  shape"
} >> "$OUT"

# probe <id> <method> <path> <body-or-empty>
probe() {
  local id="$1" method="$2" path="$3" body="$4"
  local tmp http raw bytes sha shan code msg dlen shape
  tmp="$(mktemp)"

  if [ "$method" = "GET" ]; then
    http="$(curl -s -m 25 -o "$tmp" -w '%{http_code}' "${BASE}${path}" 2>/dev/null)"
  else
    http="$(curl -s -m 25 -o "$tmp" -w '%{http_code}' \
              -X "$method" \
              -H 'Content-Type: application/json' \
              --data-binary "$body" \
              "${BASE}${path}" 2>/dev/null)"
  fi

  raw="$(cat "$tmp" 2>/dev/null)"
  rm -f "$tmp"

  bytes="$(printf '%s' "$raw" | wc -c | tr -d ' ')"
  sha="$(printf '%s' "$raw" | sha256sum | cut -d' ' -f1)"
  # 归一化：只抹掉错误页里的 timestamp，其余字节一律保留。
  # ★ 已实测取值形式（不要改回数字模式）：
  #   {"timestamp":"2026-11-04T04:56:29.391+00:00","status":500,…}
  #   即 Spring Boot 默认错误属性里 timestamp 是**带引号的 ISO-8601 字符串**，
  #   不是 epoch 毫秒数字。第一版写成 s/"timestamp":[0-9]*/…/ 时 [0-9]*
  #   匹配零个字符，归一化完全失效（sha 与 sha_norm 两次连跑仍不等）。
  #   ISO 串长度恒定，所以 bytes 列不变——单看 bytes 会漏掉这个坑。
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

# ---- A 组：N1-N4 新端点（REQ-20261022-03 交付物，全部只读）----
# A1 正常路径：假卡号 → 期望 success + 空结果（证明 DB 通路 + 序列化正常）
probe H01 POST /openapi/terminal/detail   "{\"iccid\":\"${FAKE_ICCID}\"}"
# A2 参数校验：缺 iccid → 期望 code=-1 请求参数非法
probe H02 POST /openapi/terminal/detail   "{}"
# A3 请求体解析：非 JSON → 期望 code=-1 请求体或字段类型非法
probe H03 POST /openapi/terminal/detail   "not-a-json"
# A4 N2 正常路径
probe H04 POST /openapi/flow/package/list "{\"iccids\":[\"${FAKE_ICCID}\"]}"
# A5 N2 枚举校验：非法 status → 期望 code=-1 请求参数非法
probe H05 POST /openapi/flow/package/list "{\"iccids\":[\"${FAKE_ICCID}\"],\"status\":\"NOT_AN_ENUM\"}"
# A6 N3 正常路径（分页 size=1，假卡号）
probe H06 POST /openapi/recharge/list     "{\"iccid\":\"${FAKE_ICCID}\",\"page\":0,\"size\":1}"
# A7 N3 三选一校验：agentId/iccid/rechargeId 全缺 → 期望 code=-1 请求参数非法
probe H07 POST /openapi/recharge/list     "{\"page\":0,\"size\":1}"
# A8 N4 鉴权：不带 X-Openapi-Token → 期望 code=-1 准入校验失败（早返回，不查库）
probe H08 POST /openapi/agent/list        "{\"page\":0,\"size\":1}"

# ---- B 组：改造前就存在的既有端点（证明老功能未被回归破坏）----
# B1 /openapi/iccid（既有五端点之一，被 threeants queryIccid/queryTerminal 共用）
#    ⚠ 必须带非空 iccids，见文件头「危险入参」说明
probe H09 POST /openapi/iccid             "{\"iccids\":[\"${FAKE_ICCID}\"]}"

# ---- C 组：框架层（路由 / 拦截器 / 全局异常 / 错误页）----
# C1 不存在的路径 → 期望 404（响应体含 timestamp，sha 允许 before/after 不同）
probe H10 POST /openapi/no-such-endpoint  "{}"
# C2 JWT 拦截器：真实存在但受保护的 handler，不带 token → 期望 401 code=1401
probe H11 GET  /mall/terminal             ""
# C3 完全不存在的路径 + GET → 期望 404
probe H12 GET  /no/such/path              ""

echo "---- 结果（${LABEL}）----"
cat "$OUT"
echo "---- 已写入 ${OUT} ----"

# 自检 1：探针数量必须为 12，少了说明有探针静默失败
N="$(grep -c '^H' "$OUT")"
if [ "$N" -ne 12 ]; then
  echo "FATAL: 探针数 ${N} != 12，结果不可用于对照" >&2
  exit 6
fi

# 自检 2：归一化必须真的生效且充分。两个方向都要查：
#   a) 若 sha 与 sha_norm 全表恒等，说明 sed 根本没匹配上（错误页结构变了），
#      此时 sha_norm 不提供任何信息，判读会退化成看 sha。
#   b) 本自检无法在一次跑内验证 sha_norm 是否“足够稳定”——必须连跑两次 diff，
#      见 README 的「基线可重现性双跑验证」步骤（否则归一化不完全是静默假阳性）。
DIFFN="$(awk -F'\t' '/^H/ && $4 != $5 { c++ } END { print c+0 }' "$OUT")"
RAWONLY="$(awk -F'\t' '/^H/ && $4 != $5 { print $1 }' "$OUT" | tr '\n' ',' )"
echo "OK: 12 条探针全部返回"
echo "OK: 归一化生效条数=${DIFFN}（这些条目的原文 sha 每次必变，只能按 sha_norm 对照）: ${RAWONLY:-none}"
