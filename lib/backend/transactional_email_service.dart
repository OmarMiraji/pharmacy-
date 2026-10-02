import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mailer/mailer.dart' as mailer;
import 'package:mailer/smtp_server.dart';

import 'pharmacy_service.dart';

class TransactionalEmailService {
  static const _userKey = 'pharmspecio_smtp_user';
  static const _passKey = 'pharmspecio_smtp_pass';
  static const _storage = FlutterSecureStorage();

  Future<void> saveSmtp({required String gmail, required String appPassword}) async {
    final user = gmail.trim().toLowerCase();
    final pass = appPassword.replaceAll(RegExp(r'\s+'), '');
    if (!user.contains('@')) throw ArgumentError('Enter the Gmail address.');
    if (pass.length < 8) throw ArgumentError('Enter the 16-character App password.');
    await _storage.write(key: _userKey, value: user);
    await _storage.write(key: _passKey, value: pass);
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
  }) async {
    final mail = toEmail.trim().toLowerCase();
    if (mail.isEmpty || role == 'super_admin') return null;
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
        text: _adminWelcomeText(displayName, mail, shop, trial, trialEnds),
      );
    }
    return send(
      to: mail,
      subject: 'Your PharmSpecio login${shop.isEmpty ? '' : ' — $shop'}',
      text: _staffWelcomeText(displayName, mail, shop, role),
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
    try {
      final smtp = await loadSmtp();
      if (smtp == null) {
        return 'Email is not configured. Open Email settings and save the Gmail App password.';
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
      return 'Login was created, but the email could not be sent: $error';
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

  String _adminWelcomeText(String name, String email, String shop, bool trial, DateTime? trialEnds) {
    final who = name.trim().isEmpty ? email : name.trim();
    final until = trialEnds == null ? '' : '${trialEnds.day}/${trialEnds.month}/${trialEnds.year}';
    return [
      'Hello $who,',
      '',
      'Welcome to PharmSpecio. Your shop admin login is ready.',
      if (shop.isNotEmpty) 'Shop: $shop',
      'Login email: $email',
      'Role: Shop admin',
      if (trial) 'You are on a 7-day free trial${until.isEmpty ? '' : ', until $until'}.',
      '',
      'Open the PharmSpecio Windows app and sign in with this email and the password that was set for you.',
    ].join('\n');
  }

  String _staffWelcomeText(String name, String email, String shop, String role) {
    final who = name.trim().isEmpty ? email : name.trim();
    return [
      'Hello $who,',
      '',
      'A PharmSpecio login has been created for you.',
      if (shop.isNotEmpty) 'Shop: $shop',
      'Login email: $email',
      'Role: $role',
      '',
      'Sign in on the PharmSpecio Windows app with this email and the password your shop admin gave you.',
    ].join('\n');
  }
}
