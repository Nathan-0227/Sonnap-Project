/// 把帶時區偏移的 ISO8601 字串解析成「牆鐘時間」。
///
/// ## 為什麼需要這個而不是直接用 `DateTime.tryParse`
///
/// `DateTime.tryParse('2026-08-22T22:32:00+08:00')` 回傳的是 **UTC** 的
/// DateTime（`isUtc == true`），所以 `.hour` 讀出來是 **14**，不是 22：
///
/// ```
/// 原始字串      : 2026-08-22T22:32:00+08:00
/// tryParse.hour : 14:32   ← 錯，這是 UTC
/// toLocal().hour: 22:32   ← 對，但只在裝置時區剛好是 +08:00 時才對
/// ```
///
/// 這個 bug 實際發生過兩處，而且都是使用者看得到的畫面：
///   - `report_screen.dart` 的 Insights 圖表（每晚就寢時間都早 8 小時）
///   - 睡眠助理回答「你幾點睡的」
///
/// ## 為什麼不用 `.toLocal()`
///
/// `.toLocal()` 用的是**執行裝置**的時區。受測同學如果把手機時區設成別的地方
/// （或出國），同一筆資料就會顯示成不同時間——但那筆資料記錄的是
/// 「手錶在當地量到你 22:32 睡著」，那個事實不會因為看的人在哪裡而改變。
///
/// 本專案的規範是「時間格式一律 ISO8601（+08:00）」，字串裡already帶著
/// 正確的偏移量，直接照它還原即可，不需要也不應該倚賴裝置設定。
library;

/// 解析 ISO8601 字串，回傳一個 `.hour` / `.minute` 等於**字串上寫的那個時間**
/// 的 DateTime。轉不動回 null。
///
/// ⚠️ 回傳值只適合用來「顯示」與「算同一天內的時間差」。
///    它刻意不是一個絕對時間點——`isUtc` 為 true 但實際承載的是當地牆鐘時間，
///    拿它跟 `DateTime.now()` 直接比較會錯 8 小時。要比較絕對時間請另外
///    用 `DateTime.tryParse` 的原始結果。
DateTime? parseWallClock(dynamic value) {
  if (value is! String || value.isEmpty) return null;

  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;

  // 沒有偏移量的字串（例如 "2026-08-22 22:32:00"）tryParse 會當成本地時間、
  // isUtc 為 false，此時它讀出來的就已經是牆鐘時間，不用動。
  if (!parsed.isUtc) return parsed;

  // 從字串尾端取出偏移量。三種合法寫法：Z、+08:00、-05:30
  final offset = _offsetOf(value);
  if (offset == null) return parsed; // 明確標 Z（UTC），本身就是牆鐘時間

  // parsed 是 UTC，加回偏移量就得到原本寫在字串上的那個時間
  return parsed.add(offset);
}

/// 從 ISO8601 字串尾端解析時區偏移量。標了 Z 或沒有偏移量時回 null。
Duration? _offsetOf(String iso) {
  // 只看最後 6 個字元，避免誤判日期裡的減號（2026-08-22 那兩個）
  final tail = iso.length >= 6 ? iso.substring(iso.length - 6) : iso;
  final m = RegExp(r'^([+-])(\d{2}):?(\d{2})$').firstMatch(tail);
  if (m == null) return null;

  final sign = m.group(1) == '-' ? -1 : 1;
  final hours = int.parse(m.group(2)!);
  final minutes = int.parse(m.group(3)!);
  return Duration(hours: sign * hours, minutes: sign * minutes);
}
