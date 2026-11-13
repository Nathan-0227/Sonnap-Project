import 'package:flutter/material.dart';

import '../screens/morning_report_screen.dart' show reportDateTitle;
import '../services/key_value_store.dart';
import '../theme/report_style.dart';
import 'home_pet.dart';

/// 寵物跟你說「我做了一個夢」：小狗旁邊一個短對話框，點開才看完整的夢境日記
/// （2026-11-13 使用者定：對話框不放那麼多字）。
///
/// - 對話框只說固定一句 [kDreamBubbleText]，**不從夢境裡截一段**——截半句容易斷在怪地方。
/// - 只有那一晚**真的有夢境**才出現；沒有就不出現，**小狗不說「我昨晚沒做夢」**
///   （那是編的：沒有夢境的原因是資料沒來，不是牠沒做夢）。
/// - 首頁看過之後縮成小小的 💭，同一個夢不再大聲提醒；有新的夢（不同日期）才回到完整對話框。
///
/// 夢境本身是 AI 寫的虛構內容（`ai/generate_advice.py`），只呈現、不計分。

/// 對話框那一句。
const String kDreamBubbleText = 'I had a dream…';

/// 雲朵對話框的圖（使用者生成，去背；字由 App 疊上去，圖裡沒有字）。
const String kDreamCloudAsset = 'assets/moods/dream_cloud.png';

/// 完整那朵雲的寬度（首頁排位置要用）。
const double kDreamBubbleWidth = 150;

/// 雲身的中心（佔圖寬、高的比例）：字放這裡。右下那兩顆小圓點與四周的星星月亮不算。
const Offset _cloudTextCenter = Offset(0.494, 0.476);
const double _cloudAspect = 720 / 427;

/// 小狗旁邊的對話框（雲朵）。[compact] = 看過了，只剩一朵小雲、不寫字。
/// 雲朵圖讀不到時退回程式畫的白色對話框（[_PaintedBubble]），不會報錯。
class DreamBubble extends StatelessWidget {
  final VoidCallback onTap;
  final bool compact;
  final String cloudAsset;

  const DreamBubble({
    super.key,
    required this.onTap,
    this.compact = false,
    this.cloudAsset = kDreamCloudAsset,
  });

  @override
  Widget build(BuildContext context) {
    final width = compact ? 58.0 : kDreamBubbleWidth;
    final height = width / _cloudAspect;
    return Semantics(
      button: true,
      label: compact ? 'Open dream diary' : kDreamBubbleText,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Image.asset(
          cloudAsset,
          key: const Key('dream-cloud'),
          width: width,
          height: height,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => _PaintedBubble(compact: compact),
          frameBuilder: (context, child, frame, sync) {
            if (compact) {
              return SizedBox(
                key: const Key('dream-bubble-compact'),
                width: width,
                height: height,
                child: child,
              );
            }
            return SizedBox(
              width: width,
              height: height,
              child: Stack(
                children: [
                  Positioned.fill(child: child),
                  // 字限制在雲身裡（左右各留 16%、上下置中在雲身中心）；放不下就縮小，
                  // 不換行、不跑出雲外（系統字體放大時也一樣）
                  Positioned(
                    left: width * (_cloudTextCenter.dx - 0.34),
                    right: width * (1 - _cloudTextCenter.dx - 0.34),
                    top: height * (_cloudTextCenter.dy - 0.2),
                    height: height * 0.4,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: const Text(
                        kDreamBubbleText,
                        key: Key('dream-bubble-text'),
                        style: TextStyle(
                          fontFamily: kReportFont,
                          color: Color(0xFF6B3E22),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 雲朵圖讀不到時的退路：程式畫的白色對話框。
class _PaintedBubble extends StatelessWidget {
  final bool compact;
  const _PaintedBubble({required this.compact});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _BubbleTailPainter(),
      child: Container(
        // 尾巴畫在左下角外面，留一點邊讓點得到
        margin: const EdgeInsets.only(bottom: 8),
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 9, vertical: 6)
            : const EdgeInsets.fromLTRB(14, 9, 14, 9),
        decoration: BoxDecoration(
          color: _bubbleColor,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          compact ? '💭' : '$kDreamBubbleText 💭',
          key: Key(compact ? 'dream-bubble-compact' : 'dream-bubble-text'),
          style: TextStyle(
            fontFamily: kReportFont,
            color: ReportColors.navy,
            fontSize: compact ? 16 : 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

const Color _bubbleColor = Color(0xFFF7F4FF);

/// 對話框左下角的小尾巴，指向小狗。
class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final bottom = size.height - 8; // 對話框本體的底
    final path = Path()
      ..moveTo(18, bottom - 2)
      ..lineTo(30, bottom - 2)
      ..lineTo(12, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = _bubbleColor);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 打開夢境日記（底部滑上來，報告的深藍樣式）。
///
/// [date]：那一晚（YYYY-MM-DD），標題下面寫日期——舊的夢也不會被誤以為是昨晚的。
/// [mood]：那一晚的寵物心情，畫成小頭像（不認得的一律 bored，同 [HomePet]）。
/// [disclaimer]：「AI 生成」那行小字；有就放在最下面。
Future<void> showDreamDiary(
  BuildContext context, {
  required String text,
  String? date,
  String? mood,
  String? disclaimer,
}) {
  final day = date == null ? null : DateTime.tryParse(date);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: ReportColors.sheet,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => ReportFont(
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: SingleChildScrollView(
            key: const Key('dream-diary'),
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 56,
                      height: 56,
                      child: HomePet(mood: mood, size: 56),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Your buddy's dream",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (day != null)
                            Text(
                              reportDateTitle(day),
                              key: const Key('dream-diary-date'),
                              style: const TextStyle(
                                color: ReportColors.muted,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  text,
                  key: const Key('dream-diary-text'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.55,
                  ),
                ),
                if (disclaimer != null && disclaimer.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    disclaimer,
                    key: const Key('dream-diary-disclaimer'),
                    style: const TextStyle(
                      color: ReportColors.dim,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// 記住哪一晚的夢看過了（首頁的對話框縮成 💭 用）。只存在手機上。
class DreamReadStore {
  final KeyValueStore store;
  const DreamReadStore(this.store);

  static String _key(String date) => 'dream_read_$date';

  Future<bool> isRead(String date) async {
    try {
      return await store.getString(_key(date)) == '1';
    } catch (_) {
      return false;
    }
  }

  Future<void> markRead(String date) async {
    try {
      await store.setString(_key(date), '1');
    } catch (_) {
      // 記不住就下次再提醒一次，不影響看夢
    }
  }
}
