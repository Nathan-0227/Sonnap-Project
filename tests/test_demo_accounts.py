"""
tests/test_demo_accounts.py —— 成果展示範帳號不得污染真實資料

  【1】示範帳號的夜數比本人多時，resolve_phone_account() 仍然認得本人
       （含反向對照：確認示範帳號真的比較多，否則這條會假性通過）
  【2】compare_night_sources 不帶暱稱時不讀示範帳號
  【3】示範帳號都加成本人的好友，好友頁看得到，且暱稱都帶 (demo)
  【4】重跑 --create 不會越長越多；--remove 清乾淨，本人的資料一筆不少
  【5】每晚的達成度跟手機上傳走同一個函式（adherence.evaluate_night）
  【6】手錶資料（2026-11-16 起也產生）：source 一律 "demo"、分數由既有評分器算、
       API 重排的睡眠階段跟評分時同一份（demo_sleep 是決定性的）、白天資料有寫
  【7】動態牆：每張卡帶自己選的場景與寵物；11-19 起示範帳號分享全開（每人都有階梯、時刻、
       起床自評），沒有攝影機的人照樣沒有攝影機資料；回應裡沒有任何 user_id
  【9】🐾（2026-11-19 使用者同意）：Mia、Leo 在最後一天各拜訪本人一次；重建不累積；
       --remove 之後本人收到的拜訪一筆不剩；回傳的摘要裡沒有 user_id
  【8】Garmin 原始檔是本人的：示範帳號（沒有 garmin 來源）的「昨天」一次都不讀它，
       整天心率／壓力線／醒著心率是 null；有 garmin 來源的帳號照讀（反向對照）

⚠️ 全程使用暫存資料庫。執行：python tests/test_demo_accounts.py
"""
import sys
import tempfile
from datetime import datetime
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import db
TMP = Path(tempfile.mkdtemp()) / "test_demo_accounts.db"
db.DB_PATH = TMP

import compare_night_sources
import demo_accounts
from behavior import adherence

fails = []


def check(label, got, want):
    good = got == want
    print(f"  {'✓' if good else '✗'} {label}" + ("" if good else f"：得到 {got!r}，應為 {want!r}"))
    if not good:
        fails.append(label)


db.init_db(TMP)

# 本人：5 晚真實資料（比任何一個示範帳號都少）
me = db.create_user("Nathan", db_path=TMP)
for d in range(1, 6):
    night = adherence.evaluate_night(f"2026-11-0{d}T23:40:00+08:00", "23:30")
    db.upsert_nightly_behavior(me, night["date"], night["target_bedtime"],
                               night["lights_out_at"], night["adherence_minutes"],
                               night["is_late"], db_path=TMP)

from datetime import date, timedelta
rows = demo_accounts.create_all(nights=21, end=date(2026, 11, 6), db_path=TMP)

print("【1】示範帳號不會被當成手機帳號")
conn = db.connect(TMP)
counts = {r["display_name"]: r["n"] for r in conn.execute(
    "SELECT u.display_name, COUNT(n.date) AS n FROM users u "
    "LEFT JOIN nightly_behavior n ON n.user_id = u.user_id GROUP BY u.user_id")}
conn.close()
check("反向對照：至少一個示範帳號的夜數比本人多",
      max(v for k, v in counts.items() if k != "Nathan") > counts["Nathan"], True)
picked, info = db.resolve_phone_account(TMP)
check("resolve_phone_account 選中本人", picked == me, True)
check("理由是 ok", info["reason"], "ok")

print("【2】compare_night_sources 不讀示範帳號")
loaded = compare_night_sources.load_behavior(TMP)
check("只讀到本人那 5 晚", len(loaded), 5)

print("【3】好友與暱稱")
friends = set(db.list_friend_ids(me, TMP))
demo_ids = {uid for uid, _ in demo_accounts.demo_users(TMP)}
check("4 個示範帳號", len(demo_ids), 4)
check("全部是本人的好友", friends == demo_ids, True)
check("暱稱都帶 (demo)", all(n.endswith("(demo)") for _, n in demo_accounts.demo_users(TMP)), True)
check("每個都有邀請碼", all(r["code"] for r in rows), True)


def visits_to_me():
    c = db.connect(TMP)
    try:
        return sorted((u["display_name"], v["day"], v["kind"]) for v in c.execute(
            "SELECT sender_id, day, kind FROM friend_visits WHERE receiver_id = ?", (me,))
            for u in [c.execute("SELECT display_name FROM users WHERE user_id = ?",
                                (v["sender_id"],)).fetchone()])
    finally:
        c.close()


print("【9】🐾 給本人")
check("Mia、Leo 在最後一天各拜訪一次", visits_to_me(),
      [("Leo (demo)", "2026-11-06", "sleep_well"), ("Mia (demo)", "2026-11-06", "pet")])
check("摘要裡沒有 user_id", any("uid" in r or any(v in str(r) for v in demo_ids) for r in rows), False)

print("【4】重建不累積、刪除不傷本人")
demo_accounts.create_all(nights=21, end=date(2026, 11, 6), db_path=TMP)
check("重建後仍是 4 個", len(demo_accounts.demo_users(TMP)), 4)
check("本人的好友仍是 4 個（舊的那批已被清掉）", len(db.list_friend_ids(me, TMP)), 4)
check("【9】重建後本人收到的拜訪仍是 2 筆", len(visits_to_me()), 2)
check("刪除回報 4 個", demo_accounts.remove_all(TMP), 4)
check("本人的 5 晚還在", len(db.get_nightly_behavior(me, days=3650, db_path=TMP)), 5)
check("本人沒有好友殘留", db.list_friend_ids(me, TMP), [])
check("【9】--remove 之後本人收到的拜訪一筆不剩", visits_to_me(), [])
conn = db.connect(TMP)
orphans = conn.execute(
    "SELECT COUNT(*) AS n FROM nightly_behavior WHERE user_id NOT IN (SELECT user_id FROM users)"
).fetchone()["n"]
conn.close()
check("沒有孤兒的每晚資料", orphans, 0)

print("【5】達成度與 evaluate_night 一致")
demo_accounts.create_all(nights=21, end=date(2026, 11, 6), db_path=TMP)
uid = demo_accounts.demo_users(TMP)[0][0]
mismatch = 0
for r in db.get_nightly_behavior(uid, days=3650, db_path=TMP):
    again = adherence.evaluate_night(r["lights_out_at"], r["target_bedtime"])
    mismatch += (again["adherence_minutes"], again["is_late"], again["date"]) != \
                (r["adherence_minutes"], bool(r["is_late"]), r["date"])
check("每一晚都對得上", mismatch, 0)

print("【6】手錶資料是示範來源、分數走既有評分器")
import demo_sleep  # noqa: E402
conn = db.connect(TMP)
sources = {r["source"] for r in conn.execute(
    "SELECT DISTINCT source FROM wearable_nightly WHERE user_id IN "
    "(SELECT user_id FROM users WHERE study_cohort = ?)", (db.DEMO_COHORT,)).fetchall()}
daily = conn.execute(
    "SELECT COUNT(*) AS n FROM garmin_daily WHERE user_id IN "
    "(SELECT user_id FROM users WHERE study_cohort = ?)", (db.DEMO_COHORT,)).fetchone()["n"]
conn.close()
check("示範帳號的手錶資料 source 只有 demo", sources, {"demo"})
check("白天資料每人 21 天", daily, 4 * 21)
rows_w = db.get_wearable_nightly(uid, days=3650, db_path=TMP)
check("每晚都有手錶資料", len(rows_w), 21)
check("每晚都有分數與等級", all(r["final_score"] is not None and r["final_quality"] for r in rows_w), True)
bad = 0
for r in rows_w:
    blk = demo_sleep.stages_block(r)
    segs = blk["segments"] if blk else []
    asleep = sum((datetime.fromisoformat(x["end"]) - datetime.fromisoformat(x["start"])).total_seconds() / 60
                 for x in segs if x["stage"] != "awake")
    bad += (not segs or round(asleep) != round(r["duration_min"])
            or segs[0]["start"] != r["sleep_start_time"]
            or demo_sleep.awake_count(segs) != r["awake_count"])
check("重排的階梯跟存下來的睡眠分鐘、入睡時刻、醒來次數一致", bad, 0)
check("同一晚重排兩次一模一樣", demo_sleep.stages_block(rows_w[-1]) == demo_sleep.stages_block(rows_w[-1]), True)

print("【7】動態牆")
import main  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
# 動態牆只看最近 7 天 → 這裡重建到今天為止
demo_accounts.create_all(nights=21, db_path=TMP)
client = TestClient(main.app, raise_server_exceptions=False)
r = client.get("/friends/feed", params={"user_id": me})
check("200", r.status_code, 200)
cards = r.json()["cards"]
latest = {}
for c in cards:
    if not c["mine"]:
        latest.setdefault(c["display_name"], c)
check("4 位朋友都有卡", len(latest), 4)
check("各自的場景", {n: c["scene"] for n, c in latest.items()},
      {"Mia (demo)": "lake", "Leo (demo)": "campfire", "Yuki (demo)": "rooftop", "Ken (demo)": "treehouse"})
mia = latest["Mia (demo)"]["items"]
check("Mia：有階梯", bool(mia.get("stages", {}).get("segments")), True)
check("Mia（11-19 起全開、時刻準確）：階梯兩端有時刻、有放下手機的時刻",
      (all(mia["stages"].get(k) for k in ("start", "end")), "phone_down_time" in mia), (True, True))
check("每個人都有起床自評（1–5）",
      {n: (c["items"].get("morning_rating") or {}).get("rested") in (1, 2, 3, 4, 5) for n, c in latest.items()},
      {n: True for n in latest})
leo = latest["Leo (demo)"]["items"]
check("Leo（準確時刻）：階梯兩端有時刻", all(leo["stages"].get(k) for k in ("start", "end")), True)
check("Ken（11-19 起全開）：也有階梯", "stages" in latest["Ken (demo)"]["items"], True)
moves = {n: c["items"].get("camera_moves") for n, c in latest.items()}
check("Mia／Leo／Yuki 有每小時動幾次（預設分享）、Ken 沒有攝影機", 
      ({n: isinstance(v, (int, float)) for n, v in moves.items()}),
      {"Mia (demo)": True, "Leo (demo)": True, "Yuki (demo)": True, "Ken (demo)": False})
# 完整頁的區塊（2026-11-16）：整晚的心率線、攝影機時間軸（自己一個開關、預設關）
mia_hr = latest["Mia (demo)"]["items"].get("sleeping_hr") or {}
check("Mia：心率有整晚的線（≥ 30 點）", len(mia_hr.get("curve") or []) >= 30, True)
check("Mia：心率線只給第幾分鐘，不給時刻",
      all(set(p) == {"m", "v"} and isinstance(p["m"], (int, float)) for p in mia_hr.get("curve") or []), True)
tl = latest["Mia (demo)"]["items"].get("camera_timeline") or {}
check("Mia：攝影機時間軸有光柱、總次數、動了多久、跟平常比",
      (len(tl.get("points") or []) >= 30, isinstance(tl.get("total"), int),
       isinstance(tl.get("moving_sec"), int), isinstance(tl.get("usual"), str)),
      (True, True, True, True))
check("攝影機時間軸只給第幾分鐘，不給時刻",
      any("T" in str(p.get("m")) for p in tl.get("points") or []), False)
check("Ken 沒有攝影機：全開也沒有攝影機時間軸（不編）", "camera_timeline" in latest["Ken (demo)"]["items"], False)
# 排行榜 Chill：示範帳號每天有平均壓力（腳本產生），壓力多的人平均高
_since = (date.today() - timedelta(days=30)).isoformat()
_avg = {}
for _uid, _name in demo_accounts.demo_users(TMP):
    _vals = [r["stress_avg"] for r in db.list_garmin_daily(_uid, _since, date.today().isoformat(), db_path=TMP)
             if r.get("stress_avg") is not None]
    _avg[_name] = sum(_vals) / len(_vals) if _vals else None
check("每個示範帳號都有平均壓力", all(v is not None for v in _avg.values()), True)
check("壓力設定最高的 Yuki 平均比最低的 Mia 高", _avg["Yuki (demo)"] > _avg["Mia (demo)"], True)
devs = {n: [d["name"] for d in (c["items"].get("devices") or [])] for n, c in latest.items()}
check("設備（預設分享）：手錶、攝影機、手機都寫型號；沒有攝影機的就沒有那一台",
      (devs["Mia (demo)"], devs["Ken (demo)"]),
      (["Garmin Forerunner 265", "Tapo C210", "Google Pixel 8"],
       ["Garmin Vivoactive 5", "Samsung Galaxy A54"]))
all_ids = {me} | {u for u, _ in demo_accounts.demo_users(TMP)}
check("回應裡沒有任何 user_id", any(u in r.text for u in all_ids), False)
seg_iso = any("T" in str(s.get("from", "")) for c in cards for s in (c["items"].get("stages") or {}).get("segments", []))
check("每一段只給第幾分鐘，不給 ISO 時刻", seg_iso, False)

print("【8】Garmin 原始檔只給本人讀")
calls = []
real_records = main._garmin_records
main._garmin_records = lambda: calls.append(1) or []
try:
    demo_uid = demo_accounts.demo_users(TMP)[0][0]
    y = main.yesterday_block(demo_uid, date.today().isoformat())
    check("示範帳號有白天資料（步數）", y is not None and y["steps"] is not None, True)
    check("示範帳號的昨天一次都沒讀原始檔", len(calls), 0)
    check("整天心率／壓力線／醒著心率都是 null",
          [y["heart_rate"], y["stress_curve"], y["awake_heart_rate"]], [None, None, None])
    # 反向對照：本人有一晚 garmin 來源 → 會去讀
    db.upsert_wearable_nightly(me, "2026-11-01", "garmin", {"duration_min": 400}, db_path=TMP)
    db.upsert_garmin_daily(me, "2026-10-31", {"steps": 5000}, db_path=TMP)
    main.yesterday_block(me, "2026-11-01")
    check("有 garmin 來源的帳號照讀原始檔", len(calls) > 0, True)
finally:
    main._garmin_records = real_records

print()
print("【即時狀態】示範帳號（2026-11-19）")
# 模擬「即時狀態上線之前建的示範帳號」：分享設定裡把 live_status 關掉
for _uid, _ in demo_accounts.demo_users(TMP):
    db.set_friend_sharing(_uid, items={"live_status": False}, db_path=TMP)
noon = datetime(2026, 11, 25, 14, 0)
check("白天：Mia 睡著、Leo 起床了、Yuki／Ken 醒著（看時鐘）",
      demo_accounts.set_live_demo(now=noon, db_path=TMP),
      {"Ken (demo)": "awake", "Leo (demo)": "up", "Mia (demo)": "asleep", "Yuki (demo)": "awake"})
night = datetime(2026, 11, 25, 23, 45)
check("晚上：Leo 改成睡著（18:00 以後不能是 up）、Ken 過了 23:00 的目標",
      demo_accounts.set_live_demo(now=night, db_path=TMP),
      {"Ken (demo)": "past_bedtime", "Leo (demo)": "asleep", "Mia (demo)": "asleep", "Yuki (demo)": "awake"})
db.set_live_sleep_status(me, started_at="2026-11-25T23:00:00", db_path=TMP)
demo_accounts.set_live_demo(now=night, db_path=TMP)
check("--live 不碰本人的即時狀態", db.get_live_sleep_status(me, db_path=TMP)["started_at"],
      "2026-11-25T23:00:00")
seen = {f["display_name"]: f for f in client.get("/friends", params={"user_id": me}).json()["friends"]}
check("好友頁看得到示範帳號的即時狀態（分享全開含 live_status）",
      all(f["live_state"] is not None for f in seen.values()), True)

print("【送禮】--live 今天送本人 3 則（2026-11-22）")
gift_day = "2026-11-26"  # 23:45 加 6 小時＝隔天的起床日
check("Mia、Leo、Yuki 各送一則", demo_accounts.send_demo_gifts(now=night, db_path=TMP),
      {"Mia (demo)": "good_night", "Leo (demo)": "good_morning", "Yuki (demo)": "hugs"})
check("重跑不累積、不被一天一次擋住", demo_accounts.send_demo_gifts(now=night, db_path=TMP),
      {"Mia (demo)": "good_night", "Leo (demo)": "good_morning", "Yuki (demo)": "hugs"})
check("今天那 3 筆，日期是起床日", sorted(v for v in visits_to_me() if v[1] == gift_day),
      [("Leo (demo)", gift_day, "good_morning"), ("Mia (demo)", gift_day, "good_night"),
       ("Yuki (demo)", gift_day, "hugs")])
check("每種都是 town 認得的", all(k in demo_accounts.social_town.KINDS
                              for k in demo_accounts.DEMO_GIFTS.values()), True)

print("【衣服】示範帳號各穿一件、都是自己等級已經解鎖的（2026-11-22）")
import main  # noqa: E402
from game import inventory  # noqa: E402
_dressed = {n: (db.get_game_state(u, db_path=TMP) or {}).get("equipped_item_id")
            for u, n in demo_accounts.demo_users(TMP)}
check("--create 之後四個人都穿上了", _dressed, demo_accounts.DEMO_OUTFITS)
_real_path = db.DB_PATH
db.DB_PATH = TMP  # main 的等級算法走預設資料庫 → 暫時指過來
try:
    _locked = [n for u, n in demo_accounts.demo_users(TMP)
               if demo_accounts.DEMO_OUTFITS[n] not in inventory.level_unlocked(main._closet_level(u))]
finally:
    db.DB_PATH = _real_path
check("每一件都是他自己等級已經解鎖的（沒有 3 級戴 8 級的皇冠）", _locked, [])
for u, _ in demo_accounts.demo_users(TMP):
    db.set_equipped_item(u, None, db_path=TMP)
check("--live 會補穿（舊的示範帳號不用重建）", demo_accounts.dress_demo(db_path=TMP), demo_accounts.DEMO_OUTFITS)
check("本人的衣服不被動到", (db.get_game_state(me, db_path=TMP) or {}).get("equipped_item_id"), None)
demo_accounts.remove_all(TMP)
_c = db.connect(TMP)
left = _c.execute("SELECT COUNT(*) AS n FROM live_sleep_status").fetchall()[0]["n"]
_c.close()
check("刪示範帳號連它們的即時狀態一起刪（只剩本人那一列）", left, 1)
check("本人的即時狀態還在", db.get_live_sleep_status(me, db_path=TMP) is not None, True)

print()
if fails:
    print(f"✗ {len(fails)} 項失敗")
    sys.exit(1)
print("✓ 全部通過")
