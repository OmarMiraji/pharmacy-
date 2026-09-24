import 'dart:convert';
import 'dart:io';

import '../firebase_options.dart';

class AuthAccountService {
  Future<String> createAuthUser({
    required String email,
    required String password,
  }) async {
    final trimmedEmail = email.trim().toLowerCase();
    if (trimmedEmail.isEmpty) throw ArgumentError('Email is required.');
    if (password.length < 6) throw ArgumentError('Password must be at least 6 characters.');

    try {
      return await _identity('accounts:signUp', {
        'email': trimmedEmail,
        'password': password,
        'returnSecureToken': true,
      });
    } on _IdentityError catch (error) {
      if (error.code.contains('EMAIL_EXISTS')) {
        try {
          return await _identity('accounts:signInWithPassword', {
            'email': trimmedEmail,
            'password': password,
            'returnSecureToken': true,
          });
        } on _IdentityError {
          throw Exception(
            '$trimmedEmail already exists in Firebase Authentication from an earlier create. Use a new email, or type the original password for that email.',
          );
        }
      }
      throw Exception(error.userMessage);
    }
  }

  Future<String> _identity(String method, Map<String, Object> body) async {
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
        throw StateError('Unexpected Firebase Auth response.');
      }
      final error = json['error'];
      if (error is Map) {
        throw _IdentityError((error['message'] as String? ?? 'IDENTITY_ERROR').trim());
      }
      final uid = (json['localId'] as String? ?? '').trim();
      if (uid.isEmpty) throw StateError('Firebase Auth did not return a user ID.');
      return uid;
    } on SocketException {
      throw StateError('No internet. Staff login could not be created.');
    } finally {
      client.close(force: true);
    }
  }
}

class _IdentityError implements Exception {
  _IdentityError(this.code);
  final String code;

  String get userMessage {
    if (code.contains('EMAIL_EXISTS')) return 'That email already has a Firebase login.';
    if (code.contains('INVALID_EMAIL')) return 'Enter a valid email address.';
    if (code.contains('WEAK_PASSWORD')) return 'Password must be at least 6 characters.';
    if (code.contains('OPERATION_NOT_ALLOWED')) {
      return 'Email/Password is OFF in Firebase Console → Authentication → Sign-in method.';
    }
    return 'Firebase Auth error: $code';
  }
}
