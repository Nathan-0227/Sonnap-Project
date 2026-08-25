"""
tests/test_healthconnect_adapter.py

手刻一份 Health Connect session，確認 wearable/healthconnect_adapter.py
算出的 Tier1/2 分數**與手算相符**——也就是它真的走了既有的評分器，
沒有為 Health Connect 另開一套標準。

執行：python tests/test_healthconnect_adapter.py
"""
import sys
from pathlib import Path

# Windows 主控台預設 cp1252，印中文會崩。專案慣例，見 run_pipeline.py。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

# 從專案根目錄 import。用 __file__ 定位，從任何工作目錄執行都可以
# （沿用 garmin/ 各腳本 2026-08-11 整理時採用的作法）。
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from wearable.healthconnect_adapter import (
    to_features, to_wearable_row, parse_session, normalize_stage,
    HealthConnectError,
)

D = "2026-08-25"
E = "2026-08-26"


def seg(s, e, stage, day_s=D, day_e=None):
    return {
        "startTime": f"{day_s}T{s}:00+08:00",
        "endTime": f"{day_e or day_s}T{e}:00+08:00",
        "stage": stage,
    }


SESSION = {
    "startTime": f"{D}T23:00:00+08:00",   # 上床
    "endTime":   f"{E}T07:30:00+08:00",   # 起床
    "stages": [
        seg("23:00", "23:20", "AWAKE"),                    # 入睡潛伏期，不是 WASO
        seg("23:20", "23:59", "LIGHT"),
        {"startTime": f"{D}T23:59:00+08:00",
         "endTime":   f"{E}T00:20:00+08:00", "stage": 4},  # LIGHT，用整數代碼
        seg("00:20", "01:20", "DEEP", E),
        seg("01:20", "01:35", "AWAKE", E),                 # ← WASO 15 分鐘
        seg("01:35", "03:05", "LIGHT", E),
        seg("03:05", "04:05", 6, E),                       # REM，整數代碼
        seg("04:05", "05:35", "SLEEP_LIGHT", E),           # health 套件的字串寫法
        seg("05:35", "06:35", "STAGE_TYPE_REM", E),        # Android 常數寫法
        seg("06:35", "07:00", "LIGHT", E),
        seg("07:00", "07:30", "AWAKE_IN_BED", E),          # 醒後賴床，不是 WASO
    ],
    "avgHeartRate": 58.2,
    "restingHeartRate": 52,
}

# ── 手算 ────────────────────────────────────────────────────────
# LIGHT = 39+21+90+90+25 = 265   DEEP = 60   REM = 60+60 = 120
# total_sleep = 445 分 = 7.4167 h → 7.42
# WASO = 15（只有 01:20–01:35；23:00 與 07:00 那兩段在睡眠區間之外）
# sleep_onset = 23:20, final_wake = 07:00 → sleep_period = 460 分
# efficiency = 445/460 = 96.74%
# deep_ratio = 60/445 = 0.1348 → 13.48%
# rem_ratio  = 120/445 = 0.2697 → 26.97%
# TIB = 23:00 → 07:30 = 510 分   clinical_eff = 445/510 = 87.25%   latency = 20 分
#
# 評分（young_adult）：
#   duration  7.42h ∈ [7,9]        → 30.0
#   efficiency 96.74 ≥ 85          → 25.0
#   waso      15 ≤ 15（佳）        → 25.0
#   deep      13.48% ∈ [13,23]     → 10.0
#   rem       26.97% > 25          → 10 − (26.97−25)×0.6 = 8.818
#   總分 = 98.818 → 98.8  Good
EXPECT = {
    "sleep_duration_hours": 7.42,
    "sleep_efficiency": 96.74,
    "waso_minutes": 15.0,
    "deep_ratio": 0.1348,
    "rem_ratio": 0.2697,
    "time_in_bed_minutes": 510.0,
    "sleep_latency_minutes": 20.0,
    "clinical_sleep_efficiency": 87.25,
}
EXPECT_SCORE = 98.8
EXPECT_QUALITY = "Good"

fails = []


def check(label, got, want):
    ok = got == want
    print(f"  {'✓' if ok else '✗'} {label:<30} 得到 {got!r:<12} 期望 {want!r}")
    if not ok:
        fails.append(label)


print("=" * 68)
print("【1】特徵抽取 vs 手算")
print("=" * 68)
feats = to_features(SESSION, age_band="young_adult")
for k, v in EXPECT.items():
    check(k, feats[k], v)
check("date（起床日）", feats["date"], E)
check("unknown_stage_labels", feats["unknown_stage_labels"], [])

print()
print("=" * 68)
print("【2】走既有評分器算出的 Tier1/2 vs 手算")
print("=" * 68)
date, metrics, _ = to_wearable_row(SESSION, age_band="young_adult",
                                   device_brand="Fitbit")
check("base_score", metrics["base_score"], EXPECT_SCORE)
check("base_quality", metrics["base_quality"], EXPECT_QUALITY)
check("final_score = base（無 Tier3）", metrics["final_score"], EXPECT_SCORE)
check("rem_measured", metrics["rem_measured"], 1)
check("total_modifier（確實是 0）", metrics["total_modifier"], 0.0)
check("sri（算不出來 → None）", metrics["sri"], None)
check("device_brand", metrics["device_brand"], "Fitbit")
print(f"  · modifier_note 有區分冷啟動與無此欄位: "
      f"{'✓' if '永遠不會有' in metrics['modifier_note'] and '冷啟動' in metrics['modifier_note'] else '✗'}")

print()
print("=" * 68)
print("【3】WASO 只算睡眠區間內 —— 把中間那段清醒拿掉應該掉 15 分鐘")
print("=" * 68)
no_waso = dict(SESSION)
no_waso["stages"] = [s for s in SESSION["stages"]
                     if not (s["startTime"].endswith("01:20:00+08:00")
                             and s["stage"] == "AWAKE")]
f2 = to_features(no_waso)
check("WASO", f2["waso_minutes"], 0.0)
print(f"  · 前後那兩段清醒（20 分 + 30 分）仍然沒被算進 WASO ✓")

print()
print("=" * 68)
print("【4】分期代碼正規化")
print("=" * 68)
for raw, want in [(5, "deep"), ("DEEP", "deep"), ("SLEEP_DEEP", "deep"),
                  ("STAGE_TYPE_REM", "rem"), ("HealthDataType.SLEEP_AWAKE", "awake"),
                  (2, "sleeping"), ("asleep", "sleeping"),
                  (99, None), ("???", None), (True, None), (None, None)]:
    check(f"normalize_stage({raw!r})", normalize_stage(raw), want)

print()
print("=" * 68)
print("【5】壞資料要明確失敗，不要安靜算出錯的數字")
print("=" * 68)
bad_cases = [
    ("沒有 stages", {"startTime": f"{D}T23:00:00+08:00",
                     "endTime": f"{E}T07:00:00+08:00", "stages": []}),
    ("endTime 早於 startTime", {"startTime": f"{E}T07:00:00+08:00",
                                "endTime": f"{D}T23:00:00+08:00",
                                "stages": [seg("23:00", "23:20", "LIGHT")]}),
    ("全是清醒", {"startTime": f"{D}T23:00:00+08:00",
                  "endTime": f"{E}T07:00:00+08:00",
                  "stages": [seg("23:00", "23:20", "AWAKE")]}),
    ("時間格式壞掉", {"startTime": "not-a-time", "endTime": "x",
                      "stages": [seg("23:00", "23:20", "LIGHT")]}),
]
for label, bad in bad_cases:
    try:
        parse_session(bad)
        print(f"  ✗ {label:<24} 沒有丟例外（安靜地算出了東西）")
        fails.append(label)
    except HealthConnectError as e:
        print(f"  ✓ {label:<24} {str(e)[:46]}")

print()
print("=" * 68)
print("【6】未知分期代碼要浮出來，不能被吞掉")
print("=" * 68)
weird = dict(SESSION)
weird["stages"] = SESSION["stages"] + [seg("07:30", "07:40", "SOMETHING_NEW", E)]
f3 = to_features(weird)
check("unknown_stage_labels", f3["unknown_stage_labels"], ["SOMETHING_NEW"])

print()
print("=" * 68)
print(f"結果：{'全部通過' if not fails else f'{len(fails)} 項失敗 → {fails}'}")
print("=" * 68)
sys.exit(1 if fails else 0)
