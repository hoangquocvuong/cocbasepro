import 'package:shared_preferences/shared_preferences.dart';

class AppStorage {

  static Future<SharedPreferences> prefs() async {
    return SharedPreferences.getInstance();
  }

}