# SOP-03：threeants（S3 unicard-java-threeants）生产换包

- 版本：v1.0（2026-11-18）
- 授权来源：REQ-20261113-01《M5 生产上线批次计划》v1.0 §三 D1（用户 2026-11-18「核准，请开始」）。
  **本 SOP 的编写与侦察不需授权；其中每一个生产写步骤对应批次 G3，须用户单独显式授权后才可执行。**
- 执行分工（批次计划 §四）：默认＝主管出命令与探针，用户在生产机执行；如逐次授权远程执行须另行明示。
- 目标机：threeants 机（ssh 别名 `runyd-47-111-157-5`，坐标见本仓 `指纹台账.md` §3/§15）。
- 服务：`ryd-unicard-official`（unicard-official-1.0.0.jar，7003，`/usr/local/ryd-unicard/bin/`）。
- 衔接：本 SOP 只换 jar，**严禁动 unit**（方案 A 修复值在 unit，见 SOP-02 §9）。

---

## 0. 前置复核（全部只读，任何一项不符即停）

| # | 检查 | 通过条件 |
|---|---|---|
| 0-1 | 现役 jar sha256 | = `bd24267bcf629b528fe6bc4bedaa2cc57faccd031b9e2a820769e8c194732b05`（93,135,977 B，台账 §3；不等＝有漂移，先查清） |
| 0-2 | unit sha256（脱敏读） | = `4a928353dcb3aa78dd209d8ee11786f1e525a6ab6b0a10503e030eefb20767cc`（台账 §5，方案 A 后现役值） |
| 0-3 | `/data` 余量 | `df -h /data` ≥ 2G（留档 ≈750MB＋jar 备份 93MB＋余量；R1 实测余 93G） |
| 0-4 | 根分区余量 | `df -h /` ≥ 300MB（新包 staging 93MB 落 bin/ 同目录所需；R1 实测 94% 满仅 1.3G，**逼近红线时先停下向用户报告**） |
| 0-5 | 新包（S3 交付 jar） | 本地 sha256 已登记交付件；**class 级 sha256 与测试通过包判同源**（整包哈希无判别力，口径同 SOP-01）。★ 2026-11-18 已核验（台账 §21）：交付件＝测试部署仓 origin/main 提取，整包 sha=`68b12477…5063a6a`（93,136,188 B）与测试机在役 jar **逐字节同锚**（强于 class 级判据）；staging＝Hub var/tmp/s0-artifacts/threeants/bin/ |
| 0-6 | before 基线 | `probe-threeants-http.sh` before 已跑并归档（批次 R2/W6）；error 基线已在 |
| 0-7 | 回滚工具在机 | `/tmp/apply-agentflow-fix.sh` 存在（SOP-02 §7 第 4 条保留件；若已被清理须先重新 scp `scripts/apply-agentflow-fix.sh`） |
| 0-8 | 同机无关服务清单 | 复核 5 个严禁误伤的服务仍在（见 §8），确认本次只 restart `ryd-unicard-official` |
| 0-9 | ★新包 `${ENV:}` 空默认键清单 | 列出新包引入的全部空默认占位键，逐键确认注入点已在（现役已知仅 `OPENAPI_TOKEN`，unit Environment 已承载；新增键漏注入＝启动看似成功、定时任务每周期抛准入失败，fail-closed 判例口径）。★ 2026-11-18 已核验（台账 §21）：新 jar prod/base yml 占位键仅 `${OPENAPI_TOKEN:}` 无新增；新 jar 内 application-prod.yml 与生产现役 jar 内同文件机上哈希逐字相同（969c00c6…，内容不出机）；unit 两个 agent-flow -D 在位 |

> ⚠ unit 含明文 `OPENAPI_TOKEN`：只允许 `sudo sed 's/\(TOKEN=\).*/\1REDACTED/'` 脱敏后输出；
> 禁止整文件 cat、禁止 scp 回本仓、禁止入 git（SOP-02 §8 第 11/12 条）。

## 1. official.log 留档（★ 强制步，不可跳过 —— 2026-11-05 曾毁 502MB）

`ExecStart` 重定向是 **`>`（截断）**：每次 restart 都把 `official.log` 整份清零。

**留档必须落 `/data`**（根分区 94% 满仅 1.3G，747MB 留档放根分区会打爆磁盘）：

```bash
ssh runyd-47-111-157-5 'sudo mkdir -p /data/log-archive/ryd-unicard && \
  sudo cp -p /usr/local/ryd-unicard/var/official.log \
  /data/log-archive/ryd-unicard/official.log.pre-G3-<日期> && \
  sudo stat -c "%s %n" /usr/local/ryd-unicard/var/official.log \
  /data/log-archive/ryd-unicard/official.log.pre-G3-<日期>'
```

通过条件：**源与留档字节数完全一致**（cp 期间日志仍在写，若差值明显须停手复采）。
747MB 的 cp 约需数十秒，先做 0-3。留档 sha256 双端核对后登记台账。

> ⚠ 严禁把留档放 `/usr/local/ryd-unicard/var/`（根分区）；SOP-02 §5.1b 的旧路径示例在本机已不适用。
> ⚠ 若用户判断历史日志无保留价值，也必须在动手前明确说出来并获用户确认，不能默认跳过。

## 2. 现役 jar 备份（★ 回滚唯一来源）

```bash
ssh runyd-47-111-157-5 'sudo cp -p /usr/local/ryd-unicard/bin/unicard-official-1.0.0.jar \
  /data/log-archive/ryd-unicard/unicard-official-1.0.0.jar.pre-G3-<日期> && \
  sudo chmod 600 /data/log-archive/ryd-unicard/unicard-official-1.0.0.jar.pre-G3-<日期> && \
  sudo sha256sum /data/log-archive/ryd-unicard/unicard-official-1.0.0.jar.pre-G3-<日期>'
```

通过条件：备份 sha256 = 0-1 的现役值（逐字比对）。
`chmod 600`：jar 内含第三方明文凭据（TD-20261105-03），不得放宽权限。
**本备份在 G3 核验通过且用户确认前严禁删除。**

## 3. 新包 staging ＋ 原子替换

★ 新包必须落 **bin/ 同目录**（同分区），`mv -f` 才是原子 rename；
跨分区（如先落 /data 再 mv）＝ copy+delete，非原子且打爆根分区风险。
根分区余 1.3G > 新包 ≈93MB，可容（0-4 已复核）。

```bash
# 本地 → 机上 staging（用户执行或逐次授权后远程执行）
scp <新包本地路径> runyd-47-111-157-5:/usr/local/ryd-unicard/bin/unicard-official-1.0.0.jar.new

ssh runyd-47-111-157-5 'sha256sum /usr/local/ryd-unicard/bin/unicard-official-1.0.0.jar.new'
# 必须等于交付件登记 sha256；不等＝传输损坏，重传，严禁继续
```

替换（G3 授权后的核心写操作，与 §4 restart 连着做，窗口最短化）：

```bash
ssh runyd-47-111-157-5 'sudo chown nlxq:nlxq /usr/local/ryd-unicard/bin/unicard-official-1.0.0.jar.new && \
  sudo mv -f /usr/local/ryd-unicard/bin/unicard-official-1.0.0.jar.new \
  /usr/local/ryd-unicard/bin/unicard-official-1.0.0.jar && \
  sha256sum /usr/local/ryd-unicard/bin/unicard-official-1.0.0.jar'
```

> ⚠ `mv -f`，**GNU mv 没有 `-a`**（SOP-02 §5.1 血泪条款）。
> ⚠ 属主对齐现役（nlxq:nlxq，以 0 轮实测为准）；unit 以 root 运行，属主不阻断启动但保持惯例。

## 4. 重启（★ 唯一允许 restart 的 unit）

```bash
ssh runyd-47-111-157-5 'sudo systemctl reset-failed ryd-unicard-official; \
  sudo systemctl restart ryd-unicard-official'
```

- **严禁** `daemon-reload`、严禁改 unit 任何一行（方案 A 的 `-D` 在 unit L16，动了＝fail-closed 复活，SOP-02 §9）。
- **严禁** restart 同机其他任何服务（§8 清单）。
- `reset-failed` 是幂等保险，不是「已规避限流」的证据（SOP-02 §5.3：生产启动 27.4s > 限流窗 10s）。

## 5. 启动判据（restart 后 60s 窗内全绿才算过）

| # | 判据 | 命令要点 | 通过条件 |
|---|---|---|---|
| ① | 端口 LISTEN | `netstat -tlnp` grep 7003（**本机无 ss**） | = 1，唯一硬健康信号 |
| ② | 启动日志点名 | `grep -n Started /usr/local/ryd-unicard/var/official.log` | 出现 `Started OfficialApplication`（新日志，restart 后从零起） |
| ③ | HTTP 冒烟 | `curl -s -o /dev/null -w "%{http_code} %{size_download}" http://127.0.0.1:7003/api/web/iccid/123456` | **800 / 23B**（R1 实测基线） |
| ④ | MainPID | `systemctl show ryd-unicard-official -p MainPID` | ≠ 23774（旧 PID），且 cmdline 含新 jar 路径 |
| ⑤ | unit 零漂移 | unit sha256（脱敏读） | 仍 = `4a928353…67cc`（逐字） |
| ⑥ | -D 仍在 | `ps` cmdline | `-Dutc.agent-flow-coefficient=50 -Dutc.agent-flow-recharge-min=0` 均在，且在 jar 路径**之前** |

> ⚠ **禁止用 `is-active` 作健康判据**（Type=simple + Restart=always，恒不可信，SOP-02 §5.4）。
> ⚠ 生产完整启动实测 ≈27s：60s 窗内未见 ①②，即视为失败进入 §7 回滚评估，不得干等。
> ⚠ 远程命令一律写脚本 scp 上传执行（SOP-02 §8 第 8 条：内联 `$`/竖线/双引号会被 PowerShell 剥壳）。

## 6. 换包后必验（判据全绿后逐项做，缺一项不得宣称 G3 通过）

1. **★ SOP-02 §9 verify 重跑**（换包后强制条款）：
   ```bash
   ssh runyd-47-111-157-5 'TA_UNIT=ryd-unicard-official \
     bash /tmp/apply-agentflow-fix.sh verify'
   ```
   判据：`coef_exact=1`、`rmin_exact=1`、`port_listen=1`、`unit_sha256` = 台账 §5 现役值。
   `VERIFY_FAIL` 当场查清，不得留到业务报错。
2. **probe-threeants-http.sh after**：与 before 全列对比。预期差异**只有一类**：
   卡详情/LIST 响应新增 `statusDesc` 键（本 REQ 目标增量）；其余任何 diff 须 100% 归因。
3. **★ N4 恢复观测**（本次换包重启的正是 N4 调用方自身，台账 §13 定案）：
   restart 后在 UTC 机跑 `probe-utc-traffic.sh`，确认 N4（8001 openapi）调用恢复每分钟节奏
   （before 基线：今日计数 660、每分钟触发）。中断 > 5 分钟＝异常，查 threeants 侧。
4. **error 增量归因**：threeants 侧新 official.log 与 UTC 机 `error-noise-rate.sh`（传换包时刻 HH:MM:SS 第 2 参），
   增量 100% 归因；UTC 机 01:00 NO_TYPE 脉冲 2290 条为既有形态，归因时排除（R2 基线口径）。
5. **statusDesc 实证**（G4 的硬前置）：`probe-statusdesc.sh` 用运行时传入的真实生产卡号在**机上**比对
   状态 9/28082 等映射，出参**只带掩码卡号与 statusDesc 文本**；真实卡号与完整响应严禁出机、严禁入 Hub/git。
   实证结果（非空 statusDesc）经主管核验后才解锁 G4。

## 7. 回滚（任一判据不过 → 停链，报告用户后执行；不得跳步继续 G4）

1. **回滚 restart 前再做一次 §1 留档**（回滚同样触发 `>` 截断；此时日志虽短，纪律不减）。
2. 备份回替（同分区原子 mv 不适用——备份在 /data，跨分区 cp 可接受：服务已 DOWN，无原子性诉求）：
   ```bash
   ssh runyd-47-111-157-5 'sudo cp -p /data/log-archive/ryd-unicard/unicard-official-1.0.0.jar.pre-G3-<日期> \
     /usr/local/ryd-unicard/bin/unicard-official-1.0.0.jar && \
     sudo chown nlxq:nlxq /usr/local/ryd-unicard/bin/unicard-official-1.0.0.jar && \
     sha256sum /usr/local/ryd-unicard/bin/unicard-official-1.0.0.jar'
   ```
   sha 必须回到 `bd24267b…32b05`（逐字）。
3. `reset-failed` + restart（同 §4，仍只动这一个 unit）。
4. 复验：§5 判据（④ 改为「PID 再次变更」）＋ §6 第 1 条 verify 重跑 ＋ N4 恢复观测。
5. 回滚后**新包与失败证据保留**（.new 已不存在则留 staging sha 记录），供归因；备份继续保留。
6. 台账登记回滚事实＋原因；G4~G6 全链冻结待主管裁定。

## 8. 同机严禁误伤清单（R0b 实测，2026-11-18）

| 服务 | 端口 | 路径栈 |
|---|---|---|
| unicard api-sp | 9002 | /usr/local/unicard/bin/（旧栈） |
| unicard schedule | 9001 | /usr/local/unicard/bin/（旧栈） |
| unicard api-official | 9003 | /usr/local/unicard/bin/（旧栈，**勿与 ryd-unicard-official 7003 混淆**） |
| notice | 5001 | — |
| notice-test | 6001 | — |

任何 systemctl/cp/mv/rm 命令必须显式点名 `ryd-unicard-official` 或 `/usr/local/ryd-unicard/` 全路径；
**禁止**通配 `unicard*`、禁止 `systemctl restart` 不带 unit 名。

## 9. 禁止事项（本 SOP 专属，叠加 SOP-02 §8 全部条款）

1. 禁止未做 §1 留档就 restart（含回滚 restart）。
2. 禁止把留档/备份落根分区（94% 满）。
3. 禁止动 unit / daemon-reload / 清理 unit 里的 `-D`。
4. 禁止新包跨分区 mv 冒充原子替换；禁止 sha 未核对就替换。
5. 禁止删除 §2 备份（用户确认前）。
6. 禁止真实卡号/完整卡详情响应出机入 Hub/git（掩码出参例外）。
7. 禁止跳过 §6 任何一项宣称 G3 通过；禁止 G3 未实证 statusDesc 就启 G4。
8. 禁止据本 SOP 顺手处理同机其他服务或清理 bin/ 历史包。

## 10. 收尾（G3 通过后）

1. 证据归档 `变更留痕/<日期>-G3-threeants换包/`（留档/备份/替换/判据/verify/after 探针/N4/error 归因/statusDesc 掩码实证）。
2. 台账更新：jar 新 sha256＋字节数＋mtime、MainPID、启动时刻、留档与备份坐标；历史行不改，新节登记。
3. 机上痕迹清理：/tmp 脚本即 rm（**保留** §2 备份、§1 留档、`/tmp/apply-agentflow-fix.sh` 回滚工具）。
4. Hub STATE 留痕一行＋G4 解锁申请（附 statusDesc 实证给主管核验）。