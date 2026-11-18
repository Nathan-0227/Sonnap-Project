"""
tests/test_export_teammate.py —— 給隊友的資料庫副本：真的 id 不得外流、別人的資料不得帶出去

  【1】只帶手機帳號＋它的好友；別的帳號一列都不帶
  【2】真的 user_id 在輸出檔裡**一個位元組都找不到**（含反向對照：來源檔裡找得到）
  【3】好友關係兩個方向都在，指向新的 id
  【4】--user-id-file 沿用上次的 id（APK 不用重建）
  【5】輸出已存在時停下來；來源資料庫一筆都沒變
  【6】片段只帶手機帳號的
  【7】輸出是單一檔案（沒有 -wal），外鍵全部對得上
  【8】後端讀副本，回應跟讀來源時一樣（只差 user_id）

⚠️ 全程使用暫存資料庫。執行：python tests/test_export_teammate.py
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import db
WORK = Path(tempfile.mkdtemp())
SRC = WORK / "source.db"
db.DB_PATH = SRC

import export_teammate
from behavior import adherence

fails = []


def check(label, got, want):
    good = got == want
    print(f"  {'✓' if good else '✗'} {label}" + ("" if good else f"：得到 {got!r}，應為 {want!r}"))
    if not good:
        fails.append(label)


def count(path, table, where="", args=()):
    conn = db.connect(path)
    try:
        return conn.execute(f"SELECT COUNT(*) AS n FROM {table} {where}", args).fetchone()["n"]
    finally:
        conn.close()


# ── 來源：本人 4 晚、好友 1 晚、陌生人 6 晚（夜數比本人多也不能被當成手機帳號以外的東西帶走）
db.init_db(SRC)
db.seed_challenges(SRC)
me = db.create_user("Me", db_path=SRC)
friend = db.create_user("Friend (demo)", db_path=SRC)
stranger = db.create_user("Stranger", db_path=SRC)
conn = db.connect(SRC)
conn.execute("UPDATE users SET study_cohort = ? WHERE user_id IN (?, ?)",
             (db.DEMO_COHORT, friend, stranger))
conn.commit()
conn.close()


def nights(uid, n):
    for d in range(1, n + 1):
        x = adherence.evaluate_night(f"2026-11-0{d}T23:50:00+08:00", "23:30")
        db.upsert_nightly_behavior(uid, x["date"], x["target_bedtime"], x["lights_out_at"],
                                   x["adherence_minutes"], x["is_late"], db_path=SRC)


nights(me, 4)
nights(friend, 1)
nights(stranger, 6)
db.ensure_invite_code(me, SRC)
db.ensure_invite_code(friend, SRC)
db.add_friendship(me, friend, SRC)

CLIPS = WORK / "clips"
CLIPS.mkdir()
conn = db.connect(SRC)
for cid, uid in (("a" * 32, me), ("b" * 32, stranger)):
    conn.execute("INSERT INTO camera_clips (clip_id, user_id, date, clip_rank, start_at, "
                 "duration_seconds, label, created_at) VALUES (?, ?, '2026-11-02', 1, "
                 "'2026-11-02T02:00:00', 6, '02:00 · moved for 6 s', '2026-11-02T08:00:00')",
                 (cid, uid))
    (CLIPS / f"{cid}.gif").write_bytes(b"GIF89a")
conn.commit()
conn.close()

before = {t: count(SRC, t) for t in ("users", "nightly_behavior", "friendships", "camera_clips")}
OUT = WORK / "out1"
r = export_teammate.export(OUT, source_db=SRC, clips_dir=CLIPS)
DST = OUT / "sonnap.db"
new_id = (OUT / "NEW_USER_ID.txt").read_text(encoding="utf-8")

print("【1】只帶手機帳號與它的好友")
check("帳號 2 個（本人＋好友）", count(DST, "users"), 2)
check("本人 4 晚都在", count(DST, "nightly_behavior", "WHERE user_id = ?", (new_id,)), 4)
check("總共 5 晚（陌生人的 6 晚沒帶）", count(DST, "nightly_behavior"), 5)
check("挑戰定義照抄", count(DST, "challenges"), count(SRC, "challenges"))

print("【2】真的 id 不外流")
raw_src = SRC.read_bytes() + b"".join(p.read_bytes() for p in WORK.glob("source.db-*"))
check("反向對照：來源檔裡找得到本人的 id", me.encode() in raw_src, True)
raw = DST.read_bytes()
for label, uid in (("本人", me), ("好友", friend), ("陌生人", stranger)):
    check(f"輸出檔裡找不到{label}原本的 id", uid.encode() in raw, False)
check("新 id 跟原本的不同", new_id != me, True)

print("【3】好友關係")
conn = db.connect(DST)
pairs = {(x["user_id"], x["friend_id"]) for x in conn.execute("SELECT * FROM friendships")}
new_friend = next(x["user_id"] for x in conn.execute("SELECT user_id FROM users WHERE user_id <> ?", (new_id,)))
conn.close()
check("兩個方向都在、指向新 id", pairs, {(new_id, new_friend), (new_friend, new_id)})
check("好友的那一晚也在", count(DST, "nightly_behavior", "WHERE user_id = ?", (new_friend,)), 1)

print("【4】沿用上次的 id")
r2 = subprocess.run([sys.executable, str(ROOT / "export_teammate.py"), "--out", str(WORK / "out2"),
                     "--user-id-file", str(OUT / "NEW_USER_ID.txt"), "--clips-dir", str(CLIPS)],
                    capture_output=True, text=True, encoding="utf-8",
                    env={**__import__("os").environ, "SONNAP_DB": str(SRC), "SONNAP_DB_URL": ""})
check("指令成功", r2.returncode, 0)
check("id 跟上次一樣", (WORK / "out2" / "NEW_USER_ID.txt").read_text(encoding="utf-8"), new_id)
check("資料庫裡的帳號也是那個 id",
      count(WORK / "out2" / "sonnap.db", "users", "WHERE user_id = ?", (new_id,)), 1)
check("輸出不印 id", new_id in r2.stdout + r2.stderr or me in r2.stdout + r2.stderr, False)

print("【5】不覆寫、不動來源")
try:
    export_teammate.export(OUT, source_db=SRC, clips_dir=CLIPS)
    check("輸出已存在時停下來", "沒停", "停下來")
except SystemExit:
    check("輸出已存在時停下來", "停下來", "停下來")
check("來源每張表筆數不變", {t: count(SRC, t) for t in before}, before)

print("【6】片段")
check("只帶本人那段", sorted(p.name for p in (OUT / "camera_clips").iterdir()), ["a" * 32 + ".gif"])
check("片段的那一列也只有本人的", count(DST, "camera_clips"), 1)
check("沒有找不到的", r["clips_missing"], 0)

print("【7】單一檔案、外鍵對得上")
check("沒有 -wal 檔", list(OUT.glob("sonnap.db-*")), [])
check("外鍵錯誤 0", r["fk_errors"], 0)

print("【8】後端讀副本跟讀來源一樣")
from fastapi.testclient import TestClient
import main


def get(path, uid, dbfile):
    db.DB_PATH = dbfile
    res = TestClient(main.app).get(f"{path}?user_id={uid}")
    body = json.loads(json.dumps(res.json()).replace(uid, "ID"))
    return res.status_code, body


for path in ("/home", "/insights", "/challenges", "/friends"):
    a = get(path, me, SRC)
    b = get(path, new_id, DST)
    check(f"{path} 相同", a, b)
db.DB_PATH = SRC

print()
if fails:
    print(f"✗ {len(fails)} 條沒過")
    sys.exit(1)
print("✓ 全部通過")
