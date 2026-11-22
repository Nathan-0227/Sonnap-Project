import 'package:flutter/material.dart';

import '../services/bedtime_guard.dart';
import '../theme/app_accent.dart';
import '../widgets/settings_list.dart';

/// 就寢守門的設定：哪一種模式、守哪些 App、無障礙權限開了沒。
///
/// ⚠️ 權限要使用者自己到系統設定打開（跟「使用情況存取」一樣要不到），
///    這裡只負責把人帶過去，回來時重查一次。
/// ⚠️ 畫面上要講清楚它看得到什麼、看不到什麼：服務只看「哪個 App 被打開」，
///    不看畫面內容（canRetrieveWindowContent=false）。
class BedtimeGuardScreen extends StatefulWidget {
  final BedtimeGuardController controller;
  final TimeOfDay bedtime;

  const BedtimeGuardScreen({super.key, required this.controller, required this.bedtime});

  @override
  State<BedtimeGuardScreen> createState() => _BedtimeGuardScreenState();
}

class _BedtimeGuardScreenState extends State<BedtimeGuardScreen> with WidgetsBindingObserver {
  GuardSettings _settings = const GuardSettings();
  List<LaunchableApp> _apps = const [];
  bool _enabled = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 從系統設定頁回來時重查權限——openSettings() 送出 intent 就立刻返回，
  /// 拿不到使用者按了什麼（同 report_screen 的使用情況存取）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshEnabled();
  }

  Future<void> _load() async {
    final settings = await widget.controller.load();
    final apps = await widget.controller.platform.listApps();
    final enabled = await widget.controller.platform.isEnabled();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _apps = apps;
      _enabled = enabled;
      _loaded = true;
    });
  }

  Future<void> _refreshEnabled() async {
    final enabled = await widget.controller.platform.isEnabled();
    if (!mounted) return;
    setState(() => _enabled = enabled);
  }

  Future<void> _update(GuardSettings next) async {
    setState(() => _settings = next);
    await widget.controller.save(next);
    await widget.controller.push(widget.bedtime);
  }

  static String modeTitle(GuardMode m) {
    switch (m) {
      case GuardMode.off:
        return 'Off';
      case GuardMode.reminder:
        return 'Full-screen reminder';
      case GuardMode.block:
        return 'Send me back to the home screen';
    }
  }

  static String modeSubtitle(GuardMode m) {
    switch (m) {
      case GuardMode.off:
        return 'Sonnap does not watch which apps you open.';
      case GuardMode.reminder:
        return 'A reminder you can close. The app stays open.';
      case GuardMode.block:
        return 'The app closes and you land on the home screen.';
    }
  }

  static IconData _modeIcon(GuardMode m) => switch (m) {
        GuardMode.off => Icons.do_not_disturb_off_outlined,
        GuardMode.reminder => Icons.notifications_active_outlined,
        GuardMode.block => Icons.home_outlined,
      };

  static Color _modeColor(GuardMode m) => switch (m) {
        GuardMode.off => const Color(0xFF5B6B9A),
        GuardMode.reminder => const Color(0xFFE58A3A),
        GuardMode.block => const Color(0xFFD2557A),
      };

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: 'Bedtime guard',
      loading: !_loaded,
      children: [
        const SettingsNote(
          'From 30 minutes before your target bedtime, opening an app on your list '
          'will either show a reminder or send you back to the home screen.',
        ),
        SettingsGroup(title: 'MODE', rows: [
          for (final m in GuardMode.values)
            SettingsRow(
              key: Key('guard-mode-${m.name}'),
              icon: _modeIcon(m),
              color: _modeColor(m),
              title: modeTitle(m),
              subtitle: modeSubtitle(m),
              trailing: SettingsRadio(selected: _settings.mode == m),
              onTap: _settings.mode == m ? null : () => _update(_settings.copyWith(mode: m)),
            ),
        ]),
        if (_settings.mode != GuardMode.off) _permissionCard(),
        SettingsGroup(
          title: 'APPS TO GUARD',
          rows: _apps.isEmpty
              ? const [SettingsRow(title: 'No apps could be listed on this device.')]
              : [
                  for (final app in _apps)
                    SettingsRow(
                      key: Key('guard-app-${app.packageName}'),
                      dense: true,
                      title: app.label,
                      trailing: SettingsCheck(checked: _settings.packages.contains(app.packageName)),
                      onTap: () {
                        final next = {..._settings.packages};
                        if (!next.remove(app.packageName)) next.add(app.packageName);
                        _update(_settings.copyWith(packages: next));
                      },
                    ),
                ],
        ),
      ],
    );
  }

  Widget _permissionCard() => Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kSettingsCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _enabled ? const Color(0x554FE0A0) : const Color(0x66FFC83D),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _enabled ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                  color: _enabled ? const Color(0xFF4FE0A0) : const Color(0xFFFFC83D),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _enabled ? 'Accessibility access is on.' : 'Accessibility access is off.',
                    key: const Key('guard-permission'),
                    style: TextStyle(
                      color: _enabled ? const Color(0xFF4FE0A0) : const Color(0xFFFFC83D),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Sonnap only sees which app is opening, never what is on the screen. '
              'Without this access the guard cannot work.',
              style: TextStyle(color: kSettingsSub, fontSize: 12, height: 1.4),
            ),
            if (!_enabled) ...[
              const SizedBox(height: 6),
              // ⚠️ Android 13 起側載的 App 預設被「受限設定」擋住，開關是灰的而且
              //    不說為什麼。D2 走側載，少了這一句大部分受測者會卡在這裡。
              const Text(
                "If Sonnap's switch is greyed out: open Sonnap's App info, "
                'tap the menu in the top corner, then "Allow restricted settings".',
                key: Key('guard-restricted-hint'),
                style: TextStyle(color: kSettingsSub, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('guard-open-settings'),
                  onPressed: () => widget.controller.platform.openSettings(),
                  style: FilledButton.styleFrom(
                    backgroundColor: accentOf(context),
                    minimumSize: const Size(0, 46),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  child: const Text('Open accessibility settings'),
                ),
              ),
            ],
          ],
        ),
      );
}
