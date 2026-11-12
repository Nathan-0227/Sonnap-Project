import 'package:flutter/material.dart';

/// 首頁上方的「Today / Tonight」切換。
///
/// 預設由時間自動選（見 `home_mode.dart`），使用者可以手動切；
/// 切換只活在這次開著的 App 裡，下次打開恢復自動（2026-11-12 定案）。
/// 主要用途：白天的成果展也看得到晚上版；傍晚想看昨晚分數的人切得回去。
class HomeModeToggle extends StatelessWidget {
  final bool tonight;
  final ValueChanged<bool> onChanged;

  const HomeModeToggle({
    super.key,
    required this.tonight,
    required this.onChanged,
  });

  static const Color _track = Color(0xFF1B2548);
  static const Color _thumb = Color(0xFF8B6DFF);

  Widget _segment(String label, bool selected, VoidCallback onTap, Key key) {
    return Expanded(
      child: GestureDetector(
        key: key,
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? _thumb : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white60,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _track,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          _segment('Today', !tonight, () => onChanged(false),
              const Key('mode-today')),
          _segment('Tonight', tonight, () => onChanged(true),
              const Key('mode-tonight')),
        ],
      ),
    );
  }
}
