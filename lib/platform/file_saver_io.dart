import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

abstract final class FileSaver {
  /// Asks where to save, then writes the file. Returns the saved path, or null when cancelled.
  static Future<String?> saveAs({
    required String dialogTitle,
    required String fileName,
    required String extension,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
  }) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [extension],
    );
    if (path == null || path.trim().isEmpty) return null;
    final file = File(path.endsWith('.$extension') ? path : '$path.$extension');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Writes straight to the Downloads folder. Returns the saved path.
  static Future<String> saveToDownloads({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
  }) async {
    final directory = await getDownloadsDirectory() ?? Directory.systemTemp;
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<Uint8List?> readPicked(PlatformFile file) async {
    if (file.bytes != null) return file.bytes;
    final path = file.path;
    if (path == null) return null;
    return File(path).readAsBytes();
  }
}
