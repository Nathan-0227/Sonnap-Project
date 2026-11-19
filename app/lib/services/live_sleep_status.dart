/// 好友頁的即時狀態（2026-11-19 使用者 grill 後定）。
///
/// 按 Start Sleep／Out of bed（含 I already got up）／Cancel 的**當下**各送一次 `POST /sleep-status`。
/// 狀態怎麼判（asleep／up／past_bedtime／awake）全在後端 `social/live_status.py`，Dart 不判。
///
/// ⚠️ **只試一次、不排隊補送**：半夜補送一個「我在睡」已經沒有意義（使用者定）。
/// ⚠️ **送不出去不能擋住睡覺**：呼叫端一律 `unawaited`，這裡吞掉所有錯誤。
/// ⚠️ 不碰上床／下床的正式紀錄——那個照舊早上跟 `POST /nightly` 一起送。
library;

/// 'start'／'end'／'cancel'。
typedef SleepStatusSink = Future<void> Function(String event, DateTime? at);

/// 手機的牆鐘時間（不帶時區，同 bed_start_at）。後端照牆鐘讀，不換 UTC。
String wallClockIso(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
      'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// 呼叫 [sink]，任何錯誤都吞掉（不擋睡覺畫面）。
Future<void> sendSleepStatus(SleepStatusSink? sink, String event, DateTime? at) async {
  if (sink == null) return;
  try {
    await sink(event, at);
  } catch (_) {
    // 只試一次，連不到就算了
  }
}
