-- =============================================================================
-- REQ-20261005-01 M4 · PR-M4-1 · agent-mp 本实例库【结构脚本】（Q-O① 结构克隆·纯 DDL·无数据/无 PII）
-- 目标库：ryd_unicard_agentmp（D21·每经销商独立实例·单租户天然隔离·严禁 fuzhoukuaifu/ryd_unicard 现网库）。
-- 来源：提取自 src/sql/ryd_unicard.sql（Navicat dump·源 MySQL 8.0.19）——删除全部行首 INSERT INTO/BEGIN;/COMMIT;
--       数据块·保留 38 表 DROP+CREATE 结构 + 1 存储过程（--no-data 等价·§7.2 快照严禁进 git→本脚本纯结构无快照）。
-- 内容：49 张表 CREATE TABLE（38 张 dump 基线表 t_agent/t_sys_dictionary/t_iccid/t_order 等 + 10 张 REQ-20260920-01 B1/B2/B3 镜像表 + 1 张 REQ-20260909-01 C1/C7 镜像表 t_agent_recharge_log）+ 存储过程 proc_insert_rpt_total_4hon4h
--       ★基线漂移根治（任务D/E·2026-10-14）：re_order_iccid 由 dump 基线 14 列补齐至 threeants 现网 17 列（utc_recharge_id[REQ-20260918-01]+card_cycle_type/actual_deduct_flow[B1]）；新增 t_agent_profit_zero_log（B1）。
--       全面核对 vs threeants 现网 ryd_unicard（49 表/526 列·mysqldump 等价 information_schema 列集 diff）：46 共有表列集一致·仅 re_order_iccid 列漂移（已补）+ 2 缺表（zero_log 任务D 补·t_agent_recharge_log 任务F 补[承主管 §五请裁 2 问均 YES·2026-10-15]）+ t_finance_withdraw_audit 反向多 created_date/modified_date（agent-mp 忠实 B2 sql·现网测试库落后·非本模块缺陷·已另行知会 threeants）。
--       ★任务F（承 §五裁定·2026-10-15）：补 t_agent_recharge_log（REQ-20260909-01 C1 写/C7 读·13 列·逐字镜像 src/sql/t_agent_recharge_log.sql·幂等 IF NOT EXISTS）→ 49 表；additive 镜像 C7 recharge/history 端点（AgentMpAgentResource·纯委托 common/data·前端 home「我的」区入口→整页真实消费方主管 git grep 坐实）。
--       （现网报表 job·agent-mp 可选·保留不影响 level1 登录/主池绑定 P1 必测）+ SET FOREIGN_KEY_CHECKS 头0尾1。
-- 配套：基础数据（config 4 表清洗）→ basedata-ryd_unicard_agentmp.sql；level1 seed → REQ-20261005-01-M0-agentmp-seed.sql；
--       编排（drop+recreate / 幂等）→ init-agentmp-db.sh。逐表分类清单（finding2）→ PR-M4-1 完成单。
-- ⚠ 版本兼容：源 8.0.19·部署目标 compose mysql:5.7.44（部署规范 §13.3）——本 dump 表均 CHARSET=utf8/utf8mb4·
--       COLLATE=utf8_general_ci（无 8.0 专有 utf8mb4_0900）·5.7 兼容（已 grep 核）。
-- 回指：Q-O①（需求书 L361）·D21·甲4（去 kuaifu level0 见 basedata/seed）·§7.2·finding2。
-- =============================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------
-- Table structure for re_agent_iccid
-- ----------------------------
DROP TABLE IF EXISTS `re_agent_iccid`;
CREATE TABLE `re_agent_iccid` (
  `id` varchar(40) NOT NULL,
  `coefficient` int DEFAULT NULL,
  `create_time` datetime DEFAULT NULL,
  `cycle_type` int DEFAULT NULL,
  `iccid` varchar(255) DEFAULT NULL,
  `is_transfer_user` bit(1) NOT NULL,
  `single_card_flow` decimal(19,2) DEFAULT NULL,
  `single_card_price` decimal(19,2) DEFAULT NULL,
  `transfer_user_time` datetime DEFAULT NULL,
  `agent_id` varchar(40) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `UKs00shotvh876925qm0cfjqe80` (`iccid`),
  KEY `FKf2gitbig5ry9jo4cs4c1hbv2` (`agent_id`),
  CONSTRAINT `FKf2gitbig5ry9jo4cs4c1hbv2` FOREIGN KEY (`agent_id`) REFERENCES `t_agent` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of re_agent_iccid
-- ----------------------------

-- ----------------------------
-- Table structure for re_agent_iccid_bak
-- ----------------------------
DROP TABLE IF EXISTS `re_agent_iccid_bak`;
CREATE TABLE `re_agent_iccid_bak` (
  `id` varchar(40) NOT NULL,
  `coefficient` int DEFAULT NULL,
  `create_time` datetime DEFAULT NULL,
  `cycle_type` int DEFAULT NULL,
  `iccid` varchar(255) DEFAULT NULL,
  `is_transfer_user` bit(1) NOT NULL,
  `single_card_flow` decimal(19,2) DEFAULT NULL,
  `single_card_price` decimal(19,2) DEFAULT NULL,
  `transfer_user_time` datetime DEFAULT NULL,
  `agent_id` varchar(40) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `UKs00shotvh876925qm0cfjqe80` (`iccid`),
  KEY `FKf2gitbig5ry9jo4cs4c1hbv2` (`agent_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of re_agent_iccid_bak
-- ----------------------------

-- ----------------------------
-- Table structure for re_agent_pre_iccid
-- ----------------------------
DROP TABLE IF EXISTS `re_agent_pre_iccid`;
CREATE TABLE `re_agent_pre_iccid` (
  `id` varchar(40) NOT NULL,
  `create_time` datetime DEFAULT NULL,
  `iccid` varchar(255) DEFAULT NULL,
  `agent_pre_transfer_id` varchar(40) DEFAULT NULL,
  `coefficient` int DEFAULT NULL,
  `single_card_flow` decimal(19,2) DEFAULT NULL,
  `single_card_price` decimal(19,2) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `UKl8e5d09v7l1ntmcoh7s25i592` (`iccid`),
  KEY `FKh5bti05vgmf92i02kh10m9x0x` (`agent_pre_transfer_id`),
  CONSTRAINT `FKh5bti05vgmf92i02kh10m9x0x` FOREIGN KEY (`agent_pre_transfer_id`) REFERENCES `t_agent_pre_transfer` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of re_agent_pre_iccid
-- ----------------------------

-- ----------------------------
-- Table structure for re_order_iccid
-- ----------------------------
DROP TABLE IF EXISTS `re_order_iccid`;
CREATE TABLE `re_order_iccid` (
  `id` varchar(40) NOT NULL,
  `agent_coupon_id` varchar(255) DEFAULT NULL,
  `coefficient` int NOT NULL,
  `cycle_month` int DEFAULT NULL,
  `cycle_start_time` datetime DEFAULT NULL,
  `cycle_type` int DEFAULT NULL,
  `discount_amount` decimal(10,2) DEFAULT '0.00',
  `iccid` varchar(255) DEFAULT NULL,
  `single_card_flow` decimal(19,2) DEFAULT NULL,
  `single_card_price` decimal(19,2) DEFAULT NULL,
  `total_price` decimal(19,2) DEFAULT NULL,
  `user_coupon_id` varchar(255) DEFAULT NULL,
  `order_id` varchar(40) DEFAULT NULL,
  `virnum` varchar(255) DEFAULT NULL,
  `utc_recharge_id` varchar(32) DEFAULT NULL COMMENT 'UTC充值流水ID(REQ-20260918-01·基线漂移补齐·退款恢复候选查询JOIN键·orders()800真因)',
  `card_cycle_type` int DEFAULT NULL COMMENT '卡轴周期(建单冻结·month判据):FIXED=1/FLEXIBLE=2;区别于cycle_type(套餐轴)',
  `actual_deduct_flow` decimal(20,3) DEFAULT NULL COMMENT 'UTC实际扣池量(充值成功冻结·成本直读源·方案乙)',
  PRIMARY KEY (`id`),
  KEY `FK6edhjlcbafg6y7yu39n86ua35` (`order_id`),
  CONSTRAINT `FK6edhjlcbafg6y7yu39n86ua35` FOREIGN KEY (`order_id`) REFERENCES `t_order` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of re_order_iccid
-- ----------------------------

-- ----------------------------
-- Table structure for re_user_conpon_rate_plan
-- ----------------------------
DROP TABLE IF EXISTS `re_user_conpon_rate_plan`;
CREATE TABLE `re_user_conpon_rate_plan` (
  `id` varchar(40) NOT NULL,
  `rate_plan_id` varchar(40) DEFAULT NULL,
  `user_coupon_id` varchar(40) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `FKeabndytbvua7g83p22fipdh0c` (`rate_plan_id`),
  KEY `FKtmpq7sgj2hiw41x1rgkniy1vo` (`user_coupon_id`),
  CONSTRAINT `FKeabndytbvua7g83p22fipdh0c` FOREIGN KEY (`rate_plan_id`) REFERENCES `t_rate_plan` (`id`),
  CONSTRAINT `FKtmpq7sgj2hiw41x1rgkniy1vo` FOREIGN KEY (`user_coupon_id`) REFERENCES `t_user_coupon` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of re_user_conpon_rate_plan
-- ----------------------------

-- ----------------------------
-- Table structure for re_virnum_iccid
-- ----------------------------
DROP TABLE IF EXISTS `re_virnum_iccid`;
CREATE TABLE `re_virnum_iccid` (
  `iccid` varchar(255) NOT NULL,
  `msisdn` varchar(255) DEFAULT NULL,
  `virnum` varchar(255) NOT NULL,
  `jasper_username` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`iccid`),
  UNIQUE KEY `uniquekyerevirnumiccidvirnum` (`virnum`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of re_virnum_iccid
-- ----------------------------

-- ----------------------------
-- Table structure for rpt_4hon4h_subtract_info
-- ----------------------------
DROP TABLE IF EXISTS `rpt_4hon4h_subtract_info`;
CREATE TABLE `rpt_4hon4h_subtract_info` (
  `id` varchar(255) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `user_top_flow` decimal(19,4) NOT NULL,
  `user_use_flow` decimal(19,4) NOT NULL,
  `user_real_top_flow` decimal(19,4) DEFAULT NULL,
  `user_real_use_flow` decimal(19,4) DEFAULT NULL,
  `status0` int DEFAULT NULL,
  `status1` int DEFAULT NULL,
  `status2` int DEFAULT NULL,
  `status3` int DEFAULT NULL,
  `status4` int DEFAULT NULL,
  `uptime` datetime DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of rpt_4hon4h_subtract_info
-- ----------------------------

-- ----------------------------
-- Table structure for rpt_daily_rechargeinfo
-- ----------------------------
DROP TABLE IF EXISTS `rpt_daily_rechargeinfo`;
CREATE TABLE `rpt_daily_rechargeinfo` (
  `id` varchar(40) NOT NULL,
  `create_date` datetime NOT NULL,
  `cnt_order` int DEFAULT '0',
  `cnt_user` int DEFAULT '0',
  `pay_total` decimal(12,3) NOT NULL DEFAULT '0.000',
  `sell_flow` decimal(12,3) NOT NULL DEFAULT '0.000',
  `real_sell_flow` decimal(12,3) NOT NULL DEFAULT '0.000',
  `price` decimal(12,3) NOT NULL DEFAULT '0.000',
  `real_price` decimal(12,3) NOT NULL DEFAULT '0.000',
  `agent_profit_sharing` decimal(12,3) NOT NULL DEFAULT '0.000',
  `profit` decimal(12,3) NOT NULL DEFAULT '0.000',
  `olduser_cnt_order` int DEFAULT '0',
  `olduser_cnt_user` int DEFAULT '0',
  `olduser_pay_total` decimal(12,3) NOT NULL DEFAULT '0.000',
  `olduser_sell_flow` decimal(12,3) NOT NULL DEFAULT '0.000',
  `olduser_real_sell_flow` decimal(12,3) NOT NULL DEFAULT '0.000',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of rpt_daily_rechargeinfo
-- ----------------------------

-- ----------------------------
-- Table structure for rpt_total_info
-- ----------------------------
DROP TABLE IF EXISTS `rpt_total_info`;
CREATE TABLE `rpt_total_info` (
  `id` varchar(255) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `user_top_flow` decimal(19,4) NOT NULL,
  `user_use_flow` decimal(19,4) NOT NULL,
  `user_real_top_flow` decimal(19,4) DEFAULT NULL,
  `user_real_use_flow` decimal(19,4) DEFAULT NULL,
  `status0` int DEFAULT NULL,
  `status1` int DEFAULT NULL,
  `status2` int DEFAULT NULL,
  `status3` int DEFAULT NULL,
  `status4` int DEFAULT NULL,
  `uptime` datetime DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of rpt_total_info
-- ----------------------------

-- ----------------------------
-- Table structure for rpt_trashcan_4hon4h_subtract_info
-- ----------------------------
DROP TABLE IF EXISTS `rpt_trashcan_4hon4h_subtract_info`;
CREATE TABLE `rpt_trashcan_4hon4h_subtract_info` (
  `id` varchar(255) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `user_top_flow` decimal(19,4) NOT NULL,
  `user_use_flow` decimal(19,4) NOT NULL,
  `user_real_top_flow` decimal(19,4) DEFAULT NULL,
  `user_real_use_flow` decimal(19,4) DEFAULT NULL,
  `status0` int DEFAULT NULL,
  `status1` int DEFAULT NULL,
  `status2` int DEFAULT NULL,
  `status3` int DEFAULT NULL,
  `status4` int DEFAULT NULL,
  `uptime` datetime DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of rpt_trashcan_4hon4h_subtract_info
-- ----------------------------

-- ----------------------------
-- Table structure for rpt_trashcan_total_info
-- ----------------------------
DROP TABLE IF EXISTS `rpt_trashcan_total_info`;
CREATE TABLE `rpt_trashcan_total_info` (
  `id` varchar(255) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `user_top_flow` decimal(19,4) NOT NULL,
  `user_use_flow` decimal(19,4) NOT NULL,
  `user_real_top_flow` decimal(19,4) DEFAULT NULL,
  `user_real_use_flow` decimal(19,4) DEFAULT NULL,
  `status0` int DEFAULT NULL,
  `status1` int DEFAULT NULL,
  `status2` int DEFAULT NULL,
  `status3` int DEFAULT NULL,
  `status4` int DEFAULT NULL,
  `uptime` datetime DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of rpt_trashcan_total_info
-- ----------------------------

-- ----------------------------
-- Table structure for store_terminnal_detail_coefficient
-- ----------------------------
DROP TABLE IF EXISTS `store_terminnal_detail_coefficient`;
CREATE TABLE `store_terminnal_detail_coefficient` (
  `id` int NOT NULL,
  `iccid` varchar(30) NOT NULL,
  `first_coefficient` decimal(10,2) NOT NULL DEFAULT '1.00',
  `second_coefficient` decimal(10,2) NOT NULL DEFAULT '1.00',
  PRIMARY KEY (`id`),
  UNIQUE KEY `iccid` (`iccid`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of store_terminnal_detail_coefficient
-- ----------------------------

-- ----------------------------
-- Table structure for t_activity
-- ----------------------------
DROP TABLE IF EXISTS `t_activity`;
CREATE TABLE `t_activity` (
  `id` varchar(40) NOT NULL,
  `activity_type` tinyint NOT NULL DEFAULT '0' COMMENT '1：首次关注送券活动，2：充值指定套餐送券活动',
  `begin_date` date NOT NULL,
  `coupon_num` int NOT NULL,
  `coupon_type` tinyint NOT NULL DEFAULT '0' COMMENT '1：打折券，2：现金购买券，3：流量券',
  `create_time` datetime DEFAULT NULL,
  `deleted` bit(1) NOT NULL,
  `denomination` decimal(19,2) NOT NULL,
  `enabled` bit(1) NOT NULL,
  `end_date` date NOT NULL,
  `flow` decimal(19,2) NOT NULL,
  `intro` varchar(255) DEFAULT NULL,
  `name` varchar(255) DEFAULT NULL,
  `update_time` datetime DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_activity
-- ----------------------------

-- ----------------------------
-- Table structure for t_activity_log
-- ----------------------------
DROP TABLE IF EXISTS `t_activity_log`;
CREATE TABLE `t_activity_log` (
  `id` varchar(40) NOT NULL,
  `activity_id` varchar(255) DEFAULT NULL,
  `create_time` datetime DEFAULT NULL,
  `user_coupon_id` varchar(255) DEFAULT NULL,
  `user_id` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_activity_log
-- ----------------------------

-- ----------------------------
-- Table structure for t_admin
-- ----------------------------
DROP TABLE IF EXISTS `t_admin`;
CREATE TABLE `t_admin` (
  `id` varchar(40) NOT NULL,
  `create_time` datetime DEFAULT NULL,
  `deleted` bit(1) NOT NULL,
  `enabled` bit(1) NOT NULL,
  `gender` int DEFAULT NULL,
  `is_super` bit(1) NOT NULL,
  `mobile` varchar(255) DEFAULT NULL,
  `name` varchar(255) DEFAULT NULL,
  `nickname` varchar(255) DEFAULT NULL,
  `password` varchar(255) NOT NULL,
  `username` varchar(255) DEFAULT NULL,
  `role_id` varchar(40) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `FKtacpsu83rn6i7jl7wiw9w7h8r` (`role_id`),
  CONSTRAINT `FKtacpsu83rn6i7jl7wiw9w7h8r` FOREIGN KEY (`role_id`) REFERENCES `t_role` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_admin
-- ----------------------------

-- ----------------------------
-- Table structure for t_agent
-- ----------------------------
DROP TABLE IF EXISTS `t_agent`;
CREATE TABLE `t_agent` (
  `id` varchar(40) NOT NULL,
  `avatar` varchar(255) DEFAULT NULL,
  `create_time` datetime DEFAULT NULL,
  `enabled` bit(1) NOT NULL,
  `level` int DEFAULT NULL,
  `parent_id` varchar(255) DEFAULT NULL,
  `password` varchar(255) DEFAULT NULL,
  `profit_ratio` decimal(19,2) DEFAULT NULL,
  `remark` varchar(255) DEFAULT NULL,
  `username` varchar(255) DEFAULT NULL,
  `transfer_profit_ratio` decimal(19,2) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_agent
-- ----------------------------

-- ----------------------------
-- Table structure for t_agent_coupon
-- ----------------------------
DROP TABLE IF EXISTS `t_agent_coupon`;
CREATE TABLE `t_agent_coupon` (
  `id` varchar(40) NOT NULL,
  `agent_id` varchar(255) DEFAULT NULL,
  `begin_date` date NOT NULL,
  `coupon_num` int NOT NULL,
  `coupon_type` tinyint NOT NULL DEFAULT '0',
  `create_time` datetime DEFAULT NULL,
  `deleted` bit(1) NOT NULL,
  `denomination` decimal(19,2) NOT NULL,
  `end_date` date NOT NULL,
  `name` varchar(255) DEFAULT NULL,
  `update_time` datetime DEFAULT NULL,
  `use_num` int NOT NULL DEFAULT '0',
  `rate_plan_id` varchar(40) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `FKejhat8uxqvffj6h0m8i35or9e` (`rate_plan_id`),
  CONSTRAINT `FKejhat8uxqvffj6h0m8i35or9e` FOREIGN KEY (`rate_plan_id`) REFERENCES `t_rate_plan` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_agent_coupon
-- ----------------------------

-- ----------------------------
-- Table structure for t_agent_pre_transfer
-- ----------------------------
DROP TABLE IF EXISTS `t_agent_pre_transfer`;
CREATE TABLE `t_agent_pre_transfer` (
  `id` varchar(40) NOT NULL,
  `agent_id` varchar(255) DEFAULT NULL,
  `coefficient` int DEFAULT NULL,
  `create_time` datetime DEFAULT NULL,
  `cycle_type` tinyint DEFAULT '0',
  `end_number_segment` int DEFAULT NULL,
  `single_card_flow` decimal(19,2) DEFAULT NULL,
  `single_card_price` decimal(19,2) DEFAULT NULL,
  `start_number_segment` int DEFAULT NULL,
  `to_agent_id` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_agent_pre_transfer
-- ----------------------------

-- ----------------------------
-- Table structure for t_agent_profit
-- ----------------------------
DROP TABLE IF EXISTS `t_agent_profit`;
CREATE TABLE `t_agent_profit` (
  `id` varchar(40) NOT NULL,
  `agent_id` varchar(255) DEFAULT NULL,
  `create_time` datetime DEFAULT NULL,
  `deleted` bit(1) NOT NULL,
  `iccid` varchar(255) DEFAULT NULL,
  `need_audit` bit(1) NOT NULL,
  `order_number` varchar(255) DEFAULT NULL,
  `order_pay_price` decimal(10,2) NOT NULL DEFAULT '0.00',
  `order_price` decimal(10,2) NOT NULL DEFAULT '0.00',
  `profit_price` decimal(10,2) NOT NULL DEFAULT '0.00',
  `profit_status` int DEFAULT NULL,
  `order_type` tinyint DEFAULT '0',
  `withdraw_apply_id` varchar(40) DEFAULT NULL COMMENT '提现申请单ID(NULL=未提现·乐观锁目标列)',
  `record_type` tinyint(4) NOT NULL DEFAULT '0' COMMENT '记录类型:0=分润(正)/1=冲账(负);B2恒0·B3才写1',
  `refund_source_order` varchar(255) DEFAULT NULL COMMENT '冲账源订单号(record_type=1时用·B3落地)',
  PRIMARY KEY (`id`),
  UNIQUE KEY `UKc4xjbh2so4uyo5k3ojwii4uux` (`agent_id`,`order_number`,`iccid`),
  KEY `idx_ap_withdraw_apply_id` (`withdraw_apply_id`),
  KEY `idx_ap_agent_status` (`agent_id`,`profit_status`,`record_type`),
  KEY `idx_ap_refund_source` (`order_number`,`record_type`,`deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_agent_profit
-- ----------------------------

-- ----------------------------
-- Table structure for t_agent_transfer_info
-- ----------------------------
DROP TABLE IF EXISTS `t_agent_transfer_info`;
CREATE TABLE `t_agent_transfer_info` (
  `id` varchar(40) NOT NULL,
  `create_time` datetime DEFAULT NULL,
  `cycle_month` int DEFAULT NULL,
  `error_msg` text,
  `from_agent_id` varchar(255) DEFAULT NULL,
  `iccid_info` text,
  `success` bit(1) NOT NULL,
  `to_agent_id` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_agent_transfer_info
-- ----------------------------

-- ----------------------------
-- Table structure for t_cmp_account
-- ----------------------------
DROP TABLE IF EXISTS `t_cmp_account`;
CREATE TABLE `t_cmp_account` (
  `id` varchar(40) NOT NULL,
  `iot_api_url` varchar(255) DEFAULT NULL,
  `iot_app_id` varchar(255) DEFAULT NULL,
  `iot_app_secret` varchar(255) DEFAULT NULL,
  `iot_open_id` varchar(255) DEFAULT NULL,
  `iot_version` varchar(255) DEFAULT NULL,
  `jasper_username` varchar(255) DEFAULT NULL,
  `username` varchar(255) DEFAULT NULL,
  `cookie` varchar(255) DEFAULT NULL,
  `password_encrypt` varchar(255) DEFAULT NULL,
  `username_encrypt` varchar(255) DEFAULT NULL,
  `acct_id` varchar(255) DEFAULT NULL,
  `smz_app_id` varchar(255) DEFAULT NULL,
  `smz_app_secret` varchar(255) DEFAULT NULL,
  `smz_app_url` varchar(255) DEFAULT NULL,
  `transfer_flow_id` bigint DEFAULT NULL,
  `flow_account_id` varchar(255) DEFAULT NULL,
  `enabled_sms` int DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_cmp_account
-- ----------------------------

-- ----------------------------
-- Table structure for t_cmp_comm_plan
-- ----------------------------
DROP TABLE IF EXISTS `t_cmp_comm_plan`;
CREATE TABLE `t_cmp_comm_plan` (
  `id` varchar(40) NOT NULL,
  `nac_desc` varchar(255) DEFAULT NULL,
  `nac_id` varchar(255) DEFAULT NULL,
  `nac_name` varchar(255) DEFAULT NULL,
  `nac_type` int DEFAULT NULL,
  `cmp_account_id` varchar(40) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `FK9anybrcfy3ube5nfheb1l12w2` (`cmp_account_id`),
  CONSTRAINT `FK9anybrcfy3ube5nfheb1l12w2` FOREIGN KEY (`cmp_account_id`) REFERENCES `t_cmp_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_cmp_comm_plan
-- ----------------------------

-- ----------------------------
-- Table structure for t_cmp_operate_log
-- ----------------------------
DROP TABLE IF EXISTS `t_cmp_operate_log`;
CREATE TABLE `t_cmp_operate_log` (
  `id` varchar(40) NOT NULL,
  `create_time` datetime DEFAULT NULL,
  `iccid` varchar(255) DEFAULT NULL,
  `new_status` varchar(255) DEFAULT NULL,
  `operate_type` int DEFAULT NULL,
  `status` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_cmp_operate_log
-- ----------------------------

-- ----------------------------
-- Table structure for t_cmp_push_log
-- ----------------------------
DROP TABLE IF EXISTS `t_cmp_push_log`;
CREATE TABLE `t_cmp_push_log` (
  `id` varchar(40) NOT NULL,
  `create_time` datetime DEFAULT NULL,
  `data` varchar(255) DEFAULT NULL,
  `event_type` varchar(255) DEFAULT NULL,
  `iot_app_id` varchar(255) DEFAULT NULL,
  `message_id` varchar(255) DEFAULT NULL,
  `version` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_cmp_push_log
-- ----------------------------

-- ----------------------------
-- Table structure for t_iccid
-- ----------------------------
DROP TABLE IF EXISTS `t_iccid`;
CREATE TABLE `t_iccid` (
  `iccid` varchar(255) NOT NULL,
  `agent_user_id` varchar(255) DEFAULT NULL,
  `agent_user_name` varchar(255) DEFAULT NULL,
  `created_date` datetime DEFAULT NULL,
  `cycle_type` int DEFAULT NULL,
  `jasper_rate_plan` varchar(255) DEFAULT NULL,
  `last_end_time` date DEFAULT NULL,
  `modified_date` datetime DEFAULT NULL,
  `msisdn` varchar(255) DEFAULT NULL,
  `number_segment` bigint DEFAULT NULL,
  `status` int DEFAULT NULL,
  `user_end_time` date DEFAULT NULL,
  `user_name` varchar(255) DEFAULT NULL,
  `user_start_time` date DEFAULT NULL,
  `user_top_flow` decimal(10,2) DEFAULT '0.00',
  `user_use_flow` decimal(10,2) DEFAULT '0.00',
  `jasper_account` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`iccid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_iccid
-- ----------------------------

-- ----------------------------
-- Table structure for t_interface_log
-- ----------------------------
DROP TABLE IF EXISTS `t_interface_log`;
CREATE TABLE `t_interface_log` (
  `id` varchar(40) NOT NULL,
  `create_time` datetime DEFAULT NULL,
  `req` text,
  `resp` text,
  `result` text,
  `type` int DEFAULT NULL,
  `url` text,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_interface_log
-- ----------------------------

-- ----------------------------
-- Table structure for t_lucky_draw
-- ----------------------------
DROP TABLE IF EXISTS `t_lucky_draw`;
CREATE TABLE `t_lucky_draw` (
  `id` varchar(40) NOT NULL,
  `actual_coefficient` double DEFAULT NULL,
  `coefficient` double DEFAULT NULL,
  `create_time` datetime DEFAULT NULL,
  `draw` bit(1) NOT NULL,
  `draw_time` datetime DEFAULT NULL,
  `openid` varchar(255) DEFAULT NULL,
  `order_number` varchar(255) DEFAULT NULL,
  `rate_plan_id` varchar(255) DEFAULT NULL,
  `user_coupon_id` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_lucky_draw
-- ----------------------------

-- ----------------------------
-- Table structure for t_menu
-- ----------------------------
DROP TABLE IF EXISTS `t_menu`;
CREATE TABLE `t_menu` (
  `id` varchar(40) NOT NULL,
  `create_time` datetime DEFAULT NULL,
  `icon` varchar(255) DEFAULT NULL,
  `is_super` bit(1) NOT NULL,
  `name` varchar(255) DEFAULT NULL,
  `path` varchar(255) DEFAULT NULL,
  `sequence` int NOT NULL,
  `type` int NOT NULL,
  `parent_id` varchar(40) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `FK4paxqyebl0scq6ur9osr0f56k` (`parent_id`),
  CONSTRAINT `FK4paxqyebl0scq6ur9osr0f56k` FOREIGN KEY (`parent_id`) REFERENCES `t_menu` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_menu
-- ----------------------------

-- ----------------------------
-- Table structure for t_order
-- ----------------------------
DROP TABLE IF EXISTS `t_order`;
CREATE TABLE `t_order` (
  `id` varchar(40) NOT NULL,
  `agent_id` varchar(255) DEFAULT NULL,
  `created_date` datetime DEFAULT NULL,
  `error_desc` text,
  `modified_date` datetime DEFAULT NULL,
  `order_number` varchar(32) NOT NULL,
  `order_type` tinyint DEFAULT '0',
  `pay_time` datetime DEFAULT NULL,
  `pay_total` decimal(10,2) NOT NULL DEFAULT '0.00',
  `pay_type` tinyint DEFAULT '0',
  `price_total` decimal(10,2) NOT NULL DEFAULT '0.00',
  `rate_plan_id` varchar(255) DEFAULT NULL,
  `refund_amount` decimal(10,2) DEFAULT '0.00',
  `refund_order_number` varchar(32) DEFAULT NULL,
  `single_card_flow` decimal(19,2) DEFAULT NULL,
  `single_card_price` decimal(19,2) DEFAULT NULL,
  `status` tinyint DEFAULT '1',
  `trade_no` varchar(255) DEFAULT NULL,
  `trade_status` tinyint DEFAULT '1',
  `user` varchar(255) DEFAULT NULL,
  `wx_app_id` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `UKnq76igeeo12bbi59hblq12526` (`order_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_order
-- ----------------------------

-- ----------------------------
-- Table structure for t_order_status_log
-- ----------------------------
DROP TABLE IF EXISTS `t_order_status_log`;
CREATE TABLE `t_order_status_log` (
  `id` varchar(40) NOT NULL,
  `created_date` datetime DEFAULT NULL,
  `modified_date` datetime DEFAULT NULL,
  `content` varchar(255) DEFAULT NULL,
  `new_status` int DEFAULT NULL,
  `old_status` int DEFAULT NULL,
  `order_number` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_order_status_log
-- ----------------------------

-- ----------------------------
-- Table structure for t_permission
-- ----------------------------
DROP TABLE IF EXISTS `t_permission`;
CREATE TABLE `t_permission` (
  `id` varchar(40) NOT NULL,
  `menu_id` varchar(40) DEFAULT NULL,
  `role_id` varchar(40) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `FKlovhacrw3uryaorleg014evd4` (`menu_id`),
  KEY `FK1rwkq1j8auw69w9t99r1wsamf` (`role_id`),
  CONSTRAINT `FK1rwkq1j8auw69w9t99r1wsamf` FOREIGN KEY (`role_id`) REFERENCES `t_role` (`id`),
  CONSTRAINT `FKlovhacrw3uryaorleg014evd4` FOREIGN KEY (`menu_id`) REFERENCES `t_menu` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_permission
-- ----------------------------

-- ----------------------------
-- Table structure for t_rate_plan
-- ----------------------------
DROP TABLE IF EXISTS `t_rate_plan`;
CREATE TABLE `t_rate_plan` (
  `id` varchar(40) NOT NULL,
  `create_time` datetime DEFAULT NULL,
  `cycle_type` int DEFAULT NULL,
  `flow` decimal(19,2) DEFAULT NULL,
  `reference_price` decimal(19,2) DEFAULT NULL,
  `update_time` datetime DEFAULT NULL,
  `first_charge` bit(1) NOT NULL,
  `free_flow` decimal(19,2) DEFAULT NULL,
  `order_index` int DEFAULT NULL,
  `nation` bit(1) NOT NULL,
  `cycle_month` int NOT NULL,
  `jasper_account` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_rate_plan
-- ----------------------------

-- ----------------------------
-- Table structure for t_rate_plan_copy1
-- ----------------------------
DROP TABLE IF EXISTS `t_rate_plan_copy1`;
CREATE TABLE `t_rate_plan_copy1` (
  `id` varchar(40) NOT NULL,
  `create_time` datetime DEFAULT NULL,
  `cycle_type` int DEFAULT NULL,
  `flow` decimal(19,2) DEFAULT NULL,
  `reference_price` decimal(19,2) DEFAULT NULL,
  `update_time` datetime DEFAULT NULL,
  `first_charge` bit(1) NOT NULL,
  `free_flow` decimal(19,2) DEFAULT NULL,
  `order_index` int DEFAULT NULL,
  `nation` bit(1) NOT NULL,
  `cycle_month` int NOT NULL,
  `jasper_account` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_rate_plan_copy1
-- ----------------------------

-- ----------------------------
-- Table structure for t_rate_plan_copy2
-- ----------------------------
DROP TABLE IF EXISTS `t_rate_plan_copy2`;
CREATE TABLE `t_rate_plan_copy2` (
  `id` varchar(40) NOT NULL,
  `create_time` datetime DEFAULT NULL,
  `cycle_type` int DEFAULT NULL,
  `flow` decimal(19,2) DEFAULT NULL,
  `reference_price` decimal(19,2) DEFAULT NULL,
  `update_time` datetime DEFAULT NULL,
  `first_charge` bit(1) NOT NULL,
  `free_flow` decimal(19,2) DEFAULT NULL,
  `order_index` int DEFAULT NULL,
  `nation` bit(1) NOT NULL,
  `cycle_month` int NOT NULL,
  `jasper_account` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_rate_plan_copy2
-- ----------------------------

-- ----------------------------
-- Table structure for t_role
-- ----------------------------
DROP TABLE IF EXISTS `t_role`;
CREATE TABLE `t_role` (
  `id` varchar(40) NOT NULL,
  `create_time` datetime DEFAULT NULL,
  `desc` varchar(255) DEFAULT NULL,
  `is_super` bit(1) NOT NULL,
  `name` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_role
-- ----------------------------

-- ----------------------------
-- Table structure for t_sys_dictionary
-- ----------------------------
DROP TABLE IF EXISTS `t_sys_dictionary`;
CREATE TABLE `t_sys_dictionary` (
  `code_id` varchar(128) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `code_value` text CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL,
  `remark` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`code_id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8 ROW_FORMAT=COMPACT;

-- ----------------------------
-- Records of t_sys_dictionary
-- ----------------------------

-- ----------------------------
-- Table structure for t_user
-- ----------------------------
DROP TABLE IF EXISTS `t_user`;
CREATE TABLE `t_user` (
  `openid` varchar(255) NOT NULL,
  `avatar_url` varchar(255) DEFAULT NULL,
  `city` varchar(255) DEFAULT NULL,
  `country` varchar(255) DEFAULT NULL,
  `create_time` datetime DEFAULT NULL,
  `disclaimer` bit(1) NOT NULL,
  `has_first_charge` bit(1) NOT NULL,
  `language` varchar(255) DEFAULT NULL,
  `login_count` bigint DEFAULT NULL,
  `nickname` varchar(255) DEFAULT NULL,
  `province` varchar(255) DEFAULT NULL,
  `remark` varchar(255) DEFAULT NULL,
  `sex` int DEFAULT NULL,
  `subscribe` bit(1) DEFAULT NULL,
  `subscribe_time` datetime DEFAULT NULL,
  `wx_app_id` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`openid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_user
-- ----------------------------

-- ----------------------------
-- Table structure for t_user_coupon
-- ----------------------------
DROP TABLE IF EXISTS `t_user_coupon`;
CREATE TABLE `t_user_coupon` (
  `id` varchar(40) NOT NULL,
  `begin_date` date NOT NULL,
  `coupon_num` int NOT NULL,
  `coupon_type` tinyint NOT NULL DEFAULT '0',
  `create_time` datetime DEFAULT NULL,
  `deleted` bit(1) NOT NULL,
  `denomination` decimal(19,2) NOT NULL,
  `end_date` date NOT NULL,
  `name` varchar(255) DEFAULT NULL,
  `update_time` datetime DEFAULT NULL,
  `use_num` int NOT NULL DEFAULT '0',
  `user_id` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ----------------------------
-- Records of t_user_coupon
-- ----------------------------

-- =============================================================================
-- REQ-20260920-01 B1/B2/B3 镜像表（phase2 L1 冒烟缺表根治·任务A[B2/B3]·任务D[B1]·2026-10-14）
-- 来源：逐字镜像 src/sql/REQ-20260920-01-B1-分润计算改造.sql（t_agent_profit_zero_log）+ -B2-提现闭环报表.sql（8 表）+ -B3-退款恢复.sql（t_order_refund_job）。
-- 范式对齐：DROP+CREATE（同本 schema 38 表）·表名/列名加反引号；列/类型/可空/默认/索引/枚举 ordinal 与 B1/B2/B3 逐字一致防漂移。
-- t_agent_profit 的 B2 三列（withdraw_apply_id/record_type/refund_source_order）+ 三索引已内联进上方 CREATE TABLE（幂等·全新重建自带）。
-- re_order_iccid 的 B1/REQ-20260918-01 三列（utc_recharge_id/card_cycle_type/actual_deduct_flow·14→17 列）已内联进上方 CREATE TABLE（基线漂移根治·任务E 全面核对坐实仅此表列漂移）。
-- t_order_refund_job 的 27 列 + 4 索引与 FinanceRefundSchemaGuard.refresh() 就绪探针判据完全一致（补表+重启 app 后 ready=true）。
-- 边界：仅 ryd_unicard_agentmp 独立库；ryd_utc/ryd_unicard/fuzhoukuaifu 零扰动（D6/D21）。
-- =============================================================================

-- ----------------------------
-- Table structure for t_agent_profit_zero_log (REQ-20260920-01 B1·零分润台账·方案甲·8原因码)
-- ----------------------------
DROP TABLE IF EXISTS `t_agent_profit_zero_log`;
CREATE TABLE `t_agent_profit_zero_log` (
  `id` varchar(40) NOT NULL COMMENT '主键(框架分配)',
  `iccid` varchar(255) DEFAULT NULL COMMENT '卡号',
  `order_number` varchar(255) DEFAULT NULL COMMENT '订单编号',
  `order_type` tinyint(4) DEFAULT NULL COMMENT 'OrderType ordinal',
  `agent_id` varchar(255) DEFAULT NULL COMMENT '归属经销商ID(关卡③可能为空)',
  `reason_code` int(11) NOT NULL COMMENT 'ZeroProfitReason ordinal(0..7)',
  `reason_desc` varchar(255) DEFAULT NULL COMMENT '原因描述',
  `single_card_price` decimal(10,2) DEFAULT NULL COMMENT '利润快照:单卡价',
  `discount_amount` decimal(10,2) DEFAULT NULL COMMENT '利润快照:优惠额',
  `actual_deduct_flow` decimal(20,3) DEFAULT NULL COMMENT '利润快照:实际扣池量',
  `cost_price` decimal(10,4) DEFAULT NULL COMMENT '利润快照:成本价C',
  `single_card_profit` decimal(20,6) DEFAULT NULL COMMENT '利润快照:单卡利润',
  `agent_profit_amount` decimal(20,6) DEFAULT NULL COMMENT '利润快照:经销商应得利润',
  `coupon_id` varchar(255) DEFAULT NULL COMMENT '经销商券ID',
  `coupon_type` varchar(32) DEFAULT NULL COMMENT '券类型名(DISCOUNT/CASH/FLOW)',
  `root_profit` decimal(20,6) DEFAULT NULL COMMENT 'interfj应得利润(券分支B)',
  `create_time` datetime DEFAULT NULL COMMENT '创建时间',
  PRIMARY KEY (`id`),
  KEY `idx_zpl_iccid` (`iccid`),
  KEY `idx_zpl_order_number` (`order_number`),
  KEY `idx_zpl_agent_id` (`agent_id`),
  KEY `idx_zpl_reason_code` (`reason_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='零分润台账(REQ-20260920-01 B1·方案甲·8原因码)';

-- ----------------------------
-- Records of t_agent_profit_zero_log
-- ----------------------------

-- ----------------------------
-- Table structure for t_agent_withdraw_apply (REQ-20260920-01 B2)
-- ----------------------------
DROP TABLE IF EXISTS `t_agent_withdraw_apply`;
CREATE TABLE `t_agent_withdraw_apply` (
  `id` varchar(40) NOT NULL COMMENT '主键(框架分配)',
  `agent_id` varchar(40) NOT NULL COMMENT '申请经销商ID',
  `apply_time` datetime NOT NULL COMMENT '申请时间',
  `apply_amount` decimal(14,2) NOT NULL DEFAULT '0' COMMENT '申请总额=Σ勾选月month_amount',
  `withdraw_task_id` varchar(40) DEFAULT NULL COMMENT '归属财务任务单ID(节点日汇总回填·NULL=待汇总)',
  `status` int(11) NOT NULL DEFAULT '2' COMMENT '四态联动(AgentProfitStatus ordinal):2审核中/3转账中/4已提现',
  `created_date` datetime DEFAULT NULL COMMENT '框架审计列',
  `modified_date` datetime DEFAULT NULL COMMENT '框架审计列',
  PRIMARY KEY (`id`),
  KEY `idx_awa_agent_id` (`agent_id`),
  KEY `idx_awa_task_id` (`withdraw_task_id`),
  KEY `idx_awa_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='提现申请单(REQ-20260920-01 B2·三层表中列)';

-- ----------------------------
-- Table structure for t_agent_withdraw_apply_month (REQ-20260920-01 B2·筷子表)
-- ----------------------------
DROP TABLE IF EXISTS `t_agent_withdraw_apply_month`;
CREATE TABLE `t_agent_withdraw_apply_month` (
  `id` varchar(40) NOT NULL COMMENT '主键(框架分配)',
  `apply_id` varchar(40) NOT NULL COMMENT 'FK→t_agent_withdraw_apply.id',
  `bill_month` varchar(7) NOT NULL COMMENT '账单月 YYYY-MM',
  `month_amount` decimal(14,2) NOT NULL DEFAULT '0' COMMENT '申请时点该月净额快照',
  `created_date` datetime DEFAULT NULL COMMENT '框架审计列',
  `modified_date` datetime DEFAULT NULL COMMENT '框架审计列',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_awam_apply_month` (`apply_id`,`bill_month`),
  KEY `idx_awam_bill_month` (`bill_month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='提现申请单↔账单月筷子表(REQ-20260920-01 B2·month_amount快照)';

-- ----------------------------
-- Table structure for t_agent_withdraw_task (REQ-20260920-01 B2)
-- ----------------------------
DROP TABLE IF EXISTS `t_agent_withdraw_task`;
CREATE TABLE `t_agent_withdraw_task` (
  `id` varchar(40) NOT NULL COMMENT '主键(框架分配)',
  `batch_node` date NOT NULL COMMENT '批次节点日(7/17/27/月末)',
  `period_start` date NOT NULL COMMENT '汇总期间起(上一节点次日)',
  `period_end` date NOT NULL COMMENT '汇总期间止(本节点日)',
  `notify_status` int(11) NOT NULL DEFAULT '0' COMMENT '0待通知/1已通知/2失败',
  `process_status` int(11) NOT NULL DEFAULT '0' COMMENT '0待处理/1转账中/2已打款',
  `auditor` varchar(40) DEFAULT NULL COMMENT '处理财务(level0用户ID)',
  `process_time` datetime DEFAULT NULL COMMENT '⑧b处理时间(→转账中)',
  `transfer_time` datetime DEFAULT NULL COMMENT '⑧c打款时间(→已打款)',
  `created_date` datetime DEFAULT NULL COMMENT '框架审计列',
  `modified_date` datetime DEFAULT NULL COMMENT '框架审计列',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_awt_batch_node` (`batch_node`),
  KEY `idx_awt_process_status` (`process_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='提现节点任务单(REQ-20260920-01 B2·三层表下列·财务处理对象)';

-- ----------------------------
-- Table structure for t_agent_profit_report (REQ-20260920-01 B2)
-- ----------------------------
DROP TABLE IF EXISTS `t_agent_profit_report`;
CREATE TABLE `t_agent_profit_report` (
  `id` varchar(40) NOT NULL COMMENT '主键(框架分配)',
  `report_month` varchar(7) NOT NULL COMMENT '报表月 YYYY-MM',
  `agent_id` varchar(40) NOT NULL COMMENT '经销商ID',
  `agent_name` varchar(255) DEFAULT NULL COMMENT '快照 Agent.username',
  `agent_level` int(11) DEFAULT NULL COMMENT '快照 Agent.level',
  `parent_agent_id` varchar(40) DEFAULT NULL COMMENT '快照 Agent.parentId(团队账单下溯用)',
  `gross_amount` decimal(14,2) NOT NULL DEFAULT '0' COMMENT '毛额=Σprofit_price(record_type=0)',
  `refund_amount` decimal(14,2) NOT NULL DEFAULT '0' COMMENT '冲账额=Σprofit_price(record_type=1·负·B2恒0)',
  `net_amount` decimal(14,2) NOT NULL DEFAULT '0' COMMENT '净额=gross+refund',
  `profit_count` int(11) NOT NULL DEFAULT '0' COMMENT '分润笔数(record_type=0)',
  `refund_count` int(11) NOT NULL DEFAULT '0' COMMENT '冲账笔数(record_type=1·B2恒0)',
  `generated_time` datetime NOT NULL COMMENT '报表生成时间',
  `created_date` datetime DEFAULT NULL COMMENT '框架审计列',
  `modified_date` datetime DEFAULT NULL COMMENT '框架审计列',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_apr_month_agent` (`report_month`,`agent_id`),
  KEY `idx_apr_agent_id` (`agent_id`),
  KEY `idx_apr_parent` (`parent_agent_id`,`report_month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='月度应收报表主表(REQ-20260920-01 B2·权责制·3日固化)';

-- ----------------------------
-- Table structure for t_agent_profit_report_detail (REQ-20260920-01 B2)
-- ----------------------------
DROP TABLE IF EXISTS `t_agent_profit_report_detail`;
CREATE TABLE `t_agent_profit_report_detail` (
  `id` varchar(40) NOT NULL COMMENT '主键(框架分配)',
  `report_id` varchar(40) NOT NULL COMMENT 'FK→t_agent_profit_report.id',
  `profit_id` varchar(40) NOT NULL COMMENT 'FK→t_agent_profit.id(溯源)',
  `iccid` varchar(255) DEFAULT NULL COMMENT '卡号快照',
  `order_number` varchar(255) DEFAULT NULL COMMENT '订单号快照',
  `order_type` tinyint(4) DEFAULT NULL COMMENT 'OrderType ordinal 快照',
  `record_type` tinyint(4) NOT NULL DEFAULT '0' COMMENT '0分润/1冲账快照',
  `order_price` decimal(10,2) DEFAULT NULL COMMENT '单价快照',
  `order_pay_price` decimal(10,2) DEFAULT NULL COMMENT '实付快照',
  `profit_price` decimal(20,6) DEFAULT NULL COMMENT '利润快照(精度对齐源列·L4核实)',
  `source_create_time` datetime DEFAULT NULL COMMENT '源create_time(定月份)',
  `created_date` datetime DEFAULT NULL COMMENT '框架审计列',
  `modified_date` datetime DEFAULT NULL COMMENT '框架审计列',
  PRIMARY KEY (`id`),
  KEY `idx_aprd_report_id` (`report_id`),
  KEY `idx_aprd_profit_id` (`profit_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='月度应收报表明细快照(REQ-20260920-01 B2)';

-- ----------------------------
-- Table structure for t_agent_withdraw_report (REQ-20260920-01 B2)
-- ----------------------------
DROP TABLE IF EXISTS `t_agent_withdraw_report`;
CREATE TABLE `t_agent_withdraw_report` (
  `id` varchar(40) NOT NULL COMMENT '主键(框架分配)',
  `withdraw_task_id` varchar(40) NOT NULL COMMENT 'FK→t_agent_withdraw_task.id',
  `batch_node` date NOT NULL COMMENT '批次节点日快照',
  `period_start` date NOT NULL COMMENT '期间起快照',
  `period_end` date NOT NULL COMMENT '期间止快照',
  `agent_id` varchar(40) NOT NULL COMMENT '经销商ID',
  `agent_name` varchar(255) DEFAULT NULL COMMENT '快照 Agent.username',
  `apply_count` int(11) NOT NULL DEFAULT '0' COMMENT '本节点该经销商申请单数',
  `total_amount` decimal(14,2) NOT NULL DEFAULT '0' COMMENT '本节点该经销商应付合计',
  `process_status` int(11) NOT NULL DEFAULT '0' COMMENT '快照任务单处理态:0待处理/1转账中/2已打款',
  `auditor` varchar(40) DEFAULT NULL COMMENT '处理财务快照',
  `transfer_time` datetime DEFAULT NULL COMMENT '打款时间快照',
  `generated_time` datetime NOT NULL COMMENT '报表生成时间',
  `created_date` datetime DEFAULT NULL COMMENT '框架审计列',
  `modified_date` datetime DEFAULT NULL COMMENT '框架审计列',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_awr_task_agent` (`withdraw_task_id`,`agent_id`),
  KEY `idx_awr_agent_id` (`agent_id`),
  KEY `idx_awr_batch_node` (`batch_node`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='节点汇总报表主表(REQ-20260920-01 B2·收付制·7/17/27/末)';

-- ----------------------------
-- Table structure for t_agent_withdraw_report_detail (REQ-20260920-01 B2)
-- ----------------------------
DROP TABLE IF EXISTS `t_agent_withdraw_report_detail`;
CREATE TABLE `t_agent_withdraw_report_detail` (
  `id` varchar(40) NOT NULL COMMENT '主键(框架分配)',
  `report_id` varchar(40) NOT NULL COMMENT 'FK→t_agent_withdraw_report.id',
  `apply_id` varchar(40) NOT NULL COMMENT 'FK→t_agent_withdraw_apply.id',
  `apply_time` datetime DEFAULT NULL COMMENT '申请时间快照',
  `bill_month` varchar(7) NOT NULL COMMENT '账单月(关联键·对账月度报表)',
  `month_amount` decimal(14,2) NOT NULL DEFAULT '0' COMMENT '该月净额快照(源筷子表)',
  `apply_amount` decimal(14,2) NOT NULL DEFAULT '0' COMMENT '所属申请单总额快照',
  `created_date` datetime DEFAULT NULL COMMENT '框架审计列',
  `modified_date` datetime DEFAULT NULL COMMENT '框架审计列',
  PRIMARY KEY (`id`),
  KEY `idx_awrd_report_id` (`report_id`),
  KEY `idx_awrd_apply_id` (`apply_id`),
  KEY `idx_awrd_bill_month` (`bill_month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='节点汇总报表明细快照(REQ-20260920-01 B2·源筷子表)';

-- ----------------------------
-- Table structure for t_finance_withdraw_audit (REQ-20260920-01 B2 PR-4)
-- ----------------------------
DROP TABLE IF EXISTS `t_finance_withdraw_audit`;
CREATE TABLE `t_finance_withdraw_audit` (
  `id` varchar(40) NOT NULL COMMENT '主键(框架分配)',
  `operator_id` varchar(40) DEFAULT NULL COMMENT '操作财务(level0用户ID)',
  `action_type` tinyint(4) NOT NULL DEFAULT '0' COMMENT '动作:0验证成功/1验证失败/2处理/3打款(枚举ordinal·B3 REFUND=4 尾部追加)',
  `withdraw_task_id` varchar(40) DEFAULT NULL COMMENT '关联任务单ID(密码验证为NULL)',
  `amount` decimal(14,2) DEFAULT NULL COMMENT '关联任务单应付总额(密码验证为NULL)',
  `source_ip` varchar(64) DEFAULT NULL COMMENT '来源IP(X-Forwarded-For首段或RemoteAddr)',
  `remark` varchar(255) DEFAULT NULL COMMENT '补充说明(结果/状态迁移)',
  `created_date` datetime DEFAULT NULL COMMENT '框架审计列(发生时间)',
  `modified_date` datetime DEFAULT NULL COMMENT '框架审计列',
  PRIMARY KEY (`id`),
  KEY `idx_fwa_task_id` (`withdraw_task_id`),
  KEY `idx_fwa_action_type` (`action_type`),
  KEY `idx_fwa_created_date` (`created_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='财务提现审计(REQ-20260920-01 B2 PR-4增补·append-only)';

-- ----------------------------
-- Table structure for t_order_refund_job (REQ-20260920-01 B3·27列+4索引与 FinanceRefundSchemaGuard 探针逐字对齐)
-- ----------------------------
DROP TABLE IF EXISTS `t_order_refund_job`;
CREATE TABLE `t_order_refund_job` (
  `id` varchar(40) NOT NULL COMMENT '框架主键',
  `order_id` varchar(40) NOT NULL COMMENT '原订单主键，一订单仅一主动job',
  `order_number` varchar(32) NOT NULL COMMENT '冻结原单号',
  `refund_no` varchar(32) NOT NULL COMMENT '稳定退款号，不因超时重启换号',
  `wx_app_id` varchar(64) NOT NULL COMMENT '冻结公众号',
  `amount` decimal(10,2) NOT NULL COMMENT '冻结全额实付',
  `source_refs` text NOT NULL COMMENT '版本化JSON：关联ID、iccid、UTC流水映射',
  `stage` varchar(24) NOT NULL COMMENT '阶段名称，不使用ordinal',
  `utc_attempts` int NOT NULL DEFAULT '0',
  `wx_submit_attempts` int NOT NULL DEFAULT '0',
  `wx_query_attempts` int NOT NULL DEFAULT '0',
  `ledger_attempts` int NOT NULL DEFAULT '0',
  `utc_confirmed_at` datetime(3) DEFAULT NULL,
  `wx_refund_id` varchar(64) DEFAULT NULL,
  `wx_accepted_at` datetime(3) DEFAULT NULL COMMENT '平台受理时间，非退款成功时间',
  `refund_confirmed_at` datetime(3) DEFAULT NULL COMMENT '平台真实退款成功时间，冲账归月依据',
  `next_retry_at` datetime(3) DEFAULT NULL,
  `lease_owner` varchar(64) DEFAULT NULL,
  `lease_until` datetime(3) DEFAULT NULL,
  `version` bigint NOT NULL DEFAULT '0' COMMENT 'CAS令牌，抢占和释放递增，心跳不递增',
  `last_code` varchar(64) DEFAULT NULL,
  `last_message` varchar(512) DEFAULT NULL COMMENT '脱敏截断摘要，不存原始支付响应',
  `operator_id` varchar(40) NOT NULL,
  `source_ip` varchar(64) DEFAULT NULL,
  `review_stage` varchar(24) DEFAULT NULL COMMENT '人工核查前阶段',
  `created_date` datetime(3) DEFAULT NULL,
  `modified_date` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_refund_order` (`order_id`),
  UNIQUE KEY `uk_refund_no` (`refund_no`),
  KEY `idx_refund_due` (`wx_app_id`,`stage`,`next_retry_at`),
  KEY `idx_refund_source` (`order_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='B3主动退款来源隔离与持久化恢复';

-- =============================================================================
-- REQ-20260909-01 经销商充值改造（一期）· C1 充值业务台账镜像表（任务F·承主管 §五请裁 2 问均 YES·2026-10-15）
-- 来源：逐字镜像 src/sql/t_agent_recharge_log.sql（13 列·PK id + 3 索引 iccid/agent_id/create_time·CHARSET=utf8）。
-- 语义：C1 充值业务台账（写·逐卡记操作人/扣池参数/成功失败/failCode/UTC 摘要）·C7 充值历史数据源（读·recharge/history 端点）。
-- 建表机制：现网 ryd_unicard 走 hibernate ddl-auto=update 由 @Entity AgentRechargeLog 自动建表；agent-mp 本实例库 ddl-auto 非 update
--          → 本 DDL 幂等内联补建（IF NOT EXISTS·与源 sql 一致·--recreate 全新库/既有库两路皆安全）；索引源 sql 已含·此处逐字镜像。
-- 边界：仅 ryd_unicard_agentmp 独立库；ryd_utc/ryd_unicard/fuzhoukuaifu 零扰动（D6/D21）。
-- =============================================================================

-- ----------------------------
-- Table structure for t_agent_recharge_log (REQ-20260909-01 C1 写/C7 读·经销商充值业务台账)
-- ----------------------------
CREATE TABLE IF NOT EXISTS `t_agent_recharge_log` (
  `id` varchar(40) NOT NULL,
  `iccid` varchar(40) DEFAULT NULL COMMENT '卡号',
  `agent_id` varchar(40) DEFAULT NULL COMMENT '操作人（登录经销商 Agent.id）',
  `flow` decimal(19,2) DEFAULT NULL COMMENT '充值流量(G)',
  `months` int DEFAULT NULL COMMENT '周期时长(月,1-12)',
  `start_time` datetime DEFAULT NULL COMMENT '周期开始时间',
  `actual_flow_account_id` bigint DEFAULT NULL COMMENT '扣池账号(一期不传,由UTC回退扣卡接线池,预留)',
  `success` bit(1) DEFAULT NULL COMMENT '是否成功',
  `fail_code` varchar(40) DEFAULT NULL COMMENT '失败稳定码(RechargeFailCode.code,成功时null)',
  `fail_reason` text COMMENT '失败原因(中文,成功时null)',
  `source` varchar(20) DEFAULT NULL COMMENT '来源(一期固定 threeants)',
  `utc_summary` text COMMENT 'UTC请求/响应摘要(排障)',
  `create_time` datetime DEFAULT NULL COMMENT '创建时间',
  PRIMARY KEY (`id`),
  KEY `idx_agent_recharge_log_iccid` (`iccid`),
  KEY `idx_agent_recharge_log_agent_id` (`agent_id`),
  KEY `idx_agent_recharge_log_create_time` (`create_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='经销商充值业务台账(REQ-20260909-01 C1写/C7读)';

-- ----------------------------
-- Records of t_agent_recharge_log
-- ----------------------------

-- ----------------------------
-- Procedure structure for proc_insert_rpt_total_4hon4h
-- ----------------------------
DROP PROCEDURE IF EXISTS `proc_insert_rpt_total_4hon4h`;
delimiter ;;
CREATE PROCEDURE `proc_insert_rpt_total_4hon4h`()
BEGIN
	#Routine body goes here...
	BEGIN
		INSERT INTO rpt_total_info SELECT	md5(uuid()),	floor(sum(a.user_top_flow) / 1024) AS `user_top_flow`,	floor(sum(a.user_use_flow) / 1024) AS `user_use_flow`,	floor(sum(a.user_top_flow) * b.second_coefficient / 1024) AS `user_real_top_flow`,	floor(sum(a.user_use_flow) * b.second_coefficient / 1024) AS `user_real_use_flow`,	sum(IF(`status` = 0, 1, 0)) AS `status0`,	sum(IF(`status` = 1, 1, 0)) AS `status1`,	sum(IF(`status` = 2, 1, 0)) AS `status2`,	sum(IF(`status` = 3, 1, 0)) AS `status3`,	sum(IF(`status` = 4, 1, 0)) AS `status4`,	now() AS `uptime` FROM 	t_iccid a INNER JOIN store_terminnal_detail_coefficient b on b.iccid = a.iccid;
	end;
	select SLEEP(2);
	BEGIN
		INSERT INTO rpt_4hon4h_subtract_info SELECT	md5(uuid()),	IFNULL(new_uptime.user_top_flow - old_uptime.user_top_flow,0), 	ifnull(new_uptime.user_use_flow - old_uptime.user_use_flow,0), 	new_uptime.user_real_top_flow - old_uptime.user_real_top_flow, 	new_uptime.user_real_use_flow - old_uptime.user_real_use_flow, 	new_uptime.status0 - old_uptime.status0, 	new_uptime.status1 - old_uptime.status1, 	new_uptime.status2 - old_uptime.status2, 	new_uptime.status3 - old_uptime.status3, 	new_uptime.status4 - old_uptime.status4, 	new_uptime.uptime FROM 	(		SELECT			a.user_top_flow,			a.user_use_flow,			a.user_real_top_flow,			a.user_real_use_flow,			a.status0,			a.status1,			a.status2,			a.status3,			a.status4,			a.uptime		FROM			rpt_total_info a		WHERE			a.uptime BETWEEN DATE_ADD(now(), INTERVAL - 4 HOUR)		AND now() order by uptime desc limit	1 ) new_uptime,	(		SELECT			b.user_top_flow,			b.user_use_flow,			b.user_real_top_flow,			b.user_real_use_flow,			b.status0,			b.status1,			b.status2,			b.status3,			b.status4,			b.uptime		FROM			rpt_total_info b		WHERE			b.uptime BETWEEN DATE_ADD(now(), INTERVAL - 8 HOUR)		AND DATE_ADD(now(), INTERVAL - 4 HOUR)  order by uptime desc limit 1	) old_uptime;
	END;


	BEGIN
		INSERT INTO rpt_trashcan_total_info SELECT	md5(uuid()),	ceil(sum(a.user_top_flow) / 1024) AS `user_top_flow`,	ceil(sum(a.user_use_flow) / 1024) AS `user_use_flow`,	ceil(sum(a.user_top_flow) * b.second_coefficient / 1024) AS `user_real_top_flow`,	ceil(sum(a.user_use_flow) * b.second_coefficient / 1024) AS `user_real_use_flow`,	sum(IF(`status` = 0, 1, 0)) AS `status0`,	sum(IF(`status` = 1, 1, 0)) AS `status1`,	sum(IF(`user_use_flow` <> 0, 1, 0)) AS `status2`,	sum(IF(`status` = 3, 1, 0)) AS `status3`,	sum(IF(`status` = 4, 1, 0)) AS `status4`,	now() AS `uptime` FROM 	t_iccid a INNER JOIN store_terminnal_detail_coefficient b on b.iccid = a.iccid where a.iccid BETWEEN '8986000000000000000' and '8986000000000000000';
	end;
	select SLEEP(2);
	BEGIN
		INSERT INTO rpt_trashcan_4hon4h_subtract_info SELECT	md5(uuid()),	IFNULL(new_uptime.user_top_flow - old_uptime.user_top_flow,0), 	ifnull(new_uptime.user_use_flow - old_uptime.user_use_flow,0), 	new_uptime.user_real_top_flow - old_uptime.user_real_top_flow, 	new_uptime.user_real_use_flow - old_uptime.user_real_use_flow, 	new_uptime.status0 - old_uptime.status0, 	new_uptime.status1 - old_uptime.status1, 	new_uptime.status2 - old_uptime.status2, 	new_uptime.status3 - old_uptime.status3, 	new_uptime.status4 - old_uptime.status4, 	new_uptime.uptime FROM 	(		SELECT			a.user_top_flow,			a.user_use_flow,			a.user_real_top_flow,			a.user_real_use_flow,			a.status0,			a.status1,			a.status2,			a.status3,			a.status4,			a.uptime		FROM			rpt_trashcan_total_info a		WHERE			a.uptime BETWEEN DATE_ADD(now(), INTERVAL - 4 HOUR)		AND now() order by uptime desc limit	1 ) new_uptime,	(		SELECT			b.user_top_flow,			b.user_use_flow,			b.user_real_top_flow,			b.user_real_use_flow,			b.status0,			b.status1,			b.status2,			b.status3,			b.status4,			b.uptime		FROM			rpt_trashcan_total_info b		WHERE			b.uptime BETWEEN DATE_ADD(now(), INTERVAL - 8 HOUR)		AND DATE_ADD(now(), INTERVAL - 4 HOUR)  order by uptime desc limit 1	) old_uptime;
	END;
END
;;
delimiter ;

SET FOREIGN_KEY_CHECKS = 1;
