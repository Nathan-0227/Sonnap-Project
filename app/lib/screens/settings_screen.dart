import 'package:flutter/material.dart';

import '../services/account_service.dart';

class SettingsScreen extends StatefulWidget {
  final String username;
  final String email;
  final String petName;
  final String language;
  final String appearance;
  final String appVersion;

  final bool initialReminderOn;
  final TimeOfDay initialTargetBedtime;

  final ValueChanged<bool>? onReminderChanged;
  final ValueChanged<TimeOfDay>? onBedtimeChanged;

  final VoidCallback? onEditProfile;
  final VoidCallback? onAppearanceTap;
  final VoidCallback? onPetTap;
  final VoidCallback? onLanguageTap;
  final VoidCallback? onAboutTap;
  final VoidCallback? onLogout;

  const SettingsScreen({
    super.key,
    this.username = kFallbackDisplayName,
    this.email = "jeremy@email.com",
    this.petName = "Golden Retriever",
    this.language = "English",
    this.appearance = "Dark Mode",
    this.appVersion = "Version 1.0",
    this.initialReminderOn = true,
    this.initialTargetBedtime = const TimeOfDay(
      hour: 23,
      minute: 30,
    ),
    this.onReminderChanged,
    this.onBedtimeChanged,
    this.onEditProfile,
    this.onAppearanceTap,
    this.onPetTap,
    this.onLanguageTap,
    this.onAboutTap,
    this.onLogout,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool reminderOn;
  late TimeOfDay targetBedtime;

  @override
  void initState() {
    super.initState();

    reminderOn = widget.initialReminderOn;
    targetBedtime = widget.initialTargetBedtime;
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.initialReminderOn != widget.initialReminderOn) {
      reminderOn = widget.initialReminderOn;
    }

    if (oldWidget.initialTargetBedtime != widget.initialTargetBedtime) {
      targetBedtime = widget.initialTargetBedtime;
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');

    return "$hour:$minute";
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
    });

    widget.onBedtimeChanged?.call(picked);
  }

  void _changeReminder(bool value) {
    setState(() {
      reminderOn = value;
    });

    widget.onReminderChanged?.call(value);
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("$feature will be available later."),
      ),
    );
  }

  void _handleLogout() {
    if (widget.onLogout != null) {
      widget.onLogout!();
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF10265A),
          title: const Text(
            "Log out?",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            "Are you sure you want to log out of Sonnap?",
            style: TextStyle(
              color: Colors.white70,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text(
                "Cancel",
                style: TextStyle(
                  color: Colors.white70,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Logout will be connected after authentication is ready.",
                    ),
                  ),
                );
              },
              child: const Text(
                "Log Out",
                style: TextStyle(
                  color: Color(0xFFFF6B6B),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SizedBox(
          width: MediaQuery.of(context).size.width > 520
              ? 520
              : MediaQuery.of(context).size.width,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Settings",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                const Text(
                  "Manage your account and sleep preferences.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 24),

                _buildProfileCard(),

                const SizedBox(height: 20),

                const _SectionTitle(
                  title: "Preferences",
                ),

                const SizedBox(height: 12),

                _buildSettingTile(
                  icon: Icons.dark_mode_rounded,
                  title: "Appearance",
                  subtitle: widget.appearance,
                  onTap: widget.onAppearanceTap ??
                      () => _showComingSoon("Appearance settings"),
                ),

                const SizedBox(height: 12),

                _buildReminderTile(),

                const SizedBox(height: 12),

                _buildSettingTile(
                  icon: Icons.access_time_rounded,
                  title: "Target Bedtime",
                  subtitle: _formatTimeOfDay(targetBedtime),
                  onTap: _pickBedtime,
                ),

                const SizedBox(height: 12),

                _buildSettingTile(
                  icon: Icons.pets_rounded,
                  title: "Pet",
                  subtitle: widget.petName,
                  onTap: widget.onPetTap ??
                      () => _showComingSoon("Pet settings"),
                ),

                const SizedBox(height: 12),

                _buildSettingTile(
                  icon: Icons.language_rounded,
                  title: "Language",
                  subtitle: widget.language,
                  onTap: widget.onLanguageTap ??
                      () => _showComingSoon("Language settings"),
                ),

                const SizedBox(height: 24),

                const _SectionTitle(
                  title: "Support",
                ),

                const SizedBox(height: 12),

                _buildSettingTile(
                  icon: Icons.info_outline_rounded,
                  title: "About Sonnap",
                  subtitle: widget.appVersion,
                  onTap: widget.onAboutTap ??
                      () => _showComingSoon("About Sonnap"),
                ),

                const SizedBox(height: 30),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _handleLogout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5F68),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(56),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    icon: const Icon(
                      Icons.logout_rounded,
                    ),
                    label: const Text(
                      "Log Out",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onEditProfile ??
            () => _showComingSoon("Profile editing"),
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF10265A),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 32,
                backgroundColor: Color(0xFF5B5CFF),
                child: Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      widget.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              const Icon(
                Icons.edit_rounded,
                color: Color(0xFFFFD96A),
                size: 21,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReminderTile() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF10265A),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Icon(
            reminderOn
                ? Icons.notifications_active_rounded
                : Icons.notifications_off_rounded,
            color: const Color(0xFFFFD96A),
          ),

          const SizedBox(width: 16),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Bedtime Reminder",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                SizedBox(height: 3),

                Text(
                  "Receive a reminder every night",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          Switch(
            value: reminderOn,
            activeThumbColor: const Color(0xFF8B6DFF),
            activeTrackColor:
                const Color(0xFF8B6DFF).withValues(alpha: 0.45),
            inactiveThumbColor: Colors.white70,
            inactiveTrackColor: Colors.white24,
            onChanged: _changeReminder,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF10265A),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: const Color(0xFFFFD96A),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white54,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 13,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.7,
      ),
    );
  }
}