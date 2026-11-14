"""
守「每一晚的 is_late 有三種狀態，『沒判』不能被存成『準時』」。

═══════════════════════════════════════════════════════════════════════
為什麼需要這支
═══════════════════════════════════════════════════════════════════════
`db.upsert_nightly_behavior` 原本寫 `1 if is_late else 0`，None（沒判）會被
存成 0＝準時。壞掉時沒有任何錯誤訊息：那一晚就安靜地被算進準時挑戰與
熬夜比率的分母，數字看起來比實際好。2026-11-15 在本人帳號的 11-07 實際中過
（手動補了放下手機的時刻但沒有達成度）。

App 正常上傳不會遇到（後端拒收沒有 lights_out_at 的上傳），所以只有這支測試
看得到它。用暫存 SQLite，不碰任何真的資料庫。

    python tests/test_nightly_is_late.py
"""
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

# 不讓開發機上剛好設了 MariaDB 的環境變數把測試導去真的資料庫
os.environ.pop("SONNAP_DB_URL", None)

import db  # noqa: E402
from behavior import adherence  # noqa: E402

failures = []


def check(name, ok, detail=""):
    print(f"{'✅' if ok else '❌'} {name}" + (f"  ({detail})" if detail else ""))
    if not ok:
        failures.append(name)


def raw_is_late(path, uid, date):
    conn = db.connect(path)
    try:
        row = conn.execute(
            "SELECT is_late FROM nightly_behavior WHERE user_id = ? AND date = ?",
            (uid, date),
        ).fetchone()
        return row[0]
    finally:
        conn.close()


with tempfile.TemporaryDirectory() as tmp:
    path = os.path.join(tmp, "t.db")
    db.init_db(path)
    uid = db.create_user("測試員", db_path=path)

    # 【1】三種狀態各寫一晚，資料庫裡要分得開
    db.upsert_nightly_behavior(uid, "2026-11-05", "03:00",
                               "2026-11-05T04:00:00", 60.0, True, db_path=path)
    db.upsert_nightly_behavior(uid, "2026-11-06", "03:00",
                               "2026-11-06T03:10:00", 10.0, False, db_path=path)
    db.upsert_nightly_behavior(uid, "2026-11-07", "03:00",
                               "2026-11-07T02:00:00", None, None, db_path=path)
    check("【1a】熬夜存成 1", raw_is_late(path, uid, "2026-11-05") == 1)
    check("【1b】準時存成 0（反向對照：不能全部變成 NULL）",
          raw_is_late(path, uid, "2026-11-06") == 0)
    got = raw_is_late(path, uid, "2026-11-07")
    check("【1c】⚠️ 沒判存成 NULL，不是 0（準時）", got is None, f"got={got!r}")

    # 【2】覆寫同一晚：原本判過，改成沒判 → 也要變回 NULL（走 ON CONFLICT 那條路）
    db.upsert_nightly_behavior(uid, "2026-11-06", "03:00",
                               "2026-11-06T03:10:00", None, None, db_path=path)
    got = raw_is_late(path, uid, "2026-11-06")
    check("【2】覆寫成沒判 → NULL", got is None, f"got={got!r}")

    # 【3】下游：熬夜比率的分母只算有判的晚上
    rows = db.get_nightly_behavior(uid, days=400, db_path=path)
    _, late, recorded = adherence.late_night_ratio(rows)
    check("【3】沒判的晚上不進熬夜比率的分母",
          (late, recorded) == (1, 1), f"late={late} recorded={recorded}")

if failures:
    print(f"\n❌ {len(failures)} 條沒過")
    sys.exit(1)
print("\n✅ 全部通過")
