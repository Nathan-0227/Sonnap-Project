#!/usr/bin/env python3
"""從 happy_dog.json 衍生出 bored / tired / anxious 三個 Lottie 檔。

## 為什麼要有這支腳本

`assets/animations/` 底下原本只有 `happy_dog.json` 一個檔，所以不管當晚的
`pet_mood` 是什麼，畫面上都是一隻搖尾巴吐舌頭的狗——文字寫 Anxious、圖在
搖尾巴，同一張卡自相矛盾。缺的是美術資產，不是程式。

在等美術的期間，這支腳本直接改 Lottie 的 JSON 生出三個變體。**四種狀態是
同一隻狗**，這一點比「去網路上抓四隻不同的狗」重要得多——寵物養成 App 裡
心情一變就換一隻狗，產品邏輯本身就是壞的。

⚠️ **拿到真正的美術資產之後，直接覆蓋掉這三個檔就好**，程式端一行都不用改
（`pubspec.yaml` 是以目錄宣告資產的）。這支腳本也就可以刪了。

## 它憑什麼改得動

`happy_dog.json` 是 After Effects 匯出的，圖層有拆開而且有命名（西班牙文）：

    CABEZA 頭   OJO 1/2 眼   OREJA I/D 左右耳   LENGUA 舌頭
    CUERPO 身   COLA 尾巴    PATA×4 四隻腳      COLLAR 項圈   fFONDO 背景

表情相關的圖層剛好都是可以用參數改的東西——舌頭是靜態圖層（改 opacity 就
消失）、尾巴與耳朵是 rotation 關鍵影格（縮振幅就不搖了）、眼睛是靜態 scale
（壓 Y 軸就變瞇眼）。所以這不是套個灰階濾鏡，是真的改動作。

## 色彩：刻意與 Dart 端用同一組數學

`app/lib/widgets/pet_mood_animation.dart` 的 `_adjust()` 在**檔案不存在時**
會對 `happy_dog.json` 套一個色彩矩陣當退路。這支腳本用**完全相同**的公式
（BT.709 亮度權重）把顏色烤進 JSON 裡。

→ 於是「檔案在」與「檔案不在」兩條路徑看起來是一致的，不會因為資產到位
   反而換了一種色調。兩邊的參數必須一起改，`MOOD_SPECS` 的註解有標對應。

## 用法

    python app/tools/derive_pet_moods.py           # 產生三個檔
    python app/tools/derive_pet_moods.py --check   # 只檢查磁碟上的檔是否與腳本一致

`--check` 是給「有人手改了生成檔卻沒改腳本」這種情況用的——那種漂移不會有
任何錯誤訊息，只會讓下次重跑腳本默默蓋掉別人的修改。
"""

import argparse
import copy
import json
import sys
from pathlib import Path

# Windows 的 Git Bash 是 cp1252，印中文會 UnicodeEncodeError（見 CLAUDE.md）
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ANIM_DIR = Path(__file__).resolve().parent.parent / "assets" / "animations"
SOURCE = ANIM_DIR / "happy_dog.json"

# ITU-R BT.709 亮度權重。與 pet_mood_animation.dart 的 _adjust() 同一組。
# 用感知亮度而非單純平均，去飽和之後深淺關係才不會亂掉。
LUM_R, LUM_G, LUM_B = 0.213, 0.715, 0.072


class MoodSpec:
    """一種心情的所有調整參數。

    每個欄位都對應到「這個心情在生理上長什麼樣」，不是隨便調的數字：

    - `fr`         整支動畫的播放速率。累的時候動作慢，焦躁的時候動作快
    - `tail`       尾巴搖擺振幅的倍率。1.0 = 原樣，0.0 = 完全不動
    - `head`       頭部上下擺動的振幅倍率
    - `head_dy`    頭部整體下沉的像素數（正值 = 往下）。**這是最好認的一項**
    - `head_tilt`  頭部固定歪斜的角度
    - `head_shake` 頭部高頻小幅擺動的振幅（度）。0 = 不抖
    - `ears`       'hold' = 固定在垂耳那一格；數字 = 振幅倍率
    - `eye_y`      眼睛 Y 軸縮放。< 1 是瞇眼，> 1 是睜大
    - `tongue`     False = 把舌頭圖層藏起來（不再吐舌喘氣）

    ⚠️ **姿態比細節重要。** 第一版只改了尾巴振幅、耳朵、眼睛與顏色，渲染出來
    四隻狗在 200px 的卡片上幾乎分不出來——尾巴轉 15 度在那個尺寸下看不見。
    真正一眼認得出來的是「頭的位置」與「整體色調」，所以才加了 `head_dy` /
    `head_tilt` / `head_shake` 這三項。細節仍然留著，它們在近看時有加分。
    """

    def __init__(self, key, fr, saturation, brightness, tint,
                 tail, head, head_dy, head_tilt, head_shake,
                 ears, eye_y, tongue, note):
        self.key = key
        self.fr = fr
        self.saturation = saturation
        self.brightness = brightness
        self.tint = tint
        self.tail = tail
        self.head = head
        self.head_dy = head_dy
        self.head_tilt = head_tilt
        self.head_shake = head_shake
        self.ears = ears
        self.eye_y = eye_y
        self.tongue = tongue
        self.note = note


# ⚠️ saturation / brightness / tint 三欄**必須**與
#    app/lib/widgets/pet_mood_animation.dart 的 _moodVisuals 一致。
#    那邊是資產不存在時的退路濾鏡，這邊是烤進檔案裡的顏色——
#    兩邊不一致的話，資產到位前後會看起來像兩隻不同的狗。
#    tests/ 沒辦法跨語言檢查這件事，所以改任何一邊都要手動對過另一邊。
MOOD_SPECS = [
    MoodSpec(
        key="bored",
        fr=19,                      # 24 → 19，稍微慢一點
        saturation=0.70, brightness=0.95, tint=(0, 0, 0),
        tail=0.45,                  # 還會搖，但沒那麼起勁
        head=0.70,
        head_dy=20,                 # 頭稍微低一點
        head_tilt=-9,               # 歪頭——無趣、提不起勁，不是想睡
        head_shake=0,
        ears=0.50,
        eye_y=1.00,                 # 眼睛不變，無聊不是想睡
        tongue=False,
        note="Mildly disengaged: head cocked to one side, tongue in, "
             "and the tail only half-wagging.",
    ),
    MoodSpec(
        key="tired",
        fr=14,                      # 24 → 14，明顯變慢
        saturation=0.45, brightness=0.80, tint=(0, 0, 0),
        tail=0.15,                  # 幾乎不搖
        head=0.35,
        head_dy=58,                 # 頭明顯垂下去——這是四項裡最好認的
        head_tilt=7,
        head_shake=0,
        ears="hold",                # 固定在垂耳那一格
        eye_y=0.22,                 # 瞇成一條縫
        tongue=False,
        note="Low energy: slow playback, head hanging low, drooping ears, "
             "half-closed eyes, almost no tail movement.",
    ),
    MoodSpec(
        key="anxious",
        fr=30,                      # 24 → 30，動作變快變緊繃
        saturation=0.40, brightness=0.78, tint=(-6, 0, 18),   # 冷色偏
        tail=0.20,                  # 尾巴夾著不搖（焦慮不是沒力氣）
        head=0.50,
        head_dy=-8,                 # 頭抬高、警戒
        head_tilt=0,
        head_shake=2.6,             # 高頻小幅擺動——這一項把焦慮和累分開
        ears=0.25,                  # 耳朵繃住不擺
        eye_y=1.15,                 # 眼睛睜大
        tongue=False,
        note="Tense and alert: faster playback, head held high and trembling, "
             "wide eyes, pinned ears, a still tail, and a cool colour cast.",
    ),
]

# 圖層名稱前綴 → 用途。AE 匯出的名稱是西班牙文，這裡集中翻一次，
# 底下的程式就不用到處出現看不懂的字串。
LAYER_TONGUE = "LENGUA"
LAYER_TAIL = "COLA"
LAYER_HEAD = "CABEZA"
LAYER_EAR = "OREJA"
LAYER_EYE = "OJO"


# ── Lottie JSON 的低階操作 ────────────────────────────────────────────

def clamp01(v):
    return 0.0 if v < 0.0 else (1.0 if v > 1.0 else v)


def adjust_color(rgba, saturation, brightness, tint):
    """套用飽和度 + 亮度 + 色偏。

    這是 pet_mood_animation.dart `_adjust()` 那個 4x5 矩陣展開後的等價形式：

        R_out = [(lumR + s(1-lumR))·r + (lumG - s·lumG)·g + (lumB - s·lumB)·b] · b
              = [L + s·(r - L)] · brightness          其中 L 是感知亮度

    展開成這個形式只是好讀，算出來的值完全一樣。
    tint 在 Dart 那邊是 0-255 的偏移量，Lottie 的顏色是 0-1，所以要除 255。
    """
    r, g, b = rgba[0], rgba[1], rgba[2]
    lum = LUM_R * r + LUM_G * g + LUM_B * b
    out = []
    for i, c in enumerate((r, g, b)):
        v = (lum + saturation * (c - lum)) * brightness + tint[i] / 255.0
        out.append(round(clamp01(v), 6))
    return out + list(rgba[3:])


def is_rgba(k):
    return isinstance(k, list) and len(k) >= 3 and all(
        isinstance(x, (int, float)) for x in k
    )


def recolor(node, spec, tally=None):
    """遞迴走訪整棵 JSON，把每個填色改掉。

    ⚠️ 顏色有**兩種存法**，兩種都要處理：靜態的 `c.k` 直接是 `[r,g,b,a]`，
    但顏色本身也可以是動畫的（`c.a == 1`），那時 `c.k` 是一串關鍵影格、
    顏色藏在每一格的 `s` 裡。這個檔的 `CABEZA`（頭）上就有兩個動畫填色
    （臉頰的粉紅色會隨時間變化）。

    第一版漏掉了動畫的那兩個，結果是「整隻狗都去飽和了，只有臉頰還是鮮豔的
    粉紅色」——而且不會有任何錯誤訊息。改用別的來源檔時要重新確認一次。

    ⚠️ 這個檔實測沒有 `st`（stroke）也沒有漸層（`gf` / `gs`），所以沒有處理，
    但**新資產可能會有**，同樣是漏掉也不報錯的那類。
    """
    tally = tally if tally is not None else {"values": 0, "skipped": 0}
    if isinstance(node, dict):
        if node.get("ty") == "fl":
            c = node.get("c", {})
            k = c.get("k")
            if c.get("a") == 1 and isinstance(k, list):
                for kf in k:
                    if is_rgba(kf.get("s")):
                        kf["s"] = adjust_color(
                            kf["s"], spec.saturation, spec.brightness, spec.tint)
                        tally["values"] += 1
                    else:
                        tally["skipped"] += 1
            elif is_rgba(k):
                c["k"] = adjust_color(k, spec.saturation, spec.brightness, spec.tint)
                tally["values"] += 1
            else:
                # 這裡進得來就表示有一種沒預期到的顏色存法（漸層？參考式？）。
                # 靜靜跳過的話會留下一塊沒去飽和的原色，所以往上報。
                tally["skipped"] += 1
        for v in node.values():
            recolor(v, spec, tally)
    elif isinstance(node, list):
        for v in node:
            recolor(v, spec, tally)
    return tally


def scale_amplitude(prop, factor, ref_index=0):
    """把一個 animated 屬性的振幅往參考影格收斂。

    factor=1.0 原樣、0.0 完全靜止。參考影格預設取第一格，因為 AE 的循環
    動畫幾乎都是從靜止姿勢開始的——用它當基準，縮小振幅就會收斂回靜止姿勢，
    而不是收斂到某個中間的怪姿勢。
    """
    if not isinstance(prop, dict) or prop.get("a") != 1:
        return False
    kfs = prop.get("k")
    if not isinstance(kfs, list) or not kfs:
        return False
    ref = kfs[ref_index].get("s")
    if ref is None:
        return False
    for kf in kfs:
        s = kf.get("s")
        if s is None:
            continue
        kf["s"] = [
            round(ref[i] + (v - ref[i]) * factor, 4) if i < len(ref) else v
            for i, v in enumerate(s)
        ]
    return True


def hold_pose(prop, kf_index=1):
    """把一個 animated 屬性凍結在某一格的姿勢上。

    預設取第 1 格（0-based）——三格式的循環動畫是「靜止 → 極值 → 靜止」，
    中間那格就是美術畫的極值姿勢。凍在那裡等於「一直維持垂耳」，
    而且因為那是美術自己畫的姿勢，不會出現亂轉的角度。
    """
    if not isinstance(prop, dict) or prop.get("a") != 1:
        return False
    kfs = prop.get("k")
    if not isinstance(kfs, list) or len(kfs) <= kf_index:
        return False
    val = kfs[kf_index].get("s")
    if val is None:
        return False
    prop["a"] = 0
    # bodymovin 的靜態值：純量屬性（rotation）存數字，向量屬性（position）存陣列
    prop["k"] = val[0] if len(val) == 1 else list(val)
    return True


def scale_static_axis(prop, index, factor):
    """縮放一個靜態向量屬性的某一軸（眼睛的 scale Y 用這個）。"""
    if not isinstance(prop, dict) or prop.get("a") != 0:
        return False
    k = prop.get("k")
    if not isinstance(k, list) or index >= len(k):
        return False
    k[index] = round(k[index] * factor, 4)
    return True


def set_static(prop, value):
    """把一個屬性硬設成某個靜態值（藏舌頭用的 opacity）。"""
    if not isinstance(prop, dict):
        return False
    prop["a"] = 0
    prop["k"] = value
    return True


def offset_vector(prop, delta):
    """給一個向量屬性的每一格加上固定偏移量（頭往下沉用這個）。

    加在**每一格**而不是只加在靜止那格，動作的振幅才不會被改到——
    只是整條曲線平移下去。振幅另外由 `scale_amplitude` 管。
    """
    if not isinstance(prop, dict):
        return False
    if prop.get("a") == 1:
        for kf in prop.get("k", []):
            s = kf.get("s")
            if s is None:
                continue
            kf["s"] = [round(v + (delta[i] if i < len(delta) else 0), 4)
                       for i, v in enumerate(s)]
        return True
    k = prop.get("k")
    if isinstance(k, list):
        prop["k"] = [round(v + (delta[i] if i < len(delta) else 0), 4)
                     for i, v in enumerate(k)]
        return True
    return False


def oscillate(prop, amplitude, period, end_frame):
    """把一個屬性換成高頻小幅的來回擺動（焦慮的發抖用這個）。

    做法是硬生出一串關鍵影格，每半個週期換一次正負號。緩動用 bodymovin
    預設那組（i.x=0.667 / o.x=0.333），跟這個檔原本的關鍵影格一致，
    所以擺動的手感不會跟其他圖層打架。

    ⚠️ `end_frame` 要蓋滿 precomp 的**內部**長度（這個檔是 96 格），
    不是主時間軸的 192——主時間軸是同一份 precomp 播兩次
    （ind=2 走 0~96、ind=1 走 96~192 但 st=96，內部一樣是 0~96）。
    寫成 192 的話後半段沒有影格，會停在最後一個值不動。
    """
    if not isinstance(prop, dict) or amplitude <= 0:
        return False
    ease_in = {"x": [0.667], "y": [1]}
    ease_out = {"x": [0.333], "y": [0]}
    kfs = []
    t = 0
    sign = 1
    half = max(1, period // 2)
    while t < end_frame:
        kfs.append({"i": ease_in, "o": ease_out, "t": t,
                    "s": [round(amplitude * sign, 4)]})
        sign = -sign
        t += half
    kfs.append({"t": end_frame, "s": [round(amplitude * sign, 4)]})
    prop["a"] = 1
    prop["k"] = kfs
    return True


# ── 組裝 ──────────────────────────────────────────────────────────────

def iter_layers(doc):
    """走訪主時間軸與所有 precomp 裡的圖層。

    這個檔的主時間軸只有兩個 precomp 圖層（同一份 comp_0 播兩次），
    真正的角色圖層全在 assets[0] 裡面。不走 assets 的話什麼都改不到。
    """
    for layer in doc.get("layers", []):
        yield layer
    for asset in doc.get("assets", []):
        for layer in asset.get("layers", []):
            yield layer


def derive(source, spec):
    doc = copy.deepcopy(source)
    doc["fr"] = spec.fr
    doc["nm"] = "%s_dog" % spec.key
    doc["meta"] = {
        "g": "derive_pet_moods.py",
        "a": "",
        "k": spec.key,
        "d": "Derived from happy_dog.json. %s" % spec.note,
        "tc": "",
    }

    touched = {"tongue": 0, "tail": 0, "head": 0, "ears": 0, "eyes": 0}

    for layer in iter_layers(doc):
        nm = layer.get("nm", "")
        ks = layer.get("ks", {})

        if nm.startswith(LAYER_TONGUE) and not spec.tongue:
            if set_static(ks.get("o"), 0):
                touched["tongue"] += 1

        elif nm.startswith(LAYER_TAIL):
            if scale_amplitude(ks.get("r"), spec.tail):
                touched["tail"] += 1

        elif nm.startswith(LAYER_HEAD):
            # 順序有意義：先縮振幅（相對於原本的靜止姿勢），再整條平移下去。
            # 反過來做的話 scale_amplitude 會拿平移後的第一格當基準，
            # 結果一樣，但讀起來會讓人以為偏移量被縮放過了。
            ok = scale_amplitude(ks.get("p"), spec.head)
            if spec.head_dy:
                ok = offset_vector(ks.get("p"), (0, spec.head_dy)) and ok
            if spec.head_shake:
                # 96 = precomp 的內部長度，見 oscillate() 的說明
                ok = oscillate(ks.get("r"), spec.head_shake, 8, 96) and ok
            elif spec.head_tilt:
                ok = set_static(ks.get("r"), spec.head_tilt) and ok
            if ok:
                touched["head"] += 1

        elif nm.startswith(LAYER_EAR):
            # 耳朵同時有 rotation 與 position 動畫，兩個要一起處理，
            # 否則會出現「耳朵在飄但角度不動」這種脫節的畫面
            if spec.ears == "hold":
                ok = hold_pose(ks.get("r")) and hold_pose(ks.get("p"))
            else:
                ok = scale_amplitude(ks.get("r"), spec.ears)
                ok = scale_amplitude(ks.get("p"), spec.ears) and ok
            if ok:
                touched["ears"] += 1

        elif nm.startswith(LAYER_EYE):
            if spec.eye_y != 1.0 and scale_static_axis(ks.get("s"), 1, spec.eye_y):
                touched["eyes"] += 1

    tally = recolor(doc, spec)
    touched["fills"] = tally["values"]
    touched["skipped_fills"] = tally["skipped"]
    return doc, touched


def dump(doc):
    # separators 去掉多餘空白：這個檔會進版控，每次重跑產生的 diff 要是穩定的
    return json.dumps(doc, ensure_ascii=False, separators=(",", ":"), sort_keys=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify the files on disk match what this script would generate",
    )
    args = parser.parse_args()

    if not SOURCE.exists():
        print("ERROR: source not found: %s" % SOURCE)
        return 1

    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    print("Source: %s  (%d fps, %d layers, %d precomp layers)" % (
        SOURCE.name, source.get("fr"), len(source.get("layers", [])),
        sum(len(a.get("layers", [])) for a in source.get("assets", [])),
    ))

    failures = 0
    for spec in MOOD_SPECS:
        doc, touched = derive(source, spec)
        text = dump(doc)
        target = ANIM_DIR / ("%s_dog.json" % spec.key)

        # 每一項都必須真的改到東西。改不到不會報錯，只會生出一個
        # 跟 happy 一模一樣的檔——那正是這支腳本要解決的問題本身。
        expected = {"tongue": 1, "tail": 1, "head": 1, "ears": 2}
        if spec.eye_y != 1.0:
            expected["eyes"] = 2
        missing = [k for k, n in expected.items() if touched.get(k, 0) < n]
        if missing or touched["fills"] == 0:
            print("  ERROR [%s] nothing changed for: %s" % (
                spec.key, ", ".join(missing) or "fills"))
            failures += 1
            continue
        if touched["skipped_fills"]:
            # 有填色是用沒預期到的方式存的，會留下一塊沒處理到的原色。
            # 這種缺陷在畫面上只是「某個小地方顏色怪怪的」，很容易被放過去。
            print("  ERROR [%s] %d fill(s) use an unrecognised colour format"
                  % (spec.key, touched["skipped_fills"]))
            failures += 1
            continue

        if args.check:
            if not target.exists():
                print("  MISSING  %s" % target.name)
                failures += 1
            elif target.read_text(encoding="utf-8") != text:
                print("  DRIFTED  %s (on-disk file differs from this script)"
                      % target.name)
                failures += 1
            else:
                print("  ok       %s" % target.name)
        else:
            target.write_text(text, encoding="utf-8")
            print("  wrote    %-18s %2d fps | tongue hidden | tail x%.2f | "
                  "ears %-4s | eyes x%.2f | %d colour values" % (
                      target.name, spec.fr, spec.tail, str(spec.ears),
                      spec.eye_y, touched["fills"]))

    if failures:
        print("\n%d problem(s)." % failures)
        return 1
    print("\nDone." if not args.check else "\nAll files match the script.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
