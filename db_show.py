"""
看資料庫裡有什麼 —— **唯讀**。

═══════════════════════════════════════════════════════════════════════
⚠️ 這支永遠不寫。
═══════════════════════════════════════════════════════════════════════
用 `file:...?mode=ro` 開啟，所以連寫錯的可能性都沒有——不是靠自律，
是靠 SQLite 本身拒絕。要改資料請用 `db.py` 或後端 API。

⚠️ **`user_id` 本身就是憑證**（這個 API 沒有認證，見 CLAUDE.md）。
   所以這支預設**不印** user_id，只印它的前 8 碼當識別。
   要完整的請加 `--show-user-id`，並且不要把輸出貼到會外流的地方。

用法
────────────────────────────────────────────────────────────────────
  python db_show.py                      # 每張表有幾列、欄位是什麼
  python db_show.py 2026-09-08           # 那一晚在每張表裡的資料
  python db_show.py --table nightly_behavior
  python db_show.py --sql "SELECT date, sleep_efficiency FROM nightly_behavior"

  # 換一個 DB（預設跟後端一樣看 SONNAP_DB）
  python db_show.py --db C:/Users/user/Projects/sonnap-data/sonnap.db

⚠️ 為什麼要有這支：同樣的事用 `python -c "..."` 一行寫，在 PowerShell 底下
   引號會被吃掉（2026-09-09 實際踩到：`\\"` 傳進去變成語法錯誤）。
   查資料庫是每天都要做的事，不該每次都跟 shell 的引號規則纏鬥。
"""
import argparse
import os
import sqlite3
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).parent
DEFAULT_DB = Path(os.environ.get("SONNAP_DB") or (ROOT / "data" / "sonnap.db"))

# 這些表有 date 欄，`db_show.py <日期>` 會逐一查
DATE_TABLES = ("nightly_behavior", "wearable_nightly", "app_usage_daily",
               "block_events")


def connect(path):
    p = Path(path)
    if not p.exists():
        sys.exit(f"✗ 找不到 {p}\n"
                 f"   後端現在用的可能是別的檔案。看 SONNAP_DB 環境變數，"
                 f"或用 --db 指定。")
    # ⚠️ mode=ro：唯讀是由 SQLite 保證的，不是靠這支程式自律。
    conn = sqlite3.connect(f"file:{p.as_posix()}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    return conn


def mask(key, value, show_user_id):
    if key == "user_id" and value and not show_user_id:
        return f"{str(value)[:8]}…（隱去，user_id 是憑證）"
    return value


def print_row(row, show_user_id, indent="   "):
    width = max(len(k) for k in row.keys())
    for k in row.keys():
        v = mask(k, row[k], show_user_id)
        tail = "" if v not in (None, "") else "   ← 空的"
        print(f"{indent}{k:<{width}}  {v}{tail}")


def tables(conn):
    return [r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name")]


def overview(conn):
    print("=" * 78)
    print("資料庫概況")
    print("=" * 78)
    for name in tables(conn):
        n = conn.execute(f'SELECT COUNT(*) FROM "{name}"').fetchone()[0]
        cols = [r[1] for r in conn.execute(f'PRAGMA table_info("{name}")')]
        print(f"\n  {name}  —  {n} 列")
        print(f"    {', '.join(cols)}")
    print()
    print("  看某一晚：   python db_show.py 2026-09-08")
    print("  看整張表：   python db_show.py --table nightly_behavior")


def show_date(conn, date, show_user_id):
    print("=" * 78)
    print(f"{date}")
    print("=" * 78)
    found = False
    for name in tables(conn):
        if name not in DATE_TABLES:
            continue
        cols = [r[1] for r in conn.execute(f'PRAGMA table_info("{name}")')]
        if "date" not in cols:
            continue
        rows = conn.execute(
            f'SELECT * FROM "{name}" WHERE date = ?', (date,)).fetchall()
        if not rows:
            continue
        found = True
        for r in rows:
            print(f"\n【{name}】")
            print_row(r, show_user_id)
    if not found:
        print(f"\n  這個日期在任何表裡都沒有資料。")
        print(f"  有資料的日期：")
        for name in DATE_TABLES:
            if name not in tables(conn):
                continue
            ds = [r[0] for r in conn.execute(
                f'SELECT DISTINCT date FROM "{name}" ORDER BY date DESC LIMIT 6')]
            if ds:
                print(f"    {name}: {', '.join(ds)} …")


def show_table(conn, name, limit, show_user_id):
    if name not in tables(conn):
        sys.exit(f"✗ 沒有這張表：{name}\n   有的是：{', '.join(tables(conn))}")
    rows = conn.execute(f'SELECT * FROM "{name}" LIMIT {int(limit)}').fetchall()
    print("=" * 78)
    print(f"{name}（最多 {limit} 列）")
    print("=" * 78)
    for r in rows:
        print()
        print_row(r, show_user_id)
    if not rows:
        print("\n  （這張表是空的）")


def run_sql(conn, sql, show_user_id):
    low = sql.strip().lower()
    if not low.startswith(("select", "with", "pragma", "explain")):
        # mode=ro 本來就會擋，這一層只是給比較清楚的訊息。
        sys.exit("✗ 只接受 SELECT / WITH / PRAGMA / EXPLAIN。\n"
                 "   （就算硬送別的，資料庫也是唯讀開啟的，寫不進去。）")
    try:
        rows = conn.execute(sql).fetchall()
    except sqlite3.Error as exc:
        sys.exit(f"✗ SQL 錯誤：{exc}")
    # ⚠️ 與 shell 共用同一個印表函式。兩份各自實作的話，遮蔽 user_id 的
    #    邏輯會有兩個定義處，改一邊忘另一邊不會有任何錯誤訊息。
    _print_rows(rows, show_user_id)


SHELL_HELP = """  可以直接打 SQL，分號結尾（可以跨行）：
      SELECT date, sleep_efficiency FROM nightly_behavior
      ORDER BY date DESC;

  點指令：
      .tables            有哪些表
      .schema <表名>     那張表的欄位
      .dates             每張表最新的幾個日期
      .help              這段
      .quit / Ctrl+C     離開
"""


def shell(conn, show_user_id):
    """互動式 SQL。**唯讀**——連線本身是 mode=ro 開的。

    ⚠️ 沒有裝任何東西：Windows 沒有內建 sqlite3 CLI，而為了查資料去裝
       一個會**可寫**開啟資料庫的 GUI，風險比這支高（後端正在服務同一個
       檔案，寫入端多一個就多一種弄壞的方式）。
    """
    print("唯讀 SQL。輸入 .help 看說明，.quit 離開。")
    print()
    buf = []
    while True:
        try:
            line = input("sql> " if not buf else "  ..> ")
        except (EOFError, KeyboardInterrupt):
            print()
            return

        stripped = line.strip()
        if not buf and stripped.startswith("."):
            cmd, _, arg = stripped.partition(" ")
            arg = arg.strip()
            if cmd in (".quit", ".exit", ".q"):
                return
            if cmd == ".help":
                print(SHELL_HELP)
            elif cmd == ".tables":
                for n in tables(conn):
                    cnt = conn.execute(f'SELECT COUNT(*) FROM "{n}"').fetchone()[0]
                    print(f"  {n:24s} {cnt:>6} 列")
            elif cmd == ".schema":
                names = [arg] if arg else tables(conn)
                for n in names:
                    if n not in tables(conn):
                        print(f"  沒有這張表：{n}")
                        continue
                    print(f"\n  {n}")
                    for r in conn.execute(f'PRAGMA table_info("{n}")'):
                        print(f"    {r[1]:24s} {r[2]}")
            elif cmd == ".dates":
                for n in DATE_TABLES:
                    if n not in tables(conn):
                        continue
                    ds = [r[0] for r in conn.execute(
                        f'SELECT DISTINCT date FROM "{n}" '
                        f'ORDER BY date DESC LIMIT 5')]
                    print(f"  {n:24s} {', '.join(ds) if ds else '（空的）'}")
            else:
                print(f"  不認識的指令 {cmd}，看 .help")
            print()
            continue

        if not stripped and not buf:
            continue
        buf.append(line)
        if not stripped.endswith(";"):
            continue

        sql = "\n".join(buf).strip().rstrip(";")
        buf = []
        low = sql.lstrip().lower()
        if not low.startswith(("select", "with", "pragma", "explain")):
            # ⚠️ 真正的保證是連線的 mode=ro，這層只是給比較清楚的訊息。
            print("  ✗ 只接受 SELECT / WITH / PRAGMA / EXPLAIN。")
            print("    （就算硬送，資料庫也是唯讀開啟的，寫不進去。）")
            print()
            continue
        try:
            rows = conn.execute(sql).fetchall()
        except sqlite3.Error as exc:
            print(f"  ✗ {exc}")
            print()
            continue
        print()
        _print_rows(rows, show_user_id)
        print()


def _print_rows(rows, show_user_id):
    if not rows:
        print("  （沒有符合的列）")
        return
    keys = rows[0].keys()
    widths = {k: max(len(str(k)), *(len(str(mask(k, r[k], show_user_id)))
                                    for r in rows)) for k in keys}
    print("  " + "  ".join(str(k).ljust(widths[k]) for k in keys))
    print("  " + "  ".join("-" * widths[k] for k in keys))
    for r in rows:
        print("  " + "  ".join(
            str(mask(k, r[k], show_user_id)).ljust(widths[k]) for k in keys))
    print(f"\n  {len(rows)} 列")


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("date", nargs="?", help="看某一晚（YYYY-MM-DD）")
    ap.add_argument("--db", default=str(DEFAULT_DB),
                    help=f"SQLite 檔（預設 {DEFAULT_DB}）")
    ap.add_argument("--table", help="印出整張表")
    ap.add_argument("--limit", type=int, default=50, help="--table 最多印幾列")
    ap.add_argument("--sql", help="自己下 SELECT")
    ap.add_argument("--shell", action="store_true",
                    help="互動式 SQL（唯讀）。不用裝任何東西")
    ap.add_argument("--show-user-id", action="store_true",
                    help="⚠️ 印出完整 user_id。它是憑證，不要貼到會外流的地方")
    args = ap.parse_args()

    conn = connect(args.db)
    print(f"（{args.db}，唯讀）\n")
    if args.shell:
        shell(conn, args.show_user_id)
    elif args.sql:
        run_sql(conn, args.sql, args.show_user_id)
    elif args.table:
        show_table(conn, args.table, args.limit, args.show_user_id)
    elif args.date:
        show_date(conn, args.date, args.show_user_id)
    else:
        overview(conn)


if __name__ == "__main__":
    main()
