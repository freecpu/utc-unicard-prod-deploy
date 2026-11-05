# SOP-01 生产 UTC 换包（`ryd-utc-admin.jar`）

> 目标机器：`runyd-47-96-163-197`（47.96.163.197:62211，user `runyd`）
> 单元：`ryd-utc-admin.service`　端口：`8001`　context-path：`/manage`
> 应用目录：`/data/apps/ryd-utc-admin/`
>
> ⚠ **本 SOP 全程是生产写操作。每一步动手前都要有用户对该动作的显式授权。**
> 授权按动作给，不按机器给、不按会话给、不沿用上一次。

---

## 0. 前置事实（2026-11-05 实测，动手前须复核是否仍成立）

| 项 | 值 |
|---|---|
| systemd | **219**（CentOS 7）。`systemctl show -p KEY --value` **不支持**，一律 `-p KEY \| cut -d= -f2-` |
| `Type` | `forking`，`PIDFile=/data/logs/ryd-utc-admin/ryd-utc-admin.pid` |
| `Restart` / `StartLimitBurst` | `on-failure` / `3` |
| 现役 jar sha256 | `ba16cd657e6e645af24f14cc7a6fd34f802cdcbc441dd988cfc9ed055b904262` / 108,561,064 B |
| 现役 MainPID / 启动时刻 | `2074989` / `Wed 2026-11-04 12:43:14 CST` |
| 现役 java 命令行 | `/usr/local/java/bin/java -server -Xmx4G -Xms4G -XX:+UseG1GC -XX:MaxGCPauseMillis=90 -Dspring.profiles.active=prod -jar ryd-utc-admin.jar` |
| 启动耗时 | 约 **14.6 s**（`Started UtcAdminApp in 14.583 seconds`） |

### ★ 一律不碰的四样东西

| 文件 | 为什么 |
|---|---|
| `application-prod.yml` (629 B) | 外置 profile 配置，含凭据。换包不改配置 |
| `.env` (338 B) / `custom.env` (33 B) | 环境变量载体，RUN_ARGS 由此注入 |
| `service.sh` (12,888 B, 2023-02-18) | 启动脚本。**java 命令行由它拼装**，改它等于改启动参数 |
| `/etc/systemd/system/ryd-utc-admin.service` | 本 SOP 无改它的需求 |

这四样在换包**前后各采一次 sha256**，哈希不变即为「确实没碰」。
这是事后自证的唯一手段 —— 光说「我没改」不算证据。
（`.env` / `service.sh` / unit 文件的指纹目前是**台账缺口**，第一次执行时顺手补上。）

### ★ 重启窗口纪律

xxl-job 每小时 **HH:00–HH:04** 有 MQ 批处理峰值（单分钟 1400+ 行日志）。
重启须避开该窗口。2026-11-04 那次选 12:43 正是为此。

---

## 1. 取基线（只读，不需要额外授权）

```bash
scp scripts/probe-utc-runtime.sh scripts/probe-utc-http.sh \
    scripts/probe-utc-traffic.sh runyd-47-96-163-197:/tmp/

ssh runyd-47-96-163-197 'bash /tmp/probe-utc-runtime.sh before > /tmp/utc-runtime-before.txt 2>&1; cat /tmp/utc-runtime-before.txt'
ssh runyd-47-96-163-197 'bash /tmp/probe-utc-http.sh    before > /tmp/utc-http-before.txt    2>&1; cat /tmp/utc-http-before.txt'
```

基线判据：`probe-utc-http.sh` 必须 **12/12 返回**。少于 12 条时**停手**，
先查清是哪条探针没回来 —— 带着残缺基线做换包，后面的 diff 全部不可信。

把两份基线 scp 回本地，归档到 `变更留痕/<日期>-<任务>/`。

## 2. 上传新包（写 `/tmp`，不动应用目录）

```bash
scp <本地>/utc-admin-prod-<短哈希>.jar runyd-47-96-163-197:/tmp/ryd-utc-admin.jar.upload
```

**双端指纹核对**（104 MB / 约 41 s，传输不完整是真实风险）：

```bash
# 本地
Get-FileHash <本地>\utc-admin-prod-<短哈希>.jar -Algorithm SHA256
# 远端
ssh runyd-47-96-163-197 'sha256sum /tmp/ryd-utc-admin.jar.upload; stat -c "%s" /tmp/ryd-utc-admin.jar.upload'
```

两边 sha256 与字节数**必须完全一致**，否则重新上传。**不要**靠「scp 返回 0」判定传输完整。

## 3. 备份现役包（★ 不可跳过）

```bash
ssh runyd-47-96-163-197 'cd /data/apps/ryd-utc-admin && \
  sudo cp -p ryd-utc-admin.jar ryd-utc-admin.jar.bak-<日期>-pre-<短哈希> && \
  sha256sum ryd-utc-admin.jar.bak-<日期>-pre-<短哈希>'
```

- 用 `cp -p` 保留权限与时间戳。
- 备份文件的 sha256 **必须等于**第 0 节记录的现役 sha256。不等就说明备份的不是现役包。
- 备份路径与 sha256 **立刻**记进 `指纹台账.md`（完整 64 位，不写缩写）。

> ⚠ 应用目录里已有 10 个历史 jar、**5 种命名风格**。
> **回滚判据只看 sha256，不看文件名。** 别指望靠文件名认出哪个是本次备份。

## 4. 落盘 + 重启（★ 核心写操作，须显式授权）

```bash
ssh runyd-47-96-163-197 'cd /data/apps/ryd-utc-admin && \
  sudo mv -f /tmp/ryd-utc-admin.jar.upload ryd-utc-admin.jar.new && \
  sudo mv -f ryd-utc-admin.jar.new ryd-utc-admin.jar && \
  sudo systemctl restart ryd-utc-admin; echo "rc=$?"'
```

- **`mv -f`，不是 `cp`**：`cp` 会保留原 inode 与部分属性，且写入过程中 jar 是半截的。
  `mv` 是同文件系统内的原子重命名。
- 先 `.new` 再 `mv` 到现役名，是为了让「落盘」与「生效」分成两步可各自核对。
- ⚠ **GNU `mv` 没有 `-a` 选项**（那是 `cp -a`）。写 `mv -a` 会直接报错。

重启后等约 15 s，确认启动标记：

```bash
ssh runyd-47-96-163-197 'sudo systemctl show ryd-utc-admin -p MainPID -p ExecMainStartTimestamp | cut -d= -f2-'
```

## 5. 验收判据（七项，全绿才算过）

| # | 判据 | 怎么取 | 通过条件 |
|---|---|---|---|
| ① | jar sha256 | `probe-utc-runtime.sh after` | **等于交付物 sha256** |
| ② | `ExecMainStartTimestamp` | 同上 | **晚于**新包落盘时刻 |
| ③ | 8001 LISTEN 的 pid | `ss -ltnp` | **等于 MainPID** |
| ④ | 目标 class 计数 | `probe-utc-runtime.sh` | 按本次需求预期变化（如 0 → 1） |
| ⑤ | `Started UtcAdminApp` | 应用日志 | 出现 1 次 |
| ⑥ | profile 未降级 | 应用日志 | `profiles are active: prod` |
| ⑦ | 新增异常类型 | `analyze-error-delta.sh` | **0** |

### ★ 关于 `is-active`

`Type=forking` 下 `is-active` 会等 PID 文件写出来才转 active，
**比 threeants 的 `Type=simple` 可信**。但它仍**不足以证明服务可用** ——
硬信号只有 **8001 LISTEN** 与 **日志里的启动标记**。
判据 ③ 和 ⑤ 才是真的，`is-active` 只是辅助。

### HTTP 回归（基础功能未被破坏）

```bash
ssh runyd-47-96-163-197 'bash /tmp/probe-utc-http.sh after > /tmp/utc-http-after.txt 2>&1'
scp runyd-47-96-163-197:/tmp/utc-http-after.txt <本地归档目录>/
bash scripts/compare-utc-http.sh <本地归档目录>/utc-http-before.txt <本地归档目录>/utc-http-after.txt
```

必须输出 **`RESULT: PASS`、退出码 0**。

12 条探针覆盖三层：A 组 H01–H08（新端点正常路径/参数校验/请求体解析/枚举/分页/token 鉴权）、
B 组 H09（改造前就存在的 `/openapi/iccid`，证明老功能未坏）、
C 组 H10–H12（路由 404、JWT 401、全局异常）。

> H10/H12 的原文 sha **每次必变**（响应体含 `timestamp`）。
> 比较器用 `sha_norm` 列（把 `"timestamp":"…"` 归一后再算）。
> **归一化正则必须是 `"timestamp":"[^"]*"`** —— Spring 输出的是带引号的 ISO-8601 串，
> 写成 `[0-9]*` 会匹配零字符、归一化静默失效，而且 ISO 串长度恒定使 `bytes` 列也不变，
> 单看 bytes 根本发现不了。**每次改归一化逻辑后连跑两次自证。**

### error 增量归因

`analyze-error-delta.sh` 报出的「新增类型」必须逐行归属到具体请求，
并用 `error-noise-rate.sh` 的全天背景噪声画像对照 —— 判断该类型是否属既有噪声。
2026-11-04 那次报出 `Exception` 与 `NestedServletException` 两个「新增」，
逐行归属后**都不是换包引入**。

⚠ 两个已修过的坑，别再踩：
- 类型正则必须 `[A-Za-z][A-Za-z0-9_.]*Exception`。写成 `[A-Za-z.]*Exception` 允许零长前缀，
  会报出伪类型 `Exception`。
- `analyze-error-delta.sh` 与 `probe-utc-runtime.sh` **必须用同一个正则**，否则两份输出不可比、
  交叉验证失效。
- 时间切片不能用 `sed -n "/<date time>/,\$p"`：error 日志里未必有以该分钟开头的时间戳行，
  会静默返回 1 行 → 假阴性。用 awk：日期前缀行更新标志位、堆栈续行继承。

### 真实业务流量存活

自造探针给不出「真实用户还在正常用」的证据。用 `probe-utc-traffic.sh`
取换包前后**同长度窗口**的日志行数与调用方分布对照。
2026-11-04 另取了 3 个整点窗口（w1055 / w1155 / w1255）证明 MQ 批量是既有周期行为、
不是换包引入的异常。

## 6. 不能当场验的东西，如实说明

以 C 线（撤销充值 / 退订监听器）为例：

- **当场可验（静态 + 装配层）**：目标 class 计数 0 → 1 确认进包；启动无异常、无新 logger、
  `Started UtcAdminApp`、profile 未降级 → Spring 容器完整启动，
  **若监听器 bean 装配失败会在启动期报错**。
- **必须等自然触发**：首次真实撤销/退订事件被正确处理；次日 xxl-job 周期任务跑完后的账目一致性。

为什么不能当场制造：触发需要真实业务动作，会写真实用户数据与账目。
**生产环境不允许为了验收而制造业务数据。** 这不是「偷懒等次日」，是生产写操作的边界。

次日观察用 `scripts/watch-cline.sh`，一次跑完即可确认，无需人肉翻日志。

> ⚠ 汇报时的措辞纪律：不要说「次日验收」。要按判据切分说清楚
> **哪几项当场已验完、哪几项必须等自然触发** —— 前者是结论，后者是挂账。

## 7. 回滚

```bash
ssh runyd-47-96-163-197
cd /data/apps/ryd-utc-admin
sudo cp -p ryd-utc-admin.jar.bak-<日期>-pre-<短哈希> ryd-utc-admin.jar.rollback.new
sudo mv -f ryd-utc-admin.jar.rollback.new ryd-utc-admin.jar
sudo systemctl restart ryd-utc-admin
```

回滚后验证三件事：
1. sha256 **回到台账记录的旧值**（不看文件名）
2. MainPID 变化、`Started UtcAdminApp` 标记 +1
3. `probe-utc-http.sh rollback` 与 `utc-http-before.txt` 比对 → `RESULT: PASS`

回滚同样受 §0 的重启窗口纪律约束。

## 8. 收尾

1. 归档全部原始输出到 `变更留痕/<日期>-<任务>/`
2. 更新 `指纹台账.md`：现役 sha256、新备份 sha256、MainPID、启动时刻；
   顺手补 §0 提到的**指纹缺口**
3. 清理远端 `/tmp` 本轮产物。**清理前先只读确认服务仍 active、8001 仍 LISTEN**，
   清理后复核文件确实不存在
4. 若沙箱拦下 `rm`（`SetNamedSecurityInfoW 失败: 5`）：**先只读复核远端真实状态**
   （文件是否还在、服务是否正常），再提权重跑。不要在状态未知时反复重试

## 9. 禁止事项

1. **禁止**未取基线就换包。
2. **禁止**未备份就 `mv`。
3. **禁止**改动 §0 列出的四样东西。
4. **禁止**改生产上的 jar 文件名或目录结构。
5. **禁止**用 `is-active` 单独作为健康判据。
6. **禁止**用整包 sha256 判断「同码/不同码」（见 SOP-00 §3.1）。
7. **禁止**在 HH:00–HH:04 窗口重启。
8. **禁止**内联远程命令：含 `$`、竖线、空格、中文的一律写成脚本 scp 上传执行。
   PowerShell 会本地求值 `$()`、吃掉 awk 的 `$N`、把 `\$f` 展开成 Windows 路径。
