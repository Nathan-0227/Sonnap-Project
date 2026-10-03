import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/sleep_session.dart';
import 'package:app/screens/report_screen.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/lights_out.dart';
import 'package:app/services/pre_bed_apps.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:app/services/usage_stats.dart';

/// 守「分數組成與警語」那一段的**四個會安靜說謊的地方**：
///
/// 1. **警語的文字必須照抄後端。** 唯一定義處是 `score_claim.py`；在 Dart 這邊
///    自己寫一份，兩份漂移時不會有任何錯誤訊息，使用者會在 App 與 API 看到
///    不同的警語。這裡用哨兵字串驗證「畫面上的字真的來自資料」。
/// 2. **`caveats` 與 `unscored` 不能併成一段。** unscored 是「沒進分數」，
///    caveats 是「進了分數但門檻效度存疑」。併起來會讓人以為有警語的項目
///    沒計分——那是反過來的。
/// 3. **`primary_component` 不得寫死成 duration。** 它是後端的判斷；
///    寫死的話，後端哪天改成別的分項，畫面會繼續講一個不再為真的宣稱。
/// 4. **沒有 `composition` 時整段不顯示。** 舊的打包檔沒這個欄位，
///    退回「四項等權」那種預設敘述等於對使用者謊稱分數的可信度。

/// 折疊開關的字。⚠️ 與 `report_screen.dart` 的 `_compositionToggleLabel`
/// 逐字相同（那邊是 private，不能 import）。改了那邊這裡會 findsNothing 而紅，
/// 這是刻意的——反向對照就靠它判斷「整段在不在」。
const _toggleLabel = 'How this score is put together';

/// 哨兵字串：只存在於這支測試的假 payload 裡。
/// 畫面上出現它，才證明那段字是從資料來的而不是 Dart 寫死的。
const _sentinelCaveat =
    'SENTINEL-CAVEAT only this test payload contains this wording';
const _sentinelReason =
    'SENTINEL-REASON only this test payload contains this wording';
const _sentinelNote =
    'SENTINEL-NOTE only this test payload contains this wording';

class _ImmediateRepository implements SleepRepository {
  final SleepSession session;
  const _ImmediateRepository(this.session);

  @override
  Future<SleepSession> load() async => session;
}

/// ⚠️ 簽名要與 `UsageStatsService` 逐字相同（含具名參數與預設值），
///    照抄 `camera_card_test.dart` 那一份。
class _FakeUsageStats extends UsageStatsService {
  const _FakeUsageStats();

  @override
  bool get isSupported => true;

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

  @override
  Future<void> openSettings() async {}
}

Map<String, Object?> _composition({
  List<String> scored = const ['duration', 'waso'],
  int scoredWeight = 55,
  String? primary = 'duration',
  List<Map<String, String>> caveats = const [
    {'component': 'waso', 'caveat': _sentinelCaveat},
  ],
  List<Map<String, String>> unscored = const [
    {'component': 'efficiency', 'reason': _sentinelReason},
  ],
}) {
  return {
    'scored': scored,
    'unscored': unscored,
    'scored_weight': scoredWeight,
    'primary_component': primary,
    'caveats': caveats,
    'note': _sentinelNote,
  };
}

void main() {
  late Map<String, dynamic> rawPayload;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // ⚠️ 在 setUpAll 讀：widget test 的假時間不會推進真正的檔案 I/O，
    //    寫在 testWidgets 內會卡到逾時（camera_card_test.dart 同一個理由）。
    rawPayload = jsonDecode(
      await rootBundle.loadString(AssetSleepRepository.assetPath),
    ) as Map<String, dynamic>;
  });

  /// 真實打包檔，只換掉 `scoring.composition`。
  /// [composition] 給 null 代表**整個欄位拿掉**（模擬舊的打包檔）。
  SleepSession sessionWith(Map<String, Object?>? composition) {
    final json = jsonDecode(jsonEncode(rawPayload)) as Map<String, dynamic>;
    final scoring = (json['scoring'] as Map).cast<String, dynamic>();
    if (composition == null) {
      scoring.remove('composition');
    } else {
      scoring['composition'] = composition;
    }
    json['scoring'] = scoring;
    return SleepSession.fromJson(json);
  }

  /// 真實打包檔，但 history 只留最後兩晚，並換掉它們的 composition。
  /// 兩晚的日期相鄰，所以預設的 30 天期間一定兩晚都看得到。
  SleepSession sessionWithTwoNights(int olderWeight, int newerWeight) {
    final json = jsonDecode(jsonEncode(rawPayload)) as Map<String, dynamic>;
    final history = (json['history'] as List).cast<Map<String, dynamic>>();
    final two = history.sublist(history.length - 2);
    two[0]['composition'] = _composition(scoredWeight: olderWeight);
    two[1]['composition'] = _composition(scoredWeight: newerWeight);
    json['history'] = two;
    return SleepSession.fromJson(json);
  }

  /// 真實打包檔，但**每一晚**的組成都一樣（反向對照用）。
  SleepSession sessionWithUniformHistory(int weight) {
    final json = jsonDecode(jsonEncode(rawPayload)) as Map<String, dynamic>;
    for (final night in (json['history'] as List).cast<Map<String, dynamic>>()) {
      night['composition'] = _composition(scoredWeight: weight);
    }
    return SleepSession.fromJson(json);
  }

  Future<void> pump(WidgetTester tester, SleepSession session) async {
    // 畫面很長，畫布太小會滿版溢位而蓋掉要驗的東西。
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: ReportScreen(
        repository: _ImmediateRepository(session),
        usageStats: const _FakeUsageStats(),
        bedMarks: BedMarkStore(InMemoryKeyValueStore()),
        cameraInsights: null,
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
  }

  /// 展開折疊區。警語預設收起來（那段很長），要點開才看得到。
  Future<void> expand(WidgetTester tester) async {
    final toggle = find.text(_toggleLabel);
    expect(toggle, findsOneWidget, reason: '找不到折疊開關就什麼都驗不到');
    await tester.ensureVisible(toggle);
    await tester.pump();
    await tester.tap(toggle);
    await tester.pump();
  }

  group('【1】預設就看得見的那一行', () {
    testWidgets('primary_component 照後端，不得寫死成 duration', (tester) async {
      // 後端說以 REM 為主（現實不會這樣，正是要證明畫面沒有寫死）。
      await pump(tester, sessionWith(_composition(primary: 'rem')));

      expect(find.textContaining('Mainly measures rem sleep'), findsOneWidget,
          reason: '以哪一項為主是後端的判斷，照抄就好');
      expect(
          find.textContaining('Mainly measures sleep duration'), findsNothing,
          reason: '寫死 duration 的話，後端改了畫面會繼續講不再為真的宣稱');
    });

    testWidgets('scored_weight 照抄，Dart 不重算配分', (tester) async {
      // duration(30) + waso(25) = 55，但後端說 42 → 畫面要顯示 42。
      // ⚠️ Dart 這邊**不該有**一份配分表；有的話就是第二個定義處。
      await pump(
          tester,
          sessionWith(
            _composition(scored: ['duration', 'waso'], scoredWeight: 42),
          ));

      expect(find.textContaining('Scored on 42 of 100 points'), findsOneWidget);
      expect(find.textContaining('55 of 100'), findsNothing,
          reason: 'Dart 自己把 30+25 加起來，就是在維護第二份配分表');
    });
  });

  group('【2】警語與「沒計分」要分得開', () {
    testWidgets('兩組各有自己的標題，而且標題不一樣', (tester) async {
      await pump(tester, sessionWith(_composition()));
      await expand(tester);

      expect(find.textContaining('Counted in the score, with a known limit:'),
          findsOneWidget,
          reason: '有警語的項目是「算進去了但門檻存疑」');
      expect(find.textContaining('Not counted in the score tonight:'),
          findsOneWidget,
          reason: '沒計分的項目要分開講，不然會被當成有警語的那一組');
    });

    testWidgets('有警語的項目仍然列在計分清單裡，沒計分的不列', (tester) async {
      await pump(tester, sessionWith(_composition()));

      // 整串精確比對：這同時證明 efficiency（沒計分）沒有混進計分清單。
      expect(
        find.textContaining(
          'Scored on 55 of 100 points: '
          'Sleep duration, Time awake during the night',
        ),
        findsOneWidget,
        reason: 'waso 有警語但照樣計分，efficiency 則完全不在清單裡',
      );
    });
  });

  group('【3】文字必須照抄後端', () {
    testWidgets('警語、原因、整段 note 都是資料裡的原文', (tester) async {
      await pump(tester, sessionWith(_composition()));
      await expand(tester);

      expect(find.textContaining(_sentinelCaveat), findsOneWidget,
          reason: '警語的字出自 score_claim.py，Dart 不得改寫或節錄');
      expect(find.textContaining(_sentinelReason), findsOneWidget,
          reason: '不計分的原因同理');
      expect(find.textContaining(_sentinelNote), findsOneWidget,
          reason: 'note 是「分數重新正規化過」那段說明，不能省');
    });

    testWidgets('沒見過的分項鍵名照原樣顯示，不得悄悄消失', (tester) async {
      await pump(
          tester,
          sessionWith(_composition(
            scored: ['duration', 'snoring'],
            scoredWeight: 40,
            caveats: const [
              {'component': 'snoring', 'caveat': _sentinelCaveat},
            ],
          )));
      await expand(tester);

      expect(find.textContaining('snoring'), findsWidgets,
          reason: '後端日後新增分項時，畫面上少一項不會有任何錯誤訊息');
    });
  });

  group('【4】沒有 composition 時', () {
    testWidgets('整段不顯示，而且不得退回任何預設敘述', (tester) async {
      await pump(tester, sessionWith(null));

      expect(find.text(_toggleLabel), findsNothing,
          reason: '舊的打包檔沒這個欄位，什麼都不該顯示');
      expect(find.textContaining('Mainly measures'), findsNothing);
      // ⚠️ 只認卡片那一行（它後面接著分項清單，所以有「: 」）。
      //    拿「of 100 points」當標記會誤判到趨勢圖的註腳——那一行講的是
      //    history 每晚的組成，與 scoring.composition 在不在無關。
      expect(find.textContaining('of 100 points: '), findsNothing,
          reason: '憑空生一個組成清單 = 對使用者謊稱分數的可信度');
    });

    testWidgets('反向對照：分數本身照樣顯示（卡片沒被弄壞）', (tester) async {
      await pump(tester, sessionWith(null));

      expect(find.text('/100'), findsOneWidget,
          reason: '沒有 composition 只是少一段說明，不是整張卡不能用');
    });
  });

  group('【6】趨勢圖點到的那一晚', () {
    /// 點趨勢圖。[fromLeft] 是距離圖形左緣的像素，決定選到第幾晚。
    Future<void> tapTrend(WidgetTester tester, double fromLeft) async {
      final graph = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is SleepTrendPainter,
      );
      expect(graph, findsOneWidget, reason: '找不到趨勢圖就點不到任何一晚');
      final box = tester.getRect(graph);
      await tester.tapAt(Offset(box.left + fromLeft, box.center.dy));
      await tester.pump();
    }

    testWidgets('顯示的是**那一晚**的 scored_weight，不是最新那晚的', (tester) async {
      // 兩個數字刻意都不是任何分項配分的和，照抄才可能出現。
      await pump(tester, sessionWithTwoNights(42, 99));

      await tapTrend(tester, 30);
      expect(find.textContaining('Scored on 42 of 100 pts'), findsOneWidget,
          reason: '點左邊選到的是較舊那一晚');
      expect(find.textContaining('99 of 100 pts'), findsNothing);

      // ⚠️ 用圖形的實際寬度，不要寫死一個大數字——點到畫面外不會報錯，
      //    只會「沒選到」，而上一次的選擇還留著，看起來像顯示錯了那一晚。
      await tapTrend(tester, tester.getRect(find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is SleepTrendPainter,
          )).width -
          10);
      expect(find.textContaining('Scored on 99 of 100 pts'), findsOneWidget,
          reason: '點右邊換成較新那一晚——每晚各自一份組成');
    });

    testWidgets('沒有 composition 的夜晚：不顯示，也不顯示 0', (tester) async {
      // ⚠️ 一條測試只 pump 一次：同型別的 widget 第二次 pump 會**重用
      //    State**，`_sessionFuture` 還是 initState 時建的那個，
      //    第二份資料根本沒進畫面（這個坑踩過一次，症狀是測試莫名其妙地紅）。
      // sessionWith(null) 只拿掉 scoring.composition，history 的還在，
      // 所以這裡要自己把 history 的也拿掉，才是「舊打包檔」的樣子。
      final json = jsonDecode(jsonEncode(rawPayload)) as Map<String, dynamic>;
      for (final n in (json['history'] as List).cast<Map<String, dynamic>>()) {
        n.remove('composition');
      }
      await pump(tester, SleepSession.fromJson(json));

      await tapTrend(tester, 30);
      expect(find.textContaining('of 100 pts'), findsNothing,
          reason: '沒有資料就什麼都不說，不要畫成 0 分');
    });
  });

  group('【7】期間內組成不一致時要講出來', () {
    testWidgets('真實打包檔的預設 30 天裡就有兩種組成 → 要出現範圍', (tester) async {
      final session = SleepSession.fromJson(
        jsonDecode(jsonEncode(rawPayload)) as Map<String, dynamic>,
      );
      await pump(tester, session);

      // 實測 83 晚：69 晚算四項（75）、14 晚手錶沒測到 REM（65）。
      expect(find.textContaining('65-75 of 100 points'), findsOneWidget,
          reason: '這一行就是「分數不能逐夜直接比」的具體證據');
      expect(find.textContaining('depending on what each night measured'),
          findsOneWidget);
    });

    testWidgets('⚠️ 反向對照：每晚組成都一樣時不得出現', (tester) async {
      await pump(tester, sessionWithUniformHistory(75));

      expect(find.textContaining('depending on what each night measured'),
          findsNothing,
          reason: '一致時還印等於每次都在喊狼來了，真的不一致時就沒人看了');
    });
  });

  group('【5】真實打包檔', () {
    testWidgets('打包檔自己就帶著 composition，而且畫面顯示的是它的原文',
        (tester) async {
      final session = SleepSession.fromJson(
        jsonDecode(jsonEncode(rawPayload)) as Map<String, dynamic>,
      );
      final composition = session.scoring.composition;
      expect(composition, isNotNull,
          reason: 'build_app_payload.py 要輸出 composition；'
              '沒有的話這條測試以下都是假性通過');

      await pump(tester, session);

      expect(find.textContaining('Mainly measures'), findsOneWidget);
      await expand(tester);

      // 逐條比對打包檔裡的原文。這條把 pipeline → payload → 畫面整條接起來。
      expect(composition!.caveats, isNotEmpty,
          reason: '實測的夜晚至少有 waso/deep/rem 三條警語');
      for (final caveat in composition.caveats) {
        expect(find.textContaining(caveat.text), findsOneWidget,
            reason: '${caveat.component} 的警語要逐字出現');
      }
      for (final note in composition.unscored) {
        expect(find.textContaining(note.text), findsOneWidget,
            reason: '${note.component} 不計分的原因要逐字出現');
      }
    });
  });
}
