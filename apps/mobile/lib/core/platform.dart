import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// True on Windows/macOS/Linux desktop builds.
///
/// Used to hide camera-only features (mobile_scanner has no desktop
/// backend) and to route receipt printing through the native OS print
/// dialog instead of the Bluetooth-only thermal path.
bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// Shared width breakpoint above which screens switch to a desktop-style
/// layout (persistent sidebar, dense multi-column dashboard, etc).
const kDesktopBreakpoint = 900.0;
