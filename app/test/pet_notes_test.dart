// 寵物 notes（2026-11-17 使用者 grill 後定，取代夢境日記與報告上的 From your buddy）：
// 草地上那本日記點開是 AI 的總結＋從清單挑的建議，全部照抄 `/night-summary`。
//
// 守的東西（壞掉時都不會報錯）：
//   - 🔴 首頁**只用 generate=false**：AI 那段一定在起床自評之後才生成（它會讀自評的標籤）
//   - 紅點跟著 **version** 走：內容換了（早上只有原句、下午多了總結）要再亮一次
//   - 畫面上的字全部照抄後端（哨兵字串），Dart 不產生任何建議
//   - 沒有內容、舊版後端、日期對不上 → 日記本不出現（不拿舊的 text 冒充）
//   - 報告上不再有 From your buddy 那張卡
import 'dart:convert';
import 'dart:math' as math;

import 'package:app/models/sleep_session.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/screens/morning_report_screen.dart';
import 'package:app/services/alarm.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/morning_report.dart';
import 'package:app/services/pet_notes.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:app/widgets/notes_book.dart';
import 'package:app/widgets/pet_notes_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repo implements SleepRepository {
  final SleepSession session;
  const _Repo(this.session);
  @override
  Future<SleepSession> load() async => session;
}

class _NoAlarm implements AlarmScheduler {
  @override
  Future<void> schedule(DateTime at) async {}
  @override
  Future<void> cancel() async {}
  @override
  Future<bool> canRing() async => true;
  @override
  Future<void> requestPermission() async {}
  @override
  Future<void> openSettings() async {}
}

/// 假的後端：記下每次要 notes 時帶的 generate。
class _Source implements MorningReportSource {
  Map<String, dynamic>? notes;

  /// 依日期給不同的 notes；有給就以它為準（沒列到的日期回 null），沒給就每天都回 [notes]。
  Map<String, Map<String, dynamic>?>? byDate;
  final generateFlags = <bool>[];
  final asked = <String>[];
  _Source(this.notes, {this.byDate});

  @override
  Future<Map<String, dynamic>?> fetchNight(String date) async => null;

  @override
  Future<Map<String, dynamic>?> fetchSummary(String date,
      {bool generate = true}) async {
    generateFlags.add(generate);
    asked.add(date);
    final b = byDate;
    return b != null ? b[date] : notes;
  }
}

const _today = '2026-11-13';

// 哨兵字串：畫面上出現的字必須就是後端給的這幾句
const _summary = 'SENTINEL-summary we slept 7h 2m.';
const _tipText = 'SENTINEL-tip keep coffee before noon.';
const _noteText = 'SENTINEL-note being unwell needs rest.';

Map<String, dynamic> notesJson({
  String date = _today,
  String status = 'ok',
  String? source = 'llm',
  String? summary = _summary,
  String version = 'v1',
  List<Map<String, dynamic>>? tips,
}) =>
    {
      'date': date,
      'status': status,
      'source': source,
      'summary': summary,
      'version': version,
      'tips': tips ??
          [
            {'id': 'T3', 'kind': 'tip', 'text': _tipText, 'original': 'orig T3'},
            {'id': 'T9', 'kind': 'note', 'text': _noteText, 'original': 'orig T9'},
          ],
    };

Future<void> frames(WidgetTester tester, [int n = 8]) async {
  // 小狗一直在動，pumpAndSettle 等不到停
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

String? textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data;

void main() {
  late SleepSession session;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    session = SleepSession.fromJson(
        jsonDecode(await rootBundle.loadString(AssetSleepRepository.assetPath))
            as Map<String, dynamic>);
  });

  group('解析（照抄後端）', () {
    test('總結、建議、version 照抄；tip／note 分開', () {
      final n = PetNotes.fromJson(notesJson(), date: _today)!;
      expect(n.summary, _summary);
      expect(n.tips.map((t) => t.text), [_tipText, _noteText]);
      expect(n.tips.map((t) => t.isNote), [false, true]);
      expect(n.version, 'v1');
    });

    test('waiting 也收（手錶還沒到，只有行為那幾條原句）', () {
      final n = PetNotes.fromJson(
          notesJson(status: 'waiting', source: null, summary: null), date: _today)!;
      expect((n.waiting, n.summary, n.tips.length), (true, null, 2));
    });

    test('⚠️ 沒有任何內容 → null（日記本不出現）', () {
      expect(
          PetNotes.fromJson(notesJson(summary: null, tips: []), date: _today), isNull);
    });

    test('⚠️ 舊版後端（只有 text／tip，沒有 tips／version）→ null，不拿舊的 text 冒充', () {
      final old = {
        'date': _today,
        'status': 'ok',
        'source': 'fallback',
        'text': 'Your buddy waited up a little.',
        'tip': {'id': 'T7', 'kind': 'tip', 'text': 'x'},
      };
      expect(PetNotes.fromJson(old, date: _today), isNull);
    });

    test('有 tips 卻沒有 version → null（沒有 version 就判斷不了紅點，也不讓它當掉）', () {
      final noVersion = notesJson()..remove('version');
      expect(PetNotes.fromJson(noVersion, date: _today), isNull);
    });

    test('日期對不上 → null', () {
      expect(PetNotes.fromJson(notesJson(date: '2026-11-12'), date: _today), isNull);
    });
  });

  group('首頁', () {
    late InMemoryKeyValueStore kv;
    setUp(() => kv = InMemoryKeyValueStore());

    Future<_Source> pumpHome(WidgetTester tester, Map<String, dynamic>? notes,
        {Size size = const Size(1200, 4200),
        double dpr = 3.0,
        Map<String, Map<String, dynamic>?>? byDate,
        DateTime? now}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      final source = _Source(notes, byDate: byDate);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            repository: _Repo(session),
            bedMarks: BedMarkStore(kv),
            alarmScheduler: _NoAlarm(),
            morningReport: source,
            clock: () => now ?? DateTime(2026, 11, 13, 9),
          ),
        ),
      ));
      await frames(tester);
      return source;
    }

    testWidgets('有 notes → 草地上一本日記；🔴 首頁只用 generate=false（絕不觸發 AI）', (tester) async {
      final source = await pumpHome(tester, notesJson());
      expect(find.byKey(const Key('home-notes')), findsOneWidget);
      expect(find.byType(NotesBook), findsOneWidget);
      expect(source.generateFlags, isNotEmpty);
      expect(source.generateFlags.every((g) => g == false), isTrue,
          reason: 'AI 那段要在起床自評之後才生成，首頁一打開就生成會不含自評、還多花一次額度');
      expect(find.text(_summary), findsNothing, reason: '點開才看');
    });

    testWidgets('沒看過 → 紅點；點開 → 總結＋建議（照抄）＋日期；看過紅點消失並記住這個 version', (tester) async {
      await pumpHome(tester, notesJson());
      expect(find.byKey(const Key('notes-book-unread-dot')), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-notes')));
      await frames(tester);
      expect(find.byKey(const Key('pet-notes')), findsOneWidget);
      expect(find.text(kNotesTitle), findsOneWidget);
      expect(textOf(tester, 'pet-notes-summary'), _summary);
      expect(find.text(_tipText), findsOneWidget);
      expect(find.text(_noteText), findsOneWidget);
      expect(textOf(tester, 'pet-notes-date'), reportDateTitle(DateTime(2026, 11, 13)));
      Navigator.of(tester.element(find.byKey(const Key('pet-notes')))).pop();
      await frames(tester);
      expect(find.byKey(const Key('notes-book-unread-dot')), findsNothing);
      expect(await NotesReadStore(kv).isRead(_today, 'v1'), isTrue);
    });

    testWidgets('這個 version 已經看過 → 一打開就沒有紅點', (tester) async {
      await NotesReadStore(kv).markRead(_today, 'v1');
      await pumpHome(tester, notesJson());
      expect(find.byKey(const Key('notes-book-unread-dot')), findsNothing);
    });

    testWidgets('⚠️ 看過的是舊 version（例如早上只有原句）→ 內容換了紅點再亮', (tester) async {
      await NotesReadStore(kv).markRead(_today, 'v-morning');
      await pumpHome(tester, notesJson(version: 'v-afternoon'));
      expect(find.byKey(const Key('notes-book-unread-dot')), findsOneWidget);
    });

    // 2026-11-19 使用者定：今天這一晚沒內容就退回前一晚，只往回 1 晚。
    // 實例：凌晨 1 點（11-14）還沒睡，問「今天」問的是還沒開始的那一晚，原本日記本會消失到起床。
    testWidgets('⚠️ 過了午夜、今天這一晚還沒內容 → 顯示前一晚的 notes（日期寫前一晚、紅點記在前一晚）',
        (tester) async {
      final source = await pumpHome(tester, null,
          now: DateTime(2026, 11, 14, 1),
          byDate: {'2026-11-14': null, _today: notesJson()});
      expect(source.asked, ['2026-11-14', _today]);
      expect(source.generateFlags.every((g) => g == false), isTrue);
      expect(find.byKey(const Key('home-notes')), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-notes')));
      await frames(tester);
      expect(textOf(tester, 'pet-notes-summary'), _summary);
      expect(textOf(tester, 'pet-notes-date'), reportDateTitle(DateTime(2026, 11, 13)),
          reason: '標題下的日期要寫前一晚，看得出是哪一晚');
      Navigator.of(tester.element(find.byKey(const Key('pet-notes')))).pop();
      await frames(tester);
      expect(await NotesReadStore(kv).isRead(_today, 'v1'), isTrue);
    });

    testWidgets('今天這一晚有內容 → 用今天的，不問前一晚', (tester) async {
      final source = await pumpHome(tester, null, byDate: {
        _today: notesJson(),
        '2026-11-12': notesJson(date: '2026-11-12', summary: 'SENTINEL-old'),
      });
      expect(source.asked, [_today]);
      await tester.tap(find.byKey(const Key('home-notes')));
      await frames(tester);
      expect(textOf(tester, 'pet-notes-summary'), _summary);
    });

    testWidgets('⚠️ 只往回 1 晚：今天和前一晚都沒有 → 不出現，也不去找兩晚前的', (tester) async {
      final source = await pumpHome(tester, null, byDate: {
        _today: null,
        '2026-11-12': notesJson(summary: null, tips: [], date: '2026-11-12'),
        '2026-11-11': notesJson(date: '2026-11-11'),
      });
      expect(source.asked, [_today, '2026-11-12']);
      expect(find.byKey(const Key('home-notes')), findsNothing);
    });

    test('往回找用日曆日：月初往回是上個月最後一天', () {
      expect(homeNotesDates(DateTime(2026, 12, 1, 2)), ['2026-12-01', '2026-11-30']);
      expect(kHomeNotesLookbackNights, 1);
    });

    testWidgets('⚠️ 沒有內容、沒有後端 → 不出現日記本', (tester) async {
      await pumpHome(tester, notesJson(summary: null, tips: []));
      expect(find.byKey(const Key('home-notes')), findsNothing);
      await pumpHome(tester, null);
      expect(find.byKey(const Key('home-notes')), findsNothing);
    });

    testWidgets('⚠️ 日記本不蓋到小狗、心情標籤、等級徽章（實機大小）', (tester) async {
      await pumpHome(tester, notesJson(), size: const Size(1080, 2340), dpr: 2.625);
      final book = tester.getRect(find.byKey(const Key('notes-book')));
      final pet = tester.getRect(find.byKey(const Key('home-pet')));
      expect(book.left, greaterThan(pet.center.dx), reason: '在小狗右邊');
      expect(book.right, lessThanOrEqualTo(1080 / 2.625));
      for (final k in ['level-badge', 'mood-chip']) {
        final f = find.byKey(Key(k));
        if (f.evaluate().isEmpty) continue;
        expect(book.overlaps(tester.getRect(f)), isFalse, reason: k);
      }
    });
  });

  group('notes 頁', () {
    Future<void> pumpView(WidgetTester tester, Map<String, dynamic> json) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PetNotesView(notes: PetNotes.fromJson(json, date: _today)!),
        ),
      ));
      await frames(tester, 2);
    }

    testWidgets('tip 是燈泡、note 是 i；AI 寫的才有 AI 小字', (tester) async {
      await pumpView(tester, notesJson());
      expect(find.byKey(const Key('pet-notes-kind-tip')), findsOneWidget);
      expect(find.byKey(const Key('pet-notes-kind-note')), findsOneWidget);
      expect(find.byKey(const Key('pet-notes-ai-line')), findsOneWidget);
    });

    testWidgets('fallback → 沒有總結、沒有 AI 小字，只有原句', (tester) async {
      await pumpView(tester, notesJson(source: 'fallback', summary: null));
      expect(find.byKey(const Key('pet-notes-summary')), findsNothing);
      expect(find.byKey(const Key('pet-notes-ai-line')), findsNothing);
      expect(find.text(_tipText), findsOneWidget);
    });

    testWidgets('waiting → 說資料到了會多寫一點，不寫總結', (tester) async {
      await pumpView(tester, notesJson(status: 'waiting', source: null, summary: null));
      expect(find.text(kNotesWaitingLine), findsOneWidget);
      expect(find.byKey(const Key('pet-notes-summary')), findsNothing);
    });
  });

  group('早晨報告', () {
    Future<void> pumpReport(WidgetTester tester, MorningReport r,
        {void Function(String)? onNotesOpened,
        Future<bool> Function(String)? isNotesRead}) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: MorningReportScreen(
          initial: r,
          onNotesOpened: onNotesOpened,
          isNotesRead: isNotesRead,
        ),
      ));
      await frames(tester);
    }

    /// 日記本在一段時間裡最大歪幾度
    Future<double> maxTilt(WidgetTester tester) async {
      var most = 0.0;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final t = tester.widget<Transform>(find.byKey(const Key('notes-book-shake')));
        final m = t.transform.storage;
        most = math.max(most, math.atan2(m[1], m[0]).abs());
      }
      return most;
    }

    MorningReport report(Map<String, dynamic>? notes) {
      final date = session.history.last.date;
      final r = buildMorningReport(date: date, session: session);
      return notes == null ? r : r.withNotes({...notes, 'date': date});
    }

    testWidgets('有 notes → 右下草地上的日記本；⚠️ 不再有 From your buddy 那張卡', (tester) async {
      final opened = <String>[];
      await pumpReport(tester, report(notesJson()), onNotesOpened: opened.add);
      expect(find.byKey(const Key('report-notes')), findsOneWidget);
      expect(find.byKey(const Key('report-buddy')), findsNothing);
      expect(find.text('From your buddy'), findsNothing);
      expect(find.text(_summary), findsNothing, reason: '總結只在日記裡，不在報告上再放一次');
      final book = tester.getRect(find.byKey(const Key('report-notes')));
      final ring = tester.getRect(find.byKey(const Key('report-score')));
      expect(book.overlaps(ring), isFalse);
      await tester.tap(find.byKey(const Key('report-notes')));
      await frames(tester);
      expect(textOf(tester, 'pet-notes-summary'), _summary);
      expect(opened, ['v1'], reason: '首頁要知道看過的是哪個 version');
      expect(tester.takeException(), isNull);
    });

    testWidgets('還沒看過 → 會抖；點開之後就不抖', (tester) async {
      await pumpReport(tester, report(notesJson()), isNotesRead: (_) async => false);
      expect(find.byKey(const Key('notes-book-unread-dot')), findsOneWidget);
      expect(await maxTilt(tester), greaterThan(0.03));
      await tester.tap(find.byKey(const Key('report-notes')));
      await frames(tester);
      Navigator.of(tester.element(find.byKey(const Key('pet-notes')))).pop();
      await frames(tester);
      expect(await maxTilt(tester), 0);
      expect(find.byKey(const Key('notes-book-unread-dot')), findsNothing);
    });

    testWidgets('這個 version 看過了 → 不抖', (tester) async {
      await pumpReport(tester, report(notesJson()), isNotesRead: (v) async => v == 'v1');
      expect(await maxTilt(tester), 0);
      expect(find.byKey(const Key('notes-book-unread-dot')), findsNothing);
    });

    testWidgets('沒有 notes → 沒有日記本', (tester) async {
      await pumpReport(tester, report(null));
      expect(find.byKey(const Key('report-notes')), findsNothing);
    });
  });
}
