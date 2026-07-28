import 'dart:convert';

enum MonthlyCloseStep { credit, bills, claims }

class MonthlyCloseRecord {
  const MonthlyCloseRecord({
    required this.periodKey,
    this.completedSteps = const {},
    this.updatedAt,
    this.completedAt,
  });

  final String periodKey;
  final Set<MonthlyCloseStep> completedSteps;
  final DateTime? updatedAt;
  final DateTime? completedAt;

  bool get isComplete => MonthlyCloseStep.values.every(completedSteps.contains);

  MonthlyCloseRecord mark(
    MonthlyCloseStep step,
    bool complete,
    DateTime now,
  ) {
    final steps = {...completedSteps};
    complete ? steps.add(step) : steps.remove(step);
    final allComplete = MonthlyCloseStep.values.every(steps.contains);
    return MonthlyCloseRecord(
      periodKey: periodKey,
      completedSteps: steps,
      updatedAt: now,
      completedAt: allComplete ? completedAt ?? now : null,
    );
  }

  String toJsonString() => jsonEncode({
        'periodKey': periodKey,
        'completedSteps': completedSteps.map((step) => step.name).toList(),
        'updatedAt': updatedAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
      });

  factory MonthlyCloseRecord.fromJsonString(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final steps = (json['completedSteps'] as List<dynamic>? ?? const [])
        .map((value) => MonthlyCloseStep.values
            .where((step) => step.name == value)
            .firstOrNull)
        .whereType<MonthlyCloseStep>()
        .toSet();
    return MonthlyCloseRecord(
      periodKey: json['periodKey']?.toString() ?? '',
      completedSteps: steps,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      completedAt: DateTime.tryParse(json['completedAt']?.toString() ?? ''),
    );
  }
}

class EvidenceHealthItem {
  const EvidenceHealthItem({
    required this.label,
    required this.detail,
    required this.ready,
  });

  final String label;
  final String detail;
  final bool ready;
}

class EvidenceHealth {
  const EvidenceHealth({
    required this.items,
    required this.pendingReceiptCount,
  });

  final List<EvidenceHealthItem> items;
  final int pendingReceiptCount;

  int get readyCount => items.where((item) => item.ready).length;
  int get totalCount => items.length;
}

class FigureAudit {
  const FigureAudit({
    required this.id,
    required this.label,
    required this.amount,
    required this.source,
    required this.detail,
    this.confirmedAt,
    this.editedByUser = false,
  });

  final String id;
  final String label;
  final int amount;
  final String source;
  final String detail;
  final DateTime? confirmedAt;
  final bool editedByUser;
}

enum CohortBenchmarkStatus { profileNeeded, waitingForSample, available }

class CohortBenchmark {
  const CohortBenchmark({
    required this.status,
    required this.sampleSize,
    required this.minimumSampleSize,
    this.city,
    this.ctcBandLabel,
    this.averageRentPercent,
  });

  static const minimumPrivateSample = 30;

  final CohortBenchmarkStatus status;
  final int sampleSize;
  final int minimumSampleSize;
  final String? city;
  final String? ctcBandLabel;
  final int? averageRentPercent;

  bool get canShowComparison =>
      status == CohortBenchmarkStatus.available &&
      sampleSize >= minimumSampleSize &&
      averageRentPercent != null;

  factory CohortBenchmark.fromAggregate({
    required int sampleSize,
    required String city,
    required String ctcBandLabel,
    required int averageRentPercent,
    int minimumSampleSize = minimumPrivateSample,
  }) {
    if (sampleSize < minimumSampleSize) {
      return CohortBenchmark(
        status: CohortBenchmarkStatus.waitingForSample,
        sampleSize: sampleSize,
        minimumSampleSize: minimumSampleSize,
        city: city,
        ctcBandLabel: ctcBandLabel,
      );
    }
    return CohortBenchmark(
      status: CohortBenchmarkStatus.available,
      sampleSize: sampleSize,
      minimumSampleSize: minimumSampleSize,
      city: city,
      ctcBandLabel: ctcBandLabel,
      averageRentPercent: averageRentPercent.clamp(0, 100),
    );
  }
}

class MonthlyCloseSnapshot {
  const MonthlyCloseSnapshot({
    required this.periodLabel,
    required this.creditAmount,
    required this.openClaimCount,
    required this.evidenceHealth,
    required this.figureAudits,
    required this.cohort,
  });

  final String periodLabel;
  final int creditAmount;
  final int openClaimCount;
  final EvidenceHealth evidenceHealth;
  final List<FigureAudit> figureAudits;
  final CohortBenchmark cohort;
}
