import 'package:shared_preferences/shared_preferences.dart';

/// Whether the app opens the Customized dashboard by default (pinned by user).
class StartupViewStorage {
  static const _kKey = 'pt_startup_prefer_customized_v1';

  static Future<bool> isCustomizedPinned() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kKey) ?? false;
  }

  static Future<void> setPreferCustomized(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kKey, v);
  }
}
