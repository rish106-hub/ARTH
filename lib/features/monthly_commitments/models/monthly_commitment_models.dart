import 'dart:convert';

enum CommitmentSource { detected, manual }

class MonthlyCommitment {
  const MonthlyCommitment({
    required this.id,
    required this.label,
    required this.monthlyAmount,
    required this.nextExpectedDate,
    required this.source,
  });

  final String id;
  final String label;
  final int monthlyAmount;
  final DateTime nextExpectedDate;
  final CommitmentSource source;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'monthlyAmount': monthlyAmount,
        'nextExpectedDate': nextExpectedDate.toIso8601String(),
        'source': source.name,
      };

  factory MonthlyCommitment.fromJson(Map<String, dynamic> json) =>
      MonthlyCommitment(
        id: json['id']?.toString() ?? '',
        label: json['label']?.toString() ?? 'Commitment',
        monthlyAmount: (json['monthlyAmount'] as num?)?.round() ?? 0,
        nextExpectedDate:
            DateTime.tryParse(json['nextExpectedDate']?.toString() ?? '') ??
                DateTime.now(),
        source: json['source'] == CommitmentSource.detected.name
            ? CommitmentSource.detected
            : CommitmentSource.manual,
      );
}

class MonthlyCommitmentsState {
  const MonthlyCommitmentsState({this.manual = const []});

  final List<MonthlyCommitment> manual;

  MonthlyCommitmentsState withManual(List<MonthlyCommitment> value) =>
      MonthlyCommitmentsState(manual: value);

  String toJsonString() => jsonEncode({
        'manual': manual.map((item) => item.toJson()).toList(),
      });

  factory MonthlyCommitmentsState.fromJsonString(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return MonthlyCommitmentsState(
      manual: (json['manual'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MonthlyCommitment.fromJson)
          .where((item) => item.id.isNotEmpty && item.monthlyAmount > 0)
          .toList(growable: false),
    );
  }
}
