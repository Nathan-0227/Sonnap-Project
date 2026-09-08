"""
守 `db_show.py` 那兩個**壞掉時不會報錯**的地方。

⚠️ 最重要的一條是 `user_id` 不可以被完整印出來。這個 API 沒有認證，
   `user_id` 本身就是憑證（見 CLAUDE.md）——查詢工具把它印進終端機、
   再被貼進 issue 或訊息裡，就等於把帳號交出去。而漏印**不會有任何
   錯誤訊息**，只會多出一串看起來無害的十六進位字串。

每一條都用「把 bug 重新引入、確認測試會紅」驗證過。
"""
import os
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

PASS = FAIL = 0
USER_ID = "d1e685eb-1234-4abc-9def-0123456789ab"


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  ✓ {name}")
    else:
        FAIL += 1
        print(f"  ✗ {name}  {detail}")


def make_db(path):
    conn = sqlite3.connect(path)
    conn.execute("""CREATE TABLE nightly_behavior (
        user_id TEXT, date TEXT, lights_out_at TEXT,
        bed_start_at TEXT, sleep_efficiency REAL)""")
    conn.execute("INSERT INTO nightly_behavior VALUES (?,?,?,?,?)",
                 (USER_ID, "2026-09-08", "2026-09-08T03:06:54", None, None))
    conn.commit()
    conn.close()


def run(*args, stdin=None):
    return subprocess.run(
        [sys.executable, str(ROOT / "db_show.py"), *map(str, args)],
        input=stdin, capture_output=True, text=True, encoding="utf-8",
        env={**os.environ, "PYTHONIOENCODING": "utf-8"})


def main():
    print("=" * 70)
    print("db_show 守門測試")
    print("=" * 70)

    with tempfile.TemporaryDirectory() as td:
        db = Path(td) / "t.db"
        make_db(db)

        print("\n【1】⚠️ 預設不可以印出完整的 user_id")
        r = run("2026-09-08", "--db", db)
        check("查某一晚時不外流", USER_ID not in r.stdout, r.stdout[:300])
        check("但仍看得出是哪個人（前 8 碼）", USER_ID[:8] in r.stdout)
        r2 = run("--db", db, "--sql", "SELECT * FROM nightly_behavior")
        check("自訂 SQL 也不外流", USER_ID not in r2.stdout, r2.stdout[:300])
        r3 = run("--db", db, "--table", "nightly_behavior")
        check("印整張表也不外流", USER_ID not in r3.stdout, r3.stdout[:300])

        print("\n【2】反向對照：明確要求時才印完整")
        # 沒有這一條，把 user_id 整欄砍掉也會讓上面全部通過，
        # 而那會讓多使用者的資料分不出是誰的。
        r4 = run("2026-09-08", "--db", db, "--show-user-id")
        check("--show-user-id 印得出來", USER_ID in r4.stdout, r4.stdout[:300])

        print("\n【3】⚠️ 寫入一律拒絕")
        for sql in ("DELETE FROM nightly_behavior",
                    "UPDATE nightly_behavior SET date='x'",
                    "DROP TABLE nightly_behavior"):
            r5 = run("--db", db, "--sql", sql)
            check(f"擋下 {sql.split()[0]}", r5.returncode != 0)
        # 真正的保證是 SQLite 的 mode=ro，不是上面那層字串檢查。
        conn = sqlite3.connect(f"file:{db.as_posix()}?mode=ro", uri=True)
        try:
            conn.execute("DELETE FROM nightly_behavior")
            check("SQLite 本身拒絕寫入", False, "竟然寫得進去")
        except sqlite3.OperationalError:
            check("SQLite 本身拒絕寫入（真正的保證在這一層）", True)
        conn.close()
        # 資料真的沒被動到
        conn = sqlite3.connect(db)
        n = conn.execute("SELECT COUNT(*) FROM nightly_behavior").fetchone()[0]
        conn.close()
        check("跑完之後資料還在", n == 1, f"剩 {n} 列")

        print("\n【6】互動式 shell")
        # ⚠️ shell 與 --sql 共用同一個印表函式。兩份各自實作的話，遮蔽
        #    user_id 的邏輯會有兩個定義處——改一邊忘另一邊不會有錯誤訊息。
        script = (
            ".tables\n"
            "SELECT date, user_id FROM nightly_behavior;\n"
            "DELETE FROM nightly_behavior;\n"
            "SELECT * FROM nosuch;\n"
            "SELECT date\nFROM nightly_behavior;\n"
            ".quit\n"
        )
        r8 = run("--db", db, "--shell", stdin=script)
        out8 = r8.stdout
        check("跑得完且沒有例外", r8.returncode == 0, r8.stderr[-300:])
        check(".tables 列得出表", "nightly_behavior" in out8)
        check("⚠️ shell 裡也不外流 user_id", USER_ID not in out8, out8[:400])
        check("寫入被擋", "只接受 SELECT" in out8)
        check("SQL 錯誤不會中斷 shell", "no such table" in out8)
        check("跨行 SQL 要能執行", out8.count("2026-09-08") >= 2, out8[-400:])

        print("\n【4】查不到的日期要說有哪些日期，不是空白")
        r6 = run("2020-01-01", "--db", db)
        check("提示現有的日期", "2026-09-08" in r6.stdout, r6.stdout[:300])

        print("\n【5】DB 不存在時給得出下一步")
        r7 = run("--db", Path(td) / "nope.db")
        out = r7.stdout + r7.stderr
        check("提到 SONNAP_DB", r7.returncode != 0 and "SONNAP_DB" in out, out[:300])

    print()
    print("=" * 70)
    print(f"通過 {PASS} / 失敗 {FAIL}")
    print("=" * 70)
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
