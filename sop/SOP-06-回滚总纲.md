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
| G5/G6 | 挂起中（SOP-05），无回滚对象 |

静态 dist 回滚**零重启**；jar 回滚每次 restart 都受各自 SOP 的窗口与留档纪律约束。
**同一时刻只重启一个服务**（批次计划 §四），跨机回滚也逐台串行。

## 3. 回滚锚汇总（R1 实测 2026-11-18，全值见台账；回滚判据只看 sha256 不看文件名）

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

### G5/G6 agent-mp
- 无锚（生产存在性未证实，SOP-05 挂起）。

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