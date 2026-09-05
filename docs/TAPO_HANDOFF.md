# TAPO 攝影機：交給影像組的問題清單與偵測層規格（2026-08-31 建立，09-01 補上規格）

這份清單來自對 `tapo/`、`tapo 2.0/` 全部程式碼與現有資料
（15 筆 SQL 列 + 9 份 per-night JSON）的逐項清點。
**每一條都可以用 `python inspect_tapo_score.py` 重現**，不是推論。

**上半部是「哪裡壞了」（#1~#8），下半部是「該怎麼做」——
[偵測層的規格](#-該怎麼做偵測層的規格)。**

> 先講結論：**現在的 `sleep_quality_score` 不能用於任何比較，
> 而且不是調係數能修的。** 前四代公式都在調權重，但權重不是問題——
> 「一個事件」不是固定的單位才是（見 #1）。
>
> 好消息是 **`large_turn` 是好的訊號**：它的量級與文獻常模相符
> （De Koninck 1992：18–24 歲約 3.6 次/小時）。
> SQL 世代那 11 筆是 **0.3–8.1 次/小時**，正好跨在常模上下。
> JSON 世代偏高（4.7–20.6），但那批的分界門檻只有 150,000，
> 本來就會把一部分微動歸成翻身——**這也再次說明門檻要記下來**（見 #1）。
> 總之要救的是 `large_turn`，不是整套重寫。

---

## 🔴 前三項：不修的話，任何分數都不可信

### #1 每一筆紀錄都要記下「當晚用的偵測門檻」與程式版本

**現象**：從 `motion_intensity` 反推得出，門檻在夜與夜之間變過至少四組——

| 期間 / 來源 | 下限 | micro / large 分界 |
|---|---|---|
| 08-02 ~ 08-07（JSON） | 30,000 | 150,000 |
| 08-02 ~ 08-07（SQL） | 150,000 | ~350,000 |
| 08-18 | ~207,000 | ~450,000 |
| 08-20 ~ 08-22 | ~151,000 | ~300,000 |
| 08-23 ~ 08-25 | ~250,000 | ~350,000 |
| **repo 現行預設** | 50,000 | 250,000 / 350,000 |

**沒有任何一晚是用現在 `default_config` 裡的設定錄的**，
而且資料裡沒有任何欄位記著當晚用的是哪一組。

**為什麼嚴重**：`sleep_quality_score` 是事件數的線性函數。
門檻變 → 事件數變 → 分數變。所以兩晚的分數相差 30，可能只是因為
那兩晚的 `config.json` 不一樣，**與睡眠完全無關**。跨夜比較在原理上不成立。

**更直接的證據**：08-02 那一晚，`sleep_records` 裡是 80 分、
同一晚的 JSON 報告是 0 分。而 SQL 那一列的 32 筆事件，
正好就是 JSON 那 1177 筆裡強度 ≥150,000 的 32 筆——**逐筆吻合**
（08-04 是 75 對 75、08-05 是 111 對 111）。
也就是說那不是重錄，是 `clean_timeline_data()` 事後用新門檻把同一批事件
重貼了一次標籤。

**要怎麼修**：`sleep_records` 加欄位（或寫進 JSON 的 `summary`）：
`motion_micro`、`motion_large`、`min_motion_area`、`detector_version`。
`clean_timeline_data()` 要用**該筆紀錄自己的門檻**重貼標籤，不是用當下程式的。

---

### #2 `video_events` 是只寫不讀的變數 —— 錄影期間的事件全部被丟掉

**位置**（三個版本都一樣）：

| 檔案 | append 的位置 |
|---|---|
| `tapo/tapo_detector.py` | 1009、1058 |
| `tapo 2.0/tapo_detector.py` | 1074、1123 |
| `tapo 2.0/sleep_monitor.py` | 1164、1213 |

`grep video_events` 在這三個檔裡只會找到 `= []`、`.append(...)`、
以及一行 `print(f"💾 影片已儲存 (共 {len(video_events)} 個事件)")`。
**沒有任何地方把它併回 `sleep_timeline`。**

**後果**：每次大翻身觸發錄影後的 5–30 秒（`VIDEO_MIN_DURATION` ~
`VIDEO_MAX_DURATION`），期間所有事件都不會進 timeline、不會被統計、不會計分。
`total_events` 因此還取決於「那一晚有多少比例的時間在錄影」。

---

### #3 連續大翻身不會進 timeline —— `large_turn_count` 數的是錄影段數

**位置**：`tapo 2.0/tapo_detector.py:1067-1080`
（`tapo/tapo_detector.py:999-1015`、`sleep_monitor.py:1154-1170` 同構）

```python
if current_motion_type == "large_turn":
    if video_writer is not None:          # ← 已經在錄影中
        recording_timer += extension_time
        video_events.append({...})        # ← 只進 video_events（見 #2，會被丟掉）
                                          # ← 沒有 add_event_to_timeline()
    else:                                 # ← 只有這一支會進 timeline
        ...
        add_event_to_timeline(sleep_timeline, event_data, threshold_seconds=3)
```

**只有每一段錄影的第一次翻身進得去 timeline。**

**為什麼這一條特別要緊**：`tapo 2.0/tapo_detector.py:399` 的
`calculate_sleep_quality_score()` 與 `tapo/newsleep score count.py` 兩代公式
的核心都是**翻身間隔**（<5 分鐘扣最多）。而被丟掉的，正好是間隔最短的那些翻身。
`newsleep score count.py` 更糟——基礎分數由翻身總數決定（≤5 次 = 95 分），
所以**漏記翻身會讓分數變高**。

---

## 🟠 接下來三項：影響數值的正確性

### #4 `MOTION_MICRO` 的門檻讓偵測器每一幀都在觸發

**實測**（08-06 那一晚，7428 筆事件 / 8.88 小時）：

- **837 筆/小時**
- 相鄰事件間隔：**6203 / 7427 個正好是 0 秒**，96.5% ≤ 1 秒

文獻常模是 **11 次/小時**（Montini A, et al. *Sleep*. 2024;47(9):zsae138，
50 名健康成人的**錄影** PSG，IQR 8–15）。我們差 **76 倍**。

錄製當時的下限 30,000 px 在 1920×1080 上只佔畫面 **1.4%**，
低於這台相機夜視模式自己的雜訊底 → 量到的是感光雜訊 / 紅外線閃爍 / 自動曝光，
不是身體。而 `micro_motion` 佔全部事件的 **93%**。

**驗收標準建議**：不是「有沒有偵測到」，而是
**每小時事件數落在個位數到數十**（對照 Montini 的 IQR 8–15）。
現在 16 筆可算率的紀錄裡只有 7 筆落在這個區間
（另外 8 筆連率都算不出來——`time` 欄位壞掉，見 #8）。

---

#### 🔴 更根本的問題：`.env` 的門檻**不描述**已經存下來的資料

2026-09-04 實測，去重後 23154 筆 `micro_motion` 事件：

| | |
|---|---|
| 強度中位數 | **54,702** |
| `.env` 的 `MOTION_MICRO` | **250,000** |
| 強度真的高於門檻的 | **158 / 23154（0.7%）** |

也就是說，拿現在 `.env` 的門檻重新分類，**99.3% 的 micro_motion 會被降級成
`none` 而丟掉**。存下來的資料是用一組**低得多**的門檻寫的，而那組門檻
沒有記在任何欄位裡（這正是 #1 的內容）。

→ **結論：調 `.env` 救不回歷史資料。** 那批資料的門檻已經無從得知，
  跨夜比較在原理上就不成立。唯一的出路是 #1 + 下方的偵測層規格：
  **錄的時候只記原始度量，門檻事後再套**。

（`large_turn` 也對不上，只是沒那麼誇張：916 筆裡只有 54.0% 高於
`MOTION_LARGE = 350,000`。）

⚠️ 附帶：`motion_intensity == 2073600`（整畫面 1920×1080）有 **132 筆**
（去重後，佔全部 25239 筆事件的 0.52%），**全部**落在 `large_turn`
（916 筆中的 14.4%），micro 一筆都沒有。

**這不是隨機的誤判，是背景模型的暖機假影**（2026-09-02 追到根因）：

```python
# tapo 2.0/sleep_monitor.py:1026-1028
cap = cv2.VideoCapture(tapo_url, cv2.CAP_FFMPEG)
if cap.isOpened():
    fgbg = cv2.createBackgroundSubtractorMOG2(history=500, ...)
```

`fgbg` 是**在連上攝影機的當下才建立的**，所以第一次 `apply()` 沒有背景可比，
整幀都被判成前景 → `countNonZero` 恰好等於整個畫面。

> **實測 15 / 15**：所有含整畫面事件的紀錄裡，那一筆**永遠是該次錄影的
> 第一個事件**。真的動作不可能每次都剛好排第一。

⚠️ **後果比「多一筆假事件」嚴重**：我們原本用「首事件時刻」推算上床時刻，
算出「比入睡早 30–48 分鐘、四晚彼此一致」——那個一致性是真的，但它量的是
**監測程式幾點被打開**，不是使用者幾點躺上床。詳見 PROJECT_STATUS 3.9 的更正框。

**修法**：連線後丟掉前 N 秒（`history` 幀數 / fps，或直接用固定秒數）。
`tapo_metric_logger.py` 已經這樣做了——它把暖機期標成 `warmup` 欄位，
照樣寫進 CSV 但事後一律排除。**這是新舊管線目前唯一的行為差異，請照抄。**

修了它**不會改變分數的行為**——撐起事件量的仍然是 micro。

---

### #5 `decibel` 不是聲壓級，而且有一個世代是亂數

**亂數的部分**：08-02 ~ 08-07 那批 JSON，23552 筆事件裡只有 **18 個相異 dB 值**：

- `quiet` 全部落在 35–41 這 7 個整數上，各 3167–3333 筆
  （最多與最少只差 1.05 倍，理想均勻是 14.3%）→ `np.random.randint(35, 42)` 的形狀
- `snoring_or_noise` 落在 56–64
- `breathing_heavy` **恆為 55**

08-17 之後的 SQL 世代是 33 個相異值、17–34 連續遞減——那是真的量測。
**所以 `snore_count × 0.4` 在前一個世代扣的是亂數產生器。**

**單位的部分**（就算真的有量）：
`db = 20 * np.log10(rms)`（`tapo 2.0/tapo_detector.py:779`）
是相對 int16 最小刻度的 **dBFS**，天花板 `20*log10(32768) = 90.3`。

門檻 30 / 40 看起來像 SPL 的「安靜圖書館」，實際上是 **−60 / −50 dBFS**，
完全取決於這台相機的麥克風增益。

文獻對打呼的操作型定義是 **A 加權聲壓級（dBA）、麥克風固定在床頭上方 1 公尺**，
常用門檻 ≥40 dBA。我們的數字與任何 dBA 門檻之間**沒有可建立的對應關係**。

→ **在拿聲級計做過校準之前，打呼不可計分。**

⚠️ 兩版的門檻還不一致：`tapo/` 是 `20 / 30`，`tapo 2.0/` 是 `30 / 40`。
這就是 SQL 世代裡 `quiet`(17–36) 與 `breathing_heavy`(21–55) 的區間會重疊的原因。

---

### #6 覆寫規則會系統性地保留每一晚分數最低的那一份

**位置**：`tapo 2.0/tapo_detector.py:340`（`calculate_completeness_score`）
與 `:448`（規則 3）

```python
score = total_events + (large_turns * 2) + (duration_hours * 15)
...
elif new_score <= old_score:
    return False          # 只有「更完整」才覆寫
```

同一晚有多份錄影時，**事件多的那份勝出**。
而事件多正好是扣分多（`deduction = large*2 + micro*0.1 + snore*0.4`）。
→ 資料庫留下來的，是每一晚**分數最低**的那一版。

「完整度」與「品質」這兩個指標的方向是相反的，不該共用同一個比較。

---

## 🟡 #7 四代評分公式寫進同一個欄位，而且欄位沒有版本標記

| 代 | 位置 | 公式 | 會不會寫 DB |
|---|---|---|---|
| V1 | `tapo/tapo_detector.py:486`、`tapo 2.0/sleep_monitor.py:760`、**兩版的 `cleanup_existing_records()`** | `100 − (large×2 + micro×0.1 + snore×0.4)` | INSERT + UPDATE |
| V2 | `tapo/sleep_anylzer.py:96` | 翻身率 + 打呼 + 事件數分段 | UPDATE |
| V2.5 | `tapo 2.0/tapo_detector.py:399` | 翻身間隔 <5min −10 / 5–15 −5 / 15–30 −2 | INSERT（:550） |
| V3 | `tapo/newsleep score count.py` | 翻身總數定基礎分 95/85/70/50/30 | 批次 UPDATE |

**同一個檔裡就有兩代**：`tapo 2.0/tapo_detector.py` 的即時存檔路徑（:550）用 V2.5，
但同一個檔的 `cleanup_existing_records()`（:671）用 V1。
→ `sleep_quality_score` 的意義取決於「哪一支程式最後碰過那一列」。

**實測現有 dump 是 V1 寫的**：用 V1 重算 15 筆，14 筆逐分完全相符
（不符的 `id 117` 是 `timeline=[]` 但 `total_events≠0` 的寫入端 bug）。
**V3 寫好了但沒有套用到這份資料。**

→ 請統一成一支，並在資料裡標版本。
→ **在 #1~#3 修好之前，`sleep_anylzer.py` 與 `newsleep score count.py` 都不要再跑**——
  兩支都會 `UPDATE sleep_records SET sleep_quality_score`，
  跑下去就再也分不出哪一列是哪一代寫的。

---

## 🟢 #8 時間欄位的三類壞法

**(a) `time` 欄位整批壞掉 —— 6 筆紀錄。**
上百個事件的 `time` 全部擠在 0–4 秒內：

| 紀錄 | 事件數 | `time` 的跨度 |
|---|---|---|
| `sleep_report_115339_recovered.json` | 146 | 0 秒 |
| `sleep_report_114346/114556/114920_recovered.json` | 各 172 | 4 秒 |
| `sql#4` | 17 | 0 秒 |
| `sql#5` | 42 | 4 秒 |

平均每秒超過一個事件，物理上不可能是真的時刻。
→ 這幾筆連「每小時幾個事件」都算不出來（見 #4）。
→ 我們這端的解法是**改用 `video_clip` 檔名裡的時間戳**，
  但那只有 `large_turn` 有（只有大翻身會錄影），micro 沒有。

**(b) `id 117`（08-19）**：`total_events = 73` 但 `timeline = []`。

2026-09-04 追過一輪，**先前寫「寫入端與統計端不同步」並不正確**，
四件事排除掉了：

| 懷疑 | 查證結果 |
|---|---|
| 我們解析失敗？ | ❌ 原始 SQL 就是字面上的 `'[]'` |
| 欄位截斷？ | ❌ `timeline` 是 `longtext`；同一份 dump 裡 id 344 存了 121KB 沒問題 |
| INSERT 路徑寫錯？ | ❌ 兩支程式都用 `len(cleaned_timeline)` 當 `total_events`，寫不出這種組合 |
| 清理用的 UPDATE 路徑？ | ❌ 它也是 `total_events = len(cleaned)`，同步更新 |

而且**所有存檔進入點都有 `if sleep_timeline:` 保護**，空 timeline 存不進去。
剩下的線索是時間戳：`created_at 13:15:44`、`updated_at 18:47:37`
——**晚了 5.5 小時，計數欄位卻保留**。dump 是 phpMyAdmin 產生的。

→ **最可能是有人在 phpMyAdmin 裡手動清掉那一格**，不是程式的 bug。
  如果是這樣，程式面沒有東西要修；但請確認一下有沒有人動過那筆。

⚠️ 我們這端已經加了防護：`tapo_index` 一律以**數出來的**事件數為準
（所以壞資料不會流進下游），同時記下來源宣稱的數字與 `count_mismatch` 旗標
——靜靜地自我修復等於把來源端的資料損毀藏起來，下次就不會有人發現。
回歸測試在 `tests/test_tapo_index.py`【6】。

**(c) `id 48`**：宣稱 `report_date = 2026-06-11`，但 `created_at` 是 **08-18**（差 68 天），
而且只錄了 29 秒。這是唯一讓 TAPO 與 Garmin 六月資料產生「重疊」的紀錄。
我們這端已經用 `tapo_index.sleep_recording_problem()` 擋掉了。

---

## 🔧 該怎麼做：偵測層的規格

上面 #2 #3 #4 都指向同一件事——**問題在偵測層，不在評分層**。
前四代公式都在改評分，所以四代都沒有改善：那一層拿到的輸入本身就已經
丟失了必要的資訊。

### 為什麼現在的度量救不回來

```python
gray    = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
blurred = cv2.GaussianBlur(gray, (21, 21), 0)
fgmask  = fgbg.apply(blurred)
_, thresh = cv2.threshold(fgmask, 200, 255, cv2.THRESH_BINARY)
motion_area = cv2.countNonZero(thresh)          # ← 問題在這一行
```

`countNonZero` 是純計數，**它無法分辨「一個身體大小的連貫區塊」和
「散布在整個畫面的 10000 個雜訊點」**——兩者算出同一個數字。

```
情況 A：真的翻身                  情況 B：夜視雜訊
┌──────────────────┐            ┌──────────────────┐
│                  │            │ ·  ·   ·  ·  ·  ·│
│     ██████████   │            │   ·  ·   ·  ·  · │
│   ██████████████ │            │ ·   ·  ·  ·   ·  │
│   ██████████████ │            │  ·  ·   ·  ·  · ·│
│     ██████████   │            │ ·   ·  ·   ·  ·  │
└──────────────────┘            └──────────────────┘
  白點 = 50,000 個                 白點 = 50,000 個

        countNonZero 兩邊都回答：50000
```

而「白點連成一塊、還是散開」正是動作與雜訊唯一的區別。這個資訊在這一行
就被丟掉了，之後不管怎麼調門檻或評分係數都拿不回來。

**資料證實了這一點。** 08-06 那晚 7386 個 micro_motion 的強度分布，
從門檻開始**單調遞減**，62.4% 擠在門檻上方 25% 的帶內，
**沒有任何一個「典型動作大小」的眾數**：

| 強度 | 佔比 |
|---|---|
| 30,000–39,999（門檻正上方） | **25.5%** |
| 40,000–49,999 | 21.2% |
| 50,000–59,999 | 15.7% |
| 60,000–69,999 | 11.5% |
| …一路遞減至 140,000+ | 0.4% |

真實的身體動作會有一個特徵尺度，這個沒有。
→ 門檻不是在**選一個現象**，只是在雜訊衰減曲線上**挑一個點**。
這就是為什麼門檻一動、事件數就整批變（#1）。

⚠️ 順帶一個讀起來像在做事、其實沒有的東西：`detectShadows=False` 時
MOG2 只輸出 0 和 255，沒有 127（影子），所以
`threshold(fgmask, 200, 255)` 是 **no-op**。不會出錯，但會讓人以為
有在處理影子。

三個檔案裡 `morphologyEx` / `dilate` / `erode` / `findContours` /
`connectedComponents` 的命中數**全部是 0**，也沒有任何 ROI 遮罩。

---

### 建議的管線

```python
# ── 每一幀 ────────────────────────────────────────────────
small = cv2.resize(frame, (640, 360))            # ① 降取樣
gray  = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
blur  = cv2.GaussianBlur(gray, (7, 7), 0)        # 核心隨解析度縮小

# ② 照明變化否決
mean_now = blur.mean()
if abs(mean_now - mean_prev) > ILLUM_JUMP:       # 紅外燈切換／自動曝光／開燈
    fgbg.apply(blur, learningRate=0.2)           # 讓背景快速重學
    skip = RELEARN_FRAMES
    mean_prev = mean_now
    continue
mean_prev = mean_now
if skip > 0:
    skip -= 1; fgbg.apply(blur); continue

mask = fgbg.apply(blur, learningRate=LEARNING_RATE)          # ③ 背景相減
mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, KERNEL)        # ④ 開運算
mask = cv2.bitwise_and(mask, roi_mask)                       # ⑤ 只看床

# ⑥ 連通域：拿到「一塊一塊」，不是「幾個白點」
n, labels, stats, _ = cv2.connectedComponentsWithStats(mask)
areas   = stats[1:, cv2.CC_STAT_AREA]            # 第 0 個是背景，跳過
biggest = areas.max() if len(areas) else 0
fraction = biggest / roi_area                    # ← 這才是動作幅度

moving = fraction >= MIN_BLOB_FRACTION
```

| 步驟 | 解掉的問題 |
|---|---|
| ① 降取樣到 640×360 | 省 9 倍算力，而且**縮圖本身就在平均雜訊**——免費的降噪 |
| ② 照明否決 ＋ 丟棄暖機期 | 解掉 `motion_intensity = 2073600` 那 **132 筆**（去重後，large_turn 的 14.4%）。⚠️ 那些**全部是每次連線後的第一筆**（15/15），根因是背景模型還沒建好而不是照明——**只做照明否決擋不掉**，必須另外丟掉連線後的暖機期 |
| ④ 開運算 | 侵蝕再膨脹：孤立雜訊點消失、大區塊保留 |
| ⑤ ROI | 排除床以外的動作，並提供**可跨房間通用的分母** |
| ⑥ 連通域 + 取最大一塊 | 散開的雜訊最大一塊只有幾 px，`fraction` ≈ 0，自動被判掉 |

**最關鍵的改變是⑥「取最大一塊的面積」而不是「所有白點總數」。**

---

### ROI 怎麼定（每個人擺放位置不一樣）

這件事正好指出為什麼現在的門檻不可能通用：相機離床近，身體佔畫面 40%；
離得遠佔 5%。所以 `MOTION_LARGE = 350000` 這種**絕對像素數**換一個房間
就失去意義。有了 ROI，門檻才能寫成「動了床面積的 15%」，遠近都一樣。

| 方案 | 做法 | 評價 |
|---|---|---|
| A 手動 | `cv2.selectROI()` 讓使用者拖一個框，存進 config | ✅ 約 10 行，零風險。❌ 多一個設定步驟，相機被撞到要重框 |
| **B 自動**（建議） | 錄一段時間，把**開運算後**的前景遮罩累加成熱區圖，取最大的連通區塊的外接矩形 | ✅ 使用者零操作、可定期自動重校準、順便得到 ROI 面積。⚠️ 一定要先開運算，否則雜訊均勻散布、熱區圖是平的 |
| C 人物偵測 | 跑人物偵測模型取聯集 | ❌ 不建議：多一個模型相依，而且模型是用站著的人訓練的，對「蓋棉被躺著的人」在紅外線畫面下不可靠 |

**建議 B 當主力、A 當備援**——自動校準的結果顯示給使用者確認，不對再自己框。

⚠️ 方案 B 有個要防的情況：窗簾整晚在晃可能被選成床。
用「取**最大的連通區塊**」而不是「取最亮的點」可以擋掉大部分，
再加一條「這塊必須佔畫面 10%~60%」的合理性檢查。

⚠️ **但 ROI 是第三優先，不是第一。** 前兩項不需要知道床在哪就能做，
而且能解掉九成問題——那 7386 個 micro_motion 幾乎全部會在連通域那一步
就被判掉：

| 順序 | 做什麼 | 為什麼可以先做 |
|---|---|---|
| **1** | 連通域分析取代 `countNonZero` | 不需要知道床在哪 |
| **2** | 開運算 | 同上，也是方案 B 的前置 |
| **3** | ROI | 解「換一個房間還能不能用」 |

---

### 真正決定事件數的：一次動作 = 一段，不是一幀

現在是**每 3 幀連續動作就記一筆**，所以一晚 7428 筆。要改成 episode：

```python
# ── 事件 = 一段動作（episode）─────────────────────────────
if moving:
    quiet_run = 0
    if not in_episode:
        motion_run += 1
        if motion_run >= START_FRAMES:           # 連續 N 幀才算開始
            in_episode, ep_start, ep_peak = True, now, fraction
    else:
        ep_peak = max(ep_peak, fraction)
else:
    motion_run = 0
    if in_episode:
        quiet_run += 1
        if quiet_run >= END_FRAMES:              # 連續 M 幀安靜才算結束
            episodes.append({
                "start":         ep_start,
                "end":           now,
                "duration_s":    (now - ep_start).total_seconds(),
                "peak_fraction": round(ep_peak, 4),   # ← 存連續值
            })
            in_episode = False
```

這一改，7428 筆會變成大約**二三十筆**——而那正是文獻在數的東西
（Montini 數的是「動作」，有起訖、有持續時間，中位數 4 秒）。

**同樣重要：存連續值，不要只存分類。**
現在存的是 `motion_level: "micro_motion"`，分類寫死之後改門檻就得重錄。
改存 `peak_fraction: 0.18` 與 `duration_s: 4.2`，分類隨時可以重算，
**而且不同門檻之間仍然可以互相比較**——這直接解掉 #1 的根因。

---

### 起始參數（一定要校準，不是抄了就用）

| 參數 | 建議起點 | 理由 |
|---|---|---|
| 解析度 | 640×360 | 偵測不需要 1080p，縮圖順便降噪 |
| 處理幀率 | 5 fps | 動作中位數 4 秒 → 20 幀，綽綽有餘 |
| `ILLUM_JUMP` | 平均亮度變化 3–5 階 | 看實際錄影的亮度曲線抓 |
| `KERNEL` | 5×5 橢圓（在 360p 下） | 剛好吃掉單點雜訊 |
| `MIN_BLOB_FRACTION` | ROI 的 5% | 起點，一定要用影片驗 |
| `START_FRAMES` | 3（≈0.6 秒） | 濾掉瞬間閃動 |
| `END_FRAMES` | 15（≈3 秒） | 同一次翻身不會被切成兩段 |
| `LEARNING_RATE` | **明確指定**，不要用預設 `-1` | 預設是 `1/history`，不寫出來沒人知道背景多久會忘記 |

---

### ⚠️ 一個要分清楚的觀念：偵測門檻 ≠ 計分門檻

這兩種門檻的正當性來源**完全不同**，本專案的「每一項計分都必須有文獻門檻」
只管後者：

| | 偵測門檻 | 計分門檻 |
|---|---|---|
| 例子 | `MIN_BLOB_FRACTION`、`START_FRAMES` | 「一小時動幾次算睡不好」 |
| 怎麼定 | **拿影片人工標註當標準答案，調到抓得準為止** | 必須有文獻 |
| 受紅線約束 | ❌ 不受 | ✅ 受 |

→ **你們可以放手調偵測參數**，不會違反專案規矩；不能自己發明的是
「幾次算差」那一類。

**校準方法**：你們已經有存影片。挑 2–3 晚，找人把影片拉一遍、
逐一標出「這裡動了」，拿這份標註當標準答案去對。
n=2 晚就足以抓出 76 倍這種等級的錯誤。

---

### 驗收條件

1. **movement index 落在 8–15 次/小時**（Montini 2024 的 IQR）——正常的一晚應該落進去
2. **large_turn 約 3–4 次/小時**（De Koninck 1992，18–24 歲）
3. **與 Garmin 的 `awake_count` / WASO 有中等以上相關**——這是唯一能證明
   「攝影機真的量到睡眠」的內部效標
4. 每一筆紀錄都帶著 **ROI 座標、ROI 面積、全部門檻、偵測器版本、
   錄影窗格、解析度與幀率**（就是 #1）

前兩條沒過 = 偵測器還沒好；第三條沒過 = 攝影機只能當呈現用，不進計分。

---

## 我們這一端已經做的事（供對照，不需要你們動）

- `tapo_index.py` —— 攝影機資料的單一事實來源。
  **日期與時刻一律取自 `video_clip` 檔名**，不用 `report_date` 也不用 `time` 欄位
  （兩者都已有壞掉的實例）。每個欄位附 provenance 標籤。
- `sleep_quality_score` 已標成 `NOT_MEASUREMENT_GRADE`，
  `snore_count` / `decibel` 標成 `SIMULATED`，
  **事件時刻是唯一標成 `MEASURED` 的量**。
- `inspect_tapo_score.py` —— 這份清單的每一個數字都從這支跑出來。
  你們送新 dump 之後直接重跑，不要照抄上面的數字。
- **`SLEEP_START` 已從 `01:00` 改成 `22:00`**（2026-09-04）。
  這不是省硬碟的設定：人已經睡著之後才開機的夜晚，上床時刻在結構上就錄不到，
  演算法再好也救不回來。用 57 個有入睡時刻的 Garmin 夜晚實測
  （`SLEEP_END` 固定 08:00）：

  | `SLEEP_START` | 涵蓋到入睡 | 錄不到 | 代價 |
  |---|---|---|---|
  | 01:00（舊值） | 50 | **7 晚（12%）** | — |
  | 00:00 | 52 | 5 晚（9%） | +1h |
  | 23:00 | 54 | 3 晚（5%） | +2h |
  | **22:00（新值）** | **57** | **0 晚（0%）** | **+3h** |
  | 21:00 / 20:00 | 57 | 0 晚 | +4h / +5h（沒有額外好處） |

  22:00 是轉折點，再往前不會多涵蓋任何一晚。
  ⚠️ 我們改的是 `.env`、`.env.example` 與程式預設值三處。
  **如果你們機器上的 `.env` 是各自維護的，記得同步改**——`.env` 會蓋過預設值。

---

## 修好之後我們打算怎麼用

**不做「攝影機分數 × 0.4 + 手錶分數 × 0.6」這種加權平均。**
理由是那要 justify 60/40 這組權重，而且是拿有文獻依據的分數去平均沒有依據的分數。

攝影機真正不可取代的價值是**它量得到「上床時刻」，而手錶量不到**
（手錶只知道你什麼時候「睡著」）。有了上床時刻就有臥床時間，
臥床時間解掉睡眠效率的分母問題、並解鎖入睡潛伏期——這條路一個新參數都不用訂。

而如果之後真的要讓攝影機參與計分，我們這邊的規矩是：
**先寫 `Research-Background/攝影機分數.md`，每一個門檻都要指得到一篇文獻**，
文件沒寫好之前不寫公式。這是本專案對所有評分項的一致要求，不是針對攝影機。

---

## 參考文獻（本文引用的兩條常模）

- Montini A, Loddo G, Zenesini C, Mainieri G, Baldelli L, Mignani F, Mondini S,
  Provini F. Physiological movements during sleep in healthy adults across all ages:
  a video-polysomnographic analysis of non-codified movements reveals sex differences
  and distinct motor patterns. *Sleep*. 2024;47(9):zsae138. doi:10.1093/sleep/zsae138
- De Koninck J, Lorrain D, Gagnon P. Sleep positions and position shifts in five age
  groups: an ontogenetic picture. *Sleep*. 1992;15(2):143-149.
