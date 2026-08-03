import 'dart:convert';

enum DecisionKind {
  moveForWork,
  buyVehicle,
  changeJobs;

  String get label => switch (this) {
        DecisionKind.moveForWork => 'Move for work',
        DecisionKind.buyVehicle => 'Buy a vehicle',
        DecisionKind.changeJobs => 'Change jobs',
      };

  String get detail => switch (this) {
        DecisionKind.moveForWork => 'Rent, commute, deposit',
        DecisionKind.buyVehicle => 'EMI, fuel, parking',
        DecisionKind.changeJobs => 'Take-home, commute, switching cost',
      };
}

class DecisionScenario {
  const DecisionScenario({
    required this.id,
    required this.name,
    required this.kind,
    required this.monthlyIncomeChange,
    required this.currentMonthlyCost,
    required this.proposedMonthlyCost,
    required this.oneOffCost,
    required this.createdAt,
    this.goalId,
  });

  final String id;
  final String name;
  final DecisionKind kind;
  final int monthlyIncomeChange;
  final int currentMonthlyCost;
  final int proposedMonthlyCost;
  final int oneOffCost;
  final DateTime createdAt;
  final String? goalId;

  int get monthlyCostChange => proposedMonthlyCost - currentMonthlyCost;
  int get monthlyRoomChange => monthlyIncomeChange - monthlyCostChange;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'monthlyIncomeChange': monthlyIncomeChange,
        'currentMonthlyCost': currentMonthlyCost,
        'proposedMonthlyCost': proposedMonthlyCost,
        'oneOffCost': oneOffCost,
        'createdAt': createdAt.toIso8601String(),
        if (goalId != null) 'goalId': goalId,
      };

  factory DecisionScenario.fromJson(Map<String, dynamic> json) =>
      DecisionScenario(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Scenario',
        kind: DecisionKind.values.firstWhere(
          (value) => value.name == json['kind'],
          orElse: () => DecisionKind.moveForWork,
        ),
        monthlyIncomeChange:
            (json['monthlyIncomeChange'] as num?)?.round() ?? 0,
        currentMonthlyCost: (json['currentMonthlyCost'] as num?)?.round() ?? 0,
        proposedMonthlyCost:
            (json['proposedMonthlyCost'] as num?)?.round() ?? 0,
        oneOffCost: (json['oneOffCost'] as num?)?.round() ?? 0,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        goalId: json['goalId']?.toString(),
      );
}

class DecisionSandboxState {
  const DecisionSandboxState({this.scenarios = const []});

  final List<DecisionScenario> scenarios;

  String toJsonString() => jsonEncode({
        'scenarios': scenarios.map((item) => item.toJson()).toList(),
      });

  factory DecisionSandboxState.fromJsonString(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return DecisionSandboxState(
      scenarios: (json['scenarios'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(DecisionScenario.fromJson)
          .where((item) => item.id.isNotEmpty)
          .toList(growable: false),
    );
  }
}
