# agent-mp 本实例库 DBA 初始化说明（G5 前置·外置 MySQL 裁定 D2）

- 日期：2026-11-19；交付＝S0；执行方＝用户协调的 DBA；需求＝REQ-20261113-01 G5
- 依据：用户裁定 D2＝**MySQL 不在第四台机本机部署**，由 DBA 提供外置库（库名/地址/用户名/口令由用户转交 S0，受控注入 .env，不入 git/Hub）
- 脚本源＝S5 仓 M4 交付 `src/unicard-agent-mp/sql/` 三件（测试机已验收同套初始化）；本包为交付副本，01-schema 经一处 PII 掩码（见§四）；另依用户建议增补 `00-createdb.sql` 建库/账号/授权模板（S0 编写，口令占位由 DBA 自行设定修改）

## 一、执行顺序（严格字母序，依赖链不可颠倒）

| 序 | 文件 | 内容 | 幂等性 |
|---|---|---|---|
| 0 | `00-createdb.sql` | 建库（utf8mb4_general_ci）＋应用账号＋库级授权模板；**库名/账号名/host/口令四处按实际调整**，DBA 高权账号执行，无需目标库上下文 | IF NOT EXISTS 守卫；口令占位 `__DBA_SET_PASSWORD__` 为 fail-closed，**DBA 必须自行设定/修改强口令** |
| 1 | `01-schema.sql` | 49 表 DROP+CREATE 结构＋1 存储过程（纯 DDL 无数据） | DROP IF EXISTS 重建（**仅限全新空库首装**） |
| 2 | `02-basedata.sql` | config 4 表基础数据（t_role/t_menu/t_permission/t_sys_dictionary 清洗件） | DELETE 精确条件＋INSERT，可重复执行 |
| 3 | `03-seed.sql` | level1 顶层经销商 1 行（AGENTMP-L1-0001/agentmp-level1） | DELETE 固定 id＋INSERT，可重复执行 |

## 二、库与账号要求（请 DBA 按此准备）

1. **全新独立空库**（建议名 `ryd_unicard_agentmp`，最终以 DBA 给定库名为准）；**严禁复用 fuzhoukuaifu/ryd_unicard 等现网库**（D26 红线）——01-schema 含 DROP TABLE，混用现网库将销毁现网表。建库/账号/授权可直接用 `00-createdb.sql` 模板（四处占位按实际改）。
2. MySQL **5.7 或 8.0 均可**（脚本源 8.0.19 dump，已核无 8.0 专有 collation，5.7 兼容）；字符集 **utf8mb4**（脚本内 SET NAMES utf8mb4；建库建议 `CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci`）。**8.0 注意**：应用驱动 mysql-connector-java 5.1.48 不支持默认 caching_sha2_password，应用账号须 `IDENTIFIED WITH mysql_native_password`（00-createdb 内已备两版写法）。
3. 时区：会话/连接按 **GMT+8**（应用 JDBC URL 带 serverTimezone=GMT%2B8；建议库侧 default-time-zone=+08:00 或确认会话时区一致）。
4. 应用账号权限：该库 **SELECT/INSERT/UPDATE/DELETE/CREATE/DROP/ALTER/INDEX/EXECUTE**（存储过程 proc_insert_rpt_total_4hon4h 报表 job 可选用）；初始化由 DBA 高权账号执行，应用账号最小权限到库级。
5. **网络可达**：第四台机（坐标见 prod-deploy 台账 §20）→ DBA 库地址:端口 须放行（安全组/白名单由用户与 DBA 协调）；G5-prep 将做只读连通探针。
6. `00-createdb.sql` 由高权账号执行（创建库本身，无需选库）；**01/02/03 三脚本均无 CREATE DATABASE/USE**——请在目标库上下文执行（mysql -D <库名> 或客户端先选库）。

## 三、初始化后交接（DBA→S0）

- 交回：**库名、主机地址:端口、应用账号用户名**（口令走受控通道，不入 git/Hub/明文文书）。
- seed 登录口令为占位符 `__PASSWORD_SHA256_UPPER_HEX_SET_AT_DEPLOY__`（fail-closed，占位不匹配任何哈希）——**DBA 无需处理**，G5 阶段由 S0 在机上按用户裁定的登录口令 UPDATE 注入（UPPER(SHA2(...,256)) 大写 hex）。
- 自检出口判据（DBA 可代跑）：`SELECT COUNT(*) FROM t_agent WHERE level=0;` 期望 **0**（无 level0）；`SELECT id,username,level,parent_id,enabled FROM t_agent WHERE id='AGENTMP-L1-0001';` 期望 1 行 level=1/parent_id=NULL/enabled=1；表计数期望 **49**。

## 四、与源脚本的差异披露（仅一处，PII 掩码）

- `01-schema.sql` L1202 存储过程内 `BETWEEN '8986…600' and '8986…700'` 两段**真实卡号形态字面量**→替换为合成占位 `'8986000000000000000'`（全 0 尾段，非真实卡）。该过程为报表 job（agent-mp 可选），掩码不影响结构与登录/主池链路；CRLF 归一 diff 实证**仅此行差异**。
- 02/03 与源逐字节一致（敏感形态扫描零命中）。
- 本包三件初始化 SQL sha256 登记于台账 §24 补记（00-createdb 模板指纹见 §24 补记 2）；DBA 执行前请核对指纹防传输篡改。

## 五、红线提醒

- 本实例库与生产 UTC 库（ryd_utc）**零关联**：agent-mp 对 ryd_utc 零 SQL（源码定案，方案§五），DBA 无需为 agent-mp 开任何 UTC 库权限。
- 初始化脚本与说明可入 git（纯结构/清洗数据/占位）；**口令与真实凭据一律不入**。