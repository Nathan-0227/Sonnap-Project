// 睡眠小知識：每一條都要引得出已經核對過的文獻。
//
// 這個專案誤植過兩次第一作者（Troxel/Iskander、Mason/Czeisler），
// 兩次都是「看起來很像、查了才發現不對」。所以這裡不相信寫在 Dart 裡的
// 作者名——拿去已經核對過的書目裡對，找不到就紅。
//
// 已驗證的書目：Research-Background/Garmin手錶分數.md 與 db.py 的
// 挑戰 literature_ref（測試在 app/ 底下跑，所以路徑是 ../）。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/content/sleep_basics.dart';
import 'package:app/models/sleep_session.dart';
import 'package:app/screens/report_screen.dart';
import 'package:app/services/lights_out.dart';
import 'package:app/services/pre_bed_apps.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:app/services/usage_stats.dart';

List<String> verifiedLines() => [
      ...File('../Research-Background/Garmin手錶分數.md').readAsLinesSync(),
      ...File('../db.py').readAsLinesSync(),
    ];

/// 名字出現在**行首**（前面只能有引號、空白、清單符號）。書目一律以第一作者開頭。
bool startsWithAuthor(String line, String author) =>
    RegExp(r'^\W*' + RegExp.escape(author) + r'\b').hasMatch(line);

class _ImmediateRepository implements SleepRepository {
  final SleepSession session;
  const _ImmediateRepository(this.session);

  @override
  Future<SleepSession> load() async => session;
}

/// 三個方法都要攔，少一個 widget test 就會卡在真的 MethodChannel 上。
class _SilentUsageStats extends UsageStatsService {
  const _SilentUsageStats();

  @override
  Future<UsageStatsResult> queryYesterday({int limit = 5}) async =>
      const UsageStatsResult(UsageStatsStatus.unsupported);

  @override
  Future<LightsOutResult> lightsOut({
    Duration window = kLightsOutWindow,
    int minQuietMinutes = kMinQuietMinutes,
    DateTime? now,
  }) async =>
      const LightsOutResult(LightsOutStatus.unsupported);

  @override
  Future<PreBedResult> preBed({
    required LightsOutResult lightsOut,
    Map<String, String> labels = const {},
    Duration window = kPreBedWindow,
  }) async =>
      const PreBedResult();
}

void main() {
  group('出處', () {
    test('行首比對本身是對的（反向對照）', () {
      // 這一條存在，是因為上一版的正規表示式寫壞了（\b 變成退格字元），
      // 導致**所有**條目都找不到——變異測試看起來全紅，其實基準本身就是紅的。
      expect(startsWithAuthor('Windred DP, Burns AC. Sleep. 2024', 'Windred'), isTrue);
      expect(startsWithAuthor('Windred DP, Burns AC. Sleep. 2024', 'Burns'), isFalse);
      expect(startsWithAuthor('            "Kroese et al. (2014) Bedtime', 'Kroese'), isTrue);
    });

    test('每一條的第一作者＋年份，在已驗證的書目裡找得到——而且真的是**第一**作者', () {
      // ⚠️ 只看「同一行有這個名字」不夠：共同作者也會在同一行。
      //    變異測試第一次跑時就是這樣漏掉的——把 Windred 那篇的第一作者換成
      //    Burns（該篇的共同作者），測試照樣過。那正是 Troxel/Iskander 那一類錯。
      final lines = verifiedLines();
      for (final b in kSleepBasics) {
        final found = lines.any((l) => startsWithAuthor(l, b.firstAuthor) && l.contains('${b.year}'));
        expect(found, isTrue,
            reason: '${b.id}: 找不到以「${b.firstAuthor}」開頭、含 ${b.year} 的書目。'
                '要新增一條，先把文獻寫進 Research-Background 的書目');
      }
    });

    test('卡片上的出處跟第一作者、年份對得起來', () {
      for (final b in kSleepBasics) {
        expect(b.source, startsWith(b.firstAuthor), reason: b.id);
        expect(b.source, contains('${b.year}'), reason: b.id);
      }
    });

    test('不寫成醫療宣稱', () {
      // 這是睡眠行為的背景知識，不是診療建議。
      final banned = RegExp(r'\b(cure|cures|treat|treats|treatment|diagnose|diagnosis|prescribe)\b',
          caseSensitive: false);
      for (final b in kSleepBasics) {
        expect(banned.hasMatch('${b.title} ${b.summary}'), isFalse, reason: b.id);
      }
    });

    test('id 不重複', () {
      final ids = kSleepBasics.map((b) => b.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('Insights 頁', () {
    late SleepSession sample;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      sample = await const AssetSleepRepository().load();
    });

    testWidgets('每一條的標題與出處都顯示出來', (tester) async {
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: ReportScreen(
          repository: _ImmediateRepository(sample),
          usageStats: const _SilentUsageStats(),
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('Sleep basics'), findsOneWidget);
      for (final b in kSleepBasics) {
        expect(find.text(b.title), findsOneWidget, reason: b.id);
        expect(find.text(b.source), findsOneWidget,
            reason: '${b.id}: 出處一定要跟著顯示——沒有出處的「小知識」就只是一句話');
      }
    });
  });
}
