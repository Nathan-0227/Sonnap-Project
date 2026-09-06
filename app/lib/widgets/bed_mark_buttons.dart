import 'package:flutter/material.dart';

import '../services/bed_marks.dart';
import '../services/key_value_store.dart';

/// 讓使用者自己宣告「上床」與「下床」的兩個按鈕。
///
/// ═══════════════════════════════════════════════════════════════
/// ⚠️ 這是**加分項不是取代品**
/// ═══════════════════════════════════════════════════════════════
/// 沒按的夜晚照樣有 `lights_out_at`（手機事件流被動推出來的「放下手機」，
/// 早上開 App 就回推得到昨晚，Android 事件保留 ≥5 天）。按了才多出
/// **臥床時間**與行為版睡眠效率。
///
/// 所以這兩個按鈕不可以做成「不按就沒有資料」的樣子，任何一段程式也
/// 不可以因為「沒有標記」就跳過上傳。`usage_stats_test.dart` 有一條
/// 反向對照守著這件事。
///
/// ⚠️ 按下去的時刻是**自述**，不是量到的。它與 `lights_out_at` 是兩個
/// 不同的量，後端各自算各自的（見 `behavior/sleep_efficiency.py`）。
///
/// 放在首頁：人是在首頁準備睡覺的。上傳與清除仍然在 Insights 頁那一輪
/// （`_loadUsage`）做——兩邊共用同一份本機儲存，不必互相知道。
class BedMarkButtons extends StatefulWidget {
  final BedMarkStore store;

  /// 標記變動時通知外面（首頁目前不需要，留給之後接寵物狀態用）。
  final ValueChanged<BedMarks>? onChanged;

  const BedMarkButtons({
    super.key,
    this.store = const BedMarkStore(PlatformKeyValueStore()),
    this.onChanged,
  });

  @override
  State<BedMarkButtons> createState() => _BedMarkButtonsState();
}

class _BedMarkButtonsState extends State<BedMarkButtons> {
  BedMarks _marks = BedMarks.none;

  static const Color _purple = Color(0xFF8B6DFF);
  static const Color _card = Color(0xFF1B2548);
  static const Color _muted = Color(0xFF8498B7);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final marks = await widget.store.read();
    if (!mounted) return;
    setState(() => _marks = marks);
    widget.onChanged?.call(marks);
  }

  Future<void> _mark({required bool start}) async {
    final now = DateTime.now();
    if (start) {
      await widget.store.markStart(now);
    } else {
      await widget.store.markEnd(now);
    }
    await _refresh();
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final started = _marks.hasStart;
    final done = _marks.isComplete;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Going to bed?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          // ⚠️ 這句話很重要：它是使用者唯一會看到的「不按也沒關係」。
          //    少了它，忘記按的人會以為那一晚白過了。
          // ⚠️ 按下「下床」之後**畫面一定要看得出來變了**。
          //    第一版沒有：按完 started 仍然是 true，卡片長得一模一樣，
          //    使用者按了以為沒反應。實機才發現（2026-09-07）。
          Text(
            done
                ? 'Saved. It uploads next time you open the app.'
                : started
                    ? 'Tap "Out of bed" when you get up.'
                    : 'Optional - bedtime is detected anyway. Tapping just adds '
                        'how long you were in bed.',
            style: TextStyle(
              color: done ? _purple : _muted,
              fontSize: 10,
              fontWeight: done ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _mark(start: true),
                  icon: Icon(
                    started
                        ? Icons.bedtime_rounded
                        : Icons.bedtime_outlined,
                    size: 16,
                  ),
                  label: Text(
                    started ? 'In bed since ${_hhmm(_marks.startAt!)}' : 'Start sleep',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: started ? _purple : Colors.white,
                    side: const BorderSide(color: _purple),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  // 沒有起點的結束算不出任何東西，所以先按開始才能按結束。
                  onPressed: started ? () => _mark(start: false) : null,
                  icon: Icon(
                    done ? Icons.check_circle_rounded : Icons.wb_sunny_outlined,
                    size: 16,
                  ),
                  label: Text(
                    done ? 'Up at ${_hhmm(_marks.endAt!)}' : 'Out of bed',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    // 完成之後換成強調色，跟左邊那顆一樣 —— 這是「有記到」
                    // 唯一的視覺回饋。
                    foregroundColor: done ? _purple : Colors.white,
                    side: BorderSide(
                        color: done ? _purple : const Color(0xFF3A4A63)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
