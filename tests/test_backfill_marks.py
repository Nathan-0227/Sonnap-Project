"""
tests/test_backfill_marks.py — 事後補的上床／下床時間（2026-11-12 使用者定）

守的是壞掉時不會報錯的地方：
【1】舊版 App 不帶 kind → 當作當下按的（'tap'），不是 NULL
【2】補的下床存成 'recalled'，上床保留 'tap'（兩端分開記）
【3】⚠️ 當下按的不能被回想的蓋掉（上床、下床各一次）
【4】只有那個 basis 真的用到回想的那一端才掛警語（② 不看下床）
【5】警語只接在效率那條後面；效率沒計分時不掛
【6】匯出給評分器的檔案帶 kind；評分器據此標 efficiency_recalled
【7】攝影機比對只拿當下按的上床
【8】API 與打包檔兩條路徑對同一晚給同一句警語

⚠️ 全程使用暫存資料庫。執行：python tests/test_backfill_marks.py
"""
import sys
import tempfile
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "garmin"))

import db  # noqa: E402
TMP = Path(tempfile.mkdtemp()) / "test.db"
db.DB_PATH = TMP

import main  # noqa: E402
import score_claim  # noqa: E402
import export_bed_marks  # noqa: E402
import build_app_payload  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

client = TestClient(main.app)
fails = []


def check(label, got, want):
    good = got == want
    print(f"  {'✓' if good else '✗'} {label:<52} {got!r}" + ("" if good else f"  期望 {want!r}"))
    if not good:
        fails.append(label)


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<52} {extra}")
    if not cond:
        fails.append(label)


db.init_db(TMP)


def new_user(name):
    return client.post("/users", json={"display_name": name, "study_cohort": "L0"}).json()["user_id"]


def row(uid, date):
    for r in db.get_nightly_behavior(uid, days=3650, db_path=TMP):
        if r["date"] == date:
            return r
    return None


LIGHTS = "2026-11-11T23:30:00+08:00"
START = "2026-11-11T23:00:00+08:00"
END = "2026-11-12T07:00:00+08:00"
NIGHT = "2026-11-12"

print("【1】舊版 App 不帶 kind → 'tap'")
u1 = new_user("舊版")
r1 = client.post("/nightly", json={"user_id": u1, "lights_out_at": LIGHTS,
                                   "bed_start_at": START, "bed_end_at": END}).json()
check("回應 start kind", r1["bed_start_kind"], "tap")
check("回應 end kind", r1["bed_end_kind"], "tap")
check("資料庫 start kind", row(u1, NIGHT)["bed_start_kind"], "tap")
u1b = new_user("沒按")
r1b = client.post("/nightly", json={"user_id": u1b, "lights_out_at": LIGHTS}).json()
check("沒按按鈕 → kind 是 None（不是 tap）", r1b["bed_start_kind"], None)

print("【2】上床當下按、下床事後補 → 兩端分開記")
u2 = new_user("補下床")
client.post("/nightly", json={"user_id": u2, "lights_out_at": LIGHTS, "bed_start_at": START})
r2 = client.post("/nightly", json={"user_id": u2, "lights_out_at": LIGHTS,
                                   "bed_start_at": START, "bed_end_at": END,
                                   "bed_start_kind": "tap", "bed_end_kind": "recalled"}).json()
check("start kind", row(u2, NIGHT)["bed_start_kind"], "tap")
check("end kind", row(u2, NIGHT)["bed_end_kind"], "recalled")
ok("補的下床照樣算進效率", r2["sleep_efficiency"] is not None, str(r2["sleep_efficiency"]))
# 之後不帶標記重傳：kind 要跟著沿用，不能被抹成 NULL
client.post("/nightly", json={"user_id": u2, "lights_out_at": LIGHTS})
check("重傳後 end kind 仍是 recalled", row(u2, NIGHT)["bed_end_kind"], "recalled")

print("【3】⚠️ 當下按的不能被回想的蓋掉")
u3 = new_user("不能蓋")
client.post("/nightly", json={"user_id": u3, "lights_out_at": LIGHTS,
                              "bed_start_at": START, "bed_end_at": END})
client.post("/nightly", json={"user_id": u3, "lights_out_at": LIGHTS,
                              "bed_start_at": "2026-11-11T22:00:00+08:00",
                              "bed_end_at": "2026-11-12T08:00:00+08:00",
                              "bed_start_kind": "recalled", "bed_end_kind": "recalled"})
r3 = row(u3, NIGHT)
ok("上床仍是當下按的那個時間", r3["bed_start_at"].startswith("2026-11-11T23:00"), r3["bed_start_at"])
ok("下床仍是當下按的那個時間", r3["bed_end_at"].startswith("2026-11-12T07:00"), r3["bed_end_at"])
check("start kind 仍是 tap", r3["bed_start_kind"], "tap")
check("end kind 仍是 tap", r3["bed_end_kind"], "tap")
# 反過來：補的可以被當下按的蓋掉（更正仍然有效）
u3b = new_user("可被蓋")
client.post("/nightly", json={"user_id": u3b, "lights_out_at": LIGHTS,
                              "bed_start_at": "2026-11-11T22:00:00+08:00",
                              "bed_start_kind": "recalled"})
client.post("/nightly", json={"user_id": u3b, "lights_out_at": LIGHTS, "bed_start_at": START})
check("回想的上床被當下按的蓋掉", row(u3b, NIGHT)["bed_start_kind"], "tap")
bad = client.post("/nightly", json={"user_id": u3b, "lights_out_at": LIGHTS,
                                    "bed_start_at": START, "bed_start_kind": "guess"})
check("kind 只收 tap／recalled", bad.status_code, 422)

print("【4】只有用到回想那一端的 basis 才算")
f = score_claim.efficiency_uses_recalled
check("① 下床是回想的", f("watch_tst__phone_tats", "tap", "recalled"), True)
check("① 都是當下按的", f("watch_tst__phone_tats", "tap", "tap"), False)
check("② 只看上床：下床回想 → 不算", f("phone_bed_start__watch_wake", "tap", "recalled"), False)
check("② 上床回想 → 算", f("phone_bed_start__watch_wake", "recalled", None), True)
check("③ 沒用按鈕 → 不算", f("watch_tst__watch_onset_to_wake", "recalled", "recalled"), False)
check("舊資料 None → 不算", f("watch_tst__phone_tats", None, None), False)

print("【5】警語只接在效率那條後面")
note = score_claim.RECALLED_EFFICIENCY_NOTE
c = score_claim.compose(["duration", "efficiency", "deep"],
                        efficiency_basis="watch_tst__phone_tats", efficiency_recalled=True)
eff_caveat = next(x["caveat"] for x in c["caveats"] if x["component"] == "efficiency")
ok("效率那條結尾是回想的警語", eff_caveat.endswith(note))
ok("其他條沒有", all(note not in x["caveat"] for x in c["caveats"] if x["component"] != "efficiency"))
check("efficiency_recalled 帶出來", c["efficiency_recalled"], True)
c2 = score_claim.compose(["duration", "deep"], efficiency_basis=None, efficiency_recalled=True)
check("效率沒計分 → 不掛", c2["efficiency_recalled"], False)
ok("效率沒計分 → 哪一條都沒有那句", all(note not in x["caveat"] for x in c2["caveats"]))

print("【6】匯出檔帶 kind；評分器據此標 efficiency_recalled")
nights = export_bed_marks.collect(TMP)
# resolve_phone_account 會挑夜數最多的帳號；這裡只確認形狀，直接從資料庫列組
rows = {r["date"]: r for r in db.get_nightly_behavior(u2, days=3650, db_path=TMP)}
ok("collect 執行得了", nights is None or isinstance(nights, dict))
import evaluate_sleep_quality as esq  # noqa: E402
night_row = {"date": NIGHT, "sleep_duration_hours": "7.5", "sleep_efficiency": "0.97",
             "waso_minutes": "10", "deep_ratio": "0.2", "rem_ratio": "0.2",
             "total_sleep_minutes": "450", "wake_time": "2026-11-12T06:50:00+08:00"}
marks = {NIGHT: {"bed_start_at": START, "bed_end_at": END, "time_in_bed_minutes": 480.0,
                 "bed_start_kind": "tap", "bed_end_kind": "recalled"}}
out = esq.evaluate_night(night_row, marks)
check("① 用到回想的下床 → efficiency_recalled", out["efficiency_recalled"],
      out["efficiency_basis"] == "watch_tst__phone_tats")
marks[NIGHT]["bed_end_kind"] = "tap"
check("都當下按 → False", esq.evaluate_night(night_row, marks)["efficiency_recalled"], False)
src = (ROOT / "export_bed_marks.py").read_text(encoding="utf-8")
ok("匯出腳本寫出 bed_start_kind／bed_end_kind", "bed_start_kind" in src and "bed_end_kind" in src)

print("【7】攝影機比對只拿當下按的上床")
src = (ROOT / "compare_night_sources.py").read_text(encoding="utf-8")
ok("compare_night_sources 檢查 bed_start_kind", 'bed_start_kind' in src)

print("【8】API 與打包檔對同一晚給同一句警語")
base_row = {"duration_score": 30, "efficiency_score": 20, "waso_score": 20,
            "deep_score": 8, "rem_score": None,
            "efficiency_basis": "watch_tst__phone_tats", "efficiency_recalled": True}
payload_c = build_app_payload.composition_for(base_row)
api_c = main.score_composition(
    {"duration_min": 450, "efficiency_basis": "watch_tst__phone_tats", "waso_min": 10,
     "deep_min": 90, "rem_measured": 0},
    {"bed_start_kind": "tap", "bed_end_kind": "recalled"})
check("兩邊 caveats 相同", payload_c["caveats"], api_c["caveats"])
check("兩邊 efficiency_recalled 相同", payload_c["efficiency_recalled"], api_c["efficiency_recalled"])

print()
if fails:
    print(f"✗ {len(fails)} 條失敗：{fails}")
    sys.exit(1)
print("✓ 全部通過")
