from fastapi import FastAPI

app = FastAPI()

# 將你這份精美的資料直接放進去
mock_data = {
  "session_id": "20260512_001",
  "status": {
    "pet_mood": "happy", 
    "current_activity": "dreaming",
    "energy_level": 85
  },
  "metrics": {
    "motion_count": 12,
    "sleep_duration_minutes": 240,
    "ambient_noise_db": 35
  },
  "ai_content": {
    "dream_summary": "Tonight, the little creature dreamed of floating on a giant marshmallow in a starry sky.",
    "advice": "You had a very calm night, keep up the good work!"
  },
  "timestamp": "2026-05-12T22:00:00Z"
}

@app.get("/get-sleep-data")
async def get_sleep_data():
    return mock_data
