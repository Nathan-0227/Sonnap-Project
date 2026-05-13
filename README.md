# Sonnap: AI Sleep Companion 🌙

Sonnap 是一款結合「睡眠監測」與「AI 寵物陪伴」的創新應用。我們透過影像辨識技術分析使用者的睡眠狀態，並由 AI 生成專屬的夢境日記，讓睡眠不再只是休息，更是一場療癒的體驗。

## 👥 團隊成員與分工
- 李嘉友：專案經理 (PM) / 系統整合
- 王皓渝：UI/UX 設計師（用Figma）
- Jeremy：前端開發 (App)
- Elvira：影像工程 (Python/OpenCV)
- 陳泰銘：AI 與數據處理

🚀 專案進度
 攝影機影像串流測試
 UI 原型設計 (Figma)
 翻身偵測演算法開發
 AI 夢境生成 API 串接
 系統整合與 Demo 測試
 
🔗 相關資源
Figma 設計稿： [(https://www.figma.com/files/team/1633021850224699912/recents-and-sharing?fuid=1633021848674802056)]

開發環境： Python 3.x, Flutter/React Native

## ⚙️ 系統架構 (Data Contract)
我們使用 JSON 格式進行模組間的數據溝通：
```json
{
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

```

欄位說明 (給開發者的指南)

欄位名稱	類型	說明

pet_mood	String	寵物心情：happy, tired, bored, anxious

current_activity	String	當前動畫狀態：sleeping, dreaming, waking_up

motion_count	Integer	翻身次數（由影像組提供）

dream_summary	String	由 Gemini API 生成的夢境描述

energy_level	Integer	0-100，影響寵物動畫的活躍度
