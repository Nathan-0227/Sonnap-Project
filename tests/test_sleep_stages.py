"""
tests/test_sleep_stages.py

首頁 Sleep Stages 圖的資料（garmin/sleep_stages.py 與打包檔的 metrics.sleep_stages）。

守的都是**壞掉時不會報錯**的地方——曲線照畫，只是畫錯：

  【1】整晚摘要那四筆（入睡時刻、每階段一筆）不能被當成時間段
  【2】入睡前一兩分鐘開始的第一段要收進來、並夾到入睡時刻（實測 11-02 丟過 51 分鐘淺睡）
  【3】最後一段結束在起床時刻；不收起床之後的段
  【4】真實資料：還原出的各階段分鐘數與手錶自己的總數，九成五以上的夜晚差在 2 分鐘內
  【5】打包檔：圖例的分鐘數用手錶的總數（不是還原出來的），rem_measured 跟評分器一致

執行：python tests/test_sleep_stages.py
"""
import json
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "garmin"))

import sleep_stages as ss  # noqa: E402

fails = []


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<56} {extra}")
    if not cond:
        fails.append(label)


def rec(ts, metric, value):
    return {"timestamp": f"2026-11-02T{ts}:00+08:00", "metric": metric, "value": value}


START = "2026-11-02T03:53:00+08:00"
WAKE = "2026-11-02T08:23:00+08:00"

records = [
    # 整晚摘要（入睡時刻，每階段一筆＋秒數）
    rec("03:53", "sleep_stage", "rem"), rec("03:53", "rem_duration_sec", 5220),
    rec("03:53", "sleep_stage", "deep"), rec("03:53", "deep_duration_sec", 0),
    rec("03:53", "sleep_stage", "light"), rec("03:53", "light_duration_sec", 10980),
    rec("03:53", "sleep_stage", "awake"), rec("03:53", "awake_duration_sec", 0),
    # 真的時間段：第一段比入睡早一分鐘
    rec("03:52", "sleep_stage", "light"), rec("03:52", "sleep_segment_start", "x"),
    rec("04:43", "sleep_stage", "rem"), rec("04:43", "sleep_segment_start", "x"),
    rec("05:07", "sleep_stage", "light"), rec("05:07", "sleep_segment_start", "x"),
    # 起床之後的段不收
    rec("08:30", "sleep_stage", "awake"), rec("08:30", "sleep_segment_start", "x"),
]

print("=" * 78)
print("【1】【2】【3】合成資料")
print("=" * 78)
segs = ss.stage_segments(records, START, WAKE)
ok("段數 3（摘要四筆沒有變成段、起床後的不收）", len(segs) == 3, str(len(segs)))
ok("第一段是淺睡、起點夾到入睡 03:53", segs[0]["stage"] == "light"
   and segs[0]["start"] == START, segs[0]["start"])
ok("最後一段結束在起床 08:23", segs[-1]["end"] == WAKE, segs[-1]["end"])
mins = ss.stage_minutes(segs)
ok("淺睡 50 + 196 = 246 分鐘、REM 24 分鐘",
   mins["light"] == 246 and mins["rem"] == 24, str(mins))
ok("沒有長度 0 的段", all(s["start"] < s["end"] for s in segs))

print("=" * 78)
print("【4】真實資料：與手錶自己的各階段總數比對")
print("=" * 78)
raw = json.loads((ROOT / "garmin/data/garmin_standard_data.json").read_text(encoding="utf-8"))
recs = raw["records"]
features = json.loads((ROOT / "garmin/data/garmin_sleep_features.json").read_text(encoding="utf-8"))
summary = {}
for r in recs:
    m = r["metric"]
    if m.endswith("_duration_sec") and m[:-13] in ss.STAGES:
        summary.setdefault(r["timestamp"], {})[m[:-13]] = r["value"] / 60
n = close = 0
for f in features:
    s, w = f.get("sleep_start_time"), f.get("wake_time")
    ref = summary.get(s)
    if not s or not w or not ref:
        continue
    got = ss.stage_minutes(ss.stage_segments(recs, s, w))
    n += 1
    if max(abs(got[k] - ref.get(k, 0)) for k in ss.STAGES) <= 2:
        close += 1
ok("比對得到的夜晚數夠多（反向對照：不是 0 晚就過）", n >= 50, f"{n} 晚")
ok("九成五以上的夜晚差在 2 分鐘內", n and close / n >= 0.95, f"{close}/{n}")

print("=" * 78)
print("【5】打包檔的 metrics.sleep_stages")
print("=" * 78)
import build_app_payload as bap  # noqa: E402

payload = bap.build_payload()
block = payload["metrics"].get("sleep_stages")
night = payload["history"][-1]["date"]
feat = {r["date"]: r for r in features}[night]
ok("有 sleep_stages 區塊", block is not None)
if block:
    ok("圖例分鐘數用手錶的總數（淺睡）", block["minutes"]["light"] == feat["light_minutes"],
       f"{block['minutes']['light']} vs {feat['light_minutes']}")
    ok("圖例分鐘數用手錶的總數（深睡）", block["minutes"]["deep"] == feat["deep_minutes"])
    ok("rem_measured 與評分器一致",
       block["rem_measured"] == ("rem" in payload["scoring"]["composition"]["scored"]))
    ok("每一段都在入睡與起床之間",
       all(feat["sleep_start_time"] <= s["start"] < s["end"] <= feat["wake_time"]
           for s in block["segments"]))
ok("metrics 有 light_minutes", payload["metrics"].get("light_minutes") == feat["light_minutes"])

print()
if fails:
    print(f"✗ {len(fails)} 條失敗：{fails}")
    sys.exit(1)
print("✓ 全部通過")
