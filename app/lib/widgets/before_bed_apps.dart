import 'package:flutter/material.dart';

import '../services/pre_bed_apps.dart';
import '../theme/report_style.dart';

/// 放下手機前那一小時用了哪些 App（Phone down 詳細頁最底下，2026-11-19 從舊 Insights 搬來）。
///
/// ⚠️ 這是**睡前**那一段，不是整天的總量——整天用了三小時跟躺下前那一小時都在滑，
/// 前者管不著、後者可以改。偵測不到就寢時刻（hasData false）就整段不出現。
/// 只寫用了多久，不說哪個 App 不好。
class BeforeBedApps extends StatelessWidget {
  final PreBedResult preBed;
  const BeforeBedApps({super.key, required this.preBed});

  static String _min(int m) =>
      m < 60 ? '${m}m' : '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';

  @override
  Widget build(BuildContext context) {
    final pre = preBed;
    if (!pre.hasData) return const SizedBox.shrink();
    final busiest = pre.apps.first.minutes;
    return Column(
      key: const Key('before-bed-apps'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Before bed',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          'Last ${pre.window.inMinutes} min before you put your phone down · '
          '${_min(pre.totalMinutes)} on screen',
          style: const TextStyle(color: ReportColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        for (final app in pre.apps)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 104,
                  child: Text(
                    app.appName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: ReportColors.soft, fontSize: 13),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: busiest <= 0 ? 0 : (app.minutes / busiest).clamp(0.0, 1.0),
                      minHeight: 10,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      valueColor: const AlwaysStoppedAnimation(ReportColors.lilac),
                    ),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    _min(app.minutes),
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: ReportColors.soft, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
