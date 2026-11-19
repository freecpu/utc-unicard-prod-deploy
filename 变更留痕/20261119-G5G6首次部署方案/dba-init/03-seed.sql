-- =============================================================================
-- REQ-20261005-01 M0 · agent-mp 本实例库最小 seed（PR-M0-2 · 乙8/丁1 · D22/D23）
-- 目标库：本实例库 ryd_unicard_agentmp（D21·每经销商独立实例·严禁 fuzhoukuaifu）。
-- 语义：level1 = 本实例唯一顶层经销商（无 level0 kuaifu·D23）；供登录去化身冒烟（乙8·D22）。
-- ⚠ 2026-11-19 用户裁定变更：初始登录口令哈希已嵌入本件（原占位符设计废止，偏离披露见台账 §24 补记 3）。
--   初始口令为弱口令（用户裁定），哈希可被彩虹表秒查——**公网开放前必须改强口令**（文末 UPDATE 模板）。
-- ⚠ 本文件=M0 最小 seed（仅种 level1 顶层）；完整 DB 初始化脚本（克隆结构+基础数据+字典主池绑定）随 M4 交付（§十-补/Q-O）。
-- 前置：目标库已含 t_agent 表结构（CREATE TABLE t_agent 见 src/sql/ryd_unicard.sql L32532）。
-- =============================================================================

-- 幂等：先清本 seed 种入的 level1 顶层（按固定 id），再插入。
DELETE FROM `t_agent` WHERE `id` = 'AGENTMP-L1-0001';

-- 本实例 level1 顶层经销商（parent_id=NULL·无上级；level=1；enabled=b'1'）。
-- password 已嵌入用户裁定初始口令的 SHA-256 大写 hex（无盐）；弱口令，上线前务必改强（见文末）。
INSERT INTO `t_agent`
  (`id`, `avatar`, `create_time`, `enabled`, `level`, `parent_id`, `password`, `profit_ratio`, `remark`, `username`, `transfer_profit_ratio`)
VALUES
  ('AGENTMP-L1-0001', NULL, NOW(), b'1', 1, NULL, '8D969EEF6ECAD3C29A3A629280E686CF0C3F5D5A86AFF3CA12020C923ADC6C92', NULL, 'agent-mp 本实例 level1 顶层（M0 seed）', 'agentmp-level1', NULL);

-- 交付自检（出口判据⑥·本实例库无 level0）：
-- SELECT COUNT(*) AS level0_count FROM `t_agent` WHERE `level` = 0;   -- 期望 0
-- SELECT `id`, `username`, `level`, `parent_id`, `enabled` FROM `t_agent` WHERE `id` = 'AGENTMP-L1-0001';

-- -----------------------------------------------------------------------------
-- 改密模板（初始为弱口令·公网开放前必改·在机器上执行·勿把明文提交回仓）：
--   UPDATE `t_agent` SET `password` = UPPER(SHA2('替换为真实登录密码', 256)) WHERE `id` = 'AGENTMP-L1-0001';
-- 说明：PasswordUtils.encodePass = DigestUtils.sha256 → 【大写 hex】；MySQL SHA2() 返回【小写】，
--       故必须 UPPER() 包裹，否则 checkPass(plain, stored) 大小写不一致 → 登录必失败。
-- config 一致性（§十-补#3·防测试机式错配）：application-agentmp.yml 的
--       utc.agentId / utc.agentName（默认 agentmp-level1）/ unicom.kuaifu.agentUserId
--       须与本实例 level1 经销商的 UTC 绑定值一致（本 seed username 默认与 utc.agentName 默认对齐）。
-- -----------------------------------------------------------------------------
