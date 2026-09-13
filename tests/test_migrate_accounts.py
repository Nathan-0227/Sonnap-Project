"""
驗收：Garmin 匯入依戴錶者分帳號（2026-09-13）。

守的是四個**壞掉時不會報錯**的地方：

1. 每一晚掛在它所屬區段的帳號
   （wearer_a → 另開帳號、unverified → 研究者帳號、wearer_c → 手機帳號）
2. 搬家後舊帳號裡的副本要清掉——主鍵是 (帳號, 日期)，資料庫擋不住跨帳號重複，
   漏清的話同一晚會同時算在兩個人頭上，而且沒有任何錯誤訊息
3. 同一晚兩個來源時 **Garmin 優先**（2026-09-13 使用者決定）：
   Health Connect 已經送過的那一晚要被 Garmin 蓋掉。反方向由 POST /wearable 擋（test_api.py）
4. 找不到手機帳號（新資料庫還沒上傳過）時不能崩潰，本人那段先留在研究者帳號

用真的 garmin/data 檔、臨時的 SQLite 資料庫跑。不需要 pytest：

    python tests/test_migrate_accounts.py
"""

import os
import sys
import tempfile
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
# ⚠️ 開發機上可能設了 SONNAP_DB_URL（指向真的 MariaDB）。測試一律用臨時 SQLite。
os.environ.pop("SONNAP_DB_URL", None)

import db  # noqa: E402
import migrate_garmin_to_db as mg  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

FAILURES = []


def check(label, got, expected):
    ok = got == expected
    print(f"  {'✓' if ok else '✗'} {label}" + ("" if ok else f"　得到 {got!r}，預期 {expected!r}"))
    if not ok:
        FAILURES.append(label)


def run_migrate(db_path):
    argv = sys.argv
    sys.argv = ["migrate_garmin_to_db.py", "--db", db_path]
    try:
        mg.main()
        return 0
    except SystemExit as e:
        return e.code or 0
    finally:
        sys.argv = argv


def garmin_owner_map(db_path, accounts):
    """date → [持有 garmin 列的帳號]"""
    out = {}
    for uid in accounts:
        for r in db.get_wearable_nightly(uid, days=10_000, db_path=db_path):
            if r.get("source") == "garmin":
                out.setdefault(r["date"], []).append(uid)
    return out


def make_db():
    fd, path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    os.remove(path)
    db.init_db(path)
    return path


rows, _ = mg.build_rows()
dates = [d for d, _ in rows]
metrics_by_date = dict(rows)
seg = {d: mg.wearer_segment(d)[0] for d in dates}
wearer_a_dates = [d for d in dates if seg[d] == "wearer_a"]
unverified_dates = [d for d in dates if seg[d] == "unverified"]
wearer_c_dates = [d for d in dates if seg[d] == "wearer_c"]


print("【1】有手機帳號：每一晚掛在對的帳號，舊副本清乾淨")
path = make_db()
phone = str(uuid.uuid4())
db.create_user(display_name="phone", target_bedtime="23:30", db_path=path, user_id=phone)
db.upsert_nightly_behavior(
    user_id=phone, date=wearer_c_dates[-1], target_bedtime="23:30",
    lights_out_at=f"{wearer_c_dates[-1]}T02:00:00", adherence_minutes=150.0,
    is_late=True, source="phone", db_path=path,
)
# 模擬舊版的狀態：本人的一晚被塞在研究者帳號
mg.ensure_user(path)
stale_date = wearer_c_dates[0]
db.upsert_wearable_nightly(mg.RESEARCHER_USER_ID, stale_date, source="garmin",
                           metrics=metrics_by_date[stale_date], db_path=path)

check("匯入成功（驗收通過）", run_migrate(path), 0)
accounts = [mg.RESEARCHER_USER_ID, mg.WEARER_A_USER_ID, phone]
owners = garmin_owner_map(path, accounts)
check("每一晚都只掛在一個帳號", sorted(d for d, us in owners.items() if len(us) != 1), [])
check("wearer_a 的夜晚全在 wearer_a 帳號",
      all(owners.get(d) == [mg.WEARER_A_USER_ID] for d in wearer_a_dates), True)
check("unverified 的夜晚全在研究者帳號",
      all(owners.get(d) == [mg.RESEARCHER_USER_ID] for d in unverified_dates), True)
check("本人（wearer_c）的夜晚全在手機帳號",
      all(owners.get(d) == [phone] for d in wearer_c_dates), True)
check("舊版塞在研究者帳號的那一晚被清掉", owners.get(stale_date), [phone])
check("總夜數與檔案一致", len(owners), len(dates))

print("【2】重複執行：結果不變")
check("第二次匯入也成功", run_migrate(path), 0)
check("重跑後每一晚仍只掛在一個帳號",
      sorted(d for d, us in garmin_owner_map(path, accounts).items() if len(us) != 1), [])

print("【3】Garmin 優先：Health Connect 已經送過的那一晚被 Garmin 蓋掉")
# 實機（2026-09-13）：兩個來源常是同一支錶——Garmin Connect 同步進 Health Connect。
# 同一晚 Garmin 69.8、Health Connect 75.9，留哪一份由使用者決定為 Garmin。
hc_date = wearer_c_dates[-1]
hc_metrics = dict(metrics_by_date[hc_date])
hc_metrics["final_score"] = 12.3
db.upsert_wearable_nightly(phone, hc_date, source="health_connect", metrics=hc_metrics, db_path=path)
check("匯入仍然成功（驗收通過，不必跳過那一晚）", run_migrate(path), 0)
row = {r["date"]: r for r in db.get_wearable_nightly(phone, days=10_000, db_path=path)}[hc_date]
check("那一晚來源變成 garmin", row["source"], "garmin")
check("那一晚的分數是 Garmin 的，不是 Health Connect 的 12.3",
      row["final_score"], metrics_by_date[hc_date]["final_score"])

print("【4】找不到手機帳號時不崩潰，本人那段先留在研究者帳號")
path2 = make_db()
check("新資料庫匯入成功", run_migrate(path2), 0)
owners2 = garmin_owner_map(path2, [mg.RESEARCHER_USER_ID, mg.WEARER_A_USER_ID])
check("wearer_a 仍分出去", all(owners2.get(d) == [mg.WEARER_A_USER_ID] for d in wearer_a_dates), True)
check("本人那段留在研究者帳號",
      all(owners2.get(d) == [mg.RESEARCHER_USER_ID] for d in wearer_c_dates), True)

for p in (path, path2):
    try:
        os.remove(p)
    except OSError:
        pass

print()
if FAILURES:
    print(f"✗ {len(FAILURES)} 條失敗")
    sys.exit(1)
print("✓ 全部通過")
