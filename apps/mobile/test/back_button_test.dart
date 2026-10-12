import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:softraxa_inventory/features/shell/home_shell.dart';

/// The phone shell with five plain tabs, as router.dart builds it.
GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => HomeShell(navigationShell: shell),
      branches: [
        for (final path in ['/', '/pos', '/products', '/reports', '/more'])
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: path,
                builder: (_, _) => Center(child: Text('page $path')),
                routes: [
                  if (path == '/products')
                    GoRoute(
                      path: 'detail',
                      builder: (_, _) => const Text('product detail'),
                    ),
                ],
              ),
            ],
          ),
      ],
    ),
  ],
);

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
  });

  Future<GoRouter> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = _router();
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();
    return router;
  }

  bool exited() => calls.any((c) => c.method == 'SystemNavigator.pop');

  testWidgets('back on Home asks first; Stay keeps the app open', (
    tester,
  ) async {
    await pumpShell(tester);
    await _back(tester);
    expect(find.text('Close Dukania?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('page /'), findsOneWidget);
    expect(exited(), isFalse);
  });

  testWidgets('Close app closes it', (tester) async {
    await pumpShell(tester);
    await _back(tester);
    await tester.tap(find.text('Close app'));
    await tester.pumpAndSettle();
    expect(exited(), isTrue);
  });

  testWidgets('back on another tab goes to Home, not out', (tester) async {
    final router = await pumpShell(tester);
    router.go('/products');
    await tester.pumpAndSettle();
    await _back(tester);
    expect(find.text('page /'), findsOneWidget);
    expect(find.text('Close Dukania?'), findsNothing);
    expect(exited(), isFalse);
  });

  testWidgets('back inside a tab still goes back one screen', (tester) async {
    final router = await pumpShell(tester);
    router.go('/products/detail');
    await tester.pumpAndSettle();
    await _back(tester);
    expect(find.text('page /products'), findsOneWidget);
    expect(find.text('Close Dukania?'), findsNothing);
  });
}
