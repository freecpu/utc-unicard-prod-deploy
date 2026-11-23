# deploy/ — 逐项目部署脚本（SOP 的机读副本）

- 建立：2026-11-23（阶段 A：仅锚文件＋基础设施，**尚无任何项目脚本**）
- 定位：`sop/` 是人读的权威步骤序列；本目录是它的**机读副本**。两者冲突时以 SOP 为准，
  但锚值（版本/字节/禁动件指纹）以 `anchors/*.env` 为准——它随每次换包在同一次提交内更新。
- ★ 不追求"通用化"：每个项目一套脚本、一套判据，互不继承。
  `_lib.sh` 只共享四类基础设施，**不含任何项目业务步骤**。

---

## 1. 目录

```
anchors/<project>.env        每项目一份：锚 + 坐标 + 禁动件 + 判据 + GAP
deploy/_lib.sh               基础设施：锚解析/lint/selftest/只读 ssh/写闸门/证据目录
deploy/<project>-<gx>.sh     项目脚本（阶段 B 起逐个落地；与 SOP 章节号一一对应）
变更留痕/<日期>-<GX>-<项目>/  脚本产出的证据目录（由 evi_new 创建）
```

已建锚：`utc-admin(G1)` `admin-web(G2)` `threeants(G3)` `official-web(G4)` `agent-mp(G5/G6·BLOCKED)`。

## 2. 四个安全机制（回答"每次操作不一样会不会不安全"）

| 机制 | 做法 | 拦住的错误 |
|---|---|---|
| 默认 dry-run | 不加 `APPLY=1` 只打印"将要执行什么 + 当前锚 vs 期望锚"，一行不写 | 误在未核锚的情况下动手 |
| 授权串 | 写阶段要求 `APPLY=1 CONFIRM=<GROUP>-<phase>-<YYYYMMDD>` | 授权跨次复用、靠记性守纪律 |
| 只读通道 | `ro_ssh` 固定 `-n -o BatchMode=yes`，并对 `mv/rm/cp/chmod/chown/systemctl restart/nginx -s/docker run/sed -i/>` 黑名单拦截 | 脚本写错时误写生产；ssh 吞后续脚本行 |
| 禁动守卫 | 换包前后对 `IMMUTABLE_FILES` 与 `UNIT_SHA`/`VHOST_SHA` 各采一次 sha，逐字比对 | "光说没改"——没改要有哈希证明 |

**不做的事**：不自动判定成功（只输出证据与建议，裁定仍由人）；不自动回滚（回滚同样是写，需授权串）；
不删除任何 `pre-G*` 备份与失败现场；不 `source` 锚文件（防止值里的 `<date>`、空格、`-Dk=v` 被 shell 解释）。

## 3. 锚字段口径

| 字段 | 含义 | 谁维护 |
|---|---|---|
| `CURRENT_FILES` | **现役**产物锚，precheck 判"无漂移"用 | 每次成功换包后更新 |
| `ROLLBACK_FILES` | **回滚目标**（上一已验证版本） | 换包时旧 CURRENT 移入 |
| `IMMUTABLE_FILES` | 禁动件（配置/启动脚本/.env） | 只增不改；改动须另立授权 |
| `UNIT_SHA`/`UNIT_FILE` | systemd unit 指纹与路径（G3 的 unit 含明文，只许脱敏读） | 同上 |
| `VHOST_SHA`/`VHOST_FILE` | nginx conf 指纹（静态替换零 reload 的证明） | 同上 |
| `STATUS` | `READY` / `BLOCKED` | 阻塞原因写 `BLOCKED_REASON` |
| `GAP=` | 已知缺口（可多行） | 补采后删除该行 |

三元组格式：`name=sha256:bytes`，空格分隔；bytes 未知写 `?`。

### 换锚规则（唯一合法路径）

1. 换包成功并验收 → 旧 `CURRENT_FILES` 整行移入 `ROLLBACK_FILES`；
2. 新锚写入 `CURRENT_FILES`；
3. `GAP=` 补采完的清零；
4. **与 SOP/台账修订、证据归档在同一次提交内完成**；台账历史行不动（新增节）。

## 4. 使用

```bash
bash deploy/_lib.sh lint all        # 锚形状校验（只读）
bash deploy/_lib.sh selftest        # 正控/负控：证明 lint 与只读黑名单不是瞎的
bash deploy/_lib.sh show utc-admin  # 打印现役/回滚锚
bash deploy/_lib.sh evi G1 utc-admin  # 建本次证据目录
```

项目脚本约定：

```bash
source "$(dirname "$0")/_lib.sh"
anchor_load utc-admin          # 加载锚（白名单键）
# 只读阶段：ro_ssh "$HOST_ALIAS" 'sha256sum ...'
# 写阶段前：wr_guard precheck|swap|verify|rollback
```

## 5. 阶段进度

| 阶段 | 范围 | 状态 |
|---|---|---|
| A | 锚文件 5 份 ＋ `_lib.sh`（lint/selftest/ro_ssh/wr_guard/evi） | ✅ 2026-11-23 |
| B | G4 official-web 脚本（最安全，先验证骨架） | 待做，需 DP-RO 只读实测 |
| C | G2 admin-web（同形态，验证"骨架复用、逻辑不共享"边界） | 待做 |
| D | G1 utc-admin（首个涉及 restart 的项目） | 待做 |
| E | G3 threeants（同机 5 服务 + unit 禁动 + log 留档，单独评审） | 待做 |
| F | G5/G6 agent-mp（需先有部署方案，SOP-05 由占位转正） | 阻塞 |
