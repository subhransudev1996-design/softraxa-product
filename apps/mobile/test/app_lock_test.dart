import 'package:flutter/material.dart';
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
  var now = DateTime(2026, 10, 7, 10);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 10, 7, 10);
    AppLockNotifier.clock = () => now;
    AppLockNotifier.signedIn = () => true;
  });

  group('PIN rules', () {
    test('4 to 6 digits only', () {
      expect(isValidPin('1234'), isTrue);
      expect(isValidPin('123456'), isTrue);
      expect(isValidPin('123'), isFalse);
      expect(isValidPin('1234567'), isFalse);
      expect(isValidPin('12a4'), isFalse);
    });

    test('hash depends on the salt and never equals the PIN', () {
      final a = hashPin('1234', 'salt-a');
      expect(a, hashPin('1234', 'salt-a'));
      expect(a, isNot(hashPin('1234', 'salt-b')));
      expect(a, isNot(hashPin('1235', 'salt-a')));
      expect(a.contains('1234'), isFalse);
    });
  });

  group('when to lock', () {
    test('locks on return only after the chosen time away', () {
      final left = DateTime(2026, 1, 1, 10);
      expect(
        shouldLockOnReturn(
          leftAt: left,
          now: left.add(const Duration(seconds: 59)),
          lockAfterSeconds: 60,
        ),
        isFalse,
      );
      expect(
        shouldLockOnReturn(
          leftAt: left,
          now: left.add(const Duration(seconds: 60)),
          lockAfterSeconds: 60,
        ),
        isTrue,
      );
      expect(
        shouldLockOnReturn(leftAt: left, now: left, lockAfterSeconds: 0),
        isTrue,
      );
      expect(
        shouldLockOnReturn(leftAt: null, now: left, lockAfterSeconds: 0),
        isFalse,
      );
    });

    test('PC idle lock waits at least a minute', () {
      final t0 = DateTime(2026, 1, 1, 10);
      expect(
        idleTooLong(
          lastUse: t0,
          now: t0.add(const Duration(seconds: 30)),
          lockAfterSeconds: 0,
        ),
        isFalse,
      );
      expect(
        idleTooLong(
          lastUse: t0,
          now: t0.add(const Duration(minutes: 5)),
          lockAfterSeconds: 300,
        ),
        isTrue,
      );
    });

    test('"Immediately" is offered on phones, not on the PC', () {
      expect(lockAfterChoices(desktop: false), contains(0));
      expect(lockAfterChoices(desktop: true), isNot(contains(0)));
    });
  });

  group('lock state', () {
    test('PIN: set, lock, wrong tries wait, right PIN unlocks', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final lock = c.read(appLockProvider.notifier);

      await lock.setPin('2468');
      expect(c.read(appLockProvider).enabled, isTrue);
      expect(c.read(appLockProvider).locked, isFalse);

      lock.lockNow();
      expect(c.read(appLockProvider).locked, isTrue);

      for (var i = 0; i < kPinTriesBeforeWait; i++) {
        expect(await lock.unlockWithPin('0000'), isFalse);
      }
      expect(c.read(appLockProvider).waitUntil, isNotNull);
      // During the wait even the right PIN is refused.
      expect(await lock.unlockWithPin('2468'), isFalse);
      expect(c.read(appLockProvider).locked, isTrue);

      now = now.add(kPinWait);
      expect(await lock.unlockWithPin('2468'), isTrue);
      expect(c.read(appLockProvider).locked, isFalse);
    });

    test('away long enough locks; a short trip does not', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final lock = c.read(appLockProvider.notifier);
      await lock.setPin('2468');
      await lock.setLockAfter(60);

      lock.markLeft();
      now = now.add(const Duration(seconds: 20));
      lock.markBack();
      expect(c.read(appLockProvider).locked, isFalse);

      lock.markLeft();
      now = now.add(const Duration(minutes: 2));
      lock.markBack();
      expect(c.read(appLockProvider).locked, isTrue);
    });

    test('never locks when signed out; turning off forgets the PIN', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final lock = c.read(appLockProvider.notifier);
      await lock.setPin('2468');

      AppLockNotifier.signedIn = () => false;
      lock.lockNow();
      expect(c.read(appLockProvider).locked, isFalse);

      await lock.disable();
      expect(c.read(appLockProvider).enabled, isFalse);
      expect(await lock.checkPin('2468'), isFalse);
    });
  });

  testWidgets('PC lock screen covers the app until the PIN is typed', (
    tester,
  ) async {
    final c = ProviderContainer(
      overrides: [appContextProvider.overrideWith(_NoShop.new)],
    );
    addTearDown(c.dispose);
    await tester.runAsync(
      () => c.read(appLockProvider.notifier).setPin('1357'),
    );
    c.read(appLockProvider.notifier).lockNow();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: AppLockGate(
            desktop: true,
            child: const Scaffold(body: Text('the bill')),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(LockScreen), findsOneWidget);

    // Wrong PIN first.
    for (final d in ['1', '1', '1', '1']) {
      await tester.tap(find.byKey(Key('pin-$d')));
    }
    await tester.tap(find.byKey(const Key('pin-ok')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.byKey(const Key('lock-error')), findsOneWidget);
    expect(find.byType(LockScreen), findsOneWidget);

    for (final d in ['1', '3', '5', '7']) {
      await tester.tap(find.byKey(Key('pin-$d')));
    }
    await tester.tap(find.byKey(const Key('pin-ok')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.byType(LockScreen), findsNothing);
    expect(find.text('the bill'), findsOneWidget);
  });
}
