-- Apteka Bober DWH: 01_schema.sql (DDL: 28 таблиц, индексы и ограничения)
USE pteka_bober;
SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS ai_demand_log;
CREATE TABLE `ai_demand_log` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `store_id` int unsigned NOT NULL,
  `goods_id` int unsigned NOT NULL,
  `scan_timestamp` datetime NOT NULL,
  `lost_qty` int NOT NULL DEFAULT '1',
  `rejection_reason` enum('OUT_OF_STOCK','PRICE','QUEUE','INCOMPETENCE','UNKNOWN') COLLATE utf8mb4_unicode_ci DEFAULT 'UNKNOWN',
  `raw_audio_text` varchar(500) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Расшифровка фразы',
  `ai_confidence` decimal(4,2) DEFAULT '1.00',
  `is_converted_to_sale` tinyint(1) DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `fk_ai_store` (`store_id`),
  KEY `fk_ai_goods` (`goods_id`),
  CONSTRAINT `fk_ai_goods` FOREIGN KEY (`goods_id`) REFERENCES `goods` (`goods_id`),
  CONSTRAINT `fk_ai_store` FOREIGN KEY (`store_id`) REFERENCES `stores` (`store_id`)
) ENGINE=InnoDB AUTO_INCREMENT=1141 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS ai_omni_audit_log;
CREATE TABLE `ai_omni_audit_log` (
  `audit_id` int unsigned NOT NULL AUTO_INCREMENT,
  `store_id` int unsigned NOT NULL,
  `employee_id` int unsigned DEFAULT NULL,
  `goods_id` int unsigned DEFAULT NULL,
  `log_timestamp` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `audit_reason` enum('PRICE_OBJECTION','QUEUE_PEAK','LOW_UX_SKILLS','DEFECTURA','NO_RECIPE','NON_COMMERCIAL') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `raw_ai_transcript` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci COMMENT 'Что услышал/увидел ИИ у кассы',
  PRIMARY KEY (`audit_id`),
  KEY `fk_ai_audit_stores` (`store_id`),
  KEY `fk_ai_audit_employees` (`employee_id`),
  CONSTRAINT `fk_ai_audit_employees` FOREIGN KEY (`employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `fk_ai_audit_stores` FOREIGN KEY (`store_id`) REFERENCES `stores` (`store_id`)
) ENGINE=InnoDB AUTO_INCREMENT=497 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Лог ИИ-фиксации событий в торговом зале';

DROP TABLE IF EXISTS bonus_cards;
CREATE TABLE `bonus_cards` (
  `card_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `card_number` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `holder_name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `issued_at` date NOT NULL,
  PRIMARY KEY (`card_id`),
  UNIQUE KEY `uq_card_number` (`card_number`)
) ENGINE=InnoDB AUTO_INCREMENT=13851 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS category_seasonality;
CREATE TABLE `category_seasonality` (
  `group_id` int unsigned NOT NULL,
  `season` enum('WINTER','SPRING','SUMMER','AUTUMN') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `boost_qty` smallint unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`group_id`,`season`),
  CONSTRAINT `fk_season_group` FOREIGN KEY (`group_id`) REFERENCES `pharm_groups` (`group_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS clinical_bundle_items;
CREATE TABLE `clinical_bundle_items` (
  `bundle_id` int unsigned NOT NULL,
  `goods_id` int unsigned NOT NULL,
  PRIMARY KEY (`bundle_id`,`goods_id`),
  KEY `fk_cbi_goods` (`goods_id`),
  CONSTRAINT `fk_cbi_bundle` FOREIGN KEY (`bundle_id`) REFERENCES `clinical_bundles` (`bundle_id`),
  CONSTRAINT `fk_cbi_goods` FOREIGN KEY (`goods_id`) REFERENCES `goods` (`goods_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS clinical_bundles;
CREATE TABLE `clinical_bundles` (
  `bundle_id` int unsigned NOT NULL AUTO_INCREMENT,
  `bundle_name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'нозология / название комплекса',
  PRIMARY KEY (`bundle_id`)
) ENGINE=InnoDB AUTO_INCREMENT=20 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS competitor_prices;
CREATE TABLE `competitor_prices` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `store_id` int unsigned NOT NULL COMMENT 'наша аптека, рядом с которой конкурент',
  `goods_id` int unsigned NOT NULL,
  `competitor_name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `comp_price` decimal(10,2) NOT NULL,
  `price_date` date NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_comp` (`store_id`,`goods_id`,`competitor_name`,`price_date`)
) ENGINE=InnoDB AUTO_INCREMENT=64 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS dm_business_viability;
CREATE TABLE `dm_business_viability` (
  `store_id` int unsigned NOT NULL,
  `snapshot_date` date NOT NULL,
  `to_past` decimal(14,2) DEFAULT '0.00',
  `margin_past_rub` decimal(14,2) DEFAULT '0.00',
  `plan_exec_past_pct` decimal(7,2) DEFAULT '0.00',
  `to_current` decimal(14,2) DEFAULT '0.00',
  `margin_current_rub` decimal(14,2) DEFAULT '0.00',
  `upch` decimal(6,2) DEFAULT '0.00' COMMENT 'упаковок в чеке',
  `sch` decimal(10,2) DEFAULT '0.00' COMMENT 'средний чек, руб',
  `tz_rub` decimal(14,2) DEFAULT '0.00' COMMENT 'товарный запас в закупке',
  `liquid_share_pct` decimal(6,2) DEFAULT '0.00',
  `surplus_share_pct` decimal(6,2) DEFAULT '0.00',
  `bad_stock_share_pct` decimal(6,2) DEFAULT '0.00' COMMENT 'доля неликвидов',
  `expiring_share_pct` decimal(6,2) DEFAULT '0.00',
  `lost_profit_rub` decimal(14,2) DEFAULT '0.00',
  `to_forecast` decimal(14,2) DEFAULT '0.00',
  `plan_gap_pct` decimal(7,2) DEFAULT '0.00',
  `viability_marker` enum('RENTABLE','RISK_ZONE','CLOSURE','INCUBATION') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'RISK_ZONE',
  `marker_comment` varchar(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`store_id`,`snapshot_date`),
  CONSTRAINT `fk_dm_store` FOREIGN KEY (`store_id`) REFERENCES `stores` (`store_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS employees;
CREATE TABLE `employees` (
  `employee_id` int unsigned NOT NULL AUTO_INCREMENT,
  `store_id` int unsigned NOT NULL,
  `first_name` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'Имя',
  `last_name` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'Фамилия',
  `middle_name` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Отчество',
  `position` enum('PHARMACIST','STORE_MANAGER') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'Должность',
  `hire_date` date NOT NULL DEFAULT '2023-01-01' COMMENT 'Дата трудоустройства',
  `termination_date` date DEFAULT NULL COMMENT 'Дата увольнения',
  `is_active` tinyint(1) NOT NULL DEFAULT '1' COMMENT '1 = активен, 0 = уволен',
  PRIMARY KEY (`employee_id`),
  KEY `fk_employees_stores` (`store_id`),
  CONSTRAINT `fk_employees_stores_new` FOREIGN KEY (`store_id`) REFERENCES `stores` (`store_id`)
) ENGINE=InnoDB AUTO_INCREMENT=41 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Справочник сотрудников сети';

DROP TABLE IF EXISTS expiry_writeoffs;
CREATE TABLE `expiry_writeoffs` (
  `writeoff_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `store_id` int unsigned NOT NULL,
  `batch_id` bigint unsigned NOT NULL,
  `goods_id` int unsigned NOT NULL,
  `qty` int NOT NULL,
  `loss_amount` decimal(12,2) NOT NULL COMMENT 'закупочная стоимость списанного',
  `writeoff_date` date NOT NULL,
  `penalty_distributed` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`writeoff_id`),
  KEY `idx_wo_store` (`store_id`,`penalty_distributed`),
  KEY `fk_wo_batch` (`batch_id`),
  CONSTRAINT `fk_wo_batch` FOREIGN KEY (`batch_id`) REFERENCES `goods_batches` (`batch_id`),
  CONSTRAINT `fk_wo_store` FOREIGN KEY (`store_id`) REFERENCES `stores` (`store_id`)
) ENGINE=InnoDB AUTO_INCREMENT=267 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS goods;
CREATE TABLE `goods` (
  `goods_id` int unsigned NOT NULL AUTO_INCREMENT,
  `goods_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `group_id` int unsigned NOT NULL,
  `matrix_status` enum('ZNVLP','COMMERCIAL_PRIORITY','STANDARD','MARKER') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'STANDARD',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `is_prescription` tinyint(1) NOT NULL DEFAULT '0' COMMENT '1 = строгий рецептурный отпуск',
  `marketing_bonus_pct` decimal(4,2) NOT NULL DEFAULT '0.00' COMMENT 'Процент ретро-бонуса от завода за закупку',
  `is_impulse` tinyint(1) NOT NULL DEFAULT '0' COMMENT '1 = импульсный товар у кассы',
  PRIMARY KEY (`goods_id`),
  KEY `idx_goods_group` (`group_id`),
  CONSTRAINT `fk_goods_group` FOREIGN KEY (`group_id`) REFERENCES `pharm_groups` (`group_id`)
) ENGINE=InnoDB AUTO_INCREMENT=205 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS goods_analogs;
CREATE TABLE `goods_analogs` (
  `contract_goods_id` int unsigned NOT NULL,
  `analog_goods_id` int unsigned NOT NULL,
  PRIMARY KEY (`contract_goods_id`,`analog_goods_id`),
  KEY `fk_ga_analog` (`analog_goods_id`),
  CONSTRAINT `fk_ga_analog` FOREIGN KEY (`analog_goods_id`) REFERENCES `goods` (`goods_id`),
  CONSTRAINT `fk_ga_contract` FOREIGN KEY (`contract_goods_id`) REFERENCES `goods` (`goods_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS goods_batches;
CREATE TABLE `goods_batches` (
  `batch_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `store_id` int unsigned NOT NULL,
  `goods_id` int unsigned NOT NULL,
  `qty` int NOT NULL DEFAULT '0',
  `purchase_price` decimal(10,2) NOT NULL,
  `retail_price` decimal(10,2) NOT NULL,
  `markup_pct` decimal(7,2) GENERATED ALWAYS AS (round((((`retail_price` / nullif(`purchase_price`,0)) - 1) * 100),2)) STORED,
  `expiry_date` date NOT NULL,
  `purchase_type` enum('OFFICE_LOAD','AUTO','MANUAL') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'AUTO',
  `donor_store_id` int unsigned DEFAULT NULL COMMENT 'аптека-донор при возврате неликвида',
  `received_at` date NOT NULL,
  `min_reprice_up` decimal(6,2) NOT NULL DEFAULT '5.00' COMMENT 'буфер шума повышения (Слон 5)',
  `min_reprice_down` decimal(6,2) NOT NULL DEFAULT '10.00' COMMENT 'буфер шума снижения (Слон 5)',
  `is_returned_dead` tinyint(1) NOT NULL DEFAULT '0' COMMENT '1 = партия создана процедурой возврата неликвида',
  `vat_pct` tinyint unsigned NOT NULL DEFAULT '10' COMMENT 'Ставка НДС из накладной (10 или 22%)',
  `purchase_price_net` decimal(10,2) GENERATED ALWAYS AS (round((`purchase_price` / (1 + (`vat_pct` / 100))),2)) STORED COMMENT 'Чистый закуп без НДС (считается сам!)',
  `turnover_anomaly_flag` enum('NONE','SUSPECT','CONFIRMED_MISSING') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'NONE',
  `anomaly_detected_at` date DEFAULT NULL,
  `anomaly_resolved_by` int unsigned DEFAULT NULL,
  `batch_status` enum('IN_TRANSIT','ON_SHELF') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'ON_SHELF',
  `expected_arrival_date` date DEFAULT NULL,
  PRIMARY KEY (`batch_id`),
  KEY `idx_batch_store_goods` (`store_id`,`goods_id`),
  KEY `idx_batch_expiry` (`expiry_date`),
  KEY `fk_batch_goods` (`goods_id`),
  CONSTRAINT `fk_batch_goods` FOREIGN KEY (`goods_id`) REFERENCES `goods` (`goods_id`),
  CONSTRAINT `fk_batch_store` FOREIGN KEY (`store_id`) REFERENCES `stores` (`store_id`),
  CONSTRAINT `chk_batch_qty_nonneg` CHECK ((`qty` >= 0))
) ENGINE=InnoDB AUTO_INCREMENT=734 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS lost_demand_log;
CREATE TABLE `lost_demand_log` (
  `decline_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `store_id` int unsigned NOT NULL,
  `goods_id` int unsigned NOT NULL,
  `pharmacist_id` int unsigned NOT NULL,
  `scan_timestamp` datetime NOT NULL,
  `lost_qty` int NOT NULL DEFAULT '1',
  `validation_status` enum('PENDING','VALID','INVALID','VALID_PHARM_REFUSAL') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'PENDING',
  `defectura_type` enum('STORE_FAULT','CITY_DEFECTURA','IN_TRANSIT_GAP') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'STORE_FAULT',
  PRIMARY KEY (`decline_id`),
  KEY `idx_ldl_store_goods` (`store_id`,`goods_id`,`scan_timestamp`),
  KEY `fk_ldl_goods` (`goods_id`),
  KEY `fk_ldl_emp` (`pharmacist_id`),
  CONSTRAINT `fk_ldl_emp` FOREIGN KEY (`pharmacist_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `fk_ldl_goods` FOREIGN KEY (`goods_id`) REFERENCES `goods` (`goods_id`),
  CONSTRAINT `fk_ldl_store` FOREIGN KEY (`store_id`) REFERENCES `stores` (`store_id`)
) ENGINE=InnoDB AUTO_INCREMENT=1078 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS lost_profit_log;
CREATE TABLE `lost_profit_log` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `calc_date` date NOT NULL,
  `store_id` int unsigned NOT NULL,
  `goods_id` int unsigned DEFAULT NULL,
  `contract_goods_id` int unsigned NOT NULL,
  `analog_goods_id` int unsigned DEFAULT NULL,
  `lost_qty` int NOT NULL,
  `lost_revenue` decimal(12,2) NOT NULL COMMENT 'дутые деньги аналога',
  `lost_margin` decimal(12,2) NOT NULL COMMENT 'чистая упущенная маржа сети',
  `reason_code` enum('ANALOG_CANNIBALIZATION','REAL_DEFECTURA','EXPIRED_WRITEOFF') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'REAL_DEFECTURA',
  `is_penalty_distributed` tinyint(1) NOT NULL DEFAULT '0',
  `defectura_type` enum('STORE_FAULT','CITY_DEFECTURA','IN_TRANSIT_GAP') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'STORE_FAULT',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_lpl` (`calc_date`,`store_id`,`contract_goods_id`,`analog_goods_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2815 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS markup_matrix;
CREATE TABLE `markup_matrix` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `price_from` decimal(10,2) NOT NULL,
  `price_to` decimal(10,2) DEFAULT NULL COMMENT 'NULL = без верхней границы',
  `markup_pct` decimal(5,2) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS min_max;
CREATE TABLE `min_max` (
  `store_id` int unsigned NOT NULL,
  `goods_id` int unsigned NOT NULL,
  `calc_date` date NOT NULL,
  `adu` decimal(10,3) NOT NULL DEFAULT '0.000' COMMENT 'среднедневные продажи + честные отказы',
  `calc_min` smallint unsigned NOT NULL DEFAULT '0',
  `calc_max` smallint unsigned NOT NULL DEFAULT '0',
  `manual_override` tinyint(1) NOT NULL DEFAULT '0',
  `fixed_min` smallint unsigned DEFAULT NULL,
  `fixed_max` smallint unsigned DEFAULT NULL,
  `seasonal_boost` smallint unsigned NOT NULL DEFAULT '0',
  `effective_min` smallint unsigned NOT NULL DEFAULT '0',
  `effective_max` smallint unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`store_id`,`goods_id`,`calc_date`),
  KEY `fk_mm_goods` (`goods_id`),
  CONSTRAINT `fk_mm_goods` FOREIGN KEY (`goods_id`) REFERENCES `goods` (`goods_id`),
  CONSTRAINT `fk_mm_store` FOREIGN KEY (`store_id`) REFERENCES `stores` (`store_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS motivation_log;
CREATE TABLE `motivation_log` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `store_id` int unsigned NOT NULL,
  `period` date NOT NULL,
  `liquid_share_pct` decimal(6,2) NOT NULL,
  `liquid_growth_pp` decimal(6,2) NOT NULL DEFAULT '0.00' COMMENT 'рост доли ликвида в п.п. к пред. месяцу',
  `def_share_pct` decimal(6,2) NOT NULL DEFAULT '0.00' COMMENT 'доля дефектуры: lost_margin к ТО за месяц',
  `def_multiplier` decimal(4,2) NOT NULL DEFAULT '1.00' COMMENT '1.00..0.00: выжигатель премии',
  `kpi_adjust_pct` decimal(5,2) NOT NULL COMMENT 'итоговая корректировка ЗП, % (-10.00..+10.00)',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_mot` (`store_id`,`period`)
) ENGINE=InnoDB AUTO_INCREMENT=12 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS penalty_distribution;
CREATE TABLE `penalty_distribution` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `writeoff_id` bigint unsigned NOT NULL,
  `employee_id` int unsigned NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `period` date NOT NULL COMMENT 'месяц расчёта ЗП',
  PRIMARY KEY (`id`),
  KEY `fk_pd_wo` (`writeoff_id`),
  KEY `fk_pd_emp` (`employee_id`),
  CONSTRAINT `fk_pd_emp` FOREIGN KEY (`employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `fk_pd_wo` FOREIGN KEY (`writeoff_id`) REFERENCES `expiry_writeoffs` (`writeoff_id`)
) ENGINE=InnoDB AUTO_INCREMENT=644 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS pharm_groups;
CREATE TABLE `pharm_groups` (
  `group_id` int unsigned NOT NULL AUTO_INCREMENT,
  `group_name` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `shelf_life_days` smallint unsigned NOT NULL DEFAULT '90',
  PRIMARY KEY (`group_id`)
) ENGINE=InnoDB AUTO_INCREMENT=42 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS pharmacy_fixed_costs;
CREATE TABLE `pharmacy_fixed_costs` (
  `store_id` int unsigned NOT NULL,
  `period` date NOT NULL COMMENT 'первое число месяца',
  `rent_cost` decimal(12,2) NOT NULL DEFAULT '0.00',
  `fot_cost` decimal(12,2) NOT NULL DEFAULT '0.00',
  `plan_to` decimal(14,2) NOT NULL DEFAULT '0.00' COMMENT 'план товарооборота',
  PRIMARY KEY (`store_id`,`period`),
  CONSTRAINT `fk_costs_store` FOREIGN KEY (`store_id`) REFERENCES `stores` (`store_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS pricing_roles;
CREATE TABLE `pricing_roles` (
  `store_id` int unsigned NOT NULL,
  `goods_id` int unsigned NOT NULL,
  `role` enum('OFFICE','LOCAL') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'OFFICE',
  `created_by` int unsigned DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`store_id`,`goods_id`),
  KEY `fk_pr_goods` (`goods_id`),
  CONSTRAINT `fk_pr_goods` FOREIGN KEY (`goods_id`) REFERENCES `goods` (`goods_id`),
  CONSTRAINT `fk_pr_store` FOREIGN KEY (`store_id`) REFERENCES `stores` (`store_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS promo_rules;
CREATE TABLE `promo_rules` (
  `rule_id` int unsigned NOT NULL AUTO_INCREMENT,
  `trigger_goods_id` int unsigned NOT NULL COMMENT 'отсканированный товар',
  `offer_goods_id` int unsigned NOT NULL COMMENT 'что предлагаем',
  `promo_type` enum('SECOND_UNIT','BUNDLE','CHAOTIC') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `discount_pct` decimal(5,2) NOT NULL,
  `min_markup_guard` decimal(5,2) NOT NULL DEFAULT '5.00' COMMENT 'скидка не может уронить наценку ниже этого порога (окупаемость логистики)',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`rule_id`),
  KEY `idx_promo_trigger` (`trigger_goods_id`,`is_active`),
  KEY `fk_promo_offer` (`offer_goods_id`),
  CONSTRAINT `fk_promo_offer` FOREIGN KEY (`offer_goods_id`) REFERENCES `goods` (`goods_id`),
  CONSTRAINT `fk_promo_trig` FOREIGN KEY (`trigger_goods_id`) REFERENCES `goods` (`goods_id`)
) ENGINE=InnoDB AUTO_INCREMENT=617 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS repricing_log;
CREATE TABLE `repricing_log` (
  `reprice_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `batch_id` bigint unsigned NOT NULL,
  `reprice_date` date NOT NULL,
  `old_price` decimal(10,2) NOT NULL,
  `new_price` decimal(10,2) NOT NULL,
  `reason` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  PRIMARY KEY (`reprice_id`),
  KEY `idx_repr_batch` (`batch_id`),
  CONSTRAINT `fk_repr_batch` FOREIGN KEY (`batch_id`) REFERENCES `goods_batches` (`batch_id`)
) ENGINE=InnoDB AUTO_INCREMENT=530 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS sabotage_log;
CREATE TABLE `sabotage_log` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `store_id` int unsigned NOT NULL,
  `employee_id` int unsigned DEFAULT NULL COMMENT 'NULL = маркер руководителю точки',
  `marker_type` enum('FAKE_DECLINE','ZERO_DECLINES_KCH_FALL','AUTOORDER_TAMPER','PRICING_CHAOS') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `details` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_sab_store` (`store_id`,`created_at`)
) ENGINE=MyISAM AUTO_INCREMENT=208 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS sales;
CREATE TABLE `sales` (
  `sale_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `store_id` int unsigned NOT NULL,
  `goods_id` int unsigned NOT NULL,
  `card_id` bigint unsigned DEFAULT NULL,
  `employee_id` int unsigned DEFAULT NULL,
  `sale_datetime` datetime NOT NULL,
  `sale_date` date GENERATED ALWAYS AS (cast(`sale_datetime` as date)) STORED,
  `qty` int NOT NULL,
  `retail_price` decimal(10,2) NOT NULL,
  `payment_method` enum('CARD','CASH') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'CARD',
  `purchase_price` decimal(10,2) NOT NULL,
  PRIMARY KEY (`sale_id`),
  KEY `idx_sales_adu` (`store_id`,`goods_id`,`sale_date`),
  KEY `idx_sales_card` (`card_id`,`sale_date`),
  KEY `fk_sales_goods` (`goods_id`),
  KEY `idx_sales_DWH_range_perf` (`sale_date`,`store_id`,`goods_id`),
  CONSTRAINT `fk_sales_goods` FOREIGN KEY (`goods_id`) REFERENCES `goods` (`goods_id`),
  CONSTRAINT `fk_sales_store` FOREIGN KEY (`store_id`) REFERENCES `stores` (`store_id`)
) ENGINE=InnoDB AUTO_INCREMENT=100798 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS stores;
CREATE TABLE `stores` (
  `store_id` int unsigned NOT NULL AUTO_INCREMENT,
  `store_name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `segment` enum('FLAGSHIP','RESIDENTIAL','HOSPITAL','DISCOUNTER','NEW') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'RESIDENTIAL',
  `opened_date` date NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `max_stagnation_multiplier` decimal(4,2) NOT NULL DEFAULT '3.00' COMMENT 'Коэффициент критического застоя для заведующей',
  `absolute_dead_threshold_days` smallint unsigned NOT NULL DEFAULT '90' COMMENT 'Железный потолок неликвида при 0 продаж',
  `daily_to_plan_rub` decimal(10,2) NOT NULL DEFAULT '150000.00' COMMENT 'Ежедневный план по ТО в рублях',
  `daily_checks_plan` smallint unsigned NOT NULL DEFAULT '170' COMMENT 'Суточный план аптеки по количеству чеков (КЧ)',
  `daily_margin_plan_rub` decimal(10,2) NOT NULL DEFAULT '25000.00' COMMENT 'Суточный план валовой маржи аптеки',
  `norm_per_shift_rub` decimal(10,2) NOT NULL DEFAULT '3500.00' COMMENT 'Ставка сотрудника за одну смену',
  PRIMARY KEY (`store_id`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS transfers;
CREATE TABLE `transfers` (
  `transfer_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `batch_id` bigint unsigned NOT NULL,
  `goods_id` int unsigned NOT NULL,
  `donor_store_id` int unsigned NOT NULL,
  `recipient_store_id` int unsigned NOT NULL,
  `qty` int NOT NULL,
  `status` enum('IN_TRANSIT','ACCEPTED','RETURNED_DEAD') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'IN_TRANSIT',
  `shipped_at` datetime NOT NULL,
  `accepted_at` datetime DEFAULT NULL,
  PRIMARY KEY (`transfer_id`),
  KEY `idx_tr_status` (`status`),
  KEY `fk_tr_batch` (`batch_id`),
  KEY `fk_tr_donor` (`donor_store_id`),
  KEY `fk_tr_recipient` (`recipient_store_id`),
  CONSTRAINT `fk_tr_batch` FOREIGN KEY (`batch_id`) REFERENCES `goods_batches` (`batch_id`),
  CONSTRAINT `fk_tr_donor` FOREIGN KEY (`donor_store_id`) REFERENCES `stores` (`store_id`),
  CONSTRAINT `fk_tr_recipient` FOREIGN KEY (`recipient_store_id`) REFERENCES `stores` (`store_id`)
) ENGINE=InnoDB AUTO_INCREMENT=146 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;
