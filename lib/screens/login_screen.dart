import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../backend/auth_service.dart';
import '../l10n/app_locale.dart';
import '../theme/brand.dart';
import '../widgets/language_toggle.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _loading = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      AuthService.workspaceError = null;
      await _authService.signIn(
        email: _emailController.text.trim().toLowerCase(),
        password: _passwordController.text,
      ).timeout(const Duration(seconds: 25));
    } on TimeoutException {
      setState(() {
        _error = S.t(
          'Sign-in is taking too long. Check your internet and try again.',
          'Kuingia kumechelewa. Angalia intaneti kisha jaribu tena.',
        );
      });
    } on FirebaseAuthException catch (error) {
      setState(() {
        _error = switch (error.code) {
          'user-not-found' || 'invalid-credential' || 'wrong-password' || 'INVALID_LOGIN_CREDENTIALS' =>
            S.t('Incorrect email or password.', 'Barua pepe au nenosiri si sahihi.'),
          'invalid-email' => S.t('Enter a valid email address.', 'Weka barua pepe sahihi.'),
          'user-disabled' => S.t('This account is disabled. Contact your administrator.', 'Akaunti imefungwa. Wasiliana na admin.'),
          'too-many-requests' => S.t('Too many attempts. Please wait a moment and try again.', 'Majaribio mengi. Subiri kidogo kisha jaribu tena.'),
          'network-request-failed' => S.t('Network error. Check your internet connection and try again.', 'Hitilafu ya mtandao. Angalia intaneti kisha jaribu tena.'),
          _ => S.t('Could not sign in. Check your details and try again.', 'Imeshindikana kuingia. Angalia taarifa zako kisha jaribu tena.'),
        };
      });
    } catch (_) {
      setState(() => _error = S.t('Could not sign in. Check your details and try again.', 'Imeshindikana kuingia. Angalia taarifa zako kisha jaribu tena.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          return Container(
            width: double.infinity,
            height: double.infinity,
            color: PhyimacyBrand.forest,
            child: wide
                ? Row(
                    children: [
                      const Expanded(flex: 11, child: _PharmacyHeroPanel()),
                      Expanded(flex: 10, child: _buildFormPane(wide: true)),
                    ],
                  )
                : _buildFormPane(wide: false),
          );
        },
      ),
    );
  }

  Widget _buildFormPane({required bool wide}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF7FAF9),
            Color(0xFFEAF3F0),
          ],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: IgnorePointer(child: _LeafWash())),
          // Soft decorative blurred blobs
          Positioned(
            top: -80,
            right: -60,
            child: _BlurBlob(color: PhyimacyBrand.teal.withValues(alpha: 0.10), size: 220),
          ),
          Positioned(
            bottom: -100,
            left: -70,
            child: _BlurBlob(color: PhyimacyBrand.gold.withValues(alpha: 0.10), size: 260),
          ),
          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: wide ? 56 : 28, vertical: 36),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: ListenableBuilder(
                  listenable: AppLocale.instance,
                  builder: (context, _) => Container(
                  padding: EdgeInsets.all(wide ? 0 : 26),
                  decoration: wide
                      ? null
                      : BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: PhyimacyBrand.forest.withValues(alpha: 0.08),
                              blurRadius: 40,
                              offset: const Offset(0, 16),
                            ),
                          ],
                        ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(alignment: Alignment.centerRight, child: LanguageToggle(compact: true)),
                      const SizedBox(height: 16),
                      if (!wide) ...[
                        const Center(child: BrandMark(size: 96)),
                        const SizedBox(height: 14),
                        Text(
                          PhyimacyBrand.appName,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: PhyimacyBrand.forest,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          PhyimacyBrand.tagline,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: PhyimacyBrand.muted,
                            fontWeight: FontWeight.w500,
                            fontSize: 13.5,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 30),
                      ] else ...[
                        const Center(child: BrandMark(size: 92)),
                        const SizedBox(height: 16),
                        Text(
                          S.t('Welcome back', 'Karibu tena'),
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            color: PhyimacyBrand.forest,
                            height: 1.1,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          S.t(
                            'Sign in to open your shop counter, inventory, and daily sales.',
                            'Ingia kufungua counter, stock, na mauzo ya siku.',
                          ),
                          style: GoogleFonts.inter(
                            color: PhyimacyBrand.muted,
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                      if (AuthService.workspaceError != null) ...[
                        _Notice(text: AuthService.workspaceError!, tone: _NoticeTone.warn),
                        const SizedBox(height: 16),
                      ],
                      _FieldLabel(text: S.t('Email address', 'Barua pepe')),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: PhyimacyBrand.ink,
                        ),
                        decoration: _fieldDecoration(
                          hint: 'you@pharmacy.com',
                          icon: Icons.mail_outline_rounded,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _FieldLabel(text: S.t('Password', 'Nenosiri')),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _passwordController,
                        obscureText: _hidePassword,
                        onSubmitted: (_) {
                          if (!_loading) _login();
                        },
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: PhyimacyBrand.ink,
                        ),
                        decoration: _fieldDecoration(
                          hint: '••••••••',
                          icon: Icons.lock_outline_rounded,
                          suffix: IconButton(
                            tooltip: _hidePassword ? 'Show password' : 'Hide password',
                            onPressed: () => setState(() => _hidePassword = !_hidePassword),
                            icon: Icon(
                              _hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              color: PhyimacyBrand.teal,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 14, color: PhyimacyBrand.muted.withValues(alpha: 0.8)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              S.t('Forgot your password? Ask your administrator to reset it.', 'Umesahau nenosiri? Mwambie admin akuweke nenosiri jipya.'),
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: PhyimacyBrand.muted,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        _Notice(text: _error!, tone: _NoticeTone.error),
                      ],
                      const SizedBox(height: 26),
                      SizedBox(
                        height: 56,
                        child: FilledButton(
                          onPressed: _loading ? null : _login,
                          style: FilledButton.styleFrom(
                            backgroundColor: PhyimacyBrand.teal,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFF9BBFBB),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            elevation: 6,
                            shadowColor: PhyimacyBrand.teal.withValues(alpha: 0.4),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      S.t('Enter pharmacy', 'Ingia dukani'),
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.arrow_forward_rounded, size: 18),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      Row(
                        children: [
                          const Expanded(child: Divider(color: Color(0xFFD9E4E1))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'TRUSTED COUNTER SOFTWARE',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                letterSpacing: 1.4,
                                fontWeight: FontWeight.w700,
                                color: PhyimacyBrand.muted,
                              ),
                            ),
                          ),
                          const Expanded(child: Divider(color: Color(0xFFD9E4E1))),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _MiniChip(icon: Icons.point_of_sale_rounded, label: 'Sales'),
                          _MiniChip(icon: Icons.inventory_2_outlined, label: 'Stock'),
                          _MiniChip(icon: Icons.receipt_long_outlined, label: 'Receipts'),
                        ],
                      ),
                    ],
                  ),
                ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required IconData icon,
    String? hint,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(
        color: PhyimacyBrand.muted.withValues(alpha: 0.6),
        fontWeight: FontWeight.w400,
      ),
      filled: true,
      fillColor: Colors.white,
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 6, right: 4),
        child: Icon(icon, color: PhyimacyBrand.teal, size: 20),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 46),
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD7E5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: PhyimacyBrand.teal, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFEE9097)),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: PhyimacyBrand.ink.withValues(alpha: 0.75),
        letterSpacing: 0.3,
      ),
    );
  }
}

class _BlurBlob extends StatelessWidget {
  const _BlurBlob({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _PharmacyHeroPanel extends StatelessWidget {
  const _PharmacyHeroPanel();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF052E2D)),
        Image.asset(
          'assets/images/pharmacy-shelves.jpg',
          fit: BoxFit.cover,
          alignment: const Alignment(0.15, 0),
          filterQuality: FilterQuality.high,
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                Color(0x66073B3A),
                Color(0x990B4F4A),
                Color(0xE6052E2D),
              ],
              stops: [0.0, 0.45, 1.0],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x33052E2D),
                Color(0x00052E2D),
                Color(0xCC052E2D),
              ],
              stops: [0.0, 0.38, 1.0],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(48, 48, 40, 44),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandMark(size: 88),
              const SizedBox(height: 16),
              Text(
                PhyimacyBrand.appName,
                style: GoogleFonts.playfairDisplay(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  height: 1,
                  shadows: const [
                    Shadow(color: Color(0x88000000), blurRadius: 16, offset: Offset(0, 3)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 44,
                height: 3,
                decoration: BoxDecoration(
                  color: PhyimacyBrand.gold,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                PhyimacyBrand.tagline.toUpperCase(),
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 11,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: PhyimacyBrand.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: PhyimacyBrand.gold.withValues(alpha: 0.4)),
                ),
                child: Text(
                  'PHARMACY SOFTWARE',
                  style: GoogleFonts.inter(
                    color: PhyimacyBrand.gold,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Built for\npharmacies.',
                style: GoogleFonts.playfairDisplay(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  height: 1.05,
                  shadows: const [
                    Shadow(color: Color(0x88000000), blurRadius: 20, offset: Offset(0, 4)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: 56,
                height: 4,
                decoration: BoxDecoration(
                  color: PhyimacyBrand.gold,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Clear selling, careful stock,\nbeautiful every day.',
                style: GoogleFonts.inter(
                  color: const Color(0xFFE7F6F2),
                  fontSize: 17,
                  height: 1.5,
                  fontWeight: FontWeight.w400,
                  shadows: const [
                    Shadow(color: Color(0x99000000), blurRadius: 12, offset: Offset(0, 2)),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _HeroPill(icon: Icons.medication_outlined, label: 'Medicines'),
                  _HeroPill(icon: Icons.monitor_heart_outlined, label: 'Expiry watch'),
                  _HeroPill(icon: Icons.groups_outlined, label: 'Team access'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PharmacyMark extends StatelessWidget {
  const _PharmacyMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5EEAD4), Color(0xFF0F766E)],
        ),
        boxShadow: [
          BoxShadow(
            color: PhyimacyBrand.mint.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.local_pharmacy_rounded, size: size * 0.46, color: Colors.white.withValues(alpha: 0.95)),
          Positioned(
            right: size * 0.16,
            bottom: size * 0.16,
            child: Icon(Icons.add_rounded, size: size * 0.22, color: PhyimacyBrand.gold),
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: PhyimacyBrand.gold),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD7E5E1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: PhyimacyBrand.teal),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: PhyimacyBrand.ink,
            ),
          ),
        ],
      ),
    );
  }
}

enum _NoticeTone { error, warn }

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.tone});

  final String text;
  final _NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final error = tone == _NoticeTone.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFFF1F2) : const Color(0xFFFFF6E8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: error ? const Color(0xFFEE9097) : const Color(0xFFE8C47A)),
      ),
      child: Row(
        children: [
          Icon(
            error ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
            size: 18,
            color: error ? const Color(0xFFB42318) : const Color(0xFF8A5A10),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                color: error ? const Color(0xFFB42318) : const Color(0xFF8A5A10),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeafWash extends StatelessWidget {
  const _LeafWash();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _LeafWashPainter());
  }
}

class _LeafWashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF0F766E).withValues(alpha: 0.04);
    canvas.drawCircle(Offset(size.width * 0.92, size.height * 0.08), 90, paint);
    canvas.drawCircle(Offset(size.width * 0.05, size.height * 0.92), 120, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}