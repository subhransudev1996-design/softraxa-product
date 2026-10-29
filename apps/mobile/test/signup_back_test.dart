import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:dukania/features/auth/forgot_password_screen.dart';
import 'package:dukania/features/auth/signup_screen.dart';

// As in the app, login opens these with go(), so nothing is behind them.
GoRouter _router(String start) => GoRouter(
  initialLocation: start,
  routes: [
    GoRoute(
      path: '/login',
      builder: (_, _) => const Scaffold(body: Text('login page')),
    ),
    GoRoute(path: '/signup', builder: (_, _) => const SignupScreen()),
    GoRoute(
      path: '/forgot-password',
      builder: (_, _) => const ForgotPasswordScreen(),
    ),
  ],
);

Future<void> _open(WidgetTester tester, String start) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(child: MaterialApp.router(routerConfig: _router(start))),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sign-up: "Log in" link goes to login', (tester) async {
    await _open(tester, '/signup');
    await tester.tap(find.text('Already have an account? Log in'));
    await tester.pumpAndSettle();
    expect(find.text('login page'), findsOneWidget);
  });

  testWidgets('sign-up: back arrow goes to login', (tester) async {
    await _open(tester, '/signup');
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('login page'), findsOneWidget);
  });

  for (final start in ['/signup', '/forgot-password']) {
    testWidgets('$start: phone back button goes to login, not out', (
      tester,
    ) async {
      await _open(tester, start);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('login page'), findsOneWidget);
    });
  }
}
