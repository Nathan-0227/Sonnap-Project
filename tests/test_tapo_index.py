"""
tests/test_tapo_index.py

守的是 `tapo_index.py` 那五個**壞掉時不會報錯**的機制。

TAPO 的資料有三個地方會安靜地錯：`report_date` 會標錯日期、`time` 欄位整串
壞成 00:00:00、同一份資料被存成三個檔。這些都不會拋例外——只會讓下游把
A 晚的攝影機資料配上 B 晚的手錶資料，或把同一晚算三次。

  【1】夜晚日期取自 video_clip 檔名，不是 report_date
  【2】time 欄位壞掉的夜晚仍能從檔名還原出時刻
  【3】橫跨兩夜的紀錄要依間隔切開
  【4】內容相同的重複檔要去重
  【5】provenance() 必須涵蓋索引輸出的每一個資料欄位

執行：python tests/test_tapo_index.py
"""
import sys
from datetime import datetime, timedelta
from pathlib import Path

# Windows 主控台預設 cp1252，印中文會崩。專案慣例，見 run_pipeline.py。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import tapo_index  # noqa: E402

fails = []


def check(label, got, want):
    ok = got == want
    print(f"  {'✓' if ok else '✗'} {label:<52} 得到 {got!r:<24} 期望 {want!r}")
    if not ok:
        fails.append(label)


def check_true(label, got):
    print(f"  {'✓' if got else '✗'} {label}")
    if not got:
        fails.append(label)


records = tapo_index.iter_raw_records()
by_id = {r["source_id"]: r for r in records}
index = tapo_index.build_index(records)

if not records:
    sys.exit("✗ 找不到 TAPO 資料。這些檔由影像組提供，測試無法執行。")


# ═══════════════════════════════════════════════════════════════════
print("【1】夜晚日期取自 video_clip 檔名，不是 report_date")
# ───────────────────────────────────────────────────────────────────
# 實例：sleep_reports/2026-08-04/sleep_report_003653.json 的 report_date
# 寫 08-04，但裡面 106 個 video_clip 全是 turn_20260803_*。
# 若改用 report_date，這一晚就會被配到 08-04 的手錶資料上——而且不會報錯。
MISLABELED = "tapo/sleep_reports/2026-08-04/sleep_report_003653.json"

if MISLABELED in by_id:
    record = by_id[MISLABELED]
    check("該檔的 report_date（已知是錯的）", record["report_date"], "2026-08-04")
    check("依檔名推出的夜晚", tapo_index.night_key(record["stamps"][0]), "2026-08-03")
    check_true("08-03 這一夜存在於索引中", "2026-08-03" in index)
    if "2026-08-03" in index:
        check("索引記下了 report_date 與實際不符",
              index["2026-08-03"]["date_mismatch"], ["2026-08-04"])
else:
    print(f"  … 略過（{MISLABELED} 不在這份資料裡）")

# 反向對照：確認「用 report_date」真的會得到不同答案，否則本條會假性通過。
mismatched = [n for n in index.values() if n["date_mismatch"]]
check_true(f"至少有一晚的 report_date 與檔名日期不符（實際 {len(mismatched)} 晚）",
           len(mismatched) >= 1)


# ═══════════════════════════════════════════════════════════════════
print("\n【2】time 欄位壞掉的夜晚仍能從檔名還原")
# ───────────────────────────────────────────────────────────────────
# 08-06 / 08-07 / 08-18 三晚的 timeline，每一筆的 time 都是 00:00:00~00:00:05。
# PROJECT_STATUS 3.9 曾把這一類記成「要等影像組修」——檔名裡有真時刻，不必等。
broken = [r for r in records
          if r["timeline"]
          and all((e.get("time") or "").startswith("00:00:0") for e in r["timeline"])]
check_true(f"找得到 time 欄位壞掉的紀錄（{len(broken)} 筆）", len(broken) >= 1)

for record in broken:
    stamps = record["stamps"]
    span = (stamps[-1] - stamps[0]).total_seconds() / 60 if len(stamps) > 1 else 0
    # time 欄位說整段只有 5 秒；檔名說是好幾個小時。後者才是真的。
    check_true(f"{record['source_id'].split('/')[-1][:38]:<38} "
               f"還原出 {len(stamps)} 個時刻、跨距 {span:.0f} 分鐘（> 5 秒）",
               len(stamps) > 0 and span > 1)


# ═══════════════════════════════════════════════════════════════════
print("\n【3】橫跨兩夜的紀錄要依間隔切開")
# ───────────────────────────────────────────────────────────────────
# sql#51 有 32 筆在 08-18、2 筆在 08-19，中間空了 15.2 小時。
# 不切的話，08-19 的兩筆事件會被算進 08-18，而且 camera_last 會變成隔天早上。
# 用結尾比對而不是完整字串：source_id 前面帶著是哪一份 dump
# （`tapo/sql#51` 與 `tapo 2.0/sql#51` 都可能存在），而這條測的是切段，
# 不是哪一份檔案。
_51 = next((r for k, r in by_id.items() if k.endswith("sql#51")), None)
if _51:
    sessions = tapo_index.split_sessions(_51["stamps"])
    check("sql#51 切成幾段", len(sessions), 2)
    if len(sessions) == 2:
        check("第一段屬於哪一夜", tapo_index.night_key(sessions[0][0]), "2026-08-18")
        check("第二段屬於哪一夜", tapo_index.night_key(sessions[1][0]), "2026-08-19")

# 通用不變式：任何一夜的錄影跨距都不該超過切段門檻的兩倍。
# 這一條抓的是「以後有新資料時切段失效」，不綁死在 sql#51 上。
limit = timedelta(hours=tapo_index.SESSION_GAP_HOURS * 2)
too_long = [n["date"] for n in index.values()
            if n["camera_last"] - n["camera_first"] > limit + timedelta(hours=12)]
check("沒有任何一夜的跨距長到不合理", too_long, [])

# 反向對照：確認 split_sessions 真的會切，而不是永遠回傳一段。
synthetic = [datetime(2026, 1, 1, 1, 0), datetime(2026, 1, 1, 2, 0),
             datetime(2026, 1, 2, 1, 0)]
check("合成資料：間隔 23 小時要切成兩段",
      len(tapo_index.split_sessions(synthetic)), 2)
check("合成資料：間隔 1 小時不切",
      len(tapo_index.split_sessions(synthetic[:2])), 1)


# ═══════════════════════════════════════════════════════════════════
print("\n【4】內容相同的重複檔要去重")
# ───────────────────────────────────────────────────────────────────
# 08-07 有三份 _recovered 檔（114346 / 114556 / 114920），內容逐筆相同。
# 不去重的話那一夜的事件數會被算成三倍——而且沒有任何錯誤訊息。
recovered = [r for r in records if "2026-08-07" in r["source_id"] and "recovered" in r["source_id"]]
if len(recovered) > 1:
    digests = {tapo_index._content_hash(r) for r in recovered}
    check(f"08-07 的 {len(recovered)} 份 _recovered 檔算出幾個指紋", len(digests), 1)
    used = [s for s in index.get("2026-08-07", {}).get("sources", []) if "recovered" in s]
    check("索引裡只留下一份", len(used), 1)
else:
    print(f"  … 略過（只找到 {len(recovered)} 份 _recovered 檔）")

# 反向對照：內容不同的檔**不可以**被誤判成重複。
# 08-06 有兩份 JSON（103000 有 7428 筆、115339_recovered 有 146 筆），兩份都要留。
aug06 = [r for r in records if "2026-08-06" in r["source_id"] and r["source_kind"] == "json"]
if len(aug06) > 1:
    check(f"08-06 的 {len(aug06)} 份內容不同的檔算出幾個指紋",
          len({tapo_index._content_hash(r) for r in aug06}), len(aug06))


# ═══════════════════════════════════════════════════════════════════
print("\n【5】provenance() 必須涵蓋索引輸出的每一個資料欄位")
# ───────────────────────────────────────────────────────────────────
# 這一條防的是「新增欄位卻忘了標可信度」。ai/night_profile.py 會照著
# provenance() 把標籤寫進 prompt；漏標的欄位會**沒有標籤地**進到模型面前，
# 而那正是 np.random 的數值混進夢境的路徑。漏標不會報錯。
labels = tapo_index.provenance()
VALID = {"MEASURED", "MEASURED_SESSION_START", "MEASURED_NOT_COMPARABLE",
         "NOT_MEASUREMENT_GRADE", "SIMULATED"}

# 這些是結構性欄位（日期、來源清單、比對結果），不是量測值，不需要標籤。
STRUCTURAL = {"date", "sources", "report_dates", "date_mismatch",
              "scores", "score_disagreement"}

sample = index[max(index)]
unlabelled = sorted(set(sample) - STRUCTURAL - set(labels))
check("每個資料欄位都有 provenance 標籤", unlabelled, [])
check("標籤值都在允許的四種之內", sorted(set(labels.values()) - VALID), [])
check_true("np.random 產生的欄位標成 SIMULATED",
           labels.get("snore_count") == "SIMULATED"
           and labels.get("decibel_min") == "SIMULATED"
           and labels.get("decibel_max") == "SIMULATED")
check_true("攝影機分數標成 NOT_MEASUREMENT_GRADE（同一晚跨來源差 80 分）",
           labels.get("stored_score") == "NOT_MEASUREMENT_GRADE")
# ⚠️ camera_first 不可以標成純 MEASURED。它在 first_is_warmup 為真時記錄的是
#    「監測程式連上攝影機的那一刻」而不是使用者的動作（去重後實測 15/15，
#    見 tapo_index._is_warmup_artifact）。標錯會讓下游把它當成上床時刻。
check("camera_first 的標籤", labels.get("camera_first"), "MEASURED_SESSION_START")
check_true("暖機旗標存在且標成 MEASURED",
           labels.get("first_is_warmup") == "MEASURED")

# 反向對照：確認索引真的會標出暖機夜晚，否則上面兩條會假性通過。
warmup_nights = [n["date"] for n in index.values() if n["first_is_warmup"]]
check_true(f"至少有一晚的首事件被認出是暖機假影（實際 {len(warmup_nights)} 晚）",
           len(warmup_nights) >= 1)


# ═══════════════════════════════════════════════════════════════════
print()
if fails:
    print(f"✗ {len(fails)} 條未通過：")
    for label in fails:
        print(f"    - {label}")
    sys.exit(1)
print("✓ 全部通過")
