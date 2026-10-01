"""
tests/test_score_composition.py

守的是「**分數由哪幾項組成**」這件事在兩個地方講得一樣。

  【1】main.score_composition() 與 evaluate_sleep_quality.evaluate_night()
      對同一晚必須給出相同的答案（拿真實資料逐夜比對）
  【2】效率一律不計分，而且理由要跟著走
  【3】WASO 0 分鐘、深睡 0 分鐘是「有測到」，不可被當成沒資料
  【4】scored_weight 要等於實際有算的項目的配分總和

═══════════════════════════════════════════════════════════════════
為什麼需要這一支
═══════════════════════════════════════════════════════════════════
`score_composition()` 是**刻意寫的第二份判準**：評分在 pipeline（讀 CSV、
獨立行程），API 讀的是資料庫，兩邊拿不到同一份資料，所以各有一份。
不 import 的理由與 has_measured_sleep / is_valid_night 完全相同
（garmin/ 五支不是 package）。

**漂移時不會有任何錯誤訊息**——API 會照樣回一個看起來合理的組成清單，
只是跟分數實際的算法不一致。那正是這支測試要擋的。

四條都用「把 bug 重新引入、確認測試會紅」驗證過。

執行：python tests/test_score_composition.py
"""
import csv
import importlib.util
import io
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))


def load_script(path):
    """以模組方式載入 pipeline 腳本（garmin/ 五支不是 package，見檔頭）。"""
    spec = importlib.util.spec_from_file_location(path.stem, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


ev = load_script(ROOT / "garmin" / "evaluate_sleep_quality.py")
import main  # noqa: E402

fails = []


def check(label, got, want):
    ok = got == want
    print(f"  {'✓' if ok else '✗'} {label:<50} 得到 {got!r:<18} 期望 {want!r}")
    if not ok:
        fails.append(label)


def ok(label, cond, extra=""):
    print(f"  {'✓' if cond else '✗'} {label:<50} {extra}")
    if not cond:
        fails.append(label)


def to_f(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def db_row_from_features(feat):
    """
    把 features 那一列轉成「資料庫會長的樣子」。

    ⚠️ 只搬 score_composition() 真的會讀的欄位，而且**照 migrate_garmin_to_db.py
       實際寫進去的語意**：duration_min / waso_min / deep_min 是分鐘數，
       rem_measured 是評分器自己的判定（Tier1/2 那份輸出帶過來的）。
    """
    graded = ev.evaluate_night(feat)
    deep_ratio = to_f(feat.get("deep_ratio"))
    total = to_f(feat.get("total_sleep_minutes"))
    return {
        "duration_min": total,
        "waso_min": to_f(feat.get("waso_minutes")),
        "deep_min": None if (deep_ratio is None or total is None) else deep_ratio * total,
        "rem_measured": 1 if graded["rem_measured"] else 0,
    }


FEATURES = ROOT / "garmin" / "data" / "garmin_sleep_features.csv"
with io.open(FEATURES, encoding="utf-8-sig") as f:
    rows = list(csv.DictReader(f))

print("=" * 78)
print("【1】API 的組成清單必須與評分器實際算的項目一致")
print("=" * 78)
print(f"  features 列數：{len(rows)}")

disagree = []
for feat in rows:
    graded = ev.evaluate_night(feat)
    # 評分器實際上算了哪幾項
    truth = {k for k in ("duration", "efficiency", "waso", "deep", "rem")
             if graded[k + "_score"] is not None}
    comp = main.score_composition(db_row_from_features(feat))
    if set(comp["scored"]) != truth:
        disagree.append((feat.get("date"), sorted(truth), sorted(comp["scored"])))

check("兩邊判斷不一致的夜晚數", len(disagree), 0)
for d in disagree[:5]:
    print(f"      {d[0]}  評分器算了 {d[1]}  API 說 {d[2]}")

# 反向對照：樣本裡真的要有「組成不同」的夜晚，否則第 1 條是假性通過
comps = {tuple(sorted(main.score_composition(db_row_from_features(r))["scored"]))
         for r in rows}
ok("反向對照：樣本裡有 2 種以上的組成", len(comps) >= 2,
   f"{len(comps)} 種：{sorted(comps)}")

print()
print("=" * 78)
print("【2】效率一律不計分，且理由要跟著走")
print("=" * 78)
check("EFFICIENCY_SCORING_ENABLED 是 False", ev.EFFICIENCY_SCORING_ENABLED, False)
n_eff = sum(1 for r in rows if ev.evaluate_night(r)["efficiency_score"] is not None)
check("有 efficiency 分數的夜晚數", n_eff, 0)

sample = main.score_composition(db_row_from_features(rows[0]))
ok("efficiency 不在 scored 裡", "efficiency" not in sample["scored"])
eff_reason = next((u["reason"] for u in sample["unscored"]
                   if u["component"] == "efficiency"), None)
ok("efficiency 有附不計分的理由", bool(eff_reason))
ok("理由要講到分母的問題（不是只說『沒測到』）",
   eff_reason is not None and "time in bed" in eff_reason)

print()
print("=" * 78)
print("【3】0 分鐘是「有測到」，不可當成沒資料")
print("=" * 78)
# ⚠️ WASO 0 分鐘會拿滿分 25、深睡 0 分鐘會拿 0 分，兩者都要算進組成。
#    用真假值判斷就會把它們誤判成沒資料——這是這條在守的東西。
zero_row = {"duration_min": 400.0, "waso_min": 0.0, "deep_min": 0.0, "rem_measured": 0}
z = main.score_composition(zero_row)
ok("WASO 0 分鐘 → 算進組成", "waso" in z["scored"])
ok("深睡 0 分鐘 → 算進組成", "deep" in z["scored"])
ok("REM 沒測到 → 不算進組成", "rem" not in z["scored"])
check("None 才是沒測到",
      "waso" in main.score_composition(
          {"duration_min": 400.0, "waso_min": None,
           "deep_min": 0.0, "rem_measured": 0})["scored"],
      False)

print()
print("=" * 78)
print("【4】scored_weight 等於有算的項目的配分總和")
print("=" * 78)
check("duration+waso+deep（效率不算、REM 沒測到）", z["scored_weight"], 30 + 25 + 10)
full = main.score_composition(
    {"duration_min": 400.0, "waso_min": 10.0, "deep_min": 50.0, "rem_measured": 1})
check("再加上 REM", full["scored_weight"], 30 + 25 + 10 + 10)
ok("效率的 25 分永遠不在裡面", full["scored_weight"] <= 100 - 25)
check("沒有手錶資料那一晚回 None", main.score_composition(None), None)

print()
print("=" * 78)
print("【5】分數的宣稱與警語（2026-10-01 新增）")
print("=" * 78)
# 2026-10-01 使用者決定：這個分數誠實宣稱「以睡眠時長為主」，不是多維度等權合成。
# 依據是四個計分項裡只有 duration 的裝置誤差明確小於它的判讀級距
# （14% vs WASO 的 89–161%，deep/rem 的量級查不到）。詳見 E-3～E-6 與 I 節。
#
# ⚠️ 這幾條守的是「宣稱不會被靜默改掉」。少了它們，之後有人把 primary_component
#    拿掉或把 caveats 清空，API 就會退回「四項看起來一樣可信」的樣子，
#    而**不會有任何錯誤訊息**。

full = main.score_composition(
    {"duration_min": 400.0, "waso_min": 10.0, "deep_min": 50.0, "rem_measured": 1})

check("primary_component 是 duration", full["primary_component"], "duration")
ok("primary_component 一定在 scored 裡",
   full["primary_component"] in full["scored"])

cav = {c["component"] for c in full["caveats"]}
check("有警語的分項", sorted(cav), ["deep", "rem", "waso"])
ok("duration 刻意沒有警語（否則警語就沒有意義）", "duration" not in cav)
ok("每條警語都有內容", all(len(c["caveat"]) > 40 for c in full["caveats"]))

# ⚠️ 警語與「沒測到」是不同的兩件事，不可混為一談。
# ⚠️ 這裡用帶預設值的 next()：警語被拿掉時要**乾淨地回報失敗**，
#    不是丟 StopIteration 把整支測試打斷——崩掉的測試比紅掉的難診斷。
waso_cav = next((c["caveat"] for c in full["caveats"]
                 if c["component"] == "waso"), "")
ok("WASO 的警語要講到「誤差和級距一樣大」這個具體理由",
   "band" in waso_cav)
ok("警語不可以只寫「沒測到」", bool(waso_cav) and "not measured" not in waso_cav)

# 沒測到的分項不該出現在 caveats（它在 unscored，理由不一樣）
partial = main.score_composition(
    {"duration_min": 400.0, "waso_min": 10.0, "deep_min": 50.0, "rem_measured": 0})
pc = {c["component"] for c in partial["caveats"]}
ok("REM 沒測到時，它出現在 unscored 而不是 caveats",
   "rem" not in pc and any(u["component"] == "rem" for u in partial["unscored"]))

# note 要講出「不是等權合成」，否則前端仍會把四項當成一樣可信
ok("note 要說明這是以時長為主、不是等權合成",
   "duration-primary" in full["note"])

print()
print("=" * 78)
print("【6】打包檔的 composition 必須與評分器一致（2026-10-01 新增）")
print("=" * 78)
# 分數組成現在有**三個地方**在講同一件事：
#   評分器（真相）      evaluate_night() 的 *_score 是不是 None
#   打包檔（原樣傳遞）  build_app_payload.composition_for() 直讀那些 *_score
#   API（推論）        main.score_composition() 從資料庫的原始度量推論
#
# 【1】守的是「API 推論 vs 評分器」。這一條守的是「打包檔 vs 評分器」。
# ⚠️ 為什麼打包檔也要守：它雖然是原樣傳遞、理論上不會錯，但**欄位名打錯
#    一個字就會變成「全部都沒算」**，而那看起來完全正常（composition 還是
#    回一個合法的 dict，只是 scored 是空的）。
#
# ⚠️ 打包檔必須帶 composition 的理由（不是可有可無）：首頁分數來自打包檔，
#    警語若改從 API 撈，兩者可能講不同的夜晚——CLAUDE.md 明列的那種
#    「App 顯示的跟 API 回傳的對不上」最難查的 bug。

PAYLOAD = ROOT / "app" / "assets" / "data" / "app_payload.json"
if not PAYLOAD.exists():
    print("  - 跳過（app_payload.json 不存在，先跑 python build_app_payload.py）")
else:
    import json
    payload = json.load(io.open(PAYLOAD, encoding="utf-8"))
    truth_by_date = {}
    for feat in rows:
        graded = ev.evaluate_night(feat)
        truth_by_date[feat["date"]] = {
            k for k in ("duration", "efficiency", "waso", "deep", "rem")
            if graded[k + "_score"] is not None
        }

    hist = payload.get("history") or []
    ok("history 逐夜都有 composition",
       bool(hist) and all(r.get("composition") for r in hist),
       f"{len(hist)} 晚")

    mismatch = [
        (r["date"], sorted(truth_by_date[r["date"]]), sorted(r["composition"]["scored"]))
        for r in hist
        if r.get("composition") and r["date"] in truth_by_date
        and set(r["composition"]["scored"]) != truth_by_date[r["date"]]
    ]
    check("打包檔與評分器不一致的夜晚數", len(mismatch), 0)
    for m in mismatch[:5]:
        print(f"      {m[0]}  評分器 {m[1]}  打包檔 {m[2]}")

    ok("打包檔的 scored 不可以是空的（欄位名打錯就會這樣）",
       all(r["composition"]["scored"] for r in hist if r.get("composition")))

    # 反向對照：樣本裡真的要有兩種組成，否則上面兩條可能假性通過
    kinds = {tuple(r["composition"]["scored"]) for r in hist if r.get("composition")}
    ok("反向對照：打包檔裡有 2 種以上的組成", len(kinds) >= 2,
       f"{len(kinds)} 種")

    top = payload.get("scoring", {}).get("composition")
    ok("scoring.composition 也要有（首頁分數讀這個）", bool(top))
    if top:
        check("最上層的 primary_component", top["primary_component"], "duration")
        # ⚠️ 最上層講的必須是**最新那一晚**，不是隨便一晚
        ok("最上層的組成與 history 最後一晚相同",
           hist and top["scored"] == hist[-1]["composition"]["scored"])

print()
print("=" * 78)
print(f"結果：{'全部通過' if not fails else f'{len(fails)} 項失敗 → {fails}'}")
print("=" * 78)
sys.exit(1 if fails else 0)
