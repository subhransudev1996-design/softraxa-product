import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/dashboard/dashboard_screen.dart';
import '../features/pos/pos_providers.dart';
import '../features/products/product_providers.dart';
import '../features/stock/stock_screens.dart';

/// Invalidate every provider that displays stock quantities.
///
/// Call after ANY operation that moves stock — sale, purchase, either
/// return, manual adjustment, job-card parts, Excel import, invoice
/// cancel. The shell tabs (Products, POS, Dashboard) are kept alive in
/// an IndexedStack, so their autoDispose providers stay warm and would
/// otherwise show stale quantities until a manual pull-to-refresh.
void invalidateStockData(WidgetRef ref) {
  ref.invalidate(productsProvider);
  ref.invalidate(stockListProvider);
  ref.invalidate(posProductsProvider);
  ref.invalidate(dashboardStatsProvider);
}
