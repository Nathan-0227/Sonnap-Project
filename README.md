# Sonnap: AI Sleep Companion 🌙

Sonnap 是一款結合「睡眠監測」與「AI 寵物陪伴」的創新應用。我們透過影像辨識技術分析使用者的睡眠狀態，並由 AI 生成專屬的夢境日記，讓睡眠不再只是休息，更是一場療癒的體驗。

## 👥 團隊成員與分工
- **[你的名字]**：專案經理 (PM) / 系統整合
- **[組員A]**：UI/UX 設計師
- **[組員B]**：前端開發 (App)
- **[組員C]**：影像工程 (Python/OpenCV)
- **[組員D]**：AI 與數據處理

## ⚙️ 系統架構 (Data Contract)
我們使用 JSON 格式進行模組間的數據溝通：
```json
{
  "pet_mood": "happy",
  "motion_count": 12,
  "dream_summary": "Tonight, the little creature dreamed of floating on a giant marshmallow.",
  "timestamp": "2026-05-12T22:00:00Z"
}
