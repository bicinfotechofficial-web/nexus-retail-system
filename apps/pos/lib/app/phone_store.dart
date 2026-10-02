import 'package:shared_preferences/shared_preferences.dart';

/// Small settings kept on this phone, not in the database. Behind an
/// interface so tests use an in-memory store and can "restart" the app with
/// the same one.
abstract interface class PhoneStore {
  Future<bool?> getBool(String key);
  Future<void> setBool(String key, bool value);
  Future<List<String>?> getStringList(String key);
  Future<void> setStringList(String key, List<String> value);
}

/// The keys used on the phone. Each is per signed-in user, so two Store
/// Managers sharing a phone keep their own choices.
abstract final class PhoneKeys {
  static String reviewBeforeSave(String uid) => 'reviewBeforeSave.$uid';
  static String seenSuggestions(String uid) => 'seenSuggestions.$uid';
}

/// [PhoneStore] on `shared_preferences`.
final class SharedPrefsPhoneStore implements PhoneStore {
  const SharedPrefsPhoneStore();

  @override
  Future<bool?> getBool(String key) async =>
      (await SharedPreferences.getInstance()).getBool(key);

  @override
  Future<void> setBool(String key, bool value) async {
    await (await SharedPreferences.getInstance()).setBool(key, value);
  }

  @override
  Future<List<String>?> getStringList(String key) async =>
      (await SharedPreferences.getInstance()).getStringList(key);

  @override
  Future<void> setStringList(String key, List<String> value) async {
    await (await SharedPreferences.getInstance()).setStringList(key, value);
  }
}
