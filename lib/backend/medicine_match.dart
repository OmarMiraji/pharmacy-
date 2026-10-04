import 'models.dart';

class MedicineMatch {
  static String key(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool matches(Medicine medicine, String query) {
    final wanted = query.trim().toLowerCase();
    if (wanted.isEmpty) return true;
    return medicine.name.toLowerCase().contains(wanted) ||
        medicine.sku.toLowerCase().contains(wanted) ||
        (medicine.genericName ?? '').toLowerCase().contains(wanted);
  }

  static Medicine? findIn(Iterable<Medicine> medicines, String name) {
    final wanted = key(name);
    if (wanted.isEmpty) return null;
    for (final medicine in medicines) {
      if (key(medicine.name) == wanted) return medicine;
    }
    return null;
  }

  static List<Medicine> unique(List<Medicine> medicines) {
    final best = <String, Medicine>{};
    for (final medicine in medicines) {
      final id = key(medicine.name);
      if (id.isEmpty) continue;
      final previous = best[id];
      if (previous == null || medicine.quantityOnHand > previous.quantityOnHand) {
        best[id] = medicine;
      }
    }
    return best.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }
}
