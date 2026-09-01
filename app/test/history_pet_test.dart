// 趨勢圖上選到某一晚 → 顯示那一晚的寵物。
//
// 這一組守的核心是**心情的來源**。最容易發生的回歸是有人覺得
// 「history 有 final_quality 啊，在 Dart 直接查表就好了」，然後寫下
// `quality == 'Good' ? 'happy' : ...`。那會同時造成兩個問題：
//
//   1. **anxious 的夜晚會被畫成 happy。** anxious 是 Tier3 生理修正值
//      （壓力、心率相對個人 baseline）的覆寫，那幾個欄位根本不在 history 裡。
//      實測 payload 裡 07-06 與 07-07 都是 `final_quality=Good` 但
//      `pet_mood=anxious`——照品質推，這兩晚會顯示成快樂的狗。
//
//   2. `QUALITY_TO_MOOD` 會有第二個定義處，違反「Python 判斷、Dart 只負責畫」。
//      兩份定義漂移時不會有任何錯誤訊息。

import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/sleep_session.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:app/widgets/pet_mood_animation.dart';

void main() {
  late SleepSession sample;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sample = await const AssetSleepRepository().load();
  });

  group('history 帶得動心情', () {
    test('每一晚都有 pet_mood，而且是四個合法值之一', () {
      const legal = {'happy', 'bored', 'tired', 'anxious'};

      expect(sample.history, isNotEmpty);
      for (final entry in sample.history) {
        expect(
          entry.petMood,
          isNotNull,
          reason: '${entry.date} 沒有 pet_mood——'
              '後端漏掉的話畫面會安靜地退回一個月亮 icon，看不出少了東西',
        );
        expect(legal, contains(entry.petMood), reason: entry.date);
      }
    });

    test('每一晚都有 mood_reason，心情要能追溯到規則', () {
      for (final entry in sample.history) {
        expect(
          entry.moodReason,
          isNotNull,
          reason: '${entry.date} 的心情講不出理由。'
              '這與評分系統「數字要能講出理由」是同一個要求',
        );
        expect(entry.moodReason, isNotEmpty);
      }
    });

    test('最新一晚的 history 心情與 status 心情必須一致', () {
      // 兩條路徑算出不同的心情，就會變成「同一晚在首頁與 Insights
      // 顯示不同的寵物」——那是最難查的一種 bug，因為兩邊看起來都正常。
      final latest = sample.history.last;
      expect(
        latest.petMood,
        sample.status.petMood,
        reason: '首頁顯示 ${sample.status.petMood}，'
            'Insights 的同一晚顯示 ${latest.petMood}',
      );
    });
  });

  group('⚠️ 心情不可以從 final_quality 推出來', () {
    test('實測資料裡存在「Good 但 anxious」的夜晚', () {
      // 這條測試本身就是證據：只要這種夜晚存在，
      // 任何「照 quality 查表」的實作都一定會畫錯。
      final overridden = sample.history
          .where((e) => e.finalQuality == 'Good' && e.petMood == 'anxious')
          .toList();

      expect(
        overridden,
        isNotEmpty,
        reason: '找不到反例的話，這條測試就失去意義了——'
            '要嘛資料換了，要嘛 anxious 覆寫沒有生效。'
            '兩種情況都該有人看一眼',
      );
    });

    test('同一個 final_quality 底下出現不只一種心情', () {
      final byQuality = <String, Set<String>>{};
      for (final e in sample.history) {
        if (e.finalQuality == null || e.petMood == null) continue;
        byQuality.putIfAbsent(e.finalQuality!, () => <String>{}).add(e.petMood!);
      }

      final ambiguous =
          byQuality.entries.where((e) => e.value.length > 1).toList();

      expect(
        ambiguous,
        isNotEmpty,
        reason: 'quality → mood 若是一對一，就會有人想把它寫進 Dart。'
            '實際上不是：$byQuality',
      );
    });
  });

  group('心情 → 動畫', () {
    test('history 裡出現過的每一種心情都對得到資產', () {
      final moods = sample.history
          .map((e) => e.petMood)
          .whereType<String>()
          .toSet();

      for (final mood in moods) {
        final visual = petMoodVisual(mood);
        expect(visual.assetPath, startsWith('assets/animations/'));
      }

      // 四種心情在這份實測資料裡都要出現過，demo 才秀得出來
      expect(
        moods.length,
        4,
        reason: '30 晚的 history 裡只有 ${moods.length} 種心情（$moods）——'
            'demo 時就秀不出完整的四態',
      );
    });

    test('不同心情對到不同的動畫檔', () {
      final happy = petMoodVisual('happy').assetPath;
      final anxious = petMoodVisual('anxious').assetPath;
      final tired = petMoodVisual('tired').assetPath;

      expect(happy, isNot(anxious));
      expect(happy, isNot(tired));
      expect(anxious, isNot(tired));
    });
  });

  group('⚠️ 每一種心情都必須在某個期間選項下看得到', () {
    /// 複製 report_screen 的期間篩選邏輯：`days` 天 = 最近 `days` 個**日曆天**，
    /// 0 = 全部。
    List<HistoryEntry> withinDays(int days) {
      final sorted = List<HistoryEntry>.from(sample.history)
        ..sort((a, b) => a.date.compareTo(b.date));
      if (days == 0) return sorted;
      final latest = DateTime.parse(sorted.last.date);
      final start = latest.subtract(Duration(days: days - 1));
      return sorted
          .where((e) => !DateTime.parse(e.date).isBefore(start))
          .toList();
    }

    test('30 天的窗格看不到 anxious——這就是為什麼需要「全部」', () {
      // 這條不是在測 bug，是把「為什麼多了一個選項」這個理由釘住。
      // 趨勢圖的期間是**日曆天**，而 history 是 30 個**有資料的夜晚**，
      // 橫跨 62 天。兩者不一樣，中間差掉的夜晚在 App 裡打不開。
      final moods30 = withinDays(30).map((e) => e.petMood).toSet();
      expect(
        moods30,
        isNot(contains('anxious')),
        reason: '如果 30 天內已經看得到 anxious，那「全部」這個選項的理由'
            '就要重寫——不要讓一段沒有理由的程式留著',
      );
    });

    test('「全部」看得到四種心情', () {
      final moodsAll = withinDays(0).map((e) => e.petMood).toSet();
      expect(
        moodsAll,
        containsAll(<String>['happy', 'bored', 'tired', 'anxious']),
        reason: '每一種心情都要有辦法在畫面上被選到，'
            '否則 payload 裡有資料、使用者卻永遠看不到',
      );
    });

    test('「全部」真的涵蓋每一晚', () {
      expect(withinDays(0).length, sample.history.length);
      expect(
        withinDays(30).length,
        lessThan(sample.history.length),
        reason: '30 天若已涵蓋全部，就表示資料範圍變了，'
            '上面兩條測試的前提要重新確認',
      );
    });
  });

  group('交接指定的驗收夜晚', () {
    HistoryEntry? nightOf(String date) {
      for (final e in sample.history) {
        if (e.date == date) return e;
      }
      return null;
    }

    test('08-09 是 tired（Poor）', () {
      final night = nightOf('2026-08-09');
      expect(night, isNotNull);
      expect(night!.petMood, 'tired');
      expect(night.finalQuality, 'Poor');
    });

    test('08-23 是 happy（Good）', () {
      final night = nightOf('2026-08-23');
      expect(night, isNotNull);
      expect(night!.petMood, 'happy');
      expect(night.finalQuality, 'Good');
    });

    test('07-06 / 07-07 是 anxious，而且品質是 Good', () {
      for (final date in ['2026-07-06', '2026-07-07']) {
        final night = nightOf(date);
        expect(night, isNotNull, reason: '$date 不在 history 裡');
        expect(night!.petMood, 'anxious', reason: date);
        expect(
          night.finalQuality,
          'Good',
          reason: '$date 正是「分數不低但生理偏離」的例子，'
              '拿掉的話上面那條反例測試就沒有素材了',
        );
      }
    });
  });
}
