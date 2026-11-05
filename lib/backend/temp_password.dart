import 'dart:math';

/// Easy-to-read first-login passwords such as `Pharm4821`.
abstract final class TempPassword {
  static String generate() {
    final random = Random.secure();
    final digits = List.generate(4, (_) => random.nextInt(10)).join();
    return 'Pharm$digits';
  }
}
