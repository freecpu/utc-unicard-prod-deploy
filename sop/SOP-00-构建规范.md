# SOP-00 构建规范 — 产物怎么来、命名与指纹怎么记

> 适用范围：`ryd-utc-admin.jar`（生产 UTC）与 `unicard-official-1.0.0.jar`（生产 threeants）。
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
