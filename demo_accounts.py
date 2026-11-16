"""
demo_accounts.py —— 成果展用的示範帳號。

建 4 個示範帳號、塞最近幾週的資料，並加成手機帳號的好友，
讓好友頁、動態牆與排行在現場 demo 時有東西可看。

    python demo_accounts.py --create          # 建立（已存在就先刪掉重建）
    python demo_accounts.py --status          # 看現在有哪些示範帳號
    python demo_accounts.py --remove          # 全部刪掉（好友關係一起消失）

要寫進 MariaDB 就先設 SONNAP_DB_URL（跟啟動後端同一個），否則寫進 SQLite。
腳本一開始會印出它寫的是哪一個。

🔴 **這些不是受測者資料。** 每一晚都是這支腳本用固定亂數種子產生的。
   - 暱稱一律帶 "(demo)"，App 的好友頁看得到
   - users.study_cohort = db.DEMO_COHORT，任何掃過所有使用者的查詢都要排除它
   - 簡報與海報上出現好友畫面時要標 "Demo accounts"
   - **不可以拿來當 D2 的結果**，也不可以算進任何「使用者數」

寫哪些（2026-11-16 使用者定「示範帳號全部資料都要生成，不能只有 Sleep Stages」）：
   - nightly_behavior：放下手機的時刻、按「開始／結束睡覺」的時刻（達成度交給 adherence 算）
   - wearable_nightly：一整晚的睡眠。**source = "demo"**（不是 garmin／health_connect）。
     睡眠階段由 demo_sleep.night_segments 排好，**分數交給既有評分器算**
     （healthconnect_adapter.to_wearable_row，跟手機用 Health Connect 上傳同一條路），
     不是手寫的數字
   - garmin_daily：白天資料（步數、壓力、Body Battery…），給動態卡的「Yesterday」
   - friend_sharing：每個人公開哪些項目、選哪隻寵物、哪個場景（讓動態卡各有樣子）
⚠️ 假的生理資料有被誤算進統計的風險，所以：source 一律 "demo"、帳號一律 DEMO_COHORT；
   評分與匯入只認 source = "garmin"（migrate_garmin_to_db 的 _garmin_windows 等）。

⚠️ 不印任何 user_id（那是憑證）。邀請碼只能加好友、不能登入，可以印。
"""
import argparse
import random
import sys
from datetime import date, datetime, timedelta, timezone

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import db
import db_backend
import demo_sleep
from behavior import adherence
from behavior.sleep_efficiency import evaluate_efficiency
from wearable.healthconnect_adapter import to_wearable_row

TZ = timezone(timedelta(hours=8))
DEFAULT_NIGHTS = 21
DEFAULT_SEED = 1125          # 成果展那天。固定種子 → 每次重建結果一樣

# 四種作息，讓排行有高有低、每個人在好友頁上各講一個故事。
# offset(i, n, rng) 回傳「比目標晚幾分鐘」；回傳 None = 那一晚沒開 App（沒有行為資料，
# 但手錶照樣有量——手錶不需要開 App）。
#
# ⚠️ 「達成」的門檻是晚 0 分鐘（challenges.ACHIEVED_MAX_ADHERENCE_MINUTES），
#    晚一分鐘連續紀錄就斷。要讓某人「一直準時」就得把偏移夾在 −1 以下。
# ⚠️ 缺晚用固定規則而不是亂數：demo 的畫面要每次重建都一樣。


def _improving(i, n, rng):
    """前期晚兩小時，線性收斂到提早；收斂到提早之後就一直準時。"""
    base = 120 - 140 * i / max(n - 1, 1)
    if base < 0:
        return min(-1.0, base + rng.gauss(0, 5))
    return base + rng.gauss(0, 15)


# sleep：(睡著分鐘數的平均, 標準差)、深睡比例、REM 比例、半夜醒著幾分鐘 (平均, 標準差)
# day：步數平均、壓力（高的時間）多寡 0–1、有沒有 VO2 max
# share：除了預設之外多打開哪些項目；precision：時刻要不要準確
# camera：每小時動幾次 (平均, 標準差)；None＝沒有攝影機（卡上就沒有 Moves/hr）
PERSONAS = [
    {   # 每晚都準時 → 排行第一、連續紀錄最長。只寫準時與否（示範時間軸不寫時刻）
        "name": "Mia (demo)", "target": "23:30",
        "offset": lambda i, n, rng: min(-1.0, rng.gauss(-20, 8)),
        "species": "cat", "scene": "lake", "precision": "on_time_only",
        "sleep": ((455, 20), 0.19, 0.23, (12, 5)), "day": (9500, 0.2, None),
        "device": "Garmin Forerunner 265", "phone": "Google Pixel 8", "camera_model": "Tapo C210",
        "share": ("stages", "sleep_duration", "score", "awake", "steps", "sleeping_hr",
                  "camera_timeline", "morning_rating", "level"),
        "camera": (12, 3),
    },
    {   # 一開始常熬夜，後來收斂 → 最近幾晚開始有連續紀錄
        "name": "Leo (demo)", "target": "00:00",
        "offset": _improving,
        "species": "dog", "scene": "campfire", "precision": "exact",
        "sleep": ((410, 30), 0.16, 0.21, (20, 8)), "day": (7200, 0.35, 44),
        "device": "Samsung Galaxy Watch6", "phone": "Samsung Galaxy S23", "camera_model": "Tapo C200",
        "share": ("stages", "sleep_duration", "time_in_bed", "awake", "sleeping_hr",
                  "level", "steps", "stress", "camera_timeline", "target_bedtime", "fell_asleep"),
        "camera": (19, 5),
    },
    {   # 夜貓子，常常晚一兩個小時 → 寵物是 tired
        "name": "Yuki (demo)", "target": "01:00",
        "offset": lambda i, n, rng: rng.gauss(75, 30),
        "species": "cat", "scene": "rooftop", "precision": "exact",
        "sleep": ((375, 40), 0.14, 0.20, (28, 10)), "day": (5200, 0.5, None),
        "device": "Fitbit Charge 6", "phone": "Google Pixel 7a", "camera_model": "Tapo C100",
        "share": ("stages", "sleep_duration", "bed_times", "awake", "stress", "body_battery",
                  "sleeping_hr", "camera_timeline", "efficiency", "time_in_bed"),
        "camera": (27, 6),
    },
    {   # 不規律，每 4 晚有 1 晚沒開 App → 缺晚會中斷連續紀錄（紅線 5）。只公開預設那幾項
        "name": "Ken (demo)", "target": "23:00",
        "offset": lambda i, n, rng: None if i % 4 == 2 else rng.gauss(15, 35),
        "species": "dog", "scene": "treehouse", "precision": "exact",
        "sleep": ((420, 50), 0.17, 0.21, (22, 12)), "day": (11000, 0.3, 47),
        "device": "Garmin Vivoactive 5", "phone": "Samsung Galaxy A54",
        "share": (),
        "camera": None,
    },
]


def backend_label():
    cfg = db_backend.mysql_config()
    if cfg:
        return f"MariaDB（{cfg.get('host')}/{cfg.get('database')}）"
    return f"SQLite（{db.DB_PATH}）"


def demo_users(db_path=None):
    """回傳 [(user_id, display_name)]。user_id 只在這支程式內部用，不印。"""
    conn = db.connect(db_path)
    try:
        rows = conn.execute(
            "SELECT user_id, display_name FROM users WHERE study_cohort = ? "
            "ORDER BY display_name",
            (db.DEMO_COHORT,),
        ).fetchall()
        return [(r["user_id"], r["display_name"]) for r in rows]
    finally:
        conn.close()


def remove_all(db_path=None):
    """刪掉所有示範帳號。CASCADE 會一併清掉每晚資料、邀請碼、好友關係、分享設定。"""
    users = demo_users(db_path)
    for uid, _ in users:
        db.delete_user(uid, db_path=db_path)
    return len(users)


def lights_out_for(wake_day, target, minutes_late):
    """起床日 + 目標時刻 + 晚幾分鐘 → 放下手機的時刻（帶 +08:00）。"""
    h, m = (int(x) for x in target.split(":"))
    target_dt = datetime(wake_day.year, wake_day.month, wake_day.day, h, m, tzinfo=TZ)
    # 目標在傍晚以後（例如 23:30）的話，是起床日「前一天」的晚上
    if h >= 12:
        target_dt -= timedelta(days=1)
    return target_dt + timedelta(minutes=round(minutes_late))


def _naive(dt):
    """按鈕時刻的慣例：牆鐘、不帶時區（同手機上傳）。"""
    return dt.replace(tzinfo=None, second=0, microsecond=0).isoformat()


def _session(onset, segments, bed_start, bed_end, rng):
    """把排好的段包成 Health Connect 的 session：上床到睡著、醒來到下床是清醒。"""
    wake = datetime.fromisoformat(segments[-1]["end"])
    stages = [{"startTime": bed_start.isoformat(), "endTime": onset.isoformat(), "stage": "AWAKE"}]
    stages += [{"startTime": s["start"], "endTime": s["end"], "stage": s["stage"].upper()}
               for s in segments]
    stages.append({"startTime": wake.isoformat(), "endTime": bed_end.isoformat(), "stage": "AWAKE"})
    return {
        "startTime": bed_start.isoformat(), "endTime": bed_end.isoformat(), "stages": stages,
        "avgHeartRate": round(rng.gauss(57, 3), 1), "restingHeartRate": round(rng.gauss(53, 2)),
    }


def write_watch_night(uid, wake_day, p, lights_out, rng, db_path=None):
    """一晚的手錶資料（source=demo）＋按鈕時刻。回傳 (bed_start, bed_end)。"""
    (dur_mu, dur_sd), deep_r, rem_r, (waso_mu, waso_sd) = p["sleep"]
    asleep = max(240, int(rng.gauss(dur_mu, dur_sd)))
    deep = int(asleep * max(0.08, rng.gauss(deep_r, 0.02)))
    rem = int(asleep * max(0.10, rng.gauss(rem_r, 0.02)))
    light = asleep - deep - rem
    waso = max(0, int(rng.gauss(waso_mu, waso_sd)))

    bed_start = lights_out + timedelta(minutes=rng.randint(2, 10))
    onset = (bed_start + timedelta(minutes=rng.randint(6, 24))).replace(second=0, microsecond=0)
    w_seed = {"user_id": uid, "date": wake_day.isoformat()}
    segs = demo_sleep.night_segments(onset, deep, light, rem, waso, demo_sleep.night_seed(w_seed))
    wake = datetime.fromisoformat(segs[-1]["end"])
    bed_end = wake + timedelta(minutes=rng.randint(4, 18))

    night, metrics, _ = to_wearable_row(_session(onset, segs, bed_start, bed_end, rng),
                                        date=wake_day.isoformat(), device_brand=p["device"])
    assert night == wake_day.isoformat(), (night, wake_day)
    metrics["awake_count"] = demo_sleep.awake_count(segs)
    db.upsert_wearable_nightly(uid, night, "demo", metrics, db_path=db_path)
    # 再排一次要跟評分時那一份相同（API 畫圖靠它）
    again = demo_sleep.stages_block({**metrics, "user_id": uid, "date": night, "source": "demo"})
    assert again and again["segments"] == segs, "demo_sleep 不是決定性的"
    return bed_start, bed_end


def write_camera_night(uid, wake_day, p, bed_start, bed_end, rng, db_path=None):
    """那一晚的攝影機摘要：只有臥床時間與動作次數（沒有錄影、沒有片段、沒有曲線）。"""
    if not p.get("camera"):
        return
    mu, sd = p["camera"]
    hours = (bed_end - bed_start).total_seconds() / 3600
    per_hour = round(max(4.0, rng.gauss(mu, sd)), 1)
    total = round(per_hour * hours)
    # 整晚每 5 分鐘一格：把 total 段動作隨機撒在臥床期間，那一格的值＝動了幾成時間
    start = bed_start.replace(tzinfo=None, second=0, microsecond=0)
    n = max(1, int(hours * 12))
    moving = [0.0] * n
    episodes = []
    for _ in range(total):
        k = rng.randrange(n)
        sec = round(rng.uniform(3, 25), 1)
        moving[k] = min(300.0, moving[k] + sec)
        at = start + timedelta(minutes=5 * k, seconds=rng.randint(0, 299))
        episodes.append({"start_at": at.isoformat(timespec="seconds"), "seconds": sec})
    curve = {"points": [{"t": (start + timedelta(minutes=5 * k)).isoformat(),
                         "value": round(moving[k] / 300, 3)} for k in range(n)],
             "bucket_minutes": 5}
    db.upsert_camera_nightly(uid, wake_day.isoformat(), {
        "bed_start_at": _naive(bed_start), "bed_end_at": _naive(bed_end),
        "time_in_bed_minutes": round(hours * 60, 1),
        "events_total": total, "events_per_hour": per_hour,
        "bed_times_provenance": "demo", "csv": None, "camera_model": p.get("camera_model"),
        # 同一把尺（basis＋roi）才進「跟平常比」的基線
        "roi": (0, 0, 1, 1), "motion_threshold_pct_of_roi": 0.75,
        "motion_curve": curve,
        "motion_episodes": sorted(episodes, key=lambda e: e["start_at"]),
    }, db_path=db_path)


def write_day(uid, day, p, rng, db_path=None):
    """那一個日曆日的白天資料（給隔天早上那張卡的 Yesterday）。"""
    steps_mu, stress, vo2 = p["day"]
    steps = max(800, int(rng.gauss(steps_mu, steps_mu * 0.25)))
    awake_sec = 16 * 3600
    high = int(awake_sec * stress * rng.uniform(0.05, 0.15))
    medium = int(awake_sec * rng.uniform(0.08, 0.16))
    low = int(awake_sec * rng.uniform(0.2, 0.3))
    walks = [{"type": "walking", "start": f"{rng.randint(7, 19):02d}:{rng.choice((5, 20, 35, 50)):02d}",
              "minutes": rng.randint(10, 35)} for _ in range(rng.randint(0, 3))]
    active_kcal = int(steps * 0.045 + rng.gauss(80, 30))
    db.upsert_garmin_daily(uid, day.isoformat(), {
        "steps": steps, "step_goal": 8000, "distance_m": int(steps * 0.74),
        "active_kcal": active_kcal, "resting_kcal": 1580, "total_kcal": 1580 + active_kcal,
        "highly_active_sec": int(steps / 10000 * 1500), "active_sec": int(steps / 10000 * 3600),
        "sedentary_sec": int(rng.uniform(8, 11) * 3600), "floors_up": rng.randint(2, 14),
        "stress_rest_sec": awake_sec - high - medium - low, "stress_low_sec": low,
        "stress_medium_sec": medium, "stress_high_sec": high,
        "body_battery_charged": rng.randint(35, 80), "body_battery_drained": rng.randint(40, 85),
        "vo2max": vo2, "move_iq": sorted(walks, key=lambda w: w["start"]),
    }, db_path=db_path)


def create_all(nights=DEFAULT_NIGHTS, end=None, seed=DEFAULT_SEED,
               friend_of=None, db_path=None):
    """
    重建所有示範帳號。回傳每個帳號的摘要 list。

    friend_of：要跟誰當好友的 user_id。None = 自動找手機帳號
    （db.resolve_phone_account，它已排除示範帳號）；找不到就不加好友。
    """
    end = end or date.today()
    rng = random.Random(seed)
    # 先補齊新欄位（後端還沒重開時資料庫可能少欄位）——要在刪掉舊帳號**之前**，
    # 不然寫到一半失敗會留下一半的示範帳號（2026-11-17 踩過）
    db.init_db(db_path)
    remove_all(db_path)

    if friend_of is None:
        friend_of, _info = db.resolve_phone_account(db_path)

    summary = []
    for p in PERSONAS:
        uid = db.create_user(p["name"], target_bedtime=p["target"],
                             study_cohort=db.DEMO_COHORT, db_path=db_path)
        written = late = 0
        for i in range(nights):
            wake_day = end - timedelta(days=nights - 1 - i)
            off = p["offset"](i, nights, rng)
            lights_out = lights_out_for(wake_day, p["target"],
                                        off if off is not None else rng.gauss(20, 30))
            bed_start, bed_end = write_watch_night(uid, wake_day, p, lights_out, rng, db_path)
            write_day(uid, wake_day - timedelta(days=1), p, rng, db_path)
            write_camera_night(uid, wake_day, p, bed_start, bed_end, rng, db_path)
            if off is None:
                continue  # 沒開 App：沒有行為資料
            night = adherence.evaluate_night(lights_out, p["target"], source="phone")
            assert night["date"] == wake_day.isoformat(), (night["date"], wake_day)
            eff = evaluate_efficiency(_naive(bed_start), _naive(lights_out), _naive(bed_end))
            db.upsert_nightly_behavior(
                uid, night["date"], night["target_bedtime"], night["lights_out_at"],
                night["adherence_minutes"], night["is_late"],
                source=night["source"], efficiency=eff,
                bed_start_kind="tap", bed_end_kind="tap", phone_model=p.get("phone"),
                db_path=db_path)
            written += 1
            late += bool(night["is_late"])
        db.set_friend_sharing(uid, items={k: True for k in p["share"]},
                              time_precision=p["precision"], pet_species=p["species"],
                              scene=p["scene"], db_path=db_path)
        code = db.ensure_invite_code(uid, db_path=db_path)
        if friend_of:
            db.add_friendship(friend_of, uid, db_path=db_path)
        summary.append({"name": p["name"], "target": p["target"], "nights": written,
                        "watch_nights": nights, "late": late, "code": code,
                        "friended": bool(friend_of)})
    return summary


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--create", action="store_true")
    g.add_argument("--status", action="store_true")
    g.add_argument("--remove", action="store_true")
    ap.add_argument("--nights", type=int, default=DEFAULT_NIGHTS)
    ap.add_argument("--end", type=date.fromisoformat, default=None,
                    help="最後一晚的起床日，預設今天（成果展前一天重跑一次，日期就會是最新的）")
    ap.add_argument("--seed", type=int, default=DEFAULT_SEED)
    args = ap.parse_args()

    print(f"資料庫：{backend_label()}")

    if args.remove:
        print(f"已刪除 {remove_all()} 個示範帳號。")
        return

    if args.status:
        users = demo_users()
        print(f"示範帳號 {len(users)} 個：{', '.join(n for _, n in users) or '（無）'}")
        return

    rows = create_all(nights=args.nights, end=args.end, seed=args.seed)
    if not rows[0]["friended"]:
        print("⚠️ 找不到手機帳號（resolve_phone_account 分不出來），沒有加好友。")
    for r in rows:
        print(f"  {r['name']:<12} 目標 {r['target']}  行為 {r['nights']:>2} 晚、手錶 {r['watch_nights']:>2} 晚、"
              f"熬夜 {r['late']:>2} 晚  邀請碼 {r['code']}")
    print("🔴 這些是示範資料，不是受測者。畫面上出現時要標 Demo accounts。")


if __name__ == "__main__":
    main()
