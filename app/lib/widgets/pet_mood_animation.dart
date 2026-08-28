import 'package:flutter/material.dart';

/// 寵物心情 → 動畫資產的對應。
///
/// ## 為什麼需要這一層
///
/// 在此之前 `home_screen.dart` 把動畫路徑寫死成 `happy_dog.json`，
/// 所以不管 `status.pet_mood` 是什麼，畫面上都是一隻開心的狗。
/// 最新一晚的心情是 `anxious`，旁邊的 PetMoodCard 文字也寫 Anxious，
/// **同一張卡上文字與圖自相矛盾**。
///
/// ## 兩段式資產策略
///
/// 目前 `assets/animations/` 底下只有 `happy_dog.json` 一個檔。
/// 這一層設計成兩段，所以「資產還沒到」與「資產到了」都不用改程式：
///
/// 1. **首選**：`assets/animations/{mood}_dog.json`。
///    檔案存在就照播，不套任何濾鏡——美術給什麼就是什麼。
/// 2. **退路**：檔案不存在時，`Lottie` 的 `errorBuilder` 會接手，
///    改播 `happy_dog.json` 但**套上該心情的濾鏡**（去飽和／冷色調）。
///
/// 退路的用意不是假裝有資產，是讓 demo 當天不要出現「文字說焦慮、
/// 圖在搖尾巴」這種自打嘴巴的畫面。降飽和度的狗讀起來是「無精打采」，
/// 這是設計上常用的手法，不是把 bug 藏起來。
///
/// ⚠️ **拿到真正的 Lottie 檔之後，把檔案丟進 `assets/animations/` 就好，
///    這個檔案一行都不用改**——`pubspec.yaml` 是以目錄宣告資產的
///    （`- assets/animations/`），新檔會自動被打包。
///
/// ## 合法的心情值
///
/// README 的 data contract 定義四個：happy / bored / tired / anxious。
/// 來源有兩處，語意不同但共用同一組標籤：
///
/// - Tier B（穿戴裝置）：`build_app_payload.py` 的 `QUALITY_TO_MOOD`，
///   由睡眠分級決定，另有 `anxious` 的生理覆寫
/// - Tier A（手機行為）：`behavior/pet_state.py`，**刻意不產生 anxious**
///   （那個標籤的語意是自律神經偏離 baseline，手機量不到）
class PetMoodVisual {
  /// 該心情專屬的動畫檔。可能還不存在——那是預期內的，見 errorBuilder。
  final String assetPath;

  /// 專屬檔不存在時，套在 `happy_dog.json` 上的濾鏡。
  /// null 表示不套（happy 本來就是那個檔）。
  final ColorFilter? fallbackFilter;

  const PetMoodVisual({required this.assetPath, this.fallbackFilter});
}

/// 所有心情共用的退路資產。這個檔一定存在。
const String kPetFallbackAnimation = 'assets/animations/happy_dog.json';

/// 建立「飽和度 + 亮度 + 色偏」的 4x5 色彩矩陣。
///
/// - [saturation] 1.0 = 原色，0.0 = 全灰
/// - [brightness] 1.0 = 原亮度，小於 1 變暗
/// - [tint] 加在 RGB 上的偏移量（-255 ~ 255），用來做冷／暖色調
///
/// 亮度權重用的是 ITU-R BT.709 的係數（0.213 / 0.715 / 0.072），
/// 也就是 CSS `filter: saturate()` 與大多數繪圖軟體採用的那一組。
/// 用感知亮度而非單純平均，去飽和之後深淺關係才不會亂掉。
ColorFilter _adjust({
  double saturation = 1.0,
  double brightness = 1.0,
  List<double> tint = const [0, 0, 0],
}) {
  const double lumR = 0.213;
  const double lumG = 0.715;
  const double lumB = 0.072;
  final double s = saturation;
  final double b = brightness;

  return ColorFilter.matrix(<double>[
    // R 列
    (lumR + s * (1 - lumR)) * b, (lumG - s * lumG) * b, (lumB - s * lumB) * b,
    0, tint[0],
    // G 列
    (lumR - s * lumR) * b, (lumG + s * (1 - lumG)) * b, (lumB - s * lumB) * b,
    0, tint[1],
    // B 列
    (lumR - s * lumR) * b, (lumG - s * lumG) * b, (lumB + s * (1 - lumB)) * b,
    0, tint[2],
    // A 列：透明度不動
    0, 0, 0, 1, 0,
  ]);
}

/// mood 字串 → 視覺設定。
///
/// 濾鏡的強弱刻意跟著「這個心情有多不好」單調遞增，理由是紅線 5：
/// **差的夜晚拿到的回饋必須明顯少於好的夜晚**。如果 tired 跟 happy
/// 看起來差不多，那個回饋迴圈就斷了。
///
///     happy    原色                        睡得好
///     bored    微降飽和                     普通
///     tired    明顯降飽和 + 變暗             睡不好／熬夜
///     anxious  降飽和 + 變暗 + 冷色偏        生理明顯偏離 baseline
final Map<String, PetMoodVisual> _moodVisuals = <String, PetMoodVisual>{
  // happy 用的就是現有那個檔，不套濾鏡
  'happy': const PetMoodVisual(assetPath: 'assets/animations/happy_dog.json'),
  'bored': PetMoodVisual(
    assetPath: 'assets/animations/bored_dog.json',
    fallbackFilter: _adjust(saturation: 0.70, brightness: 0.95),
  ),
  'tired': PetMoodVisual(
    assetPath: 'assets/animations/tired_dog.json',
    fallbackFilter: _adjust(saturation: 0.45, brightness: 0.80),
  ),
  'anxious': PetMoodVisual(
    assetPath: 'assets/animations/anxious_dog.json',
    // 冷色偏：抽掉一點紅、加一點藍，讀起來會偏向不安而不只是疲倦
    fallbackFilter: _adjust(
      saturation: 0.40,
      brightness: 0.78,
      tint: <double>[-6, 0, 18],
    ),
  ),
};

/// 查表。未知的 mood 一律當 `bored`（中性），不要當成 happy——
/// 把未知狀態顯示成最好的狀態，正是紅線 5 要防的那種「不管怎樣都給獎勵」。
PetMoodVisual petMoodVisual(String? mood) {
  return _moodVisuals[mood?.toLowerCase()] ?? _moodVisuals['bored']!;
}
