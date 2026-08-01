import 'dart:convert';

import 'money_signal_models.dart';

/// Direction of a money movement parsed from an SMS/email.
enum TxnDirection { credit, debit }

/// Coarse spend categories inferred on-device from merchant/keyword hints.
/// Keep these stable — they are persisted and synced.
class SpendCategory {
  static const food = 'food';
  static const transport = 'transport';
  static const shopping = 'shopping';
  static const bills = 'bills';
  static const groceries = 'groceries';
  static const entertainment = 'entertainment';
  static const health = 'health';
  static const insurance = 'insurance';
  static const rent = 'rent';
  static const investment = 'investment';
  static const cash = 'cash';
  static const travel = 'travel';
  static const education = 'education';
  static const loan = 'loan';
  static const fees = 'fees';
  static const subscriptions = 'subscriptions';
  static const transfer = 'transfer';
  static const pets = 'pets';
  static const gifts = 'gifts';
  static const personalCare = 'personal_care';
  static const other = 'other';

  // Insurance sub-types
  static const insuranceCar = 'insurance:car';
  static const insuranceBike = 'insurance:bike';
  static const insuranceHealth = 'insurance:health';
  static const insuranceLife = 'insurance:life';
  static const insuranceOther = 'insurance:other';

  static const insuranceSubtypes = [
    insuranceCar,
    insuranceBike,
    insuranceHealth,
    insuranceLife,
    insuranceOther,
  ];

  static const all = [
    food,
    groceries,
    transport,
    travel,
    shopping,
    entertainment,
    subscriptions,
    bills,
    fees,
    health,
    insurance,
    rent,
    education,
    loan,
    investment,
    transfer,
    pets,
    gifts,
    personalCare,
    cash,
    other,
  ];

  /// Every value a transaction's category may legitimately hold, including the
  /// insurance sub-types. Use this — not [all] — to validate a category coming
  /// from the UI or from stored/synced JSON; [all] is the flat picker list and
  /// deliberately carries only the parent `insurance` entry.
  static const assignable = [...all, ...insuranceSubtypes];

  /// Categories that count as non-discretionary living costs. Used to seed the
  /// savings-goal "essentials" figure without pulling in discretionary spend
  /// (shopping, entertainment, dining out).
  static const essentials = [
    rent,
    bills,
    groceries,
    transport,
    health,
    insurance,
    // A loan EMI and school/college fees are contractually owed, not
    // discretionary — leaving them out understated the essentials floor.
    loan,
    education,
  ];

  /// "insurance:car" → "insurance". Anything without a sub-type is its own
  /// parent. A user category's parent is the bare `custom` marker, which is in
  /// no built-in list, so custom spend is discretionary by default.
  static String parentOf(String category) {
    final separator = category.indexOf(':');
    return separator < 0 ? category : category.substring(0, separator);
  }

  /// True when [category] is a non-discretionary living cost. Tests the parent,
  /// so a sub-typed category ("insurance:car") counts like plain `insurance` —
  /// a plain [essentials] membership check silently missed every sub-type.
  static bool isEssential(String category) =>
      essentials.contains(parentOf(category));

  /// Marks a category the user created, e.g. `custom:tax`. Built-in ids never
  /// carry this prefix, so the two can share one namespace safely.
  static const customPrefix = 'custom:';

  /// Keeps `custom:<slug>` inside the 40-character limit the backend accepts for
  /// a spend-by-category key.
  static const maxCustomSlugLength = 24;

  static bool isCustom(String category) => category.startsWith(customPrefix);

  /// Builds the stable id for a user-typed category name, or null when the text
  /// holds nothing usable. Returns the built-in id when the text names one, so
  /// typing "Rent" reuses the existing category instead of shadowing it.
  static String? idForUserText(String rawLabel) {
    final slug = _slugify(rawLabel);
    if (slug.isEmpty) return null;
    if (all.contains(slug)) return slug;
    for (final builtIn in all) {
      if (_slugify(label(builtIn)) == slug) return builtIn;
    }
    return '$customPrefix$slug';
  }

  static String _slugify(String raw) {
    final collapsed = raw
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (collapsed.length <= maxCustomSlugLength) return collapsed;
    return collapsed
        .substring(0, maxCustomSlugLength)
        .replaceAll(RegExp(r'_+$'), '');
  }

  static String label(String category) {
    switch (category) {
      case food:
        return 'Food & dining';
      case transport:
        return 'Transport';
      case shopping:
        return 'Shopping';
      case bills:
        return 'Bills & recharge';
      case groceries:
        return 'Groceries';
      case entertainment:
        return 'Entertainment';
      case health:
        return 'Health';
      case insurance:
        return 'Insurance';
      case insuranceCar:
        return 'Car insurance';
      case insuranceBike:
        return 'Bike insurance';
      case insuranceHealth:
        return 'Health insurance';
      case insuranceLife:
        return 'Life insurance';
      case insuranceOther:
        return 'Other insurance';
      case rent:
        return 'Rent';
      case investment:
        return 'Investments';
      case cash:
        return 'Cash / ATM';
      case travel:
        return 'Travel & stays';
      case education:
        return 'Education';
      case loan:
        return 'Loan & EMI';
      case fees:
        return 'Fees & charges';
      case subscriptions:
        return 'Subscriptions';
      case transfer:
        return 'Sent to people';
      case pets:
        return 'Pets';
      case gifts:
        return 'Gifts & donations';
      case personalCare:
        return 'Personal care';
      default:
        // A custom id carries its own readable name, so screens that know
        // nothing about the user's category list still render a real word
        // rather than a raw `custom:` id.
        if (isCustom(category)) {
          return _humanize(category.substring(customPrefix.length));
        }
        return 'Other';
    }
  }

  static String _humanize(String slug) {
    final words = slug.split('_').where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) return 'Other';
    final first = words.first;
    return [
      first[0].toUpperCase() + first.substring(1),
      ...words.skip(1),
    ].join(' ');
  }
}

/// A spend category the user added themselves, kept so it stays clickable for
/// every later transaction. [label] preserves the text as typed; [id] is the
/// stable value written onto transactions and synced.
class CustomSpendCategory {
  const CustomSpendCategory({required this.id, required this.label});

  /// Upper bound on how many a user can keep, so the synced payload and the
  /// category picker both stay manageable.
  static const maxPerUser = 24;

  final String id;
  final String label;

  Map<String, dynamic> toJson() => {'id': id, 'label': label};

  static CustomSpendCategory? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    if (!SpendCategory.isCustom(id)) return null;
    final label = json['label']?.toString().trim();
    return CustomSpendCategory(
      id: id,
      label: label == null || label.isEmpty ? SpendCategory.label(id) : label,
    );
  }
}

/// What kind of money instrument an endpoint is. The distinction carries real
/// meaning: a bank account holds a balance, a credit card is a liability, and
/// that alone decides whether money arriving at it is income or a repayment.
enum InstrumentKind {
  bankAccount,
  creditCard,
  wallet,
  unknown;

  static InstrumentKind fromName(String? name) => switch (name) {
        'bankAccount' => InstrumentKind.bankAccount,
        'creditCard' => InstrumentKind.creditCard,
        'wallet' => InstrumentKind.wallet,
        _ => InstrumentKind.unknown,
      };
}

/// One end of a money movement: which institution, which account, what kind.
///
/// [tail] is the masked last-4 the SMS already shows ("XX1234" -> "1234"). It
/// stays on the device — endpoints are never included in anything sent for AI
/// categorisation, because four digits of a real account number is not
/// something to hand to a third party for a category guess.
class TxnEndpoint {
  const TxnEndpoint({
    this.institution,
    this.tail,
    this.kind = InstrumentKind.unknown,
  });

  /// Institution code taken from the DLT sender header: "VM-HDFCBK" -> "HDFCBK".
  final String? institution;

  /// Last four digits of the account or card, when the message shows them.
  final String? tail;

  final InstrumentKind kind;

  /// Stable identity for matching one endpoint against another, and the key the
  /// account registry stores ownership under. Null when there is not enough to
  /// identify anything.
  String? get id {
    if (tail == null || tail!.isEmpty) return null;
    return '${institution ?? 'unknown'}:${kind.name}:$tail';
  }

  bool get isEmpty =>
      institution == null && tail == null && kind == InstrumentKind.unknown;

  Map<String, dynamic> toJson() => {
        if (institution != null) 'institution': institution,
        if (tail != null) 'tail': tail,
        'kind': kind.name,
      };

  static TxnEndpoint? fromJson(Object? json) {
    if (json is! Map) return null;
    final endpoint = TxnEndpoint(
      institution: json['institution']?.toString(),
      tail: json['tail']?.toString(),
      kind: InstrumentKind.fromName(json['kind']?.toString()),
    );
    return endpoint.isEmpty ? null : endpoint;
  }

  @override
  String toString() => id ?? 'TxnEndpoint(unidentified)';
}

/// A single money movement parsed from one message.
class FinanceTxn {
  const FinanceTxn({
    required this.amount,
    required this.direction,
    required this.date,
    required this.category,
    required this.isSalary,
    this.isInternalTransfer = false,
    this.source,
    this.counterparty,
    this.transferGroupId,
    this.isLowDetailCardBill = false,
    this.merchant,
    this.sender,
    this.smsId,
    this.refNo,
    this.bodyPreview,
    this.categorySource = CategorySource.rules,
  });

  final int amount; // rupees, positive
  final TxnDirection direction;
  final DateTime date;
  final String category;
  final bool isSalary;

  /// True when this leg only moves money between the user's own accounts, or
  /// repays their own credit card. Such a leg is real — the SMS happened — but
  /// it is neither spend nor income, and counting it as either inflates the
  /// figures. A single card bill paid via an intermediate bank produces three or
  /// four legs for one payment.
  final bool isInternalTransfer;

  /// The user's side of the movement — the account or card the message is about.
  final TxnEndpoint? source;

  /// The other side, when the message names one ("debited from A/c XX1234 and
  /// credited to XX9012"). Matching one leg's counterparty against another
  /// leg's source is what identifies a transfer between the user's own
  /// accounts even when the two banks quote no shared reference.
  final TxnEndpoint? counterparty;

  /// Shared by every leg of one movement, so the UI can show "you moved ₹25,000
  /// from SBI to your ICICI card" instead of three unexplained rows. Null for an
  /// ordinary transaction.
  final String? transferGroupId;

  /// True when this is a card bill counted as spend because the card never
  /// itemised its purchases. The amount is real; the breakdown is not available,
  /// and the UI should say so rather than implying a single ₹40,000 purchase.
  final bool isLowDetailCardBill;

  /// A debit that actually reduces net worth. Internal movement is excluded, so
  /// paying a card bill from another bank does not read as spending twice.
  bool get countsAsSpend =>
      direction == TxnDirection.debit && !isInternalTransfer;
  final String? merchant;
  final String? sender;

  /// Android SMS `_id` of the source message, kept so the UI can offer to open
  /// the exact original SMS. Null when parsed from a source without an id.
  final int? smsId;

  /// UPI/NEFT reference number from the message body, when present. The same
  /// payment alerted twice (bank header + UPI app header) carries the same
  /// reference, so this is the only reliable duplicate key; it also survives a
  /// re-scan, which the Android SMS `_id` does for the same message but a
  /// re-parsed list index does not.
  final String? refNo;

  /// Short excerpt of the original SMS body, retained so the user can identify
  /// a transaction in-app without leaving the screen. Truncated at parse time.
  final String? bodyPreview;

  /// How [category] was assigned — on-device rules, an AI fallback, or a manual
  /// user correction. Lets the UI show provenance and avoid re-sending
  /// user-corrected items to the AI.
  final CategorySource categorySource;

  FinanceTxn copyWith({
    String? category,
    bool? isSalary,
    bool? isInternalTransfer,
    TxnEndpoint? source,
    TxnEndpoint? counterparty,
    String? transferGroupId,
    bool? isLowDetailCardBill,
    String? merchant,
    CategorySource? categorySource,
  }) =>
      FinanceTxn(
        amount: amount,
        direction: direction,
        date: date,
        category: category ?? this.category,
        isSalary: isSalary ?? this.isSalary,
        isInternalTransfer: isInternalTransfer ?? this.isInternalTransfer,
        source: source ?? this.source,
        counterparty: counterparty ?? this.counterparty,
        transferGroupId: transferGroupId ?? this.transferGroupId,
        isLowDetailCardBill: isLowDetailCardBill ?? this.isLowDetailCardBill,
        merchant: merchant ?? this.merchant,
        sender: sender,
        smsId: smsId,
        refNo: refNo,
        bodyPreview: bodyPreview,
        categorySource: categorySource ?? this.categorySource,
      );

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'direction': direction.name,
        'date': date.toIso8601String(),
        'category': category,
        'isSalary': isSalary,
        if (isInternalTransfer) 'isInternalTransfer': true,
        if (source != null) 'source': source!.toJson(),
        if (counterparty != null) 'counterparty': counterparty!.toJson(),
        if (transferGroupId != null) 'transferGroupId': transferGroupId,
        if (isLowDetailCardBill) 'isLowDetailCardBill': true,
        if (merchant != null) 'merchant': merchant,
        if (sender != null) 'sender': sender,
        if (smsId != null) 'smsId': smsId,
        if (refNo != null) 'refNo': refNo,
        if (bodyPreview != null) 'bodyPreview': bodyPreview,
        'categorySource': categorySource.name,
      };

  factory FinanceTxn.fromJson(Map<String, dynamic> json) => FinanceTxn(
        amount: (json['amount'] as num?)?.round() ?? 0,
        direction: json['direction'] == 'credit'
            ? TxnDirection.credit
            : TxnDirection.debit,
        date: DateTime.tryParse(json['date']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        category: json['category']?.toString() ?? SpendCategory.other,
        isSalary: json['isSalary'] == true,
        isInternalTransfer: json['isInternalTransfer'] == true,
        source: TxnEndpoint.fromJson(json['source']),
        counterparty: TxnEndpoint.fromJson(json['counterparty']),
        transferGroupId: json['transferGroupId']?.toString(),
        isLowDetailCardBill: json['isLowDetailCardBill'] == true,
        merchant: json['merchant']?.toString(),
        sender: json['sender']?.toString(),
        smsId: (json['smsId'] as num?)?.toInt(),
        refNo: json['refNo']?.toString(),
        bodyPreview: json['bodyPreview']?.toString(),
        categorySource:
            CategorySource.fromName(json['categorySource']?.toString()),
      );
}

/// Provenance of a transaction's category.
enum CategorySource {
  rules,
  ai,
  manual;

  static CategorySource fromName(String? name) {
    switch (name) {
      case 'ai':
        return CategorySource.ai;
      case 'manual':
        return CategorySource.manual;
      default:
        return CategorySource.rules;
    }
  }
}

/// A balance a bank stated in an SMS, for one account, at one moment.
///
/// This is a statement of position, not a movement, and is deliberately kept
/// out of [FinanceTxn]: adding it as a transaction would double-count the
/// payment that the same message usually reports.
///
/// Stands in for an Account Aggregator feed. It is strictly weaker than one —
/// it only knows accounts that send balance SMS, and only as recently as the
/// last message — so it is presented as "as of" a time, never as live truth.
class AccountBalance {
  const AccountBalance({
    required this.endpointId,
    required this.tail,
    required this.amount,
    required this.observedAt,
    this.institution,
  });

  /// [TxnEndpoint.id] of the account, so a balance can be tied to the same
  /// account the transactions and the ownership registry use.
  final String endpointId;

  /// Masked tail as printed, kept for display: "XX1234".
  final String tail;

  /// Rupees. Balances are whole-rupee for display; paise are not useful here.
  final int amount;

  final DateTime observedAt;
  final String? institution;

  Map<String, dynamic> toJson() => {
        'endpointId': endpointId,
        'tail': tail,
        'amount': amount,
        'observedAt': observedAt.toIso8601String(),
        if (institution != null) 'institution': institution,
      };

  factory AccountBalance.fromJson(Map<String, dynamic> json) => AccountBalance(
        endpointId: json['endpointId']?.toString() ?? '',
        tail: json['tail']?.toString() ?? '',
        amount: (json['amount'] as num?)?.round() ?? 0,
        observedAt: DateTime.tryParse(json['observedAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        institution: json['institution']?.toString(),
      );
}

class MonthlySpendPoint {
  const MonthlySpendPoint({
    required this.month,
    required this.spent,
    required this.income,
  });

  final DateTime month;
  final int spent;
  final int income;
}

/// A category's latest-month spend compared with its prior-months average.
class CategoryTrend {
  const CategoryTrend({
    required this.category,
    required this.lastMonth,
    required this.priorAverage,
  });

  final String category;
  final int lastMonth;
  final int priorAverage;

  /// Signed change vs baseline (+0.3 = 30% higher than usual).
  double get changeRatio =>
      priorAverage <= 0 ? 0 : (lastMonth - priorAverage) / priorAverage;

  bool get isUp => lastMonth > priorAverage;

  /// Absolute rupee change, used to rank the biggest movers.
  int get changeMagnitude => (lastMonth - priorAverage).abs();
}

/// Aggregated spend/income picture built from parsed transactions.
/// Persisted locally and (best-effort) synced to the backend.
class SpendMap {
  const SpendMap({
    required this.txns,
    required this.windowStart,
    required this.windowEnd,
    required this.generatedAt,
    this.fallbackMonthlyIncome,
    this.otherMonthlyIncome = 0,
    this.manualPrimaryMonthlyIncome,
    this.manualMonthlySpend,
    this.trustedSalarySourceId,
    this.incomeSignal,
    this.balances = const [],
  });

  final List<FinanceTxn> txns;
  final DateTime windowStart;
  final DateTime windowEnd;
  final DateTime generatedAt;

  /// Take-home income (rupees/month) derived from a confirmed payslip / CTC,
  /// used only when no salary credit is detected in SMS. Transient — never
  /// persisted or synced (it is re-derived from live documents on read).
  final int? fallbackMonthlyIncome;

  /// Aggregate of user-entered "other income" sources (freelance, rent, side
  /// business, ...), see OtherIncomeNotifier. Transient — the individual
  /// sources/labels never leave the device; only this rupee total contributes
  /// to [monthlyIncome] so on-screen projections account for it.
  final int otherMonthlyIncome;

  /// User override for primary monthly income (salary). Local-only.
  final int? manualPrimaryMonthlyIncome;

  /// User override for average monthly spend. Local-only.
  final int? manualMonthlySpend;

  /// SMS sender selected by the user as the salary source to trust.
  /// Transient and local-only. Null keeps the legacy behavior of using every
  /// detected salary credit until the user makes a choice.
  final String? trustedSalarySourceId;

  /// Resolved income shared by Home, Spend map, Goal, and Tax. Transient and
  /// rebuilt from live sources whenever the map loads or those sources change.
  final IncomeSignal? incomeSignal;

  /// Latest balance each account stated in SMS, newest first.
  ///
  /// A weaker signal than an Account Aggregator feed and never presented as
  /// live truth: it only knows accounts that send balance SMS, and only as of
  /// the last one. Always shown with its observation time.
  final List<AccountBalance> balances;

  /// Returns a copy carrying [income] as the fallback monthly income.
  SpendMap withFallbackIncome(int? income) => SpendMap(
        txns: txns,
        windowStart: windowStart,
        windowEnd: windowEnd,
        generatedAt: generatedAt,
        fallbackMonthlyIncome: income,
        otherMonthlyIncome: otherMonthlyIncome,
        manualPrimaryMonthlyIncome: manualPrimaryMonthlyIncome,
        manualMonthlySpend: manualMonthlySpend,
        trustedSalarySourceId: trustedSalarySourceId,
        balances: balances,
        incomeSignal: null,
      );

  /// Returns a copy carrying [income] as the user-entered other-income total.
  SpendMap withOtherIncome(int income) => SpendMap(
        txns: txns,
        windowStart: windowStart,
        windowEnd: windowEnd,
        generatedAt: generatedAt,
        fallbackMonthlyIncome: fallbackMonthlyIncome,
        otherMonthlyIncome: income,
        manualPrimaryMonthlyIncome: manualPrimaryMonthlyIncome,
        manualMonthlySpend: manualMonthlySpend,
        trustedSalarySourceId: trustedSalarySourceId,
        balances: balances,
        incomeSignal: null,
      );

  SpendMap withAdjustments({
    int? manualPrimaryMonthlyIncome,
    int? manualMonthlySpend,
  }) =>
      SpendMap(
        txns: txns,
        windowStart: windowStart,
        windowEnd: windowEnd,
        generatedAt: generatedAt,
        fallbackMonthlyIncome: fallbackMonthlyIncome,
        otherMonthlyIncome: otherMonthlyIncome,
        manualPrimaryMonthlyIncome: manualPrimaryMonthlyIncome,
        manualMonthlySpend: manualMonthlySpend,
        trustedSalarySourceId: trustedSalarySourceId,
        balances: balances,
        incomeSignal: null,
      );

  SpendMap withTrustedSalarySource(String? sourceId) => SpendMap(
        txns: txns,
        windowStart: windowStart,
        windowEnd: windowEnd,
        generatedAt: generatedAt,
        fallbackMonthlyIncome: fallbackMonthlyIncome,
        otherMonthlyIncome: otherMonthlyIncome,
        manualPrimaryMonthlyIncome: manualPrimaryMonthlyIncome,
        manualMonthlySpend: manualMonthlySpend,
        trustedSalarySourceId: sourceId,
        balances: balances,
        incomeSignal: null,
      );

  SpendMap withIncomeSignal(IncomeSignal signal) => SpendMap(
        txns: txns,
        windowStart: windowStart,
        windowEnd: windowEnd,
        generatedAt: generatedAt,
        fallbackMonthlyIncome: fallbackMonthlyIncome,
        otherMonthlyIncome: otherMonthlyIncome,
        manualPrimaryMonthlyIncome: manualPrimaryMonthlyIncome,
        manualMonthlySpend: manualMonthlySpend,
        trustedSalarySourceId: trustedSalarySourceId,
        balances: balances,
        incomeSignal: signal,
      );

  static SpendMap empty(DateTime now) => SpendMap(
        txns: const [],
        windowStart: now,
        windowEnd: now,
        generatedAt: now,
      );

  bool get isEmpty => txns.isEmpty;

  /// Count of distinct calendar months (min 1) among the transactions matching
  /// [test]. This is the correct denominator for a monthly average: it reflects
  /// the months a given series actually has data for, instead of a fixed window
  /// or the raw first-to-last span (which over-counts empty months and mixes
  /// series that cover different months — see the income-vs-spend bug).
  int _distinctMonths(bool Function(FinanceTxn) test) {
    final months = <int>{};
    for (final t in txns) {
      if (test(t)) months.add(t.date.year * 12 + t.date.month);
    }
    return months.isEmpty ? 1 : months.length;
  }

  /// Distinct months that contain any transaction (for display only).
  int get observedMonths => _distinctMonths((_) => true);

  /// Distinct months containing a salary credit / any debit — each series is
  /// averaged over its own coverage so income and spend stay on the same
  /// per-month basis regardless of which months each happens to touch.
  int get _salaryMonths => _distinctMonths(isTrustedSalaryTransaction);
  int get _spendMonths => _distinctMonths((t) => t.countsAsSpend);

  int get totalSpent =>
      txns.where((t) => t.countsAsSpend).fold(0, (sum, t) => sum + t.amount);

  bool isTrustedSalaryTransaction(FinanceTxn txn) {
    if (txn.isInternalTransfer) return false;
    if (txn.direction != TxnDirection.credit || !txn.isSalary) return false;
    final trusted = trustedSalarySourceId;
    if (trusted == null || trusted.isEmpty) return true;
    return (txn.sender ?? '').trim().toUpperCase() == trusted;
  }

  List<FinanceTxn> get trustedSalaryTransactions =>
      txns.where(isTrustedSalaryTransaction).toList(growable: false);

  int get salaryCredited =>
      trustedSalaryTransactions.fold(0, (sum, t) => sum + t.amount);

  int get otherCredited => txns
      .where(
        (t) =>
            t.direction == TxnDirection.credit &&
            !t.isSalary &&
            !t.isInternalTransfer,
      )
      .fold(0, (sum, t) => sum + t.amount);

  Map<String, int> get spendByCategory {
    final map = <String, int>{};
    for (final t in txns.where((t) => t.countsAsSpend)) {
      map[t.category] = (map[t.category] ?? 0) + t.amount;
    }
    return map;
  }

  /// Categories sorted by amount, biggest first.
  List<MapEntry<String, int>> get topCategories {
    final entries = spendByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  List<MonthlySpendPoint> get monthlyTrend {
    final values = <String, MonthlySpendPoint>{};
    for (final txn in txns) {
      final month = DateTime(txn.date.year, txn.date.month);
      final key = '${month.year}-${month.month.toString().padLeft(2, '0')}';
      final current =
          values[key] ?? MonthlySpendPoint(month: month, spent: 0, income: 0);
      values[key] = MonthlySpendPoint(
        month: month,
        spent: current.spent + (txn.countsAsSpend ? txn.amount : 0),
        income:
            current.income + (isTrustedSalaryTransaction(txn) ? txn.amount : 0),
      );
    }
    final result = values.values.toList()
      ..sort((a, b) => a.month.compareTo(b.month));
    return result;
  }

  int get spendMonthsWithData => _spendMonths;
  int get salaryMonthsWithData => _salaryMonths;

  int get monthlySpend =>
      manualMonthlySpend ?? (totalSpent / _spendMonths).round();

  int get observedMonthlySpend => (totalSpent / _spendMonths).round();

  bool get spendIsManual =>
      manualMonthlySpend != null && manualMonthlySpend! > 0;

  /// Average monthly spend on non-discretionary categories only. Seeds the
  /// savings-goal "essentials" field without discretionary spend inflating it.
  int get monthlyEssentialSpend {
    final essentialTotal = txns
        .where((t) => t.countsAsSpend && SpendCategory.isEssential(t.category))
        .fold<int>(0, (sum, t) => sum + t.amount);
    return (essentialTotal / _spendMonths).round();
  }

  /// True when income comes from a salary credit detected in SMS (as opposed to
  /// the payslip/CTC fallback). Lets the UI label the figure honestly.
  bool get incomeIsDetected =>
      incomeSignal?.source == IncomeSignalSource.salarySms ||
      (incomeSignal == null && !primaryIncomeIsManual && salaryCredited > 0);

  int get observedPrimaryMonthlyIncome {
    if (salaryCredited > 0) return (salaryCredited / _salaryMonths).round();
    return fallbackMonthlyIncome ?? 0;
  }

  int get primaryMonthlyIncome =>
      incomeSignal?.primaryMonthlyIncome ??
      manualPrimaryMonthlyIncome ??
      observedPrimaryMonthlyIncome;

  bool get primaryIncomeIsManual =>
      incomeSignal?.source == IncomeSignalSource.edited ||
      (incomeSignal == null &&
          manualPrimaryMonthlyIncome != null &&
          manualPrimaryMonthlyIncome! > 0);

  String get primaryIncomeSourceLabel {
    if (incomeSignal != null) return incomeSignal!.source.label;
    if (primaryIncomeIsManual) return 'Your entered figure';
    if (salaryCredited > 0) return 'Salary SMS average';
    if (fallbackMonthlyIncome != null && fallbackMonthlyIncome! > 0) {
      return 'Payslip estimate';
    }
    return 'Not set';
  }

  /// Total monthly income used everywhere on screen: primary (SMS salary or
  /// payslip/CTC fallback) plus any user-entered other-income total.
  int get monthlyIncome =>
      incomeSignal?.monthlyIncome ?? primaryMonthlyIncome + otherMonthlyIncome;

  /// True when other-income has been added, so the UI can break the total
  /// down instead of presenting one opaque number.
  bool get hasOtherIncome => otherMonthlyIncome > 0;

  /// Signed monthly balance = income − spend. Positive means saving, negative
  /// means overspending. Unlike [realisticMonthlySavings] this is NOT floored,
  /// so the UI can honestly show a shortfall instead of collapsing it to zero.
  /// Returns 0 when income is unknown (nothing meaningful to compare against).
  int get monthlyNet {
    if (monthlyIncome <= 0) return 0;
    return monthlyIncome - monthlySpend;
  }

  /// True when observed spend exceeds income for the month.
  bool get isOverspending => monthlyIncome > 0 && monthlyNet < 0;

  /// Monthly shortfall (rupees) when overspending, else 0. The "waste" figure.
  int get monthlyWaste => isOverspending ? -monthlyNet : 0;

  /// True when income is a payslip/CTC estimate rather than a detected salary
  /// credit AND we also have SMS spend — i.e. the net mixes two sources and
  /// should be shown with a caveat.
  bool get netMixesSources =>
      !primaryIncomeIsManual && !incomeIsDetected && totalSpent > 0;

  /// What can realistically be saved each month = income − observed spend,
  /// floored at 0. When no salary detected, falls back to 0 (unknown).
  int get realisticMonthlySavings {
    if (monthlyIncome <= 0) return 0;
    final diff = monthlyIncome - monthlySpend;
    return diff < 0 ? 0 : diff;
  }

  double get savingsRate {
    if (monthlyIncome <= 0) return 0;
    return realisticMonthlySavings / monthlyIncome;
  }

  /// Same as [realisticMonthlySavings] but computed from [primaryMonthlyIncome]
  /// only. Used exclusively for the backend sync payload so that user-entered
  /// other income — local-only and never transmitted — cannot influence any
  /// number that reaches the server, even indirectly through a derived figure.
  int get realisticMonthlySavingsExcludingOtherIncome {
    if (primaryMonthlyIncome <= 0) return 0;
    final diff = primaryMonthlyIncome - monthlySpend;
    return diff < 0 ? 0 : diff;
  }

  /// Observed-income savings for server sync — ignores manual income/spend
  /// overrides and other-income totals.
  int get observedRealisticMonthlySavings {
    if (observedPrimaryMonthlyIncome <= 0) return 0;
    final diff = observedPrimaryMonthlyIncome - observedMonthlySpend;
    return diff < 0 ? 0 : diff;
  }

  // ---- Forecasting -------------------------------------------------------
  // Predictive figures derived from the SMS time-series. These stay meaningful
  // even when absolute capture is incomplete, because they compare the current
  // month's pace against the user's own recent history rather than to a fixed
  // "correct" total.

  int _monthKey(DateTime d) => d.year * 12 + d.month;

  /// Spend recorded so far in the reference (latest) month of the window.
  int get currentMonthSpend {
    final key = _monthKey(windowEnd);
    return txns
        .where((t) => t.countsAsSpend && _monthKey(t.date) == key)
        .fold(0, (sum, t) => sum + t.amount);
  }

  /// Projected total spend for the current month, extrapolating the run-rate so
  /// far to the full month (days elapsed → days in month). Falls back to the
  /// historical monthly average when the current month has no data yet.
  int get projectedMonthlySpend {
    final spentSoFar = currentMonthSpend;
    if (spentSoFar <= 0) return monthlySpend;
    final day = windowEnd.day;
    final daysInMonth = DateTime(windowEnd.year, windowEnd.month + 1, 0).day;
    if (day <= 0 || day >= daysInMonth) return spentSoFar;
    return (spentSoFar / day * daysInMonth).round();
  }

  /// Projected month-end spend vs the historical monthly average, as a signed
  /// ratio (+0.2 = on pace to spend 20% more than usual). 0 when no baseline.
  double get spendPaceVsAverage {
    final avg = monthlySpend;
    if (avg <= 0) return 0;
    return (projectedMonthlySpend - avg) / avg;
  }

  /// Monthly spend per category, oldest→newest, as a map of category → list of
  /// (monthKey, amount). Used to derive per-category trends.
  Map<String, Map<int, int>> get _monthlyByCategory {
    final out = <String, Map<int, int>>{};
    for (final t in txns.where((t) => t.countsAsSpend)) {
      final byMonth = out[t.category] ??= <int, int>{};
      final key = _monthKey(t.date);
      byMonth[key] = (byMonth[key] ?? 0) + t.amount;
    }
    return out;
  }

  /// Per-category trend: latest month's spend vs the average of prior months.
  /// Only categories with at least two months of data and a non-zero baseline
  /// are returned, sorted by the size of the change (biggest movers first).
  List<CategoryTrend> get categoryTrends {
    final trends = <CategoryTrend>[];
    _monthlyByCategory.forEach((category, byMonth) {
      if (byMonth.length < 2) return;
      final months = byMonth.keys.toList()..sort();
      final lastKey = months.last;
      final last = byMonth[lastKey]!;
      final priorKeys = months.sublist(0, months.length - 1);
      final priorAvg =
          priorKeys.fold<int>(0, (s, k) => s + byMonth[k]!) / priorKeys.length;
      if (priorAvg <= 0) return;
      trends.add(
        CategoryTrend(
          category: category,
          lastMonth: last,
          priorAverage: priorAvg.round(),
        ),
      );
    });
    trends.sort((a, b) => b.changeMagnitude.compareTo(a.changeMagnitude));
    return trends;
  }

  /// Returns a copy carrying the balances observed in this scan.
  SpendMap withBalances(List<AccountBalance> observed) => SpendMap(
        txns: txns,
        windowStart: windowStart,
        windowEnd: windowEnd,
        generatedAt: generatedAt,
        fallbackMonthlyIncome: fallbackMonthlyIncome,
        otherMonthlyIncome: otherMonthlyIncome,
        manualPrimaryMonthlyIncome: manualPrimaryMonthlyIncome,
        manualMonthlySpend: manualMonthlySpend,
        trustedSalarySourceId: trustedSalarySourceId,
        incomeSignal: incomeSignal,
        balances: observed,
      );

  Map<String, dynamic> toJson() => {
        'txns': txns.map((t) => t.toJson()).toList(),
        'windowStart': windowStart.toIso8601String(),
        'windowEnd': windowEnd.toIso8601String(),
        'generatedAt': generatedAt.toIso8601String(),
        'balances': balances.map((b) => b.toJson()).toList(),
      };

  factory SpendMap.fromJson(Map<String, dynamic> json) {
    final rawTxns = (json['txns'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(FinanceTxn.fromJson)
        .toList();
    final now = DateTime.now();
    return SpendMap(
      txns: rawTxns,
      windowStart:
          DateTime.tryParse(json['windowStart']?.toString() ?? '') ?? now,
      windowEnd: DateTime.tryParse(json['windowEnd']?.toString() ?? '') ?? now,
      generatedAt:
          DateTime.tryParse(json['generatedAt']?.toString() ?? '') ?? now,
      balances: (json['balances'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AccountBalance.fromJson)
          .toList(),
    );
  }

  String toJsonString() => jsonEncode(toJson());
  static SpendMap fromJsonString(String s) =>
      SpendMap.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
