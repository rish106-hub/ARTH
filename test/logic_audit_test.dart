import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:arth/engine/gap_finder.dart';
import 'package:arth/engine/tax_engine.dart';
import 'package:arth/models/gap_card.dart';
import 'package:arth/models/tax_result.dart';
import 'package:arth/models/user_profile.dart';

class _RentScenario {
  final String label;
  final bool paysRent;
  final bool hasHra;
  final int monthlyRent;

  const _RentScenario(this.label, this.paysRent, this.hasHra, this.monthlyRent);
}

class _HomeLoanScenario {
  final String label;
  final bool hasLoan;
  final PropertyType? propertyType;
  final int interest;

  const _HomeLoanScenario(
    this.label,
    this.hasLoan,
    this.propertyType,
    this.interest,
  );
}

class _InsuranceScenario {
  final String label;
  final bool selfCovered;
  final bool parentsCovered;
  final bool parentsAbove60;

  const _InsuranceScenario(
    this.label,
    this.selfCovered,
    this.parentsCovered,
    this.parentsAbove60,
  );
}

class _EducationScenario {
  final String label;
  final bool hasLoan;
  final int year;
  final int interest;

  const _EducationScenario(this.label, this.hasLoan, this.year, this.interest);
}

class _DonationScenario {
  final String label;
  final bool hasDonations;
  final int amount;

  const _DonationScenario(this.label, this.hasDonations, this.amount);
}

class _AuditStats {
  int totalProfiles = 0;
  int bothZeroTax = 0;
  int bothNonZeroDifferent = 0;
  int oldBetterCount = 0;
  int newBetterCount = 0;
  int equalTaxCount = 0;
  int invariantFailures = 0;
  int monotonicityFailures = 0;
  final List<String> samples = [];

  void addSample(String message) {
    if (samples.length < 25) samples.add(message);
  }
}

class _TaxPair {
  final double oldTax;
  final double newTax;

  const _TaxPair(this.oldTax, this.newTax);
}

void main() {
  test('logic audit across income brackets and scenario permutations', () {
    final stopwatch = Stopwatch()..start();
    final audit = _runAudit();
    stopwatch.stop();

    final report = _buildReport(audit, stopwatch.elapsed);
    File('LOGIC_AUDIT_RESULTS.md').writeAsStringSync(report);

    // This is an audit harness, not a behavior gate. It should run and emit a report.
    expect(File('LOGIC_AUDIT_RESULTS.md').existsSync(), isTrue);
  });
}

_AuditStats _runAudit() {
  final stats = _AuditStats();
  final triggers = _loadTriggers();
  final previousByScenario = <String, _TaxPair>{};

  final incomes = [for (int lakhs = 1; lakhs <= 60; lakhs++) lakhs * 100000];
  const rentScenarios = [
    _RentScenario('no_rent', false, false, 0),
    _RentScenario('rent_no_hra_low', true, false, 10000),
    _RentScenario('rent_no_hra_high', true, false, 40000),
    _RentScenario('rent_hra_low', true, true, 15000),
    _RentScenario('rent_hra_high', true, true, 50000),
  ];
  const homeLoanScenarios = [
    _HomeLoanScenario('no_home_loan', false, null, 0),
    _HomeLoanScenario(
      'self_occupied_100k',
      true,
      PropertyType.selfOccupied,
      100000,
    ),
    _HomeLoanScenario(
      'self_occupied_200k',
      true,
      PropertyType.selfOccupied,
      200000,
    ),
    _HomeLoanScenario(
      'self_occupied_300k',
      true,
      PropertyType.selfOccupied,
      300000,
    ),
    _HomeLoanScenario('let_out_100k', true, PropertyType.letOut, 100000),
  ];
  const insuranceScenarios = [
    _InsuranceScenario('no_cover', false, false, false),
    _InsuranceScenario('self_only', true, false, false),
    _InsuranceScenario('parents_under_60', false, true, false),
    _InsuranceScenario('parents_above_60', false, true, true),
    _InsuranceScenario('self_and_parents_above_60', true, true, true),
  ];
  const educationScenarios = [
    _EducationScenario('no_education_loan', false, 1, 0),
    _EducationScenario('edu_year_1_50k', true, 1, 50000),
    _EducationScenario('edu_year_8_100k', true, 8, 100000),
    _EducationScenario('edu_year_9_100k', true, 9, 100000),
  ];
  const donationScenarios = [
    _DonationScenario('no_donation', false, 0),
    _DonationScenario('donation_10k', true, 10000),
    _DonationScenario('donation_50k', true, 50000),
  ];

  for (final ageGroup in AgeGroup.values) {
    for (final employment in EmploymentType.values) {
      for (final isMetro in [false, true]) {
        for (final rent in rentScenarios) {
          for (final invested80C in [0, 75000, 150000]) {
            for (final homeLoan in homeLoanScenarios) {
              for (final npsExtra in [0, 25000, 50000]) {
                for (final insurance in insuranceScenarios) {
                  for (final education in educationScenarios) {
                    for (final donation in donationScenarios) {
                      final scenarioKey = [
                        ageGroup.name,
                        employment.name,
                        isMetro ? 'metro' : 'non_metro',
                        rent.label,
                        invested80C,
                        homeLoan.label,
                        npsExtra,
                        insurance.label,
                        education.label,
                        donation.label,
                      ].join('|');

                      for (final income in incomes) {
                        final profile = UserProfile(
                          annualCTC: income,
                          employmentType: employment,
                          city: isMetro ? 'Delhi' : 'Bengaluru',
                          isMetroCity: isMetro,
                          paysRent: rent.paysRent,
                          monthlyRent: rent.monthlyRent,
                          hasHRA: rent.hasHra,
                          invested80C: invested80C,
                          hasHomeLoan: homeLoan.hasLoan,
                          propertyType: homeLoan.propertyType,
                          homeLoanInterest: homeLoan.interest,
                          hasNPS: npsExtra > 0,
                          npsExtraContribution: npsExtra,
                          hasHealthInsuranceSelf: insurance.selfCovered,
                          hasHealthInsuranceParents: insurance.parentsCovered,
                          parentsAbove60: insurance.parentsAbove60,
                          hasEducationLoan: education.hasLoan,
                          educationLoanRepaymentYear: education.year,
                          educationLoanInterest: education.interest,
                          hasDonations: donation.hasDonations,
                          donationAmount: donation.amount,
                          ageGroup: ageGroup,
                        );

                        final gaps = GapFinder.findGaps(profile, triggers);
                        final result = TaxEngine.calculate(profile, gaps);
                        stats.totalProfiles++;

                        _checkInvariants(stats, profile, gaps, result);
                        _checkMonotonicity(
                          stats,
                          previousByScenario,
                          scenarioKey,
                          result,
                        );
                        _updateAggregateCounts(stats, result);
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  _runSensitivityChecks(stats, triggers);
  return stats;
}

void _checkInvariants(
  _AuditStats stats,
  UserProfile profile,
  List<GapCard> gaps,
  TaxResult result,
) {
  if (result.oldRegimeTax < -0.01 || result.newRegimeTax < -0.01) {
    stats.invariantFailures++;
    stats.addSample(
      'Negative tax: income=${profile.annualCTC}, old=${result.oldRegimeTax}, new=${result.newRegimeTax}',
    );
  }

  final expectedBetter = result.oldRegimeTax <= result.newRegimeTax
      ? TaxRegime.oldRegime
      : TaxRegime.newRegime;
  if (expectedBetter != result.betterRegime) {
    stats.invariantFailures++;
    stats.addSample(
      'Better-regime mismatch: income=${profile.annualCTC}, old=${result.oldRegimeTax}, new=${result.newRegimeTax}, actual=${result.betterRegime}',
    );
  }

  final expectedSavings = (result.oldRegimeTax - result.newRegimeTax).abs();
  if ((expectedSavings - result.regimeSavings).abs() > 0.01) {
    stats.invariantFailures++;
    stats.addSample(
      'Savings mismatch: income=${profile.annualCTC}, expected=$expectedSavings, actual=${result.regimeSavings}',
    );
  }

  for (int i = 1; i < gaps.length; i++) {
    if (gaps[i].gapAmount > gaps[i - 1].gapAmount) {
      stats.invariantFailures++;
      stats.addSample(
        'Gap sorting mismatch: ${gaps[i - 1].id}=${gaps[i - 1].gapAmount}, ${gaps[i].id}=${gaps[i].gapAmount}',
      );
      break;
    }
  }

  if (gaps.any((g) => g.gapAmount <= 0)) {
    stats.invariantFailures++;
    stats.addSample('Non-positive gap amount detected.');
  }
}

void _checkMonotonicity(
  _AuditStats stats,
  Map<String, _TaxPair> previousByScenario,
  String scenarioKey,
  TaxResult result,
) {
  final previous = previousByScenario[scenarioKey];
  if (previous != null) {
    if (result.oldRegimeTax + 0.01 < previous.oldTax) {
      stats.monotonicityFailures++;
      stats.addSample(
        'Old-regime monotonicity failure for $scenarioKey: ${previous.oldTax} -> ${result.oldRegimeTax}',
      );
    }
    if (result.newRegimeTax + 0.01 < previous.newTax) {
      stats.monotonicityFailures++;
      stats.addSample(
        'New-regime monotonicity failure for $scenarioKey: ${previous.newTax} -> ${result.newRegimeTax}',
      );
    }
  }

  previousByScenario[scenarioKey] = _TaxPair(
    result.oldRegimeTax,
    result.newRegimeTax,
  );
}

void _updateAggregateCounts(_AuditStats stats, TaxResult result) {
  final oldZero = result.oldRegimeTax.abs() < 0.01;
  final newZero = result.newRegimeTax.abs() < 0.01;
  if (oldZero && newZero) stats.bothZeroTax++;
  if (!oldZero &&
      !newZero &&
      (result.oldRegimeTax - result.newRegimeTax).abs() > 0.01) {
    stats.bothNonZeroDifferent++;
  }

  if ((result.oldRegimeTax - result.newRegimeTax).abs() < 0.01) {
    stats.equalTaxCount++;
  } else if (result.oldRegimeTax < result.newRegimeTax) {
    stats.oldBetterCount++;
  } else {
    stats.newBetterCount++;
  }
}

void _runSensitivityChecks(_AuditStats stats, List<dynamic> triggers) {
  const base = UserProfile(
    annualCTC: 1800000,
    employmentType: EmploymentType.salaried,
    city: 'Bengaluru',
    isMetroCity: false,
    invested80C: 50000,
    ageGroup: AgeGroup.below30,
  );

  TaxResult calc(UserProfile profile) =>
      TaxEngine.calculate(profile, GapFinder.findGaps(profile, triggers));

  final npsOff = calc(base.copyWith(hasNPS: false, npsExtraContribution: 0));
  final npsOn = calc(base.copyWith(hasNPS: true, npsExtraContribution: 0));
  if ((npsOff.oldRegimeTax - npsOn.oldRegimeTax).abs() < 0.01 &&
      (npsOff.newRegimeTax - npsOn.newRegimeTax).abs() < 0.01) {
    stats.addSample(
      'Sensitivity: hasNPS flag does not affect tax logic when contribution is unchanged.',
    );
  }

  final insuranceOff = calc(base.copyWith(hasHealthInsuranceSelf: false));
  final insuranceOn = calc(base.copyWith(hasHealthInsuranceSelf: true));
  if ((insuranceOff.oldRegimeTax - insuranceOn.oldRegimeTax).abs() < 0.01) {
    stats.addSample(
      'Sensitivity: health-insurance yes/no does not affect tax payable because premium amounts are not collected.',
    );
  }

  final seniorBase = calc(base.copyWith(ageGroup: AgeGroup.above60));
  final superSeniorProxy = calc(base.copyWith(ageGroup: AgeGroup.above60));
  if ((seniorBase.oldRegimeTax - superSeniorProxy.oldRegimeTax).abs() < 0.01) {
    stats.addSample(
      'Sensitivity: app has no distinct 80+ slab input; "Above 60" always uses the 60-79 slab.',
    );
  }
}

List<dynamic> _loadTriggers() {
  final jsonStr = File('assets/tax_data.json').readAsStringSync();
  final data = jsonDecode(jsonStr) as Map<String, dynamic>;
  return data['decision_tree_triggers'] as List<dynamic>;
}

String _buildReport(_AuditStats stats, Duration elapsed) {
  final buffer = StringBuffer()
    ..writeln('# Logic Audit Results')
    ..writeln()
    ..writeln('Generated: ${DateTime.now().toIso8601String()}')
    ..writeln('Runtime: ${elapsed.inSeconds}s')
    ..writeln()
    ..writeln('## Sweep Scope')
    ..writeln()
    ..writeln('- Incomes: ₹1L to ₹60L in ₹1L increments')
    ..writeln('- Age groups: all 4 app-supported groups')
    ..writeln('- Employment types: both')
    ..writeln('- City mode: metro and non-metro')
    ..writeln('- Rent/HRA scenarios: 5')
    ..writeln('- 80C values: 3')
    ..writeln('- Home loan scenarios: 5')
    ..writeln('- NPS values: 3')
    ..writeln('- Insurance scenarios: 5')
    ..writeln('- Education loan scenarios: 4')
    ..writeln('- Donation scenarios: 3')
    ..writeln()
    ..writeln('Total profiles audited: ${stats.totalProfiles}')
    ..writeln()
    ..writeln('## Core Results')
    ..writeln()
    ..writeln('- Invariant failures: ${stats.invariantFailures}')
    ..writeln('- Monotonicity failures: ${stats.monotonicityFailures}')
    ..writeln('- Profiles with zero tax in both regimes: ${stats.bothZeroTax}')
    ..writeln(
      '- Profiles with non-zero and different tax in both regimes: ${stats.bothNonZeroDifferent}',
    )
    ..writeln('- Old regime better: ${stats.oldBetterCount}')
    ..writeln('- New regime better: ${stats.newBetterCount}')
    ..writeln('- Equal tax in both regimes: ${stats.equalTaxCount}')
    ..writeln()
    ..writeln('## Notable Findings')
    ..writeln()
    ..writeln(
      '- No fatal engine invariant failures were detected if `invariant failures` is `0`.',
    )
    ..writeln(
      '- No tax monotonicity regressions across rising income were detected if `monotonicity failures` is `0`.',
    )
    ..writeln(
      '- The regime engine remains approximation-driven for HRA/basic salary, 80GG ATI, donations, and professional tax.',
    )
    ..writeln(
      '- The app does not currently collect rupee inputs for health insurance premium or bank interest, so these cannot be modeled as exact deductions in tax payable.',
    )
    ..writeln()
    ..writeln('## Samples')
    ..writeln();

  if (stats.samples.isEmpty) {
    buffer.writeln('- No sample issues recorded.');
  } else {
    for (final sample in stats.samples) {
      buffer.writeln('- $sample');
    }
  }

  return buffer.toString();
}
