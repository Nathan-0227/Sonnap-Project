"""
tests/test_friend_sharing.py —— 每個人自己選讓好友看到什麼（2026-11-15）

守的是幾個**壞掉時不會報錯**的地方：

1. 預設：行為那幾項開、其他全部關——沒打開的值一個字都不出後端（用很好認的哨兵值掃整個回應）
2. 打開才出現，而且跟本人 /home 同一個數
3. 永遠不給的三項（攝影機片段、Move IQ 時刻、睡前用哪些 App）連 PATCH 都送不進去（422）
4. 只寫準時與否：時刻拿掉、準時照給
5. 沒公開連續天數的人不上排行
6. 別人的 user_id 永遠不出後端（動態卡、預覽也一樣）
7. Streak 那一週：週一開始、還沒到的日子是 future、沒資料是 none（不是 late）
8. 刪帳號連分享設定一起刪；寵物與場景（2026-11-16）跟著動態卡帶出去，不認得的場景 422

⚠️ 全程使用暫存資料庫。執行：python tests/test_friend_sharing.py
"""
import json
import sys
import tempfile
from datetime import date, datetime, timedelta
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import db  # noqa: E402

TMP = Path(tempfile.mkdtemp()) / "test_friend_sharing.db"
db.DB_PATH = TMP

import main  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from behavior.challenges import night_achieved  # noqa: E402
from social import sharing  # noqa: E402

client = TestClient(main.app, raise_server_exceptions=False)
fails = []


def check(label, got, want):
    good = got == want
    print(f"  {'✓' if good else '✗'} {label:<58} {got!r}" + ("" if good else f"  期望 {want!r}"))
    if not good:
        fails.append(label)


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<58} {extra}")
    if not cond:
        fails.append(label)


db.init_db(TMP)
db.seed_challenges(TMP)

TODAY = date.today()
NIGHT = (TODAY - timedelta(days=1)).isoformat()  # 那一晚（起床日）
night_dt = datetime.fromisoformat(NIGHT)


def make_user(name):
    return client.post("/users", json={"display_name": name, "target_bedtime": "23:30"}).json()["user_id"]


alice, bob = make_user("Alice"), make_user("Bob")
# Bob 那一晚：01:12 放下手機（晚了）、按了按鈕、手錶資料。值都很好認，用來掃有沒有外洩
r = client.post("/nightly", json={
    "user_id": bob, "lights_out_at": f"{NIGHT}T01:12:00",
    "bed_start_at": f"{NIGHT}T00:50:00", "bed_end_at": f"{NIGHT}T08:30:00",
})
assert r.status_code == 201, r.text
assert r.json()["date"] == NIGHT, r.json()
db.upsert_wearable_nightly(bob, NIGHT, "garmin", {
    "final_score": 42.75, "final_quality": "Poor", "duration_min": 401.5,
    "deep_min": 111.5, "rem_min": 77.25, "avg_hr": 63.5, "resting_hr": 51.5,
    "waso_min": 13.5, "awake_count": 4,
    "sleep_start_time": f"{NIGHT}T01:20:00+08:00", "wake_time": f"{NIGHT}T08:20:00+08:00",
}, db_path=TMP)
conn = db.connect(TMP)
conn.execute("INSERT INTO app_usage_daily (user_id, date, package_name, app_label, prebed_minutes) "
             "VALUES (?, ?, ?, ?, ?)", (bob, NIGHT, "com.secret.tiktokish", "SecretApp", 17.0))
conn.commit()
conn.close()

code_b = client.get(f"/friends?user_id={bob}").json()["my_invite_code"]
assert client.post("/friends", json={"user_id": alice, "invite_code": code_b}).status_code == 201

SECRETS = ("42.75", "401.5", "111.5", "77.25", "63.5", "51.5", "13.5", "SecretApp",
           "com.secret.tiktokish")


def leaked(payload):
    text = json.dumps(payload)
    return [s for s in SECRETS if s in text]


def feed():
    return client.get(f"/friends/feed?user_id={alice}").json()["cards"]


print("【1】預設：行為開、其他關")
v = client.get(f"/sharing?user_id={bob}").json()
items = {i["key"]: i["enabled"] for g in v["groups"] for i in g["items"]}
check("四組", [g["id"] for g in v["groups"]], ["sleep", "heart", "day", "game"])
check("放下手機、準時、連續、寵物心情、衣服、挑戰 預設開",
      sorted(k for k, on in items.items() if on),
      sorted(["phone_down_time", "on_time", "streak", "pet_mood", "outfit", "challenges"]))
check("永遠不給的三項有說明、但不是選項", (len(v["never_shared"]),
      any(k in items for k in ("camera_clips", "move_iq_times", "prebed_apps"))), (3, False))
cards = feed()
check("動態卡有 Bob 那一晚", [(c["display_name"], c["date"]) for c in cards], [("Bob", NIGHT)])
check("卡上只有預設開的那幾項（行為＋遊戲）", sorted(cards[0]["items"]),
      sorted(["phone_down_time", "on_time", "pet_mood", "outfit", "challenges"]))
check("放下手機時刻 01:12、晚了", (cards[0]["items"]["phone_down_time"], cards[0]["items"]["on_time"]),
      ("01:12", False))
check("⚠️ 沒打開的值一個字都不出後端（動態卡）", leaked(client.get(f"/friends/feed?user_id={alice}").json()), [])
check("⚠️ 摘要與單一朋友也一樣", leaked(client.get(f"/friends?user_id={alice}").json())
      + leaked(client.get(f"/friends/{code_b}?user_id={alice}").json()), [])

print("\n【2】打開才出現，數字跟本人 /home 同一份")
r = client.patch("/sharing", json={"user_id": bob, "items": {
    "score": True, "sleep_duration": True, "stages": True, "sleeping_hr": True,
    "resting_hr": True, "awake": True, "prebed_phone": True, "fell_asleep": True}})
check("PATCH 200", r.status_code, 200)
it = feed()[0]["items"]
home = client.get(f"/home?user_id={bob}&date={NIGHT}").json()
check("分數＋等級", it.get("score"), {"score": 42.75, "quality": "Poor"})
check("睡多久＝/home 的", it.get("sleep_duration"), home["metrics"]["sleep_duration_minutes"])
check("醒幾次、幾分鐘", it.get("awake"), {"count": 4, "minutes": 13.5})
check("睡著心率（沒曲線退回 avg_hr，四捨五入）", it.get("sleeping_hr"), {"avg": 64, "min": None})
check("睡前手機只給加總", it.get("prebed_phone"), 17.0)
check("⚠️ 哪個 App 永遠不出現", [s for s in ("SecretApp", "com.secret.tiktokish")
                                 if s in json.dumps(feed())], [])
check("躺多久才睡著＝按鈕 00:50 → 手錶 01:20", it.get("fell_asleep"), 30)
check("沒打開的（壓力、步數）照樣沒有", [k for k in ("stress", "steps") if k in it], [])

print("\n【3】永遠不給的、不認得的 → 422，一個都不改")
for bad in ({"camera_clips": True}, {"move_iq_times": True}, {"prebed_apps": True},
            {"no_such_thing": True}, {"score": "yes"}):
    r = client.patch("/sharing", json={"user_id": bob, "items": {**bad, "steps": True}})
    check(f"{list(bad)[0]} → 422", r.status_code, 422)
v = client.get(f"/sharing?user_id={bob}").json()
check("被拒的那一次裡的 steps 沒有偷偷打開",
      next(i["enabled"] for g in v["groups"] for i in g["items"] if i["key"] == "steps"), False)
check("時刻精度亂填 → 422", client.patch("/sharing", json={"user_id": bob, "time_precision": "minute"}).status_code, 422)
check("寵物亂填 → 422", client.patch("/sharing", json={"user_id": bob, "pet_species": "dragon"}).status_code, 422)

print("\n【4】只寫準時與否：時刻拿掉、準時照給")
client.patch("/sharing", json={"user_id": bob, "time_precision": "on_time_only",
                               "items": {"bed_times": True}})
it = feed()[0]["items"]
check("沒有放下手機時刻、沒有上床起床時刻", [k for k in ("phone_down_time", "bed_times") if k in it], [])
check("準時與否照給", it.get("on_time"), False)
fr = client.get(f"/friends?user_id={alice}").json()["friends"][0]
check("摘要裡的時刻也拿掉", fr["last_lights_out_at"], None)
client.patch("/sharing", json={"user_id": bob, "time_precision": "exact"})
check("改回準確 → 上床起床時刻出現", feed()[0]["items"].get("bed_times"), {"start": "00:50", "end": "08:30"})

print("\n【5】關掉連續天數 → 不上排行、摘要是 None 不是 0")
client.patch("/sharing", json={"user_id": bob, "items": {"streak": False, "on_time": False}})
f = client.get(f"/friends?user_id={alice}").json()
check("current_streak 是 None", f["friends"][0]["current_streak"], None)
check("streak_week 也拿掉（準時關了）", f["friends"][0]["streak_week"], None)
check("排行榜沒有 Bob", [e["display_name"] for e in f["leaderboard"]], [])
check("自己看自己不遮", isinstance(client.get(f"/friends?user_id={bob}").json()["me"]["current_streak"], int), True)
client.patch("/sharing", json={"user_id": bob, "items": {"streak": True, "on_time": True}})
check("打開 → 回到排行", [e["display_name"] for e in
                          client.get(f"/friends?user_id={alice}").json()["leaderboard"]], ["Bob"])

print("\n【6】別人的 user_id 永遠不出後端")
for path in ("/friends/feed", "/friends", f"/friends/{code_b}"):
    check(f"{path} 裡沒有 Bob 的 user_id", bob in client.get(f"{path}?user_id={alice}").text, False)
check("/sharing/preview 只給自己用、也不回 user_id",
      bob in client.get(f"/sharing/preview?user_id={bob}").text, False)
check("/friends/feed 不會被當成邀請碼（404）", client.get(f"/friends/feed?user_id={alice}").status_code, 200)

print("\n【7】Streak 那一週")
today = date(2026, 11, 13)  # 週五
rows = [{"date": "2026-11-09", "adherence_minutes": -5},   # 週一 準時
        {"date": "2026-11-10", "adherence_minutes": 120},  # 週二 晚了
        # 週三 沒資料
        {"date": "2026-11-12", "adherence_minutes": None},  # 週四 沒判
        {"date": "2026-11-13", "adherence_minutes": 0}]     # 週五 準時
w = sharing.streak_week(rows, today, night_achieved)
check("週一開始", w[0]["date"], "2026-11-09")
check("每一天的狀態", [d["status"] for d in w],
      ["on_time", "late", "none", "none", "on_time", "future", "future"])

print("\n【8】寵物跟著帶出去；刪帳號連設定一起刪")
client.patch("/sharing", json={"user_id": bob, "pet_species": "cat"})
check("朋友看到 Bob 是貓", client.get(f"/friends?user_id={alice}").json()["friends"][0]["pet_species"], "cat")
check("動態卡也帶", feed()[0]["pet_species"], "cat")
check("場景預設是營火", feed()[0]["scene"], "campfire")
client.patch("/sharing", json={"user_id": bob, "scene": "lake"})
check("選了湖邊，動態卡就是湖邊", feed()[0]["scene"], "lake")
check("GET /sharing 回目前的場景與可選的清單",
      {k: client.get(f"/sharing?user_id={bob}").json()[k] for k in ("scene", "scenes")},
      {"scene": "lake", "scenes": list(sharing.SCENES)})
check("不認得的場景 → 422", client.patch("/sharing", json={"user_id": bob, "scene": "beach"}).status_code, 422)
check("422 之後場景沒被改", feed()[0]["scene"], "lake")
client.delete(f"/users/{bob}")
check("friend_sharing 那一列不見了", db.get_friend_sharing(bob, TMP), None)

print()
if fails:
    print(f"✗ {len(fails)} 條沒過：{fails}")
    sys.exit(1)
print("✓ 全部通過")
