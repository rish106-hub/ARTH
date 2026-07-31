/// Real-shaped SMS sequences with the totals they must produce.
///
/// This is the regression net for the whole analyzer. Every parser change runs
/// against it, so a mistake shows up here as a changed number rather than as a
/// user who quietly stops trusting the app. Wording is copied from the shapes
/// major Indian issuers actually send — the abbreviations, the mangled merchant
/// names and the inconsistent placement of the reference are the point, not
/// noise to be tidied up.
///
/// Adding a case is cheap and always worth it. If a real inbox produces a wrong
/// figure, reproduce it here first, then fix the parser.
class SmsFixture {
  const SmsFixture({
    required this.name,
    required this.messages,
    required this.expectedSpend,
    required this.expectedSalary,
    this.expectedInternalLegs = 0,
    this.ownedTails = const {},
    this.note,
  });

  final String name;
  final List<({String sender, String body, DateTime date})> messages;

  /// Rupees the user actually parted with across the window.
  final int expectedSpend;

  /// Rupees of salary the window should report.
  final int expectedSalary;

  /// Legs kept as a record but counted as neither spend nor income.
  final int expectedInternalLegs;

  /// Account tails the user owns, for the fixtures that exercise correlation.
  final Set<String> ownedTails;

  /// Why this case exists, when that is not obvious from the name.
  final String? note;
}

({String sender, String body, DateTime date}) _sms(
  String sender,
  String body,
  DateTime date,
) =>
    (sender: sender, body: body, date: date);

final List<SmsFixture> smsFixtures = [
  SmsFixture(
    name: 'HDFC UPI spend',
    note: 'The dominant HDFC format. "Sent" with no "to" after it, which the '
        'old direction word list missed entirely.',
    messages: [
      _sms(
        'VM-HDFCBK',
        'Sent Rs.120.00 From HDFC Bank A/C x5678 To ZEPTO On 12/08/26 '
            'Ref 419203847362 Not You? Call 18002586161',
        DateTime(2026, 8, 12),
      ),
      _sms(
        'VM-HDFCBK',
        'Sent Rs.450.00 From HDFC Bank A/C x5678 To SWIGGY On 14/08/26 '
            'Ref 419203847999',
        DateTime(2026, 8, 14),
      ),
    ],
    expectedSpend: 570,
    expectedSalary: 0,
  ),
  SmsFixture(
    name: 'SBI UPI with no currency prefix',
    note: 'SBI writes the amount as a bare number. Without the verb-anchored '
        'pattern the whole message was discarded.',
    messages: [
      _sms(
        'AD-SBIINB',
        'Dear UPI user A/C X1234 debited by 250.0 on date 12Aug26 trf to '
            'SWIGGY Refno 419203847362',
        DateTime(2026, 8, 12),
      ),
    ],
    expectedSpend: 250,
    expectedSalary: 0,
  ),
  SmsFixture(
    name: 'salary credit and a month of spend',
    messages: [
      _sms(
        'VM-HDFCBK',
        'Rs.54,500.00 credited to a/c XX1234 on 01-08-26 towards SALARY. '
            'Avbl bal Rs 61,200.',
        DateTime(2026, 8, 1),
      ),
      _sms('VM-HDFCBK', 'Rs 499 debited from a/c XX1234 for UPI to SWIGGY.',
          DateTime(2026, 8, 3)),
      _sms('VM-ICICIB', 'Rs 1,299 spent on ICICI Card at AMAZON on 08-08.',
          DateTime(2026, 8, 8)),
      _sms('VM-BESCOM', 'Rs 1500 debited for BESCOM electricity bill.',
          DateTime(2026, 8, 12)),
    ],
    expectedSpend: 499 + 1299 + 1500,
    expectedSalary: 54500,
  ),
  SmsFixture(
    name: 'duplicate alert from bank and UPI app',
    note: 'One payment, two senders, same reference. Must count once.',
    messages: [
      _sms('VM-HDFCBK', 'Rs 499 debited to SWIGGY. Ref 419203847362',
          DateTime(2026, 8, 5)),
      _sms('VM-PAYTM', 'Rs 499 paid to Swiggy via UPI. Refno 419203847362',
          DateTime(2026, 8, 5)),
    ],
    expectedSpend: 499,
    expectedSalary: 0,
  ),
  SmsFixture(
    name: 'two same-amount payments on one day',
    note: 'Different payees, no reference. Both are real and must both count — '
        'the original dedup key collapsed them.',
    messages: [
      _sms('VM-HDFCBK', 'Rs 50 paid to CHAI POINT.', DateTime(2026, 8, 5, 9)),
      _sms('VM-HDFCBK', 'Rs 50 paid to TEA VILLA.', DateTime(2026, 8, 5, 18)),
    ],
    expectedSpend: 100,
    expectedSalary: 0,
  ),
  SmsFixture(
    name: 'card bill paid from another bank, three hops',
    note:
        'The case that recorded ₹50,000 of spend for a ₹25,000 bill. Only the '
        'purchase is spending.',
    ownedTails: {'1234', '9012', '4321'},
    messages: [
      _sms(
        'VM-ICICIC',
        'Rs 1299 spent on your ICICI Credit Card ending 4321 at AMAZON.',
        DateTime(2026, 8, 2),
      ),
      _sms(
        'VM-SBIINB',
        'Rs 25000 debited from A/c XX1234 and credited to XX9012 ICICI BANK '
            'via IMPS Ref 111222333444',
        DateTime(2026, 8, 20, 10),
      ),
      _sms(
        'VM-ICICIB',
        'Rs 25000 credited to your ICICI Bank Account XX9012 via IMPS '
            'Ref 111222333444',
        DateTime(2026, 8, 20, 10),
      ),
      _sms(
        'VM-ICICIB',
        'Rs 25000 debited from ICICI Bank Account XX9012 towards ICICI Credit '
            'Card XX4321 payment',
        DateTime(2026, 8, 20, 11),
      ),
    ],
    expectedSpend: 1299,
    expectedSalary: 0,
    expectedInternalLegs: 3,
  ),
  SmsFixture(
    name: 'self-transfer with no shared reference',
    note: 'Neither bank quotes a UTR. Correlation has to work from the account '
        'numbers, or this reads as spend on one side and income on the other.',
    ownedTails: {'1234', '9012'},
    messages: [
      _sms(
        'VM-SBIINB',
        'Rs 30000 debited from A/c XX1234 and credited to XX9012 ICICI BANK',
        DateTime(2026, 8, 10, 10),
      ),
      _sms(
        'VM-ICICIB',
        'Rs 30000 credited to your ICICI Bank Account XX9012 via IMPS',
        DateTime(2026, 8, 10, 11),
      ),
    ],
    expectedSpend: 0,
    expectedSalary: 0,
    expectedInternalLegs: 2,
  ),
  SmsFixture(
    name: 'monthly card bill must never read as salary',
    note: 'A same-size credit recurring across months is exactly what salary '
        'inference looks for. Paying a card bill must not inflate income.',
    ownedTails: {'1234', '9012'},
    messages: [
      for (final month in [6, 7, 8]) ...[
        _sms(
          'VM-SBIINB',
          'Rs 50000 debited from A/c XX1234 and credited to XX9012 ICICI BANK '
              'Ref 90000000000$month',
          DateTime(2026, month, 5),
        ),
        _sms(
          'VM-ICICIB',
          'Rs 50000 credited to your ICICI Bank Account XX9012 '
              'Ref 90000000000$month',
          DateTime(2026, month, 5),
        ),
      ],
    ],
    expectedSpend: 0,
    expectedSalary: 0,
    expectedInternalLegs: 6,
  ),
  SmsFixture(
    name: 'real income mentioning a card in passing',
    note: 'The phrase-matching rule booked this as a card repayment and wrote '
        'the income off as worth nothing.',
    messages: [
      _sms(
        'VM-HDFCBK',
        'Rs 5000 credited to your HDFC Bank A/c XX1234. Your HDFC Credit Card '
            'statement is generated.',
        DateTime(2026, 8, 6),
      ),
    ],
    // Internal-leg count of zero is the assertion that matters here: the old
    // rule marked this as a card repayment.
    expectedSpend: 0,
    expectedSalary: 0,
  ),
  SmsFixture(
    name: 'card that never itemises its purchases',
    note: 'Only a bill arrived. Excluding it would make the card contribute '
        'nothing at all.',
    messages: [
      _sms(
        'VM-ICICIC',
        'Payment of Rs 40000 received towards your ICICI Credit Card XX8888.',
        DateTime(2026, 8, 20),
      ),
    ],
    expectedSpend: 40000,
    expectedSalary: 0,
  ),
  SmsFixture(
    name: 'autopay and mandate debits are real spend',
    note: '"autopay" and "e-mandate" were skip words, which discarded genuine '
        'subscription and SIP debits.',
    messages: [
      _sms(
        'VM-HDFCBK',
        'Rs 649 debited from A/c XX1234 towards NETFLIX subscription via UPI '
            'Autopay on 12-Aug-26.',
        DateTime(2026, 8, 12),
      ),
      _sms(
        'VM-HDFCBK',
        'Rs 5000 debited via e-mandate for SIP in Axis Bluechip Fund.',
        DateTime(2026, 8, 15),
      ),
    ],
    expectedSpend: 5649,
    expectedSalary: 0,
  ),
  SmsFixture(
    name: 'noise is discarded',
    note: 'OTPs, future-dated notices and balance enquiries are not '
        'transactions.',
    messages: [
      _sms('VM-HDFCBK', '123456 is your OTP for Rs 5000 txn. Do not share.',
          DateTime(2026, 8, 2)),
      _sms('VM-HDFCBK', 'Rs 999 will be debited on 05-09 for autopay.',
          DateTime(2026, 8, 3)),
      _sms('VM-HDFCBK', 'Your balance is Rs 5000.', DateTime(2026, 8, 4)),
      _sms('VM-HDFCBK', 'Rs 300 debited to LOCAL STORE.', DateTime(2026, 8, 5)),
    ],
    expectedSpend: 300,
    expectedSalary: 0,
  ),
];
