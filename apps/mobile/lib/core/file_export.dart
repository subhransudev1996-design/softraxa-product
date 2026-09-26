import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a generated file (Excel export, PDF…) to the user: a Save dialog on
/// Windows/desktop, the share sheet on phones (WhatsApp, email, Drive — how
/// shop owners send files to their accountant).
///
/// Returns a short message for a snackbar, or null if the user cancelled.
Future<String?> saveOrShareFile(
  Uint8List bytes,
  String fileName, {
  String? subject,
}) async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    final ext = fileName.contains('.') ? fileName.split('.').last : null;
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save $fileName',
      fileName: fileName,
      type: ext == null ? FileType.any : FileType.custom,
      allowedExtensions: ext == null ? null : [ext],
      bytes: bytes,
    );
    return path == null ? null : 'Saved to $path';
  }
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes);
  final result = await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], subject: subject ?? fileName),
  );
  return result.status == ShareResultStatus.dismissed ? null : 'Shared $fileName';
}
