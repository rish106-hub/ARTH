import 'dart:convert';

/// A user-entered income source (freelance, rent, side business, etc.) kept
/// strictly on-device — see [OtherIncomeNotifier]. Never synced to the backend.
class OtherIncomeSource {
  const OtherIncomeSource({
    required this.id,
    required this.label,
    required this.monthlyAmount,
  });

  final String id;
  final String label;
  final int monthlyAmount; // rupees/month, positive

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'monthlyAmount': monthlyAmount,
      };

  factory OtherIncomeSource.fromJson(Map<String, dynamic> json) =>
      OtherIncomeSource(
        id: json['id']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        monthlyAmount: (json['monthlyAmount'] as num?)?.round() ?? 0,
      );

  static String encodeList(List<OtherIncomeSource> sources) =>
      jsonEncode(sources.map((s) => s.toJson()).toList());

  static List<OtherIncomeSource> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(OtherIncomeSource.fromJson)
          .where((s) => s.label.isNotEmpty && s.monthlyAmount > 0)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
