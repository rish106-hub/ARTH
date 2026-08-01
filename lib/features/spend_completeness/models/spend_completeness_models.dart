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
        sharedEssentials:
            ((json['sharedEssentials'] as num?)?.round() ?? 0).clamp(
          0,
          100000000,
        ),
        yourSharePercent:
            ((json['yourSharePercent'] as num?)?.round() ?? 50).clamp(
          0,
          100,
        ),
      );
}

/// User choices for spend completeness.
///
/// This object is stored only in account-scoped secure storage. It is never
/// included in the spend-map backend payload.
class SpendCompletenessState {
  const SpendCompletenessState({
    this.trustedSalarySourceId,
    this.userSalarySenders = const {},
    this.missingSources = const {},
    this.confirmedRecurringIds = const {},
    this.dismissedRecurringIds = const {},
    this.household = const HouseholdPlan(),
    this.categoryBudgets = const {},
  });

  final String? trustedSalarySourceId;

  /// Senders the user has explicitly told us pay their salary, normalised the
  /// same way [trustedSalarySourceId] is.
  ///
  /// [trustedSalarySourceId] can only pick among senders the parser already
  /// recognised as salary, so it cannot help when a credit was never flagged in
  /// the first place — which is exactly when the user needs to intervene. This
  /// set is that override, and it is authoritative: the user knows who pays
  /// them better than a keyword list does.
  final Set<String> userSalarySenders;
  final Set<MissingSpendSource> missingSources;
  final Set<String> confirmedRecurringIds;
  final Set<String> dismissedRecurringIds;
  final HouseholdPlan household;
  final Map<String, int> categoryBudgets;

  /// Every field, so adding one cannot silently drop it. The notifier used to
  /// rebuild this object field by field in eight places; a new field had to be
  /// threaded through all eight or it vanished on the next edit.
  SpendCompletenessState copyWith({
    String? trustedSalarySourceId,
    bool clearTrustedSalarySource = false,
    Set<String>? userSalarySenders,
    Set<MissingSpendSource>? missingSources,
    Set<String>? confirmedRecurringIds,
    Set<String>? dismissedRecurringIds,
    HouseholdPlan? household,
    Map<String, int>? categoryBudgets,
  }) {
    return SpendCompletenessState(
      trustedSalarySourceId: clearTrustedSalarySource
          ? null
          : trustedSalarySourceId ?? this.trustedSalarySourceId,
      userSalarySenders: userSalarySenders ?? this.userSalarySenders,
      missingSources: missingSources ?? this.missingSources,
      confirmedRecurringIds:
          confirmedRecurringIds ?? this.confirmedRecurringIds,
      dismissedRecurringIds:
          dismissedRecurringIds ?? this.dismissedRecurringIds,
      household: household ?? this.household,
      categoryBudgets: categoryBudgets ?? this.categoryBudgets,
    );
  }

  Map<String, dynamic> toJson() => {
        if (trustedSalarySourceId != null)
          'trustedSalarySourceId': trustedSalarySourceId,
        'userSalarySenders': userSalarySenders.toList(),
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
      userSalarySenders:
          (json['userSalarySenders'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .where((value) => value.isNotEmpty)
              .toSet(),
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
          ? HouseholdPlan.fromJson(json['household'] as Map<String, dynamic>)
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
