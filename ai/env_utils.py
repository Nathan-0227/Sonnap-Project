"""
env_utils.py — 讀取 ai/.env 的設定

⚠️ 這份是 garmin/garmin_connect_fetch.py 裡 _load_env_file() 的**刻意複製**，
   不是忘記共用。理由：

   兩個子系統要能各自獨立執行。garmin/ 需要 garminconnect 這個第三方套件，
   ai/ 完全不需要（只用標準庫）。若共用同一份 env 工具，ai/ 就得去 import
   garmin/ 底下的東西，那會需要動 sys.path——而這個專案在 2026-08-11 才剛
   花力氣把工作目錄依賴清乾淨，不想再引入路徑魔法。

   代價：**若 .env 的格式規則有變，兩處都要改。** 這裡明寫出來，
   不要留下沉默的複製。

（對照：ai/night_profile.py 確實有 import 專案根目錄的 build_app_payload，
  那是因為那支腳本只用標準庫，import 它不會拖進任何相依套件。
  判斷標準是「會不會多帶進第三方相依」，不是「能不能 import」。）
"""

import os
from pathlib import Path

ENV_FILE = Path(__file__).parent / ".env"


def load_env_file(path: Path = ENV_FILE) -> None:
    """
    把 .env 裡的 KEY=VALUE 讀進環境變數。

    刻意不使用 python-dotenv：專案規範是「優先用標準庫，非必要不加依賴」，
    而這個解析只有十幾行。

    已存在的環境變數**不覆蓋**——這樣 CI 或臨時測試可以直接設環境變數蓋過檔案，
    不必去改 .env。
    """
    if not path.exists():
        return

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value
