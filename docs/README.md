# docs/

專案文件。**這裡只放給人讀的東西，程式不讀這個目錄**（`images/` 除外，見下）。

| 檔案 | 是什麼 | 什麼時候看 |
|---|---|---|
| [`PROJECT_STATUS.md`](PROJECT_STATUS.md) | 整體現況盤點、待決策事項、設計紅線的完整證據 | 想知道某個模組現在到底能不能用 |
| [`DEVLOG.md`](DEVLOG.md) | 逐輪的過程紀錄，含「當初為什麼這樣決定」的推理 | 想知道某個決定的來龍去脈 |
| [`TAPO_HANDOFF.md`](TAPO_HANDOFF.md) | 交給影像組的問題清單 + 偵測層規格 | 跟影像組對接時 |
| [`REPORT_CAVEATS.md`](REPORT_CAVEATS.md) | 報告怎麼寫才誠實（哪些話不能寫、要怎麼改寫） | **寫報告前必讀** |
| [`PROPOSAL_GAP.md`](PROPOSAL_GAP.md) | 企劃書承諾 vs 實際做出來的落差 | 對照企劃書時 |
| `images/` | `itegration/if_integrate.py` 的圖表輸出 | — |

⚠️ **[`../CLAUDE.md`](../CLAUDE.md) 與 [`../README.md`](../README.md) 刻意留在根目錄**：
前者 Claude Code 只讀根目錄那一份，後者是 GitHub 進來第一眼看到的頁面。搬進來會壞掉。

⚠️ 程式註解裡大量引用 `PROJECT_STATUS.md` 的**節號**（如「PROJECT_STATUS.md 3.9」），
那些寫的是檔名不是路徑，所以這次搬動沒有影響——但**改節號會讓它們全部失準**。
