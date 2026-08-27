# Sonnap 開發日誌（歷史記錄）

> 這份檔案是**過程記錄**，不是指令。
> 每一輪做了什麼、量到什麼數字、踩過什麼坑，逐輪往下記，**新的在上面**。
>
> ⚠️ **不要照著這份檔案做事。** 裡面的「下一步」「待辦」都是寫下當時的狀態，
> 現在極可能已經過期。現行的規則、語意與下一步一律以
> [CLAUDE.md](CLAUDE.md) 為準；這裡只用來回答「當初為什麼這樣決定」。
>
> 從 CLAUDE.md 搬過來的內容**逐字未改**（2026-08-26 拆分）。

---

## 📌 2026-08-28（凌晨 02:00–03:00）九件收尾：憑證、Insights 欄位、baseline、意象去重、有效性、回歸測試、報告文件、攝影機上床時刻、清點腳本

使用者睡前交代「繼續完成專案」，這一輪做的是**把已經診斷完、只差動手的項目清掉**，
不開新戰線。四件事都有實測數字。

### ⚠️ 這一輪是兩個 session 並行，而且真的踩到了

另一個 session 同時在同一份 working copy 上跑。**我建了
`feature/insights-sleep-times` 之後、commit 之前，對方把 HEAD 切回了
`feature/pet-mood-animation`**，所以我那個 commit（`4aff730`）落在
pet-mood-animation 上，而不是我自己建的那支分支——`feature/insights-sleep-times`
到現在還停在 `main`，是空的。

事後核對：`a4229d2`（對方）只動 `CLAUDE.md`，我的三個 commit 只含我自己的檔案，
**沒有交叉、沒有遺失**。但這是運氣，不是機制。

→ **並行時不要做分支手術。** 我發現之後就停手不再動分支結構，
  留給使用者早上決定，因為在另一個 agent 會移動 HEAD 的情況下 rebase／
  cherry-pick 正是最容易弄丟東西的操作。
→ `git branch --show-current` 的結果**在你下一個指令之前就可能過期**。

### ① `tapo 2.0/.env`：能做的做了，真正的止血做不到

08-27 影像組用 GitHub 網頁上傳誤傳了含 RTSP 帳密與 `DB_PASSWORD` 的 `.env`，
而這個 repo 是**公開的**（未認證打 `api.github.com/repos/...` 回 200，這是判定依據）。

做了：`git rm --cached` + 產生 `.env.example`（機敏欄位佔位符、調校參數保留預設值，
其他人 clone 下來仍跑得動）+ 把根因寫進 CLAUDE.md 的常設安全規範。

**沒做，而且刻意不做：**

- **不改寫已推送的公開歷史、不 force-push。** 那會改掉所有協作者的 commit hash，
  是團隊決定不是一個人能單方面做的。
- **remediation 步驟寫進 scratchpad，不 commit 進 repo。** 在公開倉庫裡放一份
  「這裡外洩過密碼」的文件等於幫人指路。commit message 也刻意寫成中性的
  「改附 .env.example」而不是「移除外洩憑證」。

⚠️ **移除檔案不等於止血。** 密碼在公開網路上放過就是放過了，
唯一有效的動作是去 Tapo App 改 RTSP 密碼、改 MySQL 密碼——只有影像組做得到。

### ② `GET /insights` 的 `sleep_start_time` / `wake_time`：文件說三處，實際五處

CLAUDE.md 寫「要補是三處」。照著做會漏掉兩處：

| # | 位置 | 漏了會怎樣 |
|---|---|---|
| 3 | `db.py` 的 `upsert_wearable_nightly` 欄位白名單 | 拋 `ValueError`，跑一次就發現 |
| 5 | `healthconnect_adapter.py` 的 `to_wearable_row` | **不會報錯**——只有 HC 來源缺值，Garmin 有值 |

第 3 處是被白名單擋下來的，而那個白名單的註解正好寫著它存在的理由：
「呼叫端打錯鍵名會立刻拋錯而不是被安靜忽略」。它兌現了。

第 5 處才是危險的那個：不補的話，bug 只在「使用 Health Connect 的使用者」
身上出現，而我們手上一晚 HC 真實資料都沒有 → 到 demo 當天才會發現。

實測：51 晚全部有值、與 `app_payload.json` 的 history 30/30 逐字相同、
分數欄位逐列未變。新增 7 項驗收，關鍵那條是
**「不等於 session 起訖、也不等於 `lights_out_at`」**——
三個構念（上床／睡著／放下手機）在這裡第一次被測試明確釘住。

### ③ baseline 窗格：`MAX_BASELINE_NIGHTS` → `MAX_BASELINE_DAYS`

舊寫法取 `history[-28:]`，是**28 筆**不是 28 天。51 晚裡有 28 個日曆日沒戴錶，
所以「最近 28 筆」可能橫跨兩三個月——正好違背這個常數自己存在的理由。

改法：histories 改存 `(日期, 值)`，依日曆天夾窗。

| | |
|---|---|
| 分數改變 | 17 晚，最大位移 **1.60**、平均 0.129 |
| 品質等級改變 | **0 晚** |
| 最新一晚 | 不變（happy / 82.2 Good） |
| 「原本沒 baseline、改完才有」 | **0**（驗證只會更嚴、不會更鬆） |
| 改為停用 | 3 晚的 `stress_modifier` |

那 3 晚全是 `presleep_stress_score`——它要求前一晚也戴錶，是最稀疏的訊號，
所以日曆天窗格最先咬到它。方向正確。

⚠️ 順帶修了 `modifier_note` 的措辭。原本寫 "below 14 nights of history"，
但現在停用的原因是「最近 28 天內湊不到 14 晚」，**總量其實夠**。
不改的話使用者會以為系統壞了。改成 "below 14 nights within the last 28 days"。
行動仍是「繼續戴」，與 `UNVERIFIED_SEGMENT_NOTE`（「這段不該比較」，戴再多也沒用）
是不同的兩件事。

### ④ 意象去重：拆家族只是一半，另一半更嚴重

原本要做的是「`MOTIF_FAMILIES` 拆成一對一」（8/15 記的未解問題）。做完之後
拿既有 51 晚重新分類量測，**發現第二個沒人注意到的缺陷**。

**先講第一個為什麼會造成 37% 集中**——這不是「去重不夠細」那麼溫和：

> 去重的規則是「最近 7 晚用過的家族不要再用」。深睡類 6 個選項只對應 2 個家族，
> 所以模型寫了 `moss` 之後，`seabed` / `whale` / `lakebed` 這三個**沒用過的
> 選項會一起被排除**，深睡類就只剩 `quilts and snow` 可選。
> **合併家族會主動把模型逼向剩下那一個。**

**第二個缺陷：關鍵字抄了調色盤的逐字片語，但 prompt 明寫可以改寫。**

`SYSTEM_PROMPT` 寫 "You may rephrase and extend"，模型照做了，
關鍵字就對不上——51 晚裡有 **10 晚對不到任何家族**，去重對那些夜晚完全失效。

最直接的證據：08-18 與 08-22 的夢幾乎逐句相同
（"a sky that could not **decide** / **settle** on a season"），
卻因為關鍵字寫的是 `changing season` 而**雙雙沒被擋下**。

| | 修正前 | 修正後 |
|---|---|---|
| 家族數 | 21 | 27（與調色盤一對一） |
| 對不到任何家族 | **10 / 51** | **1 / 51** |
| 實際用到的家族 | 13 | 19 |
| 最集中的家族 | 19.6% | **11.8%** |
| 一晚命中 >2 個家族 | 0 | **0**（沒有製造誤判） |

六個新關鍵字（`season` / `lake` / `cold morning` / `called my name` /
`calling my name` / `stand back up`）的每一次命中都逐一核對過，全部正確。

⚠️ `"breath"` 不能單獨收——深睡選項 a 是 "a seabed that **breathes**"。
收 `"cold morning"`。這跟 `BANNED_WORDS` 改用完整單詞比對是同一種顧慮
（方法論第 5 點：驗證規則寫寬很省事，誤判的代價比漏判大）。

⚠️ **沒有動 `PROMPT_VERSION`**（仍 v4）。升版會把 51 晚標記為 stale 要求重生，
那要花使用者的 API 額度。既有夢境不因這次修改而失效，
改善的是**往後**生成時的去重精細度。這個決定留給使用者。

### ⑤ 沒量到睡眠的夜晚不得進 baseline —— 規模比交接區記的大 12 倍

交接區記為「尚未修」，說的是 07-13~07-15 三筆異常列。實際清點：
**89 列 summary 裡有 38 列沒量到睡眠**。

關鍵不是筆數，是語意。`avg_heart_rate` 的定義是「**睡眠期間**平均心率」，
`total_sleep_minutes = 0` 時手錶根本沒偵測到睡眠，那個數字量的是清醒時段。
數值本身就說得很清楚：

| | avgHR |
|---|---|
| `wearer_a` 真正的睡眠夜 | 52–58 |
| 那些無效列 | **85 / 88 / 90 / 95** |

把它們併進 baseline，等於拿白天心率當「你平常睡覺時的心率」，baseline 被推高，
之後每個正常夜晚都因為「比 baseline 低」而拿到不該有的加分。

**修法上做的一個判斷：分辨構念層級，不是整列丟掉。**

  排除 `avg_heart_rate`／`awake_count`／`sleep_segment_count`／`presleep_stress_score`
       —— 全部由睡眠期推導，沒有睡眠期就沒有這些量
  保留 `resting_heart_rate`（每日單一數字）與 `steps_total`（白天的量）
       —— 不是從睡眠期算出來的，手錶沒測到睡眠不影響它們的有效性

實測 27 晚改變（26 晚是 `avg_hr_modifier`，正是預測的機制），最大位移 1.30、
平均 0.165，品質等級改變 2 晚。方向 **下降 24 晚、上升 3 晚**，與假設一致。
單向性同前：0 項變寬鬆、2 項變停用。

⚠️ `wearer_a` 整段中位數只被推高 0.58 bpm，但 baseline 是 28 天滾動窗，
07-13~07-15 那三筆 88–95 落在窗內時局部推力大得多——這就是個別夜晚
位移到 1.30 分而整段中位數只差 0.58 的原因。**看整段統計會低估局部效應。**

### ⑥ `tests/test_scoring_guards.py` —— 而且驗證過它會失敗

今晚改了三處評分／去重邏輯，一個自動防護都沒有。新增四條，
共同點是**守的都是壞掉時不會報錯的機制**：

1. `has_measured_sleep()` 與 `extract_sleep_features.is_valid_night()` 判準不得漂移
2. 無效夜晚的睡眠衍生量不得進 baseline
3. baseline 窗格是日曆天不是筆數
4. `MOTIF_FAMILIES` 與調色盤一對一，且沒有兩個家族共用關鍵字

第 1 條的處境值得記：兩支腳本**刻意不互相 import**（pipeline 五步是五個
獨立行程），所以判準漂移不會有任何錯誤訊息。解法是用測試防漂移
而不是用耦合——**測試的需求不應該回過頭改變被測程式的架構**。

第 2 條需要一個**反向對照**才成立：光測「拿掉無效列的值，結果不變」，
在「compute_modifiers 根本沒讀這些欄位」時也會通過。所以同時測
「拿掉**有效**夜晚的 avg_hr，結果必須改變」。

⚠️ **測試沒被驗證過會失敗，就不算防護。** 三條各自把 bug 重新引入一次
（閘門改成永遠回 True、baseline 換回 `history[-28:]`、家族合併回去），
確認測試真的會紅，才算數。

### ⑦ `PROJECT_STATUS.md` 對齊現況 —— 它會直接變成報告內容

整份還停在 46 晚，而且**完全沒提到那支錶有三個配戴者**。
照它寫報告會寫出「51 晚單一使用者實測」這個事實錯誤。

新增「六、0」把界線講清楚：Tier1/2 不受影響（分數站得住），
但「長期追蹤同一人的趨勢」不能講——最長的單人資料是 `wearer_a` 的 41 晚。
而且**負責人本人目前 0 個計分夜晚**，`MIN_BASELINE_NIGHTS = 14`，
所以 demo 當天他自己的資料只會有 Tier1/2。

⚠️ **改數字時做的區分，比改數字本身重要：**

| 類型 | 例子 | 處理 |
|---|---|---|
| 描述**現況** | 狀態表「46 晚實測」、配戴率、心情分布 | ✅ 更新 |
| **歷史量測記錄** | 「修正前後 46 晚逐位元組相同」「壓力修正 34/46 → 14/46」 | ❌ 一律不動 |

後者是當時真的量到的數字，改成 51 就是竄改實驗記錄。
整批 find/replace 在這種文件上是錯的做法。

### ⚠️ 順手推翻了自己文件上的三件事：TAPO 那份 dump

CLAUDE.md 寫著那份 dump「用我們自己的資料驗證了三件已知的事（可直接引用進報告）」。
去看現行檔（影像組 08-26 推的，244KB），三件裡有兩件已經不成立：

| 文件寫的 | 實測 |
|---|---|
| 5 筆紀錄 | **15 筆** |
| 4 筆分數全是 50 → 印證紅線 3「人為地板」 | 分數有 **14 個不同的值（11~97）**，**地板症狀不存在** |
| `report_date` 全是 dump 產生當天 | 日期分散，但可信度分三層 |

用 `created_at` 對照 `report_date` 分層（唯一的內部證據）：
現場擷取 9 筆、事後批次補 5 筆（`created_at` 全是 `2026-08-12 13:21:29` 同一秒）、
幾乎確定錯的 1 筆（宣稱 06-11 卻在 08-18 才建立，差 68 天）。

→ 與 Garmin 51 晚的重疊是 **最寬鬆 10 晚、只算現場擷取 5 晚**，不是先前記的 3 晚。

⚠️ 那筆 06-11 是**唯一**讓 TAPO 與 Garmin 六月資料重疊的紀錄。
不分層就直接 `merge`，會憑空多出一個橫跨兩個月的「共同樣本」——
而 3.10 ① 已經警告過 `how='inner'` 會安靜地丟掉配不上的列。

同一份 CLAUDE.md 還同時寫著「那份 CREATE TABLE 沒有 created_at」與
「08-26 那版第 38 行有 created_at」。實測有。已修掉這個自相矛盾。

### ⑧ 攝影機到底能不能給「上床時刻」—— 樣本 3 晚 → 9 晚，結論更精確

`PROJECT_STATUS.md` 3.9 的核心主張是「攝影機的價值是提供手錶量不到的上床時刻」，
但它的證據只有三晚，而且那三晚取自**舊 dump**（其中 08-06 的「首事件 01:33」
在現行檔已不成立——那一列時間戳全是 `00:00:00`）。用現行檔重做。

**成功的四晚異常一致**：首事件早於入睡 31／33／37／48 分，
落在合理的入睡潛伏期範圍，全距只有 17 分鐘。

**失敗的五晚分成兩種完全不同的原因**，這是這次分析真正的產出：

| 類型 | 晚數 | 原因 |
|---|---|---|
| timeline 時間戳壞掉 | 3 | 整串事件的 `time` 全是 `00:00:00`~`00:00:04`。工程 bug |
| 監測窗沒開到 | 2 | `.env` 的 `SLEEP_START=01:00:00`，但那兩晚 22:31／22:32 就睡著了 |

⚠️ 第二類可以量化，而且量化之後才看得出它有多結構性：
**51 個 Garmin 夜晚裡有 7 晚（14%）入睡在 01:00 之前**，
而觀察到的兩次窗口失敗**兩晚都正好落在那 7 晚裡**。
兩晚落在 7/51 這個子集裡不是巧合——這是機制被證實，不是相關性。

這也把 3.9 原本那句佐證推到更強的位置。先前只能說「首事件都緊接在
01:00 開機之後，與『開機後的第一次動作』一致」——那是**相容於**假設的觀察。
現在有兩晚，手錶明確指出人在 22:31 就睡著，攝影機首事件卻在 03:30：
**首事件反映的是排程，不是行為。**

**對建議的影響：把原本的 (A) 拆成 A1／A2。**
原本「提早開機 + 床鋪 ROI 偵測」被當成一個大工程，所以整條被排在 (B) 之後。
但那 14% 純粹是設定問題：

  A1 只改 `SLEEP_START` —— 工程量極小，**先做**
  A2 ROI 佔用偵測 —— 工程量大（影格差分要換成背景相減）

A1 單獨做不能解決辨識問題，但它是 A2 的必要前置：
**演算法再好也認不出沒錄到的畫面。**

核心結論不變：攝影機給的是一串動作事件，但沒告訴你哪一個是「上床」。
這是辨識問題不是資料量問題（現行 dump 最多的一晚有 754 個事件）。

### ⑨ `inspect_tapo_dump.py` —— 因為上面那些數字不可重跑

⑦⑧ 寫進 `PROJECT_STATUS.md` 的 TAPO 數字，全部來自臨時腳本。
**沒有人能驗證，而影像組一送新 dump 就全部過期**——而那份文件會直接
變成 9/9 的報告內容。這是不能接受的狀態，所以補一支可重複執行的清點工具。

只用標準庫（專案規範），不做任何評分，只清點與比對。輸出重現了
3.9 與 3.10 ② 的每一個數字。兩節都加了「這一節可以重跑」的指引，
並明寫**不要照抄表格**。

⚠️ 寫這支的時候，`created_at` 分層有一個地方單看一列判斷不出來：
**「事後批次補」的判準是同一個 `created_at` 出現在多列**（那 5 筆全是
`2026-08-12 13:21:29`，同一秒）。所以要先數過整批再分類，
不能逐列判斷。這種「必須先看全體才能判斷個體」的規則，
寫成逐列的函式會安靜地失效。

順帶抓到一個先前沒發現的資料 bug：id 117（08-19）的 `total_events = 73`，
`timeline` 卻是空陣列 `[]` → 寫入端與統計端不同步。不在重疊夜裡，
所以不影響 3.9 的表，但任何以 `total_events` 為準的分析
（含 `sleep_quality_score` 的扣分公式）會落在一份不存在的 timeline 上。

### ⚠️ 方法論：「還沒做的事」清單本身也會過期

交接區的「下次接手三件事」裡，第 ② 條寫「新 5 晚沒有 AI 夢境、
`is_ai_generated=false`」。實際去看檔案：**51 晚全部 `source=llm`，
最新一晚 `is_ai_generated=true`**。那條在 08-26 全量重跑之後就已經完成了，
只是沒人回頭把它劃掉。

如果照著文件做，就會白跑一次 `--ai`、白花一次 API 額度。
→ 這跟「遠端狀態問 git 不要問文件」是同一條規則的延伸：
  **待辦清單要問產出物，不要問清單。** 動手前先看一眼它宣稱的狀態是否還成立。

---

## 📌 2026-08-28（深夜）戴錶者分段的驗證與收尾

這一輪**沒有寫 `WEARER_SEGMENTS`**——那是同一天稍早做的，當時停在工作區未提交。
這則記的是「驗證它是不是真的對」與環境收尾。

### 使用者一句話推翻了文件上的解釋

使用者說「那支錶這段期間經歷三個人帶，我是今天 8/28 才開始戴」。
在此之前 CLAUDE.md 把 08 月的訊號位移解釋成**配戴習慣改變**，
並據此判斷「再四週這個問題會自己消失」。

用 `garmin_sleep_summary.csv` 分段核對，那個解釋站不住：

| 段 | 期間 | 晚 | 睡眠平均心率 | 靜止心率 | 步數中位 |
|---|---|---|---|---|---|
| A | 05-28 ~ 07-12 | 46 | 57.9（51–85） | 52.9 | 185 |
| ? | 07-13 ~ 07-15 | 3 | **91.2**（88–95） | n/a | 10088 |
| B | 07-16 ~ 07-28 | 13 | 55.4（53–58） | 52.1 | 47 |
| C | 07-29 ~ 08-25 | 27 | **78.8**（70–88） | **68.0** | 98 |

相鄰夜最大跳動剛好落在三個交界：
`07-15→07-16 −40.5 bpm`（全資料集最大）、`07-28→07-29 +26.0`、`07-12→07-13 +21.8`。

**決定性的一點：`avg_heart_rate` 量的是「睡眠期間」。**
配戴習慣會改變步數與白天讀數，但**不會讓人睡著時的心率持續高 21 bpm、連續 27 晚**。
而且 C 段步數中位數是 **98，比 A 段的 185 還低**——「開始整天配戴」在這裡也不成立。

### 實測：分段之後改了哪 10 晚

拿 `git show HEAD:` 的舊 CSV 與重跑後的新 CSV 逐晚比對：

| | |
|---|---|
| 總夜數 | 51，**10 晚**分數改變（全在 `unverified` 區段） |
| 修正值 | −2.37 ~ −9.75 → **0.0**，平均取消 **5.61 分** |
| 品質等級 | **6 晚**改變（08-07 / 08-22 / 08-23 Normal→Good；08-09 / 08-21 Bad→Poor；08-17 Poor→Normal） |
| 最新一晚 | `pet_mood` **anxious → happy**、`mood_reason` 由 `stress_modifier=-4.0 ≤ -3.0` 變成 `final_quality=Good`、energy 77 → 82 |

最後那一列是最能說明問題的：**82.2 分的 Good 夜晚，原本顯示焦慮寵物**。
CLAUDE.md 記的異常（新 5 晚 `total_modifier` 平均 −7.09、舊 46 晚 −0.33）
根因就是拿別人的 baseline 在比，不是「那幾晚睡得特別差」。

### 環境收尾（承 08-27 那則的四個坑）

- **PATH**：使用者層的 `C:\src\flutter\bin` 換成 `C:\Users\user\flutter\bin`。
  這才是 `local.properties` 一直被改回去的真正原因——任何程式呼叫 `flutter`
  都解析到 3.47 那份。⚠️ 我先前用 `which -a flutter` 判斷「PATH 上沒有」是錯的，
  **Git Bash 的 `which` 找不到 `.bat`**，要直接看 `PATH` 字串。
- **刪掉 `C:\src\flutter`**（3.1GB）。先改名 → 驗證 `flutter --version` 與
  `pub get` 正常（`package_config.json` 的 `generatorVersion` 要是 **3.12.2**）→ 才刪。
- `pubspec.lock` 跟著回到穩定版解出來的版本（`matcher 0.12.20 → 0.12.19`）。
  committed 那版是 3.47 的 pub 解的。
- 兩支驗收測試全通過（含紅線 4「behavior/ 不得 import 評分層」）。

⚠️ 手機上那個 APK 是**修正前**打包的（顯示 anxious）。要同步得重建重裝。

### ⚠️ 方法論：文件上的因果，要拿「不受該原因影響的訊號」去驗

「配戴習慣改變」能解釋步數、能解釋白天壓力讀數，所以看那兩個訊號時它是自洽的。
真正證偽它的是**睡眠期間心率**——一個配戴習慣影響不到的量。
→ 檢驗一個解釋時，去找**它預測不到的那個訊號**，不要在它能解釋的訊號裡反覆確認。

---

## 📌 2026-08-27 Android 實機環境從零建起（第一次把 App 裝進實體手機）

目標：使用者要用自己的手機測試。**結果達成**——`app-debug.apk` 已安裝並執行於
SM S9260（Android 16 / API 36 / arm64），資料讀取正常。
分支是 `merge/jeremy-report-screen`（main + Jeremy 的 Insights 頁）。

起點：Flutter 3.44.9 已裝在 `C:\Users\user\flutter`（但不在 PATH），
**Android SDK 完全不存在**，Java 只有 JRE 8 與 JRE 9（都是 JRE 不是 JDK，
且 Gradle 9 最低要 Java 17）。選了「裝完整 Android Studio」而非只裝 cmdline-tools，
是使用者的決定。

### ⚠️ 坑 1：安裝精靈裝的是 API 37，但 Flutter 3.44.9 寫死 compileSdk = 36

`FlutterExtension.kt:23` 是 `compileSdkVersion: Int = 36`（minSdk 24、targetSdk 36）。
Android Studio 2026.1 的精靈只裝最新的 `platforms;android-37.0`，
AGP 找不到 `android-36` 會直接失敗。

補裝過程踩到兩件事，記下來免得重來：

1. **`sdkmanager "platforms;android-36"` 會失敗**，訊息是
   `Package platforms not found. / Package android-36 not found.`
   ——`.bat` 經 cmd 轉發時把 `;` 當成參數分隔字元切開了。
   新版工具已把 `sdkmanager` 標為 deprecated，改用同目錄的
   **`android.exe sdk install platforms/android-36`**（用斜線、直接呼叫 exe）。
2. 但它自己的下載器在這條網路上會 `java.io.IOException` 中斷。
   最後是用 `curl -C -` 抓 `platform-36_r02.zip`（62.8MB）解壓到 `platforms/`，
   **並手動補一份 `package.xml`**——沒有這個檔，SDK 管理器與 AGP 都不認得它。
   範本取自 `android-37.0/package.xml`，數值照 `android-36/source.properties` 改：
   API 36、extension-level 17、revision 2、layoutlib 15。
   驗證方式：`flutter doctor` 回報 `Android SDK version 36.0.0`，
   最終 APK 的 `aapt2 dump badging` 顯示 `compileSdkVersion='36'`。

### ⚠️ 坑 2：機器上有兩份 Flutter SDK，版本混用會出無意義的錯

| 路徑 | 版本 | Engine |
|---|---|---|
| `C:\Users\user\flutter` | **3.44.9 stable**（專案用這個） | `5a2a6a42cc` |
| `C:\src\flutter` | **3.47-candidate**（未發布） | `5d53178869` |

`C:\src\flutter` 在 2026-08-27 04:03:27 出現（本輪對話開始時實測還不存在）。
它是官方 SDK 的完整解壓，git remote 指向 `flutter/flutter`，
reflog 是從 `flutter.googlesource.com/mirrors/flutter` clone——
那是 **Google 打包機器**的記錄（日期 08-19），不是本機操作。
**放進來的是什麼程式，查不出來。** 不是 Android Studio 的 Flutter 外掛
（沒裝），也不是 VS Code 的 Dart-Code（沒裝）。

症狀長這樣，而且**完全不會指向真正的原因**：

```
/C:/src/flutter/packages/flutter/lib/src/gestures/binding.dart:329:15:
Error: Method not found: 'HitTestResponse'.
```

機制：`C:\src\flutter` 的 pub（3.13.1）改寫了 `app/android/local.properties`
的 `flutter.sdk` 與 `.dart_tool/package_config.json`（4 個項目指過去），
於是變成**拿 3.44.9 的編譯器去編 3.47 的 framework 原始碼**——
3.47 的 `binding.dart` 呼叫 `ui.HitTestResponse`，那個 API 在 3.44.9 的
`dart:ui` 裡還不存在。

修法：`flutter clean` → `local.properties` 指回 stable → 用 3.44.9 重跑 `pub get`。
驗證看 `package_config.json` 的 `generatorVersion`（要是 **3.12.2** 不是 3.13.1）。

⚠️ **這顆地雷還在。** `C:\src\flutter` 沒有刪，而 `local.properties`
在建置後又被改回 `C:\src\flutter`。下次建置前先確認這個檔。

### ⚠️ 坑 3：`local.properties` 的路徑不能用單反斜線

`app/android/settings.gradle.kts` 是用 Java `Properties.load()` 讀它，
所以 `\` 是跳脫字元。寫成 `C:\Users\user\flutter`，`\user` 的 `\u`
會被當成 Unicode 跳脫開頭，直接丟 **`Malformed \uxxxx encoding`**。

我用 `sed` 改的時候真的寫成單反斜線了；heredoc `<<'EOF'` 也保不住雙反斜線。
**最後用正斜線**（`C:/Users/user/flutter`），Java 與 Gradle 在 Windows 上都接受，
而且沒有任何跳脫問題。驗證方式是寫一支三行的 Java 實際 `Properties.load()` 印出來，
不要用肉眼看。

### ⚠️ 坑 4：VS Code 的「Gradle for Java」擴充套件會搶 Gradle 鎖

一開始它報 `No connection to gradle server`，我判斷「跟 Flutter 無關、按 ✕ 就好」
——**前半對，後半錯**。Temurin 17 一裝好，它就能啟動 Gradle 了，
於是自己跑了一次 sync 並吃下 `app/android/.gradle/noVersion/buildLogic.lock`，
我們的建置晚 57 秒進場就被擋掉：

```
Timeout waiting to lock build logic queue. Owner PID: 16856
```

用父程序追出來：`gradlew(41760) → daemon(16856) → kotlin compiler(33384)`，
與我們那條 `flutter build(1668)` 是兩條獨立的建置。
→ **Flutter 專案應把這個擴充套件設成 workspace 停用。**

### 網路：大檔下載會斷，一律用 curl 續傳

Android Studio 安裝檔（1.4GB）winget 斷在 136MB、curl 第一次斷在 693MB、
第二次才完成；SDK 精靈的 platform-tools 與 emulator 也各失敗一次。
`curl -L -C - --retry 20 --retry-all-errors --speed-limit 1024 --speed-time 30`
這組參數能自己撐完（`--speed-time` 是關鍵：龜速 30 秒就重試，不會卡死不動）。
**驗證完整性用 `Get-AuthenticodeSignature`**，簽章能過就代表每個 byte 都對。

### 最終環境

| 項目 | 值 |
|---|---|
| Android Studio | 2026.1（3.29GB，**未裝 Flutter 外掛**） |
| Android SDK | `platforms/android-36`（手補）+ `android-37.0`、`build-tools 36.0.0`、`platform-tools 37.0.1` |
| JDK | **Temurin 17**（`C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot`） |
| Gradle / AGP / Kotlin | 9.1.0 / 9.0.1 / 2.3.20 |

⚠️ Flutter 挑的是 Temurin 17，**不是** Android Studio 自帶的 JBR 25——
這是好事，JDK 25 與 Gradle 9.1 的相容性沒有驗證過。

⚠️ `flutter doctor` 會報 `Android license status unknown`，**可以無視**：
新版 Android CLI 已廢掉 `--licenses`（直接回 "no longer needed"），
是 Flutter 的檢查方式過時，授權檔 `licenses/android-sdk-license` 實際存在。

### 裝進手機的方式與驗證

用 `adb install -r` 直接裝（繞開 Gradle 與 `local.properties`，不受 SDK 衝突影響），
再 `adb shell am start -n com.example.app/.MainActivity` 啟動。

驗證三項，都通過：

- `aapt2 dump badging`：`compileSdkVersion='36'`、`application-label:'Sonnap'`
  （後者證實合併時把 Jeremy 的 `pubspec name` 改動移到 `AndroidManifest` 的
  `android:label` 是對的）
- APK 內含 `assets/flutter_assets/assets/data/app_payload.json`
- logcat：`SLEEP JSON LOADED`、`session_id: 20260823_001`、`pet_mood: anxious`，
  渲染後端 Impeller (Vulkan)，無 `FATAL` / `AndroidRuntime`

### ⚠️ 方法論：關聯不是因果

我看到「Android Studio 在跑」+「`local.properties` 被改」+「多出一個 release APK」，
就對使用者斷言是 Android Studio 幹的。使用者截圖顯示
**Languages & Frameworks 裡根本沒有 Flutter**（外掛沒裝，做不到這件事）才發現講錯。
→ 歸咎前先確認那個嫌疑者**有沒有能力**做這件事，不要只看時間吻合。

---

## 📌 2026-08-26（下午）輸出語言改英文

使用者決定「輸出一律以英文為主」。範圍：**後端 + `ai/`，不含 Flutter**
（`app/lib` 那 14 個 .dart 檔沒動——Jeremy 正在改 `report_screen.dart`，同時改會衝突）。
規則與實測結果已寫進 [CLAUDE.md](CLAUDE.md) 的「輸出語言」節，這裡只留過程。

### 範圍判斷：只改輸出字串，註解維持中文

「輸出」= 使用者/API 看得到的字串。程式碼註解與 docstring 不是輸出，
而且那些是本專案最有價值的資產（每個決策的理由），翻成英文反而讓團隊難讀。

### ⚠️ 「整行替換」這個做法引入了兩個真的 bug

我用「包含某中文片段的整行換掉」來改，結果把行首的程式碼一起換掉了：

| 檔案 | 被吃掉的部分 | 後果 |
|---|---|---|
| `extract_sleep_features.py` | 三個 `return False, ` | **整條 pipeline 在步驟 2 崩掉**（TypeError） |
| `healthconnect_adapter.py` | 一個 `raise HealthConnectError(` | 無效 session 會被**靜默放行** |

第一個馬上就崩，第二個不會——它只是讓驗證失效，沒有任何錯誤訊息。

**找出第二個的方法值得記：**拿 AST 把所有字串常值換成 `<S>`，
再跟 `origin/main` 逐節點比對——這樣能問出「只有字串內容變、程式結構沒變嗎」。
11 個檔裡這個檢查採出 2 個結構差異，一個是預期的（history 加兩欄），
另一個就是那個消失的 `raise`。

### ⚠️ AI 那一塊不是翻譯，是把驗證層對準新語言

四個機制與語言綁死，換掉任一個而不改對應物，**不會報錯，只會不再擋任何東西**。
對照表在 CLAUDE.md。這裡只記一個最容易被忽略的：

**`LENGTH_LIMITS` 不跟著改，51 晚會全部被長度檢查擋掉。**
依據是實測而不是估算：舊中文 46 晚的字元中位數 48/85/31，
英文寫同樣內容是 131/280/80，約 **2.7–3.3 倍**。三組上下限一律 ×3。

### 實測結果（51 晚全量重跑，真的呼叫 API）

| 指標 | 結果 |
|---|---|
| LLM 生成 | **51/51**，0 晚 fallback |
| 中文洩漏 | 0 晚 |
| 夢境含數字 | 0 晚 |
| 意象最集中的家族 | **19.6%**（sinking seabed） |
| 用到的家族數 | 13 / 21 |

⚠️ 中文版留下的未解問題「棉被與雪佔 37%」在英文版沒有重現，
但**根因沒有修**——`MOTIF_FAMILIES` 與調色盤選項仍然不是一對一。
數字好看不代表問題解決了。

### ⚠️ 順手發現：PR #12 漏了一個 commit

PR #12 在 `0acfb90` 就被合併，而我的第三個 commit `e26d030`
（修正 Jeremy 卡點的診斷）**是合併之後才推的**。
結果 `main` 上偵的是我後來確認為**錯誤**的那版診斷。
已 cherry-pick 進這一輪。

→ **推完之後又推了新 commit 時，要再確認一次 PR 是否已經合了。**

---

## 📌 2026-08-26 這一輪（多使用者迴圈打通）

**驗收可重跑**：`python tests/test_api.py`、`python tests/test_healthconnect_adapter.py`
（兩支都是獨立腳本，不需要 pytest；`test_api.py` 全程用暫存資料庫，不碰 `data/sonnap.db`）。

### 新增了什麼

```
main.py            POST /users /nightly /wearable  PATCH+DELETE /users/{id}
                   GET /home /insights /challenges     ← 舊端點行為完全不變
wearable/          Health Connect → **既有評分器**（一個門檻都沒改）
behavior/          challenges.py（挑戰引擎）+ pet_state.py（行為驅動的寵物狀態）
migrate_garmin_to_db.py   46 晚 → wearable_nightly，與 CSV 逐列相符、可重複執行
tests/             兩支驗收腳本
```

⚠️ **CORS 原本只開 `allow_methods=["GET"]`**——所以**結構上就不可能寫入**，
App 上傳一定被瀏覽器擋掉，而且錯誤只出現在瀏覽器 console。已補 POST/PATCH/DELETE/OPTIONS。

⚠️ **`db.py` 加了欄位遷移機制**。`CREATE TABLE IF NOT EXISTS` 對**已存在**的表
什麼都不做——連新加的欄位也不補。只改 SCHEMA 的話，全新環境正常、
已跑過 `--init` 的開發機則會 `no such column`。見 `COLUMN_MIGRATIONS`。

### ⚠️ 三個值得記住的發現

**1. 臥床時間（3.9）對有穿戴裝置的同學其實拿得到。**
Health Connect 的 `SleepSessionRecord` 以「**上床**」為 session 起點，
所以 TIB、入睡潛伏期、臨床睡眠效率全部算得出來——攝影機原本要解的問題，
標準層直接就給了。**但刻意不拿它計分**：Garmin 的效率分母是「起床 − 入睡」，
臨床定義是「起床 − 上床」，後者一定較低；兩種數字餵進同一組門檻
（`EFFICIENCY_GOOD = 85`），L1 同學會被**系統性地扣分**，
而那個差異來自裝置不是來自睡眠。→ 另存 `clinical_efficiency` 供報告用。

**2. 挑戰難度校準：一個門檻真的達不到，另一個是被假象騙的。**
- `作息收斂` ±30 分鐘 → **0/36 = 0%**（離散度中位數 103 分鐘）。改為 **±60**（22%）
- `連續 5 晚` → 第一次跑出 0%，**一度誤判成挑戰設計壞了**。
  ⚠️ 查下去發現有一部分是**手錶配戴率造成的假象**：46 晚散在 74 個日曆日、
  只有 1 段連續 ≥5 天，而「缺資料就中斷」讓斷點吃掉了大部分連續。
  **那個限制在 Tier A 不存在（手機天天都在）**，校準時要先把斷點拿掉。
  去掉後量到「準時率要 55–60% 才連得到 5 晚」，改為 **連續 3 晚**
- ⚠️ 校準樣本 **n=1** 且那個人特別不規律（就寢標準差 84 分鐘），是暫定值

**3. `target_bedtime` 的預設值 23:30 會讓夜貓子第一天就放棄。**
「準時放下手機」的達成率**完全由使用者自己設的目標決定**：同一批資料，
23:30 → 2%、02:30 → 43%、03:00 → 59%。→ 註冊流程要問「你現在通常幾點睡」
並據此建議，不能給所有人同一個預設值。（App 端的事，已交接給 Jeremy。）

### 兩層如何合併

`main.py` 的 `resolve_mood()`：**有行為資料時行為優先，生理只做 `anxious` 覆寫**。
理由同「挑戰標的必須是行為不是生理結果」——使用者準時放下手機卻因感冒睡不好
而看到難過的寵物，就是**因為自己控制不了的事被懲罰**，回饋迴圈一斷機制就失效。

⚠️ **沒有行為資料時完全走舊路徑的規則**（直接 import
`build_app_payload.map_pet_mood`，不重寫）。已實測：研究者那 46 晚
走新 API 與走舊 asset 給出**逐字相同**的心情與理由。

### 兩個分工決定

1. **音訊門檻 bug（3.7）交給影像組修，我不動 `tapo_detector.py`。**
   交接要點在 `PROJECT_STATUS.md` 3.7 末段——**根因是單位錯亂不是靈敏度**
   （8/17 那次註解寫「Lowered for more sensitive detection」，代表根因當時
   沒被辨識出來），`db` 天花板是 **90.3**，**驗收要跑真的有聲音的錄音**。
2. **重複的 `if_integrate.py` 留 `itegration/` 那一份**，`tapo/` 那份已刪
   （刪前驗證過全專案零 `import`）。


---

## 📌 2026-08-25 這一輪（量測時窗修正 + 產品化地基）

分支 `feature/behavior-loop`，4 個 commit。完整計劃在
`C:\Users\user\.claude\plans\abundant-nibbling-sutton.md`。

### ⚠️ 壓力與活動量的量測時窗**都差了一天**（重要，已修）

根因是同一件事：**`garmin_sleep_summary.csv` 的每一列混了兩個時段的資料。**

```
列 D 的「睡眠」＝ D-1 晚上上床、D 早上起床   （歸起床日，對齊 Garmin calendarDate）
列 D 的「步數/壓力」＝ D 白天               （時間戳不在睡眠區間內，照自己的日曆日歸類）
                                            ↑ 發生在那一覺「之後」
```

分流的那一行是 `analyze_garmin_sleep.py:185`：
`date = session_date_for(ts_dt, sessions) or get_date(timestamp)`。

**壓力（±4，Tier3 額度最大的一項）**——實測 11439 筆讀數裡**只有 8.6% 落在
睡眠期間，91.4% 是白天**，而 G 節寫的構念是「睡眠期間的生理壓力負荷」。
更麻煩的是本資料集平均就寢 02:34，所以列 D 的傍晚讀數（19:00–23:00，配戴高峰）
其實屬於**下一晚**的睡前時段——單一欄位橫跨了兩個不同夜晚。

已新增 `presleep_stress_score`（`build_awake_windows()`），定義是
**「上一次起床 → 這一次入睡」的整個清醒時段**。⚠️ **窗格兩端都由資料自己界定，
不含任何人為選定的時間長度**——這是刻意的：本專案每個門檻都要有依據，
而最好的做法是根本不需要門檻。（一度考慮過「睡前 3 小時」，但那個 3 需要引文，
而且量到的其實是 pre-sleep arousal 這個**中介變項**，不是 G 節要的「當日壓力」。）

**活動量**——改讀前一個日曆日的 `steps_total`。H 節引的 Kredlow (2015) 檢驗的是
「日間活動 → 其後睡眠」的前瞻方向。此項已因 baseline < 1000 步而停用，
**數值零影響**，只有 06-11 的 `modifier_note` 由「資料無效」改成「冷啟動」
（序列位移一天，滿 14 筆的時間點也晚一晚，是正確結果不是副作用）。

**實測影響（46 晚）：**

| | 修正前 | 修正後 |
|---|---|---|
| 壓力修正生效 | 34/46 晚 | **14/46 晚** |
| 飽和率 | 24% | **14%** |
| 改變分級 | — | 3 晚 |
| **Tier1/2 基礎分數** | — | **46 晚完全未變** |

生效夜數下降是因為需要**連續兩晚都有記錄**——與 SRI 受同一結構限制，
兩者可用夜數同為 28。這不是永久限制：**配戴率改善它就自己補起來**，
而舊定義的構念錯誤再收集 200 晚也還是錯的。

單晚差異可達整個 ±4：**2026-07-12**（02:39 入睡、15:29 起床）舊值 25.8
（基準 5.5）扣滿 −4.0，但那 25.8 **整段發生在起床之後**；新值 3.3（基準 5.4），
入睡前的清醒時段其實**低於**個人常態。同一批原始讀數，差了 7.8 倍。

⚠️ **`avg_stress_score` 保留未刪**，但不再參與計分。理由不是「歷史對照」
（那是錯的說法），是 **`itegration/if_integrate.py:250` 仍在讀它**。

### ⚠️ 順手抓到：06-02 那筆異常列會汙染 baseline

第一次跑出來壓力生效 15/46 而不是預測的 14/46。差一晚查下去是 **2026-06-02**
（`sleep_start == wake == 00:00:00`，本檔案早已記錄的異常列）。

**關鍵：`extract_sleep_features.py` 會濾掉它，但 `apply_recovery_modifier`
讀的是 `summary` 而不是過濾後的 features**，所以假值會直接進 `stress_history`
汙染 baseline，讓它提早一晚湊滿 14 筆。已在 `build_awake_windows` 自己擋掉
退化區間（兩端都檢查），**不倚賴下游過濾**。

→ 教訓：`summary` 與 `features` 的有效性標準不同，任何讀 `summary` 的新程式
都得自己做有效性檢查。

### ⚠️ 評分路徑盤點：**我在這一輪連續寫錯兩次**，過程比結論更值得記

- 第一版：「兩套」——漏了 `if_integrate.py`
- 第二版：「第三套是 `calculate_garmin_score_from_features`，用 `stress > 20`」
  ——**那是死碼**
- 第三版：「`camera_score` 會從原始計數重算，取代 TAPO 自己的分數」
  ——**也是死碼**，SQL 早就寫了 `sleep_quality_score as camera_score`

**兩次錯誤同一個原因**：看到 `df['x'] = self.calculate_x(df)` 就假設它會執行，
沒往上看那個 `if 'x' in df.columns` 是否已經成立。**這正是 8.2 的紀律
（先讀實際呼叫路徑再下結論），而我對自己的專案連續兩次沒做到。**

正確答案（兩套 + 一個組合 + 兩段死碼）：

| 分數 | 狀態 |
|---|---|
| `final_score`（`garmin/`） | ✅ 文獻加權 |
| `sleep_quality_score`（`tapo/tapo_detector.py:326`） | ✅ 扣分制 |
| `integrated_score`（`itegration/if_integrate.py:214`） | ✅ `0.6×garmin + 0.4×tapo`，**權重無依據** |
| `calculate_camera_score()` / `calculate_garmin_score_from_features()` | ❌ 都是死碼 |

✅ **重複檔已於 2026-08-26 刪掉一份**：`itegration/if_integrate.py` 與
`tapo/if_integrate.py` 曾逐位元組相同（各 518 行），已依決定**保留
`itegration/` 那一份**。刪除前驗證過全專案零 `import`（兩者都是獨立腳本），
所以不影響任何呼叫路徑。⚠️ `itegration` 是 `integration` 的拼字錯誤，
改名是另一件事，目前刻意不動（`requirements.txt:28` 的註解也指向這個名字）。

**「把 Garmin 和 TAPO 合起來」不需要從頭做——它已經寫好了。但
`PROJECT_STATUS.md` 3.10 主張根本不該做加權平均**：攝影機的價值是提供
手錶量不到的「上床時刻」（→ 臥床時間 → 解掉 6.3 的效率限制 + 解鎖入睡潛伏期），
那條路**一個新參數都不用訂**；而加權平均要 justify 60/40，還是拿有引文的分數
去平均沒引文的分數。整合路徑的五個問題見 3.8，臥床時間見 3.9。

### 產品化地基（`db.py` + `behavior/`）

D2 確認要「找同學裝 APK 實際用一到兩週」之後，**多使用者不再是待決策事項**。
`db.py` 用標準庫 `sqlite3`（`requirements.txt` 不多任何一行），七張表，
暱稱制免註冊。`behavior/` 是 Tier A 行為層。

⚠️ **架構紅線（8.7）在新架構下是結構上成立的，不需要靠紀律守住**：
遊戲化建立在 Tier A（手機行為）上，與評分器不在同一條路徑。驗收指令見
`behavior/__init__.py`——**要比對 import 行，不能單純搜關鍵字**，
否則會抓到規則自己的說明文字（實際踩過）。

### ⚠️ 兩個「安靜失效」的坑（都已修，都有實測）

1. **`.gitignore` 寫 `data/` 會遞迴匹配 `garmin/data/` 與 `ai/data/`**
   （那裡有 11 個檔已進版控）。已追蹤的檔案不受影響，所以不會立刻壞掉，
   但**新增的檔案會被靜默擋掉、沒有任何錯誤訊息**。要寫 `/data/`。
   已用 `git check-ignore -v` 實測確認。
2. **`db.py` 的 `update_user` 檢查順序反了**——當**所有**欄位都打錯時，
   `updates` 是空的而提早 `return False`，未知欄位的檢查永遠走不到。
   先擋未知、再處理空更新。

### `garmin_sleep_summary.csv` 的現行欄位（取代 2026-07-12 那份清單）

`date`、`sleep_start_time`、`wake_time`、`total_sleep_minutes`、
`deep/light/rem/awake_minutes`、**`movement_sample_minutes`**（原 `movement_count`）、
`movement_level_mean/max`、`movement_active_minutes`、`steps_total`、
`avg/min/max_heart_rate`、`avg_stress_score`（不再計分）、
**`presleep_stress_score`**（Tier3 用這個）、`resting_heart_rate`、
`awake_count`、`sleep_segment_count`。


---

## 📌 2026-08-15 這一輪（階段 0：不依賴任何人的清理）

路線圖的「階段 0」共四項，**全部完成**，四個 commit 見上方 git 狀態。

### ⚠️ `movement_count` 其實是取樣分鐘數，不是動作量（重要，已修）

使用者問「Garmin 的 movement 是動作幅度嗎」，查下去發現**原始資料是，但我們的
pipeline 把幅度丟掉了**。`analyze_garmin_sleep.py:191` 對每筆 `sleepMovement`
只做 `+= 1`，完全沒讀 `activityLevel` 的值。

**四條獨立證據（任一條不成立結論就垮，日後有人質疑可以直接重跑）：**

| # | 證據 | 結果 |
|---|---|---|
| 1 | 程式碼路徑 | fetch 把 `activityLevel` 存進 `value`，analyze 卻只 `+= 1`，從未讀取 |
| 2 | 取樣間隔 | 28444/28449 個相鄰間隔**正好 60 秒**（99.98%）→ 固定頻率取樣器 |
| 3 | 相關性 | 與睡眠時長 **r = +0.929**、與夜間清醒 WASO **r = −0.138** |
| 4 | 被丟掉的 value | 28497 筆連續值、17962 種相異值、範圍 0.00–7.64 → **那才是動作幅度** |

證據 3 是最強的反證：若真是翻身次數，該與清醒相關而非與時長相關。

**08-09 那晚示範了不修的後果**：舊 `movement_count` 是 489，四晚裡**最低**，
看起來像「動最少」。但真訊號說反話——平均幅度 1.64（其他三晚的兩倍）、
活躍分鐘佔 **72%**（其他約 22%）。那正是評級 Bad、`pet_mood: anxious` 的夜。
**舊指標不只是沒用，會給出相反的結論。**

已改名 `movement_sample_minutes` 並新增 `movement_level_mean/max`、
`movement_active_minutes`。⚠️ **這幾項永不進評分**——`MOVEMENT_ACTIVE_THRESHOLD = 1.0`
是看資料分布訂的、沒有文獻依據，本專案每一項計分都有引文，不破例。
回歸測試：`garmin_sleep_quality_final.csv` 修改前後**逐位元組相同**。

### ⚠️ 順手修掉一段會誤導人的過期註解

`extract_sleep_features.py` 原本寫著心率／壓力／步數是「V2 預留（目前未計分）」。
那寫於 Tier3 上線（2026-07-31）之前，**已經不正確**。要分兩層講：

- **features.csv 裡那幾欄**確實沒人讀（evaluate 只用 Tier1/2 的五項）
- **同樣的數值有進計分**，走的是 `summary.csv` → `apply_recovery_modifier.py`

讀的人會直接得出「心率不計分」的錯誤結論。已改寫。
（這是使用者自己抓到的，不是我發現的。）

### AI 夢境重複率 70% → 17%（`PROMPT_VERSION` 升到 v3）

原本 46 晚裡 32 晚不是「圖書館」就是「海床」。**根因不是模型偷懶**——
調色盤每個條件只給一組意象，又要求「只能用當晚事實支持的意象」，
事實相似的夜晚必然寫出幾乎一樣的夢。

修法三層：調色盤每類擴充成 3–6 組（並改用身體感受寫而非形容詞）、
新增 `recent_motifs()` 把最近 7 晚用過的意象寫進 prompt 要求避開、
數值一律阿拉伯數字。

⚠️ `recent_motifs()` 的呼叫**必須放在主迴圈內**重算，不能提到迴圈外先算好——
`entries` 每跑完一晚就更新，放裡面第 2 晚才看得到第 1 晚用掉的意象。
放外面的話一次補 46 晚時等於這個功能沒作用。

⚠️ **國字數字規則收窄過一次，這是第三次踩到同一類錯誤。**
第一版寫成「國字＋單位就擋」，結果「十分安穩」被誤判（那是「非常安穩」
不是「十分鐘」），「再試一次」「提早一小時」同理。回頭想真正的缺陷是什麼：
出問題的 4 晚**全是小數**（十點三、九十八點四），整數國字量詞從來不是問題。
收窄成「必須有『點』」之後誤判消失。
**教訓（已經第三次）：規則寫寬很省事，但誤判的代價是整晚退回規則式文字。**
前兩次分別是「沒看清」與 `SIMPLIFIED_CHARS` 的于／后／里。

### 這一輪的量測結果（46 晚實測）

| 指標 | 修正前 | 修正後 |
|---|---|---|
| 「圖書館 or 海床」 | 32 晚（70%） | **8 晚（17%）** |
| 用到的意象家族 | 5 種 | **16 種** |
| 國字數字 | 4 晚 | **0 晚** |
| 夢境出現數字 | 0 | 0 |
| fallback | — | **0 晚**（46/46 全 LLM） |
| Garmin 分數 | — | **與基準逐位元組相同** |

### ⚠️ 已知未解，留給下一輪（診斷已完成，修法很小）

**集中點搬家了**：「棉被與雪」現在佔 17 晚（37%）。文字彼此有差異
（各有不同的感官細節），但 06-01 與 06-06 仍然接近。

**根因是 `MOTIF_FAMILIES` 的粒度與調色盤不對稱：**

```
深睡類 6 個選項 → 只對應 2 個家族（海床沉降 / 棉被與雪）
REM 類 6 個選項 → 對應 5 個家族  ← 所以它沒有這個問題（圖書館只剩 8 晚）
```

深睡類兩個家族都用過後，`recent_motifs` 就沒有「沒用過的」可推薦，
而這個資料集 Good 夜晚有 31 晚，深睡充足的夜特別多。

**修法**：把 `MOTIF_FAMILIES` 拆成與調色盤選項一對一（約 6 行），再重跑 46 晚。

**Part B 已於 2026-08-12 完成真實呼叫**：`ai/.env` 的 `ANTHROPIC_API_KEY` 已填
（該檔已被 gitignore 擋住，`git check-ignore` 驗證過），模型設為 `claude-sonnet-5`。

⚠️ **第一次真實呼叫就抓到兩個 prompt 層的 bug，兩個都已修好（`PROMPT_VERSION` 升到 v2）。
這兩個都不是「模型偶爾出錯」，是 prompt 結構本身有問題，記在這裡避免改回去：**

1. **「日記中間幾頁是空白的」意象被誤用在 REM 有測到的夜晚。**
   這個意象不是修辭，是把「手錶沒測到 REM」誠實寫進敘事的機制——用在有資料的夜晚，
   等於對使用者謊稱這段沒有記錄，跟 payload 那三個誠實 null 是同一件事。
   實例：2026-08-09 的 REM = 29 分鐘（9.0%），模型仍寫了空白頁。
   **根因是 few-shot 把兩個獨立條件綁在一起**——範例二同時是「評級 Bad」又是「REM 未測得」，
   模型在 Bad 的夜晚就整段照抄。
   修法（三層，缺一不可）：
   - 調色盤那一行改成**只有 `rem_unmeasured` 為真時才放進 system prompt**
     （`build_system_prompt()`）
   - REM 有測到時**明確禁止**，不只是不提供（`PALETTE_REM_MEASURED`）
   - few-shot 拆成兩版依當晚條件挑（`build_few_shot()`）
   - `validate()` 加 `MISSING_RECORD_MOTIFS` 關鍵字擋，通不過就重試
   **第四層真的救到了**：修好前三層之後重跑，模型第 1 次仍寫出「沒看清」被驗證擋下，
   重試才過。光把選項拿掉不夠，模型自己的先驗會把它帶回來。

2. **簡體字混進 zh-TW 輸出**：`claude-sonnet-5` 寫出「門边」（門正體、边簡體，同一個詞裡兩種字形）。
   已加 `SIMPLIFIED_CHARS` 檢查 + FORMAT_RULES 明寫「一律臺灣正體中文」。
   該集合**刻意不含 于／后／里**——那些字正體中文本來就會用（皇后、公里），
   誤判的代價是整晚退回規則式文字。

3. **我自己的驗證規則太寬，反而害 3 晚退回規則式**（全量跑完才發現）：
   第一版把「沒看清」列為無條件禁詞，但 `PALETTE_REM_MEASURED` 才剛叫模型
   「REM 比例低要寫夢很淡、很快就過去」——而「來不及看清楚就散掉」正是那個意思，
   是在形容夢很模糊，**不是**在宣稱資料不存在。prompt 跟驗證規則互相打架。
   已收窄成兩組：`MISSING_RECORD_MOTIFS`（空白/留白/沒有記錄/沒看見等無條件擋）
   與「`SECTION_WORDS` + `VAGUE_VERBS` 同時出現才擋」（「中間…沒看清」擋、
   「來不及看清楚」放行）。收窄後回歸測試：原始錯誤文字仍被擋、正常說法放行、
   既有 43 晚零誤判。

**最終結果：46 晚全部由 LLM 生成（0 晚 fallback），全數重新驗證通過。**
`app/assets/data/app_payload.json` 的 `ai_content.is_ai_generated` 已是 `true`。

⚠️ **另修掉 `run_pipeline.py` 的跨終端機 bug**：它第一行就印中文標題，在 Windows
Git Bash（cp1252）下**跑任何步驟之前就 UnicodeEncodeError 崩掉**，PowerShell 則沒事——
同一台機器兩種結果。已加 `sys.stdout.reconfigure` + 對子行程設 `PYTHONIOENCODING=utf-8`
（設環境變數而非逐支腳本改，這樣新增步驟時不會忘記）。

`ADVICE_LANG` 這個設定**沒有實作**（輸出固定正體中文，prompt 本身就是中文寫的）。
`.env.example` 已改成誠實說明，不要以為改那個變數就能換語言。

Part A 那個已驗證的坑（`.gitignore` 的 `.env.*` 會連 `.env.example` 一起擋掉）
已用 `!.env.example` 修好並實測確認。同時新增了 `turn_*.mp4`——
兩支 TAPO 程式都會產生**臥室錄影片段**，原本沒有任何規則擋住它們。

Part B 的已定案決策（不要重新討論）：
- **模型用 Claude API**（Anthropic），用標準庫 `urllib.request` 打，**不裝 SDK**
  （理由：這功能不會讓 `requirements.txt` 多任何一行）
- AI 程式**獨立成 `ai/` 資料夾**，不要塞進 `garmin/`
- AI 要**整合 Garmin + TAPO** 給建議；TAPO 目前無真實資料 → 介面設計成有資料才自動啟用
- AI 的真正價值在**跨夜趨勢**（規則式 `recommendation` 46 晚只產生 8 種字串），
  數值判斷仍留在 Python 規則層，模型只負責敘事

### 前端整合的現況（2026-08-12 更新）

三個阻塞點都已解除：4 個 0 bytes 的 model 已填好、新增了 `app/lib/services/`、
`main.py` 已改成回傳真實資料。

**資料通道走 bundled asset，不走 HTTP**（已定案）：

```
garmin/data/*.json → build_app_payload.py → app/assets/data/app_payload.json
                                                    ├─→ Flutter rootBundle 讀
                                                    └─→ main.py 對外服務同一個檔
```

只產一份檔的理由：兩份就會有「App 顯示的跟 API 回傳的對不上」這種最難查的 bug。
`rootBundle` 與 `dart:convert` 都是內建的，所以**這條路徑沒有讓 `pubspec.yaml`
多任何一個套件**。之後要接 HTTP 只要實作 `sleep_repository.dart` 裡預留的
`ApiSleepRepository`（那時才需要加 `http` 套件）。

**還沒接的**：`report_screen.dart`（Insights 頁，34 KB，資料寫死在 `CustomPainter`
內部）與 `assistant_screen.dart` 的問答。`payload` 裡已經帶了 `history`（最近 30 晚），
要接 Insights 時不用改後端。

⚠️ **動 `app/` 之前先問 Jeremy**——那是他負責的部分。這一輪只碰了
「0 bytes 的空檔 + 全新檔案 + `home_screen.dart`」，刻意避開 `report_screen.dart`
以降低衝突面。


---

## 📌 2026-08-12 這一輪（Part A–E：基礎建設、AI、資料交接層、Flutter 資料層）

### Part 0–E 進度表（當時的計劃檔：`~/.claude/plans/encapsulated-squishing-rivest.md`）

計劃檔存在全域 `~/.claude/plans/`，**換工作目錄後仍讀得到**，細節請直接讀它。摘要：

| | 內容 | 狀態 |
|---|---|---|
| Part 0 | 推上 GitHub | ✅ 已完成（PR #9 已合併） |
| Part A | 基礎建設：`requirements.txt`、修 `.gitignore`、`.env.example` | ✅ 已完成（2026-08-12） |
| Part B | **AI 睡眠顧問**，獨立 `ai/` 資料夾 | ✅ 已完成（2026-08-12，含真實 API 呼叫） |
| Part C | `PROJECT_STATUS.md` 現況報告（給團隊/教授） | ✅ 已完成（2026-08-12） |
| Part D | **資料交接層**：`build_app_payload.py` + `main.py` 接真資料 | ✅ 已完成（2026-08-12） |
| Part E | **Flutter 資料層**：4 個 model + `services/` + HomeScreen | ✅ 已完成（2026-08-12） |


> 完整計劃在 `C:\Users\user\.claude\plans\plan-app-graceful-pie.md`。
> **那份檔案已於 2026-08-15 整個改寫成「產品化路線圖」**，不再是 TAPO 接入計劃——
> 因為使用者確認了目標是「別人能實際裝來用的產品，時間一學期以上」，
> 在那個標準下重新盤點的結論是：**技術難的部分幾乎都做完了，缺的是產品的部分**。
> 兩個最根本的缺口：**整個系統假設世界上只有一個使用者**、**資料不會自己更新**。

---

## 📌 2026-08-11 這一輪

✅ **garmin/ 資料夾整理**（原本 19 個檔案裡有 11 個是生成物，平鋪在同一層）

1. **生成物集中到 `garmin/data/`**，`garmin/` 只留 6 支程式 + README。
   五支腳本的路徑改用 `Path(__file__).parent / "data"`，不再是相對路徑字串——
   從專案根目錄或 `garmin/` 執行都能正確定位（已實測兩種都可）。

2. **新增 `garmin/run_pipeline.py`**：依序執行 4 步（加 `--fetch` 才含抓取），
   任一步失敗立即中止並回傳非零 exit code。解決「漏跑中間步驟不會報錯」的隱患。

3. **刪除 `garmin_importer.py`**（讀手動匯出 CSV 的替代入口）。查證後確認
   `garmin_export/` 資料夾從未存在，這條路徑從來沒被使用過。但它不能直接刪——
   `garmin_connect_fetch.py` 有 `from garmin_importer import ...` 借用兩個函式：
   - `build_standard_payload()` → 已搬進 `garmin_connect_fetch.py`，
     並順手修掉 `source` 標籤寫死的問題（API 抓的資料原本會被標成「手動匯出」）
   - `build_project_payload()` → 直接移除。它有已知 bug（沒按「一晚」分組，
     把 13 天算成一晚），而且它的產出 `garmin_project_payload.json` **全專案沒有
     任何程式讀取**——等於每次抓資料都產生一個沒人要的錯誤檔案

4. **`GARMIN_IMPORT_GUIDE.md` → `garmin/README.md`**：舊文件內容全是已刪除的
   importer 用法。新 README 有 pipeline 流程圖、各步驟輸入輸出、已知限制表、
   資料語意注意事項。專案根目錄 `README.md` 的 Garmin 段落也一併更新。

5. 驗證：整理前後 `garmin_sleep_quality_final.csv` 完全一致（`diff` 確認）。

⚠️ **這輪也發現我自己前一次的疏漏**：宣稱「全流程重跑無誤」時實際漏跑了
`extract_sleep_features.py`。那次剛好沒造成錯誤（改動只是新增下游沒用到的欄位），
但這正是 `run_pipeline.py` 要防的問題。**日後宣稱「跑過了」之前，先確認每一步都真的跑了。**


---

## 📌 2026-08-10 這一輪

1. ✅ **M（睡眠片段化）由 Tier4 併入 Tier3，Tier3 上限 ±10 → ±12；J（睡眠規律性/SRI）
   已實作計算但「刻意不計分」，只呈現數值與趨勢。**
   M 併入而非另立一層的理由：本專案區分 Tier1/2 與 Tier3 的判準一直是「文獻給絕對參考範圍
   vs 相對個人 baseline 的偏離量」，不是「生理 vs 作息」這種題材分類。M 的文獻明說沒有
   跨族群通用門檻，性質跟心率/壓力一致。
   - `analyze_garmin_sleep.py` 新增 `awake_count`、`sleep_segment_count` 兩欄
     （沒戴錶的日子輸出 None 而非 0，避免被誤判成「醒來 0 次、超規律」）。
   - `apply_recovery_modifier.py` 新增 M（醒來次數 ±1 + 睡眠段數 ±1）與 SRI（不計分）。

2. ⚠️ **J/SRI 最終「不計分」的完整推理（重要，這段是整輪最有價值的產出）：**
   依序排除了三種做法，每一種都是實際做過或查證過才排除的：
   - ❌「今晚 vs 個人 baseline」逐夜比較：會把測的東西從「你有多不規律」偷換成
     「你最近有沒有比以前更不規律」。長年作息都亂的人永遠拿 0 分（沒變得更亂），
     但文獻說這種人正是風險族群 → 構念不符，跟 K 節 Troxel/MSLT 是同型錯誤。
     且會**懲罰作息改善**：07-11 那晚 22:42 上床（平常凌晨 1-3 點）明明是變好，
     卻因「偏離常態」被扣分，而且整個調整期都會被持續扣。
     統計上也不乾淨：SRI 本身是 28 天滾動值，相鄰兩天窗格有 27 天資料重疊（96%）。
   - ❌「就寢時間標準差 + 自訂切點」：查證後三篇候選文獻各有致命傷（Wong 2022 年齡吻合
     但沒標明數字是否為標準差、Price 2023 測的是「睡眠中點」標準差構念不符、UK Biobank
     構念對但平均 62 歲且只是研討會摘要）。且技術上有 bug：用「距中午幾分鐘」換算時，
     橫跨中午的起床時間會被錨點切開，算出 507 分鐘的假變異度（實際只差 1 小時）。
   - ❌「SRI 對照同齡常模計分」（一度已經寫完並跑過）：**Czeisler 2026 證實
     同一批資料用 sleepreg 跟 GGIR 兩套件算，SRI 差異顯著，且「光是計算方法不同
     就足以改變死亡率、糖尿病、心房顫動模型的結果與詮釋」**。佐證：NHANES（54.5 歲）
     SRI 平均 63.0 vs UK Biobank（62.8 歲）中位數 81.0——差 8 歲卻差 18 分，
     顯然是方法學差異不是年齡效應。我們這個近似實作跟外部常模的誤差極可能超過
     整個 ±2 額度，那個比較本身就沒有意義。
   - ✅ **最終：SRI 照算照輸出（供 App 顯示數值與趨勢），但不進 total_modifier。**
     分寸是：Windred 2024 能支持「規律性重要、值得呈現」（預測死亡率優於睡眠時長），
     但支持不了「今晚 SRI 該換算成幾分」。之後若 RIRI 標準普及或能自建同齡常模，
     計算邏輯都保留著，恢復計分只需改幾行。
   - 實測：28 日滾動 SRI 範圍 69.5–80.4，07-11 因提早上床正確地由 79.2 掉到 69.5。

   ⚠️ **順帶抓到第二起作者誤植**：文件原本寫「Mason et al.」的那篇 RIRI 論文，
   第一作者其實是 **Czeisler ME**，且缺卷期。已更正為 Sleep. 2026;49(4):zsaf299。
   這是繼 K 節 Troxel/Iskander 之後第二次，**日後引用文獻一律要核對第一作者**。

3. ✅ **M 刻意排除 WASO**：M 節文獻用「WASO+醒來次數+睡眠段數」定義片段化概念，但 WASO
   已在 Tier1 佔 25 分，再算一次會讓同一數值影響總分兩次。窄化為只用醒來次數+睡眠段數，
   這兩者補的正是 WASO 看不出的資訊（同樣清醒 40 分鐘，「醒一次躺很久」vs「醒八次各五分鐘」
   完全不同）。已在文件誠實標註此窄化。

4. ⚠️ **發現並修掉 `activity_modifier` 的資料有效性問題（重要）：**
   實測步數中位數只有 **185 步**。查證後確認原因是**起床後會取下手錶、傍晚才戴回**
   （心率讀數佐證：12:00 只有 45 筆/小時、17:00 回到 734 筆、19:00 後回到 1100 筆）。
   所以 `steps_total` 測到的是「傍晚在家的活動量」，不是全日活動量。
   - 統計問題：baseline=185 時，多走 19 步（+10%）就打滿 +2 分——19 步是雜訊。
     這就是壓力分數當初那個「小分母」bug 的重現，而程式碼註解原本還寫著
     「步數 baseline 通常夠大，不會有這問題」，該假設已被自己的資料推翻。
   - 構念問題：H 節文獻研究的都是每日數千步的族群，「活動量高於常態有助睡眠」
     這個結論從沒在 185 步的量級上被檢驗過。
   - 已加 `ACTIVITY_MIN_BASELINE_STEPS = 1000` 門檻自動停用，且 `modifier_note` 會
     明確區分「資料無效（要改配戴習慣）」與「冷啟動（繼續戴就好）」——後者講法會誤導。
   - 修掉後平均修正值由 0.89 降到 0.04，更合理（基於個人 baseline 的修正值長期本來就該
     趨近於零，先前的 0.89 是被灌水的活動量加分撐起來的）。

5. **目前 Tier3 全貌**（33 晚實測，飽和率健康、1 晚改變分級且是相鄰級距）：
   | 訊號 | 額度 | 飽和率 | 啟用條件 |
   |---|---|---|---|
   | 靜止心率 | ±2 | 10% | 累積 14 晚 |
   | 睡眠期間平均心率 | ±2 | 10% | 累積 14 晚 |
   | 壓力 | ±4 | 14% | 累積 14 晚 |
   | 活動量 | 0~+2 | — | 累積 14 晚 **＋ baseline ≥1000 步**（本專案停用中）|
   | 醒來次數 | ±1 | 15% | 累積 14 晚 |
   | 睡眠段數 | ±1 | 15% | 累積 14 晚 |
   | **SRI（不計分）** | **—** | — | 28 日內 ≥10 組相鄰日配對；只輸出數值供呈現 |

   總上限 ±12。輸出欄位：`rhr_modifier`、`avg_hr_modifier`、`stress_modifier`、
   `activity_modifier`、`awake_modifier`、`segment_modifier`、`total_modifier`、
   `sri`（呈現用）、`sri_valid_pairs`、`modifier_note`、`final_score`、`final_quality`。

   > ⚠️ **上表是 2026-08-10 的歷史記錄。壓力與活動量兩列已於 2026-08-25 改動**
   > （量測時窗差了一天），最新狀態見本檔案「📌 2026-08-25 這一輪」。

6. 待辦（尚未動工）：
   - 中強度活動分鐘數（需接 `get_intensity_minutes`）——但在配戴習慣改變前，
     接了也一樣拿不到有效的白天資料，優先度低。
   - TAPO 側（`tapo/motion_detector.py`）有一套獨立的 `sleep_quality_score`，與本檔案輸出的
     `final_score` 邏輯、格式皆不同，需與隊友/PM 對齊要顯示哪一個或如何合併，尚未處理。
   - `main.py` 仍回傳寫死 mock_data，未接上 `garmin_sleep_quality_final.json`。


---

## 📌 2026-07-31 這一輪

1. ✅ **新增 `garmin/apply_recovery_modifier.py`，V2/Tier3「生理修正訊號」正式實作上線。**
   讀 `garmin_sleep_quality.csv`（Tier1/2 基礎分數）+ `garmin_sleep_summary.csv`（心率/壓力/步數），
   輸出 `garmin_sleep_quality_final.csv/json`（`final_score = clamp(基礎分數 + 修正值, 0, 100)`）。
   四項修正訊號、各自獨立冷啟動（累積 <14 晚有效歷史資料則該項修正值=0，非全有全無）：
   - 靜止心率 ±2（`RHR_CAP`，Quer 2020）
   - 睡眠期間平均心率 ±2（`AVG_HR_CAP`，Cosgrave 2021）
   - 壓力分數 ±4（`STRESS_CAP`，Vivoactive 3 無 HRV，以 Garmin 壓力分數替代）
   - 活動量（步數）0～+2（`ACTIVITY_CAP`，僅加分不扣分）
   總上限 ±10。baseline 採最近 14–28 晚中位數，只用「當晚之前」的歷史資料，避免時間序列資料洩漏。
   全檔逐行加了說明注釋（使用者要求）。已用 33 晚真實資料驗證：21 晚套用非零修正值、
   平均修正值 0.35、2 晚因修正值改變分級。

2. ✅ **修掉壓力/心率修正值的統計不穩定 bug（2026-07-30 記錄）**：原本用「相對 baseline 的
   百分比」換算，但壓力分數 baseline 偏小（例如平常僅 3–7 分）的夜晚，些微絕對變化會被
   百分比公式放大到不合理程度（同樣差 8 分，baseline=7 時是 -114%、baseline=50 時只有 -16%），
   屬「除以小分母」的統計不穩定，非設計邏輯錯誤。已改為「絕對差距」換算（每差 1 bpm / 1 分
   壓力分數給固定分數），不再受 baseline 大小影響；步數因 baseline 數值本身較大，維持用百分比。

3. ✅ **心率修正值拆成靜止心率／睡眠期間平均心率兩個子項（2026-07-31 記錄）**：原本只用
   `resting_heart_rate` 算心率修正值，後來發現 `Garmin手錶分數.md` F 節已有的 Cosgrave (2021)
   引用其實對應的是「睡眠期間平均心率」（`avg_heart_rate`）這個獨立子構念，先前沒接進程式碼。
   已補上 `avg_heart_rate` 修正值，並把原本合計 ±4 的心率額度拆半（RHR ±2、avg_HR ±2），
   而非兩者各自獨立滿額——理由是二者高度相關、同屬心血管自律神經訊號，各給滿額會造成
   同一件事被重複計分，跟「淺層睡眠不獨立計分，因深睡+REM+淺層=1」是同一道理。

4. ✅ **`Garmin手錶分數.md` 同步更新**：F/G/H 節各補上「實作更新」段落，I 節 Tier3 狀態由
   「V2 規劃中」改為「V2 已實作」並更新分項額度，附錄對照表 F 列拆成靜止心率／平均心率兩列，
   修訂記錄補上 2026-07-30（百分比→絕對差距）與 2026-07-31（心率拆分項）兩筆記錄。


---

## 📌 2026-07-20 這一輪

1. ⚠️→✅ **文獻查證與後續逐項核對，最終合併成單一文件**——正式且唯一的成果是
   [`Research-Background/Garmin手錶分數.md`](Research-Background/Garmin手錶分數.md)
   （A–M 共 13 節完整學術論述 + 附錄「文獻門檻 × 程式碼對照表」+ 修訂記錄 + Sonnap 章節樹狀架構）。
   演變過程：`_Perplexity_文獻查證交接.md` 是查證草稿、不是待辦事項；Claude 一度誤判成
   「還沒查證」而用 WebSearch 重查一次，另存成 `睡眠品質評分文獻依據.md`；後來逐項核對兩份文件，
   發現並修正了 B/F/G/I 節共 4 處真實的邏輯缺口（B 節自相矛盾、F/G 節引用內容支撐不了設計邏輯、
   I 節內部兩段話互相矛盾且跟 V1 程式碼對不上）；2026-07-30 使用者要求把兩份文件合併成一份，
   避免文件太多——`睡眠品質評分文獻依據.md` 的對照表與修正記錄已整併進 `Garmin手錶分數.md`
   附錄，原檔已刪除。獨立查證的結論可信：程式引用的文獻皆為真實存在、DOI 正確的論文。
   **後續有新文件要交接給別的 Claude/VS Code 前，先開口問對方現有進度，不要預設「沒做過」。**

2. ✅ **修掉 `evaluate_sleep_quality.py` 的建議文字矛盾 bug**：`build_recommendation()`
   原本只要「失分比例 > 15%」就會加一句改進建議，沒考慮整晚等級已經是 Good，
   導致像 2026-05-31（總分 93.8）出現「請維持目前的作息」後面又接「睡眠時間不足，
   建議提早就寢」的自相矛盾。已修成 Good 等級不再附加改進建議。重跑後掃過全部
   33 晚輸出，確認無殘留矛盾。平均分數 85.4（Good 25 / Normal 6 / Poor 1 / Bad 1，
   8 晚 REM 未測得排除計分）。


---

## 📌 2026-07 已完成的舊規劃：Sleep Feature Extraction + Quality Evaluation

> ⚠️ 這節原標題是「Next Development Goal（下一步）」，**已於 2026-07 全部完成**，
> 保留下來只是歷史記錄。真正的下一步請看檔案開頭的「🔖 交接區」。

延續現有 pipeline，新增兩支腳本（此規劃已跟另一個 AI 助手的建議比對過，方向正確，
但補上了資料完整性前置修正，避免建立在有瑕疵的資料上）：

**動手前，先處理資料完整性（順序很重要）：**
1. ✅ 已完成（2026-07-11）：重跑 `garmin_connect_fetch.py`，抓 2026-05-29~07-11 共 44 天、53489 筆，
   `garmin_standard_data.json` 已補回（7.5MB）。過程中修掉了 `_parse_sleep_data` 的 UnboundLocalError
   （sleepLevels 那段縮排錯誤，見問題原 #7 相關；沒睡眠資料的日子會觸發）。
2. ✅ 已完成（2026-07-12）：修好 `analyze_garmin_sleep.py`，兩項重大修正：
   (a) 分組改用「起床日」(session date = wake date)。已用 Garmin 原始 `calendarDate` 欄位驗證：
       7/10 22:42 上床、7/11 07:51 起床的那晚，Garmin 自己標記為 calendarDate=2026-07-11。
       修正後 07-10 正確變空、該晚移到 07-11，與 Garmin App 一致。跨午夜夜晚不再被切開。
   (b) 睡眠階段輸出改成「分鐘」(deep/light/rem/awake_minutes + total_sleep_minutes)，
       取代原本的「段數 count」。分鐘值直接來自 Garmin dailySleepDTO 的 *SleepSeconds，
       已驗證與 Garmin App 完全一致（例：06-11 深48/淺329/REM98 分；07-09 總541分=9h01m）。
   ⚠️ 資料語意澄清（之前混淆點）：
       - 睡眠階段 → Garmin 顯示「分鐘」，不是段數。正確資料在 *_duration_sec，已改用。
       - resting_heart_rate → 單一每日數字（Garmin 圖示旁的數字），正確。
       - movement_count → 我們自訂的翻動取樣筆數，非 Garmin 顯示值，勿直接對照。
       - steps → 見下方步數決策。
   ⚠️ 裝置限制：Vivoactive 3 沒有 Garmin 睡眠分數（sleepScores 欄位不存在），無法用官方分數驗證評分。
       且部分夜晚 REM=0（Garmin 也顯示無 REM），是舊錶偵測限制非 bug。
3. ⏭️ 待做：在 `extract_sleep_features.py` 加資料有效性檢查。實測需要濾掉的列：
   - 無睡眠記錄的日子（手錶沒戴睡）：05-28, 06-16, 06-19, 06-20, 06-23, 06-25, 06-29,
     07-03, 07-04, 07-05, 07-08, 07-10（sleep 欄位空、total_sleep_minutes=0）。
   - 06-02 異常：sleep_start == wake == 00:00:00（睡眠時長=0）。
   - 資料極少的日子（連 avg_heart_rate 都是 null）。

**步數決策：✅ 已完成（2026-07-12）改用官方 `get_daily_steps`。**
- fetch 新增 `_parse_daily_steps()`，主迴圈改呼叫 `get_daily_steps(day, day)`，輸出 `daily_steps`
  與 `step_goal` metric（時間戳設在該日 15:00 避開睡眠區間）。
- analyze 改讀 `daily_steps`（直接設定非加總）。已重抓驗證：06-11 = 195 步（= Garmin App）。
- 現在整條 pipeline（fetch → standard_data → analyze → summary）數字全部與 Garmin App 一致。
- summary 欄位：date, sleep_start_time, wake_time, total_sleep_minutes,
  deep/light/rem/awake_minutes, movement_count, steps_total,
  avg/min/max_heart_rate, avg_stress_score, resting_heart_rate。

**接著實作 `extract_sleep_features.py`：**
- 輸入：`garmin_sleep_summary.csv`
- 輸出：`garmin_sleep_features.csv`
- 每天產生：Sleep Duration (hours)、Deep/REM/Awake Ratio、Average Heart Rate、Resting Heart Rate、
  Average Stress、Movement Count、Total Steps、Sleep Efficiency (optional)。

**再實作 `evaluate_sleep_quality.py`（rule-based scoring，總分 100）：**

⚠️ 評分權重已於 2026-07-15 依文獻改版。原本的 30/20/15/15/20（時長/深睡/REM/清醒/HR+壓力+翻動）
**已作廢**，改採 `Research-Background/Garmin手錶分數.md` 的 PSQI 式「核心高權重、輔助低權重」原則。

**V1 權重（只用現有資料算得出、且有文獻門檻的指標）：**
| 指標 | 權重 | 文獻 | 門檻 |
|---|---|---|---|
| 睡眠時長（核心）| 30 | Hirshkowitz 2015 | 分齡，成人 7–9h |
| 睡眠效率（核心）| 25 | Hertenstein 2018 | ≥85 佳／80–84 尚可／<80 低 |
| WASO 夜間清醒（核心）| 25 | Ohayon 2004、Harrison 2021 | 分齡，年輕成人 0–15min 佳 |
| 深層睡眠比例（輔助）| 10 | Boulos 2019、Hertenstein 2018 | 13–23% 參考區間 |
| REM 比例（輔助）| 10 | Ohayon 2004 | 分齡，年輕成人 20–25% |

- 分級：80-100 Good／65-79 Normal／50-64 Poor／<50 Bad。
- 輸出 `garmin_sleep_quality.csv` / `garmin_sleep_quality.json`。
- Recommendation 先用 rule-based 文字，之後可替換成 Gemini AI 生成。

**V2 待加（各有前置條件）：**
- 心率／壓力：文獻要求「個人 baseline（近 14–28 晚）+ 趨勢」，非固定 bpm。
- 活動量：文獻要求「相對個人 baseline + 中強度分鐘數」，需另抓 `get_intensity_minutes`。
- 睡眠規律性（就寢/起床變異、平假日差）：用現有 summary 即可算，尚未實作。
- 入睡潛伏期 + 真實睡眠效率：**需等 TAPO 攝影機提供「上床時間」**（見下方）。
- 睡眠片段化：需把 `standard_data` 的 sleep_segment 數與醒來次數帶進 summary。

**已決議的設計決策（2026-07-15）：**
1. **年齡**：由使用者註冊時輸入。V1 先做成可設定參數，預設「年輕成人 18–25」。
   文獻的時長／REM／WASO 門檻都要分齡，不能用單一標準。
2. **權重**：採文獻的 PSQI 式核心/輔助架構（見上表），不用原本的固定 30/20/15/15/20。
3. **範圍**：先做 V1，其餘進 V2。

**⚠️ 資料語意重要澄清：**
- **HRV ≠ 心率**。心率是「一分鐘跳幾下」；HRV 是「每兩下心跳間隔時間的變化量（ms）」。
  我們抓的 `heart_rate` 是每分鐘平均值，**無法反推 HRV**（需 beat-to-beat RR interval）。
  但 Garmin 的「壓力分數」本身即由 HRV 推算，等於已間接取得 HRV 資訊。
  Garmin HRV Status 為 2022 後新錶功能，Vivoactive 3 很可能不支援（尚未實測 `get_hrv_data`）。
- **目前的 `sleep_efficiency` 不是臨床真效率**。因缺「上床時間」，分母用的是
  （起床 − 入睡），實為「睡眠期間效率」，不含入睡潛伏期。報告中須誠實標註。

**TAPO 攝影機整合（規劃中，會解鎖兩個文獻指標）：**
- 目標：由攝影機偵測「上床時間」（人進入床鋪區域並躺下），Garmin 已提供「入睡時間」，兩者互補。
- 解鎖：入睡潛伏期 = Garmin 入睡 − 攝影機上床；真實睡眠效率 = 總睡眠 ÷（起床 − 攝影機上床）。
- 三個必須解決的前置問題：
  1. **時間同步**（最關鍵）：攝影機與 Garmin 時鐘須對準同時區且準確，否則潛伏期無意義。
  2. 夜視環境：紅外線雜訊大，建議用「床鋪 ROI + 動作趨於穩定」規則，非純畫面差分。
  3. 「上床」定義：建議為「當晚第一次進入床鋪區域並持續停留」；需處理半夜起身、在床滑手機等情況。
- 隱私：臥室攝影機需在報告中說明資料處理與知情同意。

**架構決策（需要跟團隊對齊，不要自己悶著做）：**
- 這個新流程（summary → features → quality）跟原本 README 定義的 data contract
（`pet_mood`/`energy_level`/`dream_summary`，透過 `main.py` 的 FastAPI 提供給 Flutter）是兩條不同路徑。
  需要決定：quality score 要怎麼映射回 `pet_mood`/`energy_level`？最終是 Flutter 直接讀 JSON 檔，
  還是透過 FastAPI API？做決定前先跟 PM/前端對一次，避免兩條資料流各自為政。
- ✅ 已處理（2026-08-11）：`garmin_importer.py` 與其 `build_project_payload()` 已刪除，
  組員不會再誤用那個有 bug 的舊路徑。

**Coding 規範（沿用團隊既有規範 + 新腳本要求）：**
- 保持現有專案結構，不要破壞現有 Garmin parser。
- Python 3.13，輸出檔案一律 UTF-8，時間格式一律 ISO8601（+08:00）。
- 優先用標準庫，非必要不用 pandas。
- 程式碼要模組化、可重用，關鍵邏輯加註解。
