// 資料層測試：讀**真實的** assets/data/app_payload.json。
//
// ⚠️ 為什麼要獨立成一個檔案，不要併回 widget_test.dart：
//    這裡用 tester.runAsync() 讓真實的非同步 I/O 跑完（rootBundle 在
//    flutter_test 預設的假 async zone 裡永遠讀不完，pump 幾次都沒用）。
//    但 runAsync 跟前面 widget 測試留下的計時器會互相卡住——HeaderCard 會
//    起一個 Timer.periodic(30 秒)。實測：這個測試單獨跑會過，接在 widget
//    測試後面就整個 hang 住。`flutter test` 每個檔案跑在獨立 isolate，
//    所以拆檔就乾淨解決了。
//
// 這個檔案驗證的是其他測試驗不到的一整條路徑：
//   pubspec 的 assets 宣告 → rootBundle 讀得到 → Python 產生的 JSON
//   真的能被 SleepSession.fromJson 解析。

import 'package:app/services/sleep_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the real payload from the pipeline loads and parses',
      (tester) async {
    await tester.runAsync(() async {
      final session = await const AssetSleepRepository().load();

      // 後端算出來的值要完整帶到 App 這一側
      expect(session.scoring.finalQuality, isNotEmpty);
      expect(session.scoring.finalScore, isNotNull);
      expect(session.display.scoreMessage, isNotEmpty);

      expect(
        session.status.petMood,
        anyOf('happy', 'tired', 'bored', 'anxious'),
        reason: 'pet_mood 必須是 data contract 定義的四個合法值之一',
      );
      expect(
        session.status.energyLevel,
        session.scoring.finalScore!.round(),
        reason: 'energy_level 應等於四捨五入後的 final_score',
      );

      // 三個刻意留空的欄位不可以變成 0——
      // 那會謊稱我們量到了實際上沒量到的東西
      expect(session.metrics.motionCount, isNull,
          reason: 'motion_count 應由影像組提供，Garmin 的值語意不同');
      expect(session.metrics.ambientNoiseDb, isNull,
          reason: 'Garmin 沒有環境音；TAPO 的分貝是模擬值');
      expect(session.status.currentActivity, isNull,
          reason: '需要即時狀態，批次 pipeline 給不出來');

      // score_message 有長度上限（SleepScoreCard 是固定高度卡片，
      // 超過約 10 字會換行撐破版面）。Python 端也有同樣的檢查。
      expect(session.display.scoreMessage.length, lessThanOrEqualTo(10));

      // ── Garmin 動作資料（2026-08-12 修正後新增）─────────────────
      // 這一段是在鎖住那次修正：舊的 movement_count 其實是「取樣分鐘數」，
      // 跟身體動不動無關（與睡眠時長 r=+0.929、與夜間清醒 r=−0.138）。
      // 現在真訊號來自 activityLevel。若有人不小心改回只數筆數，
      // levelMean / activeMinutes 會消失，這個測試就會擋下來。
      final movement = session.metrics.garminMovement;

      expect(movement.sampleMinutes, isNotNull,
          reason: '取樣分鐘數應該一定有值（有睡眠記錄的夜晚就會有 movement 取樣）');
      expect(movement.levelMean, isNotNull,
          reason: 'activityLevel 平均是真正的動作訊號，不可以再被丟掉');
      expect(movement.activeMinutes, isNotNull,
          reason: '超過門檻的分鐘數是真正的動作訊號，不可以再被丟掉');

      // activityLevel 實測範圍 0.00–7.64。超出這個範圍代表上游解析錯了
      // （例如把別的欄位當成 activityLevel 讀進來）。
      expect(movement.levelMean!, inInclusiveRange(0, 10));
      expect(movement.levelMax!, inInclusiveRange(0, 10));

      // 活躍分鐘是取樣分鐘的子集合，不可能比它大。
      expect(movement.activeMinutes!,
          lessThanOrEqualTo(movement.sampleMinutes!),
          reason: '超過門檻的分鐘數不可能多於總取樣分鐘數');
    });
  });
}
