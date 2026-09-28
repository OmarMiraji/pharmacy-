import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../theme/brand.dart';

class LanguageToggle extends StatelessWidget {
  const LanguageToggle({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLocale.instance,
      builder: (context, _) {
        final sw = AppLocale.instance.isSw;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: compact ? PhyimacyBrand.cream : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xffd7e6e2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _chip(label: 'EN', selected: !sw, onTap: () => AppLocale.instance.setCode('en')),
              _chip(label: 'SW', selected: sw, onTap: () => AppLocale.instance.setCode('sw')),
            ],
          ),
        );
      },
    );
  }

  Widget _chip({required String label, required bool selected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: compact ? 6 : 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xff0f766e) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : const Color(0xff68807d),
          ),
        ),
      ),
    );
  }
}
