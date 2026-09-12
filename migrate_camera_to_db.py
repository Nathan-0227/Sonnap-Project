"""
migrate_camera_to_db.py — 把整夜錄影算出的臥床時間與入睡潛伏期寫進資料庫。

    tapo_metrics/<那一晚>.csv ──(tapo_sleep_onset.analyse)──▶ camera_nightly
                                                                   │
                                                   GET /insights ──┘ → App 顯示

═══════════════════════════════════════════════════════════════════
⚠️ user_id 不寫進這支程式，也不寫進任何檔案
═══════════════════════════════════════════════════════════════════
`user_id` 在這個專案裡**本身就是憑證**（免註冊、無密碼），所以它不能出現在
程式碼、設定檔、shell 歷史或 log 裡。這支腳本改成**執行時從資料庫查**——
那個 id 本來就存在那裡，查出來用完就丟，不會多一份副本。

判準：挑 `nightly_behavior` 列數最多的那個使用者（也就是手機一直在上傳的
那個帳號）。分不出來時**停下來請人指定**，不要猜——猜錯會把攝影機資料掛到
別人的帳號上，而且畫面上看起來完全正常。

⚠️ 印出來的一律是遮罩過的前 8 碼（與 `db_show.py` 同一個作法）。

═══════════════════════════════════════════════════════════════════
⚠️ 這張表不含任何分數，也不要加
═══════════════════════════════════════════════════════════════════
`Research-Background/攝影機分數.md` 的結論是「現行有效的攝影機計分項目：0 項」。
這支腳本只搬**量測值與來源標籤**。要計分就得先過那份文件 F 節的五道關卡，
否則就是第五代沒有引文的攝影機公式（設計紅線 2）。

用法：

    python migrate_camera_to_db.py --dry-run      # 先看會寫什麼，不寫入
    python migrate_camera_to_db.py                # 寫入
    python migrate_camera_to_db.py --csv tapo_metrics/20260912_011758.csv
"""
import argparse
import re
import sys
from datetime import datetime
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).parent
sys.path.insert(0, str(ROOT))

import db                                  # noqa: E402
import tapo_sleep_onset as onset           # noqa: E402
from behavior import adherence             # noqa: E402

# 只有「YYYYMMDD_HHMMSS…」這種檔名才是錄影。其餘（clip_measure.csv 之類的
# 工具檔）連 `t` 欄位都沒有。
RECORDING_NAME = re.compile(r"^\d{8}_\d{6}")

# 這些不是「一晚」：自測、人工標註的對照檔、網路狀態記錄。
SKIP_MARKERS = ("_selftest", "_truth", "_waso", "_netwatch", "unblinded")

# 比這還短的錄影不是一晚。實測 09-09 只錄到 17.9 分鐘（熱點掉了），
# 那種資料算出來的「臥床時間」會是錯的，而且錯得很合理。
MIN_NIGHT_MINUTES = 120


def mask(user_id):
    """user_id 是憑證，只印前 8 碼。"""
    return f"{user_id[:8]}…"


def resolve_user(db_path=None):
    """從資料庫挑出「手機一直在上傳的那個帳號」。回 (user_id, 診斷文字)。"""
    conn = db.connect(db_path)
    try:
        rows = conn.execute(
            """
            SELECT u.user_id AS user_id, COUNT(n.date) AS nights
            FROM users u
            LEFT JOIN nightly_behavior n ON n.user_id = u.user_id
            GROUP BY u.user_id
            ORDER BY nights DESC
            """
        ).fetchall()
    finally:
        conn.close()

    if not rows:
        sys.exit("✗ 資料庫裡沒有任何使用者。先用手機建帳號（或跑 "
                 "migrate_garmin_to_db.py）再來。")

    counts = [(r["user_id"], r["nights"]) for r in rows]
    best, best_n = counts[0]
    if best_n == 0:
        sys.exit("\n".join([
            "✗ 每個帳號都還沒有任何 nightly_behavior 資料，分不出哪個是手機在用的。",
            "   先讓手機上傳一晚，或用 --user-id 指定。",
            "   現有帳號（遮罩）：" + ", ".join(mask(u) for u, _ in counts),
        ]))
    tied = [u for u, n in counts if n == best_n]
    if len(tied) > 1:
        sys.exit("\n".join([
            f"✗ 有 {len(tied)} 個帳號的夜數一樣多（各 {best_n} 晚），我不猜。",
            "   用 --user-id 指定一個：" + ", ".join(mask(u) for u in tied),
        ]))
    return best, f"{mask(best)}（{best_n} 晚行為資料，共 {len(counts)} 個帳號）"


def nights(metrics_dir, explicit):
    """要處理的 CSV 清單。

    ⚠️ 用**檔名格式**當判準，不是用排除清單。`tapo_metrics/` 裡還有
       `clip_measure.csv`、`clip_truth.csv` 這種根本沒有 `t` 欄位的工具檔——
       排除清單總有漏的，而「檔名是 YYYYMMDD_HHMMSS」這個條件只會放進
       真正的錄影。（2026-09-12 實測：漏掉那兩個檔會讓整批 KeyError 中斷。）
    """
    if explicit:
        return [Path(p) for p in explicit]
    out = []
    for p in sorted(Path(metrics_dir).glob("*.csv")):
        if any(m in p.name for m in SKIP_MARKERS):
            continue
        if not RECORDING_NAME.match(p.name):
            continue
        out.append(p)
    return out


def main():
    ap = argparse.ArgumentParser(description="錄影 → camera_nightly（不評分）")
    ap.add_argument("--metrics-dir", default=str(ROOT / "tapo_metrics"))
    ap.add_argument("--csv", action="append", help="只處理這些檔（可重複）")
    ap.add_argument("--dry-run", action="store_true", help="只看不寫")
    ap.add_argument("--user-id", help="⚠️ 指定帳號。**會進 shell 歷史**，"
                                     "只在自動判準分不出來時才用")
    ap.add_argument("--db-path", help="覆寫資料庫位置（預設看 SONNAP_DB）")
    args = ap.parse_args()

    if args.user_id:
        user_id, who = args.user_id, f"{mask(args.user_id)}（由 --user-id 指定）"
    else:
        user_id, who = resolve_user(args.db_path)
    print(f"● 寫入帳號 {who}")
    print(f"● 資料庫   {args.db_path or db.DB_PATH}")
    if args.dry_run:
        print("● --dry-run：不會寫入任何東西")
    print()

    csvs = nights(args.metrics_dir, args.csv)
    if not csvs:
        sys.exit(f"✗ {args.metrics_dir} 裡沒有可用的 CSV")

    header = f"{'夜晚':<12}{'臥床(分)':>9}{'入睡潛伏期':>12}{'次/小時':>9}  來源檔"
    print(header)
    print("-" * len(header))
    written = skipped = 0
    for path in csvs:
        # ⚠️ 一份壞掉不能讓整批停擺——剩下的夜晚照樣要寫進去。
        try:
            r = onset.analyse(path)
        except Exception as exc:                       # noqa: BLE001
            print(f"{'—':<12}{'':>9}{'':>12}{'':>9}  {path.name}  "
                  f"⚠ 讀不下去：{type(exc).__name__}")
            skipped += 1
            continue
        if r.get("error"):
            print(f"{'—':<12}{'':>9}{'':>12}{'':>9}  {path.name}  ⚠ {r['error']}")
            skipped += 1
            continue
        tib = r["time_in_bed_minutes"]
        if tib is None or tib < MIN_NIGHT_MINUTES:
            print(f"{'—':<12}{tib or 0:>9.0f}{'太短，不是一晚':>12}{'':>9}  {path.name}")
            skipped += 1
            continue

        date = adherence.night_date(
            datetime.fromisoformat(r["bed_start_at"])).isoformat()
        # ⚠️ 低於下限時印「≤ N」而不是數字，與 DB 裡存 NULL 的語意一致。
        if r["sleep_onset_below_floor"]:
            sol = f"≤ {r['sleep_onset_floor_minutes']:.0f} 分"
        elif r["sleep_onset_latency_minutes"] is None:
            sol = "偵測不到"
        else:
            sol = f"{r['sleep_onset_latency_minutes']:.0f} 分"
        rate = r["events_per_hour"]
        print(f"{date:<12}{tib:>9.0f}{sol:>12}{rate if rate is not None else 0:>9.1f}"
              f"  {path.name}")

        if not args.dry_run:
            db.upsert_camera_nightly(user_id, date, r, db_path=args.db_path)
            written += 1

    print()
    print(f"寫入 {written} 晚，跳過 {skipped} 份。")
    if args.dry_run:
        print("（--dry-run，實際沒有寫入）")
    else:
        print("⚠️ 這些數字是**呈現用**的，不進任何分數。"
              "臥床時間是自述（開始／結束錄影），入睡時刻的效標只驗過 2 晚。")


if __name__ == "__main__":
    main()
