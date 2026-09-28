import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../firebase_options.dart';

class AuthAccountService {
  Future<String> createAuthUser({
    required String email,
    required String password,
    String role = 'cashier',
  }) async {
    final trimmedEmail = email.trim().toLowerCase();
    if (trimmedEmail.isEmpty) throw ArgumentError('Email is required.');
    if (password.length < 6) throw ArgumentError('Password must be at least 6 characters.');
    if (FirebaseAuth.instance.currentUser == null) {
      throw Exception('Sign in first, then add the staff login.');
    }

    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('createAuthUser').call(
        <String, dynamic>{
          'email': trimmedEmail,
          'password': password,
          'role': role.trim().toLowerCase(),
        },
      );
      final data = result.data;
      if (data is Map && data['uid'] is String && (data['uid'] as String).trim().isNotEmpty) {
        return (data['uid'] as String).trim();
      }
      throw StateError('Login could not be created. Try again.');
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'already-exists') {
        throw Exception('That email already has a login. Use a different email.');
      }
      if (error.code == 'unauthenticated') {
        throw Exception('Sign in first, then add the staff login.');
      }
      if (error.code == 'permission-denied') {
        throw Exception(error.message ?? 'You cannot create that login.');
      }
      if (_functionsUnavailable(error.code, error.message)) {
        return _createViaIdentity(trimmedEmail, password);
      }
      throw Exception(error.message ?? 'Could not create that login. Try again.');
    } catch (error) {
      if (error is Exception && '$error'.contains('That email already has a login')) rethrow;
      if (_isChannelError(error)) {
        return _createViaIdentity(trimmedEmail, password);
      }
      throw Exception(_staffCreateUserMessage(error));
    }
  }

  Future<String> _createViaIdentity(String email, String password) async {
    try {
      final json = await _identity('accounts:signUp', {
        'email': email,
        'password': password,
        'returnSecureToken': false,
      });
      return _requireUid(json);
    } on _IdentityError catch (error) {
      throw Exception(error.userMessage);
    }
  }

  static bool _functionsUnavailable(String code, String? message) {
    final text = '${code.toLowerCase()} ${message ?? ''}'.toLowerCase();
    return code == 'unavailable' ||
        code == 'unimplemented' ||
        code == 'not-found' ||
        code == 'internal' ||
        code == 'deadline-exceeded' ||
        text.contains('billing') ||
        text.contains('not found');
  }

  static bool _isChannelError(Object error) {
    final text = '$error'.toLowerCase();
    return text.contains('pigeon') ||
        text.contains('unable to establish connection') ||
        text.contains('cloudfunctionshostapi') ||
        text.contains('missingpluginexception') ||
        text.contains('channel');
  }

  static String _staffCreateUserMessage(Object error) {
    if (_isChannelError(error)) {
      return 'Could not reach Cloud Functions. Check internet, then try again.';
    }
    return '$error'.replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '');
  }

  Future<void> sendPasswordReset(String email) async {
    final trimmedEmail = email.trim().toLowerCase();
    if (trimmedEmail.isEmpty) throw ArgumentError('Enter your email address first.');
    try {
      await _identity('accounts:sendOobCode', {
        'requestType': 'PASSWORD_RESET',
        'email': trimmedEmail,
      });
    } on _IdentityError catch (error) {
      if (error.code.contains('EMAIL_NOT_FOUND')) {
        return;
      }
      throw Exception(error.userMessage);
    }
  }

  String _requireUid(Map<String, dynamic> json) {
    final uid = (json['localId'] as String? ?? '').trim();
    if (uid.isEmpty) throw StateError('Login could not be created. Try again.');
    return uid;
  }

  Future<Map<String, dynamic>> _identity(String method, Map<String, Object> body) async {
    final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
    final uri = Uri.https('identitytoolkit.googleapis.com', '/v1/$method', {'key': apiKey});
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) {
        throw StateError('Unexpected sign-in response. Try again.');
      }
      final error = json['error'];
      if (error is Map) {
        throw _IdentityError((error['message'] as String? ?? 'IDENTITY_ERROR').trim());
      }
      return json;
    } on SocketException {
      throw StateError('No internet connection. Try again.');
    } finally {
      client.close(force: true);
    }
  }
}

class _IdentityError implements Exception {
  _IdentityError(this.code);
  final String code;

  String get userMessage {
    if (code.contains('EMAIL_EXISTS')) return 'That email already has a login. Use a different email.';
    if (code.contains('INVALID_EMAIL')) return 'Enter a valid email address.';
    if (code.contains('WEAK_PASSWORD')) return 'Password must be at least 6 characters.';
    if (code.contains('TOO_MANY_ATTEMPTS')) return 'Too many attempts. Please wait and try again.';
    if (code.contains('OPERATION_NOT_ALLOWED')) {
      return 'Email sign-in is not available. Contact your administrator.';
    }
    return 'Could not complete this request. Try again.';
  }
}
