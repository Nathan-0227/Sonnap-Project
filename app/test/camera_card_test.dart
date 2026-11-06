import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/sleep_session.dart';
import 'package:app/screens/report_screen.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/camera_insights.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/lights_out.dart';
import 'package:app/services/pre_bed_apps.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:app/services/usage_stats.dart';

/// 守攝影機那張卡片的**三個會安靜說謊的地方**：
///
/// 1. **低於偵測下限時不得顯示 0。** 後端在那種情況回 null 並附上 floor，
///    畫面必須寫「≤ 10 min」。顯示 0 會被讀成「躺下就睡著」，而真值可能是
///    5 分鐘——那是整條路上最容易假裝自己很準的地方。
/// 2. **臥床時間是自述，入睡時刻才是偵測。** 兩者混在一起講，就等於宣稱
///    攝影機看到了人躺下（它沒有）。
/// 3. **不得出現任何分數。** 攝影機現行可計分項目是 0 項；畫面上冒出一個
///    分數就是第五代沒有引文的公式（設計紅線 2）。

/// 只屬於這張卡的標題。反向對照用它判斷「整張卡不存在」——
/// 拿「Time in bed」那種字去判斷會命中別的卡片。
const _cardTitle = 'Camera: Time in Bed & Sleep Onset';

class _ImmediateRepository implements SleepRepository {
  final SleepSession session;
  const _ImmediateRepository(this.session);

  @override
  Future<SleepSession> load() async => session;
}

/// ⚠️ 簽名要與 `UsageStatsService` 逐字相同（含具名參數與預設值），
///    照抄 `usage_stats_test.dart` 那一份。少一個具名參數就是 invalid_override，
///    而錯誤訊息會指向測試檔而不是這裡。
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

class _FakeCamera implements CameraInsightsSource {
  final CameraInsightsResult result;
  const _FakeCamera(this.result);

  @override
  Future<CameraInsightsResult> load() async => result;
}

const _note = 'Camera metrics are presentational only and never enter any '
    'score. Time in bed is SELF-REPORTED (recording start/stop), not detected.';

/// 09-11：潛伏期高於下限，有數字（實測 13.5 分）。
const _aboveFloor = CameraNight(
  date: '2026-09-11',
  bedStartAt: '2026-09-11T01:36:07',
  bedEndAt: '2026-09-11T07:11:22',
  timeInBedMinutes: 335.3,
  sleepOnsetAt: '2026-09-11T01:49:37',
  sleepOnsetLatencyMinutes: 13.5,
  belowFloor: false,
  floorMinutes: 10,
  eventsPerHour: 15.9,
  bedTimesProvenance: 'SELF_REPORTED_recording_start_stop',
  sleepOnsetProvenance: 'DETECTED_motion_density__n2_unvalidated',
);

/// 09-12：潛伏期低於下限 → 後端給 null + floor，**不是 0**。
const _belowFloor = CameraNight(
  date: '2026-09-12',
  bedStartAt: '2026-09-12T01:18:01',
  bedEndAt: '2026-09-12T11:29:28',
  timeInBedMinutes: 611.5,
  sleepOnsetAt: null,
  sleepOnsetLatencyMinutes: null,
  belowFloor: true,
  floorMinutes: 10,
  eventsPerHour: 11.7,
  bedTimesProvenance: 'SELF_REPORTED_recording_start_stop',
  sleepOnsetProvenance: 'DETECTED_motion_density__n2_unvalidated',
);

void main() {
  late SleepSession sample;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // ⚠️ 在 setUpAll 讀：widget test 的假時間不會推進真正的檔案 I/O，
    //    寫在 testWidgets 內會卡到逾時（usage_stats_test.dart 同一個理由）。
    sample = await const AssetSleepRepository().load();
  });

  Future<void> pump(WidgetTester tester, CameraInsightsSource? camera) async {
    // 畫面很長，畫布太小會滿版溢位而蓋掉要驗的東西。
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: ReportScreen(
        repository: _ImmediateRepository(sample),
        usageStats: const _FakeUsageStats(),
        bedMarks: BedMarkStore(InMemoryKeyValueStore()),
        cameraInsights: camera,
      ),
    ));
    // 有幾個 await 就要 pump 幾次。用迴圈而不是寫死次數。
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
  }

  group('低於偵測下限', () {
    testWidgets('⚠️ 要寫「≤ 10 min」，絕對不能寫 0', (tester) async {
      await pump(tester, const _FakeCamera(CameraInsightsResult(
        CameraInsightsStatus.ok,
        nights: [_belowFloor],
        note: _note,
      )));

      expect(find.textContaining('≤ 10 min'), findsWidgets,
          reason: '低於下限時只能說「最多 10 分鐘」');
      // ⚠️ 用精確比對，不能用 textContaining：畫面上別張卡片有「90 min」
      //    這種值，而它也包含「0 min」——寬鬆的比對會假性失敗。
      expect(find.text('0 min'), findsNothing,
          reason: '0 會被讀成躺下就睡著，而真值可能是 5 分鐘');
      expect(find.textContaining('upper bound - not zero'), findsWidgets,
          reason: '要主動解釋那個 ≤ 是什麼意思');
    });

    testWidgets('反向對照：高於下限就照實給數字', (tester) async {
      await pump(tester, const _FakeCamera(CameraInsightsResult(
        CameraInsightsStatus.ok,
        nights: [_aboveFloor],
        note: _note,
      )));

      expect(find.textContaining('14 min'), findsWidgets,
          reason: '13.5 分四捨五入成 14');
      expect(find.textContaining('≤'), findsNothing,
          reason: '有數字的夜晚不該出現上界的寫法');
    });
  });

  group('來源標籤：自述與偵測要分得開', () {
    testWidgets('臥床時間標成自述，入睡標成偵測', (tester) async {
      await pump(tester, const _FakeCamera(CameraInsightsResult(
        CameraInsightsStatus.ok,
        nights: [_aboveFloor],
        note: _note,
      )));

      expect(find.textContaining('self-reported'), findsWidgets,
          reason: '臥床時間是開錄影的時刻，不是攝影機看到人躺下');
      expect(find.textContaining('(detected)'), findsWidgets,
          reason: '入睡時刻才是偵測出來的');
    });

    testWidgets('⚠️ 卡片上不得出現分數，而且要主動說不計分', (tester) async {
      await pump(tester, const _FakeCamera(CameraInsightsResult(
        CameraInsightsStatus.ok,
        nights: [_aboveFloor, _belowFloor],
        note: _note,
      )));

      expect(find.textContaining('Camera score'), findsNothing);
      expect(find.textContaining('not part of any score'), findsWidgets,
          reason: '要主動講出來，不是預設讀者知道');
      // 最近一晚才是要顯示的那一晚（history 由舊到新）。
      expect(find.textContaining('Night of 2026-09-12'), findsWidgets);
    });
  });

  group('沒有資料時的表達', () {
    testWidgets('有後端但還沒有攝影機資料 → 明說沒有，不要畫 0', (tester) async {
      await pump(tester, const _FakeCamera(
        CameraInsightsResult(CameraInsightsStatus.ok),
      ));

      expect(find.textContaining('No camera nights yet'), findsWidgets);
      expect(find.text('0 min'), findsNothing);
    });

    testWidgets('連不到後端 → 說連不到，不要假裝沒有資料', (tester) async {
      await pump(tester, const _FakeCamera(
        CameraInsightsResult(CameraInsightsStatus.failed, error: 'boom'),
      ));

      expect(find.textContaining('Could not reach'), findsWidgets);
    });

    testWidgets('反向對照：沒設定後端時整張卡片不存在', (tester) async {
      await pump(tester, null);

      expect(find.text(_cardTitle), findsNothing,
          reason: '沒設定 API 是單機模式，不是降級，不該出現這張卡');
    });
  });

  // ──────────────────────────────────────────────────────────────
  // 動作片段（2026-11-07）。四件壞掉時不會報錯的事：
  //   1. 標籤與「沒有片段的原因」要**照抄後端**（camera_clips.py 是唯一定義處）
  //   2. 網址要接上 baseUrl，而且不能出現 `//`
  //   3. 舊版後端（沒有 clips 欄位）整段不出現，不是說「沒有片段」
  //   4. 指定某一晚卻沒有那晚時回 null，**不偷偷換成最近一晚**
  // ──────────────────────────────────────────────────────────────
  group('動作片段', () {
    // 哨兵字串：Dart 裡任何地方都不會自己寫出這兩句，畫面上出現就證明是照抄的。
    const sentinelLabel = '02:41 · moved for 6 s [from backend 7Q]';
    const sentinelNote = 'Sentinel note from camera_clips.py 9X';

    CameraNight withClips(List<CameraClip> clips, {String? note}) => CameraNight(
          date: _aboveFloor.date,
          timeInBedMinutes: _aboveFloor.timeInBedMinutes,
          eventsPerHour: _aboveFloor.eventsPerHour,
          bedTimesProvenance: _aboveFloor.bedTimesProvenance,
          sleepOnsetProvenance: _aboveFloor.sleepOnsetProvenance,
          clips: clips,
          clipsNote: note,
          clipsSupported: true,
        );

    testWidgets('有片段：標籤照抄、圖片用完整網址', (tester) async {
      const url = 'http://10.0.0.5:8000/camera/clips/0123456789abcdef0123456789abcdef.gif';
      await pump(tester, _FakeCamera(CameraInsightsResult(
        CameraInsightsStatus.ok,
        nights: [withClips(const [CameraClip(url: url, label: sentinelLabel)])],
      )));

      expect(find.text('Biggest movements'), findsOneWidget);
      expect(find.text(sentinelLabel), findsOneWidget, reason: '標籤一個字都不能改');
      final images = tester.widgetList<Image>(find.byType(Image))
          .map((i) => i.image)
          .whereType<NetworkImage>()
          .map((n) => n.url)
          .toList();
      expect(images, contains(url));
    });

    testWidgets('沒有片段：照抄後端給的原因，不畫空框', (tester) async {
      await pump(tester, _FakeCamera(CameraInsightsResult(
        CameraInsightsStatus.ok,
        nights: [withClips(const [], note: sentinelNote)],
      )));

      expect(find.text(sentinelNote), findsOneWidget);
      expect(
          tester.widgetList<Image>(find.byType(Image))
              .where((i) => i.image is NetworkImage),
          isEmpty);
    });

    testWidgets('反向對照：舊版後端沒有 clips 欄位 → 整段不出現', (tester) async {
      await pump(tester, const _FakeCamera(CameraInsightsResult(
        CameraInsightsStatus.ok,
        nights: [_aboveFloor],          // clipsSupported 預設 false
      )));

      expect(find.text(_cardTitle), findsOneWidget, reason: '卡片本身還在');
      expect(find.text('Biggest movements'), findsNothing,
          reason: '不是「沒有片段」，是後端不會做——講沒有就是假話');
    });

    test('fromJson：相對網址接上 baseUrl，不出現 //', () {
      final night = CameraNight.fromJson({
        'date': '2026-09-13',
        'clips': [
          {'url': '/camera/clips/abc.gif', 'label': sentinelLabel},
        ],
        'clips_note': null,
      }, baseUrl: 'http://10.0.0.5:8000/');
      expect(night.clips.single.url, 'http://10.0.0.5:8000/camera/clips/abc.gif');
      expect(night.clips.single.label, sentinelLabel);
      expect(night.clipsSupported, isTrue);
    });

    test('fromJson：有 clips 欄位但是空的 → 仍算支援，原因照抄', () {
      final night = CameraNight.fromJson({
        'date': '2026-09-13',
        'clips': <dynamic>[],
        'clips_note': sentinelNote,
      });
      expect(night.clipsSupported, isTrue);
      expect(night.clips, isEmpty);
      expect(night.clipsNote, sentinelNote);
    });

    test('nightOn：沒有那一晚就回 null，不退回最近一晚', () {
      const result = CameraInsightsResult(
        CameraInsightsStatus.ok,
        nights: [_aboveFloor, _belowFloor],
      );
      expect(result.nightOn('2026-09-11')?.date, '2026-09-11');
      expect(result.nightOn('2026-01-01'), isNull,
          reason: '換成最近一晚的話，使用者會以為看到的是自己點的那晚');
      expect(result.latest?.date, '2026-09-12');
    });
  });
}
