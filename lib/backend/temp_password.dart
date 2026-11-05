import 'dart:math';

/// Easy-to-read first-login passwords such as `Dawa4821`: one familiar word plus four digits.
abstract final class TempPassword {
  static const _words = ['Dawa', 'Afya', 'Tiba', 'Pona', 'Nuru', 'Zuri', 'Imara', 'Tumaini', 'Baraka', 'Upendo'];

  static String generate() {
    final random = Random.secure();
    final word = _words[random.nextInt(_words.length)];
    final digits = List.generate(4, (_) => random.nextInt(10)).join();
    return '$word$digits';
  }
}
