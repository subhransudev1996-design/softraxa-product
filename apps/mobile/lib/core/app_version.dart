import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The installed app's version with its build number, "1.0.7 (8)" — from
/// pubspec's version (1.0.7+8). Empty when the platform can't tell.
Future<String> readAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    var version = info.version.trim();
    var build = info.buildNumber.trim();
    // Some platforms give the whole "1.0.7+8" as the version.
    if (version.contains('+')) {
      final parts = version.split('+');
      version = parts.first;
      if (build.isEmpty) build = parts.last;
    }
    return formatAppVersion(version, build);
  } catch (_) {
    return '';
  }
}

String formatAppVersion(String version, String build) =>
    build.isEmpty || build == version ? version : '$version ($build)';

final appVersionProvider = FutureProvider<String>((ref) => readAppVersion());
