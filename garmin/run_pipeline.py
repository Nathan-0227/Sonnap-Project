"""
run_pipeline.py

一次跑完整條 Garmin 睡眠資料 pipeline，避免漏掉中間步驟。

═══════════════════════════════════════════════════════════════════
為什麼需要這支腳本
═══════════════════════════════════════════════════════════════════
這條 pipeline 有 6 個步驟，每一步都吃前一步的輸出。麻煩的是：
**漏跑中間某一步不會報錯，只會安靜地用舊資料算出新結果。**

實際發生過（2026-08-10）：改完 analyze_garmin_sleep.py 之後，只跑了
analyze → evaluate，漏掉中間的 extract_sleep_features。evaluate 照樣
跑得出結果，因為它讀的是三週前產生的 features 檔——沒有任何錯誤訊息，
但算出來的分數其實是用舊資料算的。那次剛好因為改動只是新增欄位而沒有
造成錯誤，但下次就不一定了。

這支腳本用「依序執行、任一步失敗就停」的方式杜絕這個問題。

═══════════════════════════════════════════════════════════════════
使用方式
═══════════════════════════════════════════════════════════════════
    python run_pipeline.py                # 跑步驟 2-6（用現有的原始資料重算）
    python run_pipeline.py --fetch        # 含步驟 1，重新從 Garmin API 抓資料
    python run_pipeline.py --fetch --days 30    # 抓最近 30 天

預設不含步驟 1（抓取），因為抓取要連 Garmin 伺服器、耗時且有頻率限制，
多數情況下你只是改了評分邏輯要重算，不需要重抓原始資料。

最後一步（build_app_payload.py）在專案根目錄而不是 garmin/，因為它要整合
garmin + ai + tapo 三個來源，不屬於任何單一子系統。它的產出
app/assets/data/app_payload.json 同時是 Flutter 打包的 asset 與
main.py 對外服務的資料來源——只有一份檔，所以兩邊不可能不一致。
"""

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

# Windows 的 Git Bash / cmd 預設用 cp1252，印中文會直接 UnicodeEncodeError。
# 這支腳本第一行就會印中文標題，所以沒有這段的話**在跑任何步驟之前就崩掉**。
# （2026-08-12 實測：PowerShell 沒事、Git Bash 直接炸，同一台機器。）
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

# 子行程也要一起處理——它們各自是獨立的 Python 直譯器，不會繼承上面那兩行。
# 設環境變數比逐支腳本加 reconfigure 可靠：新增步驟時不會忘記。
CHILD_ENV = {**os.environ, "PYTHONIOENCODING": "utf-8"}

# 本檔案所在目錄（= garmin/），步驟 1-4 的腳本都在這裡
SCRIPT_DIR = Path(__file__).parent
DATA_DIR = SCRIPT_DIR / "data"
# 專案根目錄，步驟 5 的腳本在這裡
ROOT_DIR = SCRIPT_DIR.parent

# ═══════════════════════════════════════════════════════════════════
# Pipeline 定義：(腳本檔名, 這一步在做什麼, 主要產出)
# 順序就是資料流動的順序，不可任意調換
# ═══════════════════════════════════════════════════════════════════
STEPS = [
    (
        "analyze_garmin_sleep.py",
        "Fold the raw event stream into a one-row-per-night summary",
        "garmin_sleep_summary.csv",
    ),
    (
        "extract_sleep_features.py",
        "Select valid nights and compute scoring features (duration / efficiency / ratios)",
        "garmin_sleep_features.csv",
    ),
    (
        "evaluate_sleep_quality.py",
        "Tier1/2 base score (duration 30 / efficiency 25 / WASO 25 / deep 10 / REM 10)",
        "garmin_sleep_quality.csv",
    ),
    (
        "apply_recovery_modifier.py",
        "Tier3 physiological modifiers (HR / stress / activity / fragmentation) + SRI display",
        "garmin_sleep_quality_final.csv",
    ),
]

# 步驟 5 單獨定義，因為它不在 garmin/ 底下。
# build_app_payload.py 在專案根目錄——它要整合 garmin + ai + tapo 三個來源，
# 不屬於任何單一子系統，放進 garmin/ 會名不副實。
# （同樣的理由，ai/ 也是獨立資料夾而不是塞進 garmin/。）
PAYLOAD_STEP = (
    ROOT_DIR / "build_app_payload.py",
    "Build the single payload the App reads (shared by the Flutter asset and main.py)",
    ROOT_DIR / "app" / "assets" / "data" / "app_payload.json",
)

# AI 步驟也單獨定義，預設不執行（比照 --fetch 的模式）。
#
# 為什麼是 opt-in：設成必跑會破壞 3 秒的開發循環，而且違反本腳本自己的契約
# （任一步失敗即中止）——API 掛掉不該中止一個根本不需要 LLM 的評分重算。
# 但設成完全獨立的腳本又會重演 2026-08-10 那個坑（沒人記得跑，然後安靜地
# 產出過期內容），所以掛在這裡當可選步驟。
#
# 位置在 payload 之前：這樣當晚生成的建議可以直接被 payload 收進去。
AI_STEP = (
    ROOT_DIR / "ai" / "generate_advice.py",
    "Generate AI sleep advice and pet dream diaries (needs ANTHROPIC_API_KEY in ai/.env)",
    ROOT_DIR / "ai" / "data" / "ai_advice.json",
)

# 步驟 1 單獨定義，因為它預設不執行（要連 Garmin 伺服器）
FETCH_STEP = (
    "garmin_connect_fetch.py",
    "Fetch raw data from the Garmin Connect API (needs credentials in .env)",
    "garmin_standard_data.json",
)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Run the Garmin sleep pipeline in order; stop as soon as a step fails."
    )
    parser.add_argument(
        "--fetch",
        action="store_true",
        help="Include step 1 (re-fetch from the Garmin API). Off by default.",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=None,
        help="Use with --fetch to set how many recent days to pull (passed to garmin_connect_fetch.py).",
    )
    parser.add_argument(
        "--ai",
        action="store_true",
        help="Generate AI sleep advice (needs ANTHROPIC_API_KEY). Off by default; "
             "failure in this step does not stop the pipeline.",
    )
    return parser.parse_args()


def run_step(index, total, script, description, output, extra_args=None,
             allow_failure=False):
    """
    執行單一步驟。回傳 True 代表可以繼續往下跑。

    allow_failure=True 時，即使該步驟失敗也回傳 True（只印警告）。
    目前只有 AI 步驟用到：LLM 呼叫失敗不該中止整條評分 pipeline，
    因為後面的步驟完全不需要 AI 的產出就能正確完成。

    用 subprocess 而不是 import 各腳本的 main()，理由：
    每支腳本都是獨立的命令列工具（有自己的 argparse），用 subprocess 呼叫
    等同於使用者手動執行，行為完全一致；若改用 import，argparse 會去讀
    run_pipeline.py 自己的命令列參數而爆掉，還得為此改寫每一支腳本。
    """
    # script / output 可以是「相對 garmin/ 的檔名」或「絕對路徑」。
    # pathlib 的 / 運算子遇到絕對路徑會直接取用它、忽略左邊，
    # 所以步驟 5（在專案根目錄）不需要為它另寫一套邏輯。
    script_path = SCRIPT_DIR / script
    if not script_path.exists():
        print(f"\n\u2717 Not found: {script_path}")
        return False

    print(f"\n{'=' * 70}")
    print(f"[Step {index}/{total}] {script_path.name}")
    print(f"          {description}")
    print(f"{'=' * 70}")

    # sys.executable 而不是寫死 "python"：確保用的是目前這個 Python 環境
    # （虛擬環境、多版本共存時，寫死 "python" 可能會叫到別的直譯器）
    cmd = [sys.executable, str(script_path)]
    if extra_args:
        cmd.extend(extra_args)

    started = time.time()
    result = subprocess.run(cmd, cwd=str(SCRIPT_DIR), env=CHILD_ENV)
    elapsed = time.time() - started

    if result.returncode != 0:
        if allow_failure:
            print(f"\n\u26a0 Step {index} failed (exit code {result.returncode}), "
                  "but this step is allowed to fail, so the pipeline continues.")
            return True
        print(f"\n\u2717 Step {index} failed (exit code {result.returncode}); pipeline aborted.")
        print("  Later steps will not run. This is deliberate: stopping here prevents")
        print("  later steps from reading incomplete or stale data and producing")
        return False

    # 確認產出檔真的有生出來（腳本可能 exit 0 但因為某些分支沒寫檔）
    out_path = DATA_DIR / output
    shown = out_path.relative_to(ROOT_DIR).as_posix()
    if out_path.exists():
        print(f"\n\u2713 Step {index} done ({elapsed:.1f}s) -> {shown}")
    else:
        print(f"\n\u26a0 Step {index} reported success but expected output {shown} is missing; please check.")
    return True


def main():
    args = parse_args()

    # 組出這次要跑的步驟清單
    steps = list(STEPS)
    if args.ai:
        steps.append(AI_STEP)  # 要在 payload 之前，當晚的建議才進得了 payload
    steps.append(PAYLOAD_STEP)
    if args.fetch:
        steps.insert(0, FETCH_STEP)

    total = len(steps)
    print(f"Garmin pipeline: {total} step(s)")
    if not args.fetch:
        print("(no --fetch: skipping the fetch step and recomputing from the existing data/garmin_standard_data.json)")

    started = time.time()
    for i, (script, description, output) in enumerate(steps, start=1):
        # --days 只對抓取步驟有意義，其他步驟不吃這個參數
        extra = None
        if script == FETCH_STEP[0] and args.days is not None:
            extra = ["--days", str(args.days)]

        # AI 步驟允許失敗：LLM 掛掉不該中止一個不需要 LLM 的評分重算
        if not run_step(i, total, script, description, output, extra,
                        allow_failure=(script == AI_STEP[0])):
            # 任一步失敗就整條中止，並用非零 exit code 讓外部（CI、批次檔）也知道失敗
            sys.exit(1)

    elapsed = time.time() - started
    print(f"\n{'=' * 70}")
    print(f"\u2713 Pipeline complete (total {elapsed:.1f}s)")
    print("  Scores:   garmin/data/garmin_sleep_quality_final.csv / .json")
    print("  App data: app/assets/data/app_payload.json")
    print(f"{'=' * 70}")


if __name__ == "__main__":
    main()
