import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/branding.dart';
import '../../core/i18n.dart';
import '../../core/platform.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import 'app_lock.dart';

/// Covers the app while it is locked. Everything underneath keeps its
/// state, but gets no taps, keys or focus until it is unlocked.
class AppLockGate extends ConsumerStatefulWidget {
  AppLockGate({super.key, required this.child, bool? desktop})
    : desktop = desktop ?? isDesktopPlatform;

  final Widget child;
  final bool desktop;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> {
  late final AppLifecycleListener _lifecycle;
  Timer? _idleTimer;
  DateTime _lastUse = DateTime.now();
  FocusNode? _focusBeforeLock;

  @override
  void initState() {
    super.initState();
    final lock = ref.read(appLockProvider.notifier);
    _lifecycle = AppLifecycleListener(
      onHide: lock.markLeft,
      onShow: lock.markBack,
    );
    if (widget.desktop) {
      // PC: lock after a while with no mouse or keyboard use.
      HardwareKeyboard.instance.addHandler(_onKey);
      _idleTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        final s = ref.read(appLockProvider);
        if (!s.enabled || s.locked) return;
        if (idleTooLong(
          lastUse: _lastUse,
          now: DateTime.now(),
          lockAfterSeconds: s.lockAfterSeconds,
        )) {
          lock.lockNow();
        }
      });
    }
  }

  bool _onKey(KeyEvent _) {
    _lastUse = DateTime.now();
    return false; // only watching, never handling
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _idleTimer?.cancel();
    if (widget.desktop) HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Put the cursor back where it was (e.g. the bill's search box).
    ref.listen(appLockProvider.select((s) => s.enabled && s.locked), (
      was,
      now,
    ) {
      if (now) {
        _focusBeforeLock = FocusManager.instance.primaryFocus;
      } else {
        _lastUse = DateTime.now();
        final f = _focusBeforeLock;
        _focusBeforeLock = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (f != null && f.context != null && f.canRequestFocus) {
            f.requestFocus();
          }
        });
      }
    });
    final s = ref.watch(appLockProvider);
    final covered = s.enabled && s.locked;
    return Stack(
      children: [
        ExcludeFocus(
          excluding: covered,
          child: ExcludeSemantics(
            excluding: covered,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _lastUse = DateTime.now(),
              onPointerHover: (_) => _lastUse = DateTime.now(),
              onPointerSignal: (_) => _lastUse = DateTime.now(),
              child: widget.child,
            ),
          ),
        ),
        if (covered)
          Positioned.fill(child: LockScreen(desktop: widget.desktop)),
      ],
    );
  }
}

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.desktop});

  final bool desktop;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _focus = FocusNode();
  String _pin = '';
  String? _error;
  bool _busy = false;
  bool _askLogout = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // A wait after wrong PINs counts down on screen.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ref.read(appLockProvider).waitUntil != null) {
        setState(() {});
      }
    });
    if (!widget.desktop) {
      // Phone: ask for the fingerprint right away.
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _unlockDevice();
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _focus.dispose();
    super.dispose();
  }

  int get _waitLeft {
    final w = ref.read(appLockProvider).waitUntil;
    if (w == null) return 0;
    final left = w.difference(AppLockNotifier.clock()).inSeconds + 1;
    return left > 0 ? left : 0;
  }

  void _digit(String d) {
    if (_busy || _waitLeft > 0 || _pin.length >= 6) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == 6) _submit();
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (_busy || _waitLeft > 0) return;
    if (_pin.length < 4) {
      setState(() => _error = t('Enter your 4 to 6 digit PIN'));
      return;
    }
    setState(() => _busy = true);
    final ok = await ref.read(appLockProvider.notifier).unlockWithPin(_pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pin = '';
      if (!ok) {
        _error = _waitLeft > 0 ? null : t('Wrong PIN');
      }
    });
  }

  Future<void> _unlockDevice() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await ref.read(appLockProvider.notifier).unlockWithDevice();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r == DeviceUnlockResult.noScreenLock) {
        _error = t(
          'This phone has no screen lock now. Log out and log in again with your password.',
        );
      }
    });
  }

  Future<void> _logout() async {
    setState(() => _busy = true);
    await ref.read(appLockProvider.notifier).disable();
    try {
      await ref.read(supabaseProvider).auth.signOut();
    } catch (_) {}
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    final ch = e.character;
    if (ch != null && RegExp(r'^\d$').hasMatch(ch)) {
      _digit(ch);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.backspace) {
      _back();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final shop = ref.watch(appContextProvider).value?.businessName ?? '';
    final wait = _waitLeft;
    final body = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/brand/icon_1024.png',
            width: 64,
            height: 64,
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(height: 14),
          Text(
            shop.isEmpty ? kAppName : shop,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 16, color: AppColors.inkSoft),
              const SizedBox(width: 6),
              Text(
                t('{v1} is locked', {'v1': kAppName}),
                style: TextStyle(color: AppColors.inkSoft, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 26),
          if (_askLogout)
            _logoutBox()
          else if (widget.desktop)
            _pinPad(wait)
          else
            FilledButton.icon(
              key: const Key('unlock-device'),
              onPressed: _busy ? null : _unlockDevice,
              icon: const Icon(Icons.fingerprint),
              label: Text(t('Unlock')),
              style: FilledButton.styleFrom(minimumSize: const Size(220, 52)),
            ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              key: const Key('lock-error'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.red, fontSize: 13.5),
            ),
          ],
          if (wait > 0) ...[
            const SizedBox(height: 14),
            Text(
              t('Too many wrong PINs. Try again in {v1} seconds.', {
                'v1': '$wait',
              }),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.red, fontSize: 13.5),
            ),
          ],
          if (!_askLogout) ...[
            const SizedBox(height: 18),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _askLogout = true),
              child: Text(
                widget.desktop
                    ? t('Forgot PIN? Log out')
                    : t('Can\'t unlock? Log out'),
              ),
            ),
          ],
        ],
      ),
    );
    return Material(
      color: AppColors.canvas,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: widget.desktop ? _onKey : null,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  Widget _logoutBox() => Column(
    children: [
      Text(
        t(
          'You will need your email and password to log in again. The app lock will be turned off.',
        ),
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.ink, fontSize: 14),
      ),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton(
            onPressed: _busy ? null : () => setState(() => _askLogout = false),
            child: Text(t('Back')),
          ),
          const SizedBox(width: 12),
          FilledButton(
            key: const Key('lock-logout'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: _busy ? null : _logout,
            child: Text(t('Logout')),
          ),
        ],
      ),
    ],
  );

  Widget _pinPad(int wait) {
    Widget key(String label, {VoidCallback? onTap, IconData? icon, Key? k}) =>
        Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            width: 72,
            height: 56,
            child: OutlinedButton(
              key: k,
              onPressed: wait > 0 || _busy ? null : onTap,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: icon != null
                  ? Icon(icon, size: 22)
                  : Text(
                      label,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        );
    Widget row(List<String> ds) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final d in ds) key(d, onTap: () => _digit(d), k: Key('pin-$d')),
      ],
    );
    return Column(
      children: [
        Text(
          t('Enter your PIN'),
          style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 18,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < (_pin.length < 4 ? 4 : _pin.length); i++)
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length
                        ? AppColors.primary
                        : Colors.transparent,
                    border: Border.all(color: AppColors.primary, width: 2),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        row(['1', '2', '3']),
        row(['4', '5', '6']),
        row(['7', '8', '9']),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            key('', icon: Icons.backspace_outlined, onTap: _back),
            key('0', onTap: () => _digit('0'), k: const Key('pin-0')),
            key(
              '',
              icon: Icons.arrow_forward,
              onTap: _submit,
              k: const Key('pin-ok'),
            ),
          ],
        ),
      ],
    );
  }
}
