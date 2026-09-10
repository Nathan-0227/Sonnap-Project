"""
把 SQLite 的資料搬進 MySQL/MariaDB —— 可重複執行。

    python migrate_sqlite_to_mysql.py \
        --sqlite C:/Users/user/Projects/sonnap-data/sonnap.db \
        --url mysql://root@127.0.0.1:3306/sonnap

    python migrate_sqlite_to_mysql.py ... --apply     # 沒有 --apply 就只是預演

═══════════════════════════════════════════════════════════════════════
⚠️ 預設是**預演**（dry-run）
═══════════════════════════════════════════════════════════════════════
不加 `--apply` 只印出「會搬幾列、會覆蓋幾列」，一個字都不寫。
搬資料是少數幾件「做錯了很難復原」的事之一，值得多打一個參數。

⚠️ **搬的是欄位的交集。** 兩邊的結構由 `db_backend.mysql_ddl()` 從同一份
   SCHEMA 產生，理論上一致；但如果不一致，這支會**明講少了哪些欄位**
   而不是安靜地漏掉。安靜地漏一欄，正是這個專案最怕的那種失敗。

⚠️ **不動 `sleep_records`。** 那是影像組的表，不在 SCHEMA 裡，
   這支只搬 SCHEMA 認得的表。
"""
import argparse
import sqlite3
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).parent
sys.path.insert(0, str(ROOT))

import db          # noqa: E402
import db_backend  # noqa: E402

# 父表要先搬，否則外鍵擋下來。順序沿用 SCHEMA。
ORDER = ["users", "challenges", "nightly_behavior", "wearable_nightly",
         "app_usage_daily", "block_events", "challenge_progress"]


def sqlite_tables(conn):
    return {r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'")}


def sqlite_columns(conn, table):
    return [r[1] for r in conn.execute(f'PRAGMA table_info("{table}")')]


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sqlite", required=True, help="來源 .db")
    ap.add_argument("--url", required=True,
                    help="目標，例如 mysql://root@127.0.0.1:3306/sonnap")
    ap.add_argument("--apply", action="store_true",
                    help="真的寫入。不加就只是預演")
    args = ap.parse_args()

    src_path = Path(args.sqlite)
    if not src_path.exists():
        sys.exit(f"✗ 找不到 {src_path}")
    cfg = db_backend.mysql_config(args.url)
    if not cfg:
        sys.exit(f"✗ --url 不是 mysql:// 開頭：{args.url}")

    # 來源唯讀開啟——搬家的時候不該有任何機會改到來源。
    src = sqlite3.connect(f"file:{src_path.as_posix()}?mode=ro", uri=True)
    src.row_factory = sqlite3.Row
    dst = db_backend.MySQLConn(cfg)

    print("=" * 74)
    print(f"{'預演（不寫入）' if not args.apply else '⚠️ 實際寫入'}")
    print(f"  來源  {src_path}")
    print(f"  目標  {cfg['user']}@{cfg['host']}:{cfg['port']}/{cfg['database']}")
    print("=" * 74)
    print()

    have = sqlite_tables(src)
    total = 0
    problems = []
    for table in ORDER:
        if table not in have:
            print(f"  {table:22s} 來源沒有這張表，跳過")
            continue
        src_cols = sqlite_columns(src, table)
        dst_cols = db.existing_columns(dst, table)
        if not dst_cols:
            problems.append(f"{table}：目標沒有這張表（先跑 python db.py --init）")
            print(f"  {table:22s} ✗ 目標沒有這張表")
            continue

        # ⚠️ 用交集，但**把差集印出來**。安靜地少搬一欄是最難查的。
        cols = [c for c in src_cols if c in dst_cols]
        missing = [c for c in src_cols if c not in dst_cols]
        rows = src.execute(f'SELECT * FROM "{table}"').fetchall()
        exists = dst.execute(f"SELECT COUNT(*) AS n FROM `{table}`").fetchone()[0]

        note = ""
        if missing:
            note = f"  ⚠️ 目標少了欄位：{', '.join(missing)}"
            problems.append(f"{table}：目標少了 {', '.join(missing)}")
        print(f"  {table:22s} 來源 {len(rows):>4} 列 → 目標現有 {exists:>4} 列{note}")

        if not args.apply or not rows:
            total += len(rows)
            continue

        placeholders = ", ".join(["?"] * len(cols))
        collist = ", ".join(f"`{c}`" for c in cols)
        updates = ", ".join(f"`{c}` = VALUES(`{c}`)" for c in cols)
        sql = (f"INSERT INTO `{table}` ({collist}) VALUES ({placeholders}) "
               f"ON DUPLICATE KEY UPDATE {updates}")
        for r in rows:
            dst.execute(sql, tuple(r[c] for c in cols))
        total += len(rows)

    if args.apply:
        dst.commit()
        print()
        print(f"✓ 寫入完成，共處理 {total} 列")
    else:
        print()
        print(f"（預演）會處理 {total} 列。確認無誤後加 --apply")

    if problems:
        print()
        print("⚠️ 有問題要看一下：")
        for p in problems:
            print(f"   - {p}")

    src.close()
    dst.close()
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
