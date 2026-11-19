"""
behavior/lights_out_resolve.py — 用手錶當裁判，從候選安靜期挑出正確的就寢時刻

═══════════════════════════════════════════════════════════════════
這支在修什麼
═══════════════════════════════════════════════════════════════════
手機端的規則是「挑**最長**的那一段安靜期」（`app/lib/services/lights_out.dart`）。
半夜起來用幾分鐘手機，會把一晚切成兩段，而後面那段通常比較長：

    11-16 實例（手錶認定入睡 00:56、攝影機 00:43 開錄）

        00:49:54 → 02:18:19   88.4 分   ← 真正的就寢時刻
        02:23:37 → 06:02:25  218.8 分   ← 現行規則挑到這段，記成熬夜 98.6 分鐘

**放下手機不可能發生在睡著之後 87 分鐘。** 但手機身上沒有裁判——
手錶認定的入睡時刻只有後端拿得到。所以手機把**所有**候選一起送上來
（`quiet_candidates`），由這支函式刷掉不可能的那些。

清點過的範圍：44 個同時有兩種訊號的夜晚裡，**17 晚**的 `lights_out_at`
晚於手錶入睡，其中 6 晚差 ≥ 60 分鐘，**全部被記成熬夜**——偏差方向
一律是「多報熬夜」。

═══════════════════════════════════════════════════════════════════
⚠️ 門檻 TOLERANCE_MINUTES = 30 是設計決策，沒有文獻
═══════════════════════════════════════════════════════════════════
同 `kMinQuietMinutes`（3 小時）與 `kBriefUnlockSeconds`（30 秒）：
它屬**偵測層**，不進任何分數，所以不受紅線 2（每項計分都要有文獻）約束。
見 `TAPO_HANDOFF.md`：**偵測門檻 ≠ 計分門檻**。

取 30 分鐘而不是 0 的理由是**要放過另一個已知的、不同的現象**：
**滑手機滑到睡著**時手機要等螢幕逾時才自動上鎖，`lights_out_at` 因此
落在入睡之後十幾到幾十分鐘（實測 09-08 +55.9、09-11 +12、11-08 +9.1）。
那個現象使用者 2026-10-22 已決定改用 `USER_INTERACTION` 事件解，
**不該被這條規則順手改掉**——兩件事的修法不同，混在一起就都查不清楚。

═══════════════════════════════════════════════════════════════════
⚠️ 四條規則（改之前逐條確認）
═══════════════════════════════════════════════════════════════════
| 規則 | 不遵守的後果 |
|---|---|
| **沒有手錶資料就什麼都不做** | 沒有裁判還硬挑，等於換一套沒有依據的規則，可能把本來對的弄壞 |
| **沒有候選（舊版 App）就什麼都不做** | 把「不知道」當成「沒有別的候選」，會錯誤地判成 unresolved |
| **挑中的候選落在別的夜晚就不換** | 夜晚的日期由 `night_date(lights_out_at)` 決定，而上床按鈕是靠日期配對的 |
| **一段都沒過關 → `unresolved`，達成度存 NULL** | 繼續顯示「熬夜 461 分鐘」是假話；說「不知道」才是誠實的 |

⚠️ **可以重複執行**：每次都從 `quiet_candidates` 重挑，不是在上次改過的值上
再改一次。所以 `lights_out_pick` 存的是「誰挑的」而不是「有沒有改過」。
"""

from datetime import datetime, timedelta

from behavior.adherence import night_date

# 候選的起點最多可以比手錶認定的入睡晚幾分鐘（見檔頭）。
TOLERANCE_MINUTES = 30

# lights_out_pick 的三種值。
PICK_PHONE = "phone"           # 照手機挑的那一個（沒有裁判、或手機已經挑對了）
PICK_WATCH = "watch"           # 用手錶刷掉之後換成另一段
PICK_UNRESOLVED = "unresolved"  # 有手錶、有候選，但沒有一段過得了關


def _parse(value):
    """ISO8601 字串或 datetime → datetime。空值回 None。

    ⚠️ 一律當**牆鐘**讀，不換算 UTC。手錶的時刻帶 `+08:00`、手機送上來的
    不帶，兩邊直接相減就差 8 小時（同 `parseWallClock` 當初修的那個 bug）。
    """
    if value is None or value == "":
        return None
    if isinstance(value, datetime):
        return value.replace(tzinfo=None)
    try:
        return datetime.fromisoformat(str(value)).replace(tzinfo=None)
    except ValueError:
        return None


def decide(lights_out_at, quiet_candidates, sleep_start_time,
           tolerance_minutes=TOLERANCE_MINUTES):
    """
    這一晚的就寢時刻該存什麼。**純函式，沒有 I/O。** 這是唯一的判準入口。

    lights_out_at：資料庫現在存的那個時刻（手機挑的）。
    quiet_candidates：`POST /nightly` 收到的候選清單；**None 或空＝舊版 App**。
    sleep_start_time：手錶認定的入睡時刻；None＝那一晚沒戴錶。

    回傳 (要存的 lights_out_at, pick)。pick 是 PICK_UNRESOLVED 時，
    呼叫端要把 `adherence_minutes` 與 `is_late` 存成 **NULL**——
    `lights_out_at` 本身留著（它仍然是「最後一次碰手機」這個量測事實），
    說不出口的是「所以你熬夜了幾分鐘」那句話。

    ⚠️ **有候選與沒候選走兩條不同的路**，不要合併：

    | 情況 | 做什麼 |
    |---|---|
    | 有手錶、有候選 | 刷掉不可能的，挑最晚的那一段（可能換成別的時刻） |
    | 有手錶、**沒有候選**（舊版 App、歷史夜晚） | **只檢查、修不了**——手機挑過的那一段已經丟了。晚於入睡太多就標 unresolved |
    | 沒有手錶 | 什麼都不做 |

    第二條存在的理由：那 6 晚（09-12、09-20、09-24、09-27、10-02、11-16）
    的候選早就不存在了（Android 只保留約 24 小時的事件），救不回來，
    但「熬夜 461 分鐘」是假話，說「不知道」才是誠實的。
    """
    current = _parse(lights_out_at)
    onset = _parse(sleep_start_time)

    if onset is None or current is None:
        return lights_out_at, PICK_PHONE

    cutoff = onset + timedelta(minutes=tolerance_minutes)

    if not quiet_candidates:
        # 沒有候選：只檢查，修不了。
        if current > cutoff:
            return lights_out_at, PICK_UNRESOLVED
        return lights_out_at, PICK_PHONE

    passed = []
    for c in quiet_candidates:
        at = _parse(c.get("at"))
        if at is not None and at <= cutoff:
            passed.append(at)

    if not passed:
        return lights_out_at, PICK_UNRESOLVED

    # 挑**最晚**的那一段：就寢時刻是「睡前最後一次使用」，不是最早那一次。
    at = max(passed)

    if at == current:
        return lights_out_at, PICK_PHONE

    # 換了之後落在別的夜晚就不換（上床按鈕是靠日期配對的）。
    if night_date(at) != night_date(current):
        return lights_out_at, PICK_PHONE

    return at.isoformat(), PICK_WATCH
