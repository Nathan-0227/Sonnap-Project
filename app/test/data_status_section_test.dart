// 設定頁的「Data」（widgets/data_status_section.dart，2026-11-19 從舊 Insights 搬來）。
//   1. 退回打包檔時一定要說「Bundled with the app」，而且不掛綠色勾勾
//   2. 昨晚上傳的狀態分得開：送到了／進了佇列等下次／沒東西可送
//   3. 單機模式（沒設定後端）不出現「後端連不上」那種降級說法
import 'package:app/models/sleep_session.dart';
import 'package:app/services/bed_marks.dart';
import 'package:app/services/key_value_store.dart';
import 'package:app/services/lights_out.dart';
import 'package:app/services/nightly_sync.dart';
import 'package:app/services/nightly_uploader.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:app/widgets/data_status_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Down implements SleepRepository {
  @override
  Future<SleepSession> load() async => throw StateError('down');
}

void main() {
  late SleepSession sample;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sample = await const AssetSleepRepository().load();
  });

  Future<void> pump(WidgetTester tester, Widget w) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
    await tester.pump();
  }

  NightlySync sync(NightlyUploadBatch batch) =>
      NightlySync(bedMarks: BedMarkStore(InMemoryKeyValueStore()))
        ..batch = batch
        ..lightsOut = LightsOutResult(LightsOutStatus.ok,
            at: DateTime(2026, 11, 19, 3, 27), quietMinutes: 300);

  testWidgets('退回打包檔：照實說，而且不是綠色', (tester) async {
    final repo = FallbackSleepRepository(primary: _Down(), fallback: _Fixed(sample));
    await repo.load();
    await pump(tester, DataStatusSection(repository: repo));
    expect(find.text('Bundled with the app'), findsOneWidget);
    final icon = tester.widget<Icon>(find.descendant(
        of: find.byKey(const Key('data-live')), matching: find.byType(Icon)));
    expect(icon.icon, Icons.cloud_off_rounded);
  });

  testWidgets('單機模式不講「連不上」', (tester) async {
    await pump(tester, DataStatusSection(repository: _Fixed(sample)));
    expect(find.byKey(const Key('data-live')), findsNothing);
  });

  testWidgets('上傳狀態三種講法分得開', (tester) async {
    await pump(
        tester,
        DataStatusSection(
          repository: _Fixed(sample),
          nightly: sync(const NightlyUploadBatch(
              current: NightlyUploadResult(NightlyUploadStatus.ok, date: '2026-11-19'))),
        ));
    expect(find.text('Last night sent'), findsOneWidget);
    expect(find.text('Phone down 03:27'), findsOneWidget);

    await pump(
        tester,
        DataStatusSection(
          repository: _Fixed(sample),
          nightly: sync(const NightlyUploadBatch(
              current: NightlyUploadResult(NightlyUploadStatus.failed, error: 'x'),
              currentQueued: true)),
        ));
    expect(find.text('Waiting to send'), findsOneWidget);

    await pump(
        tester,
        DataStatusSection(
          repository: _Fixed(sample),
          nightly: sync(const NightlyUploadBatch(
              current: NightlyUploadResult(NightlyUploadStatus.nothingDetected))),
        ));
    expect(find.text('Nothing to send'), findsOneWidget);
  });
}

class _Fixed implements SleepRepository {
  final SleepSession session;
  const _Fixed(this.session);
  @override
  Future<SleepSession> load() async => session;
}
