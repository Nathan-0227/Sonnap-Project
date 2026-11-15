"""
驗收：每晚「半夜醒了幾段」（wearable_nightly.awake_count，2026-11-15）。

早晨報告 Awake 點開那一週，每根長條底下寫「×3」、最上面寫「Woke up 3 times」。
守的是幾個**壞掉時不會報錯**的地方：

1. 次數是**還原的時間軸上清醒的段數**（跟 App 時間軸畫出來的同一份），匯入後逐晚相同。
   ⚠️ 不是 summary 的 awake_count：那個把入睡時刻的整晚摘要也算成一次，每晚多 1
   （11-15 用真實資料預覽發現；【0】把這件事釘住）
2. 回填（--awake-count-only）只補這一欄：舊夜晚的分數一個都不能動
3. 只改 Garmin 來源；Health Connect 那幾晚沒有這個量，留 null
4. 已經跑過 --init 的資料庫要自動補上欄位（CREATE TABLE IF NOT EXISTS 不會補）
5. /home 與 /insights 都帶出來；0 是真的值（整晚沒醒），null 才是沒資料

用真的 garmin/data 檔、臨時的 SQLite 資料庫跑。不需要 pytest：

    python tests/test_awake_count.py
"""

import contextlib
import io
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
# ⚠️ 開發機上可能設了 SONNAP_DB_URL（指向真的 MariaDB）。測試一律用臨時 SQLite。
os.environ.pop("SONNAP_DB_URL", None)

import db  # noqa: E402

TMP = Path(tempfile.mkdtemp()) / "test_awake_count.db"
db.DB_PATH = TMP

import main  # noqa: E402
import migrate_garmin_to_db as mg  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

client = TestClient(main.app, raise_server_exceptions=False)
FAILURES = []
SUMMARY_CSV = mg.GARMIN_DATA / "garmin_sleep_summary.csv"
sys.path.insert(0, str(ROOT / "garmin"))
import csv  # noqa: E402
import sleep_stages  # noqa: E402


def check(label, got, expected):
    ok = got == expected
    print(f"  {'✓' if ok else '✗'} {label}" + ("" if ok else f"　得到 {got!r}，預期 {expected!r}"))
    if not ok:
        FAILURES.append(label)


def run(*extra):
    argv = sys.argv
    sys.argv = ["migrate_garmin_to_db.py", "--db", str(TMP),
                "--deleted-rows-dir", tempfile.mkdtemp(), *extra]
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            mg.main()
        return 0, buf.getvalue()
    except SystemExit as e:
        return e.code or 0, buf.getvalue()
    finally:
        sys.argv = argv


def garmin_rows():
    conn = db.connect(str(TMP))
    try:
        return {r["date"]: dict(r) for r in conn.execute(
            "SELECT date, awake_count, final_score FROM wearable_nightly WHERE source = 'garmin'")}
    finally:
        conn.close()


def sql(statement, params=()):
    conn = db.connect(str(TMP))
    try:
        conn.execute(statement, params)
        conn.commit()
    finally:
        conn.close()


print("【0】整晚摘要不算一次醒來")
ON = "2026-11-14T03:33:00+08:00"
recs = [
    # 入睡時刻那四筆是整晚摘要（每個階段一筆＋*_duration_sec），不是時間段
    *({"timestamp": ON, "metric": "sleep_stage", "value": st} for st in ("deep", "light", "rem", "awake")),
    *({"timestamp": ON, "metric": f"{st}_duration_sec", "value": 60} for st in ("deep", "light", "rem", "awake")),
    {"timestamp": ON, "metric": "sleep_stage", "value": "light"},
    {"timestamp": "2026-11-14T03:42:00+08:00", "metric": "sleep_stage", "value": "awake"},
    {"timestamp": "2026-11-14T03:43:00+08:00", "metric": "sleep_stage", "value": "deep"},
    {"timestamp": "2026-11-14T08:45:00+08:00", "metric": "sleep_stage", "value": "awake"},
    {"timestamp": "2026-11-14T08:46:00+08:00", "metric": "sleep_stage", "value": "light"},
]
segs = sleep_stages.stage_segments(recs, ON, "2026-11-14T09:51:00+08:00")
check("11-14 那種晚上：真的醒 2 次（摘要那筆不算）", sleep_stages.awake_count(segs), 2)
check("整晚沒醒 → 0（不是 1）",
      sleep_stages.awake_count(sleep_stages.stage_segments(recs[:9], ON, "2026-11-14T09:51:00+08:00")), 0)

print("\n【0b】真實資料：時間軸的次數每晚都正好比 summary 少 1（摘要那筆）")
with SUMMARY_CSV.open(encoding="utf-8-sig", newline="") as f:
    summ = {r["date"]: r["awake_count"] for r in csv.DictReader(f) if r["awake_count"] not in ("", None)}
feats = {r["date"]: r for r in mg.load("garmin_sleep_features.json")}
counts0 = mg.timeline_awake_counts(
    {d: (feats[d]["sleep_start_time"], feats[d]["wake_time"]) for d in summ if d in feats})
diffs = {int(float(summ[d])) - c for d, c in counts0.items() if c is not None}
check("差值只有 1 這一種", diffs, {1})
check("有比到夠多晚", sum(c is not None for c in counts0.values()) > 50, True)

print("\n【1】匯入：每一晚的次數跟時間軸逐晚相同")
db.init_db(str(TMP))
code, out = run()
check("匯入成功（含醒來次數的核對）", code, 0)
rows = garmin_rows()
checked, problems = mg.verify_awake_counts(str(TMP))
check("比對的晚數＝資料庫裡 Garmin 的晚數", checked, len(rows))
check("逐晚沒有不一致", problems, [])
counts = [r["awake_count"] for r in rows.values()]
check("真的有寫進去（不是整欄 null 剛好對上空字串）", sum(c is not None for c in counts) > 0, True)
check("次數不只一種值（不是寫死）", len({c for c in counts if c is not None}) > 1, True)

print("\n【1b】反向對照：寫錯一晚，核對要抓得到")
some = next(d for d, r in rows.items() if r["awake_count"] is not None)
sql("UPDATE wearable_nightly SET awake_count = awake_count + 1 WHERE date = ?", (some,))
check("核對抓到那一晚", [p.split()[0] for p in mg.verify_awake_counts(str(TMP))[1]], [some])

print("\n【2】回填只補這一欄，分數不動")
sql("UPDATE wearable_nightly SET awake_count = NULL")
sql("UPDATE wearable_nightly SET final_score = 12.5 WHERE date = ?", (some,))
code, out = run("--awake-count-only")
check("回填成功", code, 0)
after = garmin_rows()
check("次數補回來、跟時間軸相同", mg.verify_awake_counts(str(TMP))[1], [])
check("⚠️ 別的欄位沒被重寫（手動改的分數還在）", after[some]["final_score"], 12.5)
check("晚數沒變（不新增、不刪）", sorted(after), sorted(rows))

print("\n【3】只改 Garmin 來源")
uid = client.post("/users", json={"display_name": "Awake", "target_bedtime": "23:30"}).json()["user_id"]
db.upsert_wearable_nightly(uid, "2031-01-02", "health_connect", {"waso_min": 10.0})
check("set_garmin_awake_counts 不碰 Health Connect 那一列",
      db.set_garmin_awake_counts({"2031-01-02": 5}, str(TMP)), 0)
hc = db.get_wearable_nightly(uid, days=10, db_path=str(TMP))
check("Health Connect 那一晚仍是 null", hc[0]["awake_count"], None)

print("\n【4】舊資料庫自動補欄位")
sql("ALTER TABLE wearable_nightly DROP COLUMN awake_count")
db.init_db(str(TMP))
conn = db.connect(str(TMP))
cols = db.existing_columns(conn, "wearable_nightly")
conn.close()
check("init 之後欄位回來了", "awake_count" in cols, True)

print("\n【5】/home 與 /insights 帶出來；0 是真的值")
db.upsert_wearable_nightly(uid, "2031-01-03", "garmin", {"waso_min": 38.0, "awake_count": 3})
db.upsert_wearable_nightly(uid, "2031-01-04", "garmin", {"waso_min": 0.0, "awake_count": 0})
home = client.get("/home", params={"user_id": uid, "date": "2031-01-03"}).json()
check("/home metrics.awake_count", (home.get("metrics") or {}).get("awake_count"), 3)
ins = client.get("/insights", params={"user_id": uid, "days": 10}).json()
by_date = {h["date"]: h for h in ins["wearable"]["history"]}
check("/insights 每晚帶次數", by_date["2031-01-03"].get("awake_count"), 3)
check("0 照實回 0、不是 null", by_date["2031-01-04"].get("awake_count"), 0)
check("Health Connect 那晚是 null（有欄位）",
      ("awake_count" in by_date["2031-01-02"], by_date["2031-01-02"]["awake_count"]), (True, None))

print("\n【6】Health Connect 轉換明寫 None（不補不會報錯，所以要守）")
src = (ROOT / "wearable" / "healthconnect_adapter.py").read_text(encoding="utf-8")
check('to_wearable_row 有 "awake_count": None', '"awake_count": None' in src, True)

print()
if FAILURES:
    print(f"✗ {len(FAILURES)} 條沒過：{FAILURES}")
    sys.exit(1)
print("✓ 全部通過")
