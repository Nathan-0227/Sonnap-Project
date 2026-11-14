"""
tests/test_bridged_unlocks.py

就寢偵測第 4 條規則的標記（2026-11-15）：App 偵測某一晚時跨過了幾次半夜的短解鎖，
`POST /nightly` 收 `bridged_unlocks`，存進 nightly_behavior。

守的是**壞掉時不會報錯**的地方：

  【1】有送 → 照存（1 就是 1）
  【2】沒送（舊版 App）→ 存 NULL，**不是 0**——「沒跨」與「不知道」要分得開
  【3】送 0 → 存 0（反向對照：不能全部變成 NULL）
  【4】負數 → 422，不寫進去
  【5】已經跑過 --init 的舊資料庫（沒有這一欄）→ 遷移補上欄位，舊資料是 NULL

⚠️ 用暫存資料庫，不會碰到真的資料庫。

執行：python tests/test_bridged_unlocks.py
"""
import os
import sqlite3
import sys
import tempfile
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
os.environ.pop("SONNAP_DB_URL", None)

# ⚠️ 一定要在 import main 之前換掉 DB_PATH，否則測試會寫到真的資料庫
import db  # noqa: E402

TMP = Path(tempfile.mkdtemp()) / "test.db"
db.DB_PATH = TMP

import main  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

fails = []


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<56} {extra}")
    if not cond:
        fails.append(label)


def stored(uid, date, path=TMP):
    conn = db.connect(path)
    try:
        row = conn.execute(
            "SELECT bridged_unlocks FROM nightly_behavior WHERE user_id = ? AND date = ?",
            (uid, date),
        ).fetchone()
        return "missing" if row is None else row[0]
    finally:
        conn.close()


db.init_db(TMP)
client = TestClient(main.app)
uid = client.post(
    "/users", json={"display_name": "bridged-guard", "target_bedtime": "04:00"}
).json()["user_id"]


def post(lights_out, **extra):
    return client.post(
        "/nightly", json={"user_id": uid, "lights_out_at": lights_out, **extra}
    )


r = post("2026-11-12T05:43:10", bridged_unlocks=1)
ok("【1】送 1 → 201", r.status_code == 201, str(r.status_code))
ok("【1】存 1", stored(uid, "2026-11-12") == 1, repr(stored(uid, "2026-11-12")))

r = post("2026-11-13T03:03:22")
ok("【2】沒送 → 201", r.status_code == 201, str(r.status_code))
got = stored(uid, "2026-11-13")
ok("【2】⚠️ 沒送存 NULL，不是 0", got is None, repr(got))

r = post("2026-11-14T03:26:54", bridged_unlocks=0)
ok("【3】送 0 → 存 0（不能全部變成 NULL）", stored(uid, "2026-11-14") == 0,
   repr(stored(uid, "2026-11-14")))

r = post("2026-11-11T04:33:41", bridged_unlocks=-1)
ok("【4】負數 → 422", r.status_code == 422, str(r.status_code))
ok("【4】負數不寫進去", stored(uid, "2026-11-11") == "missing",
   repr(stored(uid, "2026-11-11")))

# 【5】舊資料庫：先建一張沒有 bridged_unlocks 的 nightly_behavior，再跑 init_db
OLD = Path(tempfile.mkdtemp()) / "old.db"
conn = sqlite3.connect(OLD)
conn.execute(
    "CREATE TABLE nightly_behavior (user_id TEXT, date TEXT, lights_out_at TEXT, "
    "PRIMARY KEY (user_id, date))"
)
conn.execute(
    "INSERT INTO nightly_behavior VALUES ('u', '2026-11-01', '2026-11-01T03:00:00')"
)
conn.commit()
conn.close()
db.init_db(OLD)
ok("【5】遷移補上 bridged_unlocks 欄位",
   "bridged_unlocks" in db.existing_columns(db.connect(OLD), "nightly_behavior"))
got = stored("u", "2026-11-01", OLD)
ok("【5】舊資料是 NULL（不知道），不是 0", got is None, repr(got))

print()
if fails:
    print(f"✗ {len(fails)} 條失敗：{fails}")
    sys.exit(1)
print("✓ 全部通過")
