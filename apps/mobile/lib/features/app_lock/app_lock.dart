import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/i18n.dart';
import '../../core/platform.dart';

/// App lock: phones use the fingerprint / face / screen lock already set on
/// the phone; the PC uses a 4–6 digit PIN saved on this computer only.
///
/// The lock is a cover over the app — whatever was open underneath (a bill
/// half made) stays as it was.

const _kOn = 'app_lock_on';
const _kPinHash = 'app_lock_pin_hash';
const _kPinSalt = 'app_lock_pin_salt';
const _kAfter = 'app_lock_after_seconds';

/// Wrong PINs allowed before a short wait.
const kPinTriesBeforeWait = 5;
const kPinWait = Duration(seconds: 30);

/// "Lock after" choices, in seconds. 0 = as soon as you leave the app
/// (phones only — on the PC it would lock while you are still typing).
List<int> lockAfterChoices({required bool desktop}) =>
    desktop ? const [60, 300, 900, 1800] : const [0, 60, 300, 900];

int defaultLockAfter({required bool desktop}) => desktop ? 300 : 60;

String lockAfterLabel(int seconds) {
  if (seconds <= 0) return t('Immediately');
  final minutes = seconds ~/ 60;
  return minutes == 1
      ? t('After 1 minute')
      : t('After {v1} minutes', {'v1': '$minutes'});
}

/// A PIN is 4 to 6 digits.
bool isValidPin(String pin) => RegExp(r'^\d{4,6}$').hasMatch(pin);

/// Salted, stretched hash so the PIN itself is never stored.
String hashPin(String pin, String salt) {
  List<int> bytes = utf8.encode('$salt:$pin');
  for (var i = 0; i < 5000; i++) {
    bytes = sha256.convert(bytes).bytes;
  }
  return base64Encode(bytes);
}

String newSalt() {
  final r = Random.secure();
  return base64Encode(List<int>.generate(16, (_) => r.nextInt(256)));
}

/// Should the app lock now that the user is back after leaving at [leftAt]?
bool shouldLockOnReturn({
  required DateTime? leftAt,
  required DateTime now,
  required int lockAfterSeconds,
}) {
  if (leftAt == null) return false;
  return now.difference(leftAt).inSeconds >= lockAfterSeconds;
}

@immutable
class AppLockState {
  const AppLockState({
    required this.enabled,
    required this.locked,
    required this.lockAfterSeconds,
    this.hasPin = false,
    this.wrongTries = 0,
    this.waitUntil,
  });

  final bool enabled;
  final bool locked;
  final int lockAfterSeconds;

  /// PC: a PIN has been saved.
  final bool hasPin;

  /// PC: wrong PINs in a row, and the time the keypad opens again.
  final int wrongTries;
  final DateTime? waitUntil;

  AppLockState copyWith({
    bool? enabled,
    bool? locked,
    int? lockAfterSeconds,
    bool? hasPin,
    int? wrongTries,
    DateTime? waitUntil,
    bool clearWait = false,
  }) => AppLockState(
    enabled: enabled ?? this.enabled,
    locked: locked ?? this.locked,
    lockAfterSeconds: lockAfterSeconds ?? this.lockAfterSeconds,
    hasPin: hasPin ?? this.hasPin,
    wrongTries: wrongTries ?? this.wrongTries,
    waitUntil: clearWait ? null : (waitUntil ?? this.waitUntil),
  );
}

/// Read before runApp so the very first frame is already covered.
AppLockState _initial = AppLockState(
  enabled: false,
  locked: false,
  lockAfterSeconds: defaultLockAfter(desktop: isDesktopPlatform),
);

Future<void> loadAppLock() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final on = prefs.getBool(_kOn) ?? false;
    final hasPin = (prefs.getString(_kPinHash) ?? '').isNotEmpty;
    // On the PC the lock needs a PIN; without one it is off.
    final enabled = on && (!isDesktopPlatform || hasPin);
    _initial = AppLockState(
      enabled: enabled,
      // Lock at start only for someone signed in — the login screen
      // already asks for the password.
      locked: enabled && _signedIn(),
      lockAfterSeconds:
          prefs.getInt(_kAfter) ?? defaultLockAfter(desktop: isDesktopPlatform),
      hasPin: hasPin,
    );
  } catch (_) {}
}

bool _signedIn() {
  try {
    return Supabase.instance.client.auth.currentSession != null;
  } catch (_) {
    return false;
  }
}

/// Why the phone could not ask for the fingerprint / screen lock.
enum DeviceUnlockResult { ok, failed, noScreenLock }

final appLockProvider = NotifierProvider<AppLockNotifier, AppLockState>(
  AppLockNotifier.new,
);

class AppLockNotifier extends Notifier<AppLockState> {
  final _auth = LocalAuthentication();
  DateTime? _leftAt;
  bool _askingDevice = false;

  /// Tests replace these.
  static bool Function() signedIn = _signedIn;
  static DateTime Function() clock = DateTime.now;

  @override
  AppLockState build() => _initial;

  /// The phone's fingerprint / screen-lock prompt is open (the app looks
  /// "left" to the system while it shows; that must not count).
  bool get askingDevice => _askingDevice;

  // ── locking ──────────────────────────────────────────────────────────

  void lockNow() {
    if (state.enabled && signedIn()) state = state.copyWith(locked: true);
  }

  /// The app went to the background / the window was minimised.
  void markLeft() {
    if (!state.enabled || state.locked || _askingDevice) return;
    _leftAt = clock();
  }

  /// The app is back in front.
  void markBack() {
    final lock = shouldLockOnReturn(
      leftAt: _leftAt,
      now: clock(),
      lockAfterSeconds: state.lockAfterSeconds,
    );
    _leftAt = null;
    if (lock) lockNow();
  }

  /// Signed out: nothing to protect, so never show the lock.
  void onSignedOut() {
    _leftAt = null;
    state = state.copyWith(locked: false, wrongTries: 0, clearWait: true);
  }

  // ── unlocking ────────────────────────────────────────────────────────

  /// PC: check the PIN. After [kPinTriesBeforeWait] wrong PINs the keypad
  /// waits [kPinWait].
  Future<bool> unlockWithPin(String pin) async {
    final wait = state.waitUntil;
    if (wait != null && clock().isBefore(wait)) return false;
    if (!await checkPin(pin)) {
      final tries = state.wrongTries + 1;
      state = tries >= kPinTriesBeforeWait
          ? state.copyWith(wrongTries: 0, waitUntil: clock().add(kPinWait))
          : state.copyWith(wrongTries: tries, clearWait: true);
      return false;
    }
    state = state.copyWith(locked: false, wrongTries: 0, clearWait: true);
    return true;
  }

  /// Phone: ask for the fingerprint / face / screen lock.
  Future<DeviceUnlockResult> unlockWithDevice() async {
    final r = await askDevice(t('Unlock {v1}', {'v1': 'Dukania'}));
    if (r == DeviceUnlockResult.ok) state = state.copyWith(locked: false);
    return r;
  }

  Future<DeviceUnlockResult> askDevice(String reason) async {
    if (_askingDevice) return DeviceUnlockResult.failed;
    _askingDevice = true;
    try {
      if (!await _auth.isDeviceSupported()) {
        return DeviceUnlockResult.noScreenLock;
      }
      final ok = await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
      return ok ? DeviceUnlockResult.ok : DeviceUnlockResult.failed;
    } on LocalAuthException catch (e) {
      return e.code == LocalAuthExceptionCode.noCredentialsSet
          ? DeviceUnlockResult.noScreenLock
          : DeviceUnlockResult.failed;
    } catch (_) {
      return DeviceUnlockResult.failed;
    } finally {
      // The prompt's own "app left / came back" events are ignored.
      _leftAt = null;
      _askingDevice = false;
    }
  }

  Future<bool> checkPin(String pin) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hash = prefs.getString(_kPinHash);
      final salt = prefs.getString(_kPinSalt);
      if (hash == null || salt == null) return false;
      return hashPin(pin, salt) == hash;
    } catch (_) {
      return false;
    }
  }

  // ── settings ─────────────────────────────────────────────────────────

  /// PC: save a new PIN and turn the lock on.
  Future<void> setPin(String pin) async {
    assert(isValidPin(pin));
    final salt = newSalt();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPinSalt, salt);
    await prefs.setString(_kPinHash, hashPin(pin, salt));
    await prefs.setBool(_kOn, true);
    state = state.copyWith(enabled: true, hasPin: true, locked: false);
  }

  /// Phone: turn the lock on after one successful fingerprint / screen
  /// lock, so nobody is locked out by a phone without a screen lock.
  Future<DeviceUnlockResult> enableDeviceLock() async {
    final r = await askDevice(t('Confirm it is you'));
    if (r != DeviceUnlockResult.ok) return r;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOn, true);
    state = state.copyWith(enabled: true, locked: false);
    return r;
  }

  Future<void> setLockAfter(int seconds) async {
    state = state.copyWith(lockAfterSeconds: seconds);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kAfter, seconds);
    } catch (_) {}
  }

  /// Turn the lock off and forget the PIN.
  Future<void> disable() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kOn);
      await prefs.remove(_kPinHash);
      await prefs.remove(_kPinSalt);
    } catch (_) {}
    _leftAt = null;
    state = state.copyWith(
      enabled: false,
      locked: false,
      hasPin: false,
      wrongTries: 0,
      clearWait: true,
    );
  }
}

/// PC: no mouse or keyboard use for the "lock after" time (at least a
/// minute) locks the app.
bool idleTooLong({
  required DateTime lastUse,
  required DateTime now,
  required int lockAfterSeconds,
}) => now.difference(lastUse).inSeconds >= max(lockAfterSeconds, 60);
