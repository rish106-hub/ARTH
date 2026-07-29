import 'package:arth/features/monthly_close/models/monthly_close_models.dart';
import 'package:arth/features/monthly_close/providers/monthly_close_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const juneRecord = MonthlyCloseRecord(
    periodKey: '2026-06',
    completedSteps: {MonthlyCloseStep.credit, MonthlyCloseStep.bills},
  );

  test('reconcile keeps record inside the same calendar month', () {
    final resolved = reconcileMonthlyCloseRecord(
      stored: juneRecord,
      now: DateTime(2026, 6, 30, 23, 59),
    );

    expect(resolved.periodKey, '2026-06');
    expect(resolved.completedSteps, juneRecord.completedSteps);
  });

  test('reconcile drops a prior month on rehydrate', () {
    final resolved = reconcileMonthlyCloseRecord(
      stored: juneRecord,
      now: DateTime(2026, 7, 1),
    );

    expect(resolved.periodKey, '2026-07');
    expect(resolved.completedSteps, isEmpty);
    expect(resolved.completedAt, isNull);
  });

  test('reconcile starts fresh when storage is missing', () {
    final resolved = reconcileMonthlyCloseRecord(
      stored: null,
      now: DateTime(2026, 7, 28),
    );

    expect(resolved.periodKey, '2026-07');
    expect(resolved.completedSteps, isEmpty);
  });

  test('delayUntilNextMonthBoundary reaches the next calendar month', () {
    final delay = delayUntilNextMonthBoundary(DateTime(2026, 7, 28, 15, 30));

    expect(
      DateTime(2026, 7, 28, 15, 30).add(delay),
      DateTime(2026, 8, 1),
    );
  });
}
