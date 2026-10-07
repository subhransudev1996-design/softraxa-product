import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:softraxa_inventory/features/app_lock/app_lock.dart';
import 'package:softraxa_inventory/features/app_lock/app_lock_settings.dart';

void main() {
  testWidgets('PC: set a PIN from settings, then a wrong current PIN is told', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppLockSettings(context, desktop: true),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('app-lock-switch')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin-field')), '1234');
    await tester.enterText(find.byKey(const Key('pin-again-field')), '1234');
    await tester.tap(find.byKey(const Key('pin-save')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(c.read(appLockProvider).enabled, isTrue);
    expect(find.text('App lock is on'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));

    await tester.tap(find.text('Change PIN'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin-field')), '0000');
    await tester.tap(find.byKey(const Key('pin-save')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(find.text('Wrong PIN'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
