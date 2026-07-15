import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

/// Emits on every auth state change (login, logout, token refresh).
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseProvider).auth.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentUser;
});

/// Everything the app needs after login: profile, business, feature flags,
/// subscription. Backed by the `get_my_context` RPC.
class AppContext {
  AppContext({
    required this.profile,
    required this.business,
    required this.features,
    required this.subscription,
  });

  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? business;
  final Map<String, dynamic>? features;
  final Map<String, dynamic>? subscription;

  bool get hasBusiness => business != null;
  String? get businessId => business?['id'] as String?;
  String get businessName => (business?['name'] as String?) ?? '';
  String get invoicePrefix => (business?['invoice_prefix'] as String?) ?? 'INV';
  bool get gstEnabled =>
      (business?['tax_preference'] ?? 'gst') == 'gst' && featureOn('gst_billing');

  bool featureOn(String key) => (features?[key] as bool?) ?? true;

  /// active | trial | expired | suspended (with grace period applied)
  String get subscriptionState {
    final sub = subscription;
    if (sub == null) return 'active';
    final status = sub['status'] as String? ?? 'active';
    if (status == 'suspended') return 'suspended';
    final expiry = DateTime.tryParse(sub['expiry_date'] as String? ?? '');
    final grace = (sub['grace_days'] as num?)?.toInt() ?? 0;
    if (expiry != null &&
        DateTime.now().isAfter(expiry.add(Duration(days: grace + 1)))) {
      return 'expired';
    }
    return status;
  }

  bool get isBlocked =>
      subscriptionState == 'expired' || subscriptionState == 'suspended';
}

final appContextProvider = AsyncNotifierProvider<AppContextNotifier, AppContext>(
  AppContextNotifier.new,
);

class AppContextNotifier extends AsyncNotifier<AppContext> {
  @override
  Future<AppContext> build() async {
    // Rebuild whenever auth changes.
    ref.watch(authStateProvider);
    final client = ref.watch(supabaseProvider);
    if (client.auth.currentUser == null) {
      return AppContext(profile: null, business: null, features: null, subscription: null);
    }
    final data = await client.rpc('get_my_context') as Map<String, dynamic>;
    return AppContext(
      profile: data['profile'] as Map<String, dynamic>?,
      business: data['business'] as Map<String, dynamic>?,
      features: data['features'] as Map<String, dynamic>?,
      subscription: data['subscription'] as Map<String, dynamic>?,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    ref.invalidateSelf();
    await future;
  }
}
