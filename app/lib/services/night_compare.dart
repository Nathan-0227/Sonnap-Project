import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// 首頁「跟上一晚比」（2026-11-12 使用者定案）。
///
/// - 比的是**上一個有資料的晚上**（那一項沒資料的晚上跳過）
/// - 顏色只代表方向，**不代表好壞**：照台灣股市慣例，上升紅、下降綠、持平灰。
///   ⚠️ 不要改成「變好綠、變差紅」——那是在 Dart 判斷好壞，而睡得多不一定比較好
///   （評分裡超過 9 小時會扣分），攝影機動作更是驗證過與任何結果都無關。
/// - 純函式，沒有 I/O，測得到。

/// 一晚的某一項數值。
@immutable
class NightValue {
  final String date; // yyyy-MM-dd
  final double value;
  const NightValue(this.date, this.value);
}

/// 跟上一晚比的結果。
@immutable
class NightDelta {
  final double delta;
  final String previousDate;
  const NightDelta(this.delta, this.previousDate);

  bool get isUp => delta > 0;
  bool get isDown => delta < 0;
}

const Color kDeltaUp = Color(0xFFFF6B6B); // 上升：紅
const Color kDeltaDown = Color(0xFF7ED957); // 下降：綠
const Color kDeltaFlat = Color(0xFF8498B7); // 持平：灰

/// [nights] 依日期排好或沒排好都可以。[currentDate] 是首頁那一晚。
/// 回傳 null = 首頁那一晚沒有值，或之前沒有任何一晚有值。
NightDelta? compareWithPrevious(List<NightValue> nights, String currentDate) {
  NightValue? current;
  NightValue? previous;
  for (final n in nights) {
    if (n.date == currentDate) current = n;
  }
  if (current == null) return null;
  for (final n in nights) {
    if (n.date.compareTo(currentDate) >= 0) continue;
    if (previous == null || n.date.compareTo(previous.date) > 0) previous = n;
  }
  if (previous == null) return null;
  return NightDelta(current.value - previous.value, previous.date);
}

/// 最近 [count] 晚（含首頁那一晚、不含之後的），依日期由舊到新。給長條圖用。
List<NightValue> lastNights(
  List<NightValue> nights,
  String currentDate, {
  int count = 7,
}) {
  final upTo = nights.where((n) => n.date.compareTo(currentDate) <= 0).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  return upTo.length <= count ? upTo : upTo.sublist(upTo.length - count);
}

/// 「Nov 8」。
String shortDate(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : DateFormat('MMM d').format(d);
}

/// 箭頭＋差多少＋跟哪一晚比，例如「↑ 1h 12m vs Nov 8」。
/// [format] 把差值的絕對值換成文字（每一項單位不同）。
String deltaText(NightDelta d, String Function(double absDelta) format) {
  final arrow = d.isUp ? '↑' : (d.isDown ? '↓' : '=');
  final body = d.delta == 0 ? 'same' : format(d.delta.abs());
  return '$arrow $body vs ${shortDate(d.previousDate)}';
}

Color deltaColor(NightDelta d) =>
    d.isUp ? kDeltaUp : (d.isDown ? kDeltaDown : kDeltaFlat);

/// 分鐘數 → 「1h 12m」或「15m」。
String formatMinutes(double minutes) {
  final m = minutes.round();
  final h = m ~/ 60;
  final r = m % 60;
  if (h == 0) return '${r}m';
  return r == 0 ? '${h}h' : '${h}h ${r}m';
}
