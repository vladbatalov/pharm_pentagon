-- Apteka Bober DWH: 02_triggers.sql (Триггеры защиты ЖНВЛП, округления и антифрода)
USE `apteka_bober`;
DELIMITER ;;

DROP TRIGGER IF EXISTS `tg_znvlp_price_guard`;;
CREATE TRIGGER `tg_znvlp_price_guard` BEFORE INSERT ON `goods_batches` FOR EACH ROW BEGIN
    DECLARE v_status VARCHAR(30);
    DECLARE v_markup DECIMAL(5,2);
    DECLARE v_raw_price DECIMAL(10,2);

    SELECT matrix_status INTO v_status FROM goods WHERE goods_id = NEW.goods_id;

    IF NEW.retail_price IS NULL OR NEW.retail_price = 0 THEN
        SELECT markup_pct INTO v_markup
          FROM markup_matrix
         WHERE NEW.purchase_price >= price_from AND (price_to IS NULL OR NEW.purchase_price <= price_to)
         LIMIT 1;

        SET v_markup = COALESCE(v_markup, 25.00);
        IF v_status = 'ZNVLP' AND v_markup > 25.00 THEN
            SET v_markup = 25.00;
        END IF;

        SET v_raw_price = ROUND(NEW.purchase_price * (1 + v_markup / 100), 2);

        -- ЖНВЛП оставляем точной до копейки; коммерцию всегда тянем ВВЕРХ до .99
        IF v_status = 'ZNVLP' THEN
            SET NEW.retail_price = v_raw_price;
        ELSE
            SET NEW.retail_price = FLOOR(v_raw_price) + 0.99;
        END IF;
    ELSE
        IF v_status = 'ZNVLP' AND NEW.retail_price > ROUND(NEW.purchase_price * 1.25, 2) THEN
            SET NEW.retail_price = ROUND(NEW.purchase_price * 1.25, 2);
        END IF;
    END IF;
END;;

DROP TRIGGER IF EXISTS `tg_validate_lost_demand`;;
CREATE TRIGGER `tg_validate_lost_demand` BEFORE INSERT ON `lost_demand_log` FOR EACH ROW BEGIN
DECLARE v_qty INT DEFAULT 0;
-- Проверяем наличие ТОЛЬКО физически на полке и не подтвержденных как потеряшки
SELECT COALESCE(SUM(qty), 0) INTO v_qty
FROM goods_batches
WHERE store_id = NEW.store_id
AND goods_id = NEW.goods_id
AND batch_status = 'ON_SHELF'
AND turnover_anomaly_flag <> 'CONFIRMED_MISSING'
AND expiry_date >= DATE(NEW.scan_timestamp);
IF v_qty > 0 THEN
INSERT INTO sabotage_log (store_id, employee_id, marker_type, details)
VALUES (NEW.store_id, NEW.pharmacist_id, 'FAKE_DECLINE',
CONCAT('Фиктивный отказ по goods_id=', NEW.goods_id,
': на полке ', v_qty, ' уп. на ', NEW.scan_timestamp));
SIGNAL SQLSTATE '45000'
SET MESSAGE_TEXT = 'Отказ отклонён: товар в наличии. Дисциплинарный маркер выставлен.';
END IF;
END;;

DROP TRIGGER IF EXISTS `tg_pricing_roles_limit`;;
CREATE TRIGGER `tg_pricing_roles_limit` BEFORE INSERT ON `pricing_roles` FOR EACH ROW BEGIN
    DECLARE v_local_cnt INT DEFAULT 0;

    IF NEW.role = 'LOCAL' THEN
        SELECT COUNT(*) INTO v_local_cnt
          FROM pricing_roles
         WHERE store_id = NEW.store_id AND role = 'LOCAL';

        IF v_local_cnt >= 100 THEN
            INSERT INTO sabotage_log (store_id, employee_id, marker_type, details)
            VALUES (NEW.store_id, NEW.created_by, 'PRICING_CHAOS',
                    'Попытка повесить 101-й локальный маркер ценообразования');
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Лимит 100 локальных маркеров исчерпан. Снимите неэффективные маркеры.';
        END IF;
    END IF;
END;;

DROP TRIGGER IF EXISTS `tg_sales_cash_rounding`;;
CREATE TRIGGER `tg_sales_cash_rounding` BEFORE INSERT ON `sales` FOR EACH ROW BEGIN
    -- Если выбрана оплата наличными (CASH), округляем копейки до 00 в пользу покупателя
    IF NEW.payment_method = 'CASH' THEN
        SET NEW.retail_price = GREATEST(NEW.purchase_price, FLOOR(NEW.retail_price));
    END IF;
END;;

DELIMITER ;
