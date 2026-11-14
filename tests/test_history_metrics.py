"""
tests/test_history_metrics.py

history 每晚的睡眠效率與深睡（2026-11-12，首頁「跟上一晚比」用）。

守的是**壞掉時不會報錯**的地方：欄位少了，App 只是不顯示比較；
來源跟首頁卡片不同的話，卡片寫 98%、比較卻是從另一個數字算的。

  【1】asset：history[-1] 的效率與深睡，與首頁 metrics 逐字相同（同一個來源）
  【2】asset：每晚都有這兩個欄位（值可以是 null，但鍵要在）
  【3】/insights：wearable.history 也帶這兩個欄位，值與寫進資料庫的相同
  【4】/insights：wearable.history 帶 waso_minutes（Awake 一週圖用）；0 照實回 0，不是 null
  【6】/insights：wearable.history 帶 sleep_heart_rate（睡著那段的平均＋最低，同報告格子那支）；沒曲線是 null
  【5】/insights：每晚的 composition 帶 efficiency_label，字與 score_claim.EFFICIENCY_BASIS_LABELS 逐字相同；效率沒算時是 null

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
    {"final_score": 70.0, "final_quality": "Normal", "efficiency": 93.4, "deep_min": 41,
     "waso_min": 0, "efficiency_basis": "watch_tst__watch_onset_to_wake"},
    db_path=TMP,
)
db.upsert_wearable_nightly(
    user_id, "2026-11-09", "garmin",
    {"final_score": 82.0, "final_quality": "Good", "efficiency": 97.1, "deep_min": 76,
     "waso_min": 14, "efficiency_basis": "watch_tst__phone_tats"},
    db_path=TMP,
)
api = client.get(f"/insights?user_id={user_id}&days=365").json()
by_date = {e["date"]: e for e in api["wearable"]["history"]}
ok("11-08 效率 93.4", by_date["2026-11-08"].get("sleep_efficiency") == 93.4,
   repr(by_date["2026-11-08"].get("sleep_efficiency")))
ok("11-09 深睡 76", by_date["2026-11-09"].get("deep_minutes") == 76,
   repr(by_date["2026-11-09"].get("deep_minutes")))
ok("【4】11-09 清醒 14 分", by_date["2026-11-09"].get("waso_minutes") == 14,
   repr(by_date["2026-11-09"].get("waso_minutes")))
ok("【4】11-08 清醒 0 分照實回 0（不是 null）", by_date["2026-11-08"].get("waso_minutes") == 0,
   repr(by_date["2026-11-08"].get("waso_minutes")))
import score_claim
for d, basis in (("2026-11-08", "watch_tst__watch_onset_to_wake"), ("2026-11-09", "watch_tst__phone_tats")):
    comp = by_date[d].get("composition") or {}
    ok(f"【5】{d} efficiency_label 照抄 score_claim",
       comp.get("efficiency_label") == score_claim.EFFICIENCY_BASIS_LABELS[basis],
       repr(comp.get("efficiency_label")))
ok("【5】效率沒算 → efficiency_label 是 null",
   score_claim.compose(["duration"]).get("efficiency_label") is None)

# 【6】假的 Garmin 原始讀數：只有 11-09 那一晚有（01:00–02:00 每 2 分鐘，最低 47）
from datetime import datetime as _dt, timedelta as _td
db.upsert_wearable_nightly(
    user_id, "2026-11-09", "garmin",
    {"final_score": 82.0, "final_quality": "Good", "efficiency": 97.1, "deep_min": 76,
     "waso_min": 14, "efficiency_basis": "watch_tst__phone_tats",
     "sleep_start_time": "2026-11-09T01:00:00+08:00", "wake_time": "2026-11-09T02:00:00+08:00"},
    db_path=TMP,
)
_t0 = _dt.fromisoformat("2026-11-09T01:00:00+08:00")
_fake = [{"timestamp": (_t0 + _td(minutes=2 * i)).isoformat(), "metric": "heart_rate",
          "value": 47 if i == 10 else 56, "unit": "bpm"} for i in range(31)]
_saved = main._garmin_records
main._garmin_records = lambda: _fake
try:
    api = client.get(f"/insights?user_id={user_id}&days=365").json()
finally:
    main._garmin_records = _saved
by_date = {e["date"]: e for e in api["wearable"]["history"]}
hr9 = by_date["2026-11-09"].get("sleep_heart_rate")
ok("【6】11-09 睡著心率平均與最低照 night_heart_rate",
   hr9 == {k: main.sleep_heart_rate.heart_rate_curve(_fake, "2026-11-09T01:00:00+08:00",
                                                     "2026-11-09T02:00:00+08:00")[k]
           for k in ("avg", "min")} and hr9["min"] == 47, repr(hr9))
ok("【6】沒有睡著時刻的晚上 → null（不是 0）",
   "sleep_heart_rate" in by_date["2026-11-08"] and by_date["2026-11-08"]["sleep_heart_rate"] is None,
   repr(by_date["2026-11-08"].get("sleep_heart_rate")))

print()
if fails:
    print(f"✗ {len(fails)} 條失敗：{fails}")
    sys.exit(1)
print("✓ 全部通過")
