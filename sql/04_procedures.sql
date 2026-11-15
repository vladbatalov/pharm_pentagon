-- Apteka Bober DWH: 04_procedures.sql (Ночной регламент и ACID-процедуры)
USE `apteka_bober`;
DELIMITER ;;

DROP PROCEDURE IF EXISTS `sp_check_office_load`;;
CREATE PROCEDURE `sp_check_office_load`(IN p_store_id INT UNSIGNED,
                                      IN p_goods_id INT UNSIGNED,
                                      IN p_qty      INT)
BEGIN
    DECLARE v_need_month DECIMAL(12,2) DEFAULT 0;

    SELECT ROUND(COALESCE(SUM(s.qty),0) / 14 * 30, 2) INTO v_need_month
      FROM sales s
     WHERE s.store_id = p_store_id
       AND s.sale_date >= CURDATE() - INTERVAL 14 DAY
       AND s.goods_id IN (
            SELECT p_goods_id
            UNION
            SELECT analog_goods_id FROM goods_analogs
             WHERE contract_goods_id = p_goods_id
            UNION
            SELECT contract_goods_id FROM goods_analogs
             WHERE analog_goods_id = p_goods_id
           );

    IF p_qty > GREATEST(v_need_month, 1) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Прогруз заблокирован: объём превышает месячную оборачиваемость точки с учётом аналогов.';
    END IF;
END;;

DROP PROCEDURE IF EXISTS `sp_check_zero_declines`;;
CREATE PROCEDURE `sp_check_zero_declines`(IN p_date DATE)
BEGIN
    INSERT INTO sabotage_log (store_id, employee_id, marker_type, details)
    SELECT st.store_id, NULL, 'ZERO_DECLINES_KCH_FALL',
           CONCAT('КЧ падает, остатков нет, отказов за 7 дней нет (на ', p_date, ')')
      FROM stores st
     WHERE st.is_active = 1
       AND DATEDIFF(p_date, st.opened_date) >= 30
       AND NOT EXISTS (
            SELECT 1 FROM lost_demand_log l
             WHERE l.store_id = st.store_id
               AND DATE(l.scan_timestamp) BETWEEN p_date - INTERVAL 7 DAY AND p_date
           )
       AND EXISTS (
            SELECT 1 FROM goods_batches b
             WHERE b.store_id = st.store_id
             GROUP BY b.store_id
            HAVING SUM(b.qty) = 0
           );
END;;

DROP PROCEDURE IF EXISTS `sp_confirm_missing_batch`;;
CREATE PROCEDURE `sp_confirm_missing_batch`(
    IN p_batch_id BIGINT UNSIGNED, 
    IN p_employee_id INT UNSIGNED
)
BEGIN
    UPDATE goods_batches 
    SET turnover_anomaly_flag = 'CONFIRMED_MISSING',
        anomaly_resolved_by = p_employee_id
    WHERE batch_id = p_batch_id;
END;;

DROP PROCEDURE IF EXISTS `sp_daily_minmax_recalc`;;
CREATE PROCEDURE `sp_daily_minmax_recalc`(IN p_date DATE)
BEGIN
    DECLARE v_season VARCHAR(10);

    SET v_season = CASE
        WHEN MONTH(p_date) IN (12, 1, 2) THEN 'WINTER'
        WHEN MONTH(p_date) IN (3, 4, 5)  THEN 'SPRING'
        WHEN MONTH(p_date) IN (6, 7, 8)  THEN 'SUMMER'
        ELSE 'AUTUMN'
    END;

    -- Переводим доехавшие партии из IN_TRANSIT в ON_SHELF
    UPDATE goods_batches
       SET batch_status = 'ON_SHELF'
     WHERE batch_status = 'IN_TRANSIT'
       AND expected_arrival_date <= p_date;

    INSERT INTO min_max
        (store_id, goods_id, calc_date, adu,
         calc_min, calc_max, seasonal_boost, effective_min, effective_max)
    SELECT
        s.store_id,
        g.goods_id,
        p_date,
        -- Если товар лежит на полке и отказов не было -> делим на 7 календарных дней (защита от затаривания редким товаром).
        -- Если полка высохла (qty = 0) или были отказы -> делим на фактические дни продаж (active_days_7d).
        ROUND(
            (COALESCE(s7.sold_7d, 0) + COALESCE(d7.lost_7d, 0)) /
            IF(COALESCE(stk.on_shelf_qty, 0) > 0 AND COALESCE(d7.lost_7d, 0) = 0, 7, COALESCE(s7.active_days_7d, 1)),
            3
        ) AS adu,

        LEAST(
            CEIL(
                ((COALESCE(s7.sold_7d, 0) + COALESCE(d7.lost_7d, 0)) /
                 IF(COALESCE(stk.on_shelf_qty, 0) > 0 AND COALESCE(d7.lost_7d, 0) = 0, 7, COALESCE(s7.active_days_7d, 1)))
                * (CASE WHEN g.matrix_status = 'COMMERCIAL_PRIORITY' THEN 5 ELSE 3 END)
            ) * IF(g.matrix_status = 'COMMERCIAL_PRIORITY' AND COALESCE(d7.lost_7d, 0) >= 10, 3, 1),
            32000
        ) AS calc_min,

        LEAST(
            CEIL(
                ((COALESCE(s7.sold_7d, 0) + COALESCE(d7.lost_7d, 0)) /
                 IF(COALESCE(stk.on_shelf_qty, 0) > 0 AND COALESCE(d7.lost_7d, 0) = 0, 7, COALESCE(s7.active_days_7d, 1)))
                * (CASE WHEN g.matrix_status = 'COMMERCIAL_PRIORITY' THEN 14 ELSE 10 END)
            ) * IF(g.matrix_status = 'COMMERCIAL_PRIORITY' AND COALESCE(d7.lost_7d, 0) >= 10, 3, 1),
            32000
        ) AS calc_max,

        COALESCE(cs.boost_qty, 0) AS seasonal_boost,

        IF(g.matrix_status IN ('ZNVLP', 'COMMERCIAL_PRIORITY'),
           GREATEST(
               LEAST(
                   CEIL(
                       ((COALESCE(s7.sold_7d, 0) + COALESCE(d7.lost_7d, 0)) /
                        IF(COALESCE(stk.on_shelf_qty, 0) > 0 AND COALESCE(d7.lost_7d, 0) = 0, 7, COALESCE(s7.active_days_7d, 1)))
                       * (CASE WHEN g.matrix_status = 'COMMERCIAL_PRIORITY' THEN 5 ELSE 3 END)
                   ) * IF(g.matrix_status = 'COMMERCIAL_PRIORITY' AND COALESCE(d7.lost_7d, 0) >= 10, 3, 1),
                   32000
               ) + COALESCE(cs.boost_qty, 0),
               1
           ),
           LEAST(
               CEIL(
                   ((COALESCE(s7.sold_7d, 0) + COALESCE(d7.lost_7d, 0)) /
                    IF(COALESCE(stk.on_shelf_qty, 0) > 0 AND COALESCE(d7.lost_7d, 0) = 0, 7, COALESCE(s7.active_days_7d, 1))) * 3
               ),
               32000
           ) + COALESCE(cs.boost_qty, 0)
        ) AS effective_min,

        IF(g.matrix_status IN ('ZNVLP', 'COMMERCIAL_PRIORITY'),
           GREATEST(
               LEAST(
                   CEIL(
                       ((COALESCE(s7.sold_7d, 0) + COALESCE(d7.lost_7d, 0)) /
                        IF(COALESCE(stk.on_shelf_qty, 0) > 0 AND COALESCE(d7.lost_7d, 0) = 0, 7, COALESCE(s7.active_days_7d, 1)))
                       * (CASE WHEN g.matrix_status = 'COMMERCIAL_PRIORITY' THEN 14 ELSE 10 END)
                   ) * IF(g.matrix_status = 'COMMERCIAL_PRIORITY' AND COALESCE(d7.lost_7d, 0) >= 10, 3, 1),
                   32000
               ) + COALESCE(cs.boost_qty, 0),
               1
           ),
           LEAST(
               CEIL(
                   ((COALESCE(s7.sold_7d, 0) + COALESCE(d7.lost_7d, 0)) /
                    IF(COALESCE(stk.on_shelf_qty, 0) > 0 AND COALESCE(d7.lost_7d, 0) = 0, 7, COALESCE(s7.active_days_7d, 1))) * 10
               ),
               32000
           ) + COALESCE(cs.boost_qty, 0)
        ) AS effective_max

    FROM stores s
    CROSS JOIN goods g
    LEFT JOIN (
        -- Текущий физический остаток на полке
        SELECT store_id, goods_id, SUM(qty) AS on_shelf_qty
          FROM goods_batches
         WHERE batch_status = 'ON_SHELF' AND turnover_anomaly_flag != 'CONFIRMED_MISSING'
         GROUP BY store_id, goods_id
    ) stk ON stk.store_id = s.store_id AND stk.goods_id = g.goods_id
    LEFT JOIN (
        SELECT store_id, goods_id,
               SUM(qty) AS sold_7d,
               GREATEST(COUNT(DISTINCT sale_date), 1) AS active_days_7d
          FROM sales
         WHERE sale_date BETWEEN p_date - INTERVAL 7 DAY AND p_date - INTERVAL 1 DAY
         GROUP BY store_id, goods_id
    ) s7 ON s7.store_id = s.store_id AND s7.goods_id = g.goods_id
    LEFT JOIN (
        SELECT store_id, goods_id, SUM(lost_qty) AS lost_7d
          FROM lost_demand_log
         WHERE validation_status = 'VALID'
           AND defectura_type != 'CITY_DEFECTURA'
           AND DATE(scan_timestamp) BETWEEN p_date - INTERVAL 7 DAY AND p_date - INTERVAL 1 DAY
         GROUP BY store_id, goods_id
    ) d7 ON d7.store_id = s.store_id AND d7.goods_id = g.goods_id
    LEFT JOIN category_seasonality cs
           ON cs.group_id = g.group_id AND cs.season = v_season
    WHERE s.is_active = 1 AND g.is_active = 1
    ON DUPLICATE KEY UPDATE
        adu            = VALUES(adu),
        calc_min       = IF(manual_override = 1, calc_min, VALUES(calc_min)),
        calc_max       = IF(manual_override = 1, calc_max, VALUES(calc_max)),
        seasonal_boost = IF(manual_override = 1, seasonal_boost, VALUES(seasonal_boost)),
        effective_min  = IF(manual_override = 1, COALESCE(fixed_min, effective_min), VALUES(effective_min)),
        effective_max  = IF(manual_override = 1, COALESCE(fixed_max, effective_max), VALUES(effective_max));
END;;

DROP PROCEDURE IF EXISTS `sp_detect_latent_shortages`;;
CREATE PROCEDURE `sp_detect_latent_shortages`(IN p_date DATE)
BEGIN
    UPDATE goods_batches b
    JOIN goods g ON g.goods_id = b.goods_id
    JOIN pharm_groups pg ON pg.group_id = g.group_id
    LEFT JOIN (
        SELECT store_id, goods_id, MAX(sale_date) AS last_sale_date
        FROM sales
        GROUP BY store_id, goods_id
    ) s ON s.store_id = b.store_id AND s.goods_id = b.goods_id
    SET b.turnover_anomaly_flag = 'SUSPECT',
        b.anomaly_detected_at = p_date
    WHERE b.qty > 0
      AND b.turnover_anomaly_flag = 'NONE' 
      AND (
          DATEDIFF(p_date, COALESCE(s.last_sale_date, b.received_at)) > 
          CASE 
              WHEN pg.shelf_life_days = 180 THEN 180 
              WHEN b.qty > (SELECT COALESCE(effective_max, 999) FROM min_max WHERE store_id=b.store_id AND goods_id=b.goods_id ORDER BY calc_date DESC LIMIT 1) THEN 120 
              ELSE 90 
          END
      );
END;;

DROP PROCEDURE IF EXISTS `sp_distribute_writeoff_penalty`;;
CREATE PROCEDURE `sp_distribute_writeoff_penalty`(
    IN p_date DATE,
    OUT p_status_msg VARCHAR(100)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_status_msg = 'КРИТИЧЕСКИЙ СБОЙ: Начисление штрафов отменено (ROLLBACK). Люди спасены.';
    END;

    START TRANSACTION;

    INSERT INTO penalty_distribution (writeoff_id, employee_id, amount, period)
    SELECT w.writeoff_id,
           e.employee_id,
           ROUND((w.loss_amount * 0.50) / NULLIF(cnt.staff_cnt, 0), 2),
           DATE_FORMAT(p_date, '%Y-%m-01')
      FROM expiry_writeoffs w
      JOIN employees e ON e.store_id = w.store_id
      JOIN (
          SELECT store_id, COUNT(*) AS staff_cnt
            FROM employees
           WHERE is_active = 1 AND position = 'PHARMACIST'
             AND DATEDIFF(p_date, hire_date) >= 90
           GROUP BY store_id
      ) cnt ON cnt.store_id = w.store_id
     WHERE w.penalty_distributed = 0
       AND e.is_active = 1
       AND e.position = 'PHARMACIST'
       AND DATEDIFF(p_date, e.hire_date) >= 90;

    UPDATE expiry_writeoffs
       SET penalty_distributed = 1
     WHERE penalty_distributed = 0;

    COMMIT;
    SET p_status_msg = 'УСПЕХ (COMMIT): Штрафы за просрочку атомарно распределены с учетом амнистии новичков.';
END;;

DROP PROCEDURE IF EXISTS `sp_expire_repricing`;;
CREATE PROCEDURE `sp_expire_repricing`(
    IN p_date DATE,
    OUT p_status_msg VARCHAR(100)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_status_msg = 'КРИТИЧЕСКИЙ СБОЙ: Переоценка просрочки отменена (ROLLBACK). Склад в безопасности.';
    END;

    START TRANSACTION;

    -- За 3 месяца: скидка 10%
    INSERT INTO repricing_log (batch_id, old_price, new_price, reprice_date, reason)
    SELECT batch_id, retail_price, ROUND(retail_price * 0.90, 2), p_date, 'EXPIRY_3M_MINUS10'
      FROM goods_batches
     WHERE expiry_date BETWEEN p_date AND p_date + INTERVAL 3 MONTH
       AND qty > 0 AND min_reprice_down = 10.00 AND batch_status = 'ON_SHELF';

    UPDATE goods_batches
       SET retail_price = ROUND(retail_price * 0.90, 2),
           min_reprice_down = 1.00
     WHERE expiry_date BETWEEN p_date AND p_date + INTERVAL 3 MONTH
       AND qty > 0 AND min_reprice_down = 10.00 AND batch_status = 'ON_SHELF';

    -- За 1 месяц: скидка 50%
    INSERT INTO repricing_log (batch_id, old_price, new_price, reprice_date, reason)
    SELECT batch_id, retail_price, ROUND(retail_price * 0.50, 2), p_date, 'EXPIRY_1M_MINUS50'
      FROM goods_batches
     WHERE expiry_date BETWEEN p_date AND p_date + INTERVAL 1 MONTH
       AND qty > 0 AND min_reprice_down = 1.00 AND batch_status = 'ON_SHELF';

    UPDATE goods_batches
       SET retail_price = ROUND(retail_price * 0.50, 2),
           min_reprice_down = 2.00
     WHERE expiry_date BETWEEN p_date AND p_date + INTERVAL 1 MONTH
       AND qty > 0 AND min_reprice_down = 1.00 AND batch_status = 'ON_SHELF';

    -- Полная просрочка: считаем упущенную выручку и ЧЕСТНУЮ маржу по первой розничной цене ДО уценок!
    INSERT INTO lost_profit_log (store_id, goods_id, contract_goods_id, analog_goods_id, calc_date, lost_qty, lost_revenue, lost_margin, reason_code)
    SELECT b.store_id,
           b.goods_id,
           b.goods_id,
           b.goods_id,
           p_date,
           b.qty,
           ROUND(b.qty * COALESCE(orig.first_retail_price, b.retail_price), 2) AS lost_revenue,
           ROUND(b.qty * GREATEST(COALESCE(orig.first_retail_price, b.retail_price) - b.purchase_price, 0), 2) AS lost_margin,
           'EXPIRED_WRITEOFF'
      FROM goods_batches b
      LEFT JOIN (
          -- Достаем самую первую цену из лога переоценок (до скидок 10% и 50%)
          SELECT r1.batch_id, r1.old_price AS first_retail_price
            FROM repricing_log r1
            JOIN (
                SELECT batch_id, MIN(reprice_id) AS min_id
                  FROM repricing_log
                 GROUP BY batch_id
            ) r2 ON r1.reprice_id = r2.min_id
      ) orig ON orig.batch_id = b.batch_id
     WHERE b.expiry_date <= p_date AND b.qty > 0;

    -- Записываем прямой убыток по закупу в ведомость списаний (для распределения в ФОТ)
    INSERT INTO expiry_writeoffs (store_id, batch_id, goods_id, qty, loss_amount, writeoff_date)
    SELECT store_id, batch_id, goods_id, qty, (qty * purchase_price), p_date
      FROM goods_batches
     WHERE expiry_date <= p_date AND qty > 0;

    UPDATE goods_batches
       SET qty = 0
     WHERE expiry_date <= p_date AND qty > 0;

    COMMIT;
    SET p_status_msg = 'УСПЕХ (COMMIT): Уценка проведена, упущенная маржа по просрочке посчитана от базовой цены.';
END;;

DROP PROCEDURE IF EXISTS `sp_get_personal_offers`;;
CREATE PROCEDURE `sp_get_personal_offers`(
    IN p_store_id INT UNSIGNED,
    IN p_card_id BIGINT UNSIGNED,
    IN p_trigger_goods_id INT UNSIGNED
)
BEGIN
    SELECT 
        pr.promo_type,
        g_offer.goods_name AS offer_name,
        b.retail_price AS price_before_rub,
        ROUND(b.retail_price * (1 - pr.discount_pct / 100), 2) AS price_after_rub,
        ROUND(b.retail_price * (pr.discount_pct / 100), 2) AS benefit_rub,
        pr.discount_pct AS discount_pct
    FROM promo_rules pr
    JOIN goods g_offer ON g_offer.goods_id = pr.offer_goods_id
    JOIN goods_batches b ON b.goods_id = pr.offer_goods_id 
                        AND b.store_id = p_store_id 
                        AND b.qty > 0
                        AND b.batch_status = 'ON_SHELF'
                        AND b.turnover_anomaly_flag <> 'CONFIRMED_MISSING'
    WHERE pr.trigger_goods_id = p_trigger_goods_id
      AND pr.is_active = 1
      AND NOT EXISTS (
          SELECT 1 FROM sales s
          WHERE s.card_id = p_card_id
            AND s.goods_id = pr.offer_goods_id
            AND s.sale_date >= CURDATE() - INTERVAL 14 DAY
      )
      -- Исправлено: ZNVLP вместо ZVNL
      AND ROUND(b.retail_price * (1 - pr.discount_pct / 100), 2) >= 
          CASE 
              WHEN g_offer.matrix_status = 'ZNVLP' THEN b.purchase_price
              ELSE ROUND(b.purchase_price * (1 + pr.min_markup_guard / 100), 2)
          END
    LIMIT 3;
END;;

DROP PROCEDURE IF EXISTS `sp_motivation_close_month`;;
CREATE PROCEDURE `sp_motivation_close_month`(IN p_period DATE)
BEGIN
    INSERT INTO motivation_log
        (store_id, period, liquid_share_pct, liquid_growth_pp,
         def_share_pct, def_multiplier, kpi_adjust_pct)
    SELECT
        q.store_id,
        p_period,
        q.liquid_pct,
        ROUND(q.liquid_pct - COALESCE(prev.liquid_share_pct, q.liquid_pct), 2) AS growth_pp,
        COALESCE(defs.def_share, 0) AS def_share_pct,
        ROUND(CASE
            WHEN COALESCE(defs.def_share, 0) <= 2  THEN 1.00
            WHEN COALESCE(defs.def_share, 0) >= 10 THEN 0.00
            ELSE 1.00 - (defs.def_share - 2) / 8
        END, 2) AS def_multiplier,
        ROUND(
          CASE
            WHEN q.liquid_pct > 65.00 THEN
                 LEAST(q.liquid_pct - 65.00, 10.00)
                 * CASE
                     WHEN COALESCE(defs.def_share, 0) <= 2  THEN 1.00
                     WHEN COALESCE(defs.def_share, 0) >= 10 THEN 0.00
                     ELSE 1.00 - (defs.def_share - 2) / 8
                   END
            WHEN PERIOD_DIFF(DATE_FORMAT(LAST_DAY(p_period), '%Y%m'),
                             DATE_FORMAT(st.opened_date, '%Y%m')) <= 3
                 THEN 0.00
            WHEN q.liquid_pct < 65.00 THEN
                 CASE
                   WHEN q.liquid_pct - COALESCE(prev.liquid_share_pct, q.liquid_pct) > 2.00
                        THEN 0.00
                   ELSE GREATEST(q.liquid_pct - 65.00, -10.00)
                 END
            ELSE 0.00
          END, 2) AS kpi_adjust_pct
      FROM v_stock_quality q
      JOIN stores st ON st.store_id = q.store_id
      LEFT JOIN motivation_log prev
             ON prev.store_id = q.store_id
            AND prev.period = p_period - INTERVAL 1 MONTH
      LEFT JOIN (
            SELECT lp.store_id,
                   ROUND(SUM(lp.lost_margin)
                         / NULLIF(TO_tab.to_sum + SUM(lp.lost_margin), 0) * 100, 2) AS def_share
              FROM lost_profit_log lp
              JOIN (
                    SELECT store_id, SUM(qty * retail_price) AS to_sum
                      FROM sales
                     WHERE sale_date BETWEEN p_period AND LAST_DAY(p_period)
                     GROUP BY store_id
                   ) TO_tab ON TO_tab.store_id = lp.store_id
             WHERE lp.calc_date BETWEEN p_period AND LAST_DAY(p_period)
               AND lp.reason_code <> 'EXPIRED_WRITEOFF' -- Исключаем просрочку из доли дефектуры
             GROUP BY lp.store_id, TO_tab.to_sum
           ) defs ON defs.store_id = q.store_id
    ON DUPLICATE KEY UPDATE
        liquid_share_pct = VALUES(liquid_share_pct),
        liquid_growth_pp = VALUES(liquid_growth_pp),
        def_share_pct    = VALUES(def_share_pct),
        def_multiplier   = VALUES(def_multiplier),
        kpi_adjust_pct   = VALUES(kpi_adjust_pct);
END;;

DROP PROCEDURE IF EXISTS `sp_night_repricing`;;
CREATE PROCEDURE `sp_night_repricing`(
    IN p_date DATE,
    OUT p_status_msg VARCHAR(100)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_status_msg = 'КРИТИЧЕСКИЙ СБОЙ: Переоценка ценников отменена (ROLLBACK).';
    END;

    START TRANSACTION;

    INSERT INTO repricing_log (batch_id, old_price, new_price, reprice_date, reason)
    SELECT b.batch_id, b.retail_price,
           CASE
               WHEN g.matrix_status = 'ZNVLP' THEN ROUND(b.purchase_price * (1 + LEAST(m.markup_pct, 25.00) / 100), 2)
               ELSE FLOOR(ROUND(b.purchase_price * (1 + m.markup_pct / 100), 2)) + 0.99
           END,
           p_date, 'MATRIX_RECALC_SMART_99'
      FROM goods_batches b
      JOIN goods g ON g.goods_id = b.goods_id
      JOIN markup_matrix m
        ON b.purchase_price >= m.price_from AND (m.price_to IS NULL OR b.purchase_price <= m.price_to)
     WHERE b.qty > 0 AND b.min_reprice_down = 10.00;

    UPDATE goods_batches b
      JOIN goods g ON g.goods_id = b.goods_id
      JOIN markup_matrix m
        ON b.purchase_price >= m.price_from AND (m.price_to IS NULL OR b.purchase_price <= m.price_to)
       SET b.retail_price = CASE
               WHEN g.matrix_status = 'ZNVLP' THEN ROUND(b.purchase_price * (1 + LEAST(m.markup_pct, 25.00) / 100), 2)
               ELSE FLOOR(ROUND(b.purchase_price * (1 + m.markup_pct / 100), 2)) + 0.99
           END
     WHERE b.qty > 0 AND b.min_reprice_down = 10.00;

    COMMIT;
    SET p_status_msg = 'УСПЕХ (COMMIT): ЖНВЛП по точной цене, коммерция округлена ВВЕРХ до .99.';
END;;

DROP PROCEDURE IF EXISTS `sp_process_transfer_returns`;;
CREATE PROCEDURE `sp_process_transfer_returns`(IN p_date DATE)
BEGIN
    INSERT INTO goods_batches
        (store_id, goods_id, qty, purchase_price, retail_price,
         expiry_date, purchase_type, donor_store_id, received_at)
    SELECT t.donor_store_id, t.goods_id, t.qty,
           b.purchase_price, b.retail_price, b.expiry_date,
           'AUTO', t.recipient_store_id, p_date
      FROM transfers t
      JOIN goods_batches b ON b.batch_id = t.batch_id
      JOIN goods g         ON g.goods_id = t.goods_id
      JOIN pharm_groups pg ON pg.group_id = g.group_id
     WHERE t.status = 'ACCEPTED'
       AND t.accepted_at <= p_date - INTERVAL pg.shelf_life_days DAY
       AND NOT EXISTS (
            SELECT 1 FROM sales s
             WHERE s.store_id = t.recipient_store_id
               AND s.goods_id = t.goods_id
               AND s.sale_datetime >= t.accepted_at
           );

    UPDATE transfers t
      JOIN goods g         ON g.goods_id = t.goods_id
      JOIN pharm_groups pg ON pg.group_id = g.group_id
       SET t.status = 'RETURNED_DEAD'
     WHERE t.status = 'ACCEPTED'
       AND t.accepted_at <= p_date - INTERVAL pg.shelf_life_days DAY
       AND NOT EXISTS (
            SELECT 1 FROM sales s
             WHERE s.store_id = t.recipient_store_id
               AND s.goods_id = t.goods_id
               AND s.sale_datetime >= t.accepted_at
           );
END;;

DROP PROCEDURE IF EXISTS `sp_verify_and_clean_declines`;;
CREATE PROCEDURE `sp_verify_and_clean_declines`(
    IN p_date DATE,
    OUT p_status_msg VARCHAR(100)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_status_msg = 'КРИТИЧЕСКИЙ СБОЙ: Аудит отказов отменен (ROLLBACK).';
    END;

    START TRANSACTION;

    -- 1. Фиктивные отказы (товар физически ON_SHELF > 0) -> в sabotage_log
    INSERT INTO sabotage_log (store_id, employee_id, marker_type, details, created_at)
    SELECT d.store_id, d.pharmacist_id, 'FAKE_DECLINE',
           CONCAT('Аудит на ', p_date, ': фиктивный отказ по goods_id=', d.goods_id, ', на полке=', b.on_shelf_qty),
           NOW()
      FROM lost_demand_log d
      JOIN (
          SELECT store_id, goods_id, SUM(qty) AS on_shelf_qty
            FROM goods_batches
           WHERE batch_status = 'ON_SHELF' AND turnover_anomaly_flag != 'CONFIRMED_MISSING'
           GROUP BY store_id, goods_id
      ) b ON b.store_id = d.store_id AND b.goods_id = d.goods_id
     WHERE d.validation_status = 'PENDING' AND b.on_shelf_qty > 0;

    UPDATE lost_demand_log d
      JOIN (
          SELECT store_id, goods_id, SUM(qty) AS on_shelf_qty
            FROM goods_batches
           WHERE batch_status = 'ON_SHELF' AND turnover_anomaly_flag != 'CONFIRMED_MISSING'
           GROUP BY store_id, goods_id
      ) b ON b.store_id = d.store_id AND b.goods_id = d.goods_id
       SET d.validation_status = 'INVALID'
     WHERE d.validation_status = 'PENDING' AND b.on_shelf_qty > 0;

    -- 2. Проставляем IN_TRANSIT_GAP, если на полке 0, но товар уже едет в машине (IN_TRANSIT)
    UPDATE lost_demand_log d
      JOIN (
          SELECT store_id, goods_id, SUM(qty) AS transit_qty
            FROM goods_batches
           WHERE batch_status = 'IN_TRANSIT'
           GROUP BY store_id, goods_id
      ) t ON t.store_id = d.store_id AND t.goods_id = d.goods_id
       SET d.defectura_type = 'IN_TRANSIT_GAP'
     WHERE d.validation_status = 'PENDING' AND t.transit_qty > 0;

    -- 3. Честные отказы (на полке 0) -> в упущенную выгоду (кроме CITY_DEFECTURA для штрафов)
    INSERT INTO lost_profit_log (store_id, goods_id, analog_goods_id, calc_date, lost_qty, lost_revenue, lost_margin, reason_code, defectura_type)
    SELECT d.store_id, d.goods_id, d.goods_id, p_date, d.lost_qty,
           (d.lost_qty * 500.00),
           CASE WHEN d.defectura_type = 'CITY_DEFECTURA' THEN 0.00 
                ELSE (d.lost_qty * GREATEST(g.marketing_bonus_pct * 10, 50.00)) END,
           'REAL_DEFECTURA', d.defectura_type
      FROM lost_demand_log d
      JOIN goods g ON g.goods_id = d.goods_id
     WHERE d.validation_status = 'PENDING';

    UPDATE lost_demand_log
       SET validation_status = 'VALID'
     WHERE validation_status = 'PENDING';

    COMMIT;
    SET p_status_msg = 'УСПЕХ (COMMIT): Отказы сверены с учетом товара в пути и городской дефектуры.';
END;;

DROP PROCEDURE IF EXISTS `sp_viability_recalc`;;
CREATE PROCEDURE `sp_viability_recalc`(IN p_date DATE)
BEGIN
    DECLARE v_month_start DATE;
    DECLARE v_prev_start  DATE;
    DECLARE v_prev_end    DATE;
    DECLARE v_days_passed INT;
    DECLARE v_days_total  INT;

    SET v_month_start = DATE_FORMAT(p_date, '%Y-%m-01');
    SET v_prev_start  = v_month_start - INTERVAL 1 MONTH;
    SET v_prev_end    = v_month_start - INTERVAL 1 DAY;
    SET v_days_passed = DAY(p_date);
    SET v_days_total  = DAY(LAST_DAY(p_date));

    INSERT INTO dm_business_viability
        (store_id, snapshot_date,
         to_past, margin_past_rub, plan_exec_past_pct,
         to_current, margin_current_rub, upch, sch, tz_rub,
         liquid_share_pct, surplus_share_pct, bad_stock_share_pct,
         expiring_share_pct, lost_profit_rub,
         to_forecast, plan_gap_pct, viability_marker, marker_comment)
    SELECT
        st.store_id, p_date,
        COALESCE(past.to_past, 0), COALESCE(past.margin_past, 0),
        ROUND(COALESCE(past.to_past,0) / NULLIF(fc.plan_to,0) * 100, 2),
        COALESCE(cur.to_cur, 0), COALESCE(cur.margin_cur, 0),
        COALESCE(cur.upch, 0), COALESCE(cur.sch, 0),
        COALESCE(q.tz_rub_net, 0),
        COALESCE(q.liquid_pct, 0), COALESCE(q.surplus_pct, 0),
        COALESCE(q.bad_pct, 0), COALESCE(q.expiring_pct, 0),
        COALESCE(lp.lost_margin_sum, 0),
        IF(v_days_passed < 5,
           COALESCE(fc.plan_to, 0),
ROUND(COALESCE(cur.to_cur,0) / v_days_passed * v_days_total, 2)),
ROUND(IF(v_days_passed < 5, 100,
COALESCE(cur.to_cur,0) / v_days_passed * v_days_total
/ NULLIF(fc.plan_to,0) * 100), 2),
CASE
WHEN DATEDIFF(p_date, st.opened_date) < 30 THEN 'INCUBATION'
WHEN COALESCE(lp.lost_margin_sum,0) > COALESCE(cur.to_cur,0) * 0.15
AND COALESCE(cur.margin_cur,0) < COALESCE(fc.rent_cost,0) + COALESCE(fc.fot_cost,0)
THEN 'CLOSURE'
WHEN ROUND(IF(v_days_passed < 5, 100,
COALESCE(cur.to_cur,0) / v_days_passed * v_days_total
/ NULLIF(fc.plan_to,0) * 100), 2) > 95
AND COALESCE(q.liquid_pct,0) >= 65
THEN 'RENTABLE'
ELSE 'RISK_ZONE'
END,
CASE
WHEN DATEDIFF(p_date, st.opened_date) < 30
THEN 'Стадия раскачки нового объекта, санкции к KPI заблокированы'
WHEN COALESCE(lp.lost_margin_sum,0) > COALESCE(cur.to_cur,0) * 0.15
THEN 'Логистика уничтожает точку: упущенная выгода > 15% ТО'
ELSE NULL
END
FROM stores st
LEFT JOIN pharmacy_fixed_costs fc
ON fc.store_id = st.store_id AND fc.period = v_month_start
LEFT JOIN (
SELECT store_id,
SUM(qty * retail_price)                    AS to_past,
SUM(qty * (retail_price - purchase_price)) AS margin_past
FROM sales
WHERE sale_date BETWEEN v_prev_start AND v_prev_end
GROUP BY store_id
) past ON past.store_id = st.store_id
LEFT JOIN (
SELECT store_id,
SUM(qty * retail_price)                    AS to_cur,
SUM(qty * (retail_price - purchase_price)) AS margin_cur,
ROUND(SUM(qty) / NULLIF(COUNT(DISTINCT sale_datetime),0), 2) AS upch,
ROUND(SUM(qty * retail_price)
/ NULLIF(COUNT(DISTINCT sale_datetime),0), 2)          AS sch
FROM sales
WHERE sale_date BETWEEN v_month_start AND p_date
GROUP BY store_id
) cur ON cur.store_id = st.store_id
LEFT JOIN v_stock_quality q ON q.store_id = st.store_id
LEFT JOIN (
SELECT store_id, SUM(lost_margin) AS lost_margin_sum
FROM lost_profit_log
WHERE calc_date BETWEEN v_month_start AND p_date
AND reason_code <> 'EXPIRED_WRITEOFF' -- Считаем только дефектуру и каннибализацию
GROUP BY store_id
) lp ON lp.store_id = st.store_id
WHERE st.is_active = 1
ON DUPLICATE KEY UPDATE
to_past = VALUES(to_past), margin_past_rub = VALUES(margin_past_rub),
plan_exec_past_pct = VALUES(plan_exec_past_pct),
to_current = VALUES(to_current), margin_current_rub = VALUES(margin_current_rub),
upch = VALUES(upch), sch = VALUES(sch), tz_rub = VALUES(tz_rub),
liquid_share_pct = VALUES(liquid_share_pct),
surplus_share_pct = VALUES(surplus_share_pct),
bad_stock_share_pct = VALUES(bad_stock_share_pct),
expiring_share_pct = VALUES(expiring_share_pct),
lost_profit_rub = VALUES(lost_profit_rub),
to_forecast = VALUES(to_forecast), plan_gap_pct = VALUES(plan_gap_pct),
viability_marker = VALUES(viability_marker),
marker_comment = VALUES(marker_comment);
END;;

DELIMITER ;
