"""
tests/test_sleep_efficiency.py

守的是 `behavior/sleep_efficiency.py` 那六個**壞掉時不會報錯**的機制。

這個數字的危險之處在於它**永遠算得出一個看起來合理的百分比**。
分子錯、分母錯、把「沒測到」當成 0%，結果都還是落在 0–100 之間，
不會拋例外、不會有空值，只會讓使用者看到一個錯的判讀。

  【1】代數恆等式：效率 == 100 − 上床後滑手機的佔比
      （這是這份資料真正的內容。式子一旦漂掉，這個數字就變成別的東西）
  【2】「沒測到」一律 None，不是 0
  【3】efficiency_basis 必須跟著數字走，而且不能與另外兩種效率混用
  【4】放下手機早於上床是合法的一晚（滑手機 0 分鐘），晚於起床是資料錯誤
  【5】臥床時間過短要擋掉 —— 分母小的時候百分比會劇烈跳動
  【6】measured_efficiency 的分子必須是**量到的**睡眠，不是假定的
      （含反向對照：睡眠變動時數字要跟著變。舊那個數字的核心限制正是
        「睡眠完全不影響它」，兩者一旦混淆就白做了）

六條都用「把 bug 重新引入、確認測試會紅」驗證過。

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
    evaluate_efficiency, phone_in_bed_share, measured_efficiency,
    watch_wake_efficiency,
    EFFICIENCY_BASIS, MEASURED_EFFICIENCY_BASIS, MIN_TIME_IN_BED_MINUTES,
    WATCH_WAKE_EFFICIENCY_BASIS,
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
    check(f"{label}：四個**推導**欄位都是 None", nums, [None] * 4)
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

# ⚠️ 2026-09-07 實機測到的：使用者按了「開始睡覺」卻忘了按「下床」，
#    結果連 bed_start_at 都沒存進去。算不出效率 ≠ 沒有資料 ——
#    「幾點上床」本身就有用（拿它跟攝影機的開錄時刻對照，是目前唯一
#    量得到「手機代理值偏多少」的方法）。
print()
print("【2b】算不出效率時，使用者按過的時刻仍要原樣留著")
only_start = evaluate_efficiency(t, t + timedelta(minutes=30), None)
check("只按開始 → bed_start_at 留著", only_start["bed_start_at"], t.isoformat())
check("只按開始 → 效率仍是 None", only_start["sleep_efficiency"], None)
too_short = evaluate_efficiency(t, t + timedelta(minutes=1),
                                t + timedelta(minutes=5))
check("臥床過短 → 兩個時刻都留著",
      [too_short["bed_start_at"], too_short["bed_end_at"]],
      [t.isoformat(), (t + timedelta(minutes=5)).isoformat()])
check("臥床過短 → 效率仍是 None", too_short["sleep_efficiency"], None)

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
# 【6】measured_efficiency：分子改用手錶實測（2026-09-30 新增）
# ═══════════════════════════════════════════════════════════════════
#
# 這是**第二個**數字，與上面那個並存。差別只在分子：
#   evaluate_efficiency  分子 = 假定睡眠（臥床 − 滑手機）→ 量的是滑手機比例
#   measured_efficiency  分子 = 手錶實測睡眠           → 才是真的睡眠效率
#
# ⚠️ 下面第一條是**反向對照**：同一個臥床區間，餵不同的手錶睡眠時間，
#    新數字必須跟著變。少了這一條，就無法證明「分子真的換成量測值」了——
#    舊那個數字的核心限制正是「睡眠完全不影響它」（見【1】）。
print()
print("【6】measured_efficiency：分子是量到的，不是假定的")

a = measured_efficiency(total_sleep_minutes=307, time_in_bed_minutes=333.3)
b = measured_efficiency(total_sleep_minutes=250, time_in_bed_minutes=333.3)
check("307 分睡眠 ÷ 333.3 分臥床", a["measured_efficiency"], 92.1)
check("同一臥床、睡眠變少 → 數字要變低", b["measured_efficiency"], 75.0)
check_true("反向對照：睡眠確實會影響這個數字（舊那個不會）",
           a["measured_efficiency"] != b["measured_efficiency"])

# 兩個數字必須分得開：basis 不同
old = night(None, 30)
check_true("新舊兩個數字的 basis 不同（前端才分得出來）",
           old["efficiency_basis"] != MEASURED_EFFICIENCY_BASIS)

# 缺任一邊都要是 None，不是 0
check("沒有手錶資料 → None",
      measured_efficiency(None, 333.3)["measured_efficiency"], None)
check("沒有按按鈕 → None",
      measured_efficiency(307, None)["measured_efficiency"], None)
check("手錶測到 0 分鐘睡眠 → None（不是 0%）",
      measured_efficiency(0, 333.3)["measured_efficiency"], None)

# ⚠️ 矛盾的一晚不可夾平成 100%——那正是 2026-06-27 那個 bug 的形狀。
contradictory = measured_efficiency(total_sleep_minutes=500, time_in_bed_minutes=400)
check("睡眠 > 臥床 → None（不是夾平成 100）",
      contradictory["measured_efficiency"], None)
check_true("且要說明原因", bool(contradictory["measured_efficiency_note"]))

# 容差：1 分鐘內屬四捨五入，不可誤殺
check("睡眠比臥床多 0.5 分（四捨五入）→ 仍算得出來",
      measured_efficiency(400.5, 400)["measured_efficiency"], 100.0)

# basis 一定要跟著走，連算不出來的時候也是
check_true("算不出來時 basis 仍然存在",
           measured_efficiency(None, None)["measured_efficiency_basis"]
           == MEASURED_EFFICIENCY_BASIS)

# ═══════════════════════════════════════════════════════════════════
# 【6b】那幾句 note 是**使用者會直接讀到的字**，不是 log（2026-10-01）
# ═══════════════════════════════════════════════════════════════════
#
# App 的「Sleep Efficiency (measured)」卡片**原封不動顯示** note，一個字都
# 不改寫（改寫就會有第二份說法）。所以寫法壞掉時不會有任何錯誤訊息——
# 只會讓使用者在畫面上讀到一行像 log 的句子。
# 這幾條就是在守那件事；每一條都用「把舊寫法放回去、確認會紅」驗證過。
print()
print("【6b】那幾句話要寫得像話（會直接顯示在手機上）")

NOTES = {
    "沒有手錶資料": measured_efficiency(None, 333.3)["measured_efficiency_note"],
    "沒按按鈕": measured_efficiency(307, None)["measured_efficiency_note"],
    "手錶測到 0 睡眠": measured_efficiency(0, 333.3)["measured_efficiency_note"],
    "睡眠比臥床長": measured_efficiency(520, 422.2)["measured_efficiency_note"],
    "算得出來": measured_efficiency(307, 333.3)["measured_efficiency_note"],
}

for label, note in NOTES.items():
    # ① 不得出現欄位名／底線識別字——那是 API 的語言，不是人的語言
    check_true(f"{label}：沒有欄位名洩漏到畫面上",
               "_" not in note)
    # ② 不得用第三人稱講使用者本人
    check_true(f"{label}：不說「the user」，要對著使用者說話",
               "the user" not in note.lower())
    # ③ 要是完整的句子（句點結尾）
    check_true(f"{label}：是一句話不是片語", note.strip().endswith("."))

# ④ 做得到的事要講出來，而且照抄 App 上按鈕的字。
#    ⚠️ 「沒按按鈕」是這幾種情況裡**唯一使用者改得了的**，所以它必須給指示；
#       少了這句，忘記按的人只會知道「沒有數字」，不知道那是自己可以補的。
check_true("沒按按鈕：要指出按哪兩個鈕（照抄 App 上的字）",
           "Start sleep" in NOTES["沒按按鈕"]
           and "Out of bed" in NOTES["沒按按鈕"])

# ⑤ 矛盾的那一晚要把**兩個時長都講出來**，使用者才看得出是哪一邊不對勁。
#    只說「資料有誤」等於要人家自己去猜。
check_true("睡眠比臥床長：兩個時長都要出現（換算成時分）",
           "8 h 40 m" in NOTES["睡眠比臥床長"]
           and "7 h 2 m" in NOTES["睡眠比臥床長"])

# ⑥ ⚠️ **不得斷定使用者按錯**。2026-09-20 實測那一晚兩個標記都是誠實的，
#    是本人按完 Out of bed 之後又睡著（手錶多記錄 148 分鐘）。
#    說「標記是錯的」會讓使用者不敢相信自己按的紀錄，而那正是我們要他每天按的東西。
leak = NOTES["睡眠比臥床長"].lower()
check_true("睡眠比臥床長：不得斷定標記按錯了",
           "probably off" not in leak and "wrong" not in leak
           and "incorrect" not in leak)
check_true("睡眠比臥床長：要提出最可能的無辜解釋（又睡著了）",
           "fallen asleep again" in leak)

# ⑥ 算得出來的那句**必須講「不進分數」**。這個數字看起來就像一般的睡眠
#    效率，少了那半句，使用者會以為它影響了分數。
check_true("算得出來：要說它不影響分數",
           "never affects your sleep score" in NOTES["算得出來"])

# ═══════════════════════════════════════════════════════════════════
# 【6d】「沒按」與「按了但那一對不能用」必須講不同的話（2026-10-02）
# ═══════════════════════════════════════════════════════════════════
#
# 10-01 實機截圖抓到的：卡片上半說「You didn't mark this night」，
# 下半（並列的第二個效率）同時說「getting into bed 到 waking up 之間有 1 分鐘」
# ——**兩句話當場打架**，而使用者其實有按，只是兩下差 1.8 秒。
# 對②講「你沒有標記」是假話，而且會讓人以為按鈕沒作用。
print()
print("【6d】算不出來的三種情況要分得開")

none_at_all = measured_efficiency(300, None)["measured_efficiency_note"]
mistap = measured_efficiency(
    242, None, "2026-10-01T09:03:43", "2026-10-01T09:03:44.864794",
)["measured_efficiency_note"]
unusable = measured_efficiency(
    300, None, "2026-09-20T04:03:22", "2026-09-20T11:05:33",
)["measured_efficiency_note"]

check_true("① 完全沒按：要說「你沒有標記這一晚」",
           "didn't mark this night" in none_at_all)
check_true("② 按了但兩下太近：**不得**說成沒有標記",
           "didn't mark this night" not in mistap)
check_true("② 要講出兩個標記差多久（1.8 秒要講成秒，不是「0 m」）",
           "2 seconds apart" in mistap)
check_true("② 仍然要講得出可以怎麼做",
           "Tap Start sleep" in mistap and "Out of bed" in mistap)
check_true("③ 標記在、間隔也夠，但對不起來：三種話都不一樣",
           unusable not in (none_at_all, mistap)
           and "didn't mark this night" not in unusable)
check_true("⚠️ 三句互不相同（任何兩種情況講一樣的話就等於沒分）",
           len({none_at_all, mistap, unusable}) == 3)

# 不給標記時要退回舊行為（呼叫端還沒傳的話不能爆）
check_true("沒傳標記參數時照舊（向後相容）",
           measured_efficiency(300, None)["measured_efficiency"] is None)

# 這三句同樣是給人讀的
for label, note in {"①": none_at_all, "②": mistap, "③": unusable}.items():
    check_true(f"{label} 沒有欄位名洩漏到畫面上", "_" not in note)
    check_true(f"{label} 不說「the user」", "the user" not in note.lower())

# ═══════════════════════════════════════════════════════════════════
# 【6c】watch_wake_efficiency：結束時刻改用手錶的（2026-10-02 新增）
# ═══════════════════════════════════════════════════════════════════
#
# 存在的理由：measured_efficiency 兩端都是自述的，忘了按 Out of bed 整晚就報銷。
# 實測 22 晚裡有 2 晚只按了 Start sleep（09-14、09-30），再加上 09-20
# 那種「按完又睡著」，換成手錶的起床時刻就有數字了（3 晚 → 6 晚）。
#
# ⚠️ 這**不是比較好的那個，是另一個量**。下面每一條都在守「兩者不可混為一談」。
print()
print("【6c】watch_wake_efficiency：另一個分母，不是比較好的那個")

# 09-11 實測：07:11 按 Out of bed、手錶說 07:06 起床 → 分母較小、數字較高
a = measured_efficiency(307, 333.3)["measured_efficiency"]
b = watch_wake_efficiency(307, "2026-09-11T01:37:46", "2026-09-11T07:06:00")
check("09-11：手錶起床當結束 → 93.5%", b["watch_wake_efficiency"], 93.5)
check_true("同一晚兩個數字不一樣（分母不同，不可互相取代）",
           a != b["watch_wake_efficiency"])
check_true("basis 一定不同（前端只靠它分辨）",
           WATCH_WAKE_EFFICIENCY_BASIS != MEASURED_EFFICIENCY_BASIS)

# 🔴 這是整個欄位存在的理由：沒按 Out of bed 的夜晚要算得出來
# 09-14 的真值：手錶睡 243 分、起床 08:32（含 +08:00，與資料庫裡一樣）
only_start = watch_wake_efficiency(243, "2026-09-14T04:16:49",
                                   "2026-09-14T08:32:00+08:00")
check_true("🔴 只按了 Start sleep 的夜晚也算得出來（這是新增它的全部理由）",
           only_start["watch_wake_efficiency"] is not None)
check("09-14：95.2%", only_start["watch_wake_efficiency"], 95.2)

# ⚠️ 時區混用：手錶的 wake_time 帶 +08:00、手機的 bed_start_at 不帶。
#    直接相減會拋 TypeError；而**換算成 UTC 會差 8 小時**——那正是 Flutter 端
#    parseWallClock 當初修掉的那個錯。兩個都當牆鐘讀才對。
mixed = watch_wake_efficiency(307, "2026-09-11T01:37:46",
                              "2026-09-11T07:06:00+08:00")
check_true("⚠️ 一邊帶時區一邊不帶時，不得爆掉",
           mixed["watch_wake_efficiency"] is not None)
check("⚠️ 而且答案要與不帶時區時一模一樣（當牆鐘讀，不做換算）",
      mixed["watch_wake_efficiency"], b["watch_wake_efficiency"])

# 缺任一邊都是 None
check("沒有手錶資料 → None",
      watch_wake_efficiency(None, "2026-09-11T01:37:46", "2026-09-11T07:06:00")["watch_wake_efficiency"], None)
check("沒按 Start sleep → None",
      watch_wake_efficiency(307, None, "2026-09-11T07:06:00")["watch_wake_efficiency"], None)
check("沒有手錶起床時刻 → None",
      watch_wake_efficiency(307, "2026-09-11T01:37:46", None)["watch_wake_efficiency"], None)

# 10-01 實測：Start sleep 是早上 09:03 誤觸的。它的視窗其實是 **+1.3 分鐘**
# （手錶 09:05 起床），所以走的是「睡眠比視窗長」那條，不是負視窗那條。
backwards = watch_wake_efficiency(242, "2026-10-01T09:03:43", "2026-10-01T09:05:00")
check("⚠️ 10-01 那種誤觸 → None（不是夾平成 100）",
      backwards["watch_wake_efficiency"], None)

# ⚠️ 真正的負視窗要另外驗——而且要驗**訊息**不只驗 None。
#    兩條路都回 None，只看值的話那道保護被整個拿掉也不會紅
#    （第一版的測試就是這樣，mutation 驗出來的）。
inverted = watch_wake_efficiency(300, "2026-09-11T23:00:00", "2026-09-11T08:00:00")
check("標記落在手錶起床之後 → None", inverted["watch_wake_efficiency"], None)
check_true("而且要講出是「標記在起床之後」，不是講成睡太久",
           "after your watch says you already woke up"
           in inverted["watch_wake_efficiency_note"])

# 睡眠比視窗長也不夾平（與 measured_efficiency 同一條紀律）
check("睡眠比視窗長 → None",
      watch_wake_efficiency(600, "2026-09-11T01:37:46", "2026-09-11T07:06:00")["watch_wake_efficiency"], None)

# 那幾句話同樣是給人讀的
for label, note in {
    "沒按 Start sleep": watch_wake_efficiency(307, None, "2026-09-11T07:06:00")["watch_wake_efficiency_note"],
    "算得出來": b["watch_wake_efficiency_note"],
}.items():
    check_true(f"{label}：沒有欄位名洩漏到畫面上", "_" not in note)
    check_true(f"{label}：不說「the user」", "the user" not in note.lower())

check_true("算得出來：要說它不影響分數",
           "never affects your sleep score" in b["watch_wake_efficiency_note"])
check_true("算得出來：要講清楚結束時刻是**手錶**給的（否則會跟上面那個混淆）",
           "your watch says you woke up" in b["watch_wake_efficiency_note"])
check_true("沒按 Start sleep：要說這個不需要 Out of bed",
           "Out of bed" in watch_wake_efficiency(307, None, "2026-09-11T07:06:00")["watch_wake_efficiency_note"])

# ═══════════════════════════════════════════════════════════════════
print()
if fails:
    print(f"✗ {len(fails)} 條未通過：")
    for label in fails:
        print(f"    - {label}")
    sys.exit(1)
print("✓ 全部通過")
