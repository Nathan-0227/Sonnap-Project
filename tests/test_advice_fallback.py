"""
tests/test_advice_fallback.py —— LLM 失敗時，夢境要退回規則式文字，不能整批中斷

2026-11-06 金鑰失效（HTTP 401）時發現：make_fallback() 的四段文字在英文化
（ec7bc8b）時漏了 Good/Normal/Poor/Bad 的鍵，變成沒有鍵的 set，
LLM 一失敗就 AttributeError，27 晚一晚都沒寫進去。

  【1】四個品質等級各拿到自己的那段文字；不認得的等級退回 Normal
  【2】API 失敗時 generate_one() 回 fallback 而不是丟例外（用真實的一晚）
  【3】fallback 下次會被重新生成（needs_generation）——不然換好金鑰也補不回來

⚠️ 不打真的 Claude API：金鑰先清空，complete_json 換成一律丟 LLMError 的假函式。
執行：python tests/test_advice_fallback.py
"""
import os
import sys
from pathlib import Path

os.environ["ANTHROPIC_API_KEY"] = ""          # 一定要在 import 之前

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "ai"))

import generate_advice as ga                   # noqa: E402
from llm_client import LLMError                # noqa: E402

fails = []


def check(label, got, want):
    good = got == want
    print(f"  {'✓' if good else '✗'} {label}" + ("" if good else f"：得到 {got!r}，應為 {want!r}"))
    if not good:
        fails.append(label)


def _raise(*_a, **_k):
    raise LLMError("HTTP 401：invalid x-api-key")


ga.complete_json = _raise                      # 結構上不可能打到網路

print("【1】四個等級各有文字")
texts = {}
for q in ("Good", "Normal", "Poor", "Bad"):
    fb = ga.make_fallback({"final_quality": q, "recommendation": "r"})
    texts[q] = fb["dream_summary"]
    check(f"{q}：有文字且標成 fallback",
          (bool(fb["dream_summary"]), fb["source"], fb["is_ai_generated"]),
          (True, "fallback", False))
check("四段文字彼此不同", len(set(texts.values())), 4)
check("不認得的等級退回 Normal",
      ga.make_fallback({"final_quality": "???"})["dream_summary"], texts["Normal"])

print("【2】API 失敗時不中斷（真實的一晚）")
nights = ga.load_nights()
profile = ga.build_profile(nights[-1]["date"], nights)
try:
    entry, ok = ga.generate_one(profile, verbose=False)
    check("回傳 ok=False", ok, False)
    check("source 是 fallback", entry["source"], "fallback")
    check("advice 照抄規則式建議", entry["advice"], profile.get("recommendation") or "")
except Exception as exc:                       # noqa: BLE001
    check(f"generate_one 不得丟例外（{type(exc).__name__}: {exc}）", False, True)

print("【3】fallback 下次會重生")
check("needs_generation 回 True",
      ga.needs_generation({"source": "fallback"}, "fp", refresh_stale=False)[0], True)

print()
if fails:
    print(f"✗ {len(fails)} 項失敗")
    sys.exit(1)
print("✓ 全部通過")
