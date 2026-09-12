import 'package:flutter/material.dart';

import '../services/health_connect.dart';

/// Health Connect 的設定：連上、手動同步、看上一次同步的結果。
///
/// ⚠️ 畫面上要講清楚讀什麼、不讀什麼：只讀睡眠 session（起訖與分期），
///    不讀心率、步數或其他任何東西（manifest 也只宣告 READ_SLEEP）。
class HealthConnectScreen extends StatefulWidget {
  final HealthSyncController controller;

  const HealthConnectScreen({super.key, required this.controller});

  @override
  State<HealthConnectScreen> createState() => _HealthConnectScreenState();
}

class _HealthConnectScreenState extends State<HealthConnectScreen> {
  HealthAvailability? _availability;
  bool _granted = false;
  bool _busy = false;
  String? _message;

  HealthPlatform get _platform => widget.controller.platform;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final availability = await _platform.availability();
    final granted = availability == HealthAvailability.available && await _platform.hasPermission();
    if (!mounted) return;
    setState(() {
      _availability = availability;
      _granted = granted;
    });
  }

  Future<void> _sync() async {
    setState(() => _busy = true);
    final result = await widget.controller.sync(askPermission: true);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = describeHealthSync(result);
    });
    await _refresh();
  }

  String _statusText(HealthAvailability a) {
    switch (a) {
      case HealthAvailability.unavailable:
        return 'Health Connect is not available on this phone.';
      case HealthAvailability.needsUpdate:
        return 'Health Connect needs to be installed or updated.';
      case HealthAvailability.available:
        return _granted ? 'Connected.' : 'Not connected yet.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final availability = _availability;
    return Scaffold(
      backgroundColor: const Color(0xFF081326),
      appBar: AppBar(
        backgroundColor: const Color(0xFF081326),
        foregroundColor: Colors.white,
        title: const Text('Health Connect'),
      ),
      body: availability == null
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF7657FF)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'If your watch or band saves sleep to Health Connect, Sonnap can read '
                  'those sleep sessions (start, end and sleep stages) and score them the '
                  'same way as the Garmin data. Sonnap does not read heart rate, steps '
                  'or anything else.',
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 16),
                Text(
                  _statusText(availability),
                  key: const Key('health-status'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (availability == HealthAvailability.needsUpdate)
                  FilledButton(
                    key: const Key('health-install'),
                    onPressed: _platform.openProviderStore,
                    child: const Text('Get Health Connect'),
                  ),
                if (availability == HealthAvailability.available)
                  FilledButton(
                    key: const Key('health-sync'),
                    onPressed: _busy ? null : _sync,
                    child: Text(_granted ? 'Sync now' : 'Connect and sync'),
                  ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _message!,
                    key: const Key('health-message'),
                    style: const TextStyle(color: Colors.white70, height: 1.4),
                  ),
                ],
              ],
            ),
    );
  }
}
