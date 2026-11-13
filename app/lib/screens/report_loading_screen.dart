import 'dart:async';

import 'package:flutter/material.dart';

import '../services/morning_report.dart';
import '../theme/report_style.dart';
import '../widgets/home_pet.dart';

/// 起床流程裡，自評卡之後、報告之前的等待畫面（2026-11-13 使用者定）。
///
/// 等後端的分數那份（`/home`，最多 4 秒）回來，再多等 AI 那段（`/night-summary`）
/// **最多 [kReportSummaryWait]**；兩個都好了（或時間到）就換成「View sleep report」按鈕。
/// AI 那段超過時間還沒回來，**不丟掉**：交給報告畫面，進去之後再補上。
///
/// - 不自動進報告：使用者按按鈕才進（使用者定）。
/// - 連不到後端、手錶還沒同步，按鈕照樣出現——報告裡會照實說。
/// - 只在滑起床那條流程用；首頁點某一天、補填自評都直接開報告。
/// - ⚠️ AI 那段讀起床自評，所以 [loadSummary] 一定要在自評送出**之後**才呼叫——
///   這個畫面一打開才叫它，而它是蓋在自評卡上面打開的。
///
/// 要換成會動的等待 GIF：改 [_pet]，其他不用動。
class ReportLoadingScreen extends StatefulWidget {
  /// 分數那份（起床動畫一開始就在背景抓了）。
  final Future<MorningReport> report;

  /// [report] 出錯時用的（手機上已經有的那份）。
  final MorningReport fallback;

  /// AI 那段。null＝沒有後端。
  final Future<Map<String, dynamic>?> Function()? loadSummary;

  /// 按下 View sleep report：把準備好的報告交出去（還在路上的 AI 那段一起交）。
  final void Function(PreparedReport prepared) onView;

  /// 按下 Back to home。
  final VoidCallback onClose;

  /// 首頁那一份心情（後端的 pet_mood）。
  final String? mood;

  final Duration summaryWait;

  const ReportLoadingScreen({
    super.key,
    required this.report,
    required this.fallback,
    required this.onView,
    required this.onClose,
    this.loadSummary,
    this.mood,
    this.summaryWait = kReportSummaryWait,
  });

  @override
  State<ReportLoadingScreen> createState() => _ReportLoadingScreenState();
}

/// AI 那段最多多等多久（使用者定：先等分數，AI 再多等約 10 秒）。
const Duration kReportSummaryWait = Duration(seconds: 10);

/// 等待畫面交給報告畫面的東西。
class PreparedReport {
  /// AI 那段若已回來，已經併進去了。
  final MorningReport report;

  /// AI 那段還在路上（超過等待時間）就是它；已經到了或不需要就是 null。
  final Future<Map<String, dynamic>?>? pendingSummary;

  const PreparedReport(this.report, {this.pendingSummary});
}

class _ReportLoadingScreenState extends State<ReportLoadingScreen> {
  PreparedReport? _ready;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    MorningReport report;
    try {
      report = await widget.report;
    } catch (_) {
      // 準備報告本身壞掉不該卡在這裡：照樣給按鈕，報告畫面會再試一次
      if (!mounted) return;
      setState(() => _ready = PreparedReport(widget.fallback));
      return;
    }
    final load = widget.loadSummary;
    Future<Map<String, dynamic>?>? pending;
    // 手錶資料還沒到時後端不會呼叫 AI（回 waiting），不用等
    if (load != null && report.hasScore) {
      final summary = load().catchError((_) => null);
      // 用 Timer 而不是 Future.delayed：AI 先回來時要把倒數取消掉
      final first = Completer<bool>(); // true＝AI 先到
      Map<String, dynamic>? json;
      final timer = Timer(widget.summaryWait, () {
        if (!first.isCompleted) first.complete(false);
      });
      summary.then((j) {
        json = j;
        if (!first.isCompleted) first.complete(true);
      });
      final arrived = await first.future;
      timer.cancel();
      if (arrived) {
        report = report.withSummary(json);
      } else {
        pending = summary;
      }
    }
    if (!mounted) return;
    setState(() => _ready = PreparedReport(report, pendingSummary: pending));
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ready;
    return ReportFont(
      child: Scaffold(
        backgroundColor: ReportColors.bgTop,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const ReportBackground(),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                child: Column(
                  children: [
                    const Spacer(flex: 3),
                    _pet(),
                    const SizedBox(height: 28),
                    Text(
                      ready == null
                          ? 'Preparing your sleep report…'
                          : 'Your sleep report is ready',
                      key: const Key('report-loading-title'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Last night',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: ReportColors.muted, fontSize: 14),
                    ),
                    const Spacer(flex: 2),
                    SizedBox(
                      height: 56,
                      child: ready == null
                          ? const Center(
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  key: Key('report-loading-spinner'),
                                  strokeWidth: 3,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : FilledButton(
                              key: const Key('report-loading-view'),
                              onPressed: () => widget.onView(ready),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: ReportColors.navy,
                                minimumSize: const Size.fromHeight(56),
                                shape: const StadiumBorder(),
                                textStyle: const TextStyle(
                                  fontFamily: kReportFont,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              child: const Text('View sleep report'),
                            ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      key: const Key('report-loading-close'),
                      onPressed: widget.onClose,
                      style: TextButton.styleFrom(
                        foregroundColor: ReportColors.muted,
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: const Text('Back to home'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pet() => SizedBox(
        height: 200,
        child: Center(child: HomePet(mood: widget.mood, size: 190)),
      );
}
