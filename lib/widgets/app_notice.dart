import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_locale.dart';
import '../theme/brand.dart';

enum AppNoticeKind { success, error, warning, info }

OverlayEntry? _activeNotice;

void showAppNotice(
  BuildContext context,
  String message, {
  AppNoticeKind kind = AppNoticeKind.success,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _activeNotice?.remove();
  _activeNotice = null;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _AppNoticeToast(
      message: message,
      kind: kind,
      onFinished: () {
        if (_activeNotice == entry) {
          entry.remove();
          _activeNotice = null;
        }
      },
    ),
  );
  _activeNotice = entry;
  overlay.insert(entry);
}

class _AppNoticeToast extends StatefulWidget {
  const _AppNoticeToast({
    required this.message,
    required this.kind,
    required this.onFinished,
  });

  final String message;
  final AppNoticeKind kind;
  final VoidCallback onFinished;

  @override
  State<_AppNoticeToast> createState() => _AppNoticeToastState();
}

class _AppNoticeToastState extends State<_AppNoticeToast> with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(vsync: this, duration: const Duration(milliseconds: 140));
    _motion.forward();
    final hold = widget.kind == AppNoticeKind.error ? 2200 : 1400;
    _hold = Timer(Duration(milliseconds: hold), _dismiss);
  }

  Future<void> _dismiss() async {
    _hold?.cancel();
    if (!mounted) {
      widget.onFinished();
      return;
    }
    await _motion.reverse();
    if (mounted) widget.onFinished();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color tone;
    final IconData icon;
    switch (widget.kind) {
      case AppNoticeKind.success:
        tone = PhyimacyBrand.forest;
        icon = Icons.check_rounded;
      case AppNoticeKind.error:
        tone = const Color(0xffb42318);
        icon = Icons.close_rounded;
      case AppNoticeKind.warning:
        tone = const Color(0xffb54708);
        icon = Icons.info_outline_rounded;
      case AppNoticeKind.info:
        tone = PhyimacyBrand.teal;
        icon = Icons.check_rounded;
    }
    return Positioned(
      right: 28,
      bottom: 28,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _motion,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.08, 0.12), end: Offset.zero).animate(
              CurvedAnimation(parent: _motion, curve: Curves.easeOutCubic),
            ),
            child: Material(
              color: tone,
              elevation: 8,
              shadowColor: const Color(0x66000000),
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 18, 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Text(
                        widget.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String friendlyActionError(Object error) {
  final raw = '$error'.replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '').replaceFirst('Invalid argument(s): ', '').trim();
  final lower = raw.toLowerCase();
  if (lower.contains('permission-denied') || lower.contains('insufficient permissions') || lower.contains('missing or insufficient')) {
    return S.t('Could not save. Try again.', 'Haikuweza kuhifadhi. Jaribu tena.');
  }
  if (lower.contains('network') || lower.contains('unavailable') || lower.contains('offline')) {
    return S.t('Connection lost. Try again.', 'Muunganisho umekatika. Jaribu tena.');
  }
  if (raw.isEmpty) {
    return S.t('Please try again.', 'Tafadhali jaribu tena.');
  }
  return raw;
}
