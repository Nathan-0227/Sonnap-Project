"""
resolve_lights_out.py — 匯入手錶之後，用手錶當裁判重挑就寢時刻

    morning_import.py ④ 寫入
        migrate_garmin_to_db.py   手錶 → wearable_nightly
        resolve_lights_out.py     ← 就在這裡（要在手錶寫完之後）
        build_app_payload.py      打包檔（要在這之後才拿得到改正的值）

為什麼不在 `POST /nightly` 當下挑：那是**早上你開 App** 的時候，
手錶那一晚還沒進資料庫（要等這支流程跑），裁判不在場。

為什麼不在讀取時現算：`is_late` 現在有六、七處直接讀
（挑戰、熬夜比率、作息收斂、一週放下手機圖、XP），全部改走新函式的話
漏一處不會有任何錯誤訊息。存一份、一個寫入者。

⚠️ **可以重複執行。** 每次都從 `quiet_candidates` 重新挑，不是在上次改過的
值上再改一次。（App 重送同一晚時會把 `lights_out_at` 覆寫回手機挑的那個，
下一次早晨匯入會再挑一次——這是對的，不是漏洞。）

判準一律在 `behavior/lights_out_resolve.py`，這支只負責讀寫。
"""

import argparse
import json
import sys

sys.stdout.reconfigure(encoding="utf-8")

import db
from behavior import adherence, lights_out_resolve as resolver


def _load_candidates(raw):
    """`quiet_candidates` 欄位（JSON 字串）→ list。壞掉或沒有都回 None。

    ⚠️ **None 與 []（空陣列）是兩件事**：前者是「舊版 App，不知道」，
    後者是「確定只有一段」。壞掉的 JSON 當成不知道，不要當成空的——
    當成空的會讓那一晚被判成 unresolved。
    """
    if not raw:
        return None
    if isinstance(raw, list):
        return raw
    try:
        value = json.loads(raw)
    except (ValueError, TypeError):
        return None
    return value if isinstance(value, list) else None


def resolve_all(db_path=None, dry_run=False):
    """跑過每一晚，回傳 (檢查幾晚, 改了幾晚, 標成不知道幾晚)。"""
    conn = db.connect(db_path)
    try:
        rows = conn.execute(
            """
            SELECT b.user_id, b.date, b.target_bedtime, b.lights_out_at,
                   b.adherence_minutes, b.is_late, b.source,
                   b.quiet_candidates, b.lights_out_pick,
                   w.sleep_start_time
            FROM nightly_behavior b
            JOIN users u ON u.user_id = b.user_id
            LEFT JOIN wearable_nightly w
                   ON w.user_id = b.user_id AND w.date = b.date
            WHERE COALESCE(u.study_cohort, '') <> ?
            ORDER BY b.date
            """,
            (db.DEMO_COHORT,)
        ).fetchall()

        checked = changed = unresolved = 0
        # ⚠️ 示範帳號（成果展用）排除在外：它們的資料是腳本產生的，
        #    不是量測結果，拿手錶「校正」一組編出來的時刻沒有意義。
        for row in rows:
            onset = row["sleep_start_time"]
            if not onset or not row["lights_out_at"]:
                continue
            checked += 1

            candidates = _load_candidates(row["quiet_candidates"])
            new_at, pick = resolver.decide(
                row["lights_out_at"], candidates, onset)

            # 上一輪已經換成手錶挑的那一個時，decide 這次會回 'phone'
            # （因為資料庫裡存的就是它）。保留原本的標記，不然「誰挑的」
            # 會在第二次執行時悄悄變成手機挑的。
            if (pick == resolver.PICK_PHONE
                    and row["lights_out_pick"] == resolver.PICK_WATCH
                    and new_at == row["lights_out_at"]):
                pick = resolver.PICK_WATCH

            if pick == resolver.PICK_UNRESOLVED:
                # 時刻留著（那仍然是「最後一次碰手機」這個事實），
                # 說不出口的是「所以你熬夜了幾分鐘」。
                fields = {"adherence_minutes": None, "is_late": None}
                if row["is_late"] is not None or row["adherence_minutes"] is not None:
                    unresolved += 1
                    print(f"  ? {row['date']} 放下手機 {row['lights_out_at'][11:16]} "
                          f"晚於手錶入睡 {str(onset)[11:16]} 超過 "
                          f"{resolver.TOLERANCE_MINUTES} 分鐘，而且沒有可用的候選"
                          "——達成度改存「不知道」")
            elif pick == resolver.PICK_WATCH and new_at != row["lights_out_at"]:
                night = adherence.evaluate_night(
                    new_at, row["target_bedtime"], source=row["source"])
                fields = {
                    "lights_out_at": night["lights_out_at"],
                    "adherence_minutes": night["adherence_minutes"],
                    "is_late": night["is_late"],
                }
                changed += 1
                print(f"  ✓ {row['date']} {row['lights_out_at'][11:16]} → "
                      f"{night['lights_out_at'][11:16]}"
                      f"（手錶入睡 {str(onset)[11:16]}）；熬夜 "
                      f"{row['adherence_minutes']} → {night['adherence_minutes']} 分鐘")
            else:
                fields = {}

            if fields.get("lights_out_at") is None and pick == resolver.PICK_WATCH:
                fields.pop("lights_out_at", None)

            if not fields and pick == row["lights_out_pick"]:
                continue
            if dry_run:
                continue

            sets = ", ".join(f"{k} = ?" for k in fields)
            sets = (sets + ", " if sets else "") + "lights_out_pick = ?"
            params = list(fields.values()) + [
                pick, row["user_id"], row["date"]]
            conn.execute(
                f"UPDATE nightly_behavior SET {sets} "
                "WHERE user_id = ? AND date = ?", params)
        if not dry_run:
            conn.commit()
        return checked, changed, unresolved
    finally:
        conn.close()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true",
                    help="只印出會改哪幾晚，不寫資料庫")
    args = ap.parse_args(argv)

    checked, changed, unresolved = resolve_all(dry_run=args.dry_run)
    print(f"\n同時有手錶與放下手機時刻的夜晚：{checked}")
    print(f"  換成手錶挑的那一段：{changed}")
    print(f"  達成度改存「不知道」：{unresolved}")
    if args.dry_run:
        print("  （--dry-run：一列都沒寫）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
