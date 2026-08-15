/// A user-confirmed meaning for a repeating work-related cost.
///
/// ARTH never infers this from a merchant name. The user chooses it after a
/// candidate is shown from their on-device transaction history.
enum WorkCostKind {
  commute,
  officeMeals,
  coffeeAndSnacks,
  workTools,
  workSocial,
  other;

  String get label => switch (this) {
        WorkCostKind.commute => 'Commute',
        WorkCostKind.officeMeals => 'Office meals',
        WorkCostKind.coffeeAndSnacks => 'Coffee & snacks',
        WorkCostKind.workTools => 'Work tools',
        WorkCostKind.workSocial => 'Work social',
        WorkCostKind.other => 'Other work cost',
      };
}

class WorkCostTag {
  const WorkCostTag({
    required this.candidateId,
    required this.kind,
    this.alternativeUnitCost,
  });

  final String candidateId;
  final WorkCostKind kind;
  final int? alternativeUnitCost;

  int? savingsPerPurchase(int typicalCost) {
    final alternative = alternativeUnitCost;
    if (alternative == null || alternative >= typicalCost) return null;
    return typicalCost - alternative;
  }

  Map<String, dynamic> toJson() => {
        'candidateId': candidateId,
        'kind': kind.name,
        if (alternativeUnitCost != null)
          'alternativeUnitCost': alternativeUnitCost,
      };

  factory WorkCostTag.fromJson(Map<String, dynamic> json) {
    final name = json['kind']?.toString();
    return WorkCostTag(
      candidateId: json['candidateId']?.toString() ?? '',
      kind: WorkCostKind.values.firstWhere(
        (value) => value.name == name,
        orElse: () => WorkCostKind.other,
      ),
      alternativeUnitCost: (json['alternativeUnitCost'] as num?)?.round(),
    );
  }
}

/// Where a "one less each workweek" experiment has got to.
enum WorkCostExperimentStatus {
  /// Committed to, not yet judged.
  running,

  /// The user says the change stuck.
  kept,

  /// The user says it did not.
  stopped;

  bool get isDecided => this != WorkCostExperimentStatus.running;
}

/// A commitment to spend less on one repeat cost, and what came of it.
///
/// Without this, the lens can only compute a suggestion and show it. Recording
/// the commitment is what makes the suggestion measurable: it separates a user
/// who read the number from a user who acted on it, and then from a user for
/// whom acting worked.
class WorkCostExperiment {
  const WorkCostExperiment({
    required this.candidateId,
    required this.status,
    required this.monthlyTarget,
    required this.startedAt,
    this.decidedAt,
  });

  final String candidateId;
  final WorkCostExperimentStatus status;

  /// The saving the lens promised when the user committed, held still so a
  /// later change in spending does not rewrite what they signed up for.
  final int monthlyTarget;

  final DateTime startedAt;

  /// When the user marked it kept or stopped. Null while it is still running.
  final DateTime? decidedAt;

  WorkCostExperiment decide(WorkCostExperimentStatus outcome, DateTime at) =>
      WorkCostExperiment(
        candidateId: candidateId,
        status: outcome,
        monthlyTarget: monthlyTarget,
        startedAt: startedAt,
        decidedAt: at,
      );

  /// How long the experiment ran, up to [now] while it is still running.
  int daysRunning(DateTime now) =>
      (decidedAt ?? now).difference(startedAt).inDays;

  Map<String, dynamic> toJson() => {
        'candidateId': candidateId,
        'status': status.name,
        'monthlyTarget': monthlyTarget,
        'startedAt': startedAt.toIso8601String(),
        if (decidedAt != null) 'decidedAt': decidedAt!.toIso8601String(),
      };

  static WorkCostExperiment? fromJson(Map<String, dynamic> json) {
    final candidateId = json['candidateId']?.toString() ?? '';
    final startedAt = DateTime.tryParse(json['startedAt']?.toString() ?? '');
    // A commitment with no owner or no start date cannot be measured, so it is
    // dropped rather than restored into a shape the UI has to defend against.
    if (candidateId.isEmpty || startedAt == null) return null;
    final status = json['status']?.toString();
    return WorkCostExperiment(
      candidateId: candidateId,
      status: WorkCostExperimentStatus.values.firstWhere(
        (value) => value.name == status,
        orElse: () => WorkCostExperimentStatus.running,
      ),
      monthlyTarget: (json['monthlyTarget'] as num?)?.round() ?? 0,
      startedAt: startedAt,
      decidedAt: DateTime.tryParse(json['decidedAt']?.toString() ?? ''),
    );
  }
}

class WorkCostState {
  const WorkCostState({
    this.tags = const {},
    this.dismissedCandidateIds = const {},
    this.experiments = const {},
  });

  final Map<String, WorkCostTag> tags;
  final Set<String> dismissedCandidateIds;

  /// Keyed by candidate id, so one repeat cost carries one experiment.
  final Map<String, WorkCostExperiment> experiments;

  WorkCostState withTag(WorkCostTag tag) => WorkCostState(
        tags: {...tags, tag.candidateId: tag},
        dismissedCandidateIds: {...dismissedCandidateIds}
          ..remove(tag.candidateId),
        experiments: experiments,
      );

  /// Drops the tag and any experiment on it: an experiment on a cost the user
  /// no longer calls work-related has nothing left to measure.
  WorkCostState withoutTag(String candidateId) => WorkCostState(
        tags: {...tags}..remove(candidateId),
        dismissedCandidateIds: dismissedCandidateIds,
        experiments: {...experiments}..remove(candidateId),
      );

  WorkCostState dismiss(String candidateId) => WorkCostState(
        tags: tags,
        dismissedCandidateIds: {...dismissedCandidateIds, candidateId},
        experiments: experiments,
      );

  WorkCostState withExperiment(WorkCostExperiment experiment) => WorkCostState(
        tags: tags,
        dismissedCandidateIds: dismissedCandidateIds,
        experiments: {...experiments, experiment.candidateId: experiment},
      );

  Map<String, dynamic> toJson() => {
        'tags': tags.values.map((tag) => tag.toJson()).toList(),
        'dismissedCandidateIds': dismissedCandidateIds.toList(),
        'experiments':
            experiments.values.map((entry) => entry.toJson()).toList(),
      };

  factory WorkCostState.fromJson(Map<String, dynamic> json) {
    final tags = <String, WorkCostTag>{};
    for (final raw in json['tags'] as List<dynamic>? ?? const []) {
      if (raw is! Map<String, dynamic>) continue;
      final tag = WorkCostTag.fromJson(raw);
      if (tag.candidateId.isNotEmpty) tags[tag.candidateId] = tag;
    }
    final experiments = <String, WorkCostExperiment>{};
    for (final raw in json['experiments'] as List<dynamic>? ?? const []) {
      if (raw is! Map<String, dynamic>) continue;
      final experiment = WorkCostExperiment.fromJson(raw);
      if (experiment != null) experiments[experiment.candidateId] = experiment;
    }
    return WorkCostState(
      tags: tags,
      dismissedCandidateIds:
          (json['dismissedCandidateIds'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toSet(),
      experiments: experiments,
    );
  }
}

/// A repeat purchase pattern that the user may classify as a work cost.
class WorkCostCandidate {
  const WorkCostCandidate({
    required this.id,
    required this.merchant,
    required this.category,
    required this.transactionCount,
    required this.observedMonths,
    required this.totalAmount,
    required this.monthlyAmount,
    required this.medianTransactionAmount,
  });

  /// Stable local identity built from the transaction category and merchant.
  final String id;
  final String merchant;
  final String category;
  final int transactionCount;
  final int observedMonths;
  final int totalAmount;
  final int monthlyAmount;
  final int medianTransactionAmount;

  /// A small, concrete experiment: skip one similar purchase every workweek.
  /// The calculation uses a 52-week year divided across 12 months.
  int get oneLessPerWeekSavings => (medianTransactionAmount * 52 / 12).round();
}
