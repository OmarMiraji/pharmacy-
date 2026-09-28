class SellUnit {
  const SellUnit({
    required this.id,
    required this.label,
    required this.toBase,
    required this.unitPriceMinor,
    required this.baseLabel,
  });

  final String id;
  final String label;
  final int toBase;
  final int unitPriceMinor;
  final String baseLabel;

  String get pluralLabel {
    if (label.toLowerCase().endsWith('s')) return label;
    if (label.toLowerCase() == 'box') return 'Boxes';
    return '${label}s';
  }

  String receiptCaption(int sellQty) {
    final unitWord = sellQty == 1 ? label : pluralLabel;
    if (id == 'base' || toBase <= 1) {
      return '$sellQty $unitWord';
    }
    return '$sellQty $unitWord ($toBase $baseLabel${toBase == 1 ? '' : 's'})';
  }
}

abstract final class BaseUnits {
  static const options = <String>[
    'Tablet',
    'Capsule',
    'Bottle',
    'Tube',
    'Vial',
    'Ampoule',
    'Sachet',
    'Piece',
    'Strip',
  ];

  static String normalize(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return 'Tablet';
    for (final option in options) {
      if (option.toLowerCase() == value.toLowerCase()) return option;
    }
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }
}
