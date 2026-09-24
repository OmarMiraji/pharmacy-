import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'firestore_collections.dart';
import 'tenant_context.dart';

class AppRelease {
  const AppRelease({
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    this.notes = '',
    this.publishedAt,
    this.githubRepo = '',
  });

  final String version;
  final int buildNumber;
  final String downloadUrl;
  final String notes;
  final DateTime? publishedAt;
  final String githubRepo;

  factory AppRelease.fromMap(Map<String, dynamic> data) {
    return AppRelease(
      version: (data['version'] as String? ?? '').trim(),
      buildNumber: (data['buildNumber'] as num?)?.toInt() ?? 0,
      downloadUrl: (data['downloadUrl'] as String? ?? '').trim(),
      notes: (data['notes'] as String? ?? '').trim(),
      publishedAt: (data['publishedAt'] as Timestamp?)?.toDate(),
      githubRepo: (data['githubRepo'] as String? ?? '').trim(),
    );
  }

  bool get isValid => version.isNotEmpty && downloadUrl.isNotEmpty;
}

class AppUpdateCheck {
  const AppUpdateCheck({
    required this.installedVersion,
    required this.installedBuild,
    this.latest,
  });

  final String installedVersion;
  final int installedBuild;
  final AppRelease? latest;

  bool get updateAvailable {
    final release = latest;
    if (release == null || !release.isValid) return false;
    final byName = _compareVersions(release.version, installedVersion) > 0;
    if (byName) return true;
    final sameVersion = _compareVersions(release.version, installedVersion) == 0;
    return sameVersion && release.buildNumber > installedBuild && release.buildNumber < 100000;
  }
}

int _compareVersions(String left, String right) {
  final a = left.split(RegExp(r'[^0-9]+')).where((part) => part.isNotEmpty).map(int.parse).toList();
  final b = right.split(RegExp(r'[^0-9]+')).where((part) => part.isNotEmpty).map(int.parse).toList();
  final maxLength = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < maxLength; i++) {
    final leftValue = i < a.length ? a[i] : 0;
    final rightValue = i < b.length ? b[i] : 0;
    if (leftValue != rightValue) return leftValue.compareTo(rightValue);
  }
  return 0;
}

class AppUpdateService {
  AppUpdateService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  static const latestDocId = 'latest';

  DocumentReference<Map<String, dynamic>> get _latestRef =>
      _firestore.collection(FirestoreCollections.appReleases).doc(latestDocId);

  Future<PackageInfo> installed() => PackageInfo.fromPlatform();

  Future<AppUpdateCheck> check() async {
    final info = await installed();
    final snapshot = await _latestRef.get();
    final stored = snapshot.exists ? AppRelease.fromMap(snapshot.data() ?? const {}) : null;
    AppRelease? latest = stored;
    final repo = (stored?.githubRepo ?? '').trim();
    if (repo.isNotEmpty) {
      final github = await fetchGithubLatest(repo);
      if (github != null) {
        latest = github;
      }
    }
    return AppUpdateCheck(
      installedVersion: info.version,
      installedBuild: int.tryParse(info.buildNumber) ?? 0,
      latest: latest,
    );
  }

  Future<AppRelease?> fetchGithubLatest(String repo) async {
    final cleaned = repo.trim().replaceFirst(RegExp(r'^https?://github.com/'), '').replaceAll(RegExp(r'\.git$'), '');
    if (!RegExp(r'^[^/\s]+/[^/\s]+$').hasMatch(cleaned)) return null;
    final uri = Uri.https('api.github.com', '/repos/$cleaned/releases/latest');
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'Phyimacy-Updater');
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) return null;
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String? ?? '').trim().replaceFirst(RegExp(r'^v'), '');
      final assets = (json['assets'] as List?) ?? const [];
      String downloadUrl = '';
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = (asset['name'] as String? ?? '').toLowerCase();
        final url = (asset['browser_download_url'] as String? ?? '').trim();
        if (url.isEmpty) continue;
        if (name.endsWith('.zip') || name.endsWith('.exe')) {
          downloadUrl = url;
          break;
        }
      }
      if (downloadUrl.isEmpty) {
        downloadUrl = (json['html_url'] as String? ?? '').trim();
      }
      final published = json['published_at'] as String?;
      return AppRelease(
        version: tag,
        buildNumber: 0,
        downloadUrl: downloadUrl,
        notes: (json['body'] as String? ?? '').trim(),
        publishedAt: published == null ? null : DateTime.tryParse(published),
        githubRepo: cleaned,
      );
    } on Object {
      return null;
    } finally {
      client.close();
    }
  }

  Future<void> publish({
    required String version,
    required int buildNumber,
    required String downloadUrl,
    String notes = '',
    String githubRepo = '',
  }) async {
    if (!TenantContext.instance.isSuperAdmin) {
      throw StateError('Only Super Admin can publish app updates.');
    }
    final trimmedVersion = version.trim();
    final repo = githubRepo.trim().replaceFirst(RegExp(r'^https?://github.com/'), '').replaceAll(RegExp(r'\.git$'), '');
    if (trimmedVersion.isEmpty && repo.isEmpty) {
      throw ArgumentError('Enter a GitHub repo like yourname/phyimacy, or a version plus download link.');
    }
    if (repo.isEmpty && downloadUrl.trim().isEmpty) {
      throw ArgumentError('Download link is required if GitHub repo is empty.');
    }
    await _latestRef.set({
      'version': trimmedVersion.isEmpty ? '0.0.0' : trimmedVersion,
      'buildNumber': buildNumber < 1 ? 1 : buildNumber,
      'downloadUrl': downloadUrl.trim(),
      'notes': notes.trim(),
      'githubRepo': repo,
      'publishedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
