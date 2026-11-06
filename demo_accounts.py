"""
demo_accounts.py —— 成果展用的示範帳號。

建 4 個示範帳號、塞最近幾週的「放下手機時刻」，並加成手機帳號的好友，
讓好友排行與好友頁在現場 demo 時有東西可看。

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

⚠️ 只寫 nightly_behavior（行為），**不寫手錶資料**：好友之間本來就只看得到
   行為指標（social/friends.py 的 FRIEND_FIELDS），寫了也不會出現在畫面上，
   而假的生理資料一旦存在，就有被誤算進分數統計的風險。

⚠️ 達成度與熬夜一律交給 behavior/adherence.evaluate_night() 算，
   不在這裡自己算——跟手機上傳走同一條路徑，才不會有第二個定義處。

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
from behavior import adherence

TZ = timezone(timedelta(hours=8))
DEFAULT_NIGHTS = 21
DEFAULT_SEED = 1125          # 成果展那天。固定種子 → 每次重建結果一樣

# 四種作息，讓排行有高有低、每個人在好友頁上各講一個故事。
# offset(i, n, rng) 回傳「比目標晚幾分鐘」；回傳 None = 那一晚沒資料（沒開 App）。
# i 是第幾晚（0 = 最早的那晚），n 是總晚數。
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


PERSONAS = [
    {   # 每晚都準時 → 排行第一、連續紀錄最長
        "name": "Mia (demo)", "target": "23:30",
        "offset": lambda i, n, rng: min(-1.0, rng.gauss(-20, 8)),
    },
    {   # 一開始常熬夜，後來收斂 → 最近幾晚開始有連續紀錄
        "name": "Leo (demo)", "target": "00:00",
        "offset": _improving,
    },
    {   # 夜貓子，常常晚一兩個小時 → 寵物是 tired
        "name": "Yuki (demo)", "target": "01:00",
        "offset": lambda i, n, rng: rng.gauss(75, 30),
    },
    {   # 不規律，每 4 晚有 1 晚沒開 App → 缺晚會中斷連續紀錄（紅線 5）
        "name": "Ken (demo)", "target": "23:00",
        "offset": lambda i, n, rng: None if i % 4 == 2 else rng.gauss(15, 35),
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
    """刪掉所有示範帳號。CASCADE 會一併清掉每晚資料、邀請碼、好友關係。"""
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


def create_all(nights=DEFAULT_NIGHTS, end=None, seed=DEFAULT_SEED,
               friend_of=None, db_path=None):
    """
    重建所有示範帳號。回傳每個帳號的摘要 list。

    friend_of：要跟誰當好友的 user_id。None = 自動找手機帳號
    （db.resolve_phone_account，它已排除示範帳號）；找不到就不加好友。
    """
    end = end or date.today()
    rng = random.Random(seed)
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
            if off is None:
                continue
            night = adherence.evaluate_night(
                lights_out_for(wake_day, p["target"], off), p["target"], source="phone")
            assert night["date"] == wake_day.isoformat(), (night["date"], wake_day)
            db.upsert_nightly_behavior(
                uid, night["date"], night["target_bedtime"], night["lights_out_at"],
                night["adherence_minutes"], night["is_late"],
                source=night["source"], db_path=db_path)
            written += 1
            late += bool(night["is_late"])
        code = db.ensure_invite_code(uid, db_path=db_path)
        if friend_of:
            db.add_friendship(friend_of, uid, db_path=db_path)
        summary.append({"name": p["name"], "target": p["target"], "nights": written,
                        "late": late, "code": code, "friended": bool(friend_of)})
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
        print(f"  {r['name']:<12} 目標 {r['target']}  {r['nights']:>2} 晚、"
              f"熬夜 {r['late']:>2} 晚  邀請碼 {r['code']}")
    print("🔴 這些是示範資料，不是受測者。畫面上出現時要標 Demo accounts。")


if __name__ == "__main__":
    main()
