import 'i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../features/app_lock/app_lock.dart';

import 'branding.dart';
import 'notifications.dart';
import 'router.dart';
import 'supabase_providers.dart';
import 'theme.dart';
import 'theme_mode.dart';
import 'walkthrough.dart';
import 'widgets.dart';

// Chrome colors match the desktop sidebar (dark navy in both themes),
// so title bar + sidebar read as one continuous app frame.
const _barBg = Color(0xFF14162B);
const _barFg = Color(0xFF9A9FC0);

/// Custom window title bar for desktop builds. Replaces the native
/// Windows caption bar (hidden via `TitleBarStyle.hidden` in main.dart):
/// drag-to-move, double-click to maximize/restore, and min/max/close
/// buttons. Shows the Dukania mark and name, then the shop's name.
class DesktopTitleBar extends ConsumerStatefulWidget {
  const DesktopTitleBar({super.key});

  @override
  ConsumerState<DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends ConsumerState<DesktopTitleBar>
    with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final businessName =
        ref.watch(appContextProvider).value?.businessName ?? '';
    final lockOn = ref.watch(appLockProvider.select((s) => s.enabled));
    // While locked only the window buttons work.
    final locked = ref.watch(appLockProvider.select((s) => s.locked)) && lockOn;
    return Material(
      color: _barBg,
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            // drag area (logo + shop name)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => windowManager.startDragging(),
                onDoubleTap: _toggleMaximize,
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    Image.asset(
                      'assets/brand/icon_1024.png',
                      width: 22,
                      height: 22,
                      filterQuality: FilterQuality.medium,
                    ),
                    const SizedBox(width: 9),
                    const Text(
                      kAppName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (businessName.isNotEmpty) ...[
                      Container(
                        width: 1,
                        height: 14,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                      Expanded(
                        child: Text(
                          businessName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _barFg,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (businessName.isNotEmpty && !locked) ...[
              _ActionButton(
                icon: Icons.help_outline,
                onTap: () async {
                  // The welcome tour spotlights dashboard widgets — go there
                  // first so the anchors are the visible ones.
                  ref.read(routerProvider).go('/home');
                  await Future<void>.delayed(const Duration(milliseconds: 250));
                  final ctx = rootNavigatorKey.currentContext;
                  if (ctx != null && ctx.mounted) showWalkthrough(ctx, 'home');
                },
              ),
              const _NotificationBell(),
              _ActionButton(
                icon: Icons.translate,
                onTap: () {
                  final ctx = rootNavigatorKey.currentContext;
                  if (ctx != null) showLanguagePicker(ctx, ref);
                },
              ),
              _ActionButton(
                icon: ref.watch(darkModeProvider)
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                onTap: () => ref.read(darkModeProvider.notifier).toggle(),
              ),
              if (lockOn)
                _ActionButton(
                  icon: Icons.lock_outline,
                  onTap: () => ref.read(appLockProvider.notifier).lockNow(),
                ),
              _ActionButton(
                icon: Icons.logout,
                hoverForeground: Color(0xFFF87171),
                onTap: () async {
                  final ctx = rootNavigatorKey.currentContext;
                  if (ctx == null) return;
                  final ok = await confirmDialog(
                    ctx,
                    title: t('Logout'),
                    message: t('Are you sure you want to logout?'),
                    confirmText: t('Logout'),
                  );
                  if (ok) await ref.read(supabaseProvider).auth.signOut();
                },
              ),
              Container(
                width: 1,
                height: 18,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ],
            _WinButton(
              icon: Icons.remove,
              onTap: () => windowManager.minimize(),
            ),
            _WinButton(
              icon: _maximized ? Icons.filter_none : Icons.crop_square,
              iconSize: _maximized ? 13 : 16,
              onTap: _toggleMaximize,
            ),
            _WinButton(
              icon: Icons.close,
              hoverColor: const Color(0xFFE81123),
              hoverForeground: Colors.white,
              onTap: () => windowManager.close(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WinButton extends StatefulWidget {
  const _WinButton({
    required this.icon,
    required this.onTap,
    this.iconSize = 16,
    this.hoverColor = const Color(0x14FFFFFF),
    this.hoverForeground,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double iconSize;
  final Color hoverColor;
  final Color? hoverForeground;

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    // No Tooltip here: this bar lives ABOVE the Navigator (mounted in
    // MaterialApp.builder), so there is no Overlay ancestor — a Tooltip
    // would throw "No Overlay widget found". Plain hover styling only.
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: 40,
          color: _hover ? widget.hoverColor : Colors.transparent,
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: _hover ? (widget.hoverForeground ?? Colors.white) : _barFg,
          ),
        ),
      ),
    );
  }
}

/// Title-bar action (help / bell / theme / logout): same hover treatment
/// as the window buttons but slightly wider spacing.
class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.icon,
    required this.onTap,
    this.hoverForeground,
    this.badge,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? hoverForeground;
  final int? badge;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final badge = widget.badge ?? 0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 42,
          height: 40,
          color: _hover ? const Color(0x14FFFFFF) : Colors.transparent,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                widget.icon,
                size: 17,
                color: _hover
                    ? (widget.hoverForeground ?? Colors.white)
                    : _barFg,
              ),
              if (badge > 0)
                Positioned(
                  top: 7,
                  right: 7,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints: const BoxConstraints(minWidth: 15),
                    child: Text(
                      badge > 9 ? '9+' : '$badge',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationBell extends ConsumerWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(notificationsProvider).value?.length ?? 0;
    return _ActionButton(
      icon: Icons.notifications_none,
      badge: count,
      onTap: () {
        final ctx = rootNavigatorKey.currentContext;
        if (ctx == null) return;
        showNotificationsDialog(
          ctx,
          ref,
          navigate: (route) => ref.read(routerProvider).go(route),
        );
      },
    );
  }
}
