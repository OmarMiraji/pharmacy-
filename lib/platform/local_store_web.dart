import 'package:web/web.dart' as web;

/// Small text values kept in this browser (localStorage).
abstract final class LocalStore {
  static String _key(String name) => 'pharmspecio.$name';

  static Future<String?> read(String name) async => web.window.localStorage.getItem(_key(name));

  static Future<void> write(String name, String value) async {
    web.window.localStorage.setItem(_key(name), value);
  }

  static Future<void> delete(String name) async {
    web.window.localStorage.removeItem(_key(name));
  }
}
