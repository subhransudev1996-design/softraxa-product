import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The Windows program's company name changed from "com.softraxa" to
/// "Dukania" (1.0.15). Windows keeps app data in
/// AppData\Roaming\<company>\<product>, so the sign-in, settings and offline
/// bills not yet synced would seem to vanish. On the first start after the
/// update, copy the old folder into the new one. Existing files are never
/// overwritten and the old folder is left as it was.
Future<void> moveOldWindowsData() async {
  if (!Platform.isWindows) return;
  try {
    final appData = Platform.environment['APPDATA'];
    if (appData == null) return;
    final old = Directory('$appData\\com.softraxa\\Dukania');
    if (!old.existsSync()) return;
    final now = await getApplicationSupportDirectory();
    if (now.path.toLowerCase() == old.path.toLowerCase()) return;
    final done = File('${now.path}\\.moved_from_old_folder');
    if (done.existsSync()) return;
    await now.create(recursive: true);
    for (final entry in old.listSync(recursive: true)) {
      final target = '${now.path}${entry.path.substring(old.path.length)}';
      if (entry is Directory) {
        Directory(target).createSync(recursive: true);
      } else if (entry is File && !File(target).existsSync()) {
        File(target).parent.createSync(recursive: true);
        entry.copySync(target);
      }
    }
    done.writeAsStringSync(DateTime.now().toIso8601String());
  } catch (_) {
    // Never stop the app from starting; the data is still in the old folder.
  }
}
