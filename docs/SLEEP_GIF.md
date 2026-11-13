# 睡覺畫面的 GIF：趴下睡著的過場＋睡覺的循環

按了 Start Sleep 之後的睡覺畫面（`screens/sleep_mode_screen.dart`）：

| 檔案 | 用在哪 | 規格 |
|---|---|---|
| `app/assets/pets/dog01/go_to_sleep.gif` | **剛按 Start Sleep 時播一次**：小狗坐著 → 趴下 → 小月亮飛來變成小毯子 | 4.0 秒、48 格、432×768、12 fps、播一次，3.4 MB |
| `app/assets/pets/dog01/sleeping_loop.gif` | 過場之後一直播：小狗睡覺、呼吸、耳朵動一下 | 8 秒、400 寬、8 fps、96 色、無限循環，3.1 MB |
| `app/assets/pets/dog01/sleeping_still.jpg` | 系統開「減少動態效果」時代替循環 | 兩支影片共同的第一格，1080×1920 |

- 半夜重開 App 回到睡覺畫面：**不播過場**，直接是循環。
- 過場播的時候畫面上不疊東西（大時間、鬧鐘、聲音、Slide to get up 都藏著、點不到），**點一下跳過**，播完控制項淡入。
- 循環檔讀不到時退回 `bedroom.png`＋程式放的睡覺小狗，不會報錯。
- 過場的最後一格＝循環的第一格（同一張圖），所以接起來看不出來。

## 共同的第一格

App 現有的兩張圖合成，跟起床 GIF 的第一格同一個做法：

```bash
ffmpeg -y -i app/assets/backgrounds/bedroom.png -i app/assets/pets/dog01/sleeping.png \
  -filter_complex "[0]crop=863:1534:0:150,scale=1080:1920[bg];[1]scale=670:-1[d];[bg][d]overlay=(W-w)/2:820" \
  sleep_first_frame.png
```

（小狗寬 62%、墊子落在地毯中央。）

## 影片：Adobe Firefly 圖生影片（2026-11-14）

兩支都是 9:16、鏡頭固定、8 秒、24 fps、1080×1920，沒有浮水印。Firefly 沒有 Negative prompt 欄位，「不要什麼」寫在 prompt 裡。

### ① 過場：做「醒來坐起」，再**倒放**

AI 很會做「從睡著到醒來」，不會做「從醒著剛好躺成某個姿勢」。倒放之後最後一格一定是第一格那張圖，接得上循環。只設第一格。

```
The orange Shiba Inu puppy sleeping on the round cushion slowly lifts its head, opens its eyes sleepily, and calmly sits up on the cushion, looking around the quiet bedroom with a soft, drowsy expression. The night lamp keeps glowing softly and the moon and stars outside the window stay exactly the same; it remains night the whole time. The camera stays completely still. Keep the same cute flat 2D illustration style, colors and character design as the image. Slow, gentle, cozy movement. Do not yawn, do not stretch, do not stand up or walk, no text, no sparkles, no extra legs or tails, no daylight.
```

- **不准打哈欠、伸懶腰**：倒放之後哈欠會變成嘴巴往回吸。
- 這一次 Firefly 把小狗背上的小毯子變成小月亮飛走，倒放後變成「小月亮飛來蓋成毯子」——prompt 沒要求，使用者保留。前兩秒畫面下方有一顆小月亮飄著（之後是控制項的位置）。

### ② 循環：第一格與最後一格都設同一張圖

```
The orange Shiba Inu puppy sleeps peacefully curled up on the round cushion. Its body rises and falls slowly with each calm breath, one ear twitches softly once, and the tip of its tail moves very slightly, ending in exactly the same pose as the image. The stars outside the window twinkle gently and the curtain sways very slightly. The night lamp glows softly. The camera stays completely still. Keep the same flat 2D illustration style, colors and character design. Slow, subtle, looping sleep animation. The puppy never wakes up or opens its eyes, no text, no "zzz" letters, no sparkles, no daylight.
```

首尾兩格平均只差 1.7／255，接縫看不出來。沒辦法設尾格時：正放接倒放（`-filter_complex "[0]reverse[r];[0][r]concat=n=2:v=1"`）。

## 轉檔指令（ffmpeg）

```bash
# ① 過場：倒放、加速 2 倍（8 → 4 秒）、播一次
F="reverse,setpts=(PTS-STARTPTS)/2,fps=12,scale=432:-1:flags=lanczos"
ffmpeg -y -i intro.mp4 -vf "$F,palettegen=stats_mode=diff" pal.png
ffmpeg -y -i intro.mp4 -i pal.png \
  -lavfi "$F[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
  -loop -1 go_to_sleep.gif

# ② 循環：無限循環
F="fps=8,scale=400:-1:flags=lanczos"
ffmpeg -y -i loop.mp4 -vf "$F,palettegen=stats_mode=diff:max_colors=96" pal.png
ffmpeg -y -i loop.mp4 -i pal.png \
  -lavfi "$F[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
  -an -loop 0 sleeping_loop.gif
```

- 循環那支整個畫面都有飄浮的小光點，每一格都不一樣，檔案很容易變大：432 寬 10 fps 是 6.3 MB，降到 400 寬、8 fps、96 色才 3.1 MB。
- `-loop -1` 播一次（過場）、`-loop 0` 無限循環。目標各 4 MB 以內（`sleep_scene_test.dart` 守著）。

## 換掉之後要檢查

1. `flutter test test/sleep_scene_test.dart`：檔案大小、過場長度（寫死 3.8–4.2 秒，換檔要改）。
2. 上實機按一次 Start Sleep：過場播完接循環沒有跳一下；大時間、鬧鐘、Slide to get up 不蓋到小狗。
   ⚠️ 按了就真的記下上床、排了鬧鐘——只是試看，就按 Not sleeping? Cancel 並確認，今晚的開始會清掉。
