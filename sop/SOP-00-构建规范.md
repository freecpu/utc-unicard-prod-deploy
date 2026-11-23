# SOP-00 构建规范 — 产物怎么来、命名与指纹怎么记

> 适用范围：`ryd-utc-admin.jar`（生产 UTC）与 `unicard-official-1.0.0.jar`（生产 threeants）。
> ★ 2026-11-18 扩展（REQ-20261113-01 批次计划核可）：三份静态 dist（admin-web Vite／official-web umi／agent-mp 待确认）
> 与 agent-mp jar（挂起，SOP-05）纳入本仓覆盖。**dist 判据与 jar 分列**：
> dist 是普通文件集，无 ZIP 条目时间戳抖动问题，**字节级 sha256 直比即有判别力**（逐文件登记，见台账 §16）；
> §3.1「整包哈希无判别力」条款仅适用 jar，不得反推到 dist；同源构建复现性仍须双跑验证。
> 本 SOP 只管**产物侧**的纪律，不管业务代码怎么写。

---

## 1. 产物来源

| 产物 | 源码仓 | 构建模块 | 备注 |
|---|---|---|---|
| `ryd-utc-admin.jar` | `utc-server` | `utc-admin`（父 `utc-parent` 统一版本） | Spring Boot fat jar |
| `unicard-official-1.0.0.jar` | threeants / `unicard-java` | `unicard-official`（依赖 `unicard-common`、`unicard-data`） | Spring Boot fat jar，**关键类在嵌套模块 jar 内** |

上游依赖 `ryd-framework` / `ryd-components` 的版本变化会体现在 jar 清单里，
所以**清单比对是检测依赖漂移的唯一可靠手段**。

## 2. 命名

**本地构建产物一律带 git 短哈希**，形如：

```
utc-admin-prod-<7位短哈希>.jar
```

生产上落地的文件名**保持服务既有约定不变**（`ryd-utc-admin.jar` /
`unicard-official-1.0.0.jar`），改名动作由 `service.sh` / unit 承担，
**不要在换包时顺手改名** —— 生产应用目录里已经有 **5 种命名风格**的 10 个历史 jar，
再加一种只会让回滚更容易选错。

## 3. ★ 指纹怎么记（本 SOP 最重要的一节）

### 3.1 整包 sha256 **不能**用来判断「两次构建是否同码」

实测（2026-11-05）：生产与测试机的 `unicard-official-1.0.0.jar`
**字节数完全相同（93,135,977）但整包 sha256 不同**。

原因：ZIP 每个条目自带时间戳，而时间戳字段**定宽**。
同源两次构建的条目集与内容都不变 → 总尺寸不变 → 但整包哈希必变。

所以：

- 整包 sha256 的用途是 **回滚定位**（确认「换回的就是那一个文件」）；
- **同源性判定必须下沉到条目级清单**。

### 3.2 条目级清单（三层）

清单每行取 `(长度, CRC-32, 条目名)`，**不含时间戳**：

```bash
unzip -v <jar> | awk '/^[ ]*[0-9]/{print $1, $7, $8}' | LC_ALL=C sort
```

fat jar 看不到嵌套模块 jar 里的 class（`UtcProperties` 就在
`BOOT-INF/lib/unicard-common-1.0.0.jar` 内），所以必须**递归下钻**：

| 层级 | 工具 | 2026-11-05 实测条目数 |
|---|---|---|
| 外层 | `scripts/run-jar-cmp.sh` → `compare-jar-manifest.sh` | 291 |
| `unicard-common` 内层 | `scripts/compare-nested-jar.sh` | 225 |
| `unicard-data` 内层 | `scripts/compare-nested-jar.sh` | 158 |

### 3.3 清单必须先做**判别力自检**

这是比「空清单」更隐蔽的假阳性：**清单相同只能证明它覆盖到的东西相同。**
若 `BOOT-INF/lib/` 为 0，或没有自有模块 jar（`unicard|ryd|utc`），
则「哈希相同」证明不了自有代码相同。

```bash
bash scripts/inspect-jar-manifest.sh <清单文件>
# 期望输出 MANIFEST_HAS_POWER；出现 MANIFEST_NO_POWER / MANIFEST_SUSPECT 一律停手
```

2026-11-05 实测：`total=291 = 185 lib + 40 classes + 7 META-INF + 21 目录`，
自有模块 jar 为 `unicard-common-1.0.0.jar`、`unicard-data-1.0.0.jar` → `MANIFEST_HAS_POWER`。

### 3.4 Maven `pom.properties` 必然不同，须归一化

三层清单里的差异条目**全部**是 `META-INF/maven/<模块>/pom.properties`
（内含构建时间戳注释行）。判定同码的做法是**剔掉 `#` 开头行后再哈希**：

```bash
sed '/^[[:space:]]*#/d' pom.properties | LC_ALL=C sort | sha256sum
```

2026-11-05 实测归一化哈希（两台机器完全一致）：

| 模块 | 归一化 sha256 |
|---|---|
| official | `11acff69fe095e7ee86013a4bc954bc3fd9763286bb4dde648239973c01125c0` |
| common | `b906ab41be1ebe396f63a52015bca9073cdf216744e9bc6f36f104805d4f9a8f` |
| data | `5b7d7cb8b121f54135955ca7caebefb109ecad102fa8c380af4cc59a50fe6455` |

> ⚠ 「等长 + CRC 变 → 大概是时间戳」是**形态推断，不是证据**。
> 归一化哈希相同才是证据。别跳过这一步。

### 3.5 关键类兜底对照

清单比对之外，再对**关心的那个类**直接比 `(长度, CRC-32)`：

| class | 长度 | CRC-32 |
|---|---|---|
| `com/cnc/unicard/common/config/UtcProperties.class` | 6407 | `c5d879b3` |
| `com/cnc/unicard/data/service/impl/AgentServiceImpl.class` | 50853 | `32a73066` |
| `com/cnc/unicard/common/service/AgentService.class` | 4125 | `0f5683a1` |

## 4. 记录到哪里

- **产物指纹 → `指纹台账.md`**（完整 64 位 sha256，**不写缩写**；台账要能支撑回滚）
- **单次构建/换包的原始输出 → `变更留痕/<日期>-<任务>/`**
- 含凭据的文件（`application-prod.yml` / `.env` / `custom.env`）**只记指纹，不记内容**

## 5. 禁止事项

1. **禁止**用整包 sha256 相同/不同来下「同码/不同码」的结论。
2. **禁止**跳过 §3.3 判别力自检就采信清单比对结果。
3. **禁止**把凭据正文写进任何提交文件（含证据摘录）。
4. **禁止**在本仓存放 jar 二进制（`.gitignore` 已挡）。产物走部署机，不进 git。
5. **禁止**在换包时顺手改生产上的文件名或目录结构。

---

## 6. 前端 dist 交付件准入（2026-11-23 新增）

> 本节与 §5 并列，不替代 §5。补的是 §1 的缺口：§1 只列了两个后端 jar 的来源，
> **从未规定前端 dist 由谁交、交什么、缺什么算不合格**。
> 2026-11-23 因此实际卡住过一次 —— 两个前端改动已在源码仓完成、已跑过单测，
> 但没有人被要求构建，部署侧手里没有任何可准入的产物，整条链路停在「代码改完了」这一步。

### 6.1 适用对象

| 部署单元 | 形态 | 构建位置 | 是否适用本节 |
|---|---|---|---|
| admin-web | Vite | 本地（可复现） | ✅ |
| official-web | umi | 本地（Node 16 + cross-env） | ✅ |
| agent-mp 前端 | umi | 本地（同 official-web） | ✅ |
| utc-sp-web | 未采 | 未建档 | ⏸ 后期纳入 |

后端 jar（`ryd-utc-admin.jar` / `unicard-official-1.0.0.jar` / agent-mp 后端）**不适用本节**，
走 §1 与 `deploy/README.md` §5 的「生产机是唯一构建环境」例外通道。

### 6.2 交付件三件套（缺一即不合格）

| 件 | 内容 | 判据 |
|---|---|---|
| `dist-<7位短commit>/` | 构建产物目录，**目录名带短 commit** | 短 commit 须等于 BUILD-INFO 里 COMMIT 的前 7 位 |
| `BUILD-INFO` | 见 §6.3 六字段 | 六字段齐全且 `PROFILE=prod` |
| `SHA256SUMS.txt` | 产物内全部文件的 sha256 清单 | 必须是 `sha256sum` **原生格式**（每行 `<64位hex><两空格><相对路径>`）；`sha256sum -c` 全 OK；条目数与目录实际文件数一致。**字节数不得与 hash 写在同一列**（会令 `-c` 报格式错），另列在 BUILD-INFO 或清单注释行 |

### 6.3 BUILD-INFO 必备六字段

```
COMMIT=<40 位完整 commit>
PROFILE=prod            ← 必须是 prod；dev / test 一律拒收
NODE=<版本>             ← 例 v16.20.2
PKG_MGR=<名称+版本>     ← 例 npm8.19.4 / yarn1.22.19
BUILDER=<构建工具+版本> ← 例 vite3.1.3+esbuild0.15.8 / umi3.x
BUILT_AT=<ISO8601 带时区>
BUILT_ON=<构建主机标识>
```

`PROFILE=prod` 是硬闸门：测试机构建用的是 dev 环境（含测试用 openid 等注入值），
**dev 产物严禁上生产**。

> ★ 与旧口径的冲突与本日裁定：`SOP-04 §B1` 曾规定「G4 交付件＝测试机在役 dist 原字节 tar 拉回件」，
> 而测试机 threeants 跑的正是 `UMI_ENV=dev` 产物 —— 两条口径直接矛盾。
> 2026-11-23 裁定：**「测试机拉回」定源口径作废，以本节为准**。
> ★ 修订已落地（同日）：`SOP-04 §0.1`（三套前端共用的交付件口径）、`SOP-04 §0.2`（两条历史定源口径作废的成文记录）、
> `SOP-04 §B1` 与 `§A1` 的作废注记。今后 admin-web／official-web／agent-mp 一律按本节准入。

### 6.4 谁生成、谁准入

| 角色 | 责任 |
|---|---|
| **源码仓负责会话** | 生成三件套，交回「产物目录路径 + `index.html` 的 sha256 + 字节数」。**不得只交源码或 commit 号就算交付** |
| **部署侧（本仓）** | 只做准入校验：`sha256sum -c`、形态校验（`index.html` 在根、`./` 相对引用、无反斜杠条目）、BUILD-INFO 的 COMMIT 与预期一致、PROFILE=prod |
| **任何一方** | 都不得在部署时现场构建（R-BUILD-1） |

### 6.5 缺件处置

- 缺任意一件 → 部署脚本退出码 **20（EX_ARTIFACT）**，不接触生产。
- 三件套齐但 `sha256sum -c` 失败 → 同上。
- 产物可执行但 `PROFILE ≠ prod` → 同上，并在证据里记录实际 PROFILE 值再拒收。

### 6.6 附：本条立规的完整教训（2026-11-23）

两处前端 bug（`/agent/mine` 页面无法滚动、菜单间距不均）在两个源码仓各自修改完成、
各自跑过单测，其中一处已提交。用户要求「直接部署生产」，但当时：

1. 两仓都**没有构建产物**，部署侧无源码仓写权限，无法代为构建；
2. 其中一仓**没有提交 hash**，另一仓观察到其工作区仍为 `M`（已暂存未提交），与「已提交」的自述矛盾；
3. 两仓**均未推送**。

这三项都不是「再等等就好」，而是**交付链上从来没有明确过谁负责交什么**。
本节即为此而立：把「源码改完」与「可部署」之间缺失的那一段固定下来。
