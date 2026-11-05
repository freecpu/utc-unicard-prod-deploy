#!/bin/bash
# ============================================================================
# verify-d-injection.sh — 验证 -D 系统属性能否绑定到 utc.agent-flow-* 配置键
#
# 要解决的问题：
#   生产 threeants 需要注入 -Dutc.agent-flow-coefficient / -Dutc.agent-flow-recharge-min
#   来修复预划拨 fail-closed。注入前必须确认「键名真的绑定得上」，否则改完
#   服务照常启动、但配置仍是 null，缺陷照旧——而且**看不出任何异常**。
#
# 为什么用负控制而不是去调 pre-transfer 接口：
#   pre-transfer 入口要求 context.getLevel()==0（一级经销商）+ JWT 鉴权，
#   为了读一个配置值去构造一级经销商凭据，代价与风险都不划算。
#   改用「故意注入一个无法转换成 Integer 的值」：
#     - 若键名绑定得上 → Spring Boot 启动期就抛绑定异常，服务起不来（可观测）
#     - 若键名写错/没绑定 → 启动完全正常（也可观测）
#   两种结果都可判定，且**不需要任何业务凭据、不产生任何业务数据**。
#   这是负控制：用「必然失败」当信号，比用「必然成功」当信号更硬。
#
# 五个模式（必须按 neg → neg2 → neg3 → pos → restore 顺序跑完，不得只跑 neg 就收工）：
#   neg     注入 -Dutc.agent-flow-coefficient=NOT_A_NUMBER（jar 名之前）→ 期望启动失败并报出该键名
#   neg2    注入 -Dutc.agent-flow-recharge-min=NOT_A_NUMBER（jar 名之前）→ 同上，验第二个键名
#   neg3    注入同样的无效值但放在 **jar 文件名之后** → 期望被当程序参数、完全无效
#   pos     注入 -Dutc.agent-flow-coefficient=99 -Dutc.agent-flow-recharge-min=99 → 期望启动成功
#   restore 从备份还原 unit 文件 → 期望端口 LISTEN 且 cmdline 里不再有这两个 -D
#
# ★ 为什么 neg/neg2 与 pos 缺一不可：
#   pos 成功**不能**证明键名拼对了——Spring Boot 对未知属性是静默忽略的，
#   键名写错时 pos 照样 POS_OK，这是典型假阳性。
#   只有 neg（注入必然无法转成 Integer 的值）能把两种情况区分开：
#   键名绑上了 → 绑定异常里点名该属性 + 端口起不来；键名没绑上 → 全程无异常 + 端口正常。
#
# ★ 为什么还要 neg3：
#   注入点的规则我曾写成「必须在 -jar 之前」，被生产 cmdline 直接推翻
#   （生产 -jar 在最前、三个 -D 在其后且生效）。正确规则是「必须在 jar 文件名之前」。
#   这种规则不能靠传闻，neg3 用「放在文件名之后必然无效」把它测出来，
#   与 neg（放在文件名之前必然生效）构成一组对照。
#
# 用法：
#   测试机（journal 有输出，不需要 TA_LOG）：
#     bash verify-d-injection.sh neg      # 依次 neg → neg2 → neg3 → pos → restore
#   生产（必须带 TA_LOG，否则判定不可信）：
#     TA_UNIT=ryd-unicard-official \
#     TA_LOG=/usr/local/ryd-unicard/var/official.log \
#     bash verify-d-injection.sh pos
#
# ★★ 生产上**不需要也不应该**跑 neg/neg2/neg3（2026-11-05 结论）：
#   已用 (长度, CRC-32, 条目名) 全清单递归比对证明：生产与测试机的
#   unicard-official-1.0.0.jar 里，com/cnc/unicard/common/config/UtcProperties.class
#   **逐字节相同**（6407 字节 / CRC-32 c5d879b3）；AgentServiceImpl.class
#   （50853 / 32a73066）与 AgentService.class（4125 / 0f5683a1）同样相同。
#   两个 jar 整包 sha256 之所以不同，差异**只在** 3 个 Maven pom.properties 的
#   构建时间戳注释行（剔掉 # 行后的归一化哈希两边完全一致）。
#   → 键名绑定行为与 -D 位置规则属编译期/启动器行为，同码必同结果，
#     neg/neg2/neg3 的结论可直接迁移，无须在生产上故意制造启动失败。
#   生产只需跑 pos（注入真实值），不构成故意破坏。
#
# 安全边界：
#   - 默认 unit 名是**测试机**的 unicard-test-threeants-official。要跑生产必须
#     显式传 TA_UNIT=ryd-unicard-official，且必须先获得用户对「重启生产 threeants」
#     的授权（本脚本会造成服务中断：neg/neg2 期间端口不可用约 45 秒；
#     pos 期间端口不可用约 16 秒）。
#   - 每次改 unit 前先 cp -p 备份到 /tmp，restore 模式从备份还原；
#     neg/neg2/neg3/pos 每次都先从备份还原再注入，避免多次注入叠加。
#   - 不打印任何凭据；只打印 ExecStart 行、systemd 状态、启动异常里的属性名。
#
# ★ 生产环境实测差异（systemd 219 / CentOS 7，2026-11-05 探测）：
#   - `systemctl show -p KEY --value` **不支持**（报 unrecognized option），
#     `NRestarts` 属性**不存在**，`StartLimitIntervalUSec` 叫 `StartLimitInterval`。
#     本脚本一律用 `-p KEY | cut -d= -f2`，两台机器通用。
#   - journal **为空**：ExecStart 是 /bin/sh -c "exec java ... > official.log 2>&1"，
#     重定向在 sh 内部完成，systemd 收不到任何输出。必须靠 TA_LOG 读 official.log。
#   - Restart=always + RestartUSec=100ms + StartLimitBurst=5 + StartLimitInterval=10s。
#     单轮启动到绑定失败约需数秒（测试机完整启动 16 秒），故**无法断言**是否一定撞限流：
#     撞上 → 单元钉在 failed，restart 被拒；撞不上 → 无限重启循环。
#     两种都是服务持续 DOWN。故 restart 前一律先 reset-failed（幂等、无害）。
#
# 依赖： sudo、systemctl、grep、sed、ss、journalctl、stat、tail
# ============================================================================
set -uo pipefail

MODE="${1:-}"
case "$MODE" in neg|neg2|neg3|pos|restore) ;; *) echo "用法: bash verify-d-injection.sh <neg|neg2|neg3|pos|restore>" >&2; exit 2 ;; esac

UNIT="${TA_UNIT:-unicard-test-threeants-official}"
PORT="${TA_PORT:-7003}"
# neg3 用的锚点：jar 文件名。测试机与生产机同名，但路径不同，故只匹配文件名。
JAR_TOKEN="${TA_JAR_TOKEN:-unicard-official-1.0.0.jar}"
UNIT_FILE="/etc/systemd/system/${UNIT}.service"
BAK="/tmp/${UNIT}.bak-verify-d"

SUDO="sudo -n"
$SUDO true 2>/dev/null || SUDO=""

# ★ 实测教训（2026-11-05 测试机 neg 跑）：本单元 Type=simple + Restart=on-failure，
#   systemd 在 exec 成功那一刻就把 is-active 记成 active，之后 Spring 绑定失败、
#   JVM 退出、10s 后再拉起——期间 is-active 会在 active/activating 间跳，
#   **恒定不可用作健康判据**。第一版脚本据此判出 NEG_INCONCLUSIVE，是错的：
#   同一次跑里 journalctl 已明确打出 15 次 BindException + 11 次
#   utc.agent-flow-coefficient，键名其实绑定得上。
#   真正的两个硬信号是：
#     ① port_listen —— 进程活着不等于服务起来了，端口 LISTEN 才是
#     ② journalctl 里绑定异常提到的**属性名** —— 只有 Spring 真去绑这个键才会报
port_up() { $SUDO ss -ltn 2>/dev/null | grep -c ":${PORT} "; }

# 轮询等端口，最多 wait_port <秒>；起来就立刻返回，省掉无谓等待
wait_port() {
  local n="${1:-60}" i=0
  while [ "$i" -lt "$n" ]; do
    [ "$(port_up)" != "0" ] && { echo "$i"; return 0; }
    sleep 2; i=$((i+2))
  done
  echo "TIMEOUT_${n}s"; return 1;
}

# ★★ 日志源（2026-11-05 生产取证触发，是本脚本最危险的失效点）：
#   生产 ExecStart 是
#     /bin/sh -c "exec /usr/bin/java ... > /usr/local/ryd-unicard/var/official.log 2>&1"
#   —— 重定向发生在 sh **内部**，systemd journal 里因此什么都没有。
#   只读 journal 会让 KEYCNT 恒为 0，于是 pos 模式会把「日志源是死的」当成
#   「没有绑定异常」→ 报出假阳性 POS_OK。测试机上 journal 有输出，掩盖了这一点。
#   所以三件事必须一起做：
#     ① 支持 TA_LOG 指定应用日志文件（生产传 /usr/local/ryd-unicard/var/official.log）
#     ② 重启前记录该文件的**字节偏移**，重启后只读新增部分
#        （official.log 实测已 522MB 且仍在涨，整读不可接受）
#     ③ 统计实际读到的日志行数；行数为 0 就**拒绝**下 POS_OK —— 宁可 INCONCLUSIVE
LOGFILE="${TA_LOG:-}"
LOG_OFFSET=0

log_snapshot_offset() {
  [ -n "$LOGFILE" ] || { LOG_OFFSET=0; echo "log_source=journal-only（未设 TA_LOG）"; return 0; }
  if ! $SUDO test -e "$LOGFILE"; then
    LOG_OFFSET=0
    echo "log_source=${LOGFILE}（当前不存在，偏移记 0）"
    return 0
  fi
  LOG_OFFSET="$($SUDO stat -c '%s' "$LOGFILE" 2>/dev/null | tr -d ' ')"
  [ -n "$LOG_OFFSET" ] || LOG_OFFSET=0
  echo "log_source=${LOGFILE}"
  echo "log_offset_before=${LOG_OFFSET}"
}

# 取「本次 restart 之后」的日志正文：journal（从 $1 时刻起）+ 文件（从偏移起）
log_new_text() {
  $SUDO journalctl -u "$UNIT" --since "$1" --no-pager 2>/dev/null
  if [ -n "$LOGFILE" ] && $SUDO test -e "$LOGFILE"; then
    local cur off
    cur="$($SUDO stat -c '%s' "$LOGFILE" 2>/dev/null | tr -d ' ')"
    off="${LOG_OFFSET:-0}"
    # 日志被轮转/截断时 cur < off，tail -c +N 会输出空 → 又变成假阳性。
    # 这种情况必须显式警告并退回整读（文件已变小，整读可接受）。
    if [ -n "$cur" ] && [ "$cur" -lt "$off" ]; then
      echo "WARN: ${LOGFILE} 在观测期内被轮转/截断（${off} → ${cur}），改为整读" >&2
      $SUDO cat "$LOGFILE" 2>/dev/null
    else
      $SUDO tail -c "+$((off + 1))" "$LOGFILE" 2>/dev/null
    fi
  fi
}

# ★ 读 root 进程的 /proc/<pid>/cmdline 一律用 `$SUDO cat | tr`，
#   不用 `sudo tr < /proc/...`：重定向由**当前 shell**（生产是非 root 的 runyd）
#   打开文件，sudo 对它无效。实测生产该文件是 -r--r--r-- 世界可读，两种写法都能
#   工作，但换一台设了 hidepid 的机器就会静默取空 → cmdline_has_agent_flow_D 假阴性报 0。
proc_cmdline() { $SUDO cat "/proc/$1/cmdline" 2>/dev/null | tr '\0' ' '; }

echo "==== mode=${MODE} unit=${UNIT} ===="
[ -r "$UNIT_FILE" ] || $SUDO test -r "$UNIT_FILE" || { echo "FATAL: 读不到 ${UNIT_FILE}" >&2; exit 3; }

PID_BEFORE="$($SUDO systemctl show "$UNIT" -p MainPID 2>/dev/null | cut -d= -f2)"
echo "PID_before=${PID_BEFORE}"
echo "is_active_before=$($SUDO systemctl is-active "$UNIT" 2>&1)"

# ---- restore：从备份还原，不再做任何注入 ----
if [ "$MODE" = "restore" ]; then
  [ -r "$BAK" ] || { echo "FATAL: 找不到备份 ${BAK}，无法还原（请手工检查 unit 文件）" >&2; exit 4; }
  echo "== 还原前 ExecStart =="
  $SUDO grep '^ExecStart' "$UNIT_FILE"
  $SUDO cp -f "$BAK" "$UNIT_FILE"
  $SUDO systemctl daemon-reload
  # ★ 必须 reset-failed：生产 Restart=always + RestartUSec=100ms + StartLimitBurst=5
  #   + StartLimitInterval=10s（实测 systemd 219），注入错值后有可能撞进限流把单元
  #   钉在 failed 状态，此时 restart 会被拒绝。单元没进 failed 时本命令是无害空操作。
  $SUDO systemctl reset-failed "$UNIT" 2>/dev/null
  $SUDO systemctl restart "$UNIT"
  echo "restart_rc=$?"
  echo "port_up_after_secs=$(wait_port 90)"
  echo "== 还原后 ExecStart =="
  $SUDO grep '^ExecStart' "$UNIT_FILE"
  echo "is_active=$($SUDO systemctl is-active "$UNIT" 2>&1)  (Type=simple 下此项不可作健康判据)"
  PID_AFTER="$($SUDO systemctl show "$UNIT" -p MainPID 2>/dev/null | cut -d= -f2)"
  echo "PID_after=${PID_AFTER}"
  CMD="$(proc_cmdline "${PID_AFTER:-0}")"
  HAS_D="$(printf '%s' "$CMD" | grep -c 'agent-flow')"
  echo "cmdline_has_agent_flow_D=${HAS_D}"
  echo "port_listen=$(port_up)"
  echo "== 判定 =="
  if [ "$(port_up)" != "0" ] && [ "$HAS_D" = "0" ]; then
    echo "RESTORE_OK: 已完全复原，无 -D 残留，端口 ${PORT} 已 LISTEN"
  else
    echo "RESTORE_FAIL: 须人工介入。备份在 ${BAK}"
  fi
  exit 0
fi

# ---- neg / pos：先备份，再改 ExecStart ----
if [ ! -r "$BAK" ]; then
  $SUDO cp -p "$UNIT_FILE" "$BAK"
  echo "backup_created=${BAK}"
else
  echo "backup_exists=${BAK}（沿用首次备份，不覆盖——避免把已注入的版本当原始版本）"
fi

echo "== 改前 ExecStart =="
$SUDO grep '^ExecStart' "$UNIT_FILE"

# 先还原成干净版本再注入，保证 neg/pos 之间不叠加
$SUDO cp -f "$BAK" "$UNIT_FILE"

BAD="-Dutc.agent-flow-coefficient=NOT_A_NUMBER "
case "$MODE" in
  # 只打 coefficient：验证第一个键名
  neg)  INJECT="$BAD" ;;
  # 只打 recharge-min：验证第二个键名。
  # ★ 为什么必须单独验：pos 模式注入两个合法值，若第二个键名拼错，Spring 只是
  #   忽略这个未知属性、服务照常起来，pos 会给出 POS_OK 的**假阳性**。
  #   只有「注入必然转换失败的无效值」才能把「键名没绑定」和「键名绑定上了」区分开。
  neg2) INJECT="-Dutc.agent-flow-recharge-min=NOT_A_NUMBER " ;;
  # 位置负控：同样注入无效值，但放在 **jar 文件名之后**（即落到程序参数区）。
  # 期望：Spring 根本看不到它 → 无绑定异常 + 端口正常起来。
  # 若结果反而报了绑定异常，说明位置规则不成立，SOP 里的注入点写法要改。
  neg3) INJECT="$BAD" ;;
  pos)  INJECT="-Dutc.agent-flow-coefficient=99 -Dutc.agent-flow-recharge-min=99 " ;;
esac

# ★★ 注入位置规则（2026-11-05 由生产 cmdline 实测纠正，此前写错过）：
#   规则不是「必须在 -jar 之前」，而是「**必须在 jar 文件名之前**」。
#   证据：生产 threeants 现役 cmdline 为
#     java -jar -Xmx256m -Xms256m -Dspring.profiles.active=prod -Dserver.port=7003
#          -Dfinance-refund.enabled=true /usr/local/ryd-unicard/bin/unicard-official-1.0.0.jar
#   —— -jar 在最前面，三个 -D 全在它之后，而 profiles.active=prod 确实生效。
#   HotSpot 启动器是按「遇到第一个非选项参数才当作 jar 文件名」来解析的，
#   所以 -jar 标志本身的位置不影响后续 -X/-D 的解析；真正致命的是把 -D 放到
#   jar 文件名之后（那里开始全是程序参数）。neg3 就是用来把这条实测出来的。
# 用 # 作 sed 分隔符，避免与 -D 里的 . 和 / 冲突。
if [ "$MODE" = "neg3" ]; then
  $SUDO sed -i "s#${JAR_TOKEN} #${JAR_TOKEN} ${INJECT}#" "$UNIT_FILE"
else
  $SUDO sed -i "s#-Xmx256m #-Xmx256m ${INJECT}#" "$UNIT_FILE"
fi
echo "== 改后 ExecStart =="
$SUDO grep '^ExecStart' "$UNIT_FILE"

# 自检：注入是否真的落进去了（sed 无匹配时静默不改，是典型假阴性）
if ! $SUDO grep -q 'agent-flow' "$UNIT_FILE"; then
  echo "FATAL: sed 未匹配到 -Xmx256m，注入没生效。已还原。" >&2
  $SUDO cp -f "$BAK" "$UNIT_FILE"
  exit 5
fi

$SUDO systemctl daemon-reload
# ★ 记录本次 restart 的时刻，journal 从这一刻起算。
#   不能用固定窗（如 --since '-180s'）：连续跑 neg→neg2 时，上一轮遗留的
#   utc.agent-flow-coefficient 会落进本轮窗口，让 neg2 的 KEYHIT/KEYCNT 被污染成假阳性。
SINCE="$(date '+%Y-%m-%d %H:%M:%S')"
# 同时记录应用日志文件的字节偏移（生产 journal 为空，全靠这个文件）
log_snapshot_offset
$SUDO systemctl reset-failed "$UNIT" 2>/dev/null
$SUDO systemctl restart "$UNIT"
echo "restart_rc=$?"
echo "restart_since=${SINCE}"
# neg 模式下端口永远不会起来，不能 wait_port（会白等 90s）；
# 但要给足时间让 Restart=on-failure 至少走完 2 个崩溃周期，journal 才有稳定证据。
case "$MODE" in
  neg|neg2)
    sleep 45
    echo "port_up_after_secs=SKIPPED(neg)" ;;
  *)
    echo "port_up_after_secs=$(wait_port 90)" ;;
esac

echo "== 结果 =="
echo "is_active=$($SUDO systemctl is-active "$UNIT" 2>&1)  (Type=simple+Restart=on-failure 下不可作健康判据)"
echo "unit_type=$($SUDO systemctl show "$UNIT" -p Type 2>/dev/null | cut -d= -f2)"
echo "nrestarts=$($SUDO systemctl show "$UNIT" -p NRestarts 2>/dev/null | cut -d= -f2)"
PID_AFTER="$($SUDO systemctl show "$UNIT" -p MainPID 2>/dev/null | cut -d= -f2)"
echo "PID_after=${PID_AFTER}"
PL="$(port_up)"
echo "port_listen=${PL}"
if [ -n "${PID_AFTER:-}" ] && [ "$PID_AFTER" != "0" ]; then
  proc_cmdline "$PID_AFTER" | tr ' ' '\n' | grep -o 'agent-flow[a-z.-]*=[^ ]*' | sed 's/^/cmdline_/'
fi

# 启动失败时把绑定异常里的**属性名**抓出来（不打印完整堆栈，避免带出配置值）
echo "== 绑定异常里的属性名（只取 property 名，不取值）=="
# journal + 应用日志文件合并。生产 journal 为空，只有文件里有内容。
JTXT="$(log_new_text "$SINCE")"
# ★★ 日志源存活性判据：必须真的读到日志行，否则「KEYCNT=0」只是日志源是死的，
#   不是「没有绑定异常」。少了这一条，pos 模式在生产上必然假阳性 POS_OK。
#   用 Spring Boot 启动必然打印的特征串来确认日志源活着（不依赖具体键名）。
LOG_LINES="$(printf '%s' "$JTXT" | grep -c . )"
LOG_ALIVE="$(printf '%s' "$JTXT" | grep -cE 'Started .*Application|Starting .*Application|Spring Boot|Tomcat started|JVM running')"
echo "log_lines_seen=${LOG_LINES}"
echo "log_source_alive_markers=${LOG_ALIVE}"
printf '%s' "$JTXT" \
  | grep -oE "(utc\.agent-flow-[a-z-]+|agentFlowCoefficient|agentFlowRechargeMin|BindException|ConversionFailedException|ConverterNotFoundException|Failed to bind)" \
  | sort | uniq -c
# 键名命中次数：只有 Spring 真的去绑这个键，绑定异常里才会出现该属性名
KEYHIT="$(printf '%s' "$JTXT" | grep -oE 'utc\.agent-flow-[a-z-]+' | sort -u | tr '\n' ',')"
KEYCNT="$(printf '%s' "$JTXT" | grep -cE 'utc\.agent-flow-[a-z-]+')"
echo "bound_property_names_seen=${KEYHIT:-none}"
echo "bound_property_mention_lines=${KEYCNT}"

echo "== 判定 =="
# ★★ 总闸：日志源没读到任何行时，所有依赖 KEYCNT 的分支都不可信 —— 不只是 pos。
#   neg 会误报 NEG_KEY_NOT_BOUND（其实是日志源死了）、neg3 会误报 NEG3_OK。
#   这一条必须在分支之前拦住，否则「静默失效」会伪装成「验证通过」。
if [ "${LOG_LINES:-0}" = "0" ]; then
  echo "LOG_SOURCE_DEAD: 本轮从 journal 与 ${LOGFILE:-<未设 TA_LOG>} 都没读到任何日志行。"
  echo "        KEYCNT=${KEYCNT} 在此**没有意义**：它只说明日志源是死的，不说明键名没绑定。"
  echo "        生产上若出现此结论，先确认 TA_LOG 是否指向了 ExecStart 里重定向的那个文件"
  echo "        （生产是 /usr/local/ryd-unicard/var/official.log），再重跑。不得据此下任何结论。"
  echo "== 下一步：必须跑 restore 模式复原 =="
  exit 7
fi
case "$MODE" in
neg|neg2)
  if [ "${KEYCNT:-0}" -gt 0 ] && [ "$PL" = "0" ]; then
    echo "NEG_OK: 无效值触发绑定异常且异常里点名 ${KEYHIT} → 该键名确实被 Spring 绑定到目标字段；"
    echo "        同时端口未 LISTEN → 服务确实因它起不来。两条硬信号同时成立。"
  elif [ "${KEYCNT:-0}" = "0" ] && [ "$PL" != "0" ]; then
    echo "NEG_KEY_NOT_BOUND: 注入了无效值但 journal 里从未出现该属性名、服务照常起来"
    echo "        → 键名拼写或 profile 前缀不对，-D 没有绑定到任何字段。**不得据此上生产。**"
  else
    echo "NEG_INCONCLUSIVE: 信号矛盾（KEYCNT=${KEYCNT} port_listen=${PL}），须人工看 journalctl。"
    echo "        此时不得下结论。"
  fi
  ;;
neg3)
  # 位置负控：-D 放在 jar 文件名之后，期望被当成程序参数而**完全无效**
  if [ "${KEYCNT:-0}" = "0" ] && [ "$PL" != "0" ]; then
    echo "NEG3_OK: 放在 jar 文件名之后的 -D 确实无效（无绑定异常 + 端口正常）"
    echo "         → 位置规则成立：**-D 必须在 jar 文件名之前**，与 -jar 标志的位置无关。"
    echo "         对照 neg（放在文件名之前）报了 11 次属性名 + 端口起不来，两者互为对照。"
  elif [ "${KEYCNT:-0}" -gt 0 ]; then
    echo "NEG3_UNEXPECTED: 放在 jar 文件名之后居然也被绑定了 → 位置规则不成立，"
    echo "         SOP-02 里关于注入点的写法必须改写。这是好消息（约束更松），但须重新核实。"
  else
    echo "NEG3_INCONCLUSIVE: 无绑定异常但端口也没起来（KEYCNT=${KEYCNT} port_listen=${PL}），"
    echo "         须人工看 journalctl 判断失败原因，不得据此下结论。"
  fi
  ;;
*)
  CD_OK="$(proc_cmdline "${PID_AFTER:-0}" | grep -c 'agent-flow-recharge-min')"
  if [ "$PL" != "0" ] && [ "${CD_OK:-0}" != "0" ] && [ "${KEYCNT:-0}" = "0" ] && [ "${LOG_ALIVE:-0}" != "0" ]; then
    echo "POS_OK: 合法值注入后端口 ${PORT} 已 LISTEN、cmdline 含两个 -D、日志源确认存活且无绑定异常 → -D 通路可用"
    echo "        log_lines_seen=${LOG_LINES} alive_markers=${LOG_ALIVE}（证明「无绑定异常」不是日志源死了）"
    echo "        注意：POS_OK 本身**不能**证明键名拼对了（未知属性会被静默忽略），"
    echo "        键名正确性由 neg / neg2 的 NEG_OK 提供。两者缺一不可。"
  elif [ "$PL" != "0" ] && [ "${LOG_ALIVE:-0}" = "0" ]; then
    echo "POS_INCONCLUSIVE: 端口起来了，但读到的 ${LOG_LINES} 行日志里没有任何 Spring Boot 启动特征串"
    echo "        → 无法确认「KEYCNT=0」是真没异常还是日志源不对。须人工核对 TA_LOG 指向，不得据此下结论。"
  elif [ "$PL" != "0" ]; then
    echo "POS_PARTIAL: 端口起来了但 cmdline/绑定异常检查未全过（CD_OK=${CD_OK:-0} KEYCNT=${KEYCNT:-0}），须人工核对"
  else
    echo "POS_FAIL: 注入合法值后端口未 LISTEN，须立刻 restore 并排查"
  fi
  ;;
esac
echo "== 下一步：必须跑 restore 模式复原 =="
