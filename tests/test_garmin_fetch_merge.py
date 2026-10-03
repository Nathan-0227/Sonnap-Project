"""
tests/test_garmin_fetch_merge.py — 重抓 Garmin 時，舊日子不會變少

⚠️ 全程不連 Garmin：合併是純函式；跑 fetch 的 main() 時塞一個假的
   garminconnect 模組，帳密是假字串，輸出寫在暫存資料夾。

這支守的是六個**壞掉時不會報錯**的地方——每一個壞掉之後，抓取、評分、
匯入都照常成功，只是資料安靜地少了或重複了：

1. **視窗外的日子逐筆不變。** 這是整件事的目的：Garmin 會把約 4 個月前的
   細節收掉，重抓到那些日子就是把遺失抄進來。
2. **視窗內新的贏。** 最近幾天會晚到補齊（09-29：55 → 1578 筆），
   留舊的就永遠拿不到完整的那一版。
3. **某天某個來源這次一筆都沒抓到 → 留舊的。** 那是 API 那次沒回東西。
4. **切點不落在睡眠中間。** 落進去的話那一晚前半舊後半新；
   Garmin 修正過入睡時刻的話，同一晚還會出現兩筆 sleep_start_time。
5. **只抓歷史中間一段時，後面的日子也要留著。**
6. **不加 --replace 時，`--days 1` 不會讓歷史變少**；舊檔讀不出來要停，
   不能退回覆寫。

執行：python tests/test_garmin_fetch_merge.py
"""
import contextlib
import io
import json
import sys
import tempfile
import types
from datetime import date, datetime, timedelta
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "garmin"))

import merge_standard_data as m  # noqa: E402

fails = []


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<58} {extra}")
    if not cond:
        fails.append(label)


# ─── 造假資料 ─────────────────────────────────────────────────────

def rec(ts, metric, value=1):
    return {"timestamp": f"{ts}+08:00", "metric": metric, "value": value, "unit": "x"}


def night(start, wake, tag):
    """一晚的睡眠：入睡、起床、一段分期、幾筆動作。tag 寫進 value 好分辨新舊。"""
    mid = (datetime.fromisoformat(start) + (datetime.fromisoformat(wake) - datetime.fromisoformat(start)) / 2
           ).isoformat(timespec="seconds")
    return [
        rec(start, "sleep_start_time", tag),
        rec(start, "resting_heart_rate", tag),
        rec(start, "deep_duration_sec", tag),
        rec(start, "sleep_stage", tag),
        rec(start, "sleep_segment_start", tag),
        rec(mid, "movement", tag),
        rec(wake, "sleep_segment_end", tag),
        rec(wake, "wake_time", tag),
    ]


def day_series(day, tag, hours=(1, 9, 14, 20)):
    """那一天的心率、壓力（散在一天裡）與步數（固定 15:00）。"""
    rows = []
    for h in hours:
        rows.append(rec(f"{day}T{h:02d}:30:00", "heart_rate", tag))
        rows.append(rec(f"{day}T{h:02d}:40:00", "stress_score", tag))
    rows.append(rec(f"{day}T15:00:00", "daily_steps", tag))
    return rows


def by_tag(records, tag):
    return [r for r in records if r["value"] == tag]


def on(records, day, metric=None):
    return [r for r in records if r["timestamp"].startswith(day) and (metric is None or r["metric"] == metric)]


def D(s):
    return date.fromisoformat(s)


def days(first, last):
    a, b = D(first), D(last)
    return [a + timedelta(days=i) for i in range((b - a).days + 1)]


def sort(records):
    return sorted(records, key=lambda r: r["timestamp"])


# 舊檔：06-01 ~ 06-05，每晚 02:00 睡到 10:00（都不跨午夜）
OLD = sort([r for d in ("2026-06-01", "2026-06-02", "2026-06-03", "2026-06-04", "2026-06-05")
            for r in day_series(d, "old") + night(f"{d}T02:00:00", f"{d}T10:00:00", "old")])


print("【1】視窗外的日子逐筆不變")
new = sort([r for d in ("2026-06-04", "2026-06-05", "2026-06-06")
            for r in day_series(d, "new") + night(f"{d}T02:00:00", f"{d}T10:00:00", "new")])
merged, report = m.merge_records(OLD, new, days("2026-06-04", "2026-06-06"))
before = [r for r in OLD if r["timestamp"] < "2026-06-04"]
after = [r for r in merged if r["timestamp"] < "2026-06-04"]
ok("06-01 ~ 06-03 逐筆相同、順序也相同", before == after, f"{len(before)} 筆 vs {len(after)} 筆")
ok("  那三天一筆新的都沒有", not by_tag(after, "new"))
ok("報告的筆數對得起來", report["kept"] == len(before) and report["taken"] == len(new),
   str({k: report[k] for k in ("kept", "replaced", "taken")}))

print("\n【2】視窗內新的贏；新的一天加進來")
ok("06-04、06-05 全部換成新的", not on(by_tag(merged, "old"), "2026-06-04")
   and not on(by_tag(merged, "old"), "2026-06-05"))
ok("  而且新的真的在（不是只是把舊的刪了）",
   len(on(merged, "2026-06-04")) == len(on(new, "2026-06-04")) > 0)
ok("06-06 是新增的一天", len(on(merged, "2026-06-06")) == len(on(new, "2026-06-06")) > 0)
ok("合併後仍然照時間排序", merged == sort(merged))

print("\n【3】某天某個來源這次一筆都沒抓到 → 留舊的，並回報")
# 06-05 的壓力與睡眠這次沒抓到；心率、步數有
new3 = sort([r for r in new if not (r["timestamp"].startswith("2026-06-05")
                                    and r["metric"] in m.SOURCE_METRICS["stress"] | m.SOURCE_METRICS["sleep"])])
empty = {(D("2026-06-05"), "stress"), (D("2026-06-05"), "sleep"),
         (D("2026-06-06"), "steps")}                 # 06-06 舊的本來就沒有 → 不該出現在報告裡
merged3, report3 = m.merge_records(OLD, new3, days("2026-06-04", "2026-06-06"), empty)
ok("06-05 的壓力留舊的", [r["value"] for r in on(merged3, "2026-06-05", "stress_score")] == ["old"] * 4)
ok("06-05 那一晚的睡眠整組留舊的",
   {r["metric"] for r in by_tag(on(merged3, "2026-06-05"), "old")}
   == {"stress_score"} | {r["metric"] for r in night("2026-06-05T02:00:00", "2026-06-05T10:00:00", "x")})
ok("  06-05 的心率照樣換成新的（只留沒抓到的那個來源）",
   [r["value"] for r in on(merged3, "2026-06-05", "heart_rate")] == ["new"] * 4)
ok("  06-04 不受影響，壓力是新的", [r["value"] for r in on(merged3, "2026-06-04", "stress_score")] == ["new"] * 4)
ok("報告列出留了哪一天哪個來源",
   sorted((d, s) for d, s, _ in report3["kept_when_empty"]) == [("2026-06-05", "sleep"), ("2026-06-05", "stress")],
   str(report3["kept_when_empty"]))
# 反向對照：沒有標成 empty 時，新的沒有就是沒有
merged3b, _ = m.merge_records(OLD, new3, days("2026-06-04", "2026-06-06"))
ok("反向對照：沒標成「沒抓到」→ 06-05 的壓力就是空的", on(merged3b, "2026-06-05", "stress_score") == [])
# 睡眠掛在別的抓取日（新資料裡有重疊的一晚）→ 不救，否則會有兩份
merged3c, report3c = m.merge_records(OLD, new, days("2026-06-04", "2026-06-06"), {(D("2026-06-05"), "sleep")})
ok("新資料已經有同一晚 → 不救（不然會變兩份）",
   len(on(merged3c, "2026-06-05", "sleep_start_time")) == 1 and report3c["kept_when_empty"] == [])

print("\n【4】切點不落在睡眠中間")
# 舊檔：06-03 晚上 23:00 睡到 06-04 07:00（跨過視窗起點的午夜）
old4 = sort(day_series("2026-06-03", "old") + day_series("2026-06-04", "old")
            + night("2026-06-03T23:00:00", "2026-06-04T07:00:00", "old"))
# 新抓 06-04：Garmin 把那一晚的入睡修正成 00:10（落在視窗內），其餘照常
new4 = sort(day_series("2026-06-04", "new") + night("2026-06-04T00:10:00", "2026-06-04T07:00:00", "new"))
merged4, report4 = m.merge_records(old4, new4, [D("2026-06-04")])
starts = [r for r in merged4 if r["metric"] == "sleep_start_time"]
ok("那一晚只有一筆入睡時刻", len(starts) == 1, str([r["timestamp"] for r in starts]))
ok("  整晚留舊的（不是前半舊、後半新）",
   {r["value"] for r in merged4 if r["metric"] in m.SOURCE_METRICS["sleep"]} == {"old"})
ok("  起床之前的心率也留舊的（01:30）",
   [r["value"] for r in merged4 if r["timestamp"].startswith("2026-06-04T01:30")] == ["old"])
ok("  起床之後的換成新的（09:30、14:30、20:30）",
   [r["value"] for r in on(merged4, "2026-06-04", "heart_rate") if r["timestamp"] > "2026-06-04T07"] == ["new"] * 3)
ok("  視窗起點縮到起床之後", report4["window"][0].startswith("2026-06-04T07:00:01"), report4["window"][0])
ok("沒有任何一筆重複", len({json.dumps(r, sort_keys=True) for r in merged4}) == len(merged4))

print("\n【5】只抓歷史中間一段 → 前後都留著")
new5 = sort(day_series("2026-06-03", "new") + night("2026-06-03T02:00:00", "2026-06-03T10:00:00", "new"))
merged5, _ = m.merge_records(OLD, new5, [D("2026-06-03")])
ok("06-04、06-05 還在，而且是舊的",
   on(merged5, "2026-06-04") == on(OLD, "2026-06-04") and on(merged5, "2026-06-05") == on(OLD, "2026-06-05"))
ok("06-03 換成新的", {r["value"] for r in on(merged5, "2026-06-03")} == {"new"})
# 視窗終點落在一段睡眠中間（06-03 23:00 → 06-04 07:00）→ 那一晚整晚留舊的
merged5b, report5b = m.merge_records(old4, sort(day_series("2026-06-03", "new")), [D("2026-06-03")])
ok("終點那一晚整晚留舊的", {r["value"] for r in merged5b if r["metric"] in m.SOURCE_METRICS["sleep"]} == {"old"}
   and len([r for r in merged5b if r["metric"] == "sleep_start_time"]) == 1)
ok("  視窗終點縮到入睡之前", report5b["window"][1].startswith("2026-06-03T23:00:00"), report5b["window"][1])

print("\n【6】fetch 本身：不加 --replace 就不會讓歷史變少")
import garmin_connect_fetch as fetch  # noqa: E402


class FakeGarmin:
    """只有步數那支 API 有回東西；其他三支都丟例外（等於那一天沒抓到）。"""

    def __init__(self, email, password):
        pass

    def login(self):
        pass

    def get_daily_steps(self, start, end):
        return [{"calendarDate": start, "totalSteps": 4321, "stepGoal": 7000}]


def run_fetch(output, *extra):
    sys.modules["garminconnect"] = types.SimpleNamespace(Garmin=FakeGarmin)
    argv = sys.argv
    sys.argv = ["garmin_connect_fetch.py", "--email", "x", "--password", "x", "--output", str(output), *extra]
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            fetch.main()
    finally:
        sys.argv = argv
        del sys.modules["garminconnect"]
    return out.getvalue()


def write_old(path):
    path.write_text(json.dumps({"device_id": "d", "records": OLD}), encoding="utf-8")


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))["records"]


with tempfile.TemporaryDirectory() as d:
    out_path = Path(d) / "garmin_standard_data.json"
    today = date.today().isoformat()

    write_old(out_path)
    text = run_fetch(out_path, "--days", "1")
    got = read(out_path)
    ok("--days 1 之後，舊的 5 天逐筆都還在", [r for r in got if r["timestamp"] < "2026-06-06"] == OLD,
       f"{len(got)} 筆")
    ok("  今天的步數加進來了", [r["value"] for r in on(got, today, "daily_steps")] == [4321])
    ok("  total_records 跟著更新", json.loads(out_path.read_text(encoding="utf-8"))["total_records"] == len(got))
    ok("  輸出有說這次是合併", "mode: merge" in text)
    ok("  沒有留下暫存檔", [p.name for p in Path(d).iterdir()] == ["garmin_standard_data.json"])

    write_old(out_path)
    run_fetch(out_path, "--start-date", "2026-06-05", "--end-date", "2026-06-05")
    got = read(out_path)
    ok("06-05 的心率這次沒抓到 → 留舊的",
       [r["value"] for r in on(got, "2026-06-05", "heart_rate")] == ["old"] * 4)
    ok("  06-05 的步數換成新抓的", [r["value"] for r in on(got, "2026-06-05", "daily_steps")] == [4321])

    write_old(out_path)
    text = run_fetch(out_path, "--days", "1", "--replace")
    ok("反向對照：加了 --replace → 舊的 5 天全沒了",
       not [r for r in read(out_path) if r["timestamp"] < "2026-06-06"] and "mode: replace" in text)

    out_path.write_text("{ not json", encoding="utf-8")
    try:
        run_fetch(out_path, "--days", "1")
        raised = False
    except ValueError:
        raised = True
    ok("舊檔讀不出來 → 停下，而且檔案沒被動到",
       raised and out_path.read_text(encoding="utf-8") == "{ not json")

    out_path.unlink()
    run_fetch(out_path, "--days", "1")
    ok("還沒有檔案 → 照常寫出來", [r["value"] for r in on(read(out_path), today, "daily_steps")] == [4321])

print("\n【7】上次抓到哪一天")
ok("取最晚的一筆", m.last_record_day(OLD, m.parse_tz("+08:00")) == D("2026-06-05"))
ok("空的回 None", m.last_record_day([], m.parse_tz("+08:00")) is None)

print()
if fails:
    print(f"✗ {len(fails)} 項沒過：")
    for f in fails:
        print(f"   - {f}")
    sys.exit(1)
print("✓ 全部通過")
