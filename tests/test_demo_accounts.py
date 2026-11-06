"""
tests/test_demo_accounts.py —— 成果展示範帳號不得污染真實資料

  【1】示範帳號的夜數比本人多時，resolve_phone_account() 仍然認得本人
       （含反向對照：確認示範帳號真的比較多，否則這條會假性通過）
  【2】compare_night_sources 不帶暱稱時不讀示範帳號
  【3】示範帳號都加成本人的好友，好友頁看得到，且暱稱都帶 (demo)
  【4】重跑 --create 不會越長越多；--remove 清乾淨，本人的資料一筆不少
  【5】每晚的達成度跟手機上傳走同一個函式（adherence.evaluate_night）

⚠️ 全程使用暫存資料庫。執行：python tests/test_demo_accounts.py
"""
import sys
import tempfile
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

from datetime import date
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

print("【4】重建不累積、刪除不傷本人")
demo_accounts.create_all(nights=21, end=date(2026, 11, 6), db_path=TMP)
check("重建後仍是 4 個", len(demo_accounts.demo_users(TMP)), 4)
check("本人的好友仍是 4 個（舊的那批已被清掉）", len(db.list_friend_ids(me, TMP)), 4)
check("刪除回報 4 個", demo_accounts.remove_all(TMP), 4)
check("本人的 5 晚還在", len(db.get_nightly_behavior(me, days=3650, db_path=TMP)), 5)
check("本人沒有好友殘留", db.list_friend_ids(me, TMP), [])
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

print()
if fails:
    print(f"✗ {len(fails)} 項失敗")
    sys.exit(1)
print("✓ 全部通過")
