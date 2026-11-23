# deploy/ — 逐项目部署脚本（SOP 的机读副本）

- 建立：2026-11-23（阶段 A：仅锚文件＋基础设施，**尚无任何项目脚本**）
- 定位：`sop/` 是人读的权威步骤序列；本目录是它的**机读副本**。两者冲突时以 SOP 为准，
  但锚值（版本/字节/禁动件指纹）以 `anchors/*.env` 为准——它随每次换包在同一次提交内更新。
- ★ 不追求"通用化"：每个项目一套脚本、一套判据，互不继承。
  `_lib.sh` 只共享四类基础设施，**不含任何项目业务步骤**。

---

## 1. 目录

```
anchors/00-worktree归属表.md      一个 worktree = 一个项目 = 一个锚（防按仓名混为一谈）
anchors/<project>.env        每项目一份：锚 + 坐标 + 禁动件 + 判据 + GAP
deploy/_lib.sh               基础设施：锚解析/lint/selftest/只读 ssh/写闸门/证据目录
deploy/<project>-<gx>.sh     项目脚本（阶段 B 起逐个落地；与 SOP 章节号一一对应）
变更留痕/<日期>-<GX>-<项目>/  脚本产出的证据目录（由 evi_new 创建）
```

已建锚（6 份，截至 2026-11-23）：`utc-admin(G1)` `admin-web(G2)` `threeants(G3)` `official-web(G4)` `agent-mp(G5-G7)` `xxl-job-admin(G8·BLOCKED)`。

★ 两处易误读：
- `agent-mp` 的 `MODE=static-dist-swap` **只覆盖前端 dist**；后端 jar 由 G5 首次部署，尚无独立 SOP，且其 `PROBE=none`。
- `xxl-job-admin` 的 `BLOCKED` 是「已部署 1373 天但机上无任何回滚副本」，**不是「未部署」** —— 详见 SOP-08。
- ★ **`official-web` 与 `agent-mp` 是同一 git 仓（`unicard-official-nodejs`）的两个 worktree**，不是一个仓的两个名字。
  归属、推送目标与构建落点见 `anchors/00-worktree归属表.md`。**按仓名下结论会串项目**（2026-11-23 已实际发生一次）。

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

## 5. 构建与部署的边界（硬规则）

**结论：部署脚本不含构建。** 构建＝交付件生成；部署＝交付件准入＋原子替换＋判据验证。两件事风险面不同，合并会同时破坏两者的可审计性。

### 为什么

| 若把构建放进部署脚本 | 后果 |
|---|---|
| 脚本自己 `npm install && vite build` | 产物随当天依赖解析漂移（`package.json` 全是 `^` 范围，一次 install 可能换掉整棵树） |
| 产物无 commit 绑定 | 事后无法回答"生产上跑的是哪个 commit 构建的" |
| 在生产机现场构建 | 把 node/vite/esbuild 版本契约搬上生产；本仓已有先例——已核验产物被后续 clean 构建覆盖，证据链断裂 |
| 无法做可复现性校核 | 校核需要"另一环境重建同一份再比"，只能在离线做 |

### 实测依据（2026-11-23，G2）

- 同一环境重建父提交 `48ccdcb`：与生产现役 **65/65 逐字节完全一致**（零漂移）→ 构建**可复现**，前提是 commit＋lock＋node＋vite＋esbuild 全固定。
- 再构建 HEAD `dcf86e0`（仅 1 行改动）：ADD 40 / DEL 40 / CHG 1 / SAME 24 → 40 个 chunk 换名是 Vite 3 的 **hash 级联**（chunk 名含依赖 chunk 文件名），不是 40 处功能变动。
- ★ 这条结论无法靠读代码得出，只能靠**双向重建**证明。所以 R-BUILD-5 是硬规则。

### 五条硬规则

| 编号 | 规则 | 违背后果 |
|---|---|---|
| R-BUILD-1 | 部署脚本内**禁止** `npm install`/`npm ci`/`vite build`/`mvn package` 等构建命令 | 产物不可追溯，锚失效 |
| R-BUILD-2 | 产物必须随附 `BUILD-INFO`（commit、node/npm/vite/esbuild、构建主机、时间）与 `SHA256SUMS.txt` | 无法证明来源 |
| R-BUILD-3 | 产物须落到**带 commit 标记的独立目录**（如 `dist-<短commit>`），生成后立刻算 sha 固化；禁止在原 `dist/` 反复构建 | 前一份证据被覆盖 |
| R-BUILD-4 | 脚本只做**准入校验**：三件 sha/字节逐字比对锚、形态校验（`index.html` 在根、`./assets/` 相对引用、无反斜杠条目、`static/`＋`table.json` 在）、`BUILD-INFO` commit 与预期一致 | 拿错包上生产 |
| R-BUILD-5 | 换包前做**可复现性抽检**：父提交同环境重建须与现役逐字节一致；不一致先查环境契约，不换包 | 把环境漂移当成业务改动 |

### 唯一例外通道

仅当**生产机是唯一可用构建环境**时（G1/G3 后端 jar 属此列），允许在同一脚本内构建，但必须：

1. 构建前记录 `git rev-parse HEAD` 与 lock 文件 sha；
2. 构建后**先固化 sha 清单到证据目录，再做准入校验**，通过才允许替换；
3. 禁止 `install`；依赖变更单独走一次"依赖升级"评审。

### 七节点适用性

| 节点 | 构建位置 | 脚本含构建 |
|---|---|---|
| G2 admin-web | 本地（可复现） | 否 |
| G4 official-web | 本地（umi，Node16+cross-env） | 否 |
| G1 utc-admin | 机上 mvn（jar 108MB，class 可复现、jar 时间戳不可） | **是（例外通道）** |
| G3 threeants | 同上 | **是（例外通道）** |
| G5/G6 agent-mp | 前端本地（umi）；后端已部署但无 SOP | 前端否／后端未定 |
| G8 xxl-job-admin | **本仓无源码、无 pom → 只能部署不能构建** | 否（交付件须外部定源） |

## 6. 失败语义（分级退出码）

失败**只停机、保留现场、打印人工回滚指令**；绝不自动回滚、不删备份。

| 码 | 含义 | 停产点 |
|---|---|---|
| 0 | 正常 | — |
| 2 | 参数/用法错误 | 未接触任何机器 |
| 10 | 前置校验失败 | 锚漂移／禁动件不符／GAP 未清／前置未满足 |
| 20 | 交付件准入失败 | sha/字节/形态/来源不符 |
| 30 | 备份失败 | 未备份成功绝不允许替换 |
| 40 | 替换失败（含未捕获错误） | 现场保留，人工判定 |
| 50 | 判据验证失败 | **替换已发生**，人工判定是否回滚 |
| 60 | 证据落盘失败 | 停机 |
| 70 | 并发锁冲突 | 停机 |

项目脚本用法：

```bash
source "$(dirname "$0")/_lib.sh"
anchor_load admin-web
step "$EX_PRE"   "核对现役锚"  -- precheck_anchor
step "$EX_BACKUP" "备份现役"   -- do_backup
step "$EX_SWAP"   "原子替换"   -- do_swap
step "$EX_VERIFY" "判据验证"   -- do_verify
```

写阶段可再叠加 `strict`（`set -eE` + ERR trap 留证到 `$EVI_DIR/errors.log`）。

## 7. 阶段进度

| 阶段 | 范围 | 状态 |
|---|---|---|
| A | 锚文件 6 份 ＋ `_lib.sh`（lint/selftest/ro_ssh/wr_guard/evi） | ✅ 2026-11-23 |
| B | G4 official-web 脚本（最安全，先验证骨架） | 待做，需 DP-RO 只读实测 |
| C | G2 admin-web（同形态，验证"骨架复用、逻辑不共享"边界） | 待做 |
| D | G1 utc-admin（首个涉及 restart 的项目） | 待做 |
| E | G3 threeants（同机 5 服务 + unit 禁动 + log 留档，单独评审） | 待做 |
| F | G5/G6 agent-mp（需先有部署方案，SOP-05 由占位转正） | 阻塞 |
