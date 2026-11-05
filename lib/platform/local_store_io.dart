import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Small text values kept on this device (app support folder).
abstract final class LocalStore {
  static Future<File> _file(String name) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  static Future<String?> read(String name) async {
    final file = await _file(name);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  static Future<void> write(String name, String value) async {
    final file = await _file(name);
    await file.parent.create(recursive: true);
    await file.writeAsString(value, flush: true);
  }

  static Future<void> delete(String name) async {
    final file = await _file(name);
    if (await file.exists()) await file.delete();
  }
}
