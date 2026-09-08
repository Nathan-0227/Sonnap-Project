"""
守「SQLite 與 MySQL 兩個後端不可以漂移」。

═══════════════════════════════════════════════════════════════════════
為什麼需要這支
═══════════════════════════════════════════════════════════════════════
支援兩個後端就是有兩條程式碼路徑，而兩條路徑會漂移——這個專案已經因為
同型的問題吃過好幾次虧（`has_measured_sleep` vs `is_valid_night`、
asset 與 API 兩條路的 `pet_mood`、三個叫「睡眠效率」的東西）。

漂移在這裡特別安靜：MySQL 那條路只有真的接上 MySQL 才會跑到，而測試
預設是 SQLite。少一個欄位、`ON CONFLICT` 翻錯、`?` 沒換成 `%s`——
在開發機上全部看不到，只有 demo 當天才會炸。

═══════════════════════════════════════════════════════════════════════
⚠️ 沒有 MySQL 也要能跑
═══════════════════════════════════════════════════════════════════════
連不到 MySQL 時，需要連線的那幾條會**跳過並明講跳過了**，不會讓整支紅。
本專案的驗收指令是「獨立腳本、不需 pytest」，要求先開 XAMPP 才跑得動
就破壞了那個性質。

但**不需要連線的那幾條照跑**——DDL 是從 SCHEMA 產生的，翻譯是純字串
處理，這兩塊佔了漂移風險的大半，而且完全離線驗得了。

    # 要跑 MySQL 那幾條就給這個：
    set SONNAP_TEST_MYSQL_URL=mysql://root@127.0.0.1:3306/sonnap_test
"""
import os
import sqlite3
import sys
import tempfile
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import db            # noqa: E402
import db_backend    # noqa: E402

PASS = FAIL = SKIP = 0


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  ✓ {name}")
    else:
        FAIL += 1
        print(f"  ✗ {name}  {detail}")


def skip(name, why):
    global SKIP
    SKIP += 1
    print(f"  – {name}（跳過：{why}）")


# ═══════════════════════════════════════════════════════════════════
# 離線可驗的部分
# ═══════════════════════════════════════════════════════════════════

def sqlite_columns_from_schema():
    conn = sqlite3.connect(":memory:")
    conn.executescript(db.SCHEMA)
    out = {}
    for (t,) in conn.execute("SELECT name FROM sqlite_master WHERE type='table' "
                             "AND name NOT LIKE 'sqlite_%'"):
        out[t] = [r[1] for r in conn.execute(f'PRAGMA table_info("{t}")')]
    conn.close()
    return out


def mysql_columns_from_ddl():
    """從產生出來的 DDL 反推欄位。刻意用字串解析——如果 DDL 長得不對，
    這裡就會解析不出來，那正是我們想知道的事。"""
    import re
    out = {}
    for stmt in db_backend.mysql_ddl(db.SCHEMA):
        m = re.match(r"CREATE TABLE IF NOT EXISTS `(\w+)` \((.*)\n\)",
                     stmt, re.DOTALL)
        if not m:
            continue
        table, body = m.group(1), m.group(2)
        cols = []
        for line in body.split("\n"):
            cm = re.match(r"\s*`(\w+)` ", line)
            if cm:
                cols.append(cm.group(1))
        out[table] = cols
    return out


def offline_checks():
    print("\n【1】⚠️ 兩個後端的欄位集合必須完全相同")
    # 這是整支最重要的一條。MySQL 的 DDL 是從 SQLite 的 SCHEMA 產生的，
    # 所以理論上不可能少——但「理論上」正是需要測試的地方。
    a = sqlite_columns_from_schema()
    b = mysql_columns_from_ddl()
    check("表的集合相同", set(a) == set(b),
          f"只在 SQLite: {set(a) - set(b)} / 只在 MySQL: {set(b) - set(a)}")
    for t in sorted(set(a) & set(b)):
        check(f"{t} 的欄位相同（{len(a[t])} 欄）", a[t] == b[t],
              f"SQLite {a[t]}\n      MySQL  {b[t]}")

    print("\n【2】索引與主鍵有被帶過去")
    ddl = "\n".join(db_backend.mysql_ddl(db.SCHEMA))
    check("複合主鍵有帶（user_id, date）",
          "PRIMARY KEY (`user_id`, `date`)" in ddl)
    check("外鍵與 CASCADE 有帶",
          "ON DELETE CASCADE" in ddl and "REFERENCES `users`" in ddl)
    check("明確建的索引有帶", "idx_block_events_user_date" in ddl)
    check("AUTOINCREMENT 翻成 AUTO_INCREMENT", "AUTO_INCREMENT" in ddl)

    print("\n【3】⚠️ 進索引的字串欄位要是 VARCHAR，不能是 TEXT")
    # MySQL 不能對 TEXT 建索引。這條錯了的話是**建表就失敗**，
    # 但那要有 MySQL 才看得到——所以在這裡先擋。
    check("user_id 是 VARCHAR", "`user_id` VARCHAR(191)" in ddl)
    check("date 是 VARCHAR", "`date` VARCHAR(191)" in ddl)
    check("反向對照：沒進索引的還是 TEXT",
          "`display_name` TEXT" in ddl,
          "全部都變 VARCHAR 的話，長文字欄位會被截斷")

    print("\n【4】SQL 翻譯")
    t = db_backend.translate
    check("? → %s", t("SELECT * FROM x WHERE a = ? AND b = ?")
          == "SELECT * FROM x WHERE a = %s AND b = %s")
    check("ON CONFLICT → ON DUPLICATE KEY UPDATE",
          t("INSERT INTO t VALUES (?) ON CONFLICT(a) DO UPDATE SET b = excluded.b")
          == "INSERT INTO t VALUES (%s) ON DUPLICATE KEY UPDATE b = VALUES(b)")
    check("複合鍵的 ON CONFLICT 也翻得動",
          "ON DUPLICATE KEY UPDATE" in t("... ON CONFLICT(a, b) DO UPDATE SET c = excluded.c"))
    # ⚠️ 反向對照：字串字面值裡的問號不可以被換掉。
    check("反向對照：字串裡的 ? 不動",
          t("SELECT * FROM x WHERE a = '?' AND b = ?")
          == "SELECT * FROM x WHERE a = '?' AND b = %s")

    print("\n【5】db.py 的每一句 SQL 都翻得動")
    # 這一條抓的是「有人加了新語法但沒進翻譯層」。翻不動時 MySQL 會丟
    # 語法錯誤（不是安靜錯），但那要跑到才知道——這裡先靜態掃一次。
    src = (ROOT / "db.py").read_text(encoding="utf-8")
    check("沒有殘留的 ON CONFLICT 形式是翻譯層不認得的",
          src.count("ON CONFLICT") == len(
              db_backend._ON_CONFLICT.findall(src)),
          f"文字裡 {src.count('ON CONFLICT')} 個，"
          f"翻譯層認得 {len(db_backend._ON_CONFLICT.findall(src))} 個")
    check("⚠️ 衍生表都有別名（MySQL 要求，SQLite 不要求）",
          ") ORDER BY" not in src,
          "`SELECT * FROM (...) ORDER BY` 在 MySQL 是語法錯誤，要寫 `) AS x ORDER BY`")

    print("\n【6】URL 解析")
    cfg = db_backend.mysql_config("mysql://root@localhost/sonnap")
    check("XAMPP 那種沒有密碼的也解析得出來",
          cfg and cfg["user"] == "root" and cfg["password"] == ""
          and cfg["database"] == "sonnap" and cfg["port"] == 3306, str(cfg))
    cfg2 = db_backend.mysql_config("mysql://u:p%40ss@10.0.0.1:3307/db2")
    check("密碼裡的特殊字元有 unquote",
          cfg2 and cfg2["password"] == "p@ss" and cfg2["port"] == 3307, str(cfg2))
    check("不是 mysql:// 就回 None",
          db_backend.mysql_config("sqlite:///x.db") is None)
    check("沒給資料庫名稱要報錯", _raises(
        lambda: db_backend.mysql_config("mysql://root@localhost")))


def _raises(fn):
    try:
        fn()
        return False
    except Exception:
        return True


# ═══════════════════════════════════════════════════════════════════
# 需要連上 MySQL 的部分
# ═══════════════════════════════════════════════════════════════════

def live_checks(url):
    print("\n【7】兩個後端跑同一組操作，結果必須一樣")
    cfg = db_backend.mysql_config(url)
    conn = db_backend.MySQLConn(cfg)
    for t in ("challenge_progress", "block_events", "app_usage_daily",
              "nightly_behavior", "wearable_nightly", "challenges", "users"):
        try:
            conn.execute(f"DROP TABLE IF EXISTS `{t}`")
        except Exception:
            pass
    conn.commit()
    conn.close()

    with tempfile.TemporaryDirectory() as td:
        lite = Path(td) / "t.db"
        results = {}
        for label, setup in (("sqlite", lite), ("mysql", None)):
            if label == "mysql":
                os.environ["SONNAP_DB_URL"] = url
            else:
                os.environ.pop("SONNAP_DB_URL", None)

            db.init_db(setup)
            db.seed_challenges(setup)
            uid = db.create_user("測試員", db_path=setup)   # 回傳的是 user_id 字串
            db.upsert_nightly_behavior(
                uid, "2026-09-08", "23:30", "2026-09-08T03:06:54",
                216.9, True, db_path=setup)
            # 同一晚寫第二次 → 走 upsert 那條路
            db.upsert_nightly_behavior(
                uid, "2026-09-08", "23:30", "2026-09-08T02:00:00",
                150.0, True, db_path=setup)
            db.upsert_wearable_nightly(
                uid, "2026-09-08", "garmin",
                {"duration_min": 393.0, "efficiency": 91.2,
                 "final_score": 82.8, "final_quality": "Good"},
                db_path=setup)
            rows = db.get_nightly_behavior(uid, days=30, db_path=setup)
            wear = db.get_wearable_nightly(uid, days=30, db_path=setup)
            results[label] = {
                "behavior": [{k: r[k] for k in
                              ("date", "lights_out_at", "adherence_minutes",
                               "is_late", "target_bedtime")} for r in rows],
                "wearable": [{k: r[k] for k in
                              ("date", "duration_min", "efficiency",
                               "final_score", "final_quality")} for r in wear],
                "challenges": sorted(c["challenge_id"]
                                     for c in db.get_challenges(setup)),
            }
        os.environ.pop("SONNAP_DB_URL", None)

        a, b = results["sqlite"], results["mysql"]
        check("nightly_behavior 逐欄相同", a["behavior"] == b["behavior"],
              f"\n      sqlite {a['behavior']}\n      mysql  {b['behavior']}")
        check("upsert 真的覆蓋了（不是插了兩列）",
              len(a["behavior"]) == 1 and len(b["behavior"]) == 1,
              f"sqlite {len(a['behavior'])} 列 / mysql {len(b['behavior'])} 列")
        check("wearable_nightly 逐欄相同", a["wearable"] == b["wearable"],
              f"\n      sqlite {a['wearable']}\n      mysql  {b['wearable']}")
        check("challenges 相同", a["challenges"] == b["challenges"])

    print("\n【8】⚠️ 外鍵 CASCADE 在 MySQL 也要生效")
    # 知情同意書承諾「退出即刪除」。SQLite 那邊靠 PRAGMA foreign_keys=ON，
    # MySQL 的 InnoDB 預設就開——但「預設」值得驗一次，不然孤兒資料
    # 不會有任何錯誤訊息。
    os.environ["SONNAP_DB_URL"] = url
    try:
        uid = db.create_user("待刪除")
        db.upsert_nightly_behavior(uid, "2026-09-09", "23:30",
                                   "2026-09-09T01:00:00", 90.0, True)
        before = len(db.get_nightly_behavior(uid, days=30))
        db.delete_user(uid)
        after = len(db.get_nightly_behavior(uid, days=30))
        check("刪掉使用者，他的夜晚也跟著沒了",
              before == 1 and after == 0, f"before={before} after={after}")
    finally:
        os.environ.pop("SONNAP_DB_URL", None)


def main():
    print("=" * 70)
    print("兩個後端的一致性")
    print("=" * 70)
    offline_checks()

    url = os.environ.get("SONNAP_TEST_MYSQL_URL")
    if not url:
        print("\n【7】【8】需要 MySQL")
        skip("兩個後端跑同一組操作", "沒設 SONNAP_TEST_MYSQL_URL")
        skip("外鍵 CASCADE", "沒設 SONNAP_TEST_MYSQL_URL")
    else:
        try:
            live_checks(url)
        except Exception as exc:          # noqa: BLE001
            print(f"\n  ✗ MySQL 那幾條炸了：{type(exc).__name__}: {exc}")
            global FAIL
            FAIL += 1

    print()
    print("=" * 70)
    print(f"通過 {PASS} / 失敗 {FAIL} / 跳過 {SKIP}")
    if SKIP:
        print("⚠️ 跳過的那幾條要有 MySQL 才驗得了。demo 前務必跑一次：")
        print("   set SONNAP_TEST_MYSQL_URL=mysql://root@127.0.0.1:3306/sonnap_test")
    print("=" * 70)
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
