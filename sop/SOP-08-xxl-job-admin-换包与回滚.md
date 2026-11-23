# SOP-08 xxl-job-admin（调度中心）换包与回滚

> **版本** v1.0 ｜ **建档** 2026-11-23（G8 只读基线采集轮）
> **状态** `BLOCKED` —— **不是"未部署"，是"已稳定运行 1373 天但无回滚材料"**。
> 机上只有一份现役 jar，零历史副本，因此**当前不具备可执行的回滚能力**；§3 是解阻的唯一动作。
> **机读锚** `anchors/xxl-job-admin.env` ｜ **基线证据** `变更留痕/20261123-G8-xxl-job-admin基线采集/`
> **授权** 本文档的存在不构成执行许可。换包＝生产写，须按**动作**取得授权串（形如 `XXLJOB-swap-<YYYYMMDD>`）。

---

## 0. 这份规程为什么最后才有

在 2026-11-23 之前，本仓对 xxl-job-admin 的全部认知只有三件事：在 `/data/apps/xxl-job-admin`、
监听 8082、PID 89942 自 2023-02-18 起未重启。**连 jar 的 sha256 都没有** —— 没有基线锚，
任何换包规程都写不出来，写了也是猜测。所以它被排到最后，直到 2026-11-23 拿到一次只读授权。

首轮采集推翻了三条既有认知，其中两条直接决定规程怎么写（详见证据件 §4）：

| 既有认知 | 实测事实 | 对规程的影响 |
|---|---|---|
| 「脚本 nohup 拉起，**非 systemd**」 | `xxl-job-admin.service`，`Type=forking`，`ExecStart=/data/apps/xxl-job-admin/service.sh start`，`User=root`，`Restart=on-failure`，`enabled` + `active` | 重启一律 `systemctl`，**禁止 `kill`/`nohup` 手工拉起** |
| 预期配置经 `-D` 注入（照 threeants 经验） | `cmdline` 仅 74 字节、**无任何 `-D`** | 配置在 `.env` / `custom.env`，**SOP-02 的 `-D` 模式不可套用** |
| 预期应用目录有 `start.sh` | 目录是 `service.sh` + `.env` + `custom.env` + jar | `service.sh` 与 utc-admin **逐字节相同**（`2ffe750f…` / 12,888 B），禁动纪律可直接沿用 |

---

## 1. 坐标与现役基线（2026-11-23 只读实测，全部为实测值非估算）

### 1.1 机与进程

| 项 | 值 |
|---|---|
| 机 / SSH 别名 | UTC 生产机 `runyd-47-96-163-197`（47.96.163.197:62211，user `runyd`） |
| 应用目录 | `/data/apps/xxl-job-admin`，属主 `root:root`，mode `755` |
| systemd unit | `xxl-job-admin.service`，`/etc/systemd/system/xxl-job-admin.service` |
| 启动方式 | `Type=forking`，`ExecStart=…/service.sh start`，`User=root`，`WorkingDirectory=…/xxl-job-admin`，`Restart=on-failure` |
| 现役 MainPID | `89942`（启动于 **Sat 2023-02-18 22:36:59 CST**，至 2026-11-23 已 1373 天） |
| JVM 参数 | `-Xms512m -Xmx512m`（堆固定，无 `-D`，无 `-XX`） |
| 监听 | `*:8082`（**绑 0.0.0.0，不是回环**） |
| 上下文路径 | `/xxl-job-admin`（`http://127.0.0.1:8082/xxl-job-admin/toLogin` → 200） |
| 日志根 | `/data/logs/xxl-job-admin`（由 `/proc/89942/fd/1,2` 反查确认，**不在应用目录下**） |
| 磁盘 | `/data` 余量 184G、使用率 9%（备份与新 jar 无压力） |

### 1.2 现役 jar —— 唯一一份，无历史副本

| 项 | 值 |
|---|---|
| 文件 | `/data/apps/xxl-job-admin/xxl-job-admin.jar` |
| sha256 | `4c94e30ab99dd5719f21b204ea831326ebaa1d205088f50c858fd30df8543d71` |
| 字节 | `46,859,824` |
| mtime | `2023-02-18 21:30:08` |
| mode / 属主 | `755` / `root:root` |
| 形态 | Spring Boot fat jar（`Main-Class=org.springframework.boot.loader.JarLauncher`） |
| Spring Boot | `2.6.7` ｜ Build-Jdk `11.0.8` ｜ 442 条目 / 152 class |
| 启动类 | `com.xxl.job.admin.XxlJobAdminApplication` |
| **机内副本数** | **1（`jar_count=1`，无任何 `.bak`）** ← 本单元最大缺口 |

### 1.3 控制文件三件（只记指纹，正文一律不入仓）

| 文件 | sha256 | 字节 | mode | mtime |
|---|---|---|---|---|
| `service.sh` | `2ffe750f0211db65bf2001edd67caf0d6bf051d5bb10a08fac4b4716a82178b9` | 12,888 | 755 | 2023-02-18 21:31:28 |
| `.env` | `1b97338c1ca07788980a250bac2be7266ae1d46a3e129f9d99520f413484d1e8` | 200 | 644 | 2023-02-18 21:54:50 |
| `custom.env` | `7cf950d38814b82141540b9f189f3906317cac1439b4a970a48f43054e7aaee8` | 359 | 644 | 2023-02-18 22:01:59 |

★ `service.sh` 与 utc-admin 的**逐字节相同**（台账 §16）→ 共用同一套参数化模板。
但 `.env`（200 B）与 utc-admin 的（338 B）**不同**，`custom.env`（359 B）与 utc-admin 的（33 B）也不同
→ **共用脚本 ≠ 共用配置**，改配置绝不可跨服务复制。

★ `.env` / `custom.env` 是否含数据库口令：**未验证**（按纪律未读正文）。两文件 mode `644`、目录 `755`，
同机任何本地用户均可读 —— 若含口令即构成暴露面，登记于 §10，处置须单独授权。

### 1.4 与 utc-admin 的关系（换包影响面的核心，比 jar 本身重要）

```
        ┌──────────────────────────┐          ┌───────────────────────────┐
        │  xxl-job-admin（本单元）  │  HTTP    │  ryd-utc-admin（SOP-01）  │
        │  调度中心 · 独立进程      │◄────────►│  ★执行器内嵌在本进程内     │
        │  :8082 · 独立 jar         │  注册/   │  utc-job 模块随 jar 打包   │
        │  2023-02-18 起未重启      │  回调    │  executor ip=127.0.0.1:8083│
        └──────────────────────────┘          └───────────────────────────┘
             换它 = 不动客户端                    换它 = 不动调度中心
```

- 执行器**没有独立进程**（`utc-job` 随 utc-admin jar 打包，台账 §23 原话「无独立 utc-job 进程」）。
- `application-prod.yml` 的 `xxl.job.admin.addresses=http://127.0.0.1:8082/xxl-job-admin`。
- **单向换包的诱人假设是错的**：两者通过 HTTP 协议绑定，**大版本不兼容会同时打断两条链**。

| 只换调度中心 | 只换执行器（utc-admin jar） |
|---|---|
| 客户端不动 → 兼容性风险**单侧可控** | 调度中心不动 → 兼容性风险**单侧可控** |
| 风险：新服务端若改了注册/回调路径或强制 accessToken，老执行器注册失败 | 风险：新执行器若用新版 `xxl-job-core`，老服务端不认 |
| 判据：执行器在线 + 手动触发成功（§5.2） | 判据：日志出现新 regist 序列 + 调度中心看到在线（SOP-01 §0） |

★ **结论：跨大版本时两者必须同批换。** 现役执行器端的 `xxl-job-core` 版本**未采**（GAP）——
这是判定能否单换服务端的唯一前置，必须在 §2 第 6 项补齐。

---

## 2. 前置条件（缺一不动）

1. **现役锚零漂移**：`sha256sum /data/apps/xxl-job-admin/xxl-job-admin.jar` = `4c94e30a…`。
   不等则先查是谁动过（本节失败即停，不得继续）。
2. **回滚材料已在机上**（§3）—— **首次换包前此项必然是"未做"，必须先单独执行 §3 并取得授权。**
3. **新 jar 定源可陈述**：来源（官方 release / 自建 / 供应商交付）、版本号、sha256、字节数四件齐全。
   **只有 jar 没有出处的一律拒收**（等同 SOP-00 §6 的准入口径）。
4. **属主与权限**：新文件与现役一致 `root:root` / `755`；执行 `chown` / `chmod` 属写操作，须在授权串内。
5. **磁盘余量**：`/data` 可用 ≥ 3 × 新 jar（现余 184G，非阻断项，仍须现采一次）。
6. **版本兼容性已判定**：新调度中心的 `xxl-job` 版本 vs 现役执行器的 `xxl-job-core` 版本，
   须给出"兼容 / 需同批换执行器"的明确结论。**未判定即视为不兼容**（fail-closed）。
7. **调度窗口**：避开 `HH:00–HH:05`（整点触发密集）。重启期间到点的 cron **不会补跑**，
   须提前确认该窗口内没有必须准点执行的业务任务。
8. **业务知会**：列出本调度中心管理的任务清单与影响面，确认可接受一次调度中断。
9. **授权串**：`XXLJOB-swap-<YYYYMMDD>`，按动作绑定、不可复用（`deploy/README.md` 契约）。
10. **探针基线**：`bash scripts/probe-xxljob-admin.sh before` 落一份 before 输出（用于 after 的 diff）。

---

## 3. 首次换包前必须先做的事：建回滚材料（★ 当前唯一阻断项）

现役机内 `jar_count=1` —— 一旦新包有问题或启动失败，**没有任何东西可以退回去**。
这不是"以后再补"的事，它是 `STATUS=BLOCKED` 的唯一原因。

```bash
# 机上执行（写操作，须单独授权；建议与 §4 同一次授权内先行完成）
cd /data/apps/xxl-job-admin
sudo cp -p xxl-job-admin.jar xxl-job-admin.jar.bak-<YYYYMMDD>-pre-<新版本号>
sha256sum xxl-job-admin.jar xxl-job-admin.jar.bak-<...>
```

**验收判据**：备份件 sha256 必须 **逐字等于** `4c94e30ab99dd5719f21b204ea831326ebaa1d205088f50c858fd30df8543d71`，
字节 `46,859,824`。不等说明备份过程被干扰，**停手**。

完成后同一次提交内：把该值写入 `anchors/xxl-job-admin.env` 的 `ROLLBACK_FILES`，
并把 `STATUS` 由 `BLOCKED` 改为 `READY`、删除 `BLOCKED_REASON`。

> ★ 为什么强调"备份 sha 必须等于现役锚"：SOP-01 §3 已经踩过一次这个坑——
> 用过期读数当判据会把「备份的是现役包」误判成「备份的不是现役包」而停手。
> 反向更危险：把别的东西当成了现役包备份下来，回滚时才发现退回去的不是原版本。

---

## 4. 替换（五步骨架；与 SOP-01／SOP-03 同构）

### 4.1 上传到同分区 staging

```bash
# 本地
scp <新jar本地路径> runyd-47-96-163-197:/data/apps/xxl-job-admin/xxl-job-admin.jar.staging-<批次>
```

### 4.2 机上校验 staging（不校验不上位）

```bash
ssh runyd-47-96-163-197 -n
cd /data/apps/xxl-job-admin
sha256sum xxl-job-admin.jar.staging-<批次>
stat -c '%s %U:%G %a' xxl-job-admin.jar.staging-<批次>
```

- sha256 必须等于计划值；字节数一致。
- ★ **scp 用 `runyd` 用户上传 → 文件属主是 `runyd:runyd`**，而 unit 以 `root` 运行。
  必须 `sudo chown root:root` + `chmod 755`，否则换包后属主漂移，下一次 IMMUTABLE 比对会失败。

### 4.3 停服（`Type=forking` 下必须走 systemctl）

```bash
sudo systemctl stop xxl-job-admin
systemctl is-active xxl-job-admin      # 应为 inactive/failed，不是 active
```

★ **禁止 `kill <pid>` 或 `kill -9`**：`Type=forking` + `Restart=on-failure` 下，非 systemctl 的停止
会让 systemd 判定为异常退出并**可能立刻拉起**，与后续 `mv` 形成竞态。

### 4.4 替换并启动

```bash
cd /data/apps/xxl-job-admin
mv xxl-job-admin.jar.staging-<批次> xxl-job-admin.jar
sudo chown root:root xxl-job-admin.jar
chmod 755 xxl-job-admin.jar
sudo systemctl start xxl-job-admin
```

### 4.5 立即复核（3 条硬信号，任一不过即进 §6）

```bash
systemctl show xxl-job-admin -p MainPID --value      # 必须 ≠ 89942（且 ≠ 0）
ss -ltn | grep ':8082 '                              # 必须 1 条
curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8082/xxl-job-admin/toLogin   # 必须 200
sha256sum /data/apps/xxl-job-admin/xxl-job-admin.jar # 必须 = 计划值
```

---

## 5. 判据（三层；前一层不过不进下一层）

### 5.1 机内硬信号（必须全过）

| # | 判据 | 通过标准 |
|---|---|---|
| 1 | 现役 jar 指纹 | sha256 = 计划值，字节 = 计划值 |
| 2 | MainPID | 已变化（≠ `89942`）且非 0 |
| 3 | 端口 | `ss -ltn` 命中 `:8082` 恰好 1 条 |
| 4 | HTTP | `/xxl-job-admin/toLogin` = 200 |
| 5 | 启动标记 | `/data/logs/xxl-job-admin/stdout.log` 新增 `Started XxlJobAdminApplication in N seconds`（历史计数 1 → 2） |
| 6 | 绑定范围 | 与计划一致（现为 `*:8082`；若本轮计划收紧须复核新值） |
| 7 | 禁动件未动 | `service.sh` / `.env` / `custom.env` sha256 逐字等于 §1.3（换包不应碰配置） |
| 8 | 属主 | jar 为 `root:root` `755` |

★ **`systemctl is-active` 单独不构成判据**（README 铁律 2）：`Type=forking` + `Restart=on-failure` 下
`active` 只说明父进程退出过一次、systemd 认了，不代表应用绑上了 8082。

### 5.2 调度功能（人工，**不可自动化**）

| # | 判据 | 说明 |
|---|---|---|
| 9 | 执行器在线 | 浏览器进调度中心「执行器管理」，`127.0.0.1:8083` 在列表且在线 |
| 10 | 手动触发成功 | 任一任务「执行一次」→ 调度成功，日志 `handleCode=200` |
| 11 | 次日核对 | 当日任务按 cron 正常触发、无漏跑（**这是唯一能证明调度恢复的证据**） |

★ 为什么这两条无法自动化：调度中心无登录态、执行器注册关系不对外暴露 API；
而**任务执行日志写数据库 `xxl_job_log` 表、不落文件**（实测 `jobhandler_dir=none`），
所以"看日志文件判断任务跑了没有"这条路**不存在**，只能人看或查库（查库另需授权）。

### 5.3 若同批换了执行器（utc-admin jar）

| # | 判据 |
|---|---|
| 12 | utc-admin 日志出现新的整点 `regist` 序列，执行器在调度中心侧在线 |
| 13 | 当日执行日志条数与基线量级一致（台账 §23 口径：单日 27 件、`handleCode=200`） |

---

## 6. 回滚

```bash
cd /data/apps/xxl-job-admin
sudo cp -pR xxl-job-admin.jar.bak-<YYYYMMDD>-pre-<...> /tmp/rb.jar   # 先复制，别直接动备份件
sha256sum /tmp/rb.jar                                               # 必须 = 4c94e30a…
sudo systemctl stop xxl-job-admin
sudo mv /tmp/rb.jar xxl-job-admin.jar
sudo chown root:root xxl-job-admin.jar
chmod 755 xxl-job-admin.jar
sudo systemctl start xxl-job-admin
```

判据＝§5.1 全过，且 jar sha256 **逐字等于** `4c94e30ab99dd5719f21b204ea831326ebaa1d205088f50c858fd30df8543d71`。
**回滚只认 sha256，不认文件名**（同机可能有多种命名风格的历史件）。

★ 回滚后必须补做：`anchors/xxl-job-admin.env` 的 CURRENT 改回旧值、`变更留痕/00-索引.md` 登记回滚批次。
★ **禁止**在回滚后删除失败的新包 —— 它是事故分析的唯一材料。

---

## 7. 禁止事项

1. **禁止**在没有回滚材料时换包（§3 未完成即不得进入 §4）。
2. **禁止**用 `kill` / `nohup` / 手工 `java -jar` 起停 —— 一律 `systemctl`（`Type=forking`）。
3. **禁止**只凭 `systemctl is-active` 判成功。
4. **禁止**在 `HH:00–HH:05` 重启（整点触发密集，且**待触发任务不补跑**）。
5. **禁止**把 `MemoryCurrent` 当容量判据 —— 实测读数 `4096`（字节）在 `Type=forking` 下不可用，
   要看 RSS 就实测 `ps -o rss=`。
6. **禁止**照 threeants 的 `-D` 注入经验改本服务配置 —— 本服务 `cmdline` 无 `-D`，配置在 `.env` / `custom.env`。
7. **禁止**把 `.env` / `custom.env` 正文读入证据、仓库、文书（可能含数据库口令）。
8. **禁止**在跨大版本升级时只换调度中心不判执行器兼容性（§2 第 6 项，fail-closed）。
9. **禁止**清理 `/data/logs/xxl-job-admin/*.zip` —— 1260 个按天压缩件是 2023-02-18 至今
   **唯一的调度日志历史**（总量仅 3.5 MB，毫无清理必要）。
10. **禁止**跨服务复制 `.env` / `custom.env` —— `service.sh` 相同但参数文件不同（§1.3）。
11. **禁止**在换包后直接宣称"调度正常" —— §5.2 第 11 项（次日核对）完成前，状态只记"待观察"。

---

## 8. 收尾

1. 归档本次证据到 `变更留痕/<日期>-<批次>-xxl-job-admin-<动作>/`。
2. 回写三处（README 铁律 4）：`sop/SOP-08` 按实际执行修订、`anchors/xxl-job-admin.env` 的 CURRENT/ROLLBACK 移位、
   `变更留痕/00-索引.md` 追加一行。
3. 更新 `指纹台账.md` 的 xxl-job-admin 段（新建或追加）。
4. 机上清理 staging 残留（`rm` 属写操作，须在授权串内）；**备份件与日志 zip 禁删**。

---

## 9. 判例（本单元特有的四条，全部来自实测）

**判例 1：`ppid=1` 不等于 nohup。**
首轮看到 `pid_ppid=1` 时，若套用"父进程是 1 → 被 init 收养 → nohup 拉起"的经验，会得出错误结论。
本机实际是 systemd（PID 1）直接拉起的服务，`ppid=1` 是**正常形态**。
→ 判"谁在管理进程"必须看 `systemctl show -p ExecStart` / `FragmentPath`，不能从 ppid 反推。

**判例 2："目录不存在"必须由第二条证据背书。**
首轮 `log_dir=NOT_FOUND` 差点被写成"日志被 `1>/dev/null` 丢弃、该服务无日志"。
真相是日志根在 `/data/logs/xxl-job-admin`（由 `/proc/<pid>/fd/1` 反查）。
→ 否定性结论（不存在/没有/零命中）永远需要独立第二证据，这是 README 铁律 3 的又一次实例。

**判例 3：同一个 `service.sh` 不等于同一套配置。**
`service.sh` 两台服务逐字节相同（`2ffe750f…`/12,888 B），但 `.env` 200 B vs 338 B、
`custom.env` 359 B vs 33 B 完全不同。**模板共用是最容易诱发"照抄配置"的陷阱。**

**判例 4：`Type=forking` + `Restart=on-failure` 是回滚的隐形对手。**
`kill` 掉进程后 systemd 可能立刻拉起旧 jar，与随后的 `mv` 形成竞态，出现"新包放上去了但跑的是旧进程"。
→ 停止必须走 `systemctl stop`，并**确认 `is-active` 已非 active 再动文件**。

---

## 10. 已知风险与缺口（登记不处置；处置须单独授权）

| # | 项 | 现状 | 影响 |
|---|---|---|---|
| R1 | **无回滚材料** | 机内 `jar_count=1` | 换包失败无退路；`STATUS=BLOCKED` 的唯一原因 |
| R2 | **8082 绑 `0.0.0.0`** | `*:8082`，且 `firewalld=inactive`、`iptables` 无 8082 规则 | 暴露面**完全取决于云安全组**，机内无第二道防线 |
| R3 | `.env` / `custom.env` mode `644` | 目录 `755`、属主 `root:root` | 若含数据库口令，同机任何本地用户可读 |
| R4 | 调度中心 1373 天未重启 | `2023-02-18` 起 | 首次重启若失败，等于把一台跑了 3.8 年的服务变成事故现场 —— 这正是 R1 必须先解的原因 |
| R5 | 执行器 `xxl-job-core` 版本未采 | GAP | 无法判定服务端能否单换（§2 第 6 项 fail-closed） |
| R6 | `unit` 文件 sha256 未采 | GAP | 无法做 unit 防漂移比对 |
| R7 | jar 内未解包核 `BOOT-INF/lib` 版本 | 只读了 manifest 与条目数 | 无法用 lib 字节指纹区分"版本相同但重打包" |
| R8 | 无专属 `after` 探针基线 | 本轮只有 `before` 形态（`scripts/probe-xxljob-admin.sh`） | 换包时须自建 before/after 两份并 diff |
| R9 | 库 `xxl_job` 位置未知 | 本机 `mysql_port_listen=0`、`mysql_client=none` | 查执行日志须知道库在哪；换包本身不依赖它 |

> ★ R4 与 R1 叠加后有一个必须说清的结论：**本单元当前不是一个"可以安排换包"的对象，
> 而是一个"先要建立退路、再谈升级"的对象。** 任何绕过 §3 的换包计划都不可接受。
