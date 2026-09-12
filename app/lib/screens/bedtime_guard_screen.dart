import 'package:flutter/material.dart';

import '../services/bedtime_guard.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF081326),
      appBar: AppBar(
        backgroundColor: const Color(0xFF081326),
        foregroundColor: Colors.white,
        title: const Text('Bedtime guard'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF7657FF)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'From 30 minutes before your target bedtime, opening an app on your list '
                  'will either show a reminder or send you back to the home screen.',
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 16),
                RadioGroup<GuardMode>(
                  groupValue: _settings.mode,
                  onChanged: (v) => _update(_settings.copyWith(mode: v)),
                  child: Column(
                    children: [
                      for (final m in GuardMode.values)
                        RadioListTile<GuardMode>(
                          key: Key('guard-mode-${m.name}'),
                          value: m,
                          title: Text(modeTitle(m), style: const TextStyle(color: Colors.white)),
                          subtitle: Text(modeSubtitle(m), style: const TextStyle(color: Colors.white54)),
                        ),
                    ],
                  ),
                ),
                if (_settings.mode != GuardMode.off) ...[
                  const SizedBox(height: 8),
                  _permissionCard(),
                ],
                const SizedBox(height: 16),
                const Text('Apps to guard',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                if (_apps.isEmpty)
                  const Text(
                    'No apps could be listed on this device.',
                    style: TextStyle(color: Colors.white54),
                  )
                else
                  for (final app in _apps)
                    CheckboxListTile(
                      key: Key('guard-app-${app.packageName}'),
                      value: _settings.packages.contains(app.packageName),
                      onChanged: (checked) {
                        final next = {..._settings.packages};
                        if (checked == true) {
                          next.add(app.packageName);
                        } else {
                          next.remove(app.packageName);
                        }
                        _update(_settings.copyWith(packages: next));
                      },
                      title: Text(app.label, style: const TextStyle(color: Colors.white)),
                    ),
              ],
            ),
    );
  }

  Widget _permissionCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF10265A),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _enabled ? 'Accessibility access is on.' : 'Accessibility access is off.',
              key: const Key('guard-permission'),
              style: TextStyle(
                color: _enabled ? const Color(0xFF7ED957) : const Color(0xFFFFC83D),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Sonnap only sees which app is opening, never what is on the screen. '
              'Without this access the guard cannot work.',
              style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
            ),
            if (!_enabled) ...[
              const SizedBox(height: 6),
              // ⚠️ Android 13 起側載的 App 預設被「受限設定」擋住，開關是灰的而且
              //    不說為什麼。D2 走側載，少了這一句大部分受測者會卡在這裡。
              const Text(
                "If Sonnap's switch is greyed out: open Sonnap's App info, "
                'tap the menu in the top corner, then "Allow restricted settings".',
                key: Key('guard-restricted-hint'),
                style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('guard-open-settings'),
                onPressed: () => widget.controller.platform.openSettings(),
                child: const Text('Open accessibility settings'),
              ),
            ],
          ],
        ),
      );
}
