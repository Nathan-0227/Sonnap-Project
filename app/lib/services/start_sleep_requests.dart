import 'package:flutter/foundation.dart';

/// 「開始睡覺」的請求（2026-11-13 使用者定：Start Sleep 從首頁搬到導覽列中間的月亮）。
///
/// 導覽列在 main.dart、開始睡覺的流程（存標記、排鬧鐘、睡覺畫面、起床報告）在首頁，
/// 所以月亮只送一個請求，由首頁照原本的流程做——**流程只有一份**。
class StartSleepRequests extends ChangeNotifier {
  void request() => notifyListeners();
}
