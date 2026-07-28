enum ClaimCaseStatus { review, prepared, submitted, paid, closed }

class ClaimCase {
  const ClaimCase({
    required this.id,
    required this.paycheckItemId,
    required this.label,
    required this.detail,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.dueDate,
    this.note = '',
    this.selectedEvidenceIds = const [],
    this.updatedAt,
  });

  final String id;
  final String paycheckItemId;
  final String label;
  final String detail;
  final int amount;
  final ClaimCaseStatus status;
  final DateTime createdAt;
  final DateTime? dueDate;
  final String note;
  final List<String> selectedEvidenceIds;
  final DateTime? updatedAt;

  ClaimCase copyWith({
    String? label,
    String? detail,
    int? amount,
    ClaimCaseStatus? status,
    DateTime? dueDate,
    String? note,
    List<String>? selectedEvidenceIds,
    DateTime? updatedAt,
  }) {
    return ClaimCase(
      id: id,
      paycheckItemId: paycheckItemId,
      label: label ?? this.label,
      detail: detail ?? this.detail,
      amount: amount ?? this.amount,
      status: status ?? this.status,
      createdAt: createdAt,
      dueDate: dueDate ?? this.dueDate,
      note: note ?? this.note,
      selectedEvidenceIds: selectedEvidenceIds ?? this.selectedEvidenceIds,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'paycheckItemId': paycheckItemId,
        'label': label,
        'detail': detail,
        'amount': amount,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        if (dueDate != null) 'dueDate': dueDate!.toIso8601String(),
        'note': note,
        'selectedEvidenceIds': selectedEvidenceIds,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };

  factory ClaimCase.fromJson(Map<String, dynamic> json) => ClaimCase(
        id: json['id']?.toString() ?? '',
        paycheckItemId: json['paycheckItemId']?.toString() ?? '',
        label: json['label']?.toString() ?? 'Claim',
        detail: json['detail']?.toString() ?? '',
        amount: (json['amount'] as num?)?.round() ?? 0,
        status: ClaimCaseStatus.values.firstWhere(
          (value) => value.name == json['status'],
          orElse: () => ClaimCaseStatus.review,
        ),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        dueDate: DateTime.tryParse(json['dueDate']?.toString() ?? ''),
        note: json['note']?.toString() ?? '',
        selectedEvidenceIds:
            (json['selectedEvidenceIds'] as List<dynamic>? ?? const [])
                .map((value) => value.toString())
                .toList(growable: false),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      );
}

class ReconciliationSnapshot {
  const ReconciliationSnapshot({
    required this.id,
    required this.payPeriod,
    required this.createdAt,
    required this.promised,
    required this.grossPaid,
    required this.netPaid,
    required this.salaryCredit,
    required this.delta,
    required this.itemAmounts,
    required this.itemLabels,
    required this.evidenceIds,
  });

  final String id;
  final String payPeriod;
  final DateTime createdAt;
  final int promised;
  final int grossPaid;
  final int netPaid;
  final int salaryCredit;
  final int delta;
  final Map<String, int> itemAmounts;
  final Map<String, String> itemLabels;
  final List<String> evidenceIds;

  Map<String, dynamic> toJson() => {
        'id': id,
        'payPeriod': payPeriod,
        'createdAt': createdAt.toIso8601String(),
        'promised': promised,
        'grossPaid': grossPaid,
        'netPaid': netPaid,
        'salaryCredit': salaryCredit,
        'delta': delta,
        'itemAmounts': itemAmounts,
        'itemLabels': itemLabels,
        'evidenceIds': evidenceIds,
      };

  factory ReconciliationSnapshot.fromJson(Map<String, dynamic> json) =>
      ReconciliationSnapshot(
        id: json['id']?.toString() ?? '',
        payPeriod: json['payPeriod']?.toString() ?? 'Pay period',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        promised: (json['promised'] as num?)?.round() ?? 0,
        grossPaid: (json['grossPaid'] as num?)?.round() ?? 0,
        netPaid: (json['netPaid'] as num?)?.round() ?? 0,
        salaryCredit: (json['salaryCredit'] as num?)?.round() ?? 0,
        delta: (json['delta'] as num?)?.round() ?? 0,
        itemAmounts:
            (json['itemAmounts'] as Map<String, dynamic>? ?? const {}).map(
          (key, value) => MapEntry(key, (value as num?)?.round() ?? 0),
        ),
        itemLabels:
            (json['itemLabels'] as Map<String, dynamic>? ?? const {}).map(
          (key, value) => MapEntry(key, value.toString()),
        ),
        evidenceIds: (json['evidenceIds'] as List<dynamic>? ?? const [])
            .map((value) => value.toString())
            .toList(growable: false),
      );
}

class BenefitLedgerEntry {
  const BenefitLedgerEntry({
    required this.id,
    required this.label,
    required this.claimed,
    required this.source,
    this.annualCap,
    this.resetMonth,
    this.deadline,
  });

  final String id;
  final String label;
  final int? annualCap;
  final int claimed;
  final int? resetMonth;
  final DateTime? deadline;
  final String source;

  int? get remaining =>
      annualCap == null ? null : (annualCap! - claimed).clamp(0, annualCap!);

  BenefitLedgerEntry copyWith({
    int? annualCap,
    int? resetMonth,
    DateTime? deadline,
    String? source,
  }) {
    return BenefitLedgerEntry(
      id: id,
      label: label,
      annualCap: annualCap ?? this.annualCap,
      claimed: claimed,
      resetMonth: resetMonth ?? this.resetMonth,
      deadline: deadline ?? this.deadline,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        if (annualCap != null) 'annualCap': annualCap,
        'claimed': claimed,
        if (resetMonth != null) 'resetMonth': resetMonth,
        if (deadline != null) 'deadline': deadline!.toIso8601String(),
        'source': source,
      };

  factory BenefitLedgerEntry.fromJson(Map<String, dynamic> json) =>
      BenefitLedgerEntry(
        id: json['id']?.toString() ?? '',
        label: json['label']?.toString() ?? 'Benefit',
        annualCap: (json['annualCap'] as num?)?.round(),
        claimed: (json['claimed'] as num?)?.round() ?? 0,
        resetMonth: (json['resetMonth'] as num?)?.round(),
        deadline: DateTime.tryParse(json['deadline']?.toString() ?? ''),
        source: json['source']?.toString() ?? 'User-confirmed evidence',
      );
}

class PaydayChecklist {
  const PaydayChecklist({
    required this.monthKey,
    required this.creditFound,
    required this.payslipChecked,
    required this.claimItemsReviewed,
    this.completedAt,
  });

  final String monthKey;
  final bool creditFound;
  final bool payslipChecked;
  final bool claimItemsReviewed;
  final DateTime? completedAt;

  bool get complete => creditFound && payslipChecked && claimItemsReviewed;

  PaydayChecklist copyWith({
    bool? creditFound,
    bool? payslipChecked,
    bool? claimItemsReviewed,
    DateTime? completedAt,
  }) {
    return PaydayChecklist(
      monthKey: monthKey,
      creditFound: creditFound ?? this.creditFound,
      payslipChecked: payslipChecked ?? this.payslipChecked,
      claimItemsReviewed: claimItemsReviewed ?? this.claimItemsReviewed,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'monthKey': monthKey,
        'creditFound': creditFound,
        'payslipChecked': payslipChecked,
        'claimItemsReviewed': claimItemsReviewed,
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      };

  factory PaydayChecklist.fromJson(Map<String, dynamic> json) =>
      PaydayChecklist(
        monthKey: json['monthKey']?.toString() ?? '',
        creditFound: json['creditFound'] == true,
        payslipChecked: json['payslipChecked'] == true,
        claimItemsReviewed: json['claimItemsReviewed'] == true,
        completedAt: DateTime.tryParse(json['completedAt']?.toString() ?? ''),
      );
}

class EmployerRule {
  const EmployerRule({
    required this.id,
    required this.matchTerms,
    required this.sourceLabel,
    this.annualCap,
    this.resetMonth,
    this.deadlineMonth,
    this.deadlineDay,
  });

  final String id;
  final List<String> matchTerms;
  final int? annualCap;
  final int? resetMonth;
  final int? deadlineMonth;
  final int? deadlineDay;
  final String sourceLabel;

  factory EmployerRule.fromJson(Map<String, dynamic> json) => EmployerRule(
        id: json['id']?.toString() ?? '',
        matchTerms: (json['matchTerms'] as List<dynamic>? ?? const [])
            .map((value) => value.toString())
            .toList(growable: false),
        annualCap: (json['annualCap'] as num?)?.round(),
        resetMonth: (json['resetMonth'] as num?)?.round(),
        deadlineMonth: (json['deadlineMonth'] as num?)?.round(),
        deadlineDay: (json['deadlineDay'] as num?)?.round(),
        sourceLabel:
            json['sourceLabel']?.toString() ?? 'Bundled generic guidance',
      );
}

class EmployerPlaybook {
  const EmployerPlaybook({
    required this.key,
    required this.name,
    required this.aliases,
    required this.status,
    required this.sourceUrl,
    required this.rules,
  });

  final String key;
  final String name;
  final List<String> aliases;
  final String status;
  final String sourceUrl;
  final List<EmployerRule> rules;

  factory EmployerPlaybook.fromJson(Map<String, dynamic> json) =>
      EmployerPlaybook(
        key: json['key']?.toString() ?? 'generic',
        name: json['name']?.toString() ?? 'Generic employer',
        aliases: (json['aliases'] as List<dynamic>? ?? const [])
            .map((value) => value.toString())
            .toList(growable: false),
        status: json['status']?.toString() ?? 'generic',
        sourceUrl: json['sourceUrl']?.toString() ?? '',
        rules: (json['rules'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(EmployerRule.fromJson)
            .toList(growable: false),
      );
}

class RecoveryState {
  const RecoveryState({
    this.schemaVersion = 1,
    this.datasetVersion = '',
    this.claimCases = const [],
    this.history = const [],
    this.benefits = const [],
    this.checklists = const [],
    this.playbook,
  });

  final int schemaVersion;
  final String datasetVersion;
  final List<ClaimCase> claimCases;
  final List<ReconciliationSnapshot> history;
  final List<BenefitLedgerEntry> benefits;
  final List<PaydayChecklist> checklists;
  final EmployerPlaybook? playbook;

  RecoveryState copyWith({
    String? datasetVersion,
    List<ClaimCase>? claimCases,
    List<ReconciliationSnapshot>? history,
    List<BenefitLedgerEntry>? benefits,
    List<PaydayChecklist>? checklists,
    EmployerPlaybook? playbook,
  }) {
    return RecoveryState(
      schemaVersion: schemaVersion,
      datasetVersion: datasetVersion ?? this.datasetVersion,
      claimCases: claimCases ?? this.claimCases,
      history: history ?? this.history,
      benefits: benefits ?? this.benefits,
      checklists: checklists ?? this.checklists,
      playbook: playbook ?? this.playbook,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'datasetVersion': datasetVersion,
        'claimCases': claimCases.map((value) => value.toJson()).toList(),
        'history': history.map((value) => value.toJson()).toList(),
        'benefits': benefits.map((value) => value.toJson()).toList(),
        'checklists': checklists.map((value) => value.toJson()).toList(),
      };

  factory RecoveryState.fromJson(Map<String, dynamic> json) => RecoveryState(
        schemaVersion: (json['schemaVersion'] as num?)?.round() ?? 1,
        datasetVersion: json['datasetVersion']?.toString() ?? '',
        claimCases: (json['claimCases'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ClaimCase.fromJson)
            .toList(growable: false),
        history: (json['history'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ReconciliationSnapshot.fromJson)
            .toList(growable: false),
        benefits: (json['benefits'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(BenefitLedgerEntry.fromJson)
            .toList(growable: false),
        checklists: (json['checklists'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(PaydayChecklist.fromJson)
            .toList(growable: false),
      );
}
