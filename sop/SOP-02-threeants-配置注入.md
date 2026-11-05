# SOP-02 生产 threeants 配置注入（`-Dutc.agent-flow-*`）

> 目标机器：`runyd-47-111-157-5`（47.111.157.5:62211，user `runyd`）
> 单元：`ryd-unicard-official.service`　端口：`7003`
> 应用目录：`/usr/local/ryd-unicard/`　`WorkingDirectory=/usr/local/ryd-unicard`
> 应用日志：`/usr/local/ryd-unicard/var/official.log`
>
> ✅ **本 SOP 的方案 A 已于 2026-11-05 17:25 CST 执行完毕**（用户授权「选定方案后立即执行」）。
> 结果 `APPLY_OK` + `VERIFY_OK`。执行记录见 `变更留痕/20261105-S4-生产方案A/执行与验收记录.md`。
> 现役 unit sha256 = `4a928353…67cc`；回滚目标 = `ad1acd4d…570d`（备份在生产 `/tmp/`）。
> ⚠ **仍有 1 环未闭环**：预划拨**真实业务调用**未验证（脚本不制造业务数据）。
> ⚠ **方案 A 的代价（配置漂移）**：修复值只在 unit L16，不在 jar / 不在源码仓；
> 换包或按源码重建 unit 会静默丢失这两个键，缺陷复活且无告警。
>
> ⚠ **本 SOP 是生产写操作（改 unit + 重启）。再次执行前须重新取得授权。**
> ⚠ **注入值取多少、走方案 A 还是 B，属架构决策，须用户裁定，操作者不得自行选定。**
> ⚠⚠ **重启前必须先备份 `official.log`（§5.1b）**：重定向是 `>`（截断），重启即清零。
> 2026-11-05 的执行没做这一步，销毁了 502 MB 生产日志。
> ⚠⚠ **unit 文件含明文 `OPENAPI_TOKEN`**：读它必须脱敏，禁止整文件 `cat`，禁止入 git（§8 第 11/12 条）。

---

## 0. 要修的缺陷（★ 已于 2026-11-05 修复，本节保留为病因记录）

生产 threeants 的**经销商流量池预划拨自 2026-10-28 起 fail-closed**，坏了 8 天。
`AgentServiceImpl` 预划拨 100% 抛「经销商流量池不存在」。

> ★ 病因不是「缺池 id」。现行 `AgentServiceImpl` L369-373 只读
> `utc.agent-flow-coefficient` / `utc.agent-flow-recharge-min` 两个配置项，任一为 null 即抛；
> `utcProperties.getAgentFlowId()` 在整个 threeants 源码树引用数为 **0**，
> 且 prod yml 的 `agentFlowId` 本来就未注释。报错文案是**沿用旧代码未改的字符串**。
> 详见 `变更留痕/20261105-S4-生产方案A/执行与验收记录.md` §1。


**运行期直接证据**（`变更留痕/20261105-S4-D注入通路验证/生产移植性探测.txt`）：

```
has_agent_flow_D = 0        ← 现役 cmdline 里没有任何 -Dutc.agent-flow-*
MainPID          = 13930
ExecMainStartTimestamp = Wed 2026-10-28 01:12:59 CST   ← 连续 8 天未变
```

根因：`application-prod.yml` 里两个键**被注释掉了**，而 threeants 没有其它取值来源，
代码走 fail-closed 分支。

### 注入值（取自生产库自身，不是搬测试夹具）

`ryd_utc.t_agent_flow WHERE id = 130820039822` → **coefficient = 50，recharge_min = 0**

取证方式见 `scripts/read-prod-agentflow.sh`（凭据不回显、不落盘，
证据文件里只有 `username_len = 4  password_len = 11`）。

> prod yml 注释里「杜绝误搬测试机 50/0」的顾虑是对的 —— 而生产实数**恰好也是 50/0**。
> 区别在于这个值取自生产库、有独立取证链，不是从 `application-dev.yml` 抄的。

---

## 1. 方案选型（★ 须用户裁定，不得自行决定）

| | 方案 A：`-D` 注入 systemd unit | 方案 B：改 yml 重新构建换包 |
|---|---|---|
| 做法 | 改 unit L16，在 jar 路径**之前**加两个 `-D` | 取消 `application-prod.yml` 两行注释，重新构建，按换包流程替换 93 MB jar |
| 优点 | 不需重新构建；可逆（备份 + restore）；**通路已完整验证** | 符合 yml 注释写明的原设计意图（「取数后取消注释填入」）；**单一事实源，无漂移** |
| 缺点 | **产生配置漂移**：jar 内 yml 仍写着「已注释 / fail-closed」，真实值躺在 unit 里，日后读 yml 的人会被误导 | 要构建 + 传输 + 替换 + 重启，改动面与耗时大得多；新构建会带新时间戳（不影响代码，但整包哈希会变） |
| 共同代价 | 都需**重启生产 threeants**（约 16 秒端口不可用） | 同左 |

两条路都能修好缺陷。选哪条属配置管理的架构决策。

> **不存在「更轻的第三条路」**：生产 threeants **没有任何外部配置目录**
> （S6 之后 `candidate_yml_list=` 为空，`WorkingDirectory` 下无 `config/`、顶层无 `application*.yml`）。
> 「不改 unit、只放一个外部 yml」要用就得同时改 unit 加
> `--spring.config.additional-location` 并新建配置文件 —— 比纯 `-D` 改动面更大。

---

## 2. 前置事实（2026-11-05 实测，动手前须复核）

| 项 | 值 |
|---|---|
| systemd | **219**（CentOS 7）。`-p KEY --value` **不支持**；`NRestarts` **不存在**；`StartLimitIntervalUSec` 叫 `StartLimitInterval` |
| `Type` | **`simple`** ← **`is-active` 恒定不可作健康判据**（见 §5） |
| `Restart` / `RestartUSec` | `always` / `100ms` |
| `StartLimitBurst` / `StartLimitInterval` | `5` / `10000000`（=10s） |
| unit 文件 | `/etc/systemd/system/ryd-unicard-official.service`，sha256 `ad1acd4d7fbb3aa63b4d6e7edda896c08c51130c45448b13bc09ff386e03570d`，1321 B，`root:root` |
| jar | `/usr/local/ryd-unicard/bin/unicard-official-1.0.0.jar`，sha256 `bd24267b…2b05`，93,135,977 B |
| journal | **空**。ExecStart 的重定向在 `sh` **内部**完成，systemd 收不到任何输出 |
| 启动耗时 | 约 **16 s**（测试机实测） |

现役 ExecStart（unit L16）：

```
/bin/sh -c "exec /usr/bin/java -jar -Xmx256m -Xms256m -Dspring.profiles.active=prod \
  -Dserver.port=7003 -Dfinance-refund.enabled=true \
  /usr/local/ryd-unicard/bin/unicard-official-1.0.0.jar \
  > /usr/local/ryd-unicard/var/official.log 2>&1"
```

> ⚠ unit **L15 保留着一份被注释掉的旧 ExecStart 变体**（用 `--finance-refund.enabled=true`
> 双横线程序参数形式）。改 unit 时**只动 L16**，不要误改 L15，也不要「顺手清理」它 ——
> 清理属另一个决策，须单独授权。

### ★ 属性优先级（决定注入点是否会被覆盖）

Spring Boot 中：Java 系统属性（`-D`）**高于** jar 内/外的 application yml，
但**低于**命令行程序参数（`--x=y`）。

生产用 `-D` 传 profile 且**无任何外置配置目录** → 注入的 `-Dutc.agent-flow-*`
**不会被任何 yml 覆盖**，通路成立。

### ★ `-D` 位置规则（曾写错过，已被生产 cmdline 推翻并纠正）

**正确规则：`-D` 必须在 jar 文件名之前**，与 `-jar` 标志本身的位置无关。

HotSpot 启动器按「遇到第一个非选项参数才当作 jar 文件名」解析。生产现役 cmdline 就是活证据：
`-jar` 在最前、三个 `-D` 全在其后，而 `spring.profiles.active=prod` 确实生效。

真正致命的是把 `-D` 放到 **jar 文件名之后**（那里开始全是程序参数，会被 Spring 当 `--` 参数处理）。

> 我曾把规则写成「JDK 8 下 `-jar` 之后的 `-D` 会失效」并写进仓库文件，**那是错的**。
> neg3 模式就是专门用来把这条**测出来**而不是靠传闻。

**本 SOP 的注入点选在 `-Dfinance-refund.enabled=true` 之后、jar 路径之前** ——
生产已证明该位置上的 `-D` 生效。

---

## 3. 搬到生产前必跑：移植性探测（只读）

**测试机脚本不可直接套到生产。** 2026-11-05 实测发现两个会导致**静默假阴性**的坑：

```bash
scp scripts/probe-prod-portability.sh runyd-47-111-157-5:/tmp/
ssh runyd-47-111-157-5 'bash /tmp/probe-prod-portability.sh'
```

必须确认的输出项：

| 项 | 期望 | 若不符 |
|---|---|---|
| `systemd_version` | 记录下来 | 219 → 全脚本改用 `-p KEY \| cut -d= -f2-` |
| `show_--value` | 记录 SUPPORTED / UNSUPPORTED | UNSUPPORTED → 同上 |
| journal 是否有内容 | 记录 | **为空 → `verify-d-injection.sh` 必须带 `TA_LOG`** |
| `has_agent_flow_D` | `0`（未修复前） | 若为 1，说明已被人修过，**停手重新评估** |
| `MainPID` / `ExecMainStartTimestamp` | 记录为基线 | 用于事后证明「只读操作没影响运行态」 |
| unit 文件 sha256 | 等于 §2 记录值 | 不等说明 unit 已变，**停手** |

### ★ journal 为空 → 本类脚本最危险的假阳性

只读 journal 时属性名命中数恒为 0，于是 pos 模式会把「**日志源是死的**」
当成「没有绑定异常」→ 报出**假阳性 `POS_OK`**。
测试机上 journal 有输出，恰好掩盖了这一点。

`verify-d-injection.sh` 已做三处加固，**在生产上必须全部生效**：

1. `TA_LOG` 指定应用日志文件；
2. **重启前记录该文件字节偏移，重启后只读新增部分**
   （`official.log` 实测已 **522 MB** 且仍在涨，整读不可接受）；
   并处理观测期内被轮转/截断（`cur < off`，此时 `tail -c +N` 会输出空、同样退化成假阳性）；
3. 统计实际读到的行数与 Spring Boot 启动特征串命中数，
   **行数为 0 就在所有判定分支之前直接拦住并报 `LOG_SOURCE_DEAD`（exit 7）**。
   这道总闸不只保护 pos：neg 会误报 `NEG_KEY_NOT_BOUND`、neg3 会误报 `NEG3_OK`，
   都是「静默失效伪装成验证通过」。

### ★ `/proc/<pid>/cmdline` 读法

生产以**非 root 的 `runyd`** 登录，读 root 进程的 cmdline 时：

- **不要用 `sudo tr '\0' '\n' < /proc/<pid>/cmdline`** —— 重定向由**当前 shell** 打开文件，
  `sudo` 对它无效。用 `sudo cat /proc/<pid>/cmdline | tr '\0' ' '`。
- 权限判据用 `$SUDO test -r`，**不用** shell 的 `[ -r ]` —— 判据必须与实际读取能力一致，
  否则会在能读时误报 FATAL（假阴性）。
- 实测生产该文件是 `-r--r--r-- root root`、`read_len_nosudo=170`=`read_len_sudo=170`，
  两种写法都能工作。**但这是实测结论，不是可以假设的前提** —— 换机器必须重测。

---

## 4. ★ 生产上只跑 pos，不跑 neg 类模式

依据（`指纹台账.md` §7，逐字节证据）：**生产与测试机跑的是同一份代码。**

三层清单（外层 291 / common 内层 225 / data 内层 158）逐条比对，
差异共 **5 处、全是 Maven `pom.properties`**；三者剔掉 `#` 注释行后的归一化 sha256
两边完全一致；关键类逐字节相同：

| class | 长度 | CRC-32 |
|---|---|---|
| `UtcProperties.class`（**绑定 `-D` 键的类**） | 6407 | `c5d879b3` |
| `AgentServiceImpl.class`（fail-closed 抛出点） | 50853 | `32a73066` |
| `AgentService.class` | 4125 | `0f5683a1` |

键名绑定行为与 `-D` 位置规则属**编译期/启动器行为，同码必同结果** →
测试机上 neg / neg2 / neg3 的结论可外推到生产，
**无须也不应该在生产上故意制造启动失败。**

### 测试机已完成的五模式实测（2026-11-05，unit `unicard-test-threeants-official`）

| 模式 | 注入位置与内容 | 属性名点名行数 | port_listen | 判定 |
|---|---|---|---|---|
| neg | `-Xmx256m` 后：`-Dutc.agent-flow-coefficient=NOT_A_NUMBER` | **11**（另 18× BindException、1× ConversionFailedException、9× Failed to bind） | **0** | `NEG_OK` |
| neg2 | `-Xmx256m` 后：`-Dutc.agent-flow-recharge-min=NOT_A_NUMBER` | **11** | **0** | `NEG_OK` |
| neg3 | **jar 文件名之后**：同一无效值 | **0** | **1**（16s） | `NEG3_OK` |
| pos | `-Xmx256m` 后：两个 `-D…=99` | 0 | **1**（16s） | `POS_OK` |
| restore ×4 | 从 `/tmp/<unit>.bak-verify-d` 还原 | — | **1** | `RESTORE_OK` ×4 |

**方法为什么是负控制**：不去调 pre-transfer 接口（它要求 `context.getLevel()==0`
一级经销商 + JWT 鉴权 —— 为读一个配置值去构造业务凭据，代价与风险都不划算，
且会产生业务数据）。改为**故意注入无法转成 Integer 的 `NOT_A_NUMBER`**：
键名绑得上 → 启动期抛绑定异常、异常里点名该属性、端口起不来；
键名写错 → 全程无异常、端口正常起来。两种结果都可判定，不需业务凭据、不产生业务数据。
**用「必然失败」当信号，比用「必然成功」当信号更硬。**

> ⚠ **pos 不能单独作为证据**：键名拼错时 pos 照样 `POS_OK`（未知属性被静默忽略），
> 这是典型假阳性。**键名正确性只能由 neg / neg2 提供**，两者缺一不可。
> 生产上不跑 neg，前提是 §4 的同源性证明成立 —— 那个证明失效时，这条豁免也失效。

---

## 5. 执行步骤（方案 A，须逐步授权）

### 5.1 备份 unit（★ 不可跳过）

推荐直接用执行脚本，它把备份与指纹核对绑在一起（备份 sha 不等于台账值就 `exit 4`）：

```bash
scp scripts/apply-agentflow-fix.sh runyd-47-111-157-5:/tmp/
ssh runyd-47-111-157-5 'TA_UNIT=ryd-unicard-official \
  TA_LOG=/usr/local/ryd-unicard/var/official.log \
  bash /tmp/apply-agentflow-fix.sh preflight'      # 只读，4 项闸门
```

手工备份的等价命令：

```bash
ssh runyd-47-111-157-5 'sudo cp -p /etc/systemd/system/ryd-unicard-official.service \
  /tmp/ryd-unicard-official.service.bak-<日期> && \
  sha256sum /tmp/ryd-unicard-official.service.bak-<日期>'
```

sha256 **必须等于** §2 记录的 `ad1acd4d…570d`（**方案 A 已于 2026-11-05 执行，现役值已变为
`4a928353…67cc`；`ad1acd4d…570d` 现在是回滚目标**）。不等就停手。

> ⚠ 用 `cp -p`，**不是 `cp -a`**；`mv` 用 `mv -v`，**GNU `mv` 没有 `-a` 选项**。
> 我曾在给用户的生产命令里写过 `sudo mv -a`，那是错的。

> ⚠⚠ **这个 unit 文件含明文 `OPENAPI_TOKEN`（`Environment=` 行）。读它必须先脱敏**：
> `sudo grep -v Environment= <unit>` 或 `sudo sed 's/\(TOKEN=\).*/\1REDACTED/' <unit>`。
> 备份文件同样含该 token —— **禁止 scp 回本仓、禁止入 git、禁止在记录里复述其值**。
> 2026-11-05 我用 `cat -A` 整文件打印，把 token 带进了终端输出，这是取证环节的纪律违反。

### 5.1b 备份应用日志（★ 不可跳过 —— 2026-11-05 血的教训）

`ExecStart` 的重定向是 **`>`（截断）而非 `>>`（追加）**，
**每次重启都会把 `official.log` 整份清零**。2026-11-05 的重启销毁了
526,489,119 B（约 502 MB，覆盖 2026-10-28 → 2026-11-05 的全部 threeants 生产日志），不可恢复。

```bash
ssh runyd-47-111-157-5 'sudo cp -p /usr/local/ryd-unicard/var/official.log \
  /usr/local/ryd-unicard/var/official.log.pre-<日期> && \
  sudo stat -c "%s %n" /usr/local/ryd-unicard/var/official.log*'
```

> 502 MB 的 `cp` 需要几十秒与等量磁盘空间，先 `df -h` 确认。
> 若判断历史日志无保留价值，**也必须在动手前明确说出来并让用户确认**，不能默认它无所谓。
> `apply-agentflow-fix.sh` 里的 `log_new_text` 有「读到 `cur < off` 就退回整读」的守卫，
> 但那守的是**结论正确性**（防止把日志源死掉当成没有异常），**守不住数据**。两件事必须分开做。

### 5.2 改 ExecStart

在 L16 的 `-Dfinance-refund.enabled=true` **之后、jar 路径之前**插入：

```
 -Dutc.agent-flow-coefficient=50 -Dutc.agent-flow-recharge-min=0
```

约束：
- **只改 L16**，不动 L15 的注释变体。（锚点选单横线 `-D` 形式，实测 `anchor_match_count=1`，天然不误伤 L15 的双横线 `--finance-refund.enabled=true`）
- 保持 `/bin/sh -c "exec …"` 的整体结构与末尾重定向不变。
- 改完立刻 `sha256sum` + `diff` 与备份比对，**确认只有预期的那一行变了**（`diff_changed_lines` 必须恰好为 2）。
- ★ `sed` **无匹配时静默不改且 rc=0**，是典型假阴性 → 改完必须 `grep -q` 自检注入是否真落进去。

### 5.3 重载并重启（★ 核心写操作）

生产修复用 `apply-agentflow-fix.sh`（注入真实值 50/0，只跑 pos 类路径）：

```bash
ssh runyd-47-111-157-5 'TA_UNIT=ryd-unicard-official \
  TA_LOG=/usr/local/ryd-unicard/var/official.log \
  bash /tmp/apply-agentflow-fix.sh apply'
```

`TA_LOG` **必须带**，否则脚本直接 `exit 3` 拒绝执行（§3）。

脚本会在 `restart` 前一律先 `systemctl reset-failed`。
> 注意：`reset-failed` 是幂等无害的保险，但**不能**把它当作「已规避启动限流」的证据 ——
> 生产实测完整启动 27.4 s > `StartLimitInterval` 10 s，应用层反复失败时每轮间隔 ≥27 s，
> 10 s 窗口内凑不满 `StartLimitBurst=5`，所以那种失败形态下**不会**进 `failed`，而是无限重启。


### ★ 注入错值后的失败形态 —— **无法断言，别照抄我旧的说法**

`Restart=always` + `RestartUSec=100ms` + `StartLimitBurst=5` + `StartLimitInterval=10s`。
单轮「启动 → 绑定失败」需数秒（测试机完整启动实测 16 秒），因此：

- 若单轮 < 2s → 10 秒窗口内 5 次启动 → 撞限流 → 单元钉在 `failed`，`restart` 被拒；
- 若单轮 ≥ 10s → 窗口内只有 1 次启动 → **永远撞不上** → 无限重启循环。

**哪种都无法断言**（要断言就得在生产上真的注入错值，而那正是要避免的）。
两种结果都是服务持续 DOWN 等人工干预，所以 `reset-failed` 一律执行（幂等、无害）。

> 我曾断言「注入错值会撞 StartLimitBurst=5 变 failed 停住」——
> **在实测参数下这句话不能断言**，已更正。

### 5.4 判据（全绿才算过）

| # | 判据 | 通过条件 |
|---|---|---|
| ① | `port_listen` | **= 1**（7003 LISTEN）。这是**唯一的硬健康信号** |
| ② | `cmdline_agent-flow-coefficient` | **= 50** |
| ③ | `cmdline_agent-flow-recharge-min` | **= 0** |
| ④ | `log_lines_seen` | **≠ 0**（否则 `LOG_SOURCE_DEAD`，判定全部无效） |
| ⑤ | `log_source_alive_markers` | **≠ 0**（证明读到的确实是 Spring Boot 启动日志） |
| ⑥ | `bound_property_mention_lines` | **= 0**（无绑定异常） |
| ⑦ | unit 文件 sha256 | 已变，且 diff 只有预期那一行 |

`verify-d-injection.sh` 判定输出：
- `POS_OK` — ①②③⑥ 通过且 ④⑤ 非零
- `POS_INCONCLUSIVE` — 端口起来了，但读到的日志里没有任何 Spring Boot 启动特征串
  → **不算通过**，须查清日志源
- `LOG_SOURCE_DEAD`（exit 7）— 一行日志都没读到，所有判定无效

### ★ 为什么 `is-active` 在这里完全没用

`Type=simple` + `Restart=always` 下，systemd 在 `exec` 成功那一刻就记 `active`。
之后应用绑定失败、JVM 退出、100ms 后再拉起，`is-active` 会在 `active`/`activating` 之间跳。
**它恒定不可作健康判据。** 硬信号只有两个：**端口 LISTEN**、**日志里点名的属性名**。

---

## 6. 回滚

```bash
ssh runyd-47-111-157-5 'sudo cp -p /tmp/ryd-unicard-official.service.bak-<日期> \
  /etc/systemd/system/ryd-unicard-official.service && \
  sudo systemctl daemon-reload && sudo systemctl reset-failed ryd-unicard-official && \
  sudo systemctl restart ryd-unicard-official'
```

或用脚本（★ 方案 A 已于 2026-11-05 执行，现役备份就是它产生的）：

```bash
ssh runyd-47-111-157-5 'TA_UNIT=ryd-unicard-official \
  TA_LOG=/usr/local/ryd-unicard/var/official.log \
  bash /tmp/apply-agentflow-fix.sh rollback'
# 备份：/tmp/ryd-unicard-official.bak-agentflow-fix（sha256 = ad1acd4d…570d）
# 脚本守卫：备份 sha 不等于台账值就拒绝回滚（回滚到来历不明的文件比不回滚更危险）
```

（测试机通路验证用的是另一个备份与另一个命令：`bash scripts/verify-d-injection.sh restore`）

回滚后验证：
1. unit 文件 sha256 **回到** `ad1acd4d…570d`
2. `cmdline_has_agent_flow_D` **= 0**（无 `-D` 残留）
3. `port_listen` **= 1**
4. ExecStart 与备份**逐字一致**（用 diff，不用肉眼）

> ⚠ 回滚意味着 fail-closed 缺陷**重新生效**，须另行安排修复。
> ⚠ 回滚同样会触发 `>` 截断 —— **回滚前也要先备份 `official.log`**（§5.1b）。

> `reset-failed` 在回滚时同样要执行：它是幂等保险。但注意 §5.3 的实测结论 ——
> 生产启动 27.4 s > 限流窗口 10 s，应用层反复失败其实**不会**进 `failed`。

---

## 7. 收尾

1. 归档原始输出到 `变更留痕/<日期>-<任务>/` —— ✅ 2026-11-05 已做：`变更留痕/20261105-S4-生产方案A/`（01-preflight / 02-apply / 03-verify / 04-log-health + 执行与验收记录.md）
2. 更新 `指纹台账.md`：unit 新 sha256、MainPID、启动时刻；技术债第 1 条状态改为「已修复」 —— ✅ 已做（§4/§5/§9/§10）
3. **登记配置漂移**（方案 A 的已知代价）：在台账里写明
   「jar 内 `application-prod.yml` 仍是注释状态，真实值在 unit L16」 —— ✅ 已登记于台账 §9 第 1 条与第 16 条
4. 清理远端 `/tmp`。**清理前先只读确认服务 active、7003 LISTEN**，清理后复核文件不存在
   —— ⚠ 本次**不清理**：`/tmp/ryd-unicard-official.bak-agentflow-fix` 是唯一回滚源，
   `/tmp/apply-agentflow-fix.sh` 是回滚所需工具，两者须保留（台账 §9 第 14 条另记其权限问题）
5. 若沙箱拦下 `rm`（`SetNamedSecurityInfoW 失败: 5`）：**先只读复核远端真实状态**再提权重跑
6. ★ **补做业务侧验证**：预划拨真实调用一次，确认不再抛「经销商流量池不存在」。
   在此之前不得对外宣称缺陷彻底闭环 —— 脚本判据证明的是「两个属性已非 null」，
   不是「业务流程已通」。

## 8. 禁止事项

1. **禁止**未做 §3 移植性探测就把测试机脚本套到生产。
2. **禁止**不带 `TA_LOG` 跑 `verify-d-injection.sh` / `apply-agentflow-fix.sh`。
3. **禁止**在生产上跑 neg / neg2 / neg3（除非 §4 的同源性证明被推翻并重获授权）。
4. **禁止**用 `is-active` 作为健康判据。
5. **禁止**把 `-D` 放到 jar 文件名之后。
6. **禁止**自行选定注入值或方案 A/B。
7. **禁止**改动 L15 的注释变体、jar 本体。
8. **禁止**内联远程命令（含 `$`、竖线、空格、中文一律写成脚本 scp 上传）。
   ★ 2026-11-05 又踩一次：`grep -nE "Started .*Application|Tomcat started"` 的内层双引号被
   PowerShell 剥掉，`|` 被当成管道 → `bash: JVM: command not found`。改用**无空格的单词模式**
   （`grep -n Started`）或写脚本上传。
9. **禁止**用 `sudo cmd < /proc/...` 形式读 root 进程文件。
10. **禁止**在未备份 `official.log` 的情况下重启 threeants（§5.1b）。`>` 是截断式重定向，重启即清零。
11. **禁止**不脱敏就 `cat` / `cat -A` unit 文件（含明文 `OPENAPI_TOKEN`）。只允许 `grep -v Environment=` 或 sed 脱敏后输出。
12. **禁止**把 unit 文件或其备份 scp 回本仓 / 提交进 git。
13. **禁止**仅凭脚本 `APPLY_OK` 就宣称业务已恢复 —— 真实业务调用是独立的一环（§7 第 6 条）。

---

## 9. ★ 后续任何 threeants 换包 / 重建 unit，必须重跑 verify

方案 A 把修复值放在了 **unit 文件**里，不在 jar 内、不在源码仓。这带来一个
**没有任何自动机制会发现**的失效模式：

| 触发场景 | 后果 |
|---|---|
| 换 threeants jar（不动 unit） | 注入仍在 → **安全**。但 jar 内 `application-prod.yml` 那两个键**仍是注释状态**，一旦有人「顺手把 unit 里的 -D 清掉，因为源码里已经配好了」就会立刻失效 |
| 按源码/模板**重建** unit 文件 | 两个 `-D` **静默丢失** → 属性回到 null → fail-closed **复活，且无任何告警** |
| 走方案 B（改 yml 重新构建）后忘记清 unit 里的 `-D` | `-D` 优先级高于 yml，unit 里的值会**压住**新构建的配置 → 改 yml 不生效，排查方向被彻底带偏 |

所以：**每次 threeants 换包或动 unit 之后，收尾必须跑一次**

```bash
ssh runyd-47-111-157-5 'TA_UNIT=ryd-unicard-official \
  bash /tmp/apply-agentflow-fix.sh verify'
```

判据：`coef_exact=1`、`rmin_exact=1`、`port_listen=1`、`unit_sha256` 与台账 §5 现役值一致。
输出 `VERIFY_FAIL` 就必须当场查清，不得留到业务报错才发现。

> 若已改走方案 B（值进了 jar），则**期望结果反过来**：`unit_sha256` 应回到不含 `-D` 的版本，
> 且需另外验证 jar 内 yml 的两个键已取消注释。届时本节须重写，不能照抄。

**根治仍是方案 B**：把两个值写进 `application-prod.yml` 并重新构建，让配置回到版本控制里。
方案 A 是「已授权、可立即执行、代价是配置漂移」的应急修复，不是终态。


