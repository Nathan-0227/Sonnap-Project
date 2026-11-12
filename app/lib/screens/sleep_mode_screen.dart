import 'dart:async';

import 'package:flutter/material.dart';

import '../services/bed_marks.dart';
import '../widgets/sleepy_pet.dart';

/// 按了「Start sleep」之後佔滿整個畫面的睡覺畫面（2026-11-12 定案）。
///
/// ⚠️ 幾條不能破的規則：
/// - **不讓螢幕常亮。** 我們是靠「手機什麼時候上鎖／解鎖」推就寢時刻
///   （`lights_out.dart`）。螢幕一直亮著，手機整晚不上鎖，那一晚就抓不到。
/// - **不放任何即時數據**，也不寫「measuring／tracking」：睡覺時 App 沒有在量東西，
///   放上去等於造假。
/// - **有 Cancel**：不小心按到開始的人，只能按「下床」離開的話會留下一筆兩分鐘
///   的假睡眠，而上床按鈕是驗證攝影機唯一的 ground truth。
/// - 返回鍵擋掉：只能用「下床」或「取消」離開。導覽列不在這一頁上。
///
/// 鬧鐘、睡眠音樂、「I already got up」分別在之後的 PR 加，這一版刻意不放
/// 還不能用的按鈕。
class SleepModeScreen extends StatefulWidget {
  final BedMarkStore store;
  final DateTime startAt;
  final DateTime Function() clock;

  const SleepModeScreen({
    super.key,
    required this.store,
    required this.startAt,
    this.clock = DateTime.now,
  });

  @override
  State<SleepModeScreen> createState() => _SleepModeScreenState();
}

class _SleepModeScreenState extends State<SleepModeScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _outOfBed() async {
    await widget.store.markEnd(widget.clock());
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1B2350),
        title: const Text('Cancel this sleep?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'This removes the "Start sleep" you just tapped. Nothing else changes.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep sleeping'),
          ),
          TextButton(
            key: const Key('sleep-cancel-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel sleep',
                style: TextStyle(color: Color(0xFFFF8A8A))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.cancelStart();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.clock();
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0F1530), Color(0xFF1B2350), Color(0xFF2A2766)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  FittedBox(
                    child: Text(
                      _hhmm(now),
                      key: const Key('sleep-clock'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 76,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  Text(
                    'Sleep mode · since ${_hhmm(widget.startAt)}',
                    key: const Key('sleep-since'),
                    style: const TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  const Spacer(),
                  const SleepyPet(size: 260),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('sleep-out-of-bed'),
                      onPressed: _outOfBed,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFB9A6FF),
                        foregroundColor: const Color(0xFF1B2350),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Out of bed',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  TextButton(
                    key: const Key('sleep-cancel'),
                    onPressed: _cancel,
                    child: const Text(
                      'Not sleeping? Cancel',
                      style: TextStyle(
                        color: Colors.white60,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white60,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
