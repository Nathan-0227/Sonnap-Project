"""
main.py — Sonnap 後端 API

對外提供 App 需要的睡眠資料。資料來源是 build_app_payload.py 產生的
app/assets/data/app_payload.json——**跟 Flutter 打包進 App 的是同一個檔案**。

為什麼共用同一個檔而不各自產一份：兩份就會出現「App 畫面顯示的」跟
「API 回傳的」對不上這種最難查的 bug。同一個檔案兩種讀法，
結構上就不可能不一致。

啟動：
    uvicorn main:app --reload
    uvicorn main:app --host 0.0.0.0 --port 8000    # 要讓手機連進來時用
"""

import json
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="Sonnap API")

# Flutter web 版（flutter run -d chrome）是從另一個 origin 發請求，
# 沒有 CORS 設定一定會被瀏覽器擋掉，而且錯誤訊息出現在瀏覽器 console、
# 後端這邊完全看不到，很容易誤判成「API 壞了」。
# 學生專案的開發階段全開；正式部署要收斂成實際的前端網域。
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)

PAYLOAD_PATH = Path(__file__).parent / "app" / "assets" / "data" / "app_payload.json"


@app.get("/get-sleep-data")
async def get_sleep_data():
    """
    回傳最新一晚的完整睡眠資料。

    ⚠️ 檔案不存在時回 503，**不 fallback 回假資料**。
       這是刻意的：本專案 2026-08-10 踩過「漏跑中間步驟不會報錯，
       只會安靜地用舊資料算出結果」的坑。若這裡回一份寫死的 mock，
       「忘記跑 pipeline」看起來就會跟正常運作一模一樣，
       而那正是最難發現的失敗模式。寧可明確地壞掉。
    """
    if not PAYLOAD_PATH.exists():
        raise HTTPException(
            status_code=503,
            detail=(
                "尚未產生資料檔 app/assets/data/app_payload.json。"
                "請先執行：python garmin/run_pipeline.py"
            ),
        )

    # 每次請求都重讀而不快取在記憶體：檔案只有幾 KB，重讀的成本可以忽略，
    # 換來的是重跑 pipeline 之後不必重啟伺服器就能看到新資料。
    try:
        with PAYLOAD_PATH.open(encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        raise HTTPException(
            status_code=500,
            detail=f"app_payload.json 格式損毀：{exc}。請重新執行 pipeline 產生。",
        ) from exc


@app.get("/health")
async def health():
    """讓前端/隊友快速確認伺服器活著、以及資料檔在不在。"""
    return {
        "status": "ok",
        "payload_available": PAYLOAD_PATH.exists(),
    }
