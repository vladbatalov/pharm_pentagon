import datetime
import pymysql
import random

DB_CONFIG = {
    'host': 'localhost',
    'user': 'root',
    'password': 'root1234', 
    'database': 'apteka_bober',
    'charset': 'utf8mb4',
    'cursorclass': pymysql.cursors.DictCursor
}

def generate_batches():
    conn = pymysql.connect(**DB_CONFIG)
    try:
        with conn.cursor() as cursor:
            print("Очистка старых партий...")
            cursor.execute("SET FOREIGN_KEY_CHECKS = 0;")
            cursor.execute("TRUNCATE TABLE goods_batches;")
            cursor.execute("SET FOREIGN_KEY_CHECKS = 1;")

            # 1. Получаем актуальные Мин-Максы
            cursor.execute("""
                SELECT mm.store_id, mm.goods_id, mm.effective_max
                FROM min_max mm
                WHERE mm.calc_date = CURDATE() AND mm.effective_max > 0
            """)
            minmax_data = cursor.fetchall()

            # 2. Получаем средние цены из ПРОДАЖ
            cursor.execute("""
                SELECT s.goods_id, 
                       AVG(s.purchase_price) as avg_purchase, 
                       AVG(s.retail_price) as avg_retail
                FROM sales s
                GROUP BY s.goods_id
            """)
            prices = {row['goods_id']: (float(row['avg_purchase']), float(row['avg_retail'])) for row in cursor.fetchall()}

            print(f"Найдено {len(minmax_data)} записей для генерации партий...")

            batches_to_insert = []
            today = datetime.date.today()

            # Счетчики для обеспечения нужных процентов
            # (в реальности лучше делать по количеству SKU, но для демо сойдет и по штукам)
            
            for row in minmax_data:
                store_id = row['store_id']
                goods_id = row['goods_id']
                max_qty = row['effective_max']
                
                purchase_price, retail_price = prices.get(goods_id, (500.0, 700.0))

                # Базовый товар (всегда ликвидный)
                qty_main = max_qty + random.randint(1, 5)
                expiry_main = today + datetime.timedelta(days=random.randint(100, 365))
                received_main = today - datetime.timedelta(days=random.randint(1, 30))
                
                batches_to_insert.append((
                    store_id, goods_id, qty_main, purchase_price, retail_price,
                    expiry_main, 'AUTO', None, received_main, 5.00, 10.00, 0, 'NONE'
                ))

                # --- ФОРМИРУЕМ СТАТУСЫ ДЛЯ АПТЕК ---
                
                # Аптека 1 (Флагман) - ВСЕ СТАТУСЫ, НО В НОРМЕ
                if store_id == 1:
                    if random.random() < 0.15: # 15% SKU идут в излишки
                        qty_surplus = max_qty * 2 + random.randint(5, 15)
                        batches_to_insert.append((
                            store_id, goods_id, qty_surplus, purchase_price, retail_price,
                            today + datetime.timedelta(days=180), 'AUTO', None, today - datetime.timedelta(days=10), 5.00, 10.00, 0, 'NONE'
                        ))
                    if random.random() < 0.05: # 5% SKU - неликвид
                        qty_dead = random.randint(5, 15)
                        batches_to_insert.append((
                            store_id, goods_id, qty_dead, purchase_price, retail_price,
                            today + datetime.timedelta(days=80), 'AUTO', None, today - datetime.timedelta(days=200), 5.00, 10.00, 0, 'NONE'
                        ))
                    if random.random() < 0.03: # 3% SKU - сроковые
                        qty_exp = random.randint(1, 3)
                        batches_to_insert.append((
                            store_id, goods_id, qty_exp, purchase_price, retail_price,
                            today + datetime.timedelta(days=random.randint(10, 60)), 'AUTO', None, today - datetime.timedelta(days=40), 5.00, 10.00, 0, 'NONE'
                        ))

                # Аптека 2 (Спальный) - БАРДАК
                elif store_id == 2:
                    if random.random() < 0.3:
                        qty_surplus = max_qty * 3 + random.randint(10, 30)
                        batches_to_insert.append((
                            store_id, goods_id, qty_surplus, purchase_price, retail_price,
                            today + datetime.timedelta(days=200), 'AUTO', None, today - datetime.timedelta(days=15), 5.00, 10.00, 0, 'NONE'
                        ))
                    if random.random() < 0.25:
                        qty_dead = random.randint(20, 60)
                        batches_to_insert.append((
                            store_id, goods_id, qty_dead, purchase_price, retail_price,
                            today + datetime.timedelta(days=70), 'AUTO', None, today - datetime.timedelta(days=180), 5.00, 10.00, 0, 'NONE'
                        ))
                    if random.random() < 0.15 or goods_id == 8: # Ибуклин (8) обязательно сроковый
                        qty_exp = random.randint(2, 8)
                        batches_to_insert.append((
                            store_id, goods_id, qty_exp, purchase_price, retail_price,
                            today + datetime.timedelta(days=random.randint(5, 20)), 'AUTO', None, today - datetime.timedelta(days=60), 5.00, 10.00, 0, 'NONE'
                        ))

                # Аптека 3 (Прибольничная) - ВСЕ ЛИКВИДНО, НО ЕСТЬ ПОТЕРЯШКА
                elif store_id == 3:
                    if goods_id == 6: # Ксарелто (потеряшка)
                        batches_to_insert.append((
                            store_id, goods_id, 5, purchase_price, retail_price,
                            today + datetime.timedelta(days=200), 'AUTO', None, today - datetime.timedelta(days=100), 5.00, 10.00, 0, 'CONFIRMED_MISSING'
                        ))
                    # Излишки нет, неликвида нет.

                # Аптека 4 (Дискаунтер) - ОФИСНЫЙ ПРОГРУЗ
                elif store_id == 4:
                    if random.random() < 0.4:
                        qty_office = max_qty * 4 + random.randint(20, 80)
                        batches_to_insert.append((
                            store_id, goods_id, qty_office, purchase_price, retail_price,
                            today + datetime.timedelta(days=150), 'OFFICE_LOAD', None, today - datetime.timedelta(days=14), 5.00, 10.00, 0, 'NONE'
                        ))
                    if random.random() < 0.1:
                        qty_dead = random.randint(10, 30)
                        batches_to_insert.append((
                            store_id, goods_id, qty_dead, purchase_price, retail_price,
                            today + datetime.timedelta(days=90), 'AUTO', None, today - datetime.timedelta(days=170), 5.00, 10.00, 0, 'NONE'
                        ))

                # Аптека 5 (Новая) - ИНКУБАЦИЯ (все партии новые и недавние)
                elif store_id == 5:
                    # Просто создаем базовые партии (они уже вставлены выше)
                    # Они все попадут в INCUBATION, так как аптека открылась 12 дней назад
                    pass

            print(f"Вставка {len(batches_to_insert)} партий в базу...")
            insert_query = """
                INSERT INTO goods_batches 
                (store_id, goods_id, qty, purchase_price, retail_price, expiry_date, purchase_type, donor_store_id, received_at, min_reprice_up, min_reprice_down, is_returned_dead, turnover_anomaly_flag)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """
            for i in range(0, len(batches_to_insert), 1000):
                cursor.executemany(insert_query, batches_to_insert[i:i+1000])
                conn.commit()

            print("Готово! Создана реалистичная картина со всеми статусами.")

    finally:
        conn.close()

if __name__ == "__main__":
    generate_batches()