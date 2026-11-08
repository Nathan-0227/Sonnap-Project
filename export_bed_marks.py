"""
export_bed_marks.py —— 把每晚的「開始／結束睡覺」按鈕匯出成檔案，給評分 pipeline 讀。

    python export_bed_marks.py          # 要讀 MariaDB 就先設 SONNAP_DB_URL

輸出：garmin/data/bed_marks.json
morning_import.py 在跑評分 pipeline 之前會自動呼叫一次。

═══════════════════════════════════════════════════════════════════
為什麼是檔案、不是讓 pipeline 直接查資料庫（2026-11-07 使用者決定）
═══════════════════════════════════════════════════════════════════
garmin/ 的 pipeline 從頭到尾只讀檔案、不碰資料庫——任何一個 worktree、
任何一台沒開 MariaDB 的電腦都跑得出同一份分數。睡眠效率 11-07 恢復計分
之後需要按鈕資料，把它先匯出成檔案，pipeline 才能維持這個性質。

⚠️ 只匯出**按鈕本身**（上床、下床、臥床分鐘數），不匯出算好的效率：
   效率的分子是手錶的總睡眠，而那一晚的手錶資料要等 pipeline 跑完才進資料庫。
   在這裡算的話，最新那一晚永遠是用前一天的資料（或沒有）。
⚠️ 帳號用 db.resolve_phone_account()——與手錶、攝影機匯入同一個判準。
⚠️ 檔案裡**沒有 user_id**（那是憑證），也沒有匯出時刻（內容沒變時檔案就不變，
   git 才不會每天多一筆假的修改）。
"""
import json
import os
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import db

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "garmin" / "data" / "bed_marks.json"


def collect(db_path=None):
    """{起床日: {bed_start_at, bed_end_at, time_in_bed_minutes}}，只收有按 Start sleep 的夜晚。"""
    user_id, _info = db.resolve_phone_account(db_path)
    if not user_id:
        return None
    nights = {}
    for r in db.get_nightly_behavior(user_id, days=3650, db_path=db_path):
        if not r.get("bed_start_at"):
            continue
        nights[r["date"]] = {
            "bed_start_at": r["bed_start_at"],
            "bed_end_at": r.get("bed_end_at"),
            "time_in_bed_minutes": r.get("time_in_bed_minutes"),
        }
    return dict(sorted(nights.items()))


def export(out=OUT, db_path=None):
    """寫檔並回傳匯出的晚數；分不出手機帳號時回 None（不寫檔）。"""
    nights = collect(db_path)
    if nights is None:
        return None
    payload = {
        "note": ("Start sleep / Out of bed marks of the phone account, exported for "
                 "garmin/evaluate_sleep_quality.py. Sleep efficiency is scored from "
                 "these when available (see behavior/sleep_efficiency.scoring_efficiency)."),
        "nights": nights,
    }
    Path(out).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
                         encoding="utf-8")
    return len(nights)


def main():
    if os.environ.get("SONNAP_DB_URL"):
        print("● 資料庫   MySQL/MariaDB（由 SONNAP_DB_URL 指定，內容不印）")
    else:
        print(f"● 資料庫   {db.DB_PATH}（SQLite）")
    n = export()
    if n is None:
        print("✗ 分不出手機帳號（db.resolve_phone_account），沒有匯出。"
              "評分會把每晚都退回手錶自己的效率。")
        return 1
    print(f"✓ 匯出 {n} 晚的按鈕紀錄 → {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
