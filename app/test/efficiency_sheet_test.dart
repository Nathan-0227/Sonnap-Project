// 早晨報告 Efficiency 點開（2026-11-15 使用者定）：這一晚怎麼算的＋一週依種類畫實心／空心。
import 'dart:convert';
import 'dart:io';

import 'package:app/services/camera_insights.dart';
import 'package:app/services/morning_report.dart';
import 'package:app/services/user_identity.dart';
import 'package:app/widgets/efficiency_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime t(String s) => DateTime.parse(s);

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 380, height: 1000, child: child)),
);

String textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

// basis 字串故意用哨兵：Dart 不能寫死 basis，種類要靠 behavior 自己帶的 *_basis 對出來
const behavior = {
  'measured_efficiency': 93.2,
  'measured_efficiency_basis': 'SENT-measured',
  'watch_wake_efficiency': 95.5,
  'watch_wake_efficiency_basis': 'SENT-watch-wake',
};

void main() {
  group('純函式', () {
    test('種類靠 behavior 的 *_basis 對，不寫死 basis 字串', () {
      expect(
        efficiencyKindOf('SENT-measured', behavior),
        EfficiencyKind.buttons,
      );
      expect(
        efficiencyKindOf('SENT-watch-wake', behavior),
        EfficiencyKind.startToWatchWake,
      );
      expect(
        efficiencyKindOf('SENT-other', behavior),
        EfficiencyKind.watchOnly,
      );
      expect(efficiencyKindOf('SENT-other', null), EfficiencyKind.watchOnly);
      expect(efficiencyKindOf(null, behavior), isNull);
    });

    test('分母的兩個時刻依種類', () {
      final bs = t('2026-11-14 03:20'), be = t('2026-11-14 09:00');
      final a = t('2026-11-14 03:33'), w = t('2026-11-14 09:51');
      final b = countedSpan(
        EfficiencyKind.buttons,
        bedStart: bs,
        bedEnd: be,
        asleepAt: a,
        wokeAt: w,
      )!;
      expect(
        (b.from, b.to, b.fromName, b.toName),
        (bs, be, 'Start sleep', 'Out of bed'),
      );
      final s = countedSpan(
        EfficiencyKind.startToWatchWake,
        bedStart: bs,
        asleepAt: a,
        wokeAt: w,
      )!;
      expect((s.from, s.to), (bs, w));
      final o = countedSpan(EfficiencyKind.watchOnly, asleepAt: a, wokeAt: w)!;
      expect((o.from, o.to, o.fromName), (a, w, 'watch asleep'));
      expect(countedSpan(EfficiencyKind.buttons, bedStart: bs), isNull);
    });

    test('照抄數字：不四捨五入，只把 100.0 寫成 100', () {
      expect(effNumber(95.9), '95.9');
      expect(effNumber(100.0), '100');
      expect(effNumber(82.35), '82.35');
    });

    test('一週標題：各種各幾晚，照 ①②③ 排，沒有的那種不寫', () {
      expect(
        effWeekCountLines([
          const EfficiencyNight(99, EfficiencyKind.watchOnly, 'Watch only'),
          null,
          const EfficiencyNight(
            93.2,
            EfficiencyKind.buttons,
            'From your sleep buttons',
          ),
          const EfficiencyNight(100, EfficiencyKind.watchOnly, 'Watch only'),
        ]),
        ['1 night · From your sleep buttons', '2 nights · Watch only'],
      );
    });

    test('⚠️ 後端沒給名字的那一種不寫——Dart 不自己取名', () {
      expect(
        effWeekCountLines([
          const EfficiencyNight(99, EfficiencyKind.watchOnly, null),
          const EfficiencyNight(
            93.2,
            EfficiencyKind.buttons,
            'From your sleep buttons',
          ),
        ]),
        ['1 night · From your sleep buttons'],
      );
    });
  });

  group('畫面', () {
    testWidgets('這一晚：數字照抄、名字、分子分母、兩個時刻；① 不出現提示', (tester) async {
      await tester.pumpWidget(
        host(
          EfficiencyView(
            value: 94.5,
            label: 'From your sleep buttons',
            kind: EfficiencyKind.buttons,
            caveat: 'SENTINEL-caveat',
            asleepMinutes: 359,
            span: countedSpan(
              EfficiencyKind.buttons,
              bedStart: t('2026-11-14 03:20'),
              bedEnd: t('2026-11-14 09:40'),
            ),
          ),
        ),
      );
      expect(textOf(tester, 'eff-value'), '94.5%');
      expect(textOf(tester, 'eff-label'), 'From your sleep buttons');
      expect(textOf(tester, 'eff-minutes'), '5h 59m asleep of 6h 20m counted');
      expect(
        textOf(tester, 'eff-span'),
        'Start sleep 03:20 → Out of bed 09:40',
      );
      expect(textOf(tester, 'eff-caveat'), 'Efficiency - SENTINEL-caveat');
      expect(find.byKey(const Key('eff-hint')), findsNothing);
      // 不畫 85% 線、不判斷好壞
      expect(find.textContaining('85'), findsNothing);
      expect(find.textContaining('Basis:'), findsNothing);
      // 沒有一週資料 → 下半不出現
      expect(find.byKey(const Key('eff-legend')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('② ③ 的晚上多一行去按按鈕的提示', (tester) async {
      for (final k in [
        EfficiencyKind.startToWatchWake,
        EfficiencyKind.watchOnly,
      ]) {
        await tester.pumpWidget(host(EfficiencyView(value: 99, kind: k)));
        expect(textOf(tester, 'eff-hint'), kEffButtonsHint, reason: '$k');
      }
    });

    testWidgets('一週：依種類畫實心／半實心／空心；照抄數字；沒資料寫 —；不算平均', (tester) async {
      await tester.pumpWidget(
        host(
          EfficiencyView(
            value: 99.47,
            kind: EfficiencyKind.watchOnly,
            week: effWeek({
              '2026-11-14': const EfficiencyNight(
                99.47,
                EfficiencyKind.watchOnly,
                'Watch only',
              ),
              '2026-11-13': const EfficiencyNight(
                100,
                EfficiencyKind.buttons,
                'From your sleep buttons',
              ),
              '2026-11-10': const EfficiencyNight(
                95.9,
                EfficiencyKind.buttons,
                'From your sleep buttons',
              ),
              '2026-11-09': const EfficiencyNight(
                90.7,
                EfficiencyKind.startToWatchWake,
                'Start sleep to watch wake',
              ),
            }, '2026-11-14'),
          ),
        ),
      );
      expect(
        find.byKey(const Key('eff-week-fill-2026-11-14-watchOnly')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('eff-week-fill-2026-11-13-buttons')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('eff-week-fill-2026-11-09-startToWatchWake')),
        findsOneWidget,
      );
      expect(textOf(tester, 'eff-week-value-2026-11-13'), '100');
      expect(textOf(tester, 'eff-week-value-2026-11-10'), '95.9');
      expect(textOf(tester, 'eff-week-value-2026-11-12'), '—');
      expect(find.text('2 nights · From your sleep buttons'), findsOneWidget);
      expect(find.text('1 night · Start sleep to watch wake'), findsOneWidget);
      expect(find.text('1 night · Watch only'), findsOneWidget);
      expect(find.textContaining('Average'), findsNothing);
      expect(find.textContaining('week before'), findsNothing);
      expect(find.byKey(const Key('eff-legend')), findsOneWidget);
      // 空心（③）沒有填色、實心（①）有
      BoxDecoration deco(String key) =>
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: find.byKey(Key(key)),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(deco('eff-week-fill-2026-11-14-watchOnly').color, isNull);
      expect(deco('eff-week-fill-2026-11-13-buttons').color, isNotNull);
      // 0–100%：100 那根比 95.9 那根高
      final h100 = tester
          .getSize(find.byKey(const Key('eff-week-fill-2026-11-13-buttons')))
          .height;
      final h959 = tester
          .getSize(find.byKey(const Key('eff-week-fill-2026-11-10-buttons')))
          .height;
      expect(h100, greaterThan(h959));
      expect(tester.takeException(), isNull);
    });
  });

  group('/insights → 每晚進分數的效率', () {
    late HttpServer server;
    HttpOverrides? saved;
    setUp(() async {
      saved = HttpOverrides.current;
      HttpOverrides.global = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode({
            'behavior': {
              'history': [
                {'date': '2026-11-13', ...behavior},
              ],
            },
            'wearable': {
              'history': [
                {
                  'date': '2026-11-13',
                  'sleep_efficiency': 100.0,
                  'composition': {
                    'efficiency_basis': 'SENT-measured',
                    'efficiency_label': 'From your sleep buttons',
                  },
                },
                {
                  'date': '2026-11-14',
                  'sleep_efficiency': 99.47,
                  'composition': {
                    'efficiency_basis': 'SENT-watch-only',
                    'efficiency_label': 'Watch only',
                  },
                },
                {
                  'date': '2026-11-12',
                  'sleep_efficiency': 98.0,
                  'composition': null,
                },
              ],
            },
            'camera': null,
          }),
        );
        req.response.close();
      });
    });
    tearDown(() async {
      await server.close(force: true);
      HttpOverrides.global = saved;
    });

    test('跟報告格子同一支挑數字：① 用按鈕那個（93.2，不是手錶的 100）；效率沒算的晚上不收', () async {
      final r = await CameraInsightsService(
        baseUrl: 'http://127.0.0.1:${server.port}',
        identity: const BuildTimeUserIdentity(overrideId: 'stub'),
      ).load();
      final n13 = r.efficiencyNights['2026-11-13']!;
      expect(
        (n13.value, n13.kind, n13.label),
        (93.2, EfficiencyKind.buttons, 'From your sleep buttons'),
      );
      final n14 = r.efficiencyNights['2026-11-14']!;
      expect((n14.value, n14.kind), (99.47, EfficiencyKind.watchOnly));
      expect(r.efficiencyNights.containsKey('2026-11-12'), isFalse);
    });
  });
}
