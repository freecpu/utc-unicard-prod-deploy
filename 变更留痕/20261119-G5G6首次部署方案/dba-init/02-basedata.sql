-- =============================================================================
-- REQ-20261005-01 M4 · PR-M4-1 · agent-mp 本实例库【基础数据脚本】(Q-O① config 类基础数据)
-- 目标库：本实例库 ryd_unicard_agentmp（D21·每经销商独立实例·严禁 fuzhoukuaifu/ryd_unicard 现网库）。
-- 前置：schema-ryd_unicard_agentmp.sql 已导入（48 表结构存在）；本脚本只灌 config 类基础数据。
-- 来源：提取自 src/sql/ryd_unicard.sql 的 config 4 表（t_role/t_menu/t_permission/t_sys_dictionary）·
--       清洗排除现网敏感/PII（逐表分类清单见 PR-M4-1 完成单·finding2 已裁）。
-- 幂等：DELETE（精确 id/code_id 条件·承 M0 seed 范式）+ INSERT·重复执行不重复种·不误删 deploy 侧后续数据。
--
-- ⚠ 主池绑定（D4）：**本脚本不含主池绑定字典占位**（依主管裁定件 R8·2026-10-11·选项 A config 载体）。
--   主池 flowId 走 config `utc.agentFlowId`（env `AGENTMP_UTC_AGENT_FLOW_ID`）·代码 AgentServiceImpl.preTransfer
--   L380 + AgentMpIdentityResolver.topLevelAgentFlowId() L56-58 读 config·SysDictionaryService 无主池消费·
--   加字典占位=dead data。deploy 侧按经销商实际 UTC 池 `t_agent_flow.created_date ASC LIMIT 1` 查得 flowId
--   填 `.env`（归 PR-M4-2 .env.sample + PR-M4-5 部署文档·非本 DB 脚本）。
--
-- t_sys_dictionary 清洗（源库 7 条 → 携带 4 条 config·排除 3 条现网敏感）：
--   携带：DISCLAIMER（免责声明占位）/FIRST_CHARGE_TIME（首充时间）/LUCKY_DRAW_NOT_NEXT_FLOW（抽奖流量档）/OPTION_COEFFICIENT（分润可选系数 0.35,0.5,0.8）
--   排除：KUAIFU_COOKIE（现网 JSESSIONID 会话）/NATION_IDENTIFY（现网全国流量卡标识）/LIMIT_RECHARGE_JASPER_USERNAME（现网 jasper 用户名 furui*）
--
-- 配套：schema-ryd_unicard_agentmp.sql（结构）/ REQ-20261005-01-M0-agentmp-seed.sql（level1 种子）/ init-agentmp-db.sh（编排）
-- 回指：Q-O①（需求书 L361）·D21·甲4·M4 L2 §4.1 第 2 步·finding2（已裁·逐表分类）·裁定件 R8（主池绑定 config）
-- =============================================================================

SET NAMES utf8mb4;
-- t_menu 自引用外键（parent_id→t_menu.id）+ t_permission 外键（menu_id→t_menu.id·role_id→t_role.id）：
-- 关闭外键检查使 DELETE/INSERT 顺序无关（幂等重跑安全）·脚本末尾恢复。
SET FOREIGN_KEY_CHECKS = 0;

-- -----------------------------------------------------------------------------
-- 1) t_role（1 条·系统管理员角色·后台登录角色定义·无 PII）
-- -----------------------------------------------------------------------------
DELETE FROM `t_role` WHERE `id` = '5nywb5sos2yt6egz7802k6gc9';
INSERT INTO `t_role` (`id`, `create_time`, `desc`, `is_super`, `name`) VALUES ('5nywb5sos2yt6egz7802k6gc9', '2021-08-26 20:00:00', '系统管理员', b'1', '系统管理员');

-- -----------------------------------------------------------------------------
-- 2) t_menu（8 条·后台管理菜单树·path 为前端路由非现网 URL·无 PII）
--    自引用外键 parent_id：系统管理(euq6..)为根·下挂 用户管理/角色管理/菜单管理；设备管理(6izo..)为根·下挂 设备列表；订单管理(c9u0..)为根·下挂 充值列表。
-- -----------------------------------------------------------------------------
DELETE FROM `t_menu` WHERE `id` IN (
  '2anrcdvd3n005q5v6wcco939l','5r5vvz92ufqxb624rlyj38v3m','6izoquli8lvae0f52fv8ro9mz','7yts98ovi3amqgze7kxicbfac',
  'c9u0bgopakg0jfnzw6dkbn3dt','ep97cehcp8hr3m87q9lafwp28','euq6tw0bpl40dnzx9pwb4lz9h','f5hs6jbxpf1y4sm0kc5uj4421'
);
INSERT INTO `t_menu` (`id`, `create_time`, `icon`, `is_super`, `name`, `path`, `sequence`, `type`, `parent_id`) VALUES ('euq6tw0bpl40dnzx9pwb4lz9h', '2021-08-26 20:00:00', 'setting', b'1', '系统管理', '/home/admin', 1, 0, NULL);
INSERT INTO `t_menu` (`id`, `create_time`, `icon`, `is_super`, `name`, `path`, `sequence`, `type`, `parent_id`) VALUES ('5r5vvz92ufqxb624rlyj38v3m', '2021-08-26 20:00:00', '', b'1', '用户管理', '/home/admin/user', 1, 0, 'euq6tw0bpl40dnzx9pwb4lz9h');
INSERT INTO `t_menu` (`id`, `create_time`, `icon`, `is_super`, `name`, `path`, `sequence`, `type`, `parent_id`) VALUES ('ep97cehcp8hr3m87q9lafwp28', '2021-08-26 20:00:00', '', b'1', '角色管理', '/home/admin/role', 2, 0, 'euq6tw0bpl40dnzx9pwb4lz9h');
INSERT INTO `t_menu` (`id`, `create_time`, `icon`, `is_super`, `name`, `path`, `sequence`, `type`, `parent_id`) VALUES ('f5hs6jbxpf1y4sm0kc5uj4421', '2021-08-26 20:00:00', '', b'1', '菜单管理', '/home/admin/menu', 3, 0, 'euq6tw0bpl40dnzx9pwb4lz9h');
INSERT INTO `t_menu` (`id`, `create_time`, `icon`, `is_super`, `name`, `path`, `sequence`, `type`, `parent_id`) VALUES ('6izoquli8lvae0f52fv8ro9mz', '2021-08-28 11:34:34', 'crown', b'0', '设备管理', '/home/iccid', 2, 0, NULL);
INSERT INTO `t_menu` (`id`, `create_time`, `icon`, `is_super`, `name`, `path`, `sequence`, `type`, `parent_id`) VALUES ('7yts98ovi3amqgze7kxicbfac', '2021-09-03 10:59:22', NULL, b'0', '设备列表', '/home/iccid', 1, 0, '6izoquli8lvae0f52fv8ro9mz');
INSERT INTO `t_menu` (`id`, `create_time`, `icon`, `is_super`, `name`, `path`, `sequence`, `type`, `parent_id`) VALUES ('c9u0bgopakg0jfnzw6dkbn3dt', '2021-09-06 18:09:35', 'smile', b'0', '订单管理', '/home/order', 3, 0, NULL);
INSERT INTO `t_menu` (`id`, `create_time`, `icon`, `is_super`, `name`, `path`, `sequence`, `type`, `parent_id`) VALUES ('2anrcdvd3n005q5v6wcco939l', '2021-09-06 18:09:52', NULL, b'0', '充值列表', '/home/order/rechargeOrder', 1, 0, 'c9u0bgopakg0jfnzw6dkbn3dt');

-- -----------------------------------------------------------------------------
-- 3) t_permission（3 条·role↔menu 权限映射·系统管理员→用户管理/角色管理/菜单管理·无 PII）
-- -----------------------------------------------------------------------------
DELETE FROM `t_permission` WHERE `id` IN ('000iwohtuuos1g382t6fmy6aw','002ho048ph5tmt8svszczuf4n','00309ccgk9w7yjz47r2wq9cmp');
INSERT INTO `t_permission` (`id`, `menu_id`, `role_id`) VALUES ('000iwohtuuos1g382t6fmy6aw', '5r5vvz92ufqxb624rlyj38v3m', '5nywb5sos2yt6egz7802k6gc9');
INSERT INTO `t_permission` (`id`, `menu_id`, `role_id`) VALUES ('002ho048ph5tmt8svszczuf4n', 'ep97cehcp8hr3m87q9lafwp28', '5nywb5sos2yt6egz7802k6gc9');
INSERT INTO `t_permission` (`id`, `menu_id`, `role_id`) VALUES ('00309ccgk9w7yjz47r2wq9cmp', 'f5hs6jbxpf1y4sm0kc5uj4421', '5nywb5sos2yt6egz7802k6gc9');

-- -----------------------------------------------------------------------------
-- 4) t_sys_dictionary（4 条 config 字典 + 3 条 B2 提现字典 + 4 条 B1 成本价字典·排除 3 条现网敏感·**不含主池绑定**[走 config 依 R8]）
--    注：源库 7 条无主池绑定记录（主池 flowId 从来走 config/代码·非字典）。
--    【B2 提现字典·任务A 2026-10-14 纳入】WITHDRAW_MIN_AMOUNT/FINANCE_TASK_PASSWORD/FINANCE_NOTIFY_WEBHOOK 三条
--    逐字镜像 src/sql/REQ-20260920-01-B2 L188-191（INSERT IGNORE 幂等·不清改 deploy 侧 UPDATE 的真实值）：
--    WITHDRAW_MIN_AMOUNT=100（系统级默认提现阈值）；FINANCE_TASK_PASSWORD/FINANCE_NOTIFY_WEBHOOK 脱敏留空·
--    deploy 侧上线前 UPDATE 真实值（密码=SHA-256 无盐大写 hex·webhook=飞书机器人·勿提交明文/真实 hash 入 git）。
--    【B1 成本价字典·任务D 2026-10-14 纳入】PROFIT_COST_PRICE_LOCAL/NATION + PROFIT_DEDUCT_RATIO_LOCAL/NATION 四条
--    照 src/sql/REQ-20260920-01-B1 L62-66 值 INSERT IGNORE（★主管裁定：业务可配值非凭据·同 B2 WITHDRAW_MIN_AMOUNT 处理·
--    更新本脚本旧「留 deploy 侧补充」裁定）：C 本地0.25/全国0.03·S 本地0.04/全国0.04（interim 零回归基线·生产终值业务上线前确认·B1 sql L57 注记不变）。
-- -----------------------------------------------------------------------------
DELETE FROM `t_sys_dictionary` WHERE `code_id` IN ('DISCLAIMER','FIRST_CHARGE_TIME','LUCKY_DRAW_NOT_NEXT_FLOW','OPTION_COEFFICIENT');
INSERT INTO `t_sys_dictionary` (`code_id`, `code_value`, `remark`) VALUES ('DISCLAIMER', '', '免责声明内容');
INSERT INTO `t_sys_dictionary` (`code_id`, `code_value`, `remark`) VALUES ('FIRST_CHARGE_TIME', '2051-02-18 00:00:00', '首充时间');
INSERT INTO `t_sys_dictionary` (`code_id`, `code_value`, `remark`) VALUES ('LUCKY_DRAW_NOT_NEXT_FLOW', '20480,51200', '抽奖不选下一档的流量');
INSERT INTO `t_sys_dictionary` (`code_id`, `code_value`, `remark`) VALUES ('OPTION_COEFFICIENT', '0.35,0.5,0.8', '可选系数');
-- B2 提现字典（REQ-20260920-01 B2 L188-191·INSERT IGNORE 幂等·脱敏·deploy 侧 UPDATE 真实凭据）
INSERT IGNORE INTO `t_sys_dictionary` (`code_id`, `code_value`, `remark`) VALUES ('WITHDRAW_MIN_AMOUNT', '100', 'B2最低提现额(元)·系统级可配·申请时Σ勾选月净额≥此值·生产前业务确认终值');
INSERT IGNORE INTO `t_sys_dictionary` (`code_id`, `code_value`, `remark`) VALUES ('FINANCE_TASK_PASSWORD', '', 'B2财务任务闸门密码(SHA-256无盐大写hex·PasswordUtils.encodePass)·运维上线前UPDATE·勿提交明文');
INSERT IGNORE INTO `t_sys_dictionary` (`code_id`, `code_value`, `remark`) VALUES ('FINANCE_NOTIFY_WEBHOOK', '', 'B2财务任务节点飞书通知webhook·运维上线前UPDATE·脱敏');
-- B1 成本价 C/结算系数 S 字典（REQ-20260920-01 B1 L62-66·INSERT IGNORE 幂等·业务可配值非凭据·主管裁定 2026-10-14 落 basedata·生产终值业务上线前确认）
INSERT IGNORE INTO `t_sys_dictionary` (`code_id`, `code_value`, `remark`) VALUES ('PROFIT_COST_PRICE_LOCAL', '0.25', 'B1分润成本价C·本地卡(nation=0)·元/G·生产前业务确认终值');
INSERT IGNORE INTO `t_sys_dictionary` (`code_id`, `code_value`, `remark`) VALUES ('PROFIT_COST_PRICE_NATION', '0.03', 'B1分润成本价C·全国卡(nation=1)·元/G·生产前业务确认终值');
INSERT IGNORE INTO `t_sys_dictionary` (`code_id`, `code_value`, `remark`) VALUES ('PROFIT_DEDUCT_RATIO_LOCAL', '0.04', 'B1订阅结算系数S·本地卡(nation=0)·interim同916单值·零回归');
INSERT IGNORE INTO `t_sys_dictionary` (`code_id`, `code_value`, `remark`) VALUES ('PROFIT_DEDUCT_RATIO_NATION', '0.04', 'B1订阅结算系数S·全国卡(nation=1)·interim占位·待业务确认另套终值');

SET FOREIGN_KEY_CHECKS = 1;

-- -----------------------------------------------------------------------------
-- 交付自检（出口判据·本实例库 config 基础数据）：
--   SELECT COUNT(*) FROM `t_role`;            -- 期望 >= 1（系统管理员）
--   SELECT COUNT(*) FROM `t_menu`;            -- 期望 >= 8（后台菜单树）
--   SELECT COUNT(*) FROM `t_permission`;      -- 期望 >= 3（role↔menu 映射）
--   SELECT COUNT(*) FROM `t_sys_dictionary`;  -- 期望 >= 11（4 config 字典 + 3 B2 提现字典 + 4 B1 成本价字典·排除现网敏感）
--   SELECT code_id FROM `t_sys_dictionary` WHERE code_id IN ('KUAIFU_COOKIE','NATION_IDENTIFY','LIMIT_RECHARGE_JASPER_USERNAME');  -- 期望 0 行（现网敏感已排除）
-- 主池绑定（D4）走 config（AGENTMP_UTC_AGENT_FLOW_ID）·非本脚本·验证见 PR-M4-2 .env + PR-M4-5 部署文档。
-- -----------------------------------------------------------------------------
