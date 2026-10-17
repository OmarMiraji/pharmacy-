import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../backend/report_export_service.dart';
import '../theme/brand.dart';

class MobilePage extends StatelessWidget {
  const MobilePage({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: PhyimacyBrand.forest,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PHARMSPECIO',
                          style: GoogleFonts.inter(
                            color: PhyimacyBrand.gold,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          title,
                          style: GoogleFonts.playfairDisplay(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: PhyimacyBrand.cream,
            child: child,
          ),
        ),
      ],
    );
  }
}

class MobileCard extends StatelessWidget {
  const MobileCard({required this.child, this.padding = const EdgeInsets.all(16), super.key});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: PhyimacyBrand.line),
      ),
      child: child,
    );
  }
}

class MobileStat extends StatelessWidget {
  const MobileStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return MobileCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: PhyimacyBrand.forest, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: PhyimacyBrand.ink),
          ),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: PhyimacyBrand.muted)),
        ],
      ),
    );
  }
}

class MobileEmpty extends StatelessWidget {
  const MobileEmpty({required this.title, required this.body, super.key});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, color: PhyimacyBrand.teal.withValues(alpha: 0.7), size: 28),
          const SizedBox(height: 8),
          Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: PhyimacyBrand.ink)),
          const SizedBox(height: 4),
          Text(body, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13, color: PhyimacyBrand.muted, height: 1.35)),
        ],
      ),
    );
  }
}

String mobileMoney(int minor) => ReportExportService.tzs(minor);

String mobileDate(DateTime time) {
  final day = time.day.toString().padLeft(2, '0');
  final month = time.month.toString().padLeft(2, '0');
  return '$day/$month/${time.year}';
}

String mobileClock(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
