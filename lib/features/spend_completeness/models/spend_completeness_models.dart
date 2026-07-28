import 'dart:convert';

enum MissingSpendSource {
  cash,
  cardWithoutSms,
  unlinkedUpiOrBank;

  String get label => switch (this) {
        MissingSpendSource.cash => 'Cash payments',
        MissingSpendSource.cardWithoutSms => 'Cards without transaction SMS',
        MissingSpendSource.unlinkedUpiOrBank => 'Unlinked UPI or bank accounts',
      };
}

class HouseholdPlan {
  const HouseholdPlan({
    this.enabled = false,
    this.memberName = '',
    this.otherMonthlyIncome = 0,
    this.sharedEssentials = 0,
    this.yourSharePercent = 50,
  });

  final bool enabled;
  final String memberName;
  final int otherMonthlyIncome;
  final int sharedEssentials;
  final int yourSharePercent;

  int get yourSharedCost => (sharedEssentials * yourSharePercent / 100).round();

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'memberName': memberName,
        'otherMonthlyIncome': otherMonthlyIncome,
        'sharedEssentials': sharedEssentials,
        'yourSharePercent': yourSharePercent,
      };

  factory HouseholdPlan.fromJson(Map<String, dynamic> json) => HouseholdPlan(
        enabled: json['enabled'] == true,
        memberName: json['memberName']?.toString() ?? '',
        otherMonthlyIncome: ((json['otherMonthlyIncome'] as num?)?.round() ?? 0)
            .clamp(0, 100000000),
        sharedEssentials: ((json['sharedEssentials'] as num?)?.round() ?? 0)
            .clamp(0, 100000000),
        yourSharePercent:
            ((json['yourSharePercent'] as num?)?.round() ?? 50).clamp(0, 100),
      );
}

/// User choices for spend completeness.
///
/// This object is stored only in account-scoped secure storage. It is never
/// included in the spend-map backend payload.
class SpendCompletenessState {
  const SpendCompletenessState({
    this.trustedSalarySourceId,
    this.missingSources = const {},
    this.confirmedRecurringIds = const {},
    this.dismissedRecurringIds = const {},
    this.household = const HouseholdPlan(),
    this.categoryBudgets = const {},
  });

  final String? trustedSalarySourceId;
  final Set<MissingSpendSource> missingSources;
  final Set<String> confirmedRecurringIds;
  final Set<String> dismissedRecurringIds;
  final HouseholdPlan household;
  final Map<String, int> categoryBudgets;

  Map<String, dynamic> toJson() => {
        if (trustedSalarySourceId != null)
          'trustedSalarySourceId': trustedSalarySourceId,
        'missingSources': missingSources.map((source) => source.name).toList(),
        'confirmedRecurringIds': confirmedRecurringIds.toList(),
        'dismissedRecurringIds': dismissedRecurringIds.toList(),
        'household': household.toJson(),
        'categoryBudgets': categoryBudgets,
      };

  String toJsonString() => jsonEncode(toJson());

  factory SpendCompletenessState.fromJson(Map<String, dynamic> json) {
    final missing = (json['missingSources'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .map(
          (name) => MissingSpendSource.values
              .where((source) => source.name == name)
              .firstOrNull,
        )
        .whereType<MissingSpendSource>()
        .toSet();
    final rawBudgets =
        json['categoryBudgets'] as Map<String, dynamic>? ?? const {};
    return SpendCompletenessState(
      trustedSalarySourceId: json['trustedSalarySourceId']?.toString(),
      missingSources: missing,
      confirmedRecurringIds:
          (json['confirmedRecurringIds'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toSet(),
      dismissedRecurringIds:
          (json['dismissedRecurringIds'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toSet(),
      household: json['household'] is Map<String, dynamic>
          ? HouseholdPlan.fromJson(
              json['household'] as Map<String, dynamic>,
            )
          : const HouseholdPlan(),
      categoryBudgets: {
        for (final entry in rawBudgets.entries)
          if (entry.value is num && (entry.value as num) > 0)
            entry.key: (entry.value as num).round(),
      },
    );
  }

  factory SpendCompletenessState.fromJsonString(String value) =>
      SpendCompletenessState.fromJson(
        jsonDecode(value) as Map<String, dynamic>,
      );
}
