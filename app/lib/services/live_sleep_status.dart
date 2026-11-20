/// 好友頁的即時狀態（2026-11-19 使用者 grill 後定）。
///
/// 按 Start Sleep／Out of bed（含 I already got up）／Cancel 的**當下**各送一次 `POST /sleep-status`。
/// 狀態怎麼判（asleep／up／past_bedtime／awake）全在後端 `social/live_status.py`，Dart 不判。
///
/// ⚠️ **只試一次、不排隊補送**：半夜補送一個「我在睡」已經沒有意義（使用者定）。
/// ⚠️ **送不出去不能擋住睡覺**：呼叫端一律 `unawaited`，這裡吞掉所有錯誤。
/// ⚠️ 不碰上床／下床的正式紀錄——那個照舊早上跟 `POST /nightly` 一起送。
///
/// 2026-11-21 起後端收到 start 會順便開攝影機錄影（`camera_auto.py`，只對手機帳號、只從區網），
/// 回應裡的 `camera` 放進 [cameraStatusBoard]，睡覺畫面讀它顯示一行小字。
library;

import 'package:flutter/foundation.dart';

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

/// 後端回報的攝影機狀態（`POST /sleep-status` 回應的 `camera`）。
/// state 照抄後端：recording／already_recording／starting／not_started／stopping／cancelling／idle。
@immutable
class CameraStatus {
  final String state;

  /// 筆電是不是用電池；後端查不到是 null。
  final bool? onBattery;

  const CameraStatus(this.state, {this.onBattery});

  static CameraStatus? fromJson(Object? json) {
    if (json is! Map) return null;
    final state = json['state'];
    if (state is! String || state.isEmpty) return null;
    final battery = json['on_battery'];
    return CameraStatus(state, onBattery: battery is bool ? battery : null);
  }
}

/// 睡覺畫面那一行（2026-11-21 grill Q9）。只有**確定在錄**才寫；
/// 其他情況（還在接、沒開成、沒回應）一律 null＝什麼都不寫——
/// 手機分不出是後端沒開還是網路慢，寫「Camera off」可能是錯的。
String? cameraStatusLine(CameraStatus? status) {
  if (status == null) return null;
  if (status.state != 'recording' && status.state != 'already_recording') return null;
  return status.onBattery == true ? 'Camera recording · laptop on battery' : 'Camera recording';
}

/// 最近一次後端回報的攝影機狀態。按 Start Sleep 送出前先清掉，免得顯示上一晚的。
/// 半夜重開 App 時是 null（不寫字）。
final ValueNotifier<CameraStatus?> cameraStatusBoard = ValueNotifier<CameraStatus?>(null);
