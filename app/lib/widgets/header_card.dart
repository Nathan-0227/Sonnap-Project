import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class HeaderCard extends StatefulWidget {
  final String username;
  final String message;
  final bool initialReminderOn;
  final TimeOfDay initialTargetBedtime;
  final ValueChanged<bool>? onReminderChanged;
  final ValueChanged<TimeOfDay>? onBedtimeChanged;

  const HeaderCard({
    super.key,
    required this.username,
    required this.message,
    this.initialReminderOn = true,
    this.initialTargetBedtime = const TimeOfDay(
      hour: 23,
      minute: 30,
    ),
    this.onReminderChanged,
    this.onBedtimeChanged,
  });

  @override
  State<HeaderCard> createState() => _HeaderCardState();
}

class _HeaderCardState extends State<HeaderCard> {
  late TimeOfDay targetBedtime;
  late bool reminderOn;

  Timer? timer;
  late Duration initialCountdownDuration;

  @override
  void initState() {
    super.initState();

    targetBedtime = widget.initialTargetBedtime;
    reminderOn = widget.initialReminderOn;

    initialCountdownDuration = _getTimeLeftDuration(
      DateTime.now(),
      targetBedtime,
    );

    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;

      setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant HeaderCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.initialReminderOn != widget.initialReminderOn) {
      reminderOn = widget.initialReminderOn;
    }

    if (oldWidget.initialTargetBedtime != widget.initialTargetBedtime) {
      targetBedtime = widget.initialTargetBedtime;

      initialCountdownDuration = _getTimeLeftDuration(
        DateTime.now(),
        targetBedtime,
      );
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Duration _getTimeLeftDuration(
    DateTime now,
    TimeOfDay bedtime,
  ) {
    DateTime nextBedtime = DateTime(
      now.year,
      now.month,
      now.day,
      bedtime.hour,
      bedtime.minute,
    );

    if (!nextBedtime.isAfter(now)) {
      nextBedtime = nextBedtime.add(const Duration(days: 1));
    }

    return nextBedtime.difference(now);
  }

  String _getGreeting(DateTime now) {
    if (now.hour < 12) {
      return "Good morning ☀️";
    }

    if (now.hour < 18) {
      return "Good afternoon 🌤";
    }

    return "Good evening 🌙";
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');

    return "$hour:$minute";
  }

  String _calculateTimeLeft(
    DateTime now,
    TimeOfDay bedtime,
  ) {
    final difference = _getTimeLeftDuration(now, bedtime);
    final hours = difference.inHours;
    final minutes = difference.inMinutes.remainder(60);

    return "${hours.toString().padLeft(2, '0')}:"
        "${minutes.toString().padLeft(2, '0')}";
  }

  Future<void> _pickBedtime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: targetBedtime,
      initialEntryMode: TimePickerEntryMode.dial,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            alwaysUse24HourFormat: true,
          ),
          child: Theme(
            data: ThemeData.dark(),
            child: child!,
          ),
        );
      },
    );

    if (picked == null || !mounted) return;

    setState(() {
      targetBedtime = picked;

      initialCountdownDuration = _getTimeLeftDuration(
        DateTime.now(),
        picked,
      );
    });

    widget.onBedtimeChanged?.call(picked);
  }

  void _toggleReminder() {
    setState(() {
      reminderOn = !reminderOn;
    });

    widget.onReminderChanged?.call(reminderOn);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    final currentTime = DateFormat('HH:mm').format(now);
    final greeting = _getGreeting(now);
    final targetBedtimeText = _formatTimeOfDay(targetBedtime);
    final timeLeft = _calculateTimeLeft(now, targetBedtime);

    final remainingDuration = _getTimeLeftDuration(
      now,
      targetBedtime,
    );

    final rawProgress = initialCountdownDuration.inSeconds <= 0
        ? 0.0
        : remainingDuration.inSeconds /
            initialCountdownDuration.inSeconds;

    final progress = rawProgress.clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF10265A),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            greeting,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            widget.username,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            widget.message,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),

          const SizedBox(height: 24),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentTime,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 52,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 6),

                    InkWell(
                      onTap: _pickBedtime,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 5,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                "Target bedtime $targetBedtimeText",
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.edit,
                              color: Color(0xFFFFD96A),
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 24),

              SizedBox(
                width: 150,
                height: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 150,
                      height: 150,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 12,
                        backgroundColor: Colors.white24,
                        color: const Color(0xFF8B6DFF),
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.access_time,
                          color: Colors.white,
                          size: 30,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          "Time Left",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        // 倒數字串較長時（例如 "23h 42m"）在 30px 字級下會
                        // 換行，把 150×150 的圓環撐破、出現黃黑斜線。
                        // 因為長度隨當下時間變化，這個問題只在某些時段出現。
                        // FittedBox 讓它需要時等比縮小而不是換行。
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            timeLeft,
                            maxLines: 1,
                            style: const TextStyle(
                              color: Color(0xFFFFD96A),
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Text(
                          "to bedtime",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          InkWell(
            onTap: _toggleReminder,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF233A73),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    reminderOn
                        ? Icons.notifications_active
                        : Icons.notifications_off,
                    color: const Color(0xFFFFD96A),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    reminderOn
                        ? "Bedtime reminder ON"
                        : "Bedtime reminder OFF",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}