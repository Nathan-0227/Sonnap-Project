// 起床自評（2026-11-12 定案）。
// ⚠️ 守的是「壞掉時不會報錯」的幾件事：
//   - 題目、五個選項、十個標籤與後端 behavior/morning_tips.py 逐字相同
//     （Dart 另存一份只為了離線也畫得出來；兩份漂移時沒有任何錯誤訊息）
//   - 送不出去的要留著下次補送；後端說格式錯的不再送
//   - 補填小卡只在起床 6 小時內、還沒填時出現
//   - 卡片上不出現任何分數（看到分數之前先問）
import 'dart:io';

import 'package:app/screens/rested_screen.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/morning_rating.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Sender implements RestedSender {
  final List<RestedSendResult> results;
  final List<MorningRating> sent = [];
  _Sender(this.results);
  @override
  Future<RestedSendResult> send(MorningRating rating) async {
    sent.add(rating);
    return results.isEmpty ? RestedSendResult.sent : results.removeAt(0);
  }
}

void main() {
  group('與後端同一份文字', () {
    // flutter test 的工作目錄是 app/
    final py = File('../behavior/morning_tips.py').readAsStringSync();

    test('五個選項逐字等於 RESTED_LABELS（CSD-M 第 10 題）', () {
      final block = RegExp(r'RESTED_LABELS = \{([^}]*)\}').firstMatch(py)!.group(1)!;
      final labels = {
        for (final m in RegExp(r'(\d+): "([^"]+)"').allMatches(block))
          int.parse(m.group(1)!): m.group(2)!,
      };
      expect(labels, kRestedLabels);
    });

    test('十個標籤（id、文字、順序）逐字等於 TAGS', () {
      final block = RegExp(r'TAGS = \{([^}]*)\}').firstMatch(py)!.group(1)!;
      final tags = [
        for (final m in RegExp(r'"([a-z_]+)": "([^"]+)"').allMatches(block))
          (m.group(1)!, m.group(2)!),
      ];
      expect(tags, kRestedTags);
    });

    test('題目照抄研究文件裡的 CSD-M 原文', () {
      final doc =
          File('../Research-Background/起床小建議與自評.md').readAsStringSync();
      expect(doc.contains(kRestedQuestion), isTrue,
          reason: '題目要與核對過原文的那份文件一致');
    });
  });

  group('補填小卡的 6 小時窗', () {
    final wake = DateTime(2026, 11, 12, 7, 10);
    test('起床後 6 小時內、沒填過 → 出現', () {
      expect(
          showRestedMakeUp(
              wakeAt: wake, now: wake.add(const Duration(hours: 6)), existing: null),
          isTrue);
    });
    test('超過 6 小時、已經填過、沒有起床時刻 → 不出現', () {
      expect(
          showRestedMakeUp(
              wakeAt: wake,
              now: wake.add(const Duration(hours: 6, minutes: 1)),
              existing: null),
          isFalse);
      expect(
          showRestedMakeUp(
              wakeAt: wake,
              now: wake.add(const Duration(hours: 1)),
              existing: const MorningRating(date: '2026-11-12', rested: 3)),
          isFalse);
      expect(
          showRestedMakeUp(wakeAt: null, now: wake, existing: null), isFalse);
    });
    test('起床後幾分鐘：沒有起床時刻就是 null，不猜', () {
      expect(minutesAfterWake(wake, wake.add(const Duration(minutes: 25))), 25);
      expect(minutesAfterWake(null, wake), isNull);
    });
  });

  group('保存與補送', () {
    const rating = MorningRating(
        date: '2026-11-12', rested: 4, tags: ['exercise'], minutesAfterWake: 3);

    test('⚠️ 連不到 → 先存在手機上，下次補送；送成功就不再送', () async {
      final store = MorningRatingStore(InMemoryKeyValueStore());
      final sender = _Sender([RestedSendResult.retryLater]);
      expect(await store.save(rating, sender), RestedSendResult.retryLater);
      expect((await store.read('2026-11-12'))!.rested, 4,
          reason: '送不出去也要在手機上，報告才畫得出 You felt');

      await store.retryUnsent(sender);
      expect(sender.sent, hasLength(2));
      expect(sender.sent.last.tags, ['exercise']);

      await store.retryUnsent(sender);
      expect(sender.sent, hasLength(2), reason: '送成功之後不能再送');
    });

    test('後端說格式錯（4xx）→ 不再送', () async {
      final store = MorningRatingStore(InMemoryKeyValueStore());
      final sender = _Sender([RestedSendResult.rejected]);
      await store.save(rating, sender);
      await store.retryUnsent(sender);
      expect(sender.sent, hasLength(1));
    });

    test('同一晚再填一次就覆蓋', () async {
      final store = MorningRatingStore(InMemoryKeyValueStore());
      await store.save(rating, null);
      await store.save(
          const MorningRating(date: '2026-11-12', rested: 1), null);
      expect((await store.read('2026-11-12'))!.rested, 1);
    });
  });

  group('卡片', () {
    Future<void> pumpCard(WidgetTester tester, Widget home,
        {Size size = const Size(1080, 2340)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: home));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('⚠️ 沒選臉之前 Save 按不下去；卡片上沒有任何分數', (tester) async {
      await pumpCard(
        tester,
        RestedScreen(
          date: '2026-11-12',
          wakeAt: DateTime(2026, 11, 12, 7, 10),
          store: MorningRatingStore(InMemoryKeyValueStore()),
        ),
      );
      expect(find.text(kRestedQuestion), findsOneWidget);
      for (final label in kRestedLabels.values) {
        expect(find.text(label), findsOneWidget);
      }
      for (final (_, text) in kRestedTags) {
        expect(find.text(text), findsOneWidget);
      }
      final save = tester.widget<FilledButton>(find.byKey(const Key('rested-save')));
      expect(save.onPressed, isNull);
      expect(find.textContaining('score', findRichText: true), findsOneWidget,
          reason: '只有「Before you see your score」那一句提到分數');
      expect(find.textContaining('XP'), findsNothing);
      expect(tester.takeException(), isNull, reason: '1080×2340 不溢出');

      await tester.tap(find.byKey(const Key('rested-face-2')));
      await tester.pump();
      final enabled =
          tester.widget<FilledButton>(find.byKey(const Key('rested-save')));
      expect(enabled.onPressed, isNotNull);
    });

    testWidgets('小螢幕（720×1280）也不溢出、Skip 按得到', (tester) async {
      await pumpCard(
        tester,
        RestedScreen(
          date: '2026-11-12',
          store: MorningRatingStore(InMemoryKeyValueStore()),
        ),
        size: const Size(720, 1280),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('rested-skip')));
      expect(find.byKey(const Key('rested-skip')).hitTestable(), findsOneWidget);
    });
  });
}
