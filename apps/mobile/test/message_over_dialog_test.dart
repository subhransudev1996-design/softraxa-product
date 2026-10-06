import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/core/widgets.dart';

void main() {
  testWidgets('an error raised inside a dialog shows above it', (t) async {
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    content: TextButton(
                      onPressed: () => showError(ctx, 'Something broke'),
                      child: const Text('fail'),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.text('fail'));
    await t.pump();
    expect(find.byKey(const ValueKey('overlay-message')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await t.pump(const Duration(seconds: 5));
    expect(find.byKey(const ValueKey('overlay-message')), findsNothing);
  });

  testWidgets('on a page it is still a snackbar', (t) async {
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showSuccess(context, 'Saved'),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('go'));
    await t.pump();
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
