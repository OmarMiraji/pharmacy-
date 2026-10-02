import '../l10n/app_locale.dart';

class TanzaniaPhone {
  static const hint = '0712345678';

  static String get formatHelp => S.t(
        'Use a Tanzania number, e.g. 0712345678 or +255712345678',
        'Tumia namba ya Tanzania, mfano 0712345678 au +255712345678',
      );

  static String digits(String raw) => raw.replaceAll(RegExp(r'\D'), '');

  static String? nationalNine(String raw) {
    var d = digits(raw);
    if (d.startsWith('255')) d = d.substring(3);
    if (d.startsWith('0')) d = d.substring(1);
    if (d.length != 9) return null;
    if (d[0] != '6' && d[0] != '7') return null;
    if (int.tryParse(d) == null) return null;
    return d;
  }

  static bool isValid(String raw) => nationalNine(raw) != null;

  static String? validate(String? raw, {bool required = false}) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) {
      return required ? S.t('Phone number is required', 'Namba ya simu inahitajika') : null;
    }
    if (!isValid(text)) return formatHelp;
    return null;
  }

  static String? normalize(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return '';
    final national = nationalNine(text);
    if (national == null) return text;
    return '+255$national';
  }
}
