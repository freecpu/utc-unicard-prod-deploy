# SOP-06：REQ-20261113-01 M5 回滚总纲（D3）

- 版本：v1.0（2026-11-18）
- 授权来源：批次计划 v1.0 §三 D3。**编写不需授权；任何回滚执行＝生产写，须用户显式授权（紧急停链除外：停链＝停止后续 G，本身零写）。**
- 定位：各 SOP 自带回滚节（SOP-01 §7／SOP-03 §7／SOP-04 A5/B5），本总纲只管**跨 G 的决策、顺序与锚汇总**。

---

## 1. 停链规则（任一 G 判据不过）

1. **立即停链**：后续 G 全部冻结，不得跳步继续（批次计划 §四）。
2. 只读取证：失败判据原始输出＋error 增量＋日志，先归档再动手。
3. 报用户：失败现象＋归因初判＋回滚建议；**回滚执行须授权**。
4. 回滚后该 G 标记 FAIL，修复须回开发侧另走流程，不得在生产上「再试一次」。

## 2. 回滚顺序（多 G 已通过、上游出问题时）

**逆序回滚**：先前端后后端（前端依赖后端键；后端先回会让新前端拿到旧响应）。

| 场景 | 动作 |
|---|---|
| G4 后发现 G3 后端问题 | 先回 G4（official-web dist，SOP-04 B5）→ 再回 G3（jar，SOP-03 §7） |
| G2 后发现 G1 后端问题 | 先回 G2（admin-web dist，SOP-04 A5）→ 再回 G1（jar，SOP-01 §7） |
| 仅前端问题 | 只回对应 dist，后端不动 |
| G5/G6/G7 | 已执行完毕（2026-11-20 / 11-21），首次部署无旧包可回；G7 回滚对象见 §3A.7 |
| G8 xxl-job-admin | **当前不可回滚**：机上只有一份现役 jar、零历史副本（§3A.9）。建档已完成，替换未发生 |

静态 dist 回滚**零重启**；jar 回滚每次 restart 都受各自 SOP 的窗口与留档纪律约束。
**同一时刻只重启一个服务**（批次计划 §四），跨机回滚也逐台串行。

## 3. 回滚锚汇总（R1 实测 2026-11-18 **换包前**基线；换包后新值见 §3A）

> ★ 阅读须知（2026-11-23 补）：本节各小节的「现役」二字均指 **2026-11-18 换包前**的状态
> （即当日换包的回滚目标）。换包后的**真实现役值**见 §3A.1~§3A.4，本节不复写现值 ——
> 同一数字只在一个地方维护，正是为了避免两处日后再次分叉。
> 本节历史行一字不改，保留为换包前快照。

### G1 utc-admin jar（UTC 机，SOP-01 §7）
- 现役＝回滚目标：`ba16cd657e6e645af24f14cc7a6fd34f802cdcbc441dd988cfc9ed055b904262`（108,561,064 B）
- 备份惯例：`/data/apps/ryd-utc-admin/ryd-utc-admin.jar.bak-<日期>-pre-<短哈希>`（G1 执行时产生）
- 不动四样：`.env`（`49d0eb8f…195b`）／`service.sh`（`2ffe750f…78b9`）／unit（`d0efa566…c77`）／custom.env（台账 §16）
- 重启窗口：禁 HH:00–HH:04（SOP-01 §0）

### G2 admin-web dist（UTC 机，SOP-04 A5）
- 回滚目标 index.html：`d9ef7d95dd29fb6611e1904c9cdd9b8217c3b684ccf050fa9037f2428170f6e7`（685 B）
- 主件：assets/index.508ff2fc.js＝`e6a04f93…c24dd`；assets/index.293e09e1.css＝`293e09e1…9734b2`
- 备份：`dist.pre-G2-<日期>`（G2 执行时产生，/data 同分区）

### G3 threeants jar（threeants 机，SOP-03 §7）
- 回滚目标：`bd24267bcf629b528fe6bc4bedaa2cc57faccd031b9e2a820769e8c194732b05`（93,135,977 B）
- 备份：`/data/log-archive/ryd-unicard/unicard-official-1.0.0.jar.pre-G3-<日期>`（chmod 600）
- ★ 回滚 restart 前**再留档 official.log**（`>` 截断，SOP-02 §5.1b）
- ★ unit 严禁动：回滚前后 sha 均须 = `4a928353dcb3aa78dd209d8ee11786f1e525a6ab6b0a10503e030eefb20767cc`；
  回滚后必重跑 `apply-agentflow-fix.sh verify`（SOP-02 §9）
- ★ N4 调用方＝本服务自身（台账 §13）：回滚后同样要做 N4 恢复观测

### G4 official-web dist（threeants 机，SOP-04 B5）
- 回滚目标 index.html：`4e9f978d785f235ab20ce9a5e4f9ac284d242d4a586d68241958035ef94c9c06`（483 B）
- 主件：umi.8376da82.js＝`892f3749…4d746`；umi.b7afafd6.css＝`01cc3e93…0e2b01`
- 备份：`/data/log-archive/ryd-unicard/dist.pre-G4-<日期>`（根分区 94% 满，备份禁落根分区）

### G5/G6/G7 agent-mp
- ★ 2026-11-23 勘误：本条原写「无锚（生产存在性未证实，SOP-05 挂起）」，**该结论已作废**。
  该机已于 2026-11-20 完成 G5 后端与 G6 前端首次部署、2026-11-21 完成 G7 路由修复；
  现役锚与回滚材料见 §3A.5 / §3A.6 / §3A.7。

## 3A. 回滚锚补记：2026-11-18 之后七次变更（2026-11-23 补）

> §3 记的是 **2026-11-18 换包前**的 R1 基线锚。该日同一天内完成了 G1~G4 四次换包，
> 因此 **§3 的四个锚在写完当天即成为历史值**。此后又发生 G5/G6/G7 三次变更。
> 本节按时间顺序补齐七次变更的「现役 / 回滚目标 / 备份材料 / 证据目录」，是回答「生产现在跑什么」的唯一入口。
> 锚值同时机读化于 `anchors/<project>.env`；两者必须一致，不一致时以本节＋台账原始记录为准，并立即修 anchors。
> 本节历史行不改，后续变更在同一位置继续追加。

### 3A.1 G1 utc-admin jar 换包（2026-11-18，commit 782425d）
- 现役：`f3ddcdb77beabb36ae3b1dc8c98366a235a65465e67843cd54337ee5950a9060`（108,562,566 B）
- 回滚目标：`ba16cd657e6e645af24f14cc7a6fd34f802cdcbc441dd988cfc9ed055b904262`（108,561,064 B）
- 备份材料：`/data/apps/ryd-utc-admin/ryd-utc-admin.jar.bak-20261118-pre-782425d`
- 验收：MainPID 993803／Started UtcAdminApp 14.227s／8001 LISTEN／`compare-utc-http RESULT: PASS`
- 证据目录：`变更留痕/20261118-G1-UTC换包/`（12 件）
- ★ 隐藏耦合：utc-admin 进程内**内嵌了 xxl-job 执行器**（`utc-job` 模块随 jar 打包，生产无独立执行器进程）。
  因此**本次换包同时更换了全部定时任务代码**；回滚时执行器与业务代码一并回退，不可分拆。

### 3A.2 G2 admin-web dist 换包（2026-11-18）
- 现役 `index.html`：`5daccd9d746c27c0d53eb6bb7256a2ef709ff6881704355a029325f592a03cd6`（685 B）
- 现役主件：`assets/index.05463381.js`＝`a502e558b9efb12a16b4b2f0f4f0acca32df65c4d384733a710dbc1dc12f3c81`（1,386,384 B）；
  `assets/index.293e09e1.css`＝`293e09e129cfcdad9dcb6f1dd13e88871a0e0ff548b92abfba17efcfdd9734b2`（411,184 B）
- 回滚目标：`index.html`＝`d9ef7d95dd29fb6611e1904c9cdd9b8217c3b684ccf050fa9037f2428170f6e7`（685 B）；
  `assets/index.508ff2fc.js`＝`e6a04f933c5925ab4be359741b7f93ed18dc00bcd858dfcb81505d7c609c24dd`（1,386,131 B）；css 同上
- 备份材料：`/data/html/ryd-utc-admin/dist.pre-G2-20261118`
- 证据目录：`变更留痕/20261118-G2-admin-web换包/`

### 3A.3 G3 threeants jar 换包（2026-11-18）
- 现役：`68b12477751ddfa6a74ba4b56cf032ab3420eaa84ffb6ea72dcb762da5063a6a`（93,136,188 B）
- 回滚目标：`bd24267bcf629b528fe6bc4bedaa2cc57faccd031b9e2a820769e8c194732b05`（93,135,977 B，10-28 基线）
- 备份材料：`/data/log-archive/ryd-unicard/unicard-official-1.0.0.jar.pre-G3-<日期>`（chmod 600）
- unit 禁令不变：sha 须恒为 `4a928353dcb3aa78dd209d8ee11786f1e525a6ab6b0a10503e030eefb20767cc`；
  回滚后必重跑 `scripts/apply-agentflow-fix.sh verify`（SOP-02 §9）
- 证据目录：`变更留痕/20261118-G3-threeants换包/`

### 3A.4 G4 official-web dist 换包（2026-11-18）
- 现役 `index.html`：`31670ccf920afe8ae16f7ae8330fa099654ad319dba9e0716a1f4edf8270ce90`（483 B）
- 现役主件：`umi.dc9bce91.js`＝`6c19b63505538274b74f0db31b7123265330d316ff1f79041c275ff5372fdb7b`（1,597,309 B）；
  `umi.b7afafd6.css`＝`01cc3e9371ca3bf9d9f7f3b342212edd74072a09784314c3b494f652520e2b01`（402,044 B）
- 回滚目标：`index.html`＝`4e9f978d785f235ab20ce9a5e4f9ac284d242d4a586d68241958035ef94c9c06`（483 B）；
  `umi.8376da82.js`＝`892f37496815e69294e80f42d2ccb1f4a7aaa3fbbe500892a64b27c0ede4d746`（1,596,941 B）；css 同上
- 备份材料：`/data/log-archive/ryd-unicard/dist.pre-G4-20261118`
- 证据目录：`变更留痕/20261118-G4-official-web换包/`（5 件）

### 3A.5 G5 agent-mp 后端首次部署（2026-11-20）
- 现役 jar：`b8bbeabc…`（93,013,309 B）—— 首次部署，**无旧包可回**（该机此前无部署史）
- 备份材料：无。回滚语义＝停容器＋保留现场（见 anchors/agent-mp.env，待随 G6/G7 一并转正）
- 证据目录：`变更留痕/20261119-G5G6首次部署方案/`（部署方案 v1.1 §二十三）
- 基准值：`Started` 耗时 40.813s，后续任何重启以此为对照

### 3A.6 G6 agent-mp 前端首次部署（2026-11-20）
- 现役五件：`index.html`＝`743a11b3…`（483 B）；`umi.65bb8d50.js`＝`3cc5a3e4…`（1,764,058 B）；
  `umi.730fc955.css`＝`c27effd1…`（402,044 B）；`static/help.c0d849ee.jpeg`＝`397e6f7e…`（42,392 B）；
  `static/menu.429358a6.png`＝`d12a11ac…`（10,140 B）
- 回滚目标：无（首次部署）
- 同批接线 nginx：`/etc/nginx/sites-available/agentmp.conf`＝`2e8fbc15e0ef0bf88c6ac7f4fcc44bdce3d4cbb9c9215df492cba6159dac40a8`（2,830 B）。
  该文件自此刻起为**禁动件**，后续 dist 替换一律零 reload
- 证据目录：`变更留痕/20261119-G5G6首次部署方案/`（部署方案 v1.1 §二十四）

### 3A.7 G7 agent-mp 前端路由修复（2026-11-21）
- 现役五件：`index.html`＝`bd337e78d9a3f783a396d791a49ac965ac05a7100ec01ec5e547b4e1c52a9f80`（483 B）；
  `umi.8f0720bb.js`＝`2fba8e738f2cd626b3fd9b2d1f428db2d6a8cb57421068b8ac87dce3bcc0586c`（1,764,230 B）；
  `umi.478b4bfc.css`＝`bfa59d934c915bcd879394630767036b9db3da91ba43be23cc6b3478c93b25d5`（402,044 B）；
  `static/help.c0d849ee.jpeg`＝`397e6f7e40f965cbff94c6b375445d5d177753089238937c699e8907ff95ae29`（42,392 B，与 G6 逐字节相同）；
  `static/menu.429358a6.png`＝`d12a11acd658c99bfe8c91fadb4a04146c6a07158a0acca244ecd75cdd653bdc`（10,140 B，与 G6 逐字节相同）
- 回滚目标：G6 五件（执行时已 `cp -a dist dist-bak-g7-20261121`，该目录即完整回滚材料）
- 备份材料：`/data/apps/agent-mp/dist-bak-g7-20261121`
- nginx 零改（conf 仍 `2e8fbc15…`／2,830 B，无 reload）；后端零改
- 证据目录：`变更留痕/20261119-G5G6首次部署方案/`（部署方案 v1.1 §二十五）
- ★ 本条已是 agent-mp 前端**第一次完整的 dist 替换实操**，步骤可直接抽为规程（SOP 待建）

### 3A.8 回滚材料命名规范（自本段起生效）

| 时期 | 命名 | 处置 |
|---|---|---|
| 历史（不改名） | `dist.bak`／`dist.20261026.bak`／`dist.pre-G2-20261118`／`dist.pre-G4-20261118`／`dist-bak-g7-20261121` | 保持原名（已在多处证据中被引用） |
| **新规** | `dist.pre-<批次>-<YYYYMMDD>`，例 `dist.pre-G8-20261123` | 全项目统一 |

- 只统一**新建**的备份目录名；历史目录**禁止改名** —— 改生产上的目录名本身就是风险动作，且会让既有证据里的路径全部失效。
- jar 类沿用各自 SOP 既有惯例，不改：`ryd-utc-admin.jar.bak-<date>-pre-<shorthash>`／`unicard-official-1.0.0.jar.pre-G3-<date>`。
- 回滚判据**永远只认 sha256，不认文件名**（§1 已有此条，此处重申适用于全部部署单元）。

### 3A.9 G8 xxl-job-admin 建档（2026-11-23，**无换包发生**）

> 本节登记的是一个此前从未建档的部署单元，不是一次变更。它的作用是把「现役是什么」纳入回滚体系，
> 并明确「现在**不能**回滚」—— 因为机上没有任何历史副本。

- 现役 jar：`4c94e30ab99dd5719f21b204ea831326ebaa1d205088f50c858fd30df8543d71`（46,859,824 B，mtime 2023-02-18 21:30:08）
- **回滚目标：无。** 机上 `jar_count=1`，自 2023-02-18 上线以来从未换过包，无任何 `.bak`。
  → `anchors/xxl-job-admin.env` 的 `ROLLBACK_FILES` **显式留空**、`STATUS=BLOCKED`（空值是有意的，不得用现役值填）。
  → 解阻＝建备份（SOP-08 §3），属生产写、须单独授权。
- 服务面：`xxl-job-admin.service`（`Type=forking`，`ExecStart=…/service.sh start`，`User=root`，`Restart=on-failure`），
  8082／`*:8082`，日志根 `/data/logs/xxl-job-admin`（不在应用目录下）。
- 禁动件三件：`service.sh`＝`2ffe750f…`／12,888 B（与 utc-admin **逐字节相同**）／`.env`＝`1b97338c…`／200 B／`custom.env`＝`7cf950d3…`／359 B
- 与执行器的耦合：执行器内嵌在 `ryd-utc-admin` 进程内（`127.0.0.1:8083`，无独立 utc-job 进程）。
  **换调度中心不动执行器；换执行器也不动调度中心；但跨大版本必须同批换**（SOP-08 §1.4）。
- ★ 本条同时纠正一个错了三年的结论：此前记作「脚本 nohup 拉起，非 systemd」，实测为 systemd 单元。
- 证据目录：`变更留痕/20261123-G8-xxl-job-admin基线采集/` ｜ 规程：`sop/SOP-08-xxl-job-admin-换包与回滚.md`

## 4. 数据层回滚（乙案，备用）

- 本 REQ V2 **无表结构变更**（生产实测 varchar(32) 已确认，STATE 裁定 #5）。
- 归位 SQL 备用，**仅回滚时执行且须显式授权**；jar/dist 回滚不自动触发数据回滚。
- 状态「9」容错为读侧映射，旧包读新数据无兼容问题（旧包对 9 走 UNKNOWN 兜底＝回到上线前形态）。

## 5. 回滚后统一验收（每个被回滚的 G）

1. sha256 回到 §3 锚值（逐字，不看文件名）。
2. jar 类：MainPID 变更＋启动日志点名＋端口 LISTEN＋HTTP 冒烟（禁 is-active）。
3. dist 类：index/主件 sha＋旧资源可达＋浏览器强刷。
4. 12 探针（UTC 机）＋probe-threeants-http（threeants 机）与 **before 基线**比对：
   回滚态应回到 before 形态（statusDesc 键消失＝预期，不是失败）。
5. error 增量归因；N4 节奏恢复（若动了 G3）。
6. 证据归档＋台账新节登记（历史行不改）＋Hub STATE 留痕＋报用户裁定后续。

## 6. 禁止事项

1. 禁止未授权执行回滚写操作（停链本身除外）。
2. 禁止顺链回滚（必须逆序：先前端后后端）。
3. 禁止同时重启两个服务。
4. 禁止删除任何 pre-G* 备份与失败现场（*.failed-*／留档日志）。
5. 禁止 threeants 回滚 restart 前不留档 official.log。
6. 禁止动 unit／vhost／.env／service.sh（回滚只回 jar/dist 本体）。
7. 禁止在生产上重试失败新包（回开发侧）。