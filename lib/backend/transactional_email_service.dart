import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mailer/mailer.dart' as mailer;
import 'package:mailer/smtp_server.dart';

import 'firestore_collections.dart';
import 'pharmacy_service.dart';

class TransactionalEmailService {
  static const _userKey = 'pharmspecio_smtp_user';
  static const _passKey = 'pharmspecio_smtp_pass';
  static const _storage = FlutterSecureStorage();
  static const webAppUrl = 'https://pharmspecio.web.app/app/';

  Future<void> saveSmtp({required String gmail, required String appPassword}) async {
    final user = gmail.trim().toLowerCase();
    final pass = appPassword.replaceAll(RegExp(r'\s+'), '');
    if (!user.contains('@')) throw ArgumentError('Enter the Gmail address.');
    if (pass.length < 8) throw ArgumentError('Enter the 16-character App password.');
    await _storage.write(key: _userKey, value: user);
    await _storage.write(key: _passKey, value: pass);
    await _pushSmtpToServer(user, pass);
  }

  /// Cloud Functions send welcome emails from every device (including the web) using this copy.
  Future<void> _pushSmtpToServer(String user, String pass) {
    return FirebaseFirestore.instance.collection(FirestoreCollections.mailSettings).doc('smtp').set({
      'user': user,
      'pass': pass,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Super admin devices that saved Gmail before server sending existed upload it once.
  Future<void> syncSmtpToServer() async {
    try {
      final smtp = await loadSmtp();
      if (smtp == null) return;
      final doc = await FirebaseFirestore.instance.collection(FirestoreCollections.mailSettings).doc('smtp').get();
      final data = doc.data() ?? const <String, dynamic>{};
      if (data['user'] == smtp['user'] && data['pass'] == smtp['pass']) return;
      await _pushSmtpToServer(smtp['user']!, smtp['pass']!);
    } catch (_) {}
  }

  Future<Map<String, String>?> loadSmtp() async {
    final user = (await _storage.read(key: _userKey) ?? '').trim();
    final pass = (await _storage.read(key: _passKey) ?? '').replaceAll(RegExp(r'\s+'), '');
    if (user.isEmpty || pass.isEmpty) return null;
    return {'user': user, 'pass': pass, 'from': 'PharmSpecio <$user>'};
  }

  Future<String?> notifyLoginCreated({
    required String toEmail,
    required String displayName,
    required String role,
    String? pharmacyId,
    String? shopName,
    bool isNewShop = false,
    String? temporaryPassword,
  }) async {
    final mail = toEmail.trim().toLowerCase();
    if (mail.isEmpty || role == 'super_admin') return null;
    final temp = (temporaryPassword ?? '').trim();
    var shop = (shopName ?? '').trim();
    DateTime? trialEnds;
    var trial = isNewShop;
    final id = (pharmacyId ?? '').trim();
    if (id.isNotEmpty) {
      try {
        final record = await PharmacyService().getPharmacy(id);
        if (record != null) {
          if (shop.isEmpty) shop = record.name;
          trial = record.isTrial || record.plan == 'trial' || record.status == 'trial';
          trialEnds = record.trialEndsAt ?? record.expiresAt;
        }
      } catch (_) {}
    }
    if (role == 'admin') {
      return send(
        to: mail,
        subject: 'Welcome to PharmSpecio${shop.isEmpty ? '' : ' — $shop'}',
        text: _adminWelcomeText(displayName, mail, shop, trial, trialEnds, temp),
      );
    }
    return send(
      to: mail,
      subject: 'Your PharmSpecio login${shop.isEmpty ? '' : ' — $shop'}',
      text: _staffWelcomeText(displayName, mail, shop, role, temp),
    );
  }

  Future<String?> notifySubscriptionActivated({
    required String toEmail,
    required String displayName,
    required String shopName,
    required String plan,
    DateTime? expiresAt,
  }) {
    final mail = toEmail.trim().toLowerCase();
    if (mail.isEmpty) return Future.value(null);
    final until = expiresAt == null ? '' : '${expiresAt.day}/${expiresAt.month}/${expiresAt.year}';
    return send(
      to: mail,
      subject: 'PharmSpecio account activated${shopName.isEmpty ? '' : ' — $shopName'}',
      text: [
        'Hello ${displayName.trim().isEmpty ? mail : displayName.trim()},',
        '',
        'Your PharmSpecio subscription is now active. The shop is unlocked for full use.',
        if (shopName.trim().isNotEmpty) 'Shop: ${shopName.trim()}',
        'Plan: $plan',
        if (until.isNotEmpty) 'Valid until: $until',
        'Login email: $mail',
        '',
        'Open the PharmSpecio Windows app to continue.',
      ].join('\n'),
    );
  }

  Future<String?> send({required String to, required String subject, required String text}) async {
    // Browsers cannot open SMTP connections.
    if (kIsWeb) return 'email-not-ready';
    try {
      final smtp = await loadSmtp();
      if (smtp == null) {
        return 'email-not-ready';
      }
      final server = gmail(smtp['user']!, smtp['pass']!);
      final message = mailer.Message()
        ..from = mailer.Address(smtp['user']!, 'PharmSpecio')
        ..recipients.add(to)
        ..subject = subject
        ..text = text;
      await mailer.send(message, server);
      return null;
    } catch (error) {
      return 'email-not-sent';
    }
  }

  Future<String?> notifyLicenseToken({
    required String toEmail,
    required String shopName,
    required String token,
    required String plan,
    required int days,
  }) {
    final mail = toEmail.trim().toLowerCase();
    if (mail.isEmpty) return Future.value('Enter an email address.');
    return send(
      to: mail,
      subject: 'PharmSpecio license token${shopName.isEmpty ? '' : ' — $shopName'}',
      text: [
        'Hello,',
        '',
        'Your PharmSpecio license token is ready.',
        if (shopName.trim().isNotEmpty) 'Shop: ${shopName.trim()}',
        'Plan: $plan',
        'Duration: $days days',
        '',
        'Activation token:',
        token,
        '',
        'Open PharmSpecio, enter this token to unlock the shop, and keep it private.',
      ].join('\n'),
    );
  }

  String _adminWelcomeText(String name, String email, String shop, bool trial, DateTime? trialEnds, String temp) {
    final who = name.trim().isEmpty ? email : name.trim();
    final until = trialEnds == null ? '' : '${trialEnds.day}/${trialEnds.month}/${trialEnds.year}';
    return [
      'Hello $who,',
      '',
      'Welcome to PharmSpecio. Your shop admin login is ready.',
      if (shop.isNotEmpty) 'Shop: $shop',
      'Login email: $email',
      if (temp.isNotEmpty) 'Temporary password: $temp',
      'Role: Shop admin',
      if (trial) 'You are on a 7-day free trial${until.isEmpty ? '' : ', until $until'}.',
      '',
      temp.isNotEmpty
          ? 'Open the PharmSpecio Windows app and sign in with this email and temporary password.'
          : 'Open the PharmSpecio Windows app and sign in with this email and the password that was set for you.',
      'You can also sign in from a browser: $webAppUrl',
      ..._tempPasswordFooter(temp),
    ].join('\n');
  }

  String _staffWelcomeText(String name, String email, String shop, String role, String temp) {
    final who = name.trim().isEmpty ? email : name.trim();
    return [
      'Hello $who,',
      '',
      'A PharmSpecio login has been created for you.',
      if (shop.isNotEmpty) 'Shop: $shop',
      'Login email: $email',
      if (temp.isNotEmpty) 'Temporary password: $temp',
      'Role: $role',
      '',
      temp.isNotEmpty
          ? 'Sign in on the PharmSpecio Windows app with this email and temporary password.'
          : 'Sign in on the PharmSpecio Windows app with this email and the password your shop admin gave you.',
      'You can also sign in from a browser: $webAppUrl',
      ..._tempPasswordFooter(temp),
    ].join('\n');
  }

  List<String> _tempPasswordFooter(String temp) => temp.isEmpty
      ? const []
      : const [
          '',
          'The first time you sign in you will be asked to choose your own password. Do not share it with anyone.',
          '',
          'Utaombwa kuchagua nenosiri lako mwenyewe mara ya kwanza ukiingia. Usimpe mtu yeyote.',
        ];
}
