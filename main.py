from fastapi import FastAPI

app = FastAPI()

# 這就是你們定義的「數據合約」範本
mock_data = {
    "motion_count": 15,
    "light_level": "dim",
    "dream_summary": "夢見在廣闊的草原上奔跑，心情愉悅。",
    "recommendation": "睡眠品質良好，請保持規律作息。"
}

@app.get("/get-sleep-data")
async def get_sleep_data():
    # 當前端呼叫這個網址時，回傳上面的數據
    return mock_data

# 啟動指令：uvicorn main:app --reload
