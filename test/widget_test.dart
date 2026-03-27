import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arth/app.dart';

void main() {
  testWidgets('ArthApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: ArthApp(),
      ),
    );

    // Verify that our app starts and shows something (like the splash screen).
    // Since it's a router app, we check if the MaterialApp.router is present.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
