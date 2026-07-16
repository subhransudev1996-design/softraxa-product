import 'package:flutter/material.dart';

import 'branding.dart';
import 'theme.dart';

/// Branded splash: violet gradient, the receipt mark "printing" itself
/// downward, then the name + tagline fading in. Shown while auth/app
/// context loads — it never outlives its job (router redirects away the
/// moment the context resolves). [trailing] hosts error/retry actions.
class BrandSplash extends StatefulWidget {
  const BrandSplash({super.key, this.trailing});

  final Widget? trailing;

  @override
  State<BrandSplash> createState() => _BrandSplashState();
}

class _BrandSplashState extends State<BrandSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  late final Animation<double> _print = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _name = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.45, 0.75, curve: Curves.easeOut),
  );
  late final Animation<double> _tag = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.6, 0.95, curve: Curves.easeOut),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce && _c.status != AnimationStatus.completed) _c.value = 1;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF8B5CF6), AppColors.primaryDark],
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            const Spacer(flex: 3),
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) => Column(children: [
                // the mark prints downward like a receipt
                SizedBox(
                  height: 150,
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: 0.05 + 0.95 * _print.value,
                      child: Image.asset(
                        'assets/brand/glyph_1024.png',
                        width: 150,
                        height: 150,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                Opacity(
                  opacity: _name.value,
                  child: Transform.translate(
                    offset: Offset(0, 10 * (1 - _name.value)),
                    child: const Text(
                      kAppName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Opacity(
                  opacity: _tag.value,
                  child: Text(
                    kAppTagline,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ]),
            ),
            const Spacer(flex: 2),
            if (widget.trailing != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: widget.trailing,
              )
            else
              const Padding(
                padding: EdgeInsets.only(bottom: 36),
                child: SizedBox(
                  width: 130,
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    backgroundColor: Colors.white24,
                    color: Colors.white,
                    borderRadius: BorderRadius.all(Radius.circular(2)),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
