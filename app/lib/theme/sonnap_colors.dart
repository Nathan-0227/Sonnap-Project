import 'package:flutter/material.dart';

/// 首頁、晚上版、睡覺畫面共用的一組顏色、圓角、間距（2026-11-12 改版）。
///
/// 改版的起因是「每張卡片各自一個顏色、一種圓角，看起來像拼起來的」。
/// ⚠️ 新的畫面元件請從這裡拿，不要再寫死 `Color(0xFF10265A)` 這種值——
/// 寫死一次就多一個「長得不一樣的卡片」。
class SonnapColors {
  SonnapColors._();

  /// 頁面底色（與 main.dart 的 Scaffold 相同）。
  static const Color background = Color(0xFF081326);

  /// 頁面上半部的光暈，讓寵物站在一個場景裡而不是一塊色塊上。
  static const Color backdropTop = Color(0xFF1A2456);

  /// 卡片：半透明，隱約透出後面的夜空（2026-11-12 使用者要求），加一條淡邊框。
  static const Color card = Color(0x803A3672);
  static const Color cardBorder = Color(0x26FFFFFF);

  /// 強調色：切換鈕、按鈕、圖示。
  static const Color accent = Color(0xFF8B6DFF);
  static const Color accentSoft = Color(0xFFB9A6FF);

  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xB3FFFFFF);
  static const Color textMuted = Color(0xFF8498B7);

  static const double radius = 24;
  static const double gap = 12;
}

/// 統一的卡片外框。
BoxDecoration sonnapCardDecoration() => BoxDecoration(
  color: SonnapColors.card,
  borderRadius: BorderRadius.circular(SonnapColors.radius),
  border: Border.all(color: SonnapColors.cardBorder),
);
