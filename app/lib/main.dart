import 'package:flutter/material.dart';

import 'screens/assistant_screen.dart';
import 'screens/friends_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/report_screen.dart';
import 'screens/settings_screen.dart';
import 'services/account_service.dart';
import 'services/nightly_uploader.dart';
import 'services/sleep_repository.dart';

void main() {
  runApp(const SonnapApp());
}

class SonnapApp extends StatelessWidget {
  const SonnapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int currentIndex = 0;

  /// 目標就寢時間與提醒開關的**唯一擁有者**。
  ///
  /// ⚠️ **不要讓 HomeScreen 或 SettingsScreen 各自持有這兩個值。**
  /// 在此之前正是那樣：`header_card.dart` 與 `settings_screen.dart` 各存一份
  /// state、各自寫死 23:30，所以在 Settings 改完切回首頁，倒數完全沒變——
  /// 同一個設定在兩個畫面顯示互相矛盾的值，而且不會有任何錯誤訊息。
  ///
  /// 那兩個 widget 本身早就寫成受控元件了（`initial*` 參數 ＋ `onChanged`
  /// callback ＋ `didUpdateWidget`），缺的只是一個共用的擁有者，就是這裡。
  /// 所以這次修正**沒有動那兩個 widget 的內部一行**。
  ///
  /// ⚠️ 目前只存在記憶體裡，App 關掉就回到預設值。要持久化的話這裡是唯一
  /// 該接儲存的地方——不要在 widget 裡各自存，那會把剛修好的問題再造一次。
  TimeOfDay targetBedtime = const TimeOfDay(hour: 23, minute: 30);
  bool reminderOn = true;

  /// 三個畫面**共用同一個** repository 實例。
  ///
  /// 各自 `const AssetSleepRepository()` 也能跑，但那樣「這份資料是從哪來的」
  /// 會有三個答案，Insights 頁就沒辦法誠實地顯示來源。共用一個實例之後，
  /// [FallbackSleepRepository.lastSource] 才代表整個 App 的實際狀態。
  ///
  /// 沒給 `--dart-define=SONNAP_API_BASE` 時這裡回的就是 AssetSleepRepository，
  /// 行為與加這一層之前完全相同。
  final SleepRepository _repository = buildSleepRepository();

  /// 這台裝置代表誰。App 啟動時解析一次。
  ///
  /// ⚠️ **null 不等於「沒身分」**——它代表「還在解析」。兩者混在一起的話，
  /// 第一幀就會閃過一次問暱稱的畫面，然後在解析完成後又消失。
  AccountStatus? _account;

  late final AccountService _accounts = AccountService(
    baseUrl: ApiSleepRepository.configuredBaseUrl,
  );

  /// 把偵測到的就寢時刻送去後端。
  ///
  /// ⚠️ 依 [_account] 重建：帳號是在 App 開起來之後才建立的，
  /// uploader 若在啟動時就固定住，剛註冊完的那一次上傳會用到空的身分。
  NightlyUploader? get _uploader {
    final baseUrl = ApiSleepRepository.configuredBaseUrl.trim();
    if (baseUrl.isEmpty) return null;
    return NightlyUploader(
      baseUrl: baseUrl,
      identity: ResolvedUserIdentity(_account?.userId),
    );
  }

  @override
  void initState() {
    super.initState();
    _resolveAccount();
  }

  Future<void> _resolveAccount() async {
    final status = await _accounts.resolve();
    if (!mounted) return;
    setState(() => _account = status);
  }

  Future<bool> _createAccount(String displayName) async {
    final hh = targetBedtime.hour.toString().padLeft(2, '0');
    final mm = targetBedtime.minute.toString().padLeft(2, '0');
    final status = await _accounts.createAccount(
      displayName: displayName,
      targetBedtime: '$hh:$mm',
    );
    if (status == null) return false;
    if (!mounted) return true;
    setState(() => _account = status);
    return true;
  }

  /// 跳過註冊。**不寫進儲存**——下次開 App 會再問一次。
  ///
  /// 刻意這樣：跳過的最常見原因是「現在連不到後端」，那是暫時的。
  /// 記成永久決定的話，使用者之後在 WiFi 底下也永遠不會被問第二次，
  /// 而且畫面上沒有任何地方看得出來他錯過了什麼。
  void _skipOnboarding() {
    setState(() => _account = const AccountStatus(AccountState.noBackend));
  }

  void _setBedtime(TimeOfDay value) {
    if (value == targetBedtime) return;
    setState(() => targetBedtime = value);
  }

  void _setReminder(bool value) {
    if (value == reminderOn) return;
    setState(() => reminderOn = value);
  }

  /// 在 `build()` 裡組而不是 `late final`——就寢時間改變時整個清單要重建，
  /// 新的值才傳得下去。IndexedStack 依「型別 ＋ 位置」保留 State，
  /// 所以重建 widget 不會讓首頁重新讀一次 payload。
  List<Widget> _buildPages(AccountStatus account) {
    return <Widget>[
      HomeScreen(
        displayName: account.displayName ?? kFallbackDisplayName,
        repository: _repository,
        targetBedtime: targetBedtime,
        reminderOn: reminderOn,
        onBedtimeChanged: _setBedtime,
        onReminderChanged: _setReminder,
      ),
      const FriendsScreen(),
      ReportScreen(repository: _repository, uploader: _uploader),
      AssistantScreen(
        repository: _repository,
        username: account.displayName ?? kFallbackDisplayName,
      ),
      SettingsScreen(
        username: account.displayName ?? kFallbackDisplayName,
        initialTargetBedtime: targetBedtime,
        initialReminderOn: reminderOn,
        onBedtimeChanged: _setBedtime,
        onReminderChanged: _setReminder,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;

    // 還在解析。⚠️ 這一格不能省——少了它，第一幀會閃過一次問暱稱的畫面
    // 然後又消失，看起來像 App 在抽搐。
    if (account == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF081326),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF7657FF)),
        ),
      );
    }

    if (account.state == AccountState.needsOnboarding) {
      return OnboardingScreen(
        onCreate: _createAccount,
        onSkip: _skipOnboarding,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF081326),

      body: IndexedStack(
        index: currentIndex,
        children: _buildPages(account),
      ),

      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1B2548),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFFFFD96A),
          unselectedItemColor: Colors.white70,
          type: BottomNavigationBarType.fixed,

          onTap: (index) {
            setState(() {
              currentIndex = index;
            });
          },

          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              label: "Home",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.groups_rounded),
              label: "Friends",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_rounded),
              label: "Insights",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.smart_toy_rounded),
              label: "Assistants",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_rounded),
              label: "Settings",
            ),
          ],
        ),
      ),
    );
  }
}