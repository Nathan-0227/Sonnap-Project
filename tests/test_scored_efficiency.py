"""
tests/test_scored_efficiency.py —— 首頁效率小卡顯示「進分數的效率」（2026-11-13）

守的東西：
   【1】每一種 basis 都有小卡那行字，而且字只在 score_claim 定義
   【2】score_claim 的 basis 字串與 behavior/sleep_efficiency.py 的常數一致（刻意不互相 import）
   【3】打包檔每晚的 scored_efficiency 逐夜等於評分器的 efficiency_used（直讀、不推論）
   【4】今晚的 metrics 與 history 最後一晚同一個值（首頁小卡與「跟上一晚比」講同一晚）

執行：python tests/test_scored_efficiency.py
"""
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import score_claim  # noqa: E402
from behavior import sleep_efficiency as se  # noqa: E402

fails = []


def check(label, got, want):
    good = got == want
    print(f"  {'✓' if good else '✗'} {label:<60} {got!r}" + ("" if good else f"  期望 {want!r}"))
    if not good:
        fails.append(label)


print("\n【1】每一種 basis 都有小卡那行字")
check("與警語涵蓋同一組 basis",
      set(score_claim.EFFICIENCY_BASIS_LABELS), set(score_claim.EFFICIENCY_CAVEATS))
check("每行字都短到放得進小卡（≤ 26 字元）",
      all(len(v) <= 26 for v in score_claim.EFFICIENCY_BASIS_LABELS.values()), True)

print("\n【2】basis 字串與 behavior 的常數一致")
check("三個常數都在",
      {se.MEASURED_EFFICIENCY_BASIS, se.WATCH_WAKE_EFFICIENCY_BASIS, se.WATCH_ONLY_EFFICIENCY_BASIS},
      set(score_claim.EFFICIENCY_BASIS_LABELS))

print("\n【3】打包檔直讀評分器")
check("沒有評分列 → 三個 None", score_claim.scored_efficiency(None), (None, None, None))
check("直讀 efficiency_used／basis",
      score_claim.scored_efficiency({"efficiency_used": 90.7,
                                     "efficiency_basis": se.WATCH_WAKE_EFFICIENCY_BASIS}),
      (90.7, se.WATCH_WAKE_EFFICIENCY_BASIS, "Start sleep to watch wake"))

import build_app_payload as payload  # noqa: E402

if (payload.GARMIN_DATA / "garmin_sleep_quality_final.json").exists():
    d = payload.build_payload()
    base = {r["date"]: r for r in payload.load_json(payload.GARMIN_DATA / "garmin_sleep_quality.json")}
    bad = [h["date"] for h in d["history"]
           if h["scored_efficiency"] != base.get(h["date"], {}).get("efficiency_used")
           or h["scored_efficiency_basis"] != base.get(h["date"], {}).get("efficiency_basis")]
    check("每晚都等於評分器的 efficiency_used／basis", bad, [])
    print("\n【4】今晚的 metrics 與 history 最後一晚同一個值")
    m, last = d["metrics"], d["history"][-1]
    check("值、basis、字都一樣",
          (m["scored_efficiency"], m["scored_efficiency_basis"], m["scored_efficiency_label"]),
          (last["scored_efficiency"], last["scored_efficiency_basis"], last["scored_efficiency_label"]))
else:
    print("  （沒有評分檔，跳過【3】後半與【4】）")

print()
if fails:
    print(f"✗ {len(fails)} 項失敗：")
    for f in fails:
        print(f"   - {f}")
    sys.exit(1)
print("✓ 全部通過")
