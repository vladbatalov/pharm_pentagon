import math
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

SEED_CARDS = [
    ('7770001', '2015-02-21'), ('7770002', '2024-04-02'), ('7770003', '2020-01-12'),
    ('7770004', '2022-03-09'), ('7770005', '2025-10-09'), ('7770006', '2019-05-03'),
    ('7770007', '2015-12-12'), ('7770008', '2024-08-25'), ('7770009', '2021-09-01'),
    ('7770011', '2025-11-28'), ('7770012', '2020-10-20'), ('7770013', '2019-01-19'),
    ('7770014', '2022-05-04'), ('7770015', '2024-03-17'), ('7770016', '2026-02-16'),
    ('7770017', '2017-12-19'), ('7770018', '2018-09-13'), ('7770019', '2023-06-30'),
    ('7770021', '2025-11-20'), ('7770022', '2026-08-02')
]

STORE_PROFILES = {
    1: {'cards': 5500, 'checks_start': 180, 'checks_end': 285, 'card_conv_start': 0.78, 'card_conv_end': 0.82},
    2: {'cards': 2200, 'checks_start': 150, 'checks_end': 68,  'card_conv_start': 0.75, 'card_conv_end': 0.35},
    3: {'cards': 3200, 'checks_start': 160, 'checks_end': 175, 'card_conv_start': 0.78, 'card_conv_end': 0.78},
    4: {'cards': 2000, 'checks_start': 105, 'checks_end': 118, 'card_conv_start': 0.82, 'card_conv_end': 0.82},
    5: {'cards': 950,  'checks_start': 70,  'checks_end': 80,  'card_conv_start': 0.85, 'card_conv_end': 0.85}
}

HOUR_WEIGHTS = [2, 4, 7, 10, 11, 10, 9, 9, 10, 11, 9, 5, 2, 1]

def run_sales_generator():
    conn = pymysql.connect(**DB_CONFIG)
    cursor = conn.cursor()

    print("1. Читаем реальные даты открытия аптек, штат и нормализованные цены из БД...")
    cursor.execute("SELECT store_id, store_name, opened_date FROM stores WHERE is_active = 1")
    stores = cursor.fetchall()

    cursor.execute("""
        SELECT b.goods_id, b.purchase_price, b.retail_price, g.is_impulse, g.matrix_status
          FROM goods_batches b
          JOIN goods g ON g.goods_id = b.goods_id
         WHERE b.store_id = 1 AND g.is_active = 1
    """)
    goods_catalog = cursor.fetchall()
    if not goods_catalog:
        print("ОШИБКА: Сначала запусти первый скрипт load_stock.py!")
        return

    regular_goods = [g for g in goods_catalog if g[3] == 0]
    impulse_goods = [g for g in goods_catalog if g[3] == 1] or regular_goods

    cursor.execute("SELECT store_id, employee_id, hire_date FROM employees WHERE is_active = 1 AND position = 'PHARMACIST'")
    staff_by_store = {}
    for st_id, emp_id, h_date in cursor.fetchall():
        staff_by_store.setdefault(st_id, []).append((emp_id, h_date))

    print("2. Генерируем 13 850 бонусных карт лояльности...")
    cursor.execute("SET FOREIGN_KEY_CHECKS = 0;")
    cursor.execute("TRUNCATE TABLE sales;")
    cursor.execute("TRUNCATE TABLE bonus_cards;")
    cursor.execute("SET FOREIGN_KEY_CHECKS = 1;")

    cards_to_insert = []
    for c_num, c_date in SEED_CARDS:
        cards_to_insert.append((c_num, f"Клиент #{c_num[-4:]}", c_date))

    current_num = 7770023
    today = date.today()
    store_card_pools = {st_id: [] for st_id in STORE_PROFILES}
    for idx in range(1, len(SEED_CARDS) + 1):
        store_card_pools[1].append(idx)

    card_id_counter = len(SEED_CARDS) + 1
    for st_id, prof in STORE_PROFILES.items():
        st_opened = next((s[2] for s in stores if s[0] == st_id), today - timedelta(days=365))
        days_since_open = max(1, (today - st_opened).days)
        needed = prof['cards'] - (len(SEED_CARDS) if st_id == 1 else 0)
        for _ in range(needed):
            reg_offset = random.randint(0, min(60, days_since_open)) if random.random() < 0.70 else random.randint(0, days_since_open)
            reg_date = st_opened + timedelta(days=reg_offset)
            c_num = str(current_num)
            cards_to_insert.append((c_num, f"Клиент #{c_num[-4:]}", reg_date))
            store_card_pools[st_id].append((card_id_counter, reg_date))
            current_num += 1
            card_id_counter += 1

    cursor.executemany(
        "INSERT INTO bonus_cards (card_number, holder_name, issued_at) VALUES (%s, %s, %s)",
        cards_to_insert
    )
    conn.commit()
    print(f"Успешно создано {len(cards_to_insert)} бонусных карт.")

    print("3. Генерируем историю продаж (ЖНВЛП точная / Коммерция .99 / Нал .00)...")
    sales_batch = []
    total_sales_rows = 0

    for st_id, st_name, opened_date in stores:
        prof = STORE_PROFILES.get(st_id, STORE_PROFILES[1])
        total_days = (today - opened_date).days
        if total_days <= 0:
            continue

        raw_pool = store_card_pools.get(st_id, [])
        clean_pool = [(item[0], item[1]) if isinstance(item, tuple) else (item, opened_date) for item in raw_pool]
        loyal_core = clean_pool[:int(len(clean_pool) * 0.30)]

        print(f"   -> {st_name}: период с {opened_date} по {today} ({total_days} дн.)...")

        for day_idx in range(total_days + 1):
            curr_date = opened_date + timedelta(days=day_idx)
            progress = day_idx / max(1, total_days)

            base_checks = prof['checks_start'] + (prof['checks_end'] - prof['checks_start']) * progress
            card_conv = prof['card_conv_start'] + (prof['card_conv_end'] - prof['card_conv_start']) * progress
            weekday_mult = 0.85 if curr_date.weekday() >= 5 else 1.0
            daily_checks = int(base_checks * weekday_mult * random.uniform(0.90, 1.10))

            active_emps = [emp_id for emp_id, h_date in staff_by_store.get(st_id, []) if h_date <= curr_date]
            if not active_emps:
                active_emps = [emp_id for emp_id, _ in staff_by_store.get(st_id, [])]

            valid_cards = [cid for cid, reg_d in clean_pool if reg_d <= curr_date]
            valid_loyal = [cid for cid, reg_d in loyal_core if reg_d <= curr_date]

            for _ in range(daily_checks):
                hour = random.choices(range(8, 22), weights=HOUR_WEIGHTS)[0]
                sale_dt = datetime(curr_date.year, curr_date.month, curr_date.day, hour, random.randint(0, 59), random.randint(0, 59))
                emp_id = random.choice(active_emps)

                card_id = None
                if valid_cards and random.random() < card_conv:
                    card_id = random.choice(valid_loyal) if (valid_loyal and random.random() < 0.35) else random.choice(valid_cards)

                pay_method = 'CARD' if random.random() < 0.75 else 'CASH'

                items_in_check = random.choices([1, 2, 3, 4], weights=[50, 30, 15, 5])[0]
                chosen_goods = random.sample(regular_goods, k=min(items_in_check, len(regular_goods)))
                if random.random() < 0.25 and impulse_goods:
                    chosen_goods.append(random.choice(impulse_goods))

                for g_id, p_price, r_price, _, m_status in chosen_goods:
                    qty = random.choices([1, 2, 3], weights=[82, 14, 4])[0]
                    p_val = float(p_price)
                    r_val = float(r_price)

                    if card_id and m_status != 'ZNVLP':
                        discounted = round(r_val * 0.97, 2)
                        r_val = float(math.floor(discounted)) + 0.99
                        if r_val < p_val:
                            r_val = float(r_price)

                    if pay_method == 'CASH':
                        r_val = max(p_val, float(math.floor(r_val)))

                    sales_batch.append((st_id, emp_id, card_id, g_id, qty, p_val, r_val, pay_method, sale_dt))

                    if len(sales_batch) >= 10000:
                        cursor.executemany("""
                            INSERT INTO sales 
                            (store_id, employee_id, card_id, goods_id, qty, purchase_price, retail_price, payment_method, sale_datetime)
                            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                        """, sales_batch)
                        conn.commit()
                        total_sales_rows += len(sales_batch)
                        sales_batch.clear()

    if sales_batch:
        cursor.executemany("""
            INSERT INTO sales 
            (store_id, employee_id, card_id, goods_id, qty, purchase_price, retail_price, payment_method, sale_datetime)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        """, sales_batch)
        conn.commit()
        total_sales_rows += len(sales_batch)

    cursor.close()
    conn.close()
    print(f"ГОТОВО! Создано {len(cards_to_insert)} карт и {total_sales_rows} позиций в чеках!")

if __name__ == '__main__':
    run_sales_generator()
