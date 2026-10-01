import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Pharmacy POS brand colors and shared form look. Visual only.
class PhyimacyBrand {
  static const appName = 'PharmSpecio';
  static const tagline = 'Pharmacy Management System';
  static const logoAsset = 'assets/brand/pharmspecio.png';
  static const forest = Color(0xFF073B3A);
  static const teal = Color(0xFF0F766E);
  static const mint = Color(0xFF5EEAD4);
  static const gold = Color(0xFFE8C47A);
  static const cream = Color(0xFFF7F4EC);
  static const ink = Color(0xFF143230);
  static const muted = Color(0xFF5B736F);
  static const line = Color(0xFFD7E5E1);

  static OutlineInputBorder _box({Color color = line, double width = 1}) {
    return OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static ThemeData get material {
    final textTheme = GoogleFonts.interTextTheme().apply(
      bodyColor: ink,
      displayColor: ink,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: teal,
        brightness: Brightness.light,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: cream,
      textTheme: textTheme,
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: teal,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: GoogleFonts.inter(color: muted, fontWeight: FontWeight.w600, fontSize: 13),
        floatingLabelStyle: GoogleFonts.inter(color: teal, fontWeight: FontWeight.w700, fontSize: 13),
        hintStyle: GoogleFonts.inter(color: muted.withValues(alpha: 0.65)),
        prefixIconColor: teal,
        suffixIconColor: teal,
        enabledBorder: _box(),
        focusedBorder: _box(color: teal, width: 1.7),
        errorBorder: _box(color: const Color(0xFFEE9097)),
        focusedErrorBorder: _box(color: const Color(0xFFB42318), width: 1.5),
        disabledBorder: _box(color: const Color(0xFFE4EDEB)),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          enabledBorder: _box(),
          focusedBorder: _box(color: teal, width: 1.7),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: GoogleFonts.playfairDisplay(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        contentTextStyle: GoogleFonts.inter(fontSize: 14, height: 1.4, color: muted),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: teal,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: teal,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          side: const BorderSide(color: line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: teal,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: teal,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: forest,
        contentTextStyle: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Colors.white,
        headerBackgroundColor: teal,
        headerForegroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({this.size = 56, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Color(0x33073B3A), blurRadius: 14, offset: Offset(0, 6)),
          ],
        ),
        child: ClipOval(
          child: Image.asset(
            PhyimacyBrand.logoAsset,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}
