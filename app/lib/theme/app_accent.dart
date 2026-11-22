import 'package:flutter/material.dart';

import '../services/key_value_store.dart';

/// 主題色＋App 內的「減少動態效果」（2026-11-22 grill Q5：A＋C）。
///
/// - 深色底不變，只換**強調色**：導覽列、按鈕、開關、勾、進度條、讀取中的轉圈。
/// - ⚠️ **圖表裡有意思的顏色不跟著換**：睡著的淡紫、睡眠階段、報告的配色、心情的顏色——
///   換了的話「同一個顏色＝同一件事」就斷了。
/// - 兩個都**只存在手機上**，預設紫色、跟著系統。
/// - 讀的時候用 [accentOf]／[accentSoftOf]（走 Theme，換了整個 App 會重畫）；
///   不要再寫死 `Color(0xFF7657FF)`。
enum AccentTheme { purple, blue, pink, green }

class AccentPalette {
  /// 主色：按鈕底、開關、選中的框。
  final Color accent;

  /// 淡色：深底上的文字連結、選中的分頁圖示。
  final Color soft;

  const AccentPalette(this.accent, this.soft);
}

const Map<AccentTheme, AccentPalette> kAccentPalettes = {
  AccentTheme.purple: AccentPalette(Color(0xFF7657FF), Color(0xFFB9A6FF)),
  AccentTheme.blue: AccentPalette(Color(0xFF3D7EF5), Color(0xFFA9C8FF)),
  AccentTheme.pink: AccentPalette(Color(0xFFE0558F), Color(0xFFFFB3D2)),
  AccentTheme.green: AccentPalette(Color(0xFF26A672), Color(0xFFA3E8C8)),
};

String accentLabel(AccentTheme t) => switch (t) {
      AccentTheme.purple => 'Purple',
      AccentTheme.blue => 'Blue',
      AccentTheme.pink => 'Pink',
      AccentTheme.green => 'Green',
    };

class AppLook {
  AppLook._();

  static const accentKey = 'accent_theme';
  static const reduceMotionKey = 'reduce_motion';

  /// 全 App 共用的主題色。不認得的值一律紫色（預設）。
  static final ValueNotifier<AccentTheme> accent = ValueNotifier(AccentTheme.purple);

  /// App 內的減少動態效果。true＝不管系統設定都靜止；false＝跟著系統。
  static final ValueNotifier<bool> reduceMotion = ValueNotifier(false);

  static AccentTheme fromId(String? id) =>
      AccentTheme.values.firstWhere((t) => t.name == id, orElse: () => AccentTheme.purple);

  static Future<void> load(KeyValueStore store) async {
    try {
      accent.value = fromId(await store.getString(accentKey));
      reduceMotion.value = (await store.getString(reduceMotionKey)) == '1';
    } catch (_) {
      // 讀不到就維持預設
    }
  }

  static Future<void> chooseAccent(KeyValueStore store, AccentTheme t) async {
    accent.value = t;
    try {
      await store.setString(accentKey, t.name);
    } catch (_) {
      // 存不進去也照樣換（這次開著的期間有效）
    }
  }

  static Future<void> setReduceMotion(KeyValueStore store, bool on) async {
    reduceMotion.value = on;
    try {
      await store.setString(reduceMotionKey, on ? '1' : '0');
    } catch (_) {}
  }
}

/// 把淡色帶進 Theme（主色就是 colorScheme.primary）。
@immutable
class AccentExtension extends ThemeExtension<AccentExtension> {
  final Color soft;
  const AccentExtension(this.soft);

  @override
  AccentExtension copyWith({Color? soft}) => AccentExtension(soft ?? this.soft);

  @override
  AccentExtension lerp(covariant AccentExtension? other, double t) =>
      other == null ? this : AccentExtension(Color.lerp(soft, other.soft, t)!);
}

/// App 的 Theme：主色＝選的主題色。M3 預設元件（FilledButton、Switch、轉圈）都會跟著。
/// ⚠️ 底子維持 Flutter 預設的亮色（原本 MaterialApp 沒給 theme，就是它）：
///    改成暗色的話，對話框、輸入框這些沒寫死顏色的地方會悄悄變樣。
ThemeData sonnapTheme(AccentTheme t) {
  final p = kAccentPalettes[t]!;
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: p.accent).copyWith(primary: p.accent, onPrimary: Colors.white),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent),
    extensions: [AccentExtension(p.soft)],
  );
}

/// 目前的主色。Theme 沒有（測試裡直接畫元件）就用紫色。
Color accentOf(BuildContext context) {
  final ext = Theme.of(context).extension<AccentExtension>();
  return ext == null ? kAccentPalettes[AccentTheme.purple]!.accent : Theme.of(context).colorScheme.primary;
}

/// 目前的淡色。
Color accentSoftOf(BuildContext context) =>
    Theme.of(context).extension<AccentExtension>()?.soft ?? kAccentPalettes[AccentTheme.purple]!.soft;

/// 系統設定或 App 內開關任一個開了，就減少動態效果。包在 MaterialApp.builder 裡。
Widget applyReduceMotion(BuildContext context, Widget? child) {
  final mq = MediaQuery.of(context);
  return ValueListenableBuilder<bool>(
    valueListenable: AppLook.reduceMotion,
    builder: (_, on, _) => MediaQuery(
      data: mq.copyWith(disableAnimations: mq.disableAnimations || on),
      child: child ?? const SizedBox.shrink(),
    ),
  );
}
