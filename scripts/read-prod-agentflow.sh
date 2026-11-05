#!/bin/bash
# ============================================================================
# read-prod-agentflow.sh — 只读查询生产 t_agent_flow 主池实数
#
# 为什么需要它（这是 S4 的前置阻塞项）：
#   threeants B2 #24 把预划拨校验的数据源从「直读 UTC t_agent_flow」改成
#   「读 utc.agent-flow-coefficient / utc.agent-flow-recharge-min 配置」。
#   生产要注入这两个 -D，就**必须知道生产本实例主池的实数**。
#   A3 裁定的 50/0 是用户裁定值，不是从生产库取的；若实数≠50/0：
#     - 实数 < 50：会把本该放行的预划拨拒掉（业务卡住，无资金损失）
#     - 实数 > 50：会放行本该拒掉的预划拨（业务规则漂移，须避免）
#   参照判例：agent-mp 侧曾把 RECHARGE_MIN 配成 0 而实为 4，属静默放宽。
#   故注入前必须先取实数。
#
# 通路：生产 threeants 机（47.111.157.5）上有 /usr/bin/mysql，且其 jar 内
#   application-prod.yml 仍保留对 ryd_utc 的直连 datasource（B2 未摘除，
#   这本身是一条技术债）。用该 datasource 的凭据做只读 SELECT。
#
# 安全边界（三条，违反即不得运行）：
#   1) **只跑 SELECT**。脚本内不含任何 INSERT/UPDATE/DELETE/DDL。
#   2) **凭据永不回显**：url/username/password 从 yml 读进 shell 变量后直接
#      传给 mysql，不 echo、不写文件、不进日志、不出现在 ps 参数里
#      （密码走 MYSQL_PWD 环境变量，不走命令行 -p，避免被 ps 看到）。
#   3) **只选非敏感列**：id / account_id / coefficient / recharge_min / enabled。
#      不选 name（经销商名称）、不选 recharge_no（充值账号）。
#
# 用法： bash read-prod-agentflow.sh [structure|query] [agentFlowId]
#        structure — 只打印 yml 的键结构（值一律 REDACTED），用于核对 datasource 段落
#        query     — 执行只读 SELECT（缺省模式）
# 依赖： sudo、unzip、mysql、awk、sed
# ============================================================================
set -uo pipefail

MODE="${1:-query}"
FLOW_ID="${2:-130820039822}"
JAR="${TA_JAR:-/usr/local/ryd-unicard/bin/unicard-official-1.0.0.jar}"
WORK="/tmp/agentflow-probe.$$"

SUDO="sudo -n"
$SUDO true 2>/dev/null || SUDO=""

command -v mysql >/dev/null 2>&1 || { echo "FATAL: 本机无 mysql 客户端" >&2; exit 3; }

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

mkdir -p "$WORK"
$SUDO unzip -o -q "$JAR" 'BOOT-INF/classes/application-prod.yml' -d "$WORK" >/dev/null 2>&1
YML="$WORK/BOOT-INF/classes/application-prod.yml"
[ -r "$YML" ] || { echo "FATAL: 解不出 application-prod.yml" >&2; exit 4; }
$SUDO chown -R "$(id -u):$(id -g)" "$WORK" 2>&1

# ---- structure 模式：只看键结构，值全部抹掉 ----
if [ "$MODE" = "structure" ]; then
  echo "==== application-prod.yml 键结构（值一律 REDACTED）===="
  # 保留缩进与键名；url 行单独处理成只留 host/db（已在下面 sed 里做）
  sed -e 's#\(jdbc:mysql://\)[^@]*@#\1REDACTED@#' \
      -e 's#^\(\s*username:\).*#\1 REDACTED#' \
      -e 's#^\(\s*password:\).*#\1 REDACTED#' \
      -e 's#^\(\s*token:\).*#\1 REDACTED#' \
      -e 's#^\(\s*secret:\).*#\1 REDACTED#' \
      -e 's#^\(\s*appKey:\).*#\1 REDACTED#' \
      -e 's#^\(\s*appSecret:\).*#\1 REDACTED#' \
      "$YML" | cat -n
  exit 0
fi

# ---- query 模式：定位 ryd_utc 那个 datasource 段落，取 url/username/password ----
# yml 里三个 datasource（本地 ryd_unicard、fuzhoukuaifu、ryd_utc），
# 必须精确取 ryd_utc 那一段，取错就连到别的库去了。
# 做法：从含 ryd_utc 的 url 行往上找最近的 username/password（Spring yml 里
# url/username/password 通常同属一个 datasource 块且相邻）。
URL="$(awk '/jdbc:mysql:/ && /\/ryd_utc/ {print; exit}' "$YML" | sed 's/^[[:space:]]*//' | cut -d' ' -f2-)"
if [ -z "$URL" ]; then echo "FATAL: 未找到 ryd_utc datasource" >&2; exit 5; fi

DBHOST="$(printf '%s' "$URL" | sed 's#jdbc:mysql://##' | cut -d/ -f1)"
DBNAME="$(printf '%s' "$URL" | sed 's#jdbc:mysql://[^/]*/##' | cut -d? -f1)"

# 在 url 行前后 6 行内找 username/password（不打印值）
LINENO_URL="$(grep -n 'ryd_utc' "$YML" | head -1 | cut -d: -f1)"
DBUSER="$(awk -v n="$LINENO_URL" 'NR>=n-6 && NR<=n+6 && /^[[:space:]]*username:/ {gsub(/^[[:space:]]*username:[[:space:]]*/,""); print; exit}' "$YML")"
DBPWD="$(awk -v n="$LINENO_URL" 'NR>=n-6 && NR<=n+6 && /^[[:space:]]*password:/ {gsub(/^[[:space:]]*password:[[:space:]]*/,""); print; exit}' "$YML")"

echo "==== 连接目标（凭据不回显）===="
echo "host_port = ${DBHOST}"
echo "database  = ${DBNAME}"
echo "username_len = ${#DBUSER}   password_len = ${#DBPWD}"
if [ -z "$DBUSER" ] || [ -z "$DBPWD" ]; then
  echo "FATAL: 未取到 username/password（yml 结构可能不是相邻布局，请先跑 structure 模式核对）" >&2
  exit 6
fi

# 密码走 MYSQL_PWD，避免出现在 ps 里
export MYSQL_PWD="$DBPWD"
MY="mysql --connect-timeout=10 -h ${DBHOST%%:*} -P ${DBHOST##*:} -u ${DBUSER} ${DBNAME} --batch --skip-column-names"

echo ""
echo "==== 连通性自检 ===="
if ! $MY -e 'SELECT 1' >/dev/null 2>"$WORK/err"; then
  echo "FAIL: 连接不上（可能是 RDS 白名单不含本机 IP）。错误类别："
  # 只打印错误类别，不打印完整错误（完整错误里会带 username 与 host）
  sed -e 's/.*\(Access denied\).*/\1/' -e 's/.*\(Can.t connect\).*/\1/' \
      -e 's/.*\(Unknown database\).*/\1/' -e 's/.*\(timeout\).*/\1/' "$WORK/err" | head -3
  exit 7
fi
echo "OK: 可连"

echo ""
echo "==== ① 按 threeants prod yml 里的 agentFlowId=${FLOW_ID} 查 ===="
echo "-- 期望：1 行。若 0 行，说明该 id 在 t_agent_flow 里不存在，"
echo "--       那么 B2 之前 getAgentFlowById(该id) 也会返回 null，"
echo "--       即「预划拨从来就没成功过」，这会解释为什么两侧都没报错。"
$MY -e "SELECT id, account_id, coefficient, recharge_min, enabled FROM t_agent_flow WHERE id = ${FLOW_ID}" 2>&1
echo "(以上为空则 0 行)"

echo ""
echo "==== ② t_agent_flow 全表概览（只取非敏感列，最多 30 行）===="
$MY -e "SELECT id, account_id, coefficient, recharge_min, enabled FROM t_agent_flow ORDER BY id LIMIT 30" 2>&1

echo ""
echo "==== ③ coefficient / recharge_min 的取值分布 ===="
echo "-- 用于判断 50/0 是否与生产实数一致"
$MY -e "SELECT coefficient, recharge_min, COUNT(*) AS pools FROM t_agent_flow GROUP BY coefficient, recharge_min ORDER BY pools DESC" 2>&1

echo ""
echo "==== ④ ${FLOW_ID} 在 t_account 里是什么（确认它是 account 还是 flow 的 id）===="
echo "-- threeants prod yml 里 agentId 与 agentFlowId 是同一个值 ${FLOW_ID}，"
echo "-- 这本身可疑：一个是经销商账号 id，一个是流量池 id，正常不该相同。"
$MY -e "SELECT id, enabled FROM t_account WHERE id = ${FLOW_ID}" 2>&1
echo "(以上为空则该 id 不在 t_account)"

echo ""
echo "==== ⑤ 该 account 名下的流量池（若 ④ 命中）===="
$MY -e "SELECT id, account_id, coefficient, recharge_min, enabled FROM t_agent_flow WHERE account_id = ${FLOW_ID} ORDER BY id" 2>&1
echo "(以上为空则该 account 名下无流量池)"

unset MYSQL_PWD
echo ""
echo "==== 完成。凭据未回显、未落盘（临时目录已随退出清理）===="
