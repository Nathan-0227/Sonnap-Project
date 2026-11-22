import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/pet_choice.dart';
import 'journey_section.dart' show journeyHeadAsset;

/// 加朋友面板：小鎮明信片（2026-11-22 使用者從三案選 C）。
///
/// 上半是「你的小鎮地址」明信片（自己的邀請碼＋寵物郵票），下面輸入朋友的碼。
/// 郵票用 Journey 那張側面走路的頭：**不是心情臉**（心情臉固定代表後端判的心情）。
///
/// ⚠️ 底部要留系統導覽列的高度：showModalBottomSheet 的 useSafeArea 只避開上面，
/// 原本只留 24 點，手機上輸入框與 Add 被導覽列蓋掉下半截（11-22 截圖）。
/// 鍵盤跳出來時 padding.bottom 會變 0、改由 viewInsets 頂上去，兩個相加不會重複。
class InvitePostcardSheet extends StatelessWidget {
  const InvitePostcardSheet({
    super.key,
    required this.myCode,
    required this.controller,
    required this.onSubmit,
  });

  final String myCode;
  final TextEditingController controller;
  final VoidCallback onSubmit;

  static const Color _panel = Color(0xFF141A45);
  static const Color _paper = Color(0xFFF3E9D2);
  static const Color _ink = Color(0xFF3B2F22);
  static const Color _inkSoft = Color(0xFF8A6C45);
  static const Color _gold = Color(0xFFF5C96A);

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottom = 24 + mq.viewInsets.bottom + mq.padding.bottom;
    return Container(
      key: const Key('add-friend-sheet'),
      decoration: const BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 24, 20, bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome, color: _gold, size: 16),
                SizedBox(width: 6),
                Expanded(
                  child: Text('A house is waiting next to yours',
                      style: TextStyle(color: _gold, fontSize: 14, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _postcard(context),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('copy-invite-code'),
                onPressed: myCode.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: myCode));
                        ScaffoldMessenger.maybeOf(context)
                            ?.showSnackBar(const SnackBar(content: Text('Invite code copied.')));
                      },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy code'),
              ),
            ),
            const SizedBox(height: 22),
            const Text('GOT A POSTCARD?',
                style: TextStyle(
                    color: Color(0x99FFFFFF), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('invite-field'),
                    controller: controller,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Colors.white, letterSpacing: 2, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      hintText: "Friend's code",
                      hintStyle: const TextStyle(color: Colors.white38, letterSpacing: 0.5),
                      filled: true,
                      fillColor: const Color(0x14FFFFFF),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => onSubmit(),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  key: const Key('invite-submit'),
                  onPressed: onSubmit,
                  child: const Text('Add'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _postcard(BuildContext context) {
    return Transform.rotate(
      angle: -0.02,
      child: Container(
        key: const Key('invite-postcard'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 16),
        decoration: BoxDecoration(
          color: _paper,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 18, offset: Offset(0, 6))],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('YOUR TOWN ADDRESS',
                      style: TextStyle(
                          color: _inkSoft, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.3)),
                  const SizedBox(height: 2),
                  SelectableText(
                    myCode.isEmpty ? '—' : myCode,
                    key: const Key('my-invite-code'),
                    style: const TextStyle(
                        color: _ink, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 4),
                  ),
                  const SizedBox(height: 6),
                  const Text('Come live next door. Type this code in Sonnap to move in.',
                      style: TextStyle(color: Color(0xFF5C4A35), fontSize: 12.5, height: 1.4)),
                  const SizedBox(height: 10),
                  for (var i = 0; i < 2; i++) ...[
                    Container(height: 1.5, color: const Color(0xFFCDB88F)),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            ValueListenableBuilder<PetSpecies>(
              valueListenable: PetChoice.current,
              builder: (context, species, _) => _stamp(species),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stamp(PetSpecies species) => Container(
        key: const Key('invite-stamp'),
        width: 66,
        height: 76,
        decoration: BoxDecoration(
          color: const Color(0xFFE9D6AE),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.all(4),
        child: CustomPaint(
          painter: _DashedBorder(),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Image.asset(
              journeyHeadAsset(species),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Center(
                child: Icon(Icons.pets_rounded, color: _inkSoft, size: 28),
              ),
            ),
          ),
        ),
      );
}

/// 郵票的虛線邊。
class _DashedBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFB99558)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)));
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
