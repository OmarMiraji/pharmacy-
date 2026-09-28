import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AppLocale extends ChangeNotifier {
  AppLocale._();
  static final AppLocale instance = AppLocale._();

  String code = 'en';

  bool get isSw => code == 'sw';

  Future<void> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final saved = (await file.readAsString()).trim();
        if (saved == 'sw' || saved == 'en') code = saved;
      }
    } catch (_) {}
  }

  void setCode(String next) {
    final value = next == 'sw' ? 'sw' : 'en';
    if (value == code) return;
    code = value;
    notifyListeners();
    unawaited(_persist(value));
  }

  Future<void> _persist(String value) async {
    try {
      final file = await _file();
      await file.writeAsString(value);
    } catch (_) {}
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/app_locale.txt');
  }
}

abstract final class S {
  static String t(String en, String sw) => AppLocale.instance.isSw ? sw : en;

  static String monthName(int month) {
    const en = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    const sw = [
      'Januari', 'Februari', 'Machi', 'Aprili', 'Mei', 'Juni',
      'Julai', 'Agosti', 'Septemba', 'Oktoba', 'Novemba', 'Desemba',
    ];
    final index = (month - 1).clamp(0, 11);
    return t(en[index], sw[index]);
  }

  static String role(String role) => switch (role.replaceAll(' ', '_').toLowerCase()) {
        'admin' => t('admin', 'msimamizi'),
        'cashier' => t('cashier', 'cashier'),
        'pharmacist' => t('pharmacist', 'mfamasia'),
        'storekeeper' => t('storekeeper', 'mhifadhi'),
        'super_admin' => t('super admin', 'msimamizi mkuu'),
        _ => role.replaceAll('_', ' '),
      };
}
