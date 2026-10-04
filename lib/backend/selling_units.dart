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
    if (id == 'lot' && toBase > 1) {
      final tablets = sellQty * toBase;
      return '$tablets $baseLabel${tablets == 1 ? '' : 's'} ($sellQty × $toBase)';
    }
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

  static bool sellsByPiece(String unit) {
    final value = normalize(unit);
    return value == 'Tablet' || value == 'Capsule';
  }

  static int costPerStockUnit({
    required String unit,
    required int purchasePriceMinor,
    int packSize = 1,
    int minSaleQty = 0,
  }) {
    if (purchasePriceMinor <= 0) return 0;
    final size = packSize < 1 ? 1 : packSize;
    if (sellsByPiece(unit) && size <= 1) {
      final lot = minSaleQty > 1 ? minSaleQty : 5;
      return (purchasePriceMinor / lot).round();
    }
    if (size > 1) return (purchasePriceMinor / size).round();
    return purchasePriceMinor;
  }

  static String normalize(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return 'Tablet';
    for (final option in options) {
      if (option.toLowerCase() == value.toLowerCase()) return option;
    }
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }
}
