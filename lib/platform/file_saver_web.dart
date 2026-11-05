import 'dart:js_interop';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart' as web;

abstract final class FileSaver {
  /// Browsers have no save dialog, so the file goes to the browser's downloads.
  static Future<String?> saveAs({
    required String dialogTitle,
    required String fileName,
    required String extension,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
  }) async {
    final name = fileName.endsWith('.$extension') ? fileName : '$fileName.$extension';
    _download(name, bytes, mimeType);
    return name;
  }

  static Future<String> saveToDownloads({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
  }) async {
    _download(fileName, bytes, mimeType);
    return fileName;
  }

  static Future<Uint8List?> readPicked(PlatformFile file) async => file.bytes;

  static void _download(String fileName, Uint8List bytes, String mimeType) {
    final blob = web.Blob(<web.BlobPart>[bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
  }
}
