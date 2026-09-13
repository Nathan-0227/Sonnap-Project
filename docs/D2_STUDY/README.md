# D2 使用者實測．操作手冊

> 2026-09-06 建立｜受測者：研究者本人 + 1–2 人｜期間 5–7 晚
>
> 材料：[知情同意書](知情同意書.md)｜[隱私政策](隱私政策.md)｜[招募文](招募文.md)｜[前後測問卷](前後測問卷.md)

## 🔴 開跑前必讀：哪些情況會讓一晚的資料消失

（2026-09-13 改寫。09-06 建立時這裡寫的是「連不到後端那一晚就永久消失」，
那時還沒有離線補送。**09-08 的 `4a48e7a` 補上了**，所以那條已經不成立。）

| 情況 | 會不會掉 | 為什麼 |
|---|---|---|
| 早上開 App 時**連不到後端**（不在同一個 Wi-Fi、後端沒開） | ✅ **不會** | 那一晚先存在手機裡，**下次開 App 而且連得到時**補送（`pending_nightly.dart`）。不會在背景自己送 |
| 手機裡累積超過 **14 晚**沒送出去 | ❌ 最舊的會被丟掉 | 佇列上限 `PendingNightlyStore.maxEntries = 14` |
| 起床後 **24 小時內完全沒開 App** | ❌ **會** | 就寢時刻只往回找 24 小時（`lights_out.dart:180`），沒開 App 就沒有人去找 |
| 研究者電腦的後端**沒連到 MariaDB** | ⚠️ 資料沒掉，但**寫進了另一個空的資料庫**，查資料時會以為沒進來 | 見第一節第 3 步 |

→ 所以要求受測者的只有一件事：**每天開一次 App**，在哪裡開都可以。
→ 研究者這邊：實測期間後端要**常常開著**，受測者手機裡的夜晚才送得進來。

⚠️ 補送只存在 **09-08 之後建置的 APK** 裡。發出去的 APK 比這個舊就要重建。

⚠️ 不要為了讓外面也連得到而把後端丟到公網——這個 API **沒有認證**，
`user_id` 本身就是憑證，公開等於把受測者資料攤開。

---

## 一、開跑前檢查（每一項都要實際跑過）

> 這一節的指令分兩種視窗，**不能混用**：標 `powershell` 的貼進 PowerShell，
> 標 `bash` 的貼進 Git Bash。貼錯視窗會直接出錯（兩者設定環境變數的寫法不同）。

**1. 開資料庫**：打開 XAMPP Control Panel，MySQL 那一列按 **Start**。

沒開的話，要連資料庫的程式會出現 `Can't connect to MySQL server ... (10061)`
（2026-09-13 匯入手錶資料時實際遇到，原因就是忘了開 XAMPP）。
確認佔著資料庫連接埠的是 XAMPP，而不是這台電腦另外裝過的 MySQL：

```powershell
(Get-CimInstance Win32_Process -Filter "ProcessId=$((Get-NetTCPConnection -LocalPort 3306 -State Listen | Select-Object -First 1).OwningProcess)").ExecutablePath
# 應該印出 c:\xampp\mysql\bin\mysqld.exe
```

**2. 查當下 IP**。⚠️ 不要用 `192.168.56.1`（VirtualBox 的虛擬網卡，手機連不到）

```powershell
ipconfig | findstr IPv4
```

**3. 起後端**，三行都要，順序不能換：

```powershell
cd C:\Users\user\Projects\Sonnap-Project
$env:SONNAP_DB_URL="mysql://root@localhost/sonnap"
.venv\Scripts\python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000
```

🔴 **少了第二行不會有任何錯誤訊息**：後端照樣起來、手機照樣連得上、帳號照樣建得起來，
但資料全部寫進 `data/sonnap.db`（另一個空的資料庫），跟 MariaDB 分成兩邊。
之後用第二、三節的指令去查，會以為受測者都沒資料。
（2026-09-10 連踩兩次的是反方向的同一件事：後端寫進 MariaDB，查的人卻去讀 SQLite，
於是得出「少了兩晚」的錯誤結論。詳見 CLAUDE.md「跑著的後端可能根本不是 SQLite」。）

⚠️ 第二行**只對這個視窗有效**。視窗關掉、重開機，都要三行重跑。
⚠️ 實測期間這個視窗要一直開著；由 Claude 在背景啟動的後端活不過一個對話。
⚠️ 出現 `[Errno 10048] only one usage of each socket address` 不是設定錯，
是已經有一個後端在跑了。**從電腦上看不出那一個有沒有連 MariaDB**
（所有後端在程式清單裡長得一模一樣），所以一律把它關掉、照這三行重開。
找不到那個視窗的話，CLAUDE.md 有一段指令可以找出是誰佔著 8000。

**4. 防火牆**：後端起來之後在 **PowerShell** 跑。查的是防火牆有沒有放行
「實際開著 8000 埠的程式」，至少要有一列 `Allow` 且 Profile 含 `Public`：

```powershell
$exe = (Get-NetTCPConnection -LocalPort 8000 -State Listen |
  ForEach-Object { Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)" }).ExecutablePath
Get-NetFirewallApplicationFilter | Where-Object { $_.Program -eq $exe } |
  Get-NetFirewallRule | Select-Object DisplayName, Enabled, Action, Profile
```

⚠️ 開埠的是**系統 Python**，不是 venv 的 python.exe（venv 那支只是轉介），
所以查 `Sonnap venv python (demo)` 那條沒有意義——2026-09-13 實測把它停用，
手機照樣連得到。原因見 CLAUDE.md「手機連後端」一節。

**5. 建 APK**：

```bash
# ⚠️ 千萬不要帶 SONNAP_USER_ID——那會讓所有受測者變成同一個人
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
6. 確認他手機上真的建立了帳號（在 `Sonnap-Project` 目錄開 Git Bash 跑）：

```bash
SONNAP_DB_URL=mysql://root@localhost/sonnap PYTHONIOENCODING=utf-8 \
.venv/Scripts/python.exe -c "import db;c=db.connect();[print(dict(r)) for r in c.execute('SELECT user_id, display_name, created_at FROM users')];c.close()"
```

⚠️ 第一行的 `SONNAP_DB_URL=...` 不能省：省了會去查另一個空的資料庫，**永遠查不到人**。
`PYTHONIOENCODING=utf-8` 是給中文暱稱用的，Git Bash 預設編碼印中文會直接報錯。
→ **手機明明建好帳號、這裡卻查不到** → 八成是後端啟動時少了第一節第 3 步的第二行，
  帳號被建進了空的那個資料庫。先關掉後端照第一節重開。
  ⚠️ 但**重開 App 救不回來**：手機會記住第一次建的帳號、不會再建一次，
  而那個帳號在 MariaDB 裡不存在，之後每一次上傳都會失敗。
  這種情況目前**沒有現成的處理指令**，發生時先停下來處理，不要繼續收資料。

⚠️ 註冊畫面**不得出現「安全」「加密」字眼**（有測試守著）——
那會與同意書第 4 節自相矛盾。
⚠️ `user_id` 不要唸出來、不要截圖傳、不要寫進任何檔案。

## 三、每天要做的事

**受測者**：早上開一次 App（在能連到後端的 Wi-Fi 底下），30 秒。

**研究者**：確認資料真的進來了。

```bash
SONNAP_DB_URL=mysql://root@localhost/sonnap PYTHONIOENCODING=utf-8 \
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

⚠️ `db.py` **沒有** `list_users()`，所以這裡直接下 SQL。
上面兩段 2026-09-13 在 MariaDB 上照抄實測跑過（09-06 那次跑的是 SQLite，當時沒有第一行）。

**有人某天沒有資料就當天問**，不要等到最後才發現。最常見的原因是
沒開 App 或不在同一個 Wi-Fi——而那一晚**補不回來**（見開頭）。

## 四、有人要退出

不問理由，當場執行：

```bash
curl -X DELETE http://127.0.0.1:8000/users/<user_id>
```

連鎖刪除會把 `nightly_behavior`、`wearable_nightly` 等全部清掉
（`db.py` 的 `delete_user()`；`tests/test_api.py` 的「CASCADE 後沒有孤兒資料」那條測試在守）。
✅ 2026-09-13 查過 MariaDB：**13 個外鍵全部是 CASCADE**，每一張有 `user_id` 的表都有掛，
沒有漏網的表。（那條測試跑的是 SQLite，所以 MariaDB 這邊是另外查的。）

刪完回報給他，並確認：

```bash
SONNAP_DB_URL=mysql://root@localhost/sonnap \
.venv/Scripts/python.exe -c "import db;print(db.get_user('<user_id>'))"   # 應為 None
```

⚠️ 同樣不能省第一行：省了會去空的資料庫查，**沒刪乾淨也會印出 None**。

## 五、結束

1. 填[後測問卷](前後測問卷.md)（三個部分都填）+ 訪談
2. 導出彙總資料
3. **關掉伺服器**、移除防火牆規則：
   ```powershell
   Remove-NetFirewallRule -DisplayName "Sonnap venv python (demo)"   # 對連線沒作用，只是清掉雜訊
   ```
   ⚠️ **這一步不會把門關上。** 真正放行後端的是系統 Python 那四條 `python.exe` 規則
   （Windows 跳窗時有人按了允許產生的），它們放行**這台電腦上任何 Python 程式、
   任何埠、連公用網路也算**。要不要刪由電腦主人決定——不是專案加的，可能有別的用途。
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
