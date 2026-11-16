"""
守「用手錶當裁判重挑就寢時刻」這整條路（2026-11-16）。

═══════════════════════════════════════════════════════════════════════
為什麼需要這支
═══════════════════════════════════════════════════════════════════════
手機端挑**最長**的那一段安靜期。半夜起來用幾分鐘手機會把一晚切成兩段，
而後面那段通常比較長——11-16 因此記成熬夜 98.6 分鐘，實際只晚 4.9 分鐘。
壞掉時**沒有任何錯誤訊息**：那一晚看起來完全正常，只是數字是錯的。

【1】用的是 11-16 的**真實事件流**（手機只保留約 24 小時，那份存在
sonnap-data/lights-out-evidence/，是唯一的證據）。

    python tests/test_lights_out_resolve.py
"""
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

os.environ.pop("SONNAP_DB_URL", None)

import db  # noqa: E402
import resolve_lights_out  # noqa: E402
from behavior import lights_out_resolve as r  # noqa: E402

failures = []


def check(name, ok, detail=""):
    print(f"{'✅' if ok else '❌'} {name}" + (f"  ({detail})" if detail else ""))
    if not ok:
        failures.append(name)


# ── 11-16 的真實數字（見 docs/DEVLOG.md 2026-11-16 那則）──────────────
TRUE_AT = "2026-11-16T00:49:54"      # 真正放下手機（安靜 88.4 分鐘）
WRONG_AT = "2026-11-16T02:23:37"     # 手機挑的（安靜 218.8 分鐘，比較長）
ONSET = "2026-11-16T00:56:00+08:00"  # 手錶認定入睡
CANDS = [
    {"at": TRUE_AT, "quiet_minutes": 88, "source_type": "keyguard_shown",
     "bridged_unlocks": 0},
    {"at": WRONG_AT, "quiet_minutes": 218, "source_type": "keyguard_shown",
     "bridged_unlocks": 0},
]

# 【1】真實那一晚：要挑回 00:49，不是 02:23
at, pick = r.decide(WRONG_AT, CANDS, ONSET)
check("【1】11-16 真實資料：挑回 00:49（不是最長的 02:23）",
      (at, pick) == (TRUE_AT, r.PICK_WATCH), f"got={at} {pick}")

# 【1b】⚠️ 反向對照：把裁判拿掉（沒有手錶）就必須退回手機挑的那個。
#      少了這條，「永遠挑最早的候選」這種壞規則也會讓【1】通過。
at, pick = r.decide(WRONG_AT, CANDS, None)
check("【1b】反向對照：沒有手錶 → 原樣不動（不是挑最早的）",
      (at, pick) == (WRONG_AT, r.PICK_PHONE), f"got={at} {pick}")

# 【2】挑**最晚**的那一段，不是最早的：睡前 5 秒看鬧鐘也會產生一段安靜期，
#     挑最早的會讓就寢時刻往前移（同第 4 條規則「挑跨最少次」的理由）。
three = [{"at": "2026-11-16T00:10:00"}, {"at": TRUE_AT}, {"at": WRONG_AT}]
at, pick = r.decide(WRONG_AT, three, ONSET)
check("【2】過關的有好幾段時挑最晚的那一段", at == TRUE_AT, f"got={at}")

# 【3】沒有候選（舊版 App、歷史夜晚）→ 只檢查、修不了
at, pick = r.decide(WRONG_AT, None, ONSET)
check("【3】沒有候選 → unresolved（時刻留著，達成度由呼叫端存 NULL）",
      (at, pick) == (WRONG_AT, r.PICK_UNRESOLVED), f"got={at} {pick}")
at, pick = r.decide(TRUE_AT, None, ONSET)
check("【3b】沒有候選但時刻本來就合理 → 不動它",
      (at, pick) == (TRUE_AT, r.PICK_PHONE), f"got={at} {pick}")

# 【4】容差 30 分鐘**刻意**放過「滑手機滑到睡著」那個不同的現象
#     （使用者 10-22 已決定改用 USER_INTERACTION 解，不要被這條順手改掉）。
at, pick = r.decide("2026-11-16T01:08:00", None, ONSET)
check("【4】晚於入睡 12 分鐘（滑到睡著）→ 不判成 unresolved",
      pick == r.PICK_PHONE, f"got={pick}")
check("【4b】容差是 30 分鐘", r.TOLERANCE_MINUTES == 30)

# 【5】挑中的候選落在**別的夜晚**就不換（上床按鈕靠日期配對）
evening = [{"at": "2026-11-15T17:00:00"}]
at, pick = r.decide(WRONG_AT, evening, ONSET)
check("【5】候選落在別的夜晚 → 不換", (at, pick) == (WRONG_AT, r.PICK_PHONE),
      f"got={at} {pick}")

# 【6】一段都沒過關 → unresolved
at, pick = r.decide(WRONG_AT, [{"at": WRONG_AT}], ONSET)
check("【6】一段都沒過關 → unresolved", pick == r.PICK_UNRESOLVED, f"got={pick}")

# 【7】時刻一律當**牆鐘**讀：手錶帶 +08:00、手機不帶，換算 UTC 會差 8 小時
at, pick = r.decide(TRUE_AT, CANDS, "2026-11-16T00:56:00+08:00")
at2, pick2 = r.decide(TRUE_AT, CANDS, "2026-11-16T00:56:00")
check("【7】⚠️ 帶不帶 +08:00 結果要一樣（不可換算 UTC）",
      (at, pick) == (at2, pick2), f"{at} {pick} vs {at2} {pick2}")

# ── 【8】整條路：寫進資料庫、跑腳本、看結果 ──────────────────────────
with tempfile.TemporaryDirectory() as tmp:
    path = os.path.join(tmp, "t.db")
    db.init_db(path)
    uid = db.create_user("測試員", db_path=path)
    import json

    db.upsert_nightly_behavior(uid, "2026-11-16", "00:45", WRONG_AT,
                               98.6, True, db_path=path,
                               quiet_candidates=json.dumps(CANDS),
                               lights_out_pick=r.PICK_PHONE)
    db.upsert_wearable_nightly(uid, "2026-11-16", "garmin",
                               {"sleep_start_time": ONSET}, db_path=path)

    def row():
        conn = db.connect(path)
        try:
            return dict(conn.execute(
                "SELECT lights_out_at, adherence_minutes, is_late, lights_out_pick "
                "FROM nightly_behavior WHERE user_id = ? AND date = ?",
                (uid, "2026-11-16")).fetchone())
        finally:
            conn.close()

    checked, changed, unresolved = resolve_lights_out.resolve_all(
        db_path=path, dry_run=True)
    after_dry = row()
    check("【8a】--dry-run 一列都沒改",
          after_dry["lights_out_at"] == WRONG_AT and changed == 1,
          f"changed={changed}")

    resolve_lights_out.resolve_all(db_path=path)
    got = row()
    check("【8b】跑完之後存的是 00:49，熬夜 4.9 分鐘、不算熬夜",
          (got["lights_out_at"], got["adherence_minutes"], got["is_late"])
          == (TRUE_AT, 4.9, 0), f"got={got}")
    check("【8c】記下是手錶挑的", got["lights_out_pick"] == r.PICK_WATCH,
          f"got={got['lights_out_pick']}")

    # 【8d】⚠️ 可以重複執行：第二次不能把「手錶挑的」悄悄變回「手機挑的」，
    #      也不能在改過的值上再改一次。
    resolve_lights_out.resolve_all(db_path=path)
    again = row()
    check("【8d】⚠️ 再跑一次結果一模一樣（可重複執行）", again == got,
          f"{again} vs {got}")

    # 【9】沒有候選的歷史夜晚：達成度改存 NULL，時刻留著
    db.upsert_nightly_behavior(uid, "2026-09-24", "03:00",
                               "2026-09-24T04:37:00", 97.0, True, db_path=path)
    db.upsert_wearable_nightly(uid, "2026-09-24", "garmin",
                               {"sleep_start_time": "2026-09-24T00:09:00+08:00"},
                               db_path=path)
    resolve_lights_out.resolve_all(db_path=path)
    conn = db.connect(path)
    try:
        old = dict(conn.execute(
            "SELECT lights_out_at, adherence_minutes, is_late, lights_out_pick "
            "FROM nightly_behavior WHERE user_id = ? AND date = ?",
            (uid, "2026-09-24")).fetchone())
    finally:
        conn.close()
    check("【9】救不回來的歷史夜晚：達成度存 NULL（不是繼續說熬夜 97 分鐘）",
          old["adherence_minutes"] is None and old["is_late"] is None,
          f"got={old}")
    check("【9b】但時刻留著——那仍然是「最後一次碰手機」這個事實",
          old["lights_out_at"] == "2026-09-24T04:37:00", f"got={old}")

if failures:
    print(f"\n❌ {len(failures)} 條沒過")
    sys.exit(1)
print("\n✅ 全部通過")
