import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arth/app.dart';

void main() {
  FlutterSecureStorage.setMockInitialValues({});

  testWidgets('ArthApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: ArthApp()));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('ARTH'), findsOneWidget);

    // Let the splash animations finish, but dispose before the 2.5s route
    // timer advances into Firebase-backed services.
    await tester.pump(const Duration(seconds: 2));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
