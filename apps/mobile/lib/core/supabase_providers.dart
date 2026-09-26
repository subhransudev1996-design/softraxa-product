import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'network.dart';

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

/// Emits on every auth state change (login, logout, token refresh).
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseProvider).auth.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentUser;
});

/// Signed-in user id, changing only on sign-in/sign-out (not on token
/// refresh). Works offline: the saved session supplies it before the auth
/// stream emits. Account-scoped local data keys off this.
final currentUserIdProvider = Provider<String?>((ref) {
  final client = ref.read(supabaseProvider);
  return ref.watch(
    authStateProvider.select(
      (s) => s.value?.session?.user.id ?? client.auth.currentUser?.id,
    ),
  );
});

/// Everything the app needs after login: profile, business, feature flags,
/// subscription. Backed by the `get_my_context` RPC.
class AppContext {
  AppContext({
    required this.profile,
    required this.business,
    required this.features,
    required this.subscription,
    required this.permissions,
    this.offlineSince,
  });

  /// Built from the `get_my_context` response.
  factory AppContext.fromJson(Map<String, dynamic> data, {DateTime? offlineSince}) =>
      AppContext(
        profile: data['profile'] as Map<String, dynamic>?,
        business: data['business'] as Map<String, dynamic>?,
        features: data['features'] as Map<String, dynamic>?,
        subscription: data['subscription'] as Map<String, dynamic>?,
        permissions: data['permissions'] as Map<String, dynamic>?,
        offlineSince: offlineSince,
      );

  /// Set when the server couldn't be reached and this context is the last
  /// one saved on this device (offline start-up); the time it was saved.
  final DateTime? offlineSince;
  bool get isOffline => offlineSince != null;

  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? business;
  final Map<String, dynamic>? features;
  final Map<String, dynamic>? subscription;
  final Map<String, dynamic>? permissions;

  bool get hasBusiness => business != null;
  String? get businessId => business?['id'] as String?;
  String get businessName => (business?['name'] as String?) ?? '';
  String get invoicePrefix => (business?['invoice_prefix'] as String?) ?? 'INV';
  bool get gstEnabled =>
      (business?['tax_preference'] ?? 'gst') == 'gst' &&
      featureOn('gst_billing');

  String get role => (profile?['role'] as String?) ?? 'owner';
  bool get isOwner => role == 'owner' || role == 'admin';

  // Mirrors of the database's has_permission() (migration 0037). The server
  // enforces these; the app only uses them to hide actions that would fail.
  bool _perm(String key, bool fallback) =>
      isOwner || ((permissions?[key] as bool?) ?? fallback);

  bool get canCreateInvoice => _perm('can_create_invoice', true);
  bool get canEditPrices => _perm('can_edit_prices', false);
  bool get canViewProfit => _perm('can_view_profit', false);
  bool get canManageProducts => _perm('can_manage_products', true);
  bool get canManageStock => _perm('can_manage_stock', false);
  bool get canManageExpenses => _perm('can_manage_expenses', false);
  bool get canManageServices => _perm('can_manage_services', true);
  bool get canViewReports => _perm('can_view_reports', false);
  bool get canManagePurchases => _perm('can_manage_purchases', false);
  bool get canManageReturns => _perm('can_manage_returns', false);
  bool get canEditInvoices => _perm('can_edit_invoices', false);
  bool get canRecordPayments => _perm('can_record_payments', true);

  /// Staff management is owner-only at launch (LAUNCH_SPECIFICATION roles).
  bool get canManageStaff => isOwner;

  int get userLimit => (subscription?['user_limit'] as num?)?.toInt() ?? 999;
  int get staffCount => (subscription?['staff_count'] as num?)?.toInt() ?? 1;
  bool get isStaffLimitReached => userLimit != 999 && staffCount >= userLimit;

  bool featureOn(String key) => (features?[key] as bool?) ?? true;

  /// active | trial | expired | suspended (with grace period applied)
  String get subscriptionState {
    if (business != null && (business!['is_active'] as bool?) == false) {
      return 'suspended';
    }
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

final appContextProvider =
    AsyncNotifierProvider<AppContextNotifier, AppContext>(
      AppContextNotifier.new,
    );

/// How long a saved context may be used to start the app offline
/// (LAUNCH_SPECIFICATION, offline operation).
const kOfflineContextMaxAge = Duration(hours: 72);

class AppContextNotifier extends AsyncNotifier<AppContext> {
  static String _cacheKey(String uid) => 'app_context_$uid';

  @override
  Future<AppContext> build() async {
    // Rebuild whenever auth changes.
    ref.watch(authStateProvider);
    final client = ref.watch(supabaseProvider);
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      return AppContext(
        profile: null,
        business: null,
        features: null,
        subscription: null,
        permissions: null,
      );
    }
    try {
      final data =
          await client.rpc('get_my_context').timeout(const Duration(seconds: 15))
              as Map<String, dynamic>;
      unawaited(_save(uid, data));
      return AppContext.fromJson(data);
    } catch (e) {
      // Offline start-up: fall back to this user's last saved context, but
      // only for network failures and only while it's recent.
      if (!isNetworkError(e)) rethrow;
      final saved = await _load(uid);
      if (saved == null) rethrow;
      _refreshWhenOnline();
      return AppContext.fromJson(saved.data, offlineSince: saved.savedAt);
    }
  }

  Future<void> _save(String uid, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey(uid),
        jsonEncode({
          'saved_at': DateTime.now().toUtc().toIso8601String(),
          'data': data,
        }),
      );
    } catch (_) {
      // Best effort — only affects offline start-up.
    }
  }

  Future<({Map<String, dynamic> data, DateTime savedAt})?> _load(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(uid));
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.parse(json['saved_at'] as String);
      if (DateTime.now().toUtc().difference(savedAt) > kOfflineContextMaxAge) {
        return null;
      }
      return (data: Map<String, dynamic>.from(json['data'] as Map), savedAt: savedAt);
    } catch (_) {
      return null;
    }
  }

  /// Reload the live context as soon as the network is back.
  void _refreshWhenOnline() {
    final sub = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) ref.invalidateSelf();
    });
    ref.onDispose(sub.cancel);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    ref.invalidateSelf();
    await future;
  }
}
