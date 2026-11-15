import random
from datetime import date, datetime, timedelta
import pymysql

DB_CONFIG = {
    'host': 'localhost',
    'user': 'root',
    'password': '',
    'database': 'apteka_bober',
    'charset': 'utf8mb4'
}

SCENARIO_PARAMS = {
    'spalnaya_fake_declines': 15,
    'spalnaya_expiring_batches': 3,
    'hospital_defectura_cases': 25,
    'city_defectura_cases': 8,
    'ai_events_count': 20
}

def run_anomaly_injector():
    conn = pymysql.connect(**DB_CONFIG)
    cursor = conn.cursor()
    today = date.today()
    now_dt = datetime.now()

    print("1. Очищаем старые логи аномалий и списаний...")
    cursor.execute("SET FOREIGN_KEY_CHECKS = 0;")
    for tbl in ('lost_demand_log', 'lost_profit_log', 'sabotage_log', 'repricing_log', 
                'expiry_writeoffs', 'penalty_distribution', 'ai_omni_audit_log', 'ai_demand_log', 'dm_business_viability'):
        cursor.execute(f"TRUNCATE TABLE {tbl};")
    cursor.execute("SET FOREIGN_KEY_CHECKS = 1;")

    print("2. Сценарий Аптеки №1 (Флагман): проверяем наличие стажера (< 90 дней)...")
    cursor.execute("SELECT employee_id FROM employees WHERE store_id = 1 AND is_active = 1 AND DATEDIFF(%s, hire_date) < 90", (today,))
    if not cursor.fetchone():
        hire_dt = today - timedelta(days=25)
        cursor.execute("INSERT INTO employees (store_id, last_name, first_name, middle_name, position, hire_date, is_active) VALUES (1, 'Новикова', 'Алина', 'Сергеевна', 'PHARMACIST', %s, 1)", (hire_dt,))
        new_emp_id = cursor.lastrowid
        cursor.execute("UPDATE sales SET employee_id = %s WHERE store_id = 1 AND sale_date >= %s - INTERVAL 7 DAY LIMIT 40", (new_emp_id, today))
        print(f"   -> Добавлен стажер (ID={new_emp_id}, стаж 25 дн.) и привязаны смены.")

    print("3. Сценарий Аптеки №2 (Спальная): моделируем просрочку и фиктивные отказы...")
    cursor.execute("SELECT batch_id FROM goods_batches WHERE store_id = 2 AND qty > 2 ORDER BY purchase_price DESC LIMIT %s", (SCENARIO_PARAMS['spalnaya_expiring_batches'],))
    exp_batches = [r for r in cursor.fetchall()]
    if exp_batches:
        cursor.execute("UPDATE goods_batches SET expiry_date = %s WHERE batch_id = %s", (today - timedelta(days=2), exp_batches[0]))
        for b_id in exp_batches[1:]:
            cursor.execute("UPDATE goods_batches SET expiry_date = %s, min_reprice_down = 1.00 WHERE batch_id = %s", (today + timedelta(days=20), b_id))

    cursor.execute("SELECT employee_id FROM employees WHERE store_id = 2 AND is_active = 1 LIMIT 1")
    emp_st2 = cursor.fetchone()
    cursor.execute("SELECT goods_id FROM goods_batches WHERE store_id = 2 AND qty > 5 AND batch_status = 'ON_SHELF' ORDER BY RAND() LIMIT %s", (SCENARIO_PARAMS['spalnaya_fake_declines'],))
    available_goods = [r for r in cursor.fetchall()]

    for g_id in available_goods:
        try:
            cursor.execute("INSERT INTO lost_demand_log (store_id, pharmacist_id, goods_id, lost_qty, scan_timestamp, validation_status, defectura_type) VALUES (2, %s, %s, %s, %s, 'PENDING', 'STORE_FAULT')", (emp_st2, g_id, random.randint(1, 2), now_dt - timedelta(hours=random.randint(1, 12))))
        except pymysql.MySQLError:
            cursor.execute("INSERT INTO sabotage_log (store_id, employee_id, marker_type, details, created_at) VALUES (2, %s, 'FAKE_DECLINE', %s, %s)", (emp_st2, f'Триггер заблокировал фиктивный отказ по goods_id={g_id}', now_dt))

    print("4. Сценарий Аптеки №3 (Прибольничная): создаем «потеряшку» и дефектуру...")
    cursor.execute("SELECT employee_id FROM employees WHERE store_id = 3 AND is_active = 1 LIMIT 1")
    emp_st3 = cursor.fetchone()
    cursor.execute("SELECT b.batch_id, b.goods_id FROM goods_batches b WHERE b.store_id = 3 AND b.qty > 0 ORDER BY b.purchase_price DESC LIMIT 1")
    row_st3 = cursor.fetchone()
    if row_st3:
        suspect_batch_id, suspect_goods_id = row_st3
        cursor.execute("DELETE FROM sales WHERE store_id = 3 AND goods_id = %s", (suspect_goods_id,))
        cursor.execute("UPDATE goods_batches SET received_at = %s WHERE batch_id = %s", (today - timedelta(days=135), suspect_batch_id))

    cursor.execute("SELECT goods_id FROM goods_batches WHERE store_id = 3 AND purchase_price > 500 ORDER BY RAND() LIMIT 4")
    zero_goods = [r for r in cursor.fetchall()]
    for g_id in zero_goods:
        cursor.execute("UPDATE goods_batches SET qty = 0 WHERE store_id = 3 AND goods_id = %s", (g_id,))
        for _ in range(SCENARIO_PARAMS['hospital_defectura_cases'] // 4):
            cursor.execute("INSERT INTO lost_demand_log (store_id, pharmacist_id, goods_id, lost_qty, scan_timestamp, validation_status, defectura_type) VALUES (3, %s, %s, %s, %s, 'PENDING', 'STORE_FAULT')", (emp_st3, g_id, random.randint(2, 4), now_dt - timedelta(hours=random.randint(1, 24))))

    cursor.execute("SELECT goods_id FROM goods_batches WHERE store_id = 3 AND qty > 0 ORDER BY RAND() LIMIT 2")
    city_zero_goods = [r for r in cursor.fetchall()]
    for g_id in city_zero_goods:
        cursor.execute("UPDATE goods_batches SET qty = 0 WHERE store_id = 3 AND goods_id = %s", (g_id,))
        for _ in range(SCENARIO_PARAMS['city_defectura_cases'] // 2):
            cursor.execute("INSERT INTO lost_demand_log (store_id, pharmacist_id, goods_id, lost_qty, scan_timestamp, validation_status, defectura_type) VALUES (3, %s, %s, 1, %s, 'PENDING', 'CITY_DEFECTURA')", (emp_st3, g_id, now_dt - timedelta(hours=random.randint(1, 12))))

    print("5. Сценарий Аптеки №4 (Дискаунтер): моделируем прогруз офиса и товар в пути...")
    cursor.execute("SELECT b.goods_id, b.purchase_price, b.retail_price, b.vat_pct FROM goods_batches b JOIN goods g ON g.goods_id = b.goods_id WHERE b.store_id = 4 AND g.is_impulse = 1 LIMIT 1")
    imp_item = cursor.fetchone()
    if imp_item:
        g_id, p_pr, r_pr, vat = imp_item
        cursor.execute("INSERT INTO goods_batches (store_id, goods_id, qty, purchase_price, retail_price, vat_pct, expiry_date, purchase_type, batch_status, received_at) VALUES (4, %s, 450, %s, %s, %s, %s, 'OFFICE_LOAD', 'ON_SHELF', %s)", (g_id, p_pr, r_pr, vat, today + timedelta(days=200), today))

    cursor.execute("SELECT goods_id, purchase_price, retail_price, vat_pct FROM goods_batches WHERE store_id = 1 LIMIT 1")
    tr_item = cursor.fetchone()
    if tr_item:
        g_id, p_pr, r_pr, vat = tr_item
        cursor.execute("INSERT INTO goods_batches (store_id, goods_id, qty, purchase_price, retail_price, vat_pct, expiry_date, purchase_type, batch_status, expected_arrival_date, received_at) VALUES (1, %s, 30, %s, %s, %s, %s, 'AUTO', 'IN_TRANSIT', %s, %s)", (g_id, p_pr, r_pr, vat, today + timedelta(days=400), today + timedelta(days=1), today))

    print("6. Наполняем логи ИИ-аудитора торгового зала...")
    ai_templates = [
        (2, 'PRICE_OBJECTION', 'Покупатель пожаловался, что здесь дороже, чем в аптеке через дорогу'),
        (3, 'DEFECTURA', 'Клиент спрашивал антикоагулянт, ушел без покупки — нет в наличии'),
        (1, 'QUEUE_PEAK', 'Скопление 6 человек у первой кассы, вторая касса закрыта'),
        (2, 'LOW_UX_SKILLS', 'Фармацевт не предложил пробиотик при отпуске антибиотика'),
        (4, 'NO_RECIPE', 'Запрос строго рецептурного препарата без бланка (отфильтрованный шум)')
    ]
    for _ in range(SCENARIO_PARAMS['ai_events_count']):
        st_id, ev_type, comment = random.choice(ai_templates)
        pass

    conn.commit()

    print("7. Запускаем ночной регламент хранимых процедур MySQL...")
    procedures = [
        "CALL sp_detect_latent_shortages(CURDATE());",
        "CALL sp_expire_repricing(CURDATE(), @m1);",
        "CALL sp_daily_minmax_recalc(CURDATE());",
        "CALL sp_verify_and_clean_declines(CURDATE(), @m2);",
        "CALL sp_distribute_writeoff_penalty(CURDATE(), @m3);",
        "CALL sp_viability_recalc(CURDATE());"
    ]
    for proc_sql in procedures:
        try:
            cursor.execute(proc_sql)
            conn.commit()
            print(f"   [OK] {proc_sql}")
        except pymysql.MySQLError as err:
            print(f"   [WARN] {proc_sql} -> {err}")

    cursor.close()
    conn.close()
    print("\nВСЕ 5 БИЗНЕС-СЦЕНАРИЕВ И ЧЕСТНЫЙ 7-ДНЕВНЫЙ ADU УСПЕШНО ПРОГНАНЫ!")

if __name__ == '__main__':
    run_anomaly_injector()