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

class WorkCostState {
  const WorkCostState({
    this.tags = const {},
    this.dismissedCandidateIds = const {},
  });

  final Map<String, WorkCostTag> tags;
  final Set<String> dismissedCandidateIds;

  WorkCostState withTag(WorkCostTag tag) => WorkCostState(
        tags: {...tags, tag.candidateId: tag},
        dismissedCandidateIds: {...dismissedCandidateIds}
          ..remove(tag.candidateId),
      );

  WorkCostState withoutTag(String candidateId) {
    final updated = {...tags}..remove(candidateId);
    return WorkCostState(
      tags: updated,
      dismissedCandidateIds: dismissedCandidateIds,
    );
  }

  WorkCostState dismiss(String candidateId) => WorkCostState(
        tags: tags,
        dismissedCandidateIds: {...dismissedCandidateIds, candidateId},
      );

  Map<String, dynamic> toJson() => {
        'tags': tags.values.map((tag) => tag.toJson()).toList(),
        'dismissedCandidateIds': dismissedCandidateIds.toList(),
      };

  factory WorkCostState.fromJson(Map<String, dynamic> json) {
    final tags = <String, WorkCostTag>{};
    for (final raw in json['tags'] as List<dynamic>? ?? const []) {
      if (raw is! Map<String, dynamic>) continue;
      final tag = WorkCostTag.fromJson(raw);
      if (tag.candidateId.isNotEmpty) tags[tag.candidateId] = tag;
    }
    return WorkCostState(
      tags: tags,
      dismissedCandidateIds:
          (json['dismissedCandidateIds'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toSet(),
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
