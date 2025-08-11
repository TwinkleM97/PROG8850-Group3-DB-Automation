import os
import time
import random
from concurrent.futures import ThreadPoolExecutor, as_completed
import mysql.connector

DB_CFG = {
    "host": os.getenv("MYSQL_HOST", "127.0.0.1"),
    "port": int(os.getenv("MYSQL_PORT", "3307")),
    "user": os.getenv("MYSQL_USER", "root"),
    "password": os.getenv("MYSQL_PASSWORD", "Secret5555"),
    "database": os.getenv("MYSQL_DB", "project_db"),
}

def get_conn():
    return mysql.connector.connect(**DB_CFG)

def insert_row(i):
    conn = get_conn()
    try:
        cur = conn.cursor()
        q = """
        INSERT INTO ClimateData (location, record_date, temperature, precipitation, humidity)
        VALUES (%s, %s, %s, %s, %s)
        """
        locs = ["Ottawa","Toronto","Montreal","Vancouver","Calgary","Halifax","Winnipeg"]
        vals = (
            random.choice(locs),
            f"2025-07-{random.randint(10,28):02d}",
            round(random.uniform(15, 35), 1),
            round(random.uniform(0, 15), 1),
            round(random.uniform(25, 95), 1),
        )
        cur.execute(q, vals)
        conn.commit()
        return f"INSERT OK id={cur.lastrowid}"
    finally:
        conn.close()

def select_hot_days():
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT COUNT(*) FROM ClimateData
            WHERE temperature > 20
        """)
        count = cur.fetchone()[0]
        return f"SELECT OK hot_days={count}"
    finally:
        conn.close()

def update_humidity_by_location():
    conn = get_conn()
    try:
        cur = conn.cursor()
        # small, deterministic update for validation
        cur.execute("""
            UPDATE ClimateData
            SET humidity = LEAST(humidity + 5.0, 100.0)
            WHERE location IN ('Ottawa','Toronto')
        """)
        conn.commit()
        return f"UPDATE OK rows={cur.rowcount}"
    finally:
        conn.close()

def main():
    # light wait to avoid race with seeding
    time.sleep(1)
    tasks = []
    with ThreadPoolExecutor(max_workers=8) as ex:
        # burst of inserts
        for i in range(15):
            tasks.append(ex.submit(insert_row, i))
        # one select + one update issued concurrently
        tasks.append(ex.submit(select_hot_days))
        tasks.append(ex.submit(update_humidity_by_location))
        for f in as_completed(tasks):
            print(f.result())

    # final visibility
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) FROM ClimateData")
        total = cur.fetchone()[0]
        print(f"FINAL COUNT rows={total}")
    finally:
        conn.close()

if __name__ == "__main__":
    main()
