# 起床動畫 GIF：怎麼做出來的、怎麼重做

`app/assets/pets/dog01/wake_up.gif`，滑完 Slide to get up 之後播一次（`screens/wake_up_screen.dart`）。
沒有這個檔時 App 退回程式畫的版本，不會報錯。

## 現在這一支（2026-11-13）

| 項目 | 值 |
|---|---|
| 來源 | Kling 4.0 圖生影片（免費版，720×1280、24 fps、5 秒，右下角有「KlingAI 4.0」浮水印） |
| 第一格 | `bedroom.png` 切 9:16（從 y=150 起）＋ `sleeping.png` 寬 62% 放在地毯中間，輸出 1080×1920 |
| 成品 | 0–4.2 秒、加速 1.25 倍、**裁掉底部 8%（浮水印在那裡，那一塊只有地板）**、480 寬、12 fps、播一次 |
| 結果 | 3.33 秒、40 格、480×784、2.7 MB |

同一天也試了 Dreamina（10 秒）：窗外變粉紅了月亮還掛著、左上角多一個「AI」標籤，沒採用。

## 給影片工具的 prompt

```
The orange Shiba Inu puppy sleeping on the round cushion slowly wakes up. It opens its eyes sleepily, gives a big yawn, stretches its front paws forward, then sits up on the cushion and looks around calmly with a soft, sleepy expression. At the same time, the night sky outside the window gently brightens into a soft pink and orange morning. The camera stays still. Keep the same cute 2D illustration style, colors and character design as the first frame. Gentle, slow, cozy movement.
```

Negative prompt：

```
confetti, coins, sparkles, text, letters, jumping, big smile, laughing, extra legs, extra tails, deformed face, changing character design, camera movement, zoom, realistic, 3D
```

⚠️ **不准慶祝**（彩帶、金幣、大笑、跳起來、文字）：這段每天早上都播，那時分數多半還沒到，
慶祝＝每晚都誇（紅線 5）；而且它排在起床自評之前，會把自評帶偏。
「Good morning」與起床時間由 App 疊上去，GIF 裡不要有字。

## 轉檔指令（ffmpeg）

```bash
F="trim=0:4.2,setpts=(PTS-STARTPTS)/1.25,crop=720:1176:0:0,fps=12,scale=480:-1:flags=lanczos"
ffmpeg -y -i kling.mp4 -vf "$F,palettegen=stats_mode=diff" pal.png
ffmpeg -y -i kling.mp4 -i pal.png \
  -lavfi "$F[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
  -loop -1 wake_up.gif
```

- `crop=720:1176:0:0`：只留上面 92%，去掉浮水印。換工具時先看浮水印在哪裡再改。
- `-loop -1`：只播一次。App 用 GIF 本身的長度決定什麼時候進自評卡（夾在 1–6 秒）。
- 目標 3 MB 以內；15 fps、540 寬那一版是 3.9 MB。

## 換掉之後要檢查

1. `flutter test test/morning_report_test.dart`——有一條拿真的檔案算長度（目前寫死 3.30–3.36 秒，換檔要改）。
2. 上實機錄一次（`adb shell screenrecord`），確認滑起床到自評卡之間**一格都沒露出首頁**。
