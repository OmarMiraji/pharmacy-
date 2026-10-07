import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app.dart';
import 'backend/login_log_service.dart';
import 'backend/printer_settings.dart';
import 'firebase_options.dart';
import 'l10n/app_locale.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  try {
    await LoginLogService().closePreviousSession().timeout(const Duration(seconds: 4));
  } catch (_) {}
  try {
    await FirebaseAuth.instance.signOut();
  } catch (_) {}
  await AppLocale.instance.load();
  await PrinterSettingsStore.instance.load();
  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (_) {}
  runApp(const PhyimacyApp());
}

