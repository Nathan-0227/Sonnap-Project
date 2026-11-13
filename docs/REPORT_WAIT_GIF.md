# 等待畫面 GIF：小狗翻夢境日記

`app/assets/pets/dog01/report_wait.gif`，起床流程裡自評卡之後、報告之前那個等待畫面（`screens/report_loading_screen.dart`），
鋪滿畫面、無限循環。系統開「減少動態效果」時改用同一場景的靜止圖 `report_wait_still.jpg`（GIF 的第一格）。
兩個都讀不到時退回星空＋首頁那隻小狗，不會報錯。

## 現在這一支（2026-11-13）

| 項目 | 值 |
|---|---|
| 場景 | 接著起床動畫最後那個房間：早晨的臥室、窗外日出、小狗坐在紫色墊子上 |
| 第一格 | 起床動畫（Kling）最後一格 → 用圖片工具改成「小狗低頭看一本攤開的書」。書頁**只有星星月亮塗鴉、沒有字** |
| 影片 | Kling 圖生影片（免費額度），首尾設成同一張圖，8 秒、1080×1920、24 fps，沒有浮水印 |
| 成品 | 整段 8 秒、432 寬、10 fps、無限循環，3.7 MB。首尾兩格平均只差 2.7／255，接縫看不出來 |

## 給影片工具的 prompt

```
The orange Shiba Inu puppy sits on the cushion and calmly reads the small open book in front of it. Its eyes move slowly across the page, it blinks, its ears twitch softly, its curly tail sways gently, and its paw lifts the corner of a page slightly and then lets it settle back flat, returning to the exact same pose as the first frame. Its expression stays calm and curious, not excited. Warm sunrise light glows through the window and the curtain moves very slightly. The camera stays completely still. Keep the same 2D illustration style, colors and character design. Slow, subtle, looping idle animation.
```

Negative prompt：

```
text, words, letters, numbers, writing on the pages, turning many pages, flipping pages quickly, closing the book, confetti, sparkles, jumping, running, big smile, laughing, crying, sad face, sleeping, extra legs, extra paws, extra tails, deformed face, changing character design, camera movement, zoom, background change, realistic, 3D
```

- **不翻頁**：只掀起頁角再放下。真的翻頁的話最後一格跟第一格不一樣，循環每一圈都會跳一下。
- **不准慶祝、不准大笑**：這個畫面每天早上都出現、分數多半還沒到（紅線 5）。
- **書上不准有字**：AI 畫的字是亂碼。
- 免費額度不夠時：改 5 秒、換舊一點的模型、不設尾格（尾格可以在轉檔時用「正放接倒放」補）。

## 轉檔指令（ffmpeg）

```bash
F="fps=10,scale=432:-1:flags=lanczos"
ffmpeg -y -i book.mp4 -vf "$F,palettegen=stats_mode=diff" pal.png
ffmpeg -y -i book.mp4 -i pal.png \
  -lavfi "$F[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
  -loop 0 report_wait.gif
```

- `-loop 0`：無限循環（起床動畫是 `-loop -1` 只播一次，兩個相反）。
- 480 寬 10 fps 是 4.5 MB、432 寬 8 fps 是 3.3 MB；目標 4 MB 以內（測試守著）。
- 沒有尾格的影片要自己接成循環：`-filter_complex "[0]reverse[r];[0][r]concat=n=2:v=1"`（正放接倒放）。

## 換掉之後要檢查

1. `flutter test test/morning_report_test.dart --plain-name 等待畫面`。
2. 上實機看一次：字與按鈕壓在下面的地板上，小狗不被擋住。
