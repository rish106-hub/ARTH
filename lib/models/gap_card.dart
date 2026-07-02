import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum GapDifficulty { easy, medium, complex }

@immutable
class GapAction {
  final String label;
  final String url;

  const GapAction({required this.label, required this.url});

  factory GapAction.fromJson(Map<String, dynamic> json) =>
      GapAction(label: json['label'] as String, url: json['url'] as String);

  Map<String, dynamic> toJson() => {'label': label, 'url': url};
}

@immutable
class GapCard {
  final String id;
  final String section; // e.g. "80C", "80CCD(1B)"
  final String title; // e.g. "Investments Gap"
  final String shortDesc; // sub-label
  final String message; // plain English explanation
  final int gapAmount; // rupees
  final GapDifficulty difficulty;
  final String difficultyLabel;
  final String deadline;
  final List<GapAction> actions;
  final String colorHex;
  final bool isDone;

  const GapCard({
    required this.id,
    required this.section,
    required this.title,
    required this.shortDesc,
    required this.message,
    required this.gapAmount,
    required this.difficulty,
    required this.difficultyLabel,
    required this.deadline,
    required this.actions,
    required this.colorHex,
    this.isDone = false,
  });

  GapCard copyWith({bool? isDone, int? gapAmount}) => GapCard(
        id: id,
        section: section,
        title: title,
        shortDesc: shortDesc,
        message: message,
        gapAmount: gapAmount ?? this.gapAmount,
        difficulty: difficulty,
        difficultyLabel: difficultyLabel,
        deadline: deadline,
        actions: actions,
        colorHex: colorHex,
        isDone: isDone ?? this.isDone,
      );

  Color get accentColor {
    if (gapAmount >= 50000) return AppColors.gold;
    if (gapAmount >= 10000) return AppColors.amber;
    return AppColors.teal;
  }

  IconData get difficultyIcon {
    switch (difficulty) {
      case GapDifficulty.easy:
        return Icons.bolt_rounded;
      case GapDifficulty.medium:
        return Icons.tune_rounded;
      case GapDifficulty.complex:
        return Icons.account_tree_outlined;
    }
  }

  factory GapCard.fromJson(Map<String, dynamic> json, int computedGap) {
    final actionsJson = json['actions'] as List<dynamic>? ?? [];
    final diffStr = json['difficulty'] as String? ?? 'easy';
    final diff = diffStr == 'medium'
        ? GapDifficulty.medium
        : diffStr == 'complex'
            ? GapDifficulty.complex
            : GapDifficulty.easy;

    return GapCard(
      id: json['id'] as String,
      section: json['section'] as String,
      title: json['title'] as String,
      shortDesc: json['short_desc'] as String? ?? '',
      message: json['message'] as String? ?? '',
      gapAmount: computedGap,
      difficulty: diff,
      difficultyLabel: json['difficulty_label'] as String? ?? '',
      deadline: json['deadline'] as String? ?? '31 March 2026',
      actions: actionsJson
          .map((a) => GapAction.fromJson(a as Map<String, dynamic>))
          .toList(),
      colorHex: json['color_hex'] as String? ?? 'FF9800',
    );
  }

  factory GapCard.fromStoredJson(Map<String, dynamic> json) {
    final actionsJson = json['actions'] as List<dynamic>? ?? [];
    final difficultyName = json['difficulty'] as String? ?? 'easy';
    final difficulty = difficultyName == 'medium'
        ? GapDifficulty.medium
        : difficultyName == 'complex'
            ? GapDifficulty.complex
            : GapDifficulty.easy;

    return GapCard(
      id: json['id'] as String,
      section: json['section'] as String,
      title: json['title'] as String,
      shortDesc: json['shortDesc'] as String? ?? '',
      message: json['message'] as String? ?? '',
      gapAmount: json['gapAmount'] as int? ?? 0,
      difficulty: difficulty,
      difficultyLabel: json['difficultyLabel'] as String? ?? '',
      deadline: json['deadline'] as String? ?? '',
      actions: actionsJson
          .map((a) => GapAction.fromJson(a as Map<String, dynamic>))
          .toList(),
      colorHex: json['colorHex'] as String? ?? 'FF9800',
      isDone: json['isDone'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'section': section,
        'title': title,
        'shortDesc': shortDesc,
        'message': message,
        'gapAmount': gapAmount,
        'difficulty': difficulty.name,
        'difficultyLabel': difficultyLabel,
        'deadline': deadline,
        'actions': actions.map((a) => a.toJson()).toList(),
        'colorHex': colorHex,
        'isDone': isDone,
      };
}
