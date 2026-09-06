"""
tests/test_sleep_efficiency.py

守的是 `behavior/sleep_efficiency.py` 那五個**壞掉時不會報錯**的機制。

這個數字的危險之處在於它**永遠算得出一個看起來合理的百分比**。
分子錯、分母錯、把「沒測到」當成 0%，結果都還是落在 0–100 之間，
不會拋例外、不會有空值，只會讓使用者看到一個錯的判讀。

  【1】代數恆等式：效率 == 100 − 上床後滑手機的佔比
      （這是這份資料真正的內容。式子一旦漂掉，這個數字就變成別的東西）
  【2】「沒測到」一律 None，不是 0
  【3】efficiency_basis 必須跟著數字走，而且不能與另外兩種效率混用
  【4】放下手機早於上床是合法的一晚（滑手機 0 分鐘），晚於起床是資料錯誤
  【5】臥床時間過短要擋掉 —— 分母小的時候百分比會劇烈跳動

五條都用「把 bug 重新引入、確認測試會紅」驗證過。

執行：python tests/test_sleep_efficiency.py
"""
import sys
from datetime import datetime, timedelta
from pathlib import Path

# Windows 主控台預設 cp1252，印中文會崩。專案慣例，見 run_pipeline.py。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from behavior.sleep_efficiency import (  # noqa: E402
    evaluate_efficiency, phone_in_bed_share,
    EFFICIENCY_BASIS, MIN_TIME_IN_BED_MINUTES,
)

fails = []


def check(label, got, want):
    ok = got == want
    print(f"  {'✓' if ok else '✗'} {label:<52} 得到 {got!r:<22} 期望 {want!r}")
    if not ok:
        fails.append(label)


def check_true(label, got):
    print(f"  {'✓' if got else '✗'} {label}")
    if not got:
        fails.append(label)


def night(bed_min_before_end, phone_min, tib_min=480):
    """造一晚：臥床 tib_min 分鐘，其中前 phone_min 分鐘在滑手機。"""
    start = datetime(2026, 9, 6, 23, 0)
    return evaluate_efficiency(
        start, start + timedelta(minutes=phone_min), start + timedelta(minutes=tib_min))


print("=" * 92)
print("behavior/sleep_efficiency.py")
print("=" * 92)

# ── 【1】代數恆等式 ────────────────────────────────────────────────
print("\n【1】效率 == 100 − 滑手機佔比（這才是這份資料真正的內容）")
for phone in (5, 30, 72, 120):
    r = night(None, phone)
    eff = r["sleep_efficiency"]
    share = phone_in_bed_share(r)
    check(f"滑 {phone:>3} 分鐘 → 效率 {eff}%，滑手機佔比 {share}%",
          round(eff + share, 1), 100.0)

# 文件裡那張「反向判讀」表的數字必須真的是這些，否則警告就失去意義
print("\n     文件與 docstring 裡引用的那幾個數字（8 小時臥床）")
check("滑 5 分鐘", night(None, 5)["sleep_efficiency"], 99.0)
check("滑 30 分鐘", night(None, 30)["sleep_efficiency"], 93.8)
check("滑 72 分鐘 → 剛好是 Ohayon「良好」的切點", night(None, 72)["sleep_efficiency"], 85.0)
check("滑 120 分鐘 → 剛好是「不良」的切點", night(None, 120)["sleep_efficiency"], 75.0)

# 反向對照：睡眠本身完全不影響這個數字。
# 沒有這一條，就無法證明「它量的不是睡眠」這個核心限制真的成立。
print("\n     反向對照：同樣滑 30 分鐘，臥床長度不同 → 效率必然不同；")
print("     但「睡得好不好」在這個模型裡根本沒有輸入端，所以無從影響")
a = night(None, 30, tib_min=480)["sleep_efficiency"]
b = night(None, 30, tib_min=240)["sleep_efficiency"]
check_true(f"臥床 8 小時 {a}% ≠ 臥床 4 小時 {b}%", a != b)

# ── 【2】沒測到一律 None ──────────────────────────────────────────
print("\n【2】「沒測到」與「效率 0%」是兩件事，一律 None")
t = datetime(2026, 9, 6, 23, 0)
for label, args in (
        ("沒按開始睡覺", (None, t, t + timedelta(hours=8))),
        ("沒按結束睡覺", (t, t + timedelta(minutes=30), None)),
        ("沒有 lights_out", (t, None, t + timedelta(hours=8))),
        ("三個都沒有", (None, None, None)),
):
    r = evaluate_efficiency(*args)
    nums = [r["sleep_efficiency"], r["time_in_bed_minutes"],
            r["phone_in_bed_minutes"], r["assumed_sleep_minutes"]]
    check(f"{label}：四個數值欄位都是 None", nums, [None] * 4)
    check_true(f"{label}：efficiency_note 說得出原因",
               bool(r["efficiency_note"]) and r["efficiency_note"] != "")

# ── 【3】basis 必須跟著走 ─────────────────────────────────────────
print("\n【3】efficiency_basis 一定要跟著數字走（三種效率並存，混了就分不出）")
ok_night = night(None, 30)
check("有算出來時帶 basis", ok_night["efficiency_basis"], EFFICIENCY_BASIS)
check("算不出來時也帶 basis",
      evaluate_efficiency(None, None, None)["efficiency_basis"], EFFICIENCY_BASIS)
check_true("basis 的值本身就說得出兩個假設（lights_out 與 waso）",
           "lights_out" in EFFICIENCY_BASIS and "waso" in EFFICIENCY_BASIS)
check_true("basis 不得與臨床/Garmin 那兩個混淆（不能只叫 clinical 或 wearable）",
           "clinical" not in EFFICIENCY_BASIS and "wearable" not in EFFICIENCY_BASIS)

# ── 【4】lights_out 落在臥床區間外 ───────────────────────────────
print("\n【4】lights_out 在區間外：早於上床合法，晚於起床是資料錯誤")
early = evaluate_efficiency(t, t - timedelta(minutes=20), t + timedelta(hours=8))
check("上床前就放下手機 → 滑手機 0 分鐘", early["phone_in_bed_minutes"], 0.0)
check("上床前就放下手機 → 效率 100%", early["sleep_efficiency"], 100.0)
late = evaluate_efficiency(t, t + timedelta(hours=9), t + timedelta(hours=8))
check("放下手機晚於起床 → 算不出來（不是 0%）", late["sleep_efficiency"], None)

# ── 【5】臥床過短要擋 ────────────────────────────────────────────
print(f"\n【5】臥床時間低於 {MIN_TIME_IN_BED_MINUTES} 分鐘要擋掉")
short = evaluate_efficiency(t, t + timedelta(minutes=5),
                            t + timedelta(minutes=MIN_TIME_IN_BED_MINUTES - 1))
check("低於下限 → None", short["sleep_efficiency"], None)
just_ok = evaluate_efficiency(t, t + timedelta(minutes=5),
                              t + timedelta(minutes=MIN_TIME_IN_BED_MINUTES))
check_true("剛好等於下限 → 算得出來", just_ok["sleep_efficiency"] is not None)

print()
print("【附】bed_start_at / bed_end_at 要原樣回傳（DB 要存）")
ok2 = evaluate_efficiency(t, t + timedelta(minutes=30), t + timedelta(hours=8))
check("bed_start_at", ok2["bed_start_at"], t.isoformat())
check("bed_end_at", ok2["bed_end_at"], (t + timedelta(hours=8)).isoformat())
blank2 = evaluate_efficiency(None, None, None)
check("算不出來時兩者都是 None",
      [blank2["bed_start_at"], blank2["bed_end_at"]], [None, None])

# ── ISO 字串也要吃 ───────────────────────────────────────────────
print("\n【附】datetime 與 ISO8601 字串要給出一樣的結果")
iso = evaluate_efficiency("2026-09-06T23:00:00", "2026-09-06T23:30:00",
                          "2026-09-07T07:00:00")
check("ISO 字串與 datetime 一致", iso["sleep_efficiency"], night(None, 30)["sleep_efficiency"])

# ═══════════════════════════════════════════════════════════════════
print()
if fails:
    print(f"✗ {len(fails)} 條未通過：")
    for label in fails:
        print(f"    - {label}")
    sys.exit(1)
print("✓ 全部通過")
