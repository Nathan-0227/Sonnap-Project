// 手錶實測的睡眠效率（`GET /home` 的 `behavior.measured_efficiency`）。
//
// 這一組守四件**壞掉都不會報錯**的事：
//
//   1. **算不出來不是 0%。** 要同時有手錶資料與「開始／結束睡覺」兩個
//      按鈕才算得出來，所以 null 是常態。畫成 0% 等於告訴一個我們根本
//      沒量到的人「你整夜沒睡著」。
//   2. **那句「不計分」必須照抄後端。** 這個 App 裡有四個東西叫「睡眠
//      效率」，其中手錶自己那個 2026-10-01 起已經停止計分。這一個也不
//      計分——在 Dart 把它改寫成「參考值」就等於自己發明了一種說法。
//   3. **basis 不能省。** 四個「效率」只有 basis 分得開它們；只讀數字
//      的人會拿它去比另外三個。
//   4. **Dart 不重算這個百分比。** 分子在 wearable_nightly、分母在
//      nightly_behavior，後端讀取時才 join（兩張表寫入時機不固定）。
//      在 Dart 乘一次就有第二個定義處，而兩份漂移時不會有錯誤訊息。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/home_service.dart';
import 'package:app/services/user_identity.dart';

const String testUserId = '00000000-5017-4e01-9a30-000000000001';

/// 後端 `behavior/sleep_efficiency.py` 的原文（算得出來的情況）。
/// ⚠️ 照抄，不要在測試裡改寫——這條測試的意義就是「畫面上的字來自後端」。
/// ⚠️ 2026-11-07 起效率恢復計分（三段式），這兩句從「不影響分數」改成
///    「分數什麼時候用它」。
const String kOkNote =
    'The sleep your watch measured, as a share of the time you said you were '
    'trying to sleep - from when you tapped Start sleep to when you tapped '
    'Out of bed. Your sleep score uses this figure whenever it can be worked '
    'out.';

/// 並列的第二個效率，後端原文（`watch_wake_efficiency`）。
/// ⚠️ 它與 kOkNote 講的是**不同的量**——終點是手錶給的，不是使用者按的。
const String kWatchWakeNote =
    'The same watch-measured sleep, but counted from when you tapped Start '
    'sleep to when your watch says you woke up - so it still works on nights '
    'you forgot to tap Out of bed. Your sleep score uses this figure only on '
    'nights the Start sleep to Out of bed figure could not be worked out.';

/// 算不出來時後端給的原因（最常見的那一個：沒按按鈕）。
/// ⚠️ 這句**要能讓人照著做**——「沒按按鈕」是所有失敗情況裡唯一使用者
///    改得了的，所以它會指名那兩個按鈕。後端的守則寫在
///    `tests/test_sleep_efficiency.py`【6b】。
const String kNoMarksNote =
    "You didn't mark this night. Tap Start sleep when you get into bed and "
    'Out of bed when you get up, and this can be worked out for you.';

/// 有數字的那一晚。91.7% 是 2026-09-13 的實測值（480 分 ÷ 523.4 分）。
const Map<String, dynamic> kHomeWithEfficiency = {
  'schema_version': 2,
  'date': '2026-09-13',
  'behavior': {
    'late_night_ratio': 0.444,
    'late_nights': 12,
    'recorded_nights': 27,
    'measured_efficiency': 91.7,
    'measured_efficiency_basis': 'watch_tst__phone_tats',
    'measured_efficiency_note': kOkNote,
    'watch_wake_efficiency': 91.5,
    'watch_wake_efficiency_basis': 'phone_bed_start__watch_wake',
    'watch_wake_efficiency_note': kWatchWakeNote,
  },
};

/// 🔴 這一組是新欄位存在的全部理由：**沒按 Out of bed，但仍然有數字**。
/// 實測 09-14（手錶睡 243 分、04:16 按 Start sleep、手錶 08:32 起床）。
const Map<String, dynamic> kHomeOnlyWatchWake = {
  'schema_version': 2,
  'date': '2026-09-14',
  'behavior': {
    'late_night_ratio': 0.444,
    'late_nights': 12,
    'recorded_nights': 27,
    'measured_efficiency': null,
    'measured_efficiency_basis': 'watch_tst__phone_tats',
    'measured_efficiency_note': kNoMarksNote,
    'watch_wake_efficiency': 95.2,
    'watch_wake_efficiency_basis': 'phone_bed_start__watch_wake',
    'watch_wake_efficiency_note': kWatchWakeNote,
  },
};

/// 沒按按鈕的那一晚：後端回 **null** 並附上原因。
const Map<String, dynamic> kHomeWithoutMarks = {
  'schema_version': 2,
  'date': '2026-09-14',
  'behavior': {
    'late_night_ratio': 0.444,
    'late_nights': 12,
    'recorded_nights': 27,
    'measured_efficiency': null,
    'measured_efficiency_basis': 'watch_tst__phone_tats',
    'measured_efficiency_note': kNoMarksNote,
  },
};

/// 舊版後端：根本沒有這三個欄位。
const Map<String, dynamic> kHomeOldBackend = {
  'schema_version': 2,
  'date': '2026-09-01',
  'behavior': {
    'late_night_ratio': 0.444,
    'late_nights': 12,
    'recorded_nights': 27,
  },
};

class _FakeBackend {
  late final HttpServer server;
  final List<String> paths = [];
  Map<String, dynamic> response = kHomeWithEfficiency;

  Future<String> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      paths.add(request.uri.toString());
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    return 'http://127.0.0.1:${server.port}';
  }

  Future<void> stop() => server.close(force: true);
}





void main() {
  group('【1】服務層', () {
    late _FakeBackend backend;
    late String baseUrl;
    HttpOverrides? savedOverrides;

    setUp(() async {
      // ⚠️ 同一個檔案裡有 testWidgets 就會裝上「一律回 400」的假 HttpClient。
      savedOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      backend = _FakeBackend();
      baseUrl = await backend.start();
    });
    tearDown(() async {
      await backend.stop();
      HttpOverrides.global = savedOverrides;
    });

    test('三個欄位都解析得出來', () async {
      final result = await HomeService(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      ).fetch();

      expect(result.status, HomeStatus.ok);
      expect(result.behavior!.measuredEfficiency, 91.7);
      expect(result.behavior!.measuredEfficiencyBasis, 'watch_tst__phone_tats');
      expect(result.behavior!.measuredEfficiencyNote, kOkNote);
    });

    test('⚠️ 算不出來時是 null，不是 0', () async {
      backend.response = kHomeWithoutMarks;
      final result = await HomeService(
        baseUrl: baseUrl,
        identity: const BuildTimeUserIdentity(overrideId: testUserId),
      ).fetch();

      expect(result.behavior!.measuredEfficiency, isNull,
          reason: '解析成 0.0 之後就再也分不出「沒量到」與「整夜沒睡著」');
      expect(result.behavior!.measuredEfficiencyNote, kNoMarksNote,
          reason: '原因要留著——沒按按鈕是使用者唯一改得了的事');
    });
  });

}
