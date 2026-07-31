import 'package:arth/widgets/premium_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const label = 'What ARTH reads';
  const detail =
      'ARTH reads only bank and UPI transaction SMS. Personal messages are '
      'ignored, and parsing stays on this device.';

  /// Hosts the disclosure under a hard width so overflow is real, not implied
  /// by a MediaQuery the layout is free to ignore.
  Widget host({double width = 360, double textScale = 1.0}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 720),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: const SingleChildScrollView(
                child: ArthDisclosure(label: label, detail: detail),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('starts collapsed so the detail costs the user nothing',
      (tester) async {
    await tester.pumpWidget(host());

    expect(find.text(label), findsOneWidget);
    expect(find.text(detail), findsNothing);
  });

  testWidgets('reveals and hides the detail on tap', (tester) async {
    await tester.pumpWidget(host());

    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    expect(find.text(detail), findsOneWidget);

    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    expect(find.text(detail), findsNothing);
  });

  testWidgets('the label row survives a narrow phone at large text',
      (tester) async {
    // 320dp at 1.5x is where an icon, a label and a chevron in one row overflow
    // if the label is not free to wrap.
    await tester.pumpWidget(host(width: 320, textScale: 1.5));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(detail), findsOneWidget);
  });

  testWidgets('announces itself once, as a collapsed button', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host());

    // The label appears exactly once: the row is one node, not a wrapper
    // narrating over a child that says the same thing.
    expect(
      tester.getSemantics(find.text(label)),
      matchesSemantics(
        label: label,
        isButton: true,
        hasExpandedState: true,
        isExpanded: false,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );

    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text(label)),
      matchesSemantics(
        label: label,
        isButton: true,
        hasExpandedState: true,
        isExpanded: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );

    handle.dispose();
  });
}
