import 'package:arth/models/user_profile.dart';
import 'package:arth/widgets/tax_journey_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('all tax question scenes render without layout errors', (
    tester,
  ) async {
    for (var step = 0; step < 12; step++) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 390,
                child: TaxJourneyScene(
                  step: step,
                  profile: const UserProfile(),
                  chapter: 'Tax profile',
                  helper: 'This answer shapes your tax plan.',
                  accent: const Color(0xFF4B68F6),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull, reason: 'Scene $step failed');
    }
  });
}
