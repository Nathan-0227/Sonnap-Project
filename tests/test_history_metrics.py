"""
tests/test_history_metrics.py

history 每晚的睡眠效率與深睡（2026-11-12，首頁「跟上一晚比」用）。

守的是**壞掉時不會報錯**的地方：欄位少了，App 只是不顯示比較；
來源跟首頁卡片不同的話，卡片寫 98%、比較卻是從另一個數字算的。

  【1】asset：history[-1] 的效率與深睡，與首頁 metrics 逐字相同（同一個來源）
  【2】asset：每晚都有這兩個欄位（值可以是 null，但鍵要在）
  【3】/insights：wearable.history 也帶這兩個欄位，值與寫進資料庫的相同

⚠️ 【3】用暫存資料庫，不會碰到真的資料庫。

執行：python tests/test_history_metrics.py
"""
import json
import sys
import tempfile
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

# ⚠️ 一定要在 import main 之前換掉 DB_PATH，否則測試會寫到真的資料庫
import db
TMP = Path(tempfile.mkdtemp()) / "test.db"
db.DB_PATH = TMP

import build_app_payload as bap

fails = []


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<52} {extra}")
    if not cond:
        fails.append(label)


print("=" * 78)
print("【1】【2】打包檔（直接用 build_payload 產生，不讀可能過期的 asset 檔）")
print("=" * 78)

payload = bap.build_payload()
hist = payload["history"]
metrics = payload["metrics"]

ok("history[-1].sleep_efficiency == metrics.sleep_efficiency",
   hist[-1].get("sleep_efficiency") == metrics.get("sleep_efficiency"),
   f"{hist[-1].get('sleep_efficiency')!r} vs {metrics.get('sleep_efficiency')!r}")
ok("history[-1].deep_minutes == metrics.deep_minutes",
   hist[-1].get("deep_minutes") == metrics.get("deep_minutes"),
   f"{hist[-1].get('deep_minutes')!r} vs {metrics.get('deep_minutes')!r}")
missing = [e["date"] for e in hist
           if "sleep_efficiency" not in e or "deep_minutes" not in e]
ok("每晚都有 sleep_efficiency 與 deep_minutes 鍵", not missing, f"缺：{missing[:5]}")
# 反向對照：真的有值，不是整欄都 null（那樣上面幾條也會過）
ok("至少有一晚兩個值都不是 null",
   any(e.get("sleep_efficiency") is not None and e.get("deep_minutes") is not None
       for e in hist))

print("=" * 78)
print("【3】/insights 的 wearable.history")
print("=" * 78)

import main
from fastapi.testclient import TestClient

client = TestClient(main.app)
db.init_db(TMP)
user_id = client.post(
    "/users", json={"display_name": "history-metrics-guard", "target_bedtime": "23:30"}
).json()["user_id"]
db.upsert_wearable_nightly(
    user_id, "2026-11-08", "garmin",
    {"final_score": 70.0, "final_quality": "Normal", "efficiency": 93.4, "deep_min": 41},
    db_path=TMP,
)
db.upsert_wearable_nightly(
    user_id, "2026-11-09", "garmin",
    {"final_score": 82.0, "final_quality": "Good", "efficiency": 97.1, "deep_min": 76},
    db_path=TMP,
)
api = client.get(f"/insights?user_id={user_id}&days=365").json()
by_date = {e["date"]: e for e in api["wearable"]["history"]}
ok("11-08 效率 93.4", by_date["2026-11-08"].get("sleep_efficiency") == 93.4,
   repr(by_date["2026-11-08"].get("sleep_efficiency")))
ok("11-09 深睡 76", by_date["2026-11-09"].get("deep_minutes") == 76,
   repr(by_date["2026-11-09"].get("deep_minutes")))

print()
if fails:
    print(f"✗ {len(fails)} 條失敗：{fails}")
    sys.exit(1)
print("✓ 全部通過")
