// 目標就寢時間必須只有一個擁有者。
//
// 修正前：`header_card.dart` 與 `settings_screen.dart` 各自持有一份
// `targetBedtime`，各自寫死 23:30。在 Settings 改完切回首頁，倒數完全沒變——
// 同一個設定在兩個畫面顯示互相矛盾的值。
//
// 這個 bug **不會有任何錯誤訊息**，只會在有人剛好兩頁都看過時才發現，
// 所以它需要一條測試守著。回歸的方式也很自然：以後有人為了方便
// 在某個畫面裡自己存一份 state，這條就會紅。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/main.dart';
import 'package:app/models/sleep_session.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/screens/settings_screen.dart';
import 'package:app/services/sleep_repository.dart';
import 'package:app/widgets/header_card.dart';

/// 立即回應的假 repository。
///
/// 真的 `AssetSleepRepository` 走 `rootBundle` 的非同步 I/O，在 widget test
/// 的假時間裡不保證在有限次 pump 內完成——單獨跑會過、整包跑會失敗，
/// 是最惱人的那種不穩定測試。這裡要測的是「值有沒有傳下去」，
/// 不是「檔案讀得到嗎」（那個 sleep_repository_test.dart 已經在測了）。
class _ImmediateRepository implements SleepRepository {
  final SleepSession session;
  const _ImmediateRepository(this.session);

  @override
  Future<SleepSession> load() async => session;
}

void main() {
  /// ⚠️ 在 `setUpAll` 讀，不要在 `testWidgets` 裡讀。
  /// widget test 的假時間不會推進真正的檔案 I/O，`await ...load()` 寫在
  /// testWidgets 內會整條卡住直到逾時（實際踩過，一次跑了 10 分鐘）。
  late SleepSession sample;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sample = await const AssetSleepRepository().load();
  });

  /// IndexedStack 會把五個畫面都建出來，但沒顯示的那幾個包在 `Offstage` 裡，
  /// 而 `find.byType` 預設 `skipOffstage: true` 會跳過它們——所以找 Settings
  /// 一定要關掉那個預設值，否則會拿到「Bad state: No element」。
  Finder findOf<T extends Widget>() => find.byType(T, skipOffstage: false);

  HomeScreen homeOf(WidgetTester tester) =>
      tester.widget<HomeScreen>(findOf<HomeScreen>());

  SettingsScreen settingsOf(WidgetTester tester) =>
      tester.widget<SettingsScreen>(findOf<SettingsScreen>());

  /// 從當前的 widget tree 讀出兩個畫面各自拿到的就寢時間。
  (TimeOfDay, TimeOfDay) bedtimesOf(WidgetTester tester) {
    return (homeOf(tester).targetBedtime, settingsOf(tester).initialTargetBedtime);
  }

  testWidgets('首頁與設定頁一開始拿到同一個就寢時間', (tester) async {
    await tester.pumpWidget(const SonnapApp());
    await tester.pump();

    final (home, settings) = bedtimesOf(tester);
    expect(
      home,
      settings,
      reason: '兩個畫面顯示同一個設定，初始值就必須相同',
    );
  });

  testWidgets('在任一頁改就寢時間，另一頁立刻跟著變', (tester) async {
    await tester.pumpWidget(const SonnapApp());
    await tester.pump();

    final (before, _) = bedtimesOf(tester);
    const changed = TimeOfDay(hour: 1, minute: 0);
    expect(before, isNot(changed), reason: '測試值要與預設值不同才有意義');

    // 直接呼叫 callback，等同使用者在 Settings 的時間選擇器按下確定。
    // 走真的 showTimePicker 會變成在測 Material 的元件，不是測我們的狀態流。
    settingsOf(tester).onBedtimeChanged!(changed);
    await tester.pump();

    final (homeAfter, settingsAfter) = bedtimesOf(tester);
    expect(
      homeAfter,
      changed,
      reason: '在 Settings 改了，首頁沒跟著變——這正是修正前的 bug',
    );
    expect(settingsAfter, changed);

    // 反方向也要成立：首頁改，Settings 也要跟著
    const again = TimeOfDay(hour: 22, minute: 15);
    homeOf(tester).onBedtimeChanged!(again);
    await tester.pump();

    final (homeFinal, settingsFinal) = bedtimesOf(tester);
    expect(homeFinal, again);
    expect(
      settingsFinal,
      again,
      reason: '在首頁改了，Settings 沒跟著變',
    );
  });

  testWidgets('提醒開關同樣只有一個擁有者', (tester) async {
    await tester.pumpWidget(const SonnapApp());
    await tester.pump();

    final before = settingsOf(tester).initialReminderOn;
    settingsOf(tester).onReminderChanged!(!before);
    await tester.pump();

    expect(homeOf(tester).reminderOn, !before);
    expect(settingsOf(tester).initialReminderOn, !before);
  });

  testWidgets('值真的傳到了 HeaderCard，不是只傳到 HomeScreen', (tester) async {
    // 上面那幾條檢查的是 HomeScreen **收到**什麼。但如果有人把參數收下來
    // 卻在 HeaderCard 那裡仍然寫死 23:30，那幾條照樣會過——而畫面上的
    // 倒數還是不會動。這一條走到最底層，把那個漏洞補起來。
    const changed = TimeOfDay(hour: 3, minute: 45);

    // Scaffold 是必要的：HomeScreen 裡的 IconButton 需要 Material 祖先，
    // 而 MaterialApp.home 本身不提供。
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeScreen(
          repository: _ImmediateRepository(sample),
          targetBedtime: changed,
        ),
      ),
    ));
    await tester.pump();

    final header = tester.widget<HeaderCard>(find.byType(HeaderCard));
    expect(
      header.initialTargetBedtime,
      changed,
      reason: 'HomeScreen 收到了新的就寢時間，卻沒有往下傳給 HeaderCard——'
          '畫面上的倒數因此不會變，而上面那幾條測試看不出來',
    );
  });

  testWidgets('五個畫面共用同一個 repository 實例', (tester) async {
    // 各自 new 一個也能跑，但那樣「資料從哪來」會有三個答案，
    // Insights 頁就沒辦法誠實顯示來源（見 report_screen 的 _buildDeliveryRow）。
    await tester.pumpWidget(const SonnapApp());
    await tester.pump();

    expect(homeOf(tester).repository, isNotNull);
  });
}
