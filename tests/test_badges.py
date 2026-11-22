"""
tests/test_badges.py —— 徽章（game/badges.py，2026-11-22 獎盃架）

守的東西（每一條壞掉都不會報錯）：

  【1】「做到了」照用既有判定：準時、連續、挑戰本身是同一支函式（不是另寫一份）
  【2】紅線 5：熬夜、睡不好的晚上不會讓睡眠那幾個系列前進
  【3】連續要沿日曆日走：中間缺一晚就斷
  【4】Bounce back：熬夜的**隔天**準時才算；前一晚沒資料不算
  【5】Phone down／Steady week 的門檻是挑戰定義裡的，不是這裡寫的
  【6】Podium：榜上不到 3 人不算；沒公開那一項的人不上榜
  【7】API：拿到的日期是跨過門檻那一晚；領 XP 一級一次；422／409／404 分得開
  【8】拿到的不收回：資料改正之後次數變少，那一級還在、日期不變
  【9】習慣只收數字；勾的比總數多 422；同一天重送覆寫
  【10】助理：只有答出來才算；一天問幾題都只算一天
  【11】舊版 App 的 badges 三個照樣在，而且從新系列推出來
  【12】退出即刪除：三張新表跟著清掉；新表沒有存內容的欄位

⚠️ 全程使用**暫存資料庫**，不會碰到 data/sonnap.db；助理不打真的 API。

執行：python tests/test_badges.py
"""
import sqlite3
import sys
import tempfile
from datetime import date, timedelta
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import db
TMP = Path(tempfile.mkdtemp()) / "test_badges.db"
db.DB_PATH = TMP

import main
from behavior import challenges
from fastapi.testclient import TestClient
from game import badges

client = TestClient(main.app)
fails = []


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<58} {extra}")
    if not cond:
        fails.append(label)


def section(title):
    print()
    print("=" * 78)
    print(title)
    print("=" * 78)


DEFS = {c["kind"]: c for c in db.DEFAULT_CHALLENGES}


def row(d, minutes, **extra):
    return {"date": d, "adherence_minutes": minutes, **extra}


# ═══════════════════════════════════════════════════════════════════
section("【1】照用既有判定（同一支函式，不是另寫一份）")
# ═══════════════════════════════════════════════════════════════════
ok("準時＝behavior.challenges.night_achieved", badges.night_achieved is challenges.night_achieved)
ok("連續＝behavior.challenges.current_streak", badges.current_streak is challenges.current_streak)
ok("挑戰本身＝evaluate_challenge", badges.evaluate_challenge is challenges.evaluate_challenge)
src = (ROOT / "game" / "badges.py").read_text(encoding="utf-8")
ok("badges.py 沒有自己寫準時的分鐘門檻", "adherence_minutes" not in src.replace("adherence_minutes\"", ""))
ok("每個系列 5 級、由小到大",
   all(len(s["thresholds"]) == 5 and list(s["thresholds"]) == sorted(set(s["thresholds"]))
       for s in badges.SERIES))
ok("13 個系列、id 不重複", len(badges.SERIES) == 13 and len(badges.SERIES_BY_ID) == 13)
ok("每一級的 XP 都有", len(badges.TIER_XP) == 5)

# ═══════════════════════════════════════════════════════════════════
section("【2】紅線 5：差的晚上不讓睡眠系列前進")
# ═══════════════════════════════════════════════════════════════════
late = [row(f"2026-09-{i:02d}", 120, is_late=1, up_on_time=False) for i in range(1, 11)]
bad = [{"date": f"2026-09-{i:02d}", "final_quality": "Bad"} for i in range(1, 11)]
c = badges.compute({"behavior": late, "wearable": bad, "challenges": DEFS, "today": "2026-10-01"})
sleep_ids = [s["series_id"] for s in badges.SERIES if s["group"] == "sleep"]
ok("熬夜又睡不好的 10 晚：睡眠系列全部 0", all(c[s]["value"] == 0 for s in sleep_ids),
   str({s: c[s]["value"] for s in sleep_ids}))
good = [row(f"2026-09-{i:02d}", -10, up_on_time=True) for i in range(1, 11)]
c = badges.compute({"behavior": good, "wearable": [{"date": r["date"], "final_quality": "Good"} for r in good],
                    "challenges": DEFS, "today": "2026-10-01"})
ok("準時的 10 晚：Lights out 10、Good night 10、Full circle 10",
   (c["lights_out"]["value"], c["good_night"]["value"], c["full_circle"]["value"]) == (10, 10, 10))
ok("連續 10 晚：On a roll 拿到 3、7 兩級，日期是第 3、第 7 晚",
   c["on_a_roll"]["reached"] == {3: "2026-09-03", 7: "2026-09-07"}, str(c["on_a_roll"]["reached"]))
none = [row(f"2026-09-{i:02d}", None) for i in range(1, 11)]
c = badges.compute({"behavior": none, "challenges": DEFS, "today": "2026-10-01"})
ok("只有資料、沒有判定（adherence 是 None）：一個都不前進",
   all(c[s]["value"] == 0 for s in sleep_ids))

# ═══════════════════════════════════════════════════════════════════
section("【3】連續要沿日曆日走")
# ═══════════════════════════════════════════════════════════════════
gap = [row("2026-09-10", -5), row("2026-09-12", -5), row("2026-09-13", -5)]
reached = badges.streak_reached(gap)
ok("09-10 準時、09-11 沒資料、09-12、13 準時 → 最長 2", max(reached) == 2, str(reached))

# ═══════════════════════════════════════════════════════════════════
section("【4】Bounce back")
# ═══════════════════════════════════════════════════════════════════
rows = [row("2026-09-01", 120, is_late=1), row("2026-09-02", -10),
        row("2026-09-03", 120, is_late=1), row("2026-09-05", -10),
        row("2026-09-06", 20, is_late=0), row("2026-09-07", -10)]
ok("熬夜的隔天準時算一次；隔一天、前一晚沒熬夜都不算",
   badges.hits_bounce_back(rows) == ["2026-09-02"], str(badges.hits_bounce_back(rows)))
ok("前一晚 is_late 是 None（後端沒判）不算",
   badges.hits_bounce_back([row("2026-09-01", None, is_late=None), row("2026-09-02", -10)]) == [])

# ═══════════════════════════════════════════════════════════════════
section("【5】門檻在挑戰定義裡")
# ═══════════════════════════════════════════════════════════════════
pib = [row("2026-09-01", 0, phone_in_bed_minutes=20), row("2026-09-02", 0, phone_in_bed_minutes=45),
       row("2026-09-03", 0, phone_in_bed_minutes=None)]
ok("滑 20 分算、45 分不算、沒按 Start Sleep 不算",
   badges.hits_phone_down(pib, DEFS["phone_in_bed"]) == ["2026-09-01"])
looser = {**DEFS["phone_in_bed"], "target_value": 60.0}
ok("把挑戰門檻改成 60，45 分就算（證明門檻不是寫在 badges.py）",
   badges.hits_phone_down(pib, looser) == ["2026-09-01", "2026-09-02"])

span = DEFS["consistency"]["window_days"]
start = date.fromordinal((date(2026, 9, 1).toordinal() // span + 1) * span)
steady = [row((start + timedelta(days=i)).isoformat(), -5,
              lights_out_at=f"{(start + timedelta(days=i - 1)).isoformat()}T23:{10 + i:02d}:00+08:00")
          for i in range(span)]
hits = badges.hits_steady_week(steady, DEFS["consistency"], (start + timedelta(days=30)).isoformat())
ok("一整週作息收斂 → 1 週，日期是窗格最後一天",
   hits == [(start + timedelta(days=span - 1)).isoformat()], str(hits))
ok("那一週還沒結束不算",
   badges.hits_steady_week(steady, DEFS["consistency"], (start + timedelta(days=span - 1)).isoformat()) == [])

# ═══════════════════════════════════════════════════════════════════
section("【6】Podium")
# ═══════════════════════════════════════════════════════════════════
SUN = "2026-09-13"   # 週日
week = [(date(2026, 9, 7) + timedelta(days=i)).isoformat() for i in range(7)]


def person(key, on_time_nights, share=True):
    rows = [row(d, -10 if i < on_time_nights else 90) for i, d in enumerate(week)]
    return {"key": key, "shares_by": {m: share for m in badges.PODIUM_METRICS}, "behavior": rows}


ok("2026-09-13 是週日", date.fromisoformat(SUN).weekday() == 6)
three = [person("me", 7), person("a", 3), person("b", 1)]
ok("三個人、我第一 → 算", badges.on_podium(three, "me", SUN))
ok("只有兩個人 → 不算", not badges.on_podium(three[:2], "me", SUN))
four = [person("me", 0), person("a", 7), person("b", 6), person("c", 5)]
ok("四個人、我最後 → 不算", not badges.on_podium(four, "me", SUN))
hidden = [person("me", 7, share=False), person("a", 3), person("b", 1), person("c", 2)]
ok("我沒公開那一項 → 不上榜、不算", not badges.on_podium(hidden, "me", SUN))
ok("週日清單從第一個週日開始",
   badges.sundays_between("2026-09-08", "2026-09-27") == ["2026-09-13", "2026-09-20", "2026-09-27"])

# ═══════════════════════════════════════════════════════════════════
section("【7】API：日期、領 XP、錯誤碼")
# ═══════════════════════════════════════════════════════════════════
db.init_db(TMP)
db.seed_challenges(TMP)
uid = client.post("/users", json={"display_name": "Badge", "target_bedtime": "23:30"}).json()["user_id"]
for d in range(1, 6):
    r = client.post("/nightly", json={"user_id": uid, "lights_out_at": f"2026-09-0{d}T23:10:00+08:00"})
    assert r.status_code == 201, r.text
g = client.get(f"/game?user_id={uid}").json()
lo = next(s for s in g["badge_series"] if s["series_id"] == "lights_out")
ok("準時 5 晚：Lights out 第 2 級", lo["level"] == 2, str(lo["level"]))
ok("第 2 級的日期是第 5 晚（不是今天）", lo["tiers"][1]["earned_on"] == "2026-09-06", str(lo["tiers"][1]))
ok("下一級寫進度 5 / 15", lo["next"] == {"tier": 3, "threshold": 15, "value": 5}, str(lo["next"]))
ok("記進 badges_earned", any(r["series_id"] == "lights_out" and r["tier"] == 2
                             for r in db.get_badges_earned(uid)))
ids = [c["achievement_id"] for c in g["claimable_badges"]]
ok("可以領 Lights out 1、2 與 On a roll 1", {"badge:lights_out:1", "badge:lights_out:2",
                                           "badge:on_a_roll:1"} <= set(ids), str(ids))
ok("分區有三個", [x["group"] for x in g["badge_groups"]] == ["sleep", "friends", "habits"])
xp0 = g["xp_total"]
r = client.post("/game/claim", json={"user_id": uid, "badge": "badge:lights_out:1"})
ok("領第 1 級 → 201、+10 XP", r.status_code == 201 and r.json()["xp_total"] == xp0 + 10, r.text)
ok("再領一次 → 409", client.post("/game/claim", json={"user_id": uid, "badge": "badge:lights_out:1"})
   .status_code == 409)
ok("還沒拿到的第 3 級 → 422", client.post("/game/claim", json={"user_id": uid, "badge": "badge:lights_out:3"})
   .status_code == 422)
ok("不存在的系列 → 404", client.post("/game/claim", json={"user_id": uid, "badge": "badge:nope:1"})
   .status_code == 404)
ok("第 6 級 → 404", client.post("/game/claim", json={"user_id": uid, "badge": "badge:lights_out:6"})
   .status_code == 404)
ok("兩個都送 → 422", client.post("/game/claim", json={"user_id": uid, "badge": "badge:lights_out:2",
                                                     "challenge_id": "on_time_tonight"}).status_code == 422)
ok("兩個都沒送 → 422", client.post("/game/claim", json={"user_id": uid}).status_code == 422)
g = client.get(f"/game?user_id={uid}").json()
ok("XP 來源有 badge_rewards 10", g["xp_sources"]["badge_rewards"] == 10, str(g["xp_sources"]))
ok("領過的那一級不再出現在 claimable_badges",
   "badge:lights_out:1" not in [c["achievement_id"] for c in g["claimable_badges"]])
ok("挑戰獎勵照舊用 challenge_id 領（舊版 App）",
   client.post("/game/claim", json={"user_id": uid, "challenge_id": "streak_nights"}).status_code in (201, 409))

# ═══════════════════════════════════════════════════════════════════
section("【8】拿到的不收回")
# ═══════════════════════════════════════════════════════════════════
conn = sqlite3.connect(TMP)
conn.execute("UPDATE nightly_behavior SET adherence_minutes = 120, is_late = 1 "
             "WHERE user_id = ? AND date IN ('2026-09-05', '2026-09-06')", (uid,))
conn.commit()
conn.close()
g = client.get(f"/game?user_id={uid}").json()
lo = next(s for s in g["badge_series"] if s["series_id"] == "lights_out")
ok("改正後只剩 3 晚準時（value 3）", lo["value"] == 3, str(lo["value"]))
ok("第 2 級還在、日期還是 09-06", lo["level"] == 2 and lo["tiers"][1]["earned_on"] == "2026-09-06",
   str(lo["tiers"][1]))
ok("下一級的進度照實寫 3", lo["next"]["value"] == 3)

# ═══════════════════════════════════════════════════════════════════
section("【9】習慣只收數字")
# ═══════════════════════════════════════════════════════════════════
post = lambda **b: client.post("/habits/day", json={"user_id": uid, **b})
ok("勾 3 / 3 → 200", post(date="2026-09-03", checked=3, total=3).status_code == 200)
ok("勾的比總數多 → 422", post(date="2026-09-04", checked=4, total=3).status_code == 422)
ok("日期格式錯 → 422", post(date="09/04", checked=1, total=3).status_code == 422)
ok("未來的日期 → 422", post(date="2099-01-01", checked=1, total=1).status_code == 422)
post(date="2026-09-04", checked=2, total=3)
g = client.get(f"/game?user_id={uid}").json()
hb = next(s for s in g["badge_series"] if s["series_id"] == "habits")
ok("全部勾完的那天才算（1 天）", hb["value"] == 1, str(hb["value"]))
post(date="2026-09-03", checked=1, total=3)
ok("同一天重送覆寫（取消勾選算得回去）",
   [h["checked"] for h in db.get_habit_days(uid)] == [1, 2])
ok("但已經拿到的第 1 級不收回",
   next(s for s in client.get(f"/game?user_id={uid}").json()["badge_series"]
        if s["series_id"] == "habits")["level"] == 1)

# ═══════════════════════════════════════════════════════════════════
section("【10】助理：只有答出來才算，算的是天數")
# ═══════════════════════════════════════════════════════════════════
from ai import chat as chat_engine
_key, _ans = chat_engine.key_available, chat_engine.answer_question
chat_engine.key_available = lambda: True
try:
    def boom(*a, **k):
        raise chat_engine.ChatUnavailable("no")
    chat_engine.answer_question = boom
    r = client.post("/chat", json={"user_id": uid, "message": "How did I sleep?"})
    ok("答不出來（503）→ 不記", r.status_code == 503 and db.get_game_activity(uid, "assistant") == [])
    chat_engine.answer_question = lambda *a, **k: {
        "answer": "ok", "headline": "ok", "why": None, "tips": [], "link": None}
    for _ in range(3):
        client.post("/chat", json={"user_id": uid, "message": "How did I sleep?"})
    act = db.get_game_activity(uid, "assistant")
    ok("同一天答了 3 題 → 一列、count 3", len(act) == 1 and act[0]["count"] == 3, str(act))
    a = next(s for s in client.get(f"/game?user_id={uid}").json()["badge_series"]
             if s["series_id"] == "assistant")
    ok("徽章算 1 天，不是 3", a["value"] == 1, str(a["value"]))
finally:
    chat_engine.key_available, chat_engine.answer_question = _key, _ans

# ═══════════════════════════════════════════════════════════════════
section("【11】舊版 App 的 badges")
# ═══════════════════════════════════════════════════════════════════
legacy = {b["badge_id"]: b["earned"] for b in g["badges"]}
ok("三個舊徽章都在", set(legacy) == {"first_on_time", "on_time_x5", "good_sleep"}, str(legacy))
ok("first_on_time / on_time_x5 跟著 Lights out 第 1、2 級",
   legacy["first_on_time"] and legacy["on_time_x5"])
ok("沒有 Good 的晚上 → good_sleep 沒拿到", legacy["good_sleep"] is False)

# ═══════════════════════════════════════════════════════════════════
section("【12】退出即刪除；新表不存內容")
# ═══════════════════════════════════════════════════════════════════
db.bump_game_activity(uid, "visit", "2026-09-05")
conn = sqlite3.connect(TMP)
cols = {t: [r[1] for r in conn.execute(f"PRAGMA table_info({t})")]
        for t in ("badges_earned", "game_activity", "habit_days")}
conn.close()
ok("habit_days 只有數字欄位", cols["habit_days"] == ["user_id", "date", "checked", "total", "updated_at"],
   str(cols["habit_days"]))
ok("game_activity 只有次數", cols["game_activity"] == ["user_id", "kind", "date", "count"],
   str(cols["game_activity"]))
client.delete(f"/users/{uid}")
conn = sqlite3.connect(TMP)
left = {t: conn.execute(f"SELECT COUNT(*) FROM {t} WHERE user_id = ?", (uid,)).fetchone()[0]
        for t in ("badges_earned", "game_activity", "habit_days")}
conn.close()
ok("三張新表都沒有殘留", left == {"badges_earned": 0, "game_activity": 0, "habit_days": 0}, str(left))

print()
if fails:
    print(f"✗ {len(fails)} 條沒過：")
    for f in fails:
        print(f"    - {f}")
    sys.exit(1)
print("✓ 全部通過")
