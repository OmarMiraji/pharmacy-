import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../firebase_options.dart';

class AuthAccountService {
  static const _region = 'us-central1';
  static const _index = 'auth_index';
  static const _storage = FlutterSecureStorage();

  String _emailKey(String email) =>
      email.trim().toLowerCase().replaceAll('@', '_at_').replaceAll('.', '_');

  Future<void> rememberAuthUid({required String email, required String uid}) async {
    final mail = email.trim().toLowerCase();
    final id = uid.trim();
    if (mail.isEmpty || id.isEmpty) return;
    await _storage.write(key: 'auth_uid_${_emailKey(mail)}', value: id);
  }

  Future<String?> rememberedUid(String email) async {
    final local = (await _storage.read(key: 'auth_uid_${_emailKey(email)}') ?? '').trim();
    if (local.isNotEmpty) return local;
    try {
      final snap = await FirebaseFirestore.instance.collection(_index).doc(_emailKey(email)).get();
      final uid = (snap.data()?['uid'] as String? ?? '').trim();
      return uid.isEmpty ? null : uid;
    } catch (_) {
      return null;
    }
  }

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
      final uid = await _createViaIdentity(trimmedEmail, password);
      await rememberAuthUid(email: trimmedEmail, uid: uid);
      return uid;
    } on Exception catch (error) {
      if ('$error'.contains('already has a login')) {
        return _recycleExistingLogin(trimmedEmail, password);
      }
      rethrow;
    }
  }

  Future<String> _recycleExistingLogin(String email, String password) async {
    try {
      final recycled = await _callFunction('recycleAuthUser', {
        'email': email,
        'password': password,
      });
      final uid = (recycled['uid'] as String? ?? '').trim();
      if (uid.isNotEmpty) {
        await rememberAuthUid(email: email, uid: uid);
        return uid;
      }
    } catch (_) {}
    final stored = await rememberedUid(email);
    if (stored != null && stored.isNotEmpty) {
      try {
        await _callFunction('recycleAuthUser', {'email': email, 'password': password, 'uid': stored});
      } catch (_) {
        try {
          await sendPasswordReset(email);
        } catch (_) {}
      }
      return stored;
    }
    throw Exception('That email still has a Firebase login from a deleted profile. Generate the login again after a moment, or use Send reset email.');
  }

  Future<void> deleteAuthUser(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return;
    try {
      await _callFunction('deleteAuthUser', {'uid': id});
    } catch (_) {}
  }

  Future<void> setUserPassword({required String uid, required String password}) async {
    if (uid.trim().isEmpty) throw ArgumentError('User is required.');
    if (password.trim().length < 6) throw ArgumentError('Password must be at least 6 characters.');
    try {
      await _callFunction('setUserPassword', {
        'uid': uid.trim(),
        'password': password.trim(),
      });
    } on _CallableError catch (error) {
      throw StateError(error.message);
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

  Future<Map<String, dynamic>> _callFunction(String name, Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw _CallableError('unauthenticated', 'Sign in first, then add the staff login.');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw _CallableError('unauthenticated', 'Sign in first, then add the staff login.');
    }

    final projectId = DefaultFirebaseOptions.currentPlatform.projectId;
    final uri = Uri.https('$_region-$projectId.cloudfunctions.net', '/$name');
    final payload = jsonEncode({'data': data});
    final client = _httpClient();
    try {
      final request = await client.postUrl(uri).timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.add(utf8.encode(payload));
      final response = await request.close().timeout(const Duration(seconds: 25));
      final text = await response.transform(utf8.decoder).join();
      final decoded = text.isEmpty ? null : jsonDecode(text);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (decoded is Map && decoded['result'] is Map) {
          return Map<String, dynamic>.from(decoded['result'] as Map);
        }
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
        return const {};
      }
      throw _callableFromBody(response.statusCode, decoded, text);
    } on _CallableError {
      rethrow;
    } on SocketException {
      throw _CallableError('unavailable', 'No internet connection. Try again.', retryWithIdentity: true);
    } on TimeoutException {
      throw _CallableError('deadline-exceeded', 'Connection timed out. Try again.', retryWithIdentity: true);
    } on HttpException {
      throw _CallableError('unavailable', 'Could not reach Cloud Functions.', retryWithIdentity: true);
    } finally {
      client.close();
    }
  }

  _CallableError _callableFromBody(int status, Object? decoded, String raw) {
    String code = 'internal';
    String message = 'Could not create that login. Try again.';
    if (decoded is Map) {
      final error = decoded['error'];
      if (error is Map) {
        final statusName = '${error['status'] ?? ''}'.trim().toLowerCase().replaceAll('_', '-');
        if (statusName.isNotEmpty) code = statusName;
        final msg = '${error['message'] ?? ''}'.trim();
        if (msg.isNotEmpty) message = msg;
      }
    }
    if (status == 404 || status == 501) {
      return _CallableError('not-found', message, retryWithIdentity: true);
    }
    if (status == 503 || status == 504) {
      return _CallableError('unavailable', message, retryWithIdentity: true);
    }
    return _CallableError(code, message, retryWithIdentity: status >= 500);
  }

  HttpClient _httpClient() {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    client.idleTimeout = const Duration(seconds: 15);
    client.autoUncompress = true;
    client.badCertificateCallback = (cert, host, port) => false;
    client.userAgent = 'PharmSpecio/windows';
    return client;
  }

  /// True when Firebase knows this email, false when it does not, null when it will not say.
  Future<bool?> emailHasLogin(String email) async {
    final trimmed = email.trim().toLowerCase();
    if (trimmed.isEmpty || !trimmed.contains('@')) return null;
    try {
      final json = await _identity('accounts:createAuthUri', {
        'identifier': trimmed,
        'continueUri': 'https://localhost',
      });
      final registered = json['registered'];
      if (registered is bool) return registered;
      return null;
    } catch (_) {
      return null;
    }
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
    final client = _httpClient();
    try {
      final request = await client.postUrl(uri).timeout(const Duration(seconds: 20));
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(const Duration(seconds: 25));
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
    } on TimeoutException {
      throw StateError('Connection timed out. Try again.');
    } on HttpException {
      throw StateError('Connection dropped. Check internet, then try again.');
    } finally {
      client.close();
    }
  }
}

class _CallableError implements Exception {
  _CallableError(this.code, this.message, {this.retryWithIdentity = false});

  final String code;
  final String message;
  final bool retryWithIdentity;
}

class _IdentityError implements Exception {
  _IdentityError(this.code);
  final String code;

  String get userMessage {
    if (code.contains('EMAIL_EXISTS')) return 'That email already has a login.';
    if (code.contains('INVALID_EMAIL')) return 'Enter a valid email address.';
    if (code.contains('WEAK_PASSWORD')) return 'Password must be at least 6 characters.';
    if (code.contains('TOO_MANY_ATTEMPTS')) return 'Too many attempts. Please wait and try again.';
    if (code.contains('OPERATION_NOT_ALLOWED')) {
      return 'Email sign-in is not available. Contact your administrator.';
    }
    return 'Could not complete this request. Try again.';
  }
}
