import 'package:flutter/widgets.dart';

/// 助理回答底下那個「See … for last night ›」（2026-11-22）：開**首頁同一份**詳細頁（NightSheets）。
///
/// 鍵由後端給（`ai/chat.LINKS`，只給那一晚有資料的）；這裡只管「寫什麼字、開哪一頁」。
/// 不認得的鍵不畫連結。
const Map<String, String> kNightSheetLinkLabels = {
  'total_sleep': 'See Total sleep for last night',
  'efficiency': 'See Efficiency for last night',
  'awake': 'See Awake for last night',
  'deep': 'See Deep sleep for last night',
};

/// 開某一晚的某一頁。首頁建好時登記（組報告的那一份 ReportLoader 在首頁裡），
/// 跟 `PlanStore.shared` 同一個做法：助理頁不必再拿一份 loader。
/// null＝首頁還沒建好（測試），連結就不出現。
typedef NightSheetOpener = Future<void> Function(BuildContext context, String date, String key);

class NightSheetLinks {
  static NightSheetOpener? shared;
}
