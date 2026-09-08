import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'bedtime_urgency.dart';

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

    // ⚠️ 顏色由 [bedtimeUrgency] 決定，**不要在這裡自己比 Duration**。
    //    那個判斷有一段不直覺的地方（剛過就寢時間時倒數顯示的是 23 小時多，
    //    看起來像「還很充裕」），寫在純函式裡才測得到、也才只有一份。
    final urgency = bedtimeUrgency(now, targetBedtime);
    final urgencyColor = bedtimeUrgencyColor(urgency);

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

          // ⚠️ 這一段原本是「Expanded(flex:3) + 寫死 150×150 的圓環」。
          //    圓環不會縮，所以畫面一窄，左邊剩下的空間就不夠放 52px 的時鐘：
          //    360dp 折成 3 行、320dp 折成 5 行（一行一個字），還會噴出兩處
          //    RenderFlex 溢位。使用者把系統字級調大時更早發生。
          //    → 圓環改成跟著寬度縮，時鐘與底下那行改用 FittedBox 等比縮小
          //      而不是折行。`header_card_test.dart` 有四條守著。
          LayoutBuilder(
            builder: (context, constraints) {
              // 圓環最多 150，但不吃掉超過一半的寬度。
              final ring = math.min(150.0, constraints.maxWidth * 0.42);

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            currentTime,
                            maxLines: 1,
                            softWrap: false,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 52,
                              fontWeight: FontWeight.bold,
                            ),
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
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "Target bedtime $targetBedtimeText",
                                    maxLines: 1,
                                    softWrap: false,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
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
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 24),

                  SizedBox(
                    width: ring,
                    height: ring,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: ring,
                          height: ring,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 12,
                            backgroundColor: Colors.white24,
                            color: urgencyColor,
                          ),
                        ),
                        // 圓環裡的字也要跟著縮——不然系統字級一調大就從
                        // 圓環下緣溢位（實測 textScale 1.3 溢出 25px）。
                        Padding(
                          padding: EdgeInsets.all(ring * 0.16),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Column(
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
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  timeLeft,
                                  // ⚠️ 測試靠這個 key 找到它。原本是靠
                                  //    「FittedBox 底下唯一的 Text」定位，
                                  //    但版面一改就有好幾個 FittedBox 了。
                                  key: const Key('bedtime-countdown'),
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: urgencyColor,
                                    fontSize: 30,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  bedtimeUrgencyCaption(urgency),
                                  maxLines: 1,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
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
              // 同一個毛病的第三處：這顆藥丸在 320dp + 字級 1.3 下
              // 往右溢出 99px。ON/OFF 是這行唯一的資訊，不能用
              // ellipsis 截掉，所以整排等比縮。
              child: FittedBox(
                fit: BoxFit.scaleDown,
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
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}