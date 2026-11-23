# utc-unicard-prod-deploy — 生产部署操作仓

本仓是 **UTC / unicard 生产环境的部署操作与取证仓**，不是应用代码仓。
它承载三类东西：**可复跑的探针脚本**、**逐次变更的原始证据**、**给操作者照抄的 SOP**。

> 本仓刻意与 `utc-unicard-test-deploy`（测试环境总控）分开：
> 生产与测试的路径体系、systemd 单元名、配置注入形态都**不可互套**，
> 混在一个仓里迟早会有人把测试机的命令贴到生产上。

---

## 1. 仓库结构

```
utc-unicard-prod-deploy/
├── README.md              ← 本文件
├── 归属矩阵.md             ← 谁负责什么、哪台机器归谁操作、授权边界
├── 指纹台账.md             ← jar / unit / 外置配置的 sha256 权威记录（回滚判据）
├── .gitignore
├── sop/
│   ├── SOP-00-构建规范.md          ← 产物怎么来、命名与指纹怎么记
│   ├── SOP-01-utc-admin-生产换包.md ← 换 jar 的逐步操作 + 判据 + 回滚（G1）
│   ├── SOP-02-threeants-配置注入.md ← -D 注入的逐步操作 + 判据 + 回滚（已执行；§9 换包后必重跑 verify）
│   ├── SOP-03-threeants-生产换包.md ← threeants jar 换包（G3；留档落 /data＋同分区原子 mv＋严禁动 unit）
│   ├── SOP-04-静态dist替换.md      ← admin-web Vite（G2）＋official-web umi（G4）；零重启零 reload＋旧资源并留
│   ├── SOP-05-agent-mp-生产换包-占位.md ← ★占位件已过期：G5/G6 于 2026-11-20 执行完毕（勘误段待补）
│   └── SOP-06-回滚总纲.md          ← 跨 G 停链/逆序回滚/锚汇总（D3）
├── scripts/               ← 全部只读探针与验证脚本（可复跑）
└── 变更留痕/               ← 每次变更一个目录，内含原始输出与验证记录
```

## 2. 机器与单元速查

| 角色 | SSH 别名 | 主机 | systemd 单元 | 端口 |
|---|---|---|---|---|
| 生产 UTC | `runyd-47-96-163-197` | 47.96.163.197:62211 (user `runyd`) | `ryd-utc-admin.service` | 8001（context-path `/manage`） |
| 生产 threeants | `runyd-47-111-157-5` | 47.111.157.5:62211 (user `runyd`) | `ryd-unicard-official.service` | 7003 |
| 生产第四台机 agent-mp | `runyd-223-4-12-235` | 223.4.12.235:22 (user `runyd`) | —（docker compose，非 systemd） | 7013（仅绑回环，对外经 nginx 443） |
| 测试机 threeants | `47.97.47.23` | 47.97.47.23:22 (user `root`) | `unicard-test-threeants-official.service` | 7003 |

**生产两台都必须走 SSH 别名**（端口 62211、用户 runyd）。直连 IP 的 22 端口会超时。

静态前端生产坐标（R0 实测 2026-11-18，台账 §11/§12）：

| 站点 | 机 | 入口 | 静态根 | 形态 |
|---|---|---|---|---|
| admin-web（S2） | UTC 机 | openresty 8000 utc.nlxq.net（vhost `servers/ryd-utc.conf`） | `/data/html/ryd-utc-admin/dist` | Vite（assets/index.<hash>.js） |
| utc-sp-web | UTC 机 | openresty 8002 sp.threeants.cn（vhost `sp.threeants.cn.conf`） | `/data/html/ryd-utc-sp-admin/dist` | 未采 · ★**未建档**（后期纳入） |
| official-web（S4） | threeants 机 | nginx 443 threeantsonline.nlxq.net（vhost `servers/threeantsonline.nlxq.net.conf`） | `/usr/local/ryd-unicard/bin/dist/` | umi；`/api/web/`→127.0.0.1:7003 |
| agent-mp（S5/S6 后端＋S6 前端） | 第四台机 | nginx 443 www.xhc123.work（vhost `/etc/nginx/sites-available/agentmp.conf`） | `/data/apps/agent-mp/dist` | umi；`/api/`→127.0.0.1:7013 |

★ 2026-11-23 勘误：上一版此表把 agent-mp 写成「未证实／三台可达机均未见」，**该结论已作废**。
第四台机已于 2026-11-20 完成后端与前端首次部署、2026-11-21 完成 B 端路由修复，全部验收闭合；
证据见 `变更留痕/20261119-G5G6首次部署方案/00-部署方案-v1.1-已裁.md` 与 `指纹台账.md` §24/§25。
原「未证实」的判断依据是 `sop/SOP-05`（v0.3 占位件，2026-11-18 写），该文件此后从未更新 —— 教训见 §3 铁律 4。

⚠ 两机 vhost 均在 `include servers/*.conf` 子目录，只扫主 conf 会漏。
⚠ threeants 机根分区 94% 满（仅 1.3G）：留档/备份一律落 /data；同机另有 5 个 java 服务严禁误伤（SOP-03 §8）。

两台生产机的 systemd 都是 **219**（CentOS 7），实测差异见 SOP 里的「环境差异」段：
`systemctl show -p KEY --value` 不支持、`NRestarts` 属性不存在、
`StartLimitIntervalUSec` 叫 `StartLimitInterval`。**脚本一律用 `-p KEY | cut -d= -f2`。**

## 3. 四条铁律

1. **生产默认只读。** 任何写操作（改 unit、换 jar、重启服务、删文件）都必须先取得
   用户对该**具体动作**的显式授权。授权不按机器给，按动作给。
2. **判据不能只看进程活着。** `Type=simple` + `Restart=` 下 systemd 在 exec 成功那一刻
   就记 `active`，之后应用绑定失败、JVM 退出、再拉起，`is-active` 会在 active/activating 间跳，
   **恒定不可作健康判据**。硬信号只有两个：**端口 LISTEN**、**日志里点名的属性名**。
3. **0 命中不可当否定结论。** 空结果比错误结果更危险 —— 两边都空会得出「相同」的假阳性。
   本仓所有比对脚本都带空结果 FATAL 守卫；告警类脚本必须带正控 selftest
   （`scripts/audit-tmp-creds.sh` 就是被 selftest 抓出过真缺陷的）。
4. **执行完必须回写，否则视为未完成。** 每次生产变更验收闭合后，必须在**同一次提交内**完成三件回写：
   （a）`sop/` 对应规程按实际执行修订；（b）`anchors/<project>.env` 的 CURRENT 移入 ROLLBACK、新值写入 CURRENT；
   （c）`变更留痕/00-索引.md` 登记本次批次。三者缺一，本次变更状态记 `未完成`，不得声称已上线。
   > 立此条的由来（2026-11-23）：本仓 `sop/` 记的是「某一次怎么做」，而事实一直在往前跑；
   > `变更留痕/` 记着真相，却没人从它反哺 `sop/` 与 `anchors/`。结果是 2026-11-18 同日完成 G1~G4 四次换包后，
   > **SOP-06 §3 的锚表当天即过期**、`anchors/utc-admin.env` 的现役值停留在 11-04、`SOP-05` 的「空白规划机」结论与
   > 11-20 的实际上线相反。**权威文档过期比没有文档更危险：没有文档会去查，过期文档会被直接采信。**

## 4. 脚本清单

| 脚本 | 用途 | 读/写 |
|---|---|---|
| `probe-utc-http.sh` | UTC 12 探针 HTTP 基础回归（换包前后各跑一次做 diff） | 只读 |
| `probe-threeants-http.sh` | threeants 6 探针 HTTP 基础回归（G3 前后 diff；纯 GET 零写库，sha_norm 同口径） | 只读 |
| `probe-statusdesc.sh` | 卡详情 statusDesc 实证（G4 硬前置；真实卡号运行时传入，出参仅掩码，完整响应即毁） | 只读 |
| `probe-utc-runtime.sh` | UTC 运行态取证（jar 指纹、PID、端口、启动时刻） | 只读 |
| `probe-utc-traffic.sh` | UTC 流量/调用方观测 | 只读 |
| `compare-utc-http.sh` | 两次 HTTP 探针结果的 diff | 只读 |
| `analyze-error-delta.sh` | 换包后 error 日志增量归因 | 只读 |
| `error-noise-rate.sh` | error 日志噪声率基线（判断增量是否属既有噪声） | 只读 |
| `probe-threeants-config.sh` | threeants 配置形态取证（unit、cmdline、yml 搜索路径） | 只读 |
| `probe-prod-portability.sh` | **搬到生产前必跑**：systemd 版本 / journal 是否有内容 / `/proc` 权限 / Restart 策略 | 只读 |
| `verify-d-injection.sh` | `-D` 注入通路五模式验证（neg/neg2/neg3/pos/restore） | **写**（改 unit + 重启） |
| `compare-jar-manifest.sh` | jar 外层 (长度,CRC-32,条目名) 全清单指纹 | 只读 |
| `inspect-jar-manifest.sh` | 清单**判别力**自检（防「清单相同但覆盖不到关心对象」） | 只读 |
| `compare-nested-jar.sh` | 递归下钻嵌套模块 jar + pom 归一化哈希 | 只读 |
| `compare-jar-class.sh` | 单 class 比对（已被 manifest 方案取代，保留备查） | 只读 |
| `run-jar-cmp.sh` | 从 unit 解析 jar 路径的薄封装（含相对路径处理） | 只读 |
| `read-prod-agentflow.sh` | 只读查询生产 `t_agent_flow`（凭据不回显、不落盘） | 只读 |
| `audit-tmp-creds.sh` | 明文凭据审计（5 级分类 + selftest 正控/负控）；**提交前门禁** | 只读 |
| `audit-pii.ps1` | PII 审计（真实卡号/长数字串）；**提交前门禁**，REAL 必须为 0 | 只读 |
| `diag-cred-shape.sh` | 掩码查看凭据命中上下文（用于人工复核误报） | 只读 |
| `watch-cline.sh` | C 线事件观察（退卡/周期更新） | 只读 |

## 5A. 锚文件与部署脚本（anchors/ ＋ deploy/）

2026-11-23 新增。定位＝**SOP 的机读副本**，不是新规程、不替代 SOP：
`sop/` 仍是人读的权威步骤，`anchors/` 是其中"锚值／坐标／禁动件／判据"的事实源，
`deploy/` 只放基础设施与（阶段 B 起）逐项目脚本。详见 `deploy/README.md`。

| 路径 | 作用 |
|---|---|
| `anchors/<project>.env` | 每项目一份：CURRENT（现役）／ROLLBACK（回滚目标）／IMMUTABLE（禁动件）／服务面／判据／GAP |
| `deploy/_lib.sh` | 唯一共享件：锚解析、lint、selftest、只读 ssh、写授权闸门、证据目录；**不含项目业务步骤** |
| `deploy/<project>-<gx>.sh` | 逐项目脚本（待建；与 SOP 章节一一对应） |

- 校验：`bash deploy/_lib.sh lint all`；自检：`bash deploy/_lib.sh selftest`。
  无 selftest 的 CLEAN 视为假阴性（同 §5 凭据门禁口径）。
- ★ **锚分两组**：2026-11-18 四组换包后，SOP-06 §3 登记的只是"回滚锚"，现役值在台账 §22.x。
  `anchors/*.env` 同持两组；锚值以它为准，且随每次换包在同一次提交内更新。
- 未采字段写 `?` 并计入 GAP：**不阻断 dry-run，阻断 apply**。
- 阶段：A（锚＋基础设施）已完成；B 起一项目一批，顺序 G4 → G2 → G1 → G3 → G5/G6（末项阻塞）。

## 5. 提交纪律

- `git add` 前先 `git status --short` 核对清单，只提交本次任务相关文件。
- **提交前必须跑凭据门禁**：
  ```bash
  bash scripts/audit-tmp-creds.sh selftest          # 先证明工具不是瞎的
  AUDIT_DEPTH=99 bash scripts/audit-tmp-creds.sh .  # 再扫全树，HARDCODED 必须为 0
  ```
  selftest 不过时，`CLEAN` 结论**无效**（可能是假阴性）。
- 证据文件里只允许出现**长度与哈希**，不允许出现凭据正文。
  已归档的取证输出里，凭据一律以 `REDACTED` 或 `username_len = 4  password_len = 11`
  这类形态留存。
- 远程命令**不内联**：含 `$`、竖线、空格、中文的一律写成脚本 `scp` 上传执行。
  PowerShell 会本地求值 `$()`、吃掉 awk 的 `$N`、把 `\$f` 展开成 Windows 路径。

## 6. 当前未闭环事项

见 `指纹台账.md` 末尾的「技术债与未闭环」段，以及 `变更留痕/` 下各次变更的验证记录。

- ~~生产 threeants 预划拨 fail-closed 等待方案选型与重启授权~~ ✅ 方案 A 已于 2026-11-05 执行
  （台账 §4/§5；代价＝配置漂移，根治仍是方案 B）。**后续任何换包/动 unit 必重跑 verify（SOP-02 §9）**。
- ★ 当前主线：REQ-20261113-01 M5 生产上线批次 —— **G1~G7 已全部执行完毕并验收闭合**
  （G1~G4 于 2026-11-18；G5/G6 于 2026-11-20；G7 于 2026-11-21）。批次计划正本在 Hub
  `需求/归档/REQ-20261113-01/`；侦察与基线证据见 `变更留痕/20261118-R0R1R2-M5侦察与基线/`；
  逐次变更的锚与目录对照见 `变更留痕/00-索引.md`。
