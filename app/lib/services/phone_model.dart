import 'package:flutter/services.dart';

/// 這支手機叫什麼（好友頁的「用了哪些設備」，2026-11-16 使用者定）。
///
/// Android 只給廠商與型號代碼（三星是 `SM-S9260` 這種），沒有行銷名稱；
/// 下面這張表把常見的代碼換成「Samsung Galaxy S24+」，表裡沒有的就照寫代碼。
/// ⚠️ **不用**使用者自己取的裝置名稱（設定裡那個）：那常常含本人的名字。
const kPhoneModelNames = {
  // 三星：前 7 碼就決定是哪一支（後面是地區版本）
  'SM-S921': 'Galaxy S24',
  'SM-S926': 'Galaxy S24+',
  'SM-S928': 'Galaxy S24 Ultra',
  'SM-S931': 'Galaxy S25',
  'SM-S936': 'Galaxy S25+',
  'SM-S938': 'Galaxy S25 Ultra',
  'SM-S911': 'Galaxy S23',
  'SM-S916': 'Galaxy S23+',
  'SM-S918': 'Galaxy S23 Ultra',
  'SM-A556': 'Galaxy A55',
  'SM-A546': 'Galaxy A54',
  'SM-A356': 'Galaxy A35',
  'SM-F956': 'Galaxy Z Fold6',
  'SM-F741': 'Galaxy Z Flip6',
};

/// 廠商＋型號代碼 → 顯示的名字。純函式，測得到。
String phoneModelName(String? manufacturer, String? model) {
  final m = (model ?? '').trim();
  final brand = (manufacturer ?? '').trim();
  if (m.isEmpty) return '';
  final prettyBrand = brand.isEmpty
      ? ''
      : brand[0].toUpperCase() + brand.substring(1).toLowerCase();
  if (m.length >= 7 && kPhoneModelNames.containsKey(m.substring(0, 7))) {
    return '$prettyBrand ${kPhoneModelNames[m.substring(0, 7)]}'.trim();
  }
  // 型號本身已經是名字（Pixel 8、Pixel 9 Pro…）或已含廠商名時，不要再接一次廠商
  if (prettyBrand.isEmpty || m.toLowerCase().startsWith(brand.toLowerCase())) {
    return m;
  }
  return '$prettyBrand $m';
}

/// 從原生端讀一次（讀不到 → null，不擋任何東西）。
Future<String?> readPhoneModel() async {
  try {
    final r = await const MethodChannel(
      'sonnap/usage',
    ).invokeMapMethod<String, dynamic>('deviceModel');
    final name = phoneModelName(
      r?['manufacturer'] as String?,
      r?['model'] as String?,
    );
    return name.isEmpty ? null : name;
  } catch (_) {
    return null;
  }
}
