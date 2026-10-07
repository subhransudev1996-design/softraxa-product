import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:softraxa_inventory/core/supabase_providers.dart';
import 'package:softraxa_inventory/features/app_lock/app_lock.dart';
import 'package:softraxa_inventory/features/app_lock/lock_screen.dart';

class _NoShop extends AppContextNotifier {
  @override
  Future<AppContext> build() async => AppContext(
    profile: null,
    business: null,
    features: null,
    subscription: null,
    permissions: null,
  );
}

void main() {
  testWidgets(
    'the cursor goes back to where it was after unlocking',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      AppLockNotifier.signedIn = () => true;
      final c = ProviderContainer(
        overrides: [appContextProvider.overrideWith(_NoShop.new)],
      );
      addTearDown(c.dispose);
      await tester.runAsync(
        () => c.read(appLockProvider.notifier).setPin('1357'),
      );
      final field = FocusNode();
      addTearDown(field.dispose);
      final text = TextEditingController();
      addTearDown(text.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            home: AppLockGate(
              desktop: true,
              child: Scaffold(
                body: TextField(
                  controller: text,
                  focusNode: field,
                  autofocus: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(field.hasFocus, isTrue);
      await tester.enterText(find.byType(TextField), 'Egg');
      await tester.pump();

      c.read(appLockProvider.notifier).lockNow();
      await tester.pump();
      expect(field.hasFocus, isFalse);

      // The PIN typed on the keyboard goes to the lock, not to the field.
      for (final k in [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.enter,
      ]) {
        await tester.sendKeyEvent(k);
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(LockScreen), findsNothing);
      expect(text.text, 'Egg');
      expect(field.hasFocus, isTrue);
      // Typing carries on after "Egg" instead of replacing it.
      expect(text.selection, const TextSelection.collapsed(offset: 3));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
