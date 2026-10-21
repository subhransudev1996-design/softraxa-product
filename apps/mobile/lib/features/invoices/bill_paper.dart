import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Paper for full-page bills (print and Share PDF). Kept on this device:
/// it depends on the printer next to it, so the shop's PC can print A5
/// while a phone shares A4.
enum BillPaper { a4, a5 }

const _kBillPaperPrefKey = 'bill_paper'; // 'a4' | 'a5'

final billPaperProvider = NotifierProvider<BillPaperNotifier, BillPaper>(
  BillPaperNotifier.new,
);

class BillPaperNotifier extends Notifier<BillPaper> {
  @override
  BillPaper build() {
    _load();
    return BillPaper.a4;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_kBillPaperPrefKey) == 'a5') state = BillPaper.a5;
    } catch (_) {
      // No saved choice: A4.
    }
  }

  Future<void> set(BillPaper paper) async {
    state = paper;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBillPaperPrefKey, paper.name);
  }
}
