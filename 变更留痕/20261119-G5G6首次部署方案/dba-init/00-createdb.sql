-- =============================================================================
-- agent-mp 本实例库 · 第 0 步：建库＋应用账号＋授权（G5 前置·外置 MySQL 裁定 D2）
-- 交付＝S0（2026-11-19，依用户建议增补）；执行方＝DBA 高权账号（root 或同级）
-- -----------------------------------------------------------------------------
-- ★ 本脚本为模板：库名/账号名/host/口令四处按实际调整后再执行。
-- ★ 口令占位 __DBA_SET_PASSWORD__ 为 fail-closed 设计（DBA 自行设定/修改强口令）；
--   占位原样执行将导致应用无法登录——这是预期守卫，不是缺陷。
-- ★ 应用账号口令真值不入 git/Hub/文书；设定后经用户受控通道转交 S0 注入 .env。
-- ★ MySQL 8.0 注意：默认认证插件 caching_sha2_password 与应用驱动
--   mysql-connector-java 5.1.48 不兼容，8.0 请务必用 mysql_native_password（见下）。
-- ★ 本步无需目标库上下文（创建库本身）；后续 01/02/03 三脚本须在目标库上下文执行。
-- =============================================================================

-- 1) 建库（库名建议 ryd_unicard_agentmp，最终以 DBA 给定为准并同步交回 S0）
CREATE DATABASE IF NOT EXISTS `ryd_unicard_agentmp`
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_general_ci;

-- 2) 应用账号（host 建议收紧为第四台机出口 IP——坐标见 prod-deploy 台账 §20；
--    '%' 仅为模板占位，DBA 按网络实际替换；账号名可自定，交回 S0 即可）
-- MySQL 5.7 写法：
CREATE USER IF NOT EXISTS 'agentmp_app'@'%' IDENTIFIED BY '__DBA_SET_PASSWORD__';
-- MySQL 8.0 请改用下行（并删除上行）：
-- CREATE USER IF NOT EXISTS 'agentmp_app'@'%' IDENTIFIED WITH mysql_native_password BY '__DBA_SET_PASSWORD__';

-- 3) 库级最小授权（含 EXECUTE：报表存储过程 proc_insert_rpt_total_4hon4h 可选用）
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER, INDEX, EXECUTE
  ON `ryd_unicard_agentmp`.* TO 'agentmp_app'@'%';

FLUSH PRIVILEGES;

-- 4) 自检（DBA 可选跑）：
-- SHOW GRANTS FOR 'agentmp_app'@'%';
-- SELECT SCHEMA_NAME, DEFAULT_CHARACTER_SET_NAME, DEFAULT_COLLATION_NAME
--   FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='ryd_unicard_agentmp';
-- 完成后按 00-DBA初始化说明.md §三交回：库名/主机地址:端口/应用账号用户名（口令走受控通道）。