import 'package:flutter/material.dart';

import '../theme/app_accent.dart';

/// 設定頁與它點進去的頁面（守門、Health Connect、What friends can see、換寵物）共用的樣子
/// （2026-11-22 設定頁改版，畫布「A 分組＋B 名片」）：深藍底、分組小標、圓角卡片裡一列一列、
/// 前面彩色小圖示。改樣子只改這裡，幾頁才不會各長各的。

const kSettingsBg = Color(0xFF0B1430);
const kSettingsCard = Color(0xFF16224A);
const kSettingsLine = Color(0xFF24335F);
const kSettingsSub = Color(0xFFA9B2D6);
/// 紫色主題的主色。⚠️ 畫面上一律用 `accentOf(context)`（跟著主題色換），這個只當預設值。
const kSettingsAccent = Color(0xFF7657FF);

/// 點開的面板底色。⚠️ showReportSheet 的外框是透明的，底色要內容自己畫。
const kSettingsSheetColor = Color(0xFF141A45);

/// 點進去的那幾頁：圓的返回鈕＋置中標題，底下一條捲得動的清單。
class SettingsPage extends StatelessWidget {
  final String title;
  final List<Widget> children;

  /// 還在讀：畫轉圈，不畫 [children]。
  final bool loading;

  /// 讀不到時取代清單的那句話。
  final Widget? placeholder;

  final Key? listKey;

  const SettingsPage({
    super.key,
    required this.title,
    required this.children,
    this.loading = false,
    this.placeholder,
    this.listKey,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: kSettingsBg,
      body: SafeArea(
        child: Center(
          child: SizedBox(
            width: width > 520 ? 520 : width,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SettingsHeader(title: title, onBack: () => Navigator.of(context).maybePop()),
                ),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : placeholder ??
                          ListView(
                            key: listKey,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                            children: children,
                          ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 圓的返回鈕＋置中標題。[onBack] null＝不畫返回鈕。
class SettingsHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  const SettingsHeader({super.key, required this.title, this.onBack});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (onBack case final back?)
              Align(
                alignment: Alignment.centerLeft,
                child: Material(
                  color: kSettingsCard,
                  shape: const CircleBorder(),
                  child: IconButton(
                    key: const Key('settings-back'),
                    tooltip: 'Back',
                    onPressed: back,
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 52),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
}

/// 一段說明（灰字）。
class SettingsNote extends StatelessWidget {
  final String text;
  const SettingsNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 16),
        child: Text(text, style: const TextStyle(color: kSettingsSub, fontSize: 14, height: 1.45)),
      );
}

/// 一組：小標＋一張圓角卡片，裡面的列之間一條細線。
class SettingsGroup extends StatelessWidget {
  final String? title;
  final List<Widget> rows;
  const SettingsGroup({super.key, this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 8),
              child: Text(
                title!,
                style: const TextStyle(color: kSettingsSub, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1),
              ),
            ),
          Material(
            color: kSettingsCard,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const Divider(height: 1, thickness: 1, color: kSettingsLine, indent: 14),
                  rows[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 一列：（彩色小圖示）＋標題／小字＋右邊（值、開關、勾、或箭頭）。
class SettingsRow extends StatelessWidget {
  final IconData? icon;
  final Color? color;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dense;

  const SettingsRow({
    super.key,
    this.icon,
    this.color,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final end = trailing ??
        (value != null
            ? Text(value!, style: const TextStyle(color: kSettingsSub, fontSize: 14))
            : (onTap != null ? const Icon(Icons.chevron_right_rounded, color: kSettingsSub) : null));
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: dense ? 48 : 52),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 8 : 10),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: color ?? accentOf(context), borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: Colors.white, size: 19),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(color: Colors.white, fontSize: dense ? 14 : 15, fontWeight: FontWeight.w700),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!, style: const TextStyle(color: kSettingsSub, fontSize: 12, height: 1.35)),
                      ),
                  ],
                ),
              ),
              if (end != null) ...[const SizedBox(width: 8), end],
            ],
          ),
        ),
      ),
    );
  }
}

/// 單選的圈（選中＝主色實心勾）。
class SettingsRadio extends StatelessWidget {
  final bool selected;
  const SettingsRadio({super.key, required this.selected});

  @override
  Widget build(BuildContext context) => Icon(
        selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
        color: selected ? accentOf(context) : kSettingsSub,
        size: 24,
      );
}

/// 複選的方塊（選中＝主色實心勾）。
class SettingsCheck extends StatelessWidget {
  final bool checked;
  const SettingsCheck({super.key, required this.checked});

  @override
  Widget build(BuildContext context) => Icon(
        checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
        color: checked ? accentOf(context) : kSettingsSub,
        size: 24,
      );
}

/// 開關（主色）。
class SettingsSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const SettingsSwitch({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) => Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: Colors.white,
        activeTrackColor: accentOf(context),
      );
}
