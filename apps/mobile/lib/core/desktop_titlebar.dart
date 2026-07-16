import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'supabase_providers.dart';
import 'theme.dart';

// Chrome colors match the desktop sidebar (dark navy in both themes),
// so title bar + sidebar read as one continuous app frame.
const _barBg = Color(0xFF14162B);
const _barFg = Color(0xFF9A9FC0);

/// Custom window title bar for desktop builds. Replaces the native
/// Windows caption bar (hidden via `TitleBarStyle.hidden` in main.dart):
/// drag-to-move, double-click to maximize/restore, and min/max/close
/// buttons. Shows the shop's own name instead of a generic app title.
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
    return Material(
      color: _barBg,
      child: SizedBox(
        height: 40,
        child: Row(children: [
          // drag area (logo + shop name)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: _toggleMaximize,
              child: Row(children: [
                const SizedBox(width: 14),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, AppColors.primaryDark],
                    ),
                  ),
                  child: const Icon(Icons.storefront,
                      color: Colors.white, size: 14),
                ),
                const SizedBox(width: 10),
                if (businessName.isNotEmpty)
                  Expanded(
                    child: Text(
                      businessName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          _WinButton(
            icon: Icons.remove,
            tooltip: 'Minimize',
            onTap: () => windowManager.minimize(),
          ),
          _WinButton(
            icon: _maximized ? Icons.filter_none : Icons.crop_square,
            iconSize: _maximized ? 13 : 16,
            tooltip: _maximized ? 'Restore' : 'Maximize',
            onTap: _toggleMaximize,
          ),
          _WinButton(
            icon: Icons.close,
            tooltip: 'Close',
            hoverColor: const Color(0xFFE81123),
            hoverForeground: Colors.white,
            onTap: () => windowManager.close(),
          ),
        ]),
      ),
    );
  }
}

class _WinButton extends StatefulWidget {
  const _WinButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.iconSize = 16,
    this.hoverColor = const Color(0x14FFFFFF),
    this.hoverForeground,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
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
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
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
      ),
    );
  }
}
