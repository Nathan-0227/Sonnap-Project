"""
tests/test_garmin_daily_tz.py — 每日心率與壓力的時刻是真正的當地時間

⚠️ 全程不連 Garmin：解析函式直接餵假的 API 回應；跑 fetch 的 main() 時塞一個
   假的 garminconnect 模組；轉換腳本跑在暫存資料夾的假檔案上。

背景（2026-10-03 發現）：`_iso_from_epoch_ms` 回傳的是 UTC 鐘面貼上 +08:00。
睡眠那幾段另外加了 8 小時所以是對的，每日心率與壓力沒有，整批早 8 小時。
分數、評分、匯入全部照常成功——錯的只是 Tier3 讀到的是哪一段時間。

這支守的是五個**壞掉時不會報錯**的地方：

1. **每日心率與壓力的每一種回應形狀都要換算。** 兩支解析函式各有好幾個
   分支，實際走哪一個取決於 Garmin 當下回什麼形狀。
2. **睡眠那幾段不能跟著多加 8 小時。** 最直覺的修法是把 `_iso_from_epoch_ms`
   改對——那會讓入睡與起床時刻全部晚 8 小時。
3. **同一時刻的心率只留一份。** 時刻修正之後睡眠 API 與每日 API 的心率會
   重疊，兩份都留的話睡眠時段在平均值裡的權重變兩倍。
4. **既有檔案的轉換**：每日來源 +8 小時、睡眠來源去重、其他紀錄逐筆不變；
   轉過的不再轉（再轉一次會變成晚 8 小時）。
5. **還沒轉換的舊檔不能併進新抓的資料。** 那會是一份前半錯位、後半正確的檔案。

執行：python tests/test_garmin_daily_tz.py
"""
import contextlib
import io
import json
import sys
import tempfile
import types
from datetime import datetime, timedelta, timezone
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "garmin"))

import garmin_connect_fetch as fetch  # noqa: E402
import migrate_daily_series_tz as mig  # noqa: E402

fails = []


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<58} {extra}")
    if not cond:
        fails.append(label)


TZ = "+08:00"
TPE = timezone(timedelta(hours=8))


def ms(local):
    """當地時間字串 → epoch 毫秒。"""
    return int(datetime.fromisoformat(local).replace(tzinfo=TPE).timestamp() * 1000)


def gmt_str(local):
    """當地時間字串 → Garmin 的 GMT 字串（2026-06-10T18:00:00.0）。"""
    utc = datetime.fromisoformat(local).replace(tzinfo=TPE).astimezone(timezone.utc)
    return utc.strftime("%Y-%m-%dT%H:%M:%S.0")


def stamps(records, metric):
    return [r["timestamp"] for r in records if r["metric"] == metric]


WANT = "2026-06-11T02:00:00+08:00"       # 當地凌晨兩點 = UTC 前一天 18:00

print("【1】每日心率：每一種回應形狀都換算成當地時間")
shapes = {
    "heartRateValues 是 [毫秒, 值] 的清單（實際走的那條）": {"heartRateValues": [[ms("2026-06-11T02:00:00"), 61]]},
    "heartRateValues 是 {毫秒: 值}": {"heartRateValues": {str(ms("2026-06-11T02:00:00")): 61}},
    "heartRateValues 是 dict 的清單": {"heartRateValues": [{"timestamp": ms("2026-06-11T02:00:00"), "value": 61}]},
    "heartRateValues 是純數值清單 + startTimestampGMT": {
        "startTimestampGMT": gmt_str("2026-06-11T02:00:00"), "heartRateValues": [61]},
    "最外層就是清單（timestamp 毫秒）": [{"timestamp": ms("2026-06-11T02:00:00"), "value": 61}],
    "最外層就是清單（timeInSeconds）": [{"timeInSeconds": ms("2026-06-11T02:00:00") // 1000, "value": 61}],
}
for label, raw in shapes.items():
    out = []
    fetch._parse_heart_rate_data(raw, TZ, out)
    ok(label, stamps(out, "heart_rate") == [WANT], str(stamps(out, "heart_rate")))

print("\n【1b】壓力：兩種回應形狀都換算")
for label, raw in {
    "stressValuesArray（實際走的那條）": {"stressValuesArray": [[ms("2026-06-11T02:00:00"), 20]]},
    "最外層就是清單": [{"timestamp": ms("2026-06-11T02:00:00"), "value": 20}],
}.items():
    out = []
    fetch._parse_stress_data(raw, TZ, out, False)
    ok(label, stamps(out, "stress_score") == [WANT], str(stamps(out, "stress_score")))
out = []
fetch._parse_stress_data({"stressValuesArray": [[ms("2026-06-11T02:00:00"), -1]]}, TZ, out, False)
ok("負值照樣被濾掉（換算沒有繞過原本的規則）", out == [])

print("\n【2】睡眠那幾段沒有被多加 8 小時")
SLEEP = {
    "dailySleepDTO": {
        "sleepStartTimestampGMT": ms("2026-06-11T02:00:00"),
        "sleepEndTimestampGMT": ms("2026-06-11T09:00:00"),
        "deepSleepSeconds": 3600,
    },
    "sleepLevels": [{"startGMT": gmt_str("2026-06-11T02:00:00"), "endGMT": gmt_str("2026-06-11T03:00:00"),
                     "activityLevel": 0}],
    "sleepHeartRate": [{"startGMT": ms("2026-06-11T02:00:00"), "value": 55},
                       {"startGMT": ms("2026-06-11T02:02:00"), "value": 56}],
    "sleepMovement": [{"startGMT": gmt_str("2026-06-11T02:00:00"), "activityLevel": 1.0}],
    "restingHeartRate": 50,
}
out = []
fetch._parse_sleep_data("2026-06-11", SLEEP, TZ, out)
ok("入睡時刻", stamps(out, "sleep_start_time") == [WANT], str(stamps(out, "sleep_start_time")))
ok("起床時刻", stamps(out, "wake_time") == ["2026-06-11T09:00:00+08:00"], str(stamps(out, "wake_time")))
ok("睡眠分段", stamps(out, "sleep_segment_start") == [WANT] and
   stamps(out, "sleep_segment_end") == ["2026-06-11T03:00:00+08:00"])
ok("睡眠心率", stamps(out, "heart_rate") == [WANT, "2026-06-11T02:02:00+08:00"], str(stamps(out, "heart_rate")))
ok("動作", stamps(out, "movement") == [WANT], str(stamps(out, "movement")))

print("\n【3】fetch 整支：同一時刻的心率只留一份，以每日那份為準")


class FakeGarmin:
    def __init__(self, email, password):
        pass

    def login(self):
        pass

    def get_sleep_data(self, day):
        return SLEEP if day == "2026-06-11" else {}

    def get_heart_rates(self, day):
        if day != "2026-06-11":
            return {}
        # 02:00 與睡眠 API 重疊（值刻意不同，才看得出留的是哪一份）；02:02 每日沒有讀數；14:00 是白天
        return {"heartRateValues": [[ms("2026-06-11T02:00:00"), 99], [ms("2026-06-11T14:00:00"), 80]]}

    def get_stress_data(self, day):
        return {"stressValuesArray": [[ms("2026-06-11T02:00:00"), 20]]} if day == "2026-06-11" else {}


def run_fetch(output, *extra):
    sys.modules["garminconnect"] = types.SimpleNamespace(Garmin=FakeGarmin)
    argv = sys.argv
    sys.argv = ["garmin_connect_fetch.py", "--email", "x", "--password", "x", "--output", str(output),
                "--start-date", "2026-06-11", "--end-date", "2026-06-11", *extra]
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            fetch.main()
    finally:
        sys.argv = argv
        del sys.modules["garminconnect"]


with tempfile.TemporaryDirectory() as d:
    path = Path(d) / "garmin_standard_data.json"
    run_fetch(path)
    payload = json.loads(path.read_text(encoding="utf-8"))
    hr = {r["timestamp"]: r["value"] for r in payload["records"] if r["metric"] == "heart_rate"}
    n_hr = sum(r["metric"] == "heart_rate" for r in payload["records"])
    ok("02:00 只有一筆，而且是每日那份（99）", hr.get(WANT) == 99 and n_hr == 3, f"{n_hr} 筆 {hr}")
    ok("02:02 每日沒有讀數 → 睡眠那份留著（56）", hr.get("2026-06-11T02:02:00+08:00") == 56)
    ok("14:00 的白天心率在當地 14:00", hr.get("2026-06-11T14:00:00+08:00") == 80)
    ok("壓力在當地 02:00", stamps(payload["records"], "stress_score") == [WANT])
    ok("新寫出的檔案有標記", mig.is_converted(payload), str({k: v for k, v in payload.items() if k != "records"}))

    print("\n【5】還沒轉換的舊檔 → 拒絕合併，檔案不動")
    old = json.dumps({"device_id": "d", "records": [
        {"timestamp": "2026-06-01T10:00:00+08:00", "metric": "heart_rate", "value": 60, "unit": "bpm"}]})
    path.write_text(old, encoding="utf-8")
    try:
        run_fetch(path)
        raised = ""
    except ValueError as exc:
        raised = str(exc)
    ok("停下來，而且有說要跑哪一支", "migrate_daily_series_tz.py" in raised, raised[:60])
    ok("  檔案沒被動到", path.read_text(encoding="utf-8") == old)
    run_fetch(path, "--replace")
    ok("  反向對照：--replace 不看舊檔，照常寫出",
       mig.is_converted(json.loads(path.read_text(encoding="utf-8"))))

print("\n【4】既有檔案的轉換")


def rec(local, metric, value, unit="x"):
    return {"timestamp": f"{local}+08:00", "metric": metric, "value": value, "unit": unit}


def minus8(local):
    return (datetime.fromisoformat(local) - timedelta(hours=8)).isoformat(timespec="seconds")


def at(minutes):
    return (datetime(2026, 6, 11, 2, 0) + timedelta(minutes=minutes)).isoformat(timespec="seconds")


# 真實情況：02:00 入睡、04:00 起床。整段心率每 2 分鐘一筆，值 = 50 + 第幾筆。
# 睡眠來源：時刻正確。每日來源：同樣的值，但時刻早 8 小時。
truth = {at(m): 50 + m // 2 for m in range(0, 121, 2)}                      # 02:00 ~ 04:00
daytime = {"2026-06-11T12:00:00": 90, "2026-06-11T12:02:00": 91}           # 白天，只有每日來源
missing_in_daily = {at(m) for m in (40, 42, 44, 46)}                        # 這四個時刻每日來源沒有讀數

old = [rec("2026-06-11T02:00:00", "sleep_start_time", "s"), rec("2026-06-11T04:00:00", "wake_time", "w"),
       rec("2026-06-11T02:00:00", "movement", 1.0), rec("2026-06-11T15:00:00", "daily_steps", 1234)]
old += [rec(t, "heart_rate", v, "bpm") for t, v in truth.items()]                           # 睡眠來源
old += [rec(minus8(t), "heart_rate", v, "bpm") for t, v in {**truth, **daytime}.items()
        if t not in missing_in_daily]                                                       # 每日來源（錯位）
# 另一段每日讀數，錯位後剛好落在睡眠時段裡（真實時刻是 10:00 ~ 12:00，值 = 70 + 第幾筆）
late = {(datetime(2026, 6, 11, 10, 0) + timedelta(minutes=m)).isoformat(timespec="seconds"): 70 + m // 2
        for m in range(0, 120, 2)}
old += [rec(minus8(t), "heart_rate", v, "bpm") for t, v in late.items()]
old += [rec(minus8("2026-06-11T03:00:00"), "stress_score", 15, "score")]
old.sort(key=lambda r: r["timestamp"])

new, report = mig.convert(old)
hr_after = {}
for r in new:
    if r["metric"] == "heart_rate":
        hr_after.setdefault(r["timestamp"][:19], []).append(r["value"])
ok("每個時刻只剩一個心率值", all(len(v) == 1 for v in hr_after.values()),
   str([k for k, v in hr_after.items() if len(v) > 1][:3]))
ok("睡眠時段每一筆都等於真實值（含每日來源缺的那四筆）",
   all(hr_after.get(t) == [v] for t, v in truth.items()),
   str([(t, hr_after.get(t), v) for t, v in truth.items() if hr_after.get(t) != [v]][:3]))
ok("白天的心率回到 12:00", hr_after.get("2026-06-11T12:00:00") == [90] and hr_after.get("2026-06-11T12:02:00") == [91])
ok("錯位後落在睡眠時段的那批回到 10:00 ~ 12:00",
   all(hr_after.get(t) == [v] for t, v in late.items()))
ok("  原本錯位的時刻（前一天 18:00）已經沒有心率", not [k for k in hr_after if k.startswith("2026-06-10")])
ok("壓力 +8 小時", stamps(new, "stress_score") == ["2026-06-11T03:00:00+08:00"], str(stamps(new, "stress_score")))
others = lambda rs: [r for r in rs if r["metric"] not in ("heart_rate", "stress_score")]  # noqa: E731
ok("其他紀錄逐筆不變", others(new) == others(old))
ok("仍然照時間排序", new == sorted(new, key=lambda r: r["timestamp"]))
ok("報告：缺的那四筆是從睡眠來源補的", report["sleep_source_kept"] == 4, str(report))

with tempfile.TemporaryDirectory() as d:
    path = Path(d) / "garmin_standard_data.json"
    backups = Path(d) / "backups"
    path.write_text(json.dumps({"device_id": "d", "records": old}), encoding="utf-8")

    def run_migrate(*extra):
        argv = sys.argv
        sys.argv = ["migrate_daily_series_tz.py", "--file", str(path), "--backup-dir", str(backups), *extra]
        buf = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf):
                rc = mig.main()
        finally:
            sys.argv = argv
        return rc, buf.getvalue()

    before = path.read_text(encoding="utf-8")
    run_migrate("--dry-run")
    ok("--dry-run 不寫檔、不備份", path.read_text(encoding="utf-8") == before and not backups.exists())
    run_migrate()
    once = path.read_text(encoding="utf-8")
    ok("轉換後有標記、筆數對", mig.is_converted(json.loads(once))
       and json.loads(once)["total_records"] == len(new) == len(json.loads(once)["records"]))
    ok("轉換前的檔案有備份", [p.read_text(encoding="utf-8") for p in backups.iterdir()] == [before])
    rc, text = run_migrate()
    ok("再跑一次 → 什麼都不改（不會變成晚 8 小時）",
       rc == 0 and path.read_text(encoding="utf-8") == once and "Already converted" in text)
    ok("  也沒有多一份備份", len(list(backups.iterdir())) == 1)

print()
if fails:
    print(f"✗ {len(fails)} 項沒過：")
    for f in fails:
        print(f"   - {f}")
    sys.exit(1)
print("✓ 全部通過")
