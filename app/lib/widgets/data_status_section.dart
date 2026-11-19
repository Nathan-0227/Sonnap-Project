import 'package:flutter/material.dart';

import '../services/nightly_sync.dart';
import '../services/nightly_uploader.dart';
import '../services/sleep_repository.dart';

/// 設定頁的「Data」（2026-11-19 從舊 Insights 的 Sleep Tracking Sources 卡搬來）。
///
/// 三件事：資料是即時從後端拿的還是打包在 App 裡的、昨晚送到後端了沒、資料來自哪幾個來源。
/// ⚠️ 「Bundled with the app」那一列**不能省**：後端連不上時 App 會退回打包檔，
/// 不講出來使用者會以為看到的是即時資料。降級狀態不掛綠色勾勾（實機看過，讀起來像一切正常）。
class DataStatusSection extends StatelessWidget {
  final SleepRepository repository;
  final NightlySync? nightly;

  /// 資料來源（打包檔的 data_sources）。空＝不畫那一段。
  final List<String> sources;

  const DataStatusSection({
    super.key,
    required this.repository,
    this.nightly,
    this.sources = const [],
  });

  static const _ok = Color(0xFF4FE0A0);
  static const _warn = Color(0xFFFFC83D);
  static const _sub = Color(0xFF9FB3D1);

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    final repo = repository;
    // 完全沒設定後端（單機模式）不顯示這一列：那是預期的，不是降級
    if (repo is FallbackSleepRepository) {
      final live = repo.lastSource == SleepDataSource.api;
      rows.add(_row(
        key: const Key('data-live'),
        healthy: live,
        title: live ? 'Live from backend' : 'Bundled with the app',
        subtitle: live
            ? 'Fetched just now'
            : 'Backend unreachable - this data may be out of date',
      ));
    }
    final batch = nightly?.batch;
    if (batch != null) {
      final c = batch.current;
      final at = nightly?.lightsOut?.at;
      String two(int v) => v.toString().padLeft(2, '0');
      final when = at == null ? null : '${two(at.hour)}:${two(at.minute)}';
      final (bool healthy, String title, String subtitle) = switch (c.status) {
        NightlyUploadStatus.ok => (
            true,
            'Last night sent',
            when == null ? 'Phone down time received' : 'Phone down $when',
          ),
        NightlyUploadStatus.nothingDetected => (
            false,
            'Nothing to send',
            'No phone-down time detected for last night',
          ),
        NightlyUploadStatus.failed => (
            false,
            batch.currentQueued ? 'Waiting to send' : 'Not sent',
            batch.currentQueued
                ? 'Backend unreachable - will retry next time you open the app'
                : 'The backend did not accept it',
          ),
        NightlyUploadStatus.noUser || NightlyUploadStatus.noBackend => (
            false,
            'Not sent',
            'This build has no backend account',
          ),
      };
      final n = batch.replayed.length;
      rows.add(_row(
        key: const Key('data-upload'),
        healthy: healthy,
        title: title,
        subtitle: n == 0
            ? subtitle
            : '$subtitle · also synced $n earlier ${n == 1 ? 'night' : 'nights'}',
      ));
    }
    if (sources.isNotEmpty) {
      rows.add(const Padding(
        padding: EdgeInsets.only(top: 6, bottom: 4),
        child: Text(
          'Tracking sources',
          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ));
      for (final s in sources) {
        rows.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Icon(_icon(s), size: 16, color: _sub),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s, style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ],
          ),
        ));
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('data-status-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }

  Widget _row({
    required Key key,
    required bool healthy,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            healthy ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
            size: 18,
            color: healthy ? _ok : _warn,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                Text(subtitle, style: const TextStyle(color: _sub, fontSize: 12, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _icon(String s) {
    final l = s.toLowerCase();
    if (l.contains('garmin') || l.contains('watch')) return Icons.watch_rounded;
    if (l.contains('camera')) return Icons.videocam_rounded;
    if (l.contains('phone')) return Icons.phone_iphone_rounded;
    return Icons.data_usage_rounded;
  }
}
