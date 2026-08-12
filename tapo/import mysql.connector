import mysql.connector

DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "",
    "database": "sonnap"
}

try:
    conn = mysql.connector.connect(**DB_CONFIG)
    cursor = conn.cursor()
    cursor.execute("SHOW TABLES")
    tables = cursor.fetchall()
    print("✅ 資料庫連線成功！")
    print(f"📊 資料表: {[t[0] for t in tables]}")
    cursor.close()
    conn.close()
except Exception as e:
    print(f"❌ 連線失敗: {e}")
    