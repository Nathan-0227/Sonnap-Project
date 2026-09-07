# D2 使用者實測．操作手冊

> 2026-09-06 建立｜受測者：研究者本人 + 1–2 人｜期間 5–7 晚
>
> 材料：[知情同意書](知情同意書.md)｜[隱私政策](隱私政策.md)｜[招募文](招募文.md)｜[前後測問卷](前後測問卷.md)

## 🔴 開跑前必讀：一個會讓整個實測拿不到資料的結構問題

**受測者早上開 App 的那一刻，如果連不到後端，那一晚的資料就永久消失。**

三件事湊在一起造成的：

| 事實 | 位置 |
|---|---|
| 就寢時刻的查詢視窗是**往回 24 小時的滑動視窗** | `lights_out.dart:180` `kLightsOutWindow = Duration(hours: 24)` |
| 上傳是一次性的，**失敗不留任何東西**，沒有佇列也沒有重試 | `nightly_uploader.dart` 全檔沒有 `store` / `queue` / `retry` |
| 後端在研究者電腦上，**只有同一個 Wi-Fi 連得到**，IP 還是編譯期參數 | `--dart-define=SONNAP_API_BASE` |

→ 隔天再開 App 也救不回來：視窗已經滑過去了，昨晚那段安靜期不在裡面。

### 因應（依優先序）

1. **先做離線佇列再發 APK。** 上傳失敗就把 `lights_out_at` 存進本機
   （用既有的 `KeyValueStore` / `sonnap/store`，不必裝新套件），下次開 App 補送。
   這樣受測者在哪裡開 App 都沒差，回到同一個 Wi-Fi 才真正送出。
   **這是 B1 的第一項，優先於挑戰進度卡**——沒有它可能整個實測沒有資料。
2. 在那之前，只收**同一個 Wi-Fi 底下的室友**，並要求早上在家開 App。
3. 研究者的筆電在實測期間**每天早上都要開著並跑著伺服器**。

⚠️ 不要為了繞過這件事把後端丟到公網——這個 API **沒有認證**，
`user_id` 本身就是憑證，公開等於把受測者資料攤開。

---

## 一、開跑前檢查（每一項都要實際跑過）

```bash
# 1. 查當下 IP。⚠️ 不要用 192.168.56.1（VirtualBox host-only，手機連不到）
ipconfig | findstr IPv4

# 2. 起後端，一定要綁 0.0.0.0
.venv/Scripts/python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000

# 3. 防火牆規則還在嗎（綁的是程式不是埠，換過 venv 就失效且無錯誤訊息）
powershell -Command "Get-NetFirewallRule -DisplayName 'Sonnap venv python (demo)'"

# 4. 建 APK。⚠️ 千萬不要帶 SONNAP_USER_ID——那會讓所有受測者變成同一個人
cd app && flutter build apk --debug \
  --dart-define=SONNAP_API_BASE=http://<當下的IP>:8000
```

⚠️ **驗證只能從手機做。** 同一台機器打自己的區網 IP **不經過防火牆**，
09-01 那次差點誤判成「已經通了」。請用手機瀏覽器開 `http://<IP>:8000/health`。

⚠️ 明碼 HTTP 不需要改 manifest。三個 manifest 都沒有 `usesCleartextTraffic`，
卻實測連得上——因為 `dart:io` 的 `HttpClient` 走 Dart VM 自己的 socket，
不經過 Android 的 NetworkSecurityPolicy。**如果哪天有人把資料層換成
platform-backed 的 HTTP client，這件事會安靜地壞掉。**

## 二、招募與同意（每位受測者）

1. 傳 [招募文](招募文.md)
2. 有意願 → 傳 [知情同意書](知情同意書.md)，**當面或視訊講過第 3.3 節
   （無障礙權限讀得到螢幕）與第 4 節（沒有認證）**，不要只丟檔案
3. 簽名（拍照或電子簽都可以）
4. 填[前測問卷](前後測問卷.md)第一、二部分
5. 傳 APK，陪他裝完並開權限
6. 確認他手機上真的建立了帳號：

```bash
.venv/Scripts/python.exe -c "import db;c=db.connect();[print(dict(r)) for r in c.execute('SELECT user_id, display_name, created_at FROM users')];c.close()"
```

⚠️ 註冊畫面**不得出現「安全」「加密」字眼**（有測試守著）——
那會與同意書第 4 節自相矛盾。
⚠️ `user_id` 不要唸出來、不要截圖傳、不要寫進任何檔案。

## 三、每天要做的事

**受測者**：早上開一次 App（在能連到後端的 Wi-Fi 底下），30 秒。

**研究者**：確認資料真的進來了。

```bash
.venv/Scripts/python.exe -c "
import db
c = db.connect()
users = [dict(r) for r in c.execute('SELECT user_id, display_name FROM users')]
c.close()
for u in users:
    rows = db.get_nightly_behavior(u['user_id'], days=14)
    print(f\"{u['display_name']:<22} {len(rows):>2} nights {[r['date'] for r in rows]}\")
"
```

⚠️ `db.py` **沒有** `list_users()`，所以這裡直接下 SQL。上面兩段都實測跑過。

**有人某天沒有資料就當天問**，不要等到最後才發現。最常見的原因是
沒開 App 或不在同一個 Wi-Fi——而那一晚**補不回來**（見開頭）。

## 四、有人要退出

不問理由，當場執行：

```bash
curl -X DELETE http://127.0.0.1:8000/users/<user_id>
```

連鎖刪除會把 `nightly_behavior`、`wearable_nightly` 等全部清掉
（`db.py:572`；`tests/test_api.py:264` 有一條測試在守「刪完不能留下孤兒資料」）。
刪完回報給他，並確認：

```bash
.venv/Scripts/python.exe -c "import db;print(db.get_user('<user_id>'))"   # 應為 None
```

## 五、結束

1. 填[後測問卷](前後測問卷.md)（三個部分都填）+ 訪談
2. 導出彙總資料
3. **關掉伺服器**、移除防火牆規則：
   ```powershell
   Remove-NetFirewallRule -DisplayName "Sonnap venv python (demo)"
   ```
4. 報告完成後刪除原始資料（同意書第四節的承諾）

## 六、報告怎麼寫才誠實

| 不能寫 | 要寫成 |
|---|---|
| 「顯著改善睡眠拖延」 | 「3 人中 2 人自譯量表分數下降」——n=3 不做統計檢定 |
| 「BPS 得分 X，高於常模」 | 量表是我們自譯的，**未經信效度驗證**，只能做組內前後比較 |
| 「App 測到入睡時間」 | 測的是**最後一次操作手機**，是替代測量。有人放下手機後還會躺半小時 |
| 「使用者手機使用時間」 | `totalTimeInForeground` 是替代測量，與系統「數位健康」量的不是同一件事（實測 Instagram 差 2.7 倍） |
| 隱瞞前後測只隔 5–7 天 | 練習效應與期望效應都排除不掉，寫進限制一節 |

受測者知道研究者想看到什麼，這本身就是一個限制。誠實標註比藏起來有價值——
比照本專案對 `sleep_efficiency`（分母不含入睡潛伏期）的既有處理標準。
