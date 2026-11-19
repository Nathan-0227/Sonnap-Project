"""
好友排行榜（social/leaderboard.py ＋ GET /friends/leaderboard）。2026-11-17 新增。

守的事：
【1】時段的範圍（晚／日／最近 7、30、365 天，以及「上一個時段」）
【2】月、年用平均不用加總：晚數多的人不會因為加總而贏
【3】門檻：不到的人沒有名次、列在下面；沒資料的晚上不算準時也不算分母
【4】同分並列（1, 1, 3）；Steady 越小越前
【5】Score 只算有按 Start Sleep 的晚上
【6】API：只有公開那一項的人上榜（自己也一樣）、示範帳號標 demo、不回 user_id、錯的參數 422、
     名次變化跟上一個時段比
"""
import os
import sys
import tempfile
from datetime import date, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.stdout.reconfigure(encoding="utf-8")

from social import leaderboard as lb  # noqa: E402

failures = []


def check(name, got, want):
    ok = got == want
    print(f"  {'✓' if ok else '✗'} {name:<60} {got!r}" + ("" if ok else f"  期望 {want!r}"))
    if not ok:
        failures.append(name)


print("【1】時段範圍")
tue = date(2026, 11, 17)  # 週二
check("晚＝今天起床那一晚", lb.window("night", tue), ("2026-11-17", "2026-11-17"))
check("日＝昨天", lb.window("day", tue), ("2026-11-16", "2026-11-16"))
check("最近 7 天（週二也滿 7 天，不會週一週二整張空）", lb.window("week", tue), ("2026-11-11", "2026-11-17"))
check("上一個 7 天緊接在前面", lb.window("week", tue, back=1), ("2026-11-04", "2026-11-10"))
check("最近 30 天", lb.window("month", tue), ("2026-10-19", "2026-11-17"))
check("上一個 30 天", lb.window("month", tue, back=1), ("2026-09-19", "2026-10-18"))
check("最近 12 個月（365 天）", lb.window("year", tue), ("2025-11-18", "2026-11-17"))
check("時段的名字", [lb.PERIOD_LABELS[p] for p in ("week", "month", "year")], ["7 days", "30 days", "12 months"])


def night(d, late, bed=False, lights="2026-11-10T23:30:00"):
    return {"date": d, "adherence_minutes": None if late is None else (60 if late else 0),
            "lights_out_at": lights, "bed_start_at": f"{d}T23:00:00" if bed else None}


def person(key, behavior=(), wearable=(), daily=(), streak=(None, None), shares=True):
    return {"key": key, "shares": shares, "behavior": list(behavior), "wearable": list(wearable),
            "daily": list(daily), "streak": streak}


nov = [f"2026-11-{d:02d}" for d in range(1, 18)]

print("\n【2】月、年用平均")
many = person("many", wearable=[{"date": d, "duration_min": 400} for d in nov])      # 17 晚、每晚 6h40m
few = person("few", wearable=[{"date": d, "duration_min": 480} for d in nov[:10]])   # 10 晚、每晚 8h
ranked, below, _ = lb.rank([many, few], "sleep", "month", "2026-11-01", "2026-11-17")
check("晚數少但平均長的排第一", [k for k, *_ in ranked], ["few", "many"])
check("顯示的是平均", [s for _, _, _, s, _ in ranked], ["8h 0m", "6h 40m"])

print("\n【3】門檻與沒資料的晚上")
a = person("a", behavior=[night(nov[0], False), night(nov[1], False), night(nov[2], None)])
b = person("b", behavior=[night(nov[0], False), night(nov[1], True), night(nov[2], False)])
ranked, below, _ = lb.rank([a, b], "on_time", "week", "2026-11-01", "2026-11-03")
check("a 只有 2 晚有資料（第 3 晚沒測到）→ 不到週門檻 3", below, [("a", 2)])
check("b 3 晚 → 上榜，2 / 3", [(k, s) for k, _, _, s, _ in ranked], [("b", "2 / 3 nights")])
v, shown, n = lb.measure("on_time", a, "2026-11-01", "2026-11-03")
check("沒測到的晚上不算分母", shown, "2 / 2 nights")

print("\n【4】同分並列；Steady 越小越前")
p1 = person("p1", wearable=[{"date": nov[0], "duration_min": 420}])
p2 = person("p2", wearable=[{"date": nov[0], "duration_min": 420}])
p3 = person("p3", wearable=[{"date": nov[0], "duration_min": 300}])
ranked, _, _ = lb.rank([p3, p1, p2], "sleep", "night", nov[0], nov[0])
check("並列：1, 1, 3", [(k, r) for k, r, *_ in ranked], [("p1", 1), ("p2", 1), ("p3", 3)])
tight = person("tight", behavior=[night(d, False, lights=f"{d}T23:{m:02d}:00") for d, m in zip(nov[:3], (0, 5, 10))])
loose = person("loose", behavior=[night(d, False, lights=f"{d}T{h}:00:00") for d, h in zip(nov[:3], (21, 23, "01"))])
loose["behavior"][2]["lights_out_at"] = f"{nov[2]}T01:00:00"
ranked, _, _ = lb.rank([loose, tight], "steady", "week", nov[0], nov[2])
check("時刻越集中越前", [k for k, *_ in ranked], ["tight", "loose"])
s0 = person("zero", streak=(0, 3))
s5 = person("five", streak=(5, 5))
ranked, below, _ = lb.rank([s0, s5], "streak", "now", "x", "x")
check("連續 0 晚不排名次、列在下面", ([k for k, *_ in ranked], below), (["five"], [("zero", 0)]))

print("\n【5】Score 只算有按 Start Sleep 的晚上")
sc = person("sc", behavior=[night(nov[0], False, bed=True), night(nov[1], False, bed=False)],
            wearable=[{"date": nov[0], "final_score": 70}, {"date": nov[1], "final_score": 95}])
v, shown, n = lb.measure("score", sc, nov[0], nov[1])
check("沒按的那晚（95）不算", (shown, n), ("70", 1))

print("\n【5b】Chill：平均壓力越低越前；沒讀數的天不算")
calm = person("calm")
calm["stress"] = {nov[0]: 20, nov[1]: 30, nov[2]: None}
tense = person("tense")
tense["stress"] = {nov[0]: 50, nov[1]: 60, nov[2]: 40}
ranked, below, _ = lb.rank([tense, calm], "chill", "week", nov[0], nov[2])
check("None 那天不算進平均也不算天數（tense 3 天上榜、平均 50）", [(k, s, n) for k, _, _, s, n in ranked],
      [("tense", "50 avg", 3)])
check("calm 只有 2 天 → 不到 7 天榜的門檻 3", below, [("calm", 2)])
ranked, _, _ = lb.rank([tense, calm], "chill", "day", nov[0], nov[0])
check("單日：越低越前", [(k, s) for k, _, _, s, _ in ranked], [("calm", "20 avg"), ("tense", "50 avg")])
check("第一名稱號", lb.METRICS["chill"]["title"], "Most chill")
check("步數、壓力數「天」，其他數「晚」", [lb.unit(m) for m in ("steps", "chill", "sleep", "on_time", "streak")],
      ["day", "day", "night", "night", "night"])

print("\n【6】API")
tmp = tempfile.mkdtemp()
os.environ.pop("SONNAP_DB_URL", None)
import db  # noqa: E402
db.DB_PATH = Path(tmp) / "lb.db"
db.init_db()
import main  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

client = TestClient(main.app)
me = db.create_user("Me")
pal = db.create_user("Pal")
shy = db.create_user("Shy")
demo = db.create_user("Robo (demo)", study_cohort=db.DEMO_COHORT)
for u in (pal, shy, demo):
    db.add_friendship(me, u)
today = date.today()
for u, mins in ((me, 400), (pal, 450), (shy, 500), (demo, 420)):
    db.upsert_wearable_nightly(u, today.isoformat(), "health_connect",
                               {"duration_min": mins, "sleep_start_time": f"{today}T00:00:00+08:00",
                                "wake_time": f"{today}T07:00:00+08:00"})
    db.upsert_wearable_nightly(u, (today - timedelta(days=1)).isoformat(), "health_connect",
                               {"duration_min": 900 - mins, "sleep_start_time": f"{today}T00:00:00+08:00",
                                "wake_time": f"{today}T07:00:00+08:00"})
db.set_friend_sharing(shy, items={"sleep_duration": False})  # Shy 把睡多久關掉了
r = client.get("/friends/leaderboard", params={"user_id": me, "metric": "sleep", "period": "night"})
j = r.json()
check("200", r.status_code, 200)
check("沒公開的人不上榜（Shy 睡最久也不在）", [e["display_name"] for e in j["entries"]],
      ["Pal", "Robo (demo)", "Me"])
check("示範帳號標 demo", [e["demo"] for e in j["entries"]], [False, True, False])
check("我的卡：第 3 名", (j["me"]["status"], j["me"]["rank"]), ("ranked", 3))
check("名次變化跟昨晚比（昨晚 Me 第 1 → 今天第 3 ＝ −2）",
      [e["change"] for e in j["entries"]], [2, 0, -2])
check("第一名稱號", j["title"], "Sleepyhead")
check("回應帶單位：睡眠數晚", j["unit"], "night")
check("回應裡沒有任何 user_id", any(u in r.text for u in (me, pal, shy, demo)), False)
db.set_friend_sharing(me, items={"sleep_duration": False})
j = client.get("/friends/leaderboard", params={"user_id": me, "metric": "sleep", "period": "night"}).json()
check("自己沒公開 → 自己也不上榜，卡上說要打開哪一項", (j["me"]["status"], j["me"]["share_item"]),
      ("not_sharing", "sleep_duration"))
check("不認得的指標 422",
      client.get("/friends/leaderboard", params={"user_id": me, "metric": "deep"}).status_code, 422)
check("不適用的時段 422（Streak 沒有年）",
      client.get("/friends/leaderboard", params={"user_id": me, "metric": "streak", "period": "year"}).status_code,
      422)
check("沒給時段 → 那個指標的第一個時段",
      client.get("/friends/leaderboard", params={"user_id": me, "metric": "steady"}).json()["period"], "week")
check("/friends/leaderboard 不會被當成邀請碼",
      client.get("/friends/leaderboard", params={"user_id": me}).status_code, 200)

print()
if failures:
    print(f"✗ {len(failures)} 條沒過：{failures}")
    sys.exit(1)
print("全部通過")
