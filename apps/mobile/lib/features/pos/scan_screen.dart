import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/formatters.dart';
import '../../core/supabase_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../offline/offline_service.dart';
import '../products/product_providers.dart';
import 'cart.dart';

/// Camera barcode scanner (PRD 7.9).
///
/// mode = 'pos'   : scanned product is added to the bill (continuous scanning)
/// mode = 'return': pops the raw barcode string back to the caller
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key, this.mode = 'pos'});

  final String mode;

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  String _lastCode = '';
  DateTime _lastTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _handling = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;

    // debounce identical scans for a few seconds
    final now = DateTime.now();
    if (code == _lastCode && now.difference(_lastTime).inSeconds < 3) return;
    _lastCode = code;
    _lastTime = now;

    if (widget.mode == 'return') {
      context.pop(code);
      return;
    }

    _handling = true;
    try {
      final client = ref.read(supabaseProvider);
      Map<String, dynamic>? found;
      try {
        found = await findByBarcode(client, code);
      } catch (_) {
        // offline: try local cache
        final cached = await ref
            .read(offlineServiceProvider)
            .findCachedByBarcode(code);
        if (cached != null) found = {'product': cached, 'variant': null};
      }

      if (!mounted) return;
      if (found != null) {
        final product = found['product'] as Map<String, dynamic>;
        final variant = found['variant'] as Map<String, dynamic>?;
        // Weighted scale-label barcodes carry the quantity (e.g. 0.485 kg).
        final scanQty = (found['qty'] as num?)?.toDouble() ?? 1.0;
        final stock = toDouble(
          variant?['current_stock'] ?? product['current_stock'],
        );
        final notifier = ref.read(cartProvider.notifier);
        final projectedQty =
            notifier.qtyInCart(
              product['id'] as String,
              variant?['id'] as String?,
            ) +
            scanQty;
        final overStock = projectedQty > stock;
        notifier.addProduct(product, variant: variant, addQty: scanQty);
        final label =
            '${product['name']}${variant != null ? ' (${variant['name']})' : ''}'
            '${scanQty != 1 ? ' × ${qty(scanQty)}' : ''}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              overStock
                  ? '$label added — only ${qty(stock)} in stock, billing ${qty(projectedQty)}!'
                  : 'Added: $label',
            ),
            backgroundColor: overStock ? AppColors.orange : null,
            duration: Duration(seconds: overStock ? 3 : 1),
          ),
        );
      } else {
        // Unknown barcode -> offer to create the product (PRD 7.9 step 4)
        final create = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Product not found'),
            content: Text(
              'No product with barcode $code.\nAdd it as a new product?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Skip'),
              ),
              FilledButton(
                style: dialogActionStyle,
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Add product'),
              ),
            ],
          ),
        );
        if (create == true && mounted) {
          await context.push('/products/new?barcode=$code');
        }
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      _handling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.mode == 'return' ? 'Scan barcode' : 'Scan to bill'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 260,
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: CustomPaint(
                painter: _CornerPainter(color: AppColors.primary),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            top: 100,
            child: Text(
              'Align barcode within the frame',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (widget.mode == 'pos')
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: SafeArea(
                top: false,
                child: FilledButton.icon(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.shopping_cart),
                  label: Text(
                    cart.lines.isEmpty
                        ? 'Back to bill'
                        : 'Done — ${cart.itemCount} ${cart.itemCount == 1 ? 'item' : 'items'} in bill',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Brand-colored corner brackets drawn over the scanner viewfinder frame.
class _CornerPainter extends CustomPainter {
  const _CornerPainter({required this.color});

  final Color color;

  static const _len = 24.0;
  static const _thickness = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _thickness
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    void corner(Offset origin, Offset dx, Offset dy) {
      canvas.drawLine(origin, origin + dx, paint);
      canvas.drawLine(origin, origin + dy, paint);
    }

    corner(const Offset(0, 0), const Offset(_len, 0), const Offset(0, _len));
    corner(
      Offset(size.width, 0),
      const Offset(-_len, 0),
      const Offset(0, _len),
    );
    corner(
      Offset(0, size.height),
      const Offset(_len, 0),
      const Offset(0, -_len),
    );
    corner(
      Offset(size.width, size.height),
      const Offset(-_len, 0),
      const Offset(0, -_len),
    );
  }

  @override
  bool shouldRepaint(covariant _CornerPainter oldDelegate) =>
      oldDelegate.color != color;
}
