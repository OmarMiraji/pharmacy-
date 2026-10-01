import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
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
    this.sha256 = '',
  });

  final String version;
  final int buildNumber;
  final String downloadUrl;
  final String notes;
  final DateTime? publishedAt;
  final String githubRepo;
  final String sha256;

  factory AppRelease.fromMap(Map<String, dynamic> data) {
    return AppRelease(
      version: (data['version'] as String? ?? '').trim(),
      buildNumber: (data['buildNumber'] as num?)?.toInt() ?? 0,
      downloadUrl: (data['downloadUrl'] as String? ?? '').trim(),
      notes: (data['notes'] as String? ?? '').trim(),
      publishedAt: (data['publishedAt'] as Timestamp?)?.toDate(),
      githubRepo: (data['githubRepo'] as String? ?? '').trim(),
      sha256: (data['sha256'] as String? ?? '').trim().toLowerCase(),
    );
  }

  bool get isValid => version.isNotEmpty && downloadUrl.isNotEmpty;

  bool get canAutoInstall => githubRepo.isNotEmpty && isTrustedWindowsPackageUrl(downloadUrl);
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

bool isTrustedWindowsPackageUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.scheme != 'https') return false;
  if (!_isTrustedDownloadHost(uri.host)) return false;
  final path = uri.path.toLowerCase();
  if (!path.endsWith('.zip')) return false;
  if (uri.host.toLowerCase() == 'github.com' && !path.contains('/releases/download/')) return false;
  return true;
}

bool _isTrustedDownloadHost(String host) {
  final cleaned = host.toLowerCase();
  return cleaned == 'github.com' || cleaned.endsWith('.githubusercontent.com');
}

class AppUpdateService {
  AppUpdateService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  static const latestDocId = 'latest';
  static const _maxPackageBytes = 200 * 1024 * 1024;

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
        if (stored != null && _compareVersions(stored.version, github.version) > 0 && stored.isValid) {
          latest = AppRelease(
            version: stored.version,
            buildNumber: stored.buildNumber,
            downloadUrl: stored.downloadUrl.isNotEmpty ? stored.downloadUrl : github.downloadUrl,
            notes: stored.notes.isNotEmpty ? stored.notes : github.notes,
            publishedAt: stored.publishedAt ?? github.publishedAt,
            githubRepo: github.githubRepo,
            sha256: stored.sha256.isNotEmpty ? stored.sha256 : github.sha256,
          );
        } else if (stored != null && github.buildNumber == 0 && stored.buildNumber > 0) {
          latest = AppRelease(
            version: github.version,
            buildNumber: stored.buildNumber,
            downloadUrl: github.downloadUrl,
            notes: github.notes.isNotEmpty ? github.notes : stored.notes,
            publishedAt: github.publishedAt ?? stored.publishedAt,
            githubRepo: github.githubRepo,
            sha256: github.sha256,
          );
        }
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
      var sha256 = '';
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = (asset['name'] as String? ?? '').toLowerCase();
        final url = (asset['browser_download_url'] as String? ?? '').trim();
        if (url.isEmpty) continue;
        final isPreferred = name == 'pharmspecio-windows.zip' || name == 'phyimacy-windows.zip';
        final isZip = name.endsWith('.zip');
        if (!isPreferred && !isZip) continue;
        if (downloadUrl.isNotEmpty && !isPreferred) continue;
        downloadUrl = url;
        final digest = (asset['digest'] as String? ?? '').trim().toLowerCase();
        sha256 = digest.startsWith('sha256:') ? digest.substring(7).trim() : '';
        if (isPreferred) break;
      }
      if (downloadUrl.isEmpty) return null;
      final published = json['published_at'] as String?;
      return AppRelease(
        version: tag,
        buildNumber: 0,
        downloadUrl: downloadUrl,
        notes: '',
        publishedAt: published == null ? null : DateTime.tryParse(published),
        githubRepo: cleaned,
        sha256: sha256,
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

  /// Downloads the GitHub zip, verifies SHA-256, replaces this Windows install, then restarts.
  Future<void> installAndRestart({
    required AppRelease release,
    required void Function(double fraction, String label) onProgress,
  }) async {
    if (!Platform.isWindows) {
      throw StateError('In-app update is only available on Windows.');
    }
    final repo = release.githubRepo.trim();
    if (repo.isEmpty) {
      throw StateError('This computer is not connected to a trusted GitHub release.');
    }

    onProgress(0.02, 'Checking the official GitHub package...');
    final latest = await fetchGithubLatest(repo);
    if (latest == null || !latest.canAutoInstall) {
      throw StateError('GitHub did not return a verified Windows package.');
    }

    final installDir = File(Platform.resolvedExecutable).parent;
    final installPath = installDir.path.toLowerCase();
    if (installPath.contains('\\debug\\') || installPath.contains('/debug/')) {
      throw StateError(
        'This window is a developer debug session. Install the GitHub Release zip once, then use that Phyimacy.exe so Update now can replace it.',
      );
    }

    final work = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}phyimacy-update');
    if (work.existsSync()) {
      work.deleteSync(recursive: true);
    }
    work.createSync(recursive: true);
    final zipFile = File('${work.path}${Platform.pathSeparator}package.zip');
    final extractDir = Directory('${work.path}${Platform.pathSeparator}extracted');
    extractDir.createSync();

    onProgress(0.05, 'Downloading Phyimacy ${latest.version}...');
    await _downloadTrustedPackage(
      url: latest.downloadUrl,
      destination: zipFile,
      onProgress: (received, total) {
        final part = total <= 0 ? 0.2 : (received / total).clamp(0, 1);
        onProgress(0.05 + part * 0.55, 'Downloading Phyimacy ${latest.version}...');
      },
    );

    onProgress(0.62, 'Checking the package...');
    final bytes = zipFile.readAsBytesSync();
    if (latest.sha256.length == 64) {
      onProgress(0.64, 'Verifying the package checksum...');
      final actual = sha256.convert(bytes).toString();
      if (actual != latest.sha256) {
        zipFile.deleteSync();
        throw StateError('Update stopped: the file did not match GitHub SHA-256.');
      }
    }

    onProgress(0.72, 'Preparing files...');
    final payload = _extractVerifiedZip(bytes, extractDir);
    final exe = _findPayloadExe(payload);
    if (exe == null) {
      throw StateError('The package does not contain PharmSpecio.exe.');
    }

    onProgress(0.88, 'Windows may ask for permission. Click Yes. The app will close only after the updater starts...');
    final script = File('${work.path}${Platform.pathSeparator}apply.ps1');
    script.writeAsStringSync(_updaterScript(
      appPid: pid,
      payloadDir: exe.parent.path,
      installDir: installDir.path,
    ));
    final logFile = File('${Directory.systemTemp.path}${Platform.pathSeparator}pharmspecio-update.log');
    if (logFile.existsSync()) {
      try {
        logFile.deleteSync();
      } catch (_) {}
    }

    final fileArg = script.path.replaceAll("'", "''");
    final elevate = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        "Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$fileArg'",
      ],
    );
    if (elevate.exitCode != 0) {
      throw StateError(
        'Update was cancelled or needs Administrator. Click Yes on the Windows prompt, then open PharmSpecio again.',
      );
    }
    var started = false;
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (logFile.existsSync()) {
        final text = logFile.readAsStringSync();
        if (text.contains('start pid=')) {
          started = true;
          break;
        }
      }
    }
    if (!started) {
      throw StateError(
        'Windows did not start the updater. Click Yes on the Administrator prompt, or run PharmSpecio as Administrator once.',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    exit(0);
  }

  Future<void> _downloadTrustedPackage({
    required String url,
    required File destination,
    required void Function(int received, int total) onProgress,
  }) async {
    final start = Uri.parse(url);
    if (!isTrustedWindowsPackageUrl(url)) {
      throw StateError('Blocked: updates only install from GitHub Releases.');
    }
    final client = HttpClient();
    client.userAgent = 'Phyimacy-Updater';
    try {
      final response = await _openTrustedDownload(client, start);
      final total = response.contentLength;
      if (total > _maxPackageBytes) {
        await response.drain<void>();
        throw StateError('Update package is too large.');
      }
      final sink = destination.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          received += chunk.length;
          if (received > _maxPackageBytes) {
            throw StateError('Update package is too large.');
          }
          sink.add(chunk);
          onProgress(received, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<HttpClientResponse> _openTrustedDownload(HttpClient client, Uri start) async {
    var uri = start;
    for (var hop = 0; hop < 8; hop++) {
      if (uri.scheme != 'https' || !_isTrustedDownloadHost(uri.host)) {
        throw StateError('Blocked download host: ${uri.host}');
      }
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'Phyimacy-Updater');
      final response = await request.close();
      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null || location.isEmpty) {
          throw StateError('Download redirect was invalid.');
        }
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw StateError('Download failed (${response.statusCode}).');
      }
      return response;
    }
    throw StateError('Too many download redirects.');
  }

  Directory _extractVerifiedZip(List<int> bytes, Directory extractDir) {
    final archive = ZipDecoder().decodeBytes(bytes);
    var unpacked = 0;
    for (final entry in archive) {
      final name = entry.name.replaceAll('\\', '/');
      if (name.contains('..') || name.startsWith('/') || name.contains(':')) continue;
      unpacked += entry.size;
      if (unpacked > _maxPackageBytes * 2) {
        throw StateError('Update package expanded past the safety limit.');
      }
      final out = File('${extractDir.path}${Platform.pathSeparator}${name.replaceAll('/', Platform.pathSeparator)}');
      if (entry.isFile) {
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(entry.content as List<int>);
      } else {
        Directory(out.path).createSync(recursive: true);
      }
    }
    return extractDir;
  }

  File? _findPayloadExe(Directory root) {
    const names = {'pharmspecio.exe', 'phyimacy.exe'};
    final directPreferred = File('${root.path}${Platform.pathSeparator}PharmSpecio.exe');
    if (directPreferred.existsSync()) return directPreferred;
    final directLegacy = File('${root.path}${Platform.pathSeparator}phyimacy.exe');
    if (directLegacy.existsSync()) return directLegacy;
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is File && names.contains(entity.uri.pathSegments.last.toLowerCase())) {
        return entity;
      }
    }
    return null;
  }

  String _updaterScript({
    required int appPid,
    required String payloadDir,
    required String installDir,
  }) {
    String q(String value) => "'${value.replaceAll("'", "''")}'";
    return '''
\$ErrorActionPreference = 'Continue'
\$log = Join-Path \$env:TEMP 'pharmspecio-update.log'
function Log(\$m) { Add-Content -Path \$log -Value ("\$(Get-Date -Format o) \$m") }
\$appPid = $appPid
\$src = ${q(payloadDir)}
\$dest = ${q(installDir)}
Log "start pid=\$appPid src=\$src dest=\$dest"
for (\$i = 0; \$i -lt 80; \$i++) {
  if (-not (Get-Process -Id \$appPid -ErrorAction SilentlyContinue)) { break }
  Start-Sleep -Milliseconds 250
}
Get-Process -Name 'PharmSpecio','Phyimacy','phyimacy' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
\$copied = \$false
if (Get-Command robocopy -ErrorAction SilentlyContinue) {
  \$p = Start-Process -FilePath robocopy.exe -ArgumentList @(\$src, \$dest, '/E', '/IS', '/IT', '/R:12', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS') -Wait -PassThru -NoNewWindow
  if (\$p.ExitCode -le 7) { \$copied = \$true; Log "robocopy \$(\$p.ExitCode)" }
}
if (-not \$copied) {
  try {
    Copy-Item -Path (Join-Path \$src '*') -Destination \$dest -Recurse -Force -ErrorAction Stop
    \$copied = \$true
    Log 'copy-item ok'
  } catch {
    Log "copy-item failed: \$_"
  }
}
\$exe = Join-Path \$dest 'PharmSpecio.exe'
if (-not (Test-Path \$exe)) { \$exe = Join-Path \$dest 'Phyimacy.exe' }
if (-not \$copied -or -not (Test-Path \$exe)) {
  Log 'update failed; existing install was left unchanged'
  exit 1
}
Start-Process -FilePath \$exe -WorkingDirectory \$dest
Log 'restarted'
''';
  }
}
