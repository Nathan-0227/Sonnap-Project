"""
run_pipeline.py

一次跑完整條 Garmin 睡眠資料 pipeline，避免漏掉中間步驟。

═══════════════════════════════════════════════════════════════════
為什麼需要這支腳本
═══════════════════════════════════════════════════════════════════
這條 pipeline 有 5 個步驟，每一步都吃前一步的輸出。麻煩的是：
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
    python run_pipeline.py                # 跑步驟 2-5（用現有的原始資料重算）
    python run_pipeline.py --fetch        # 含步驟 1，重新從 Garmin API 抓資料
    python run_pipeline.py --fetch --days 30    # 抓最近 30 天

預設不含步驟 1（抓取），因為抓取要連 Garmin 伺服器、耗時且有頻率限制，
多數情況下你只是改了評分邏輯要重算，不需要重抓原始資料。
"""

import argparse
import subprocess
import sys
import time
from pathlib import Path

# 本檔案所在目錄（= garmin/），所有步驟腳本都在這裡
SCRIPT_DIR = Path(__file__).parent
DATA_DIR = SCRIPT_DIR / "data"

# ═══════════════════════════════════════════════════════════════════
# Pipeline 定義：(腳本檔名, 這一步在做什麼, 主要產出)
# 順序就是資料流動的順序，不可任意調換
# ═══════════════════════════════════════════════════════════════════
STEPS = [
    (
        "analyze_garmin_sleep.py",
        "把原始事件流整理成「每晚一列」的彙整表",
        "garmin_sleep_summary.csv",
    ),
    (
        "extract_sleep_features.py",
        "挑出有效夜晚、算出評分要用的特徵（時長/效率/比例…）",
        "garmin_sleep_features.csv",
    ),
    (
        "evaluate_sleep_quality.py",
        "Tier1/2 基礎分數（時長30/效率25/WASO25/深睡10/REM10）",
        "garmin_sleep_quality.csv",
    ),
    (
        "apply_recovery_modifier.py",
        "Tier3 生理修正值（心率/壓力/活動量/片段化）+ SRI 呈現",
        "garmin_sleep_quality_final.csv",
    ),
]

# 步驟 1 單獨定義，因為它預設不執行（要連 Garmin 伺服器）
FETCH_STEP = (
    "garmin_connect_fetch.py",
    "連 Garmin Connect API 抓原始資料（需要 .env 裡的帳密）",
    "garmin_standard_data.json",
)


def parse_args():
    parser = argparse.ArgumentParser(
        description="依序執行 Garmin 睡眠資料 pipeline，任一步失敗即中止。"
    )
    parser.add_argument(
        "--fetch",
        action="store_true",
        help="包含步驟 1（從 Garmin API 重新抓資料）。預設不執行。",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=None,
        help="搭配 --fetch 使用，指定要抓最近幾天（傳給 garmin_connect_fetch.py）。",
    )
    return parser.parse_args()


def run_step(index, total, script, description, output, extra_args=None):
    """
    執行單一步驟。回傳 True 代表成功。

    用 subprocess 而不是 import 各腳本的 main()，理由：
    每支腳本都是獨立的命令列工具（有自己的 argparse），用 subprocess 呼叫
    等同於使用者手動執行，行為完全一致；若改用 import，argparse 會去讀
    run_pipeline.py 自己的命令列參數而爆掉，還得為此改寫每一支腳本。
    """
    script_path = SCRIPT_DIR / script
    if not script_path.exists():
        print(f"\n✗ 找不到 {script}，pipeline 中止。")
        return False

    print(f"\n{'=' * 70}")
    print(f"[步驟 {index}/{total}] {script}")
    print(f"          {description}")
    print(f"{'=' * 70}")

    # sys.executable 而不是寫死 "python"：確保用的是目前這個 Python 環境
    # （虛擬環境、多版本共存時，寫死 "python" 可能會叫到別的直譯器）
    cmd = [sys.executable, str(script_path)]
    if extra_args:
        cmd.extend(extra_args)

    started = time.time()
    result = subprocess.run(cmd, cwd=str(SCRIPT_DIR))
    elapsed = time.time() - started

    if result.returncode != 0:
        print(f"\n✗ 步驟 {index} 失敗（exit code {result.returncode}），pipeline 中止。")
        print("  後續步驟不會執行——這是刻意的：讓失敗停在這裡，")
        print("  避免後面的步驟拿到不完整或過期的資料，算出看似正常實則錯誤的結果。")
        return False

    # 確認產出檔真的有生出來（腳本可能 exit 0 但因為某些分支沒寫檔）
    out_path = DATA_DIR / output
    if out_path.exists():
        print(f"\n✓ 步驟 {index} 完成（{elapsed:.1f} 秒）→ data/{output}")
    else:
        print(f"\n⚠ 步驟 {index} 回報成功，但找不到預期產出 data/{output}，請檢查。")
    return True


def main():
    args = parse_args()

    # 組出這次要跑的步驟清單
    steps = list(STEPS)
    if args.fetch:
        steps.insert(0, FETCH_STEP)

    total = len(steps)
    print(f"Garmin pipeline：共 {total} 個步驟")
    if not args.fetch:
        print("（未加 --fetch，跳過抓取步驟，直接用現有的 data/garmin_standard_data.json 重算）")

    started = time.time()
    for i, (script, description, output) in enumerate(steps, start=1):
        # --days 只對抓取步驟有意義，其他步驟不吃這個參數
        extra = None
        if script == FETCH_STEP[0] and args.days is not None:
            extra = ["--days", str(args.days)]

        if not run_step(i, total, script, description, output, extra):
            # 任一步失敗就整條中止，並用非零 exit code 讓外部（CI、批次檔）也知道失敗
            sys.exit(1)

    elapsed = time.time() - started
    print(f"\n{'=' * 70}")
    print(f"✓ Pipeline 全部完成（總耗時 {elapsed:.1f} 秒）")
    print(f"  最終結果：data/garmin_sleep_quality_final.csv / .json")
    print(f"{'=' * 70}")


if __name__ == "__main__":
    main()
