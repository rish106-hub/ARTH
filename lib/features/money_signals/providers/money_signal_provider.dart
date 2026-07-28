import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../engine/money_signal_engine.dart';
import '../../../models/money_signal_models.dart';
import '../../../providers/other_income_provider.dart';
import '../../../providers/paycheck_provider.dart';
import '../../../providers/spend_map_adjustments_provider.dart';
import '../../../providers/spend_map_provider.dart';
import '../../../providers/tax_result_provider.dart';
import '../../../providers/user_profile_provider.dart';

final incomeSignalProvider = Provider<IncomeSignal>((ref) {
  final map = ref.watch(spendMapProvider).map;
  final resolved = map?.incomeSignal;
  if (resolved != null) return resolved;

  final adjustments = ref.watch(spendMapAdjustmentsProvider);
  final paycheck = ref.watch(paycheckProvider);
  final profile = ref.watch(userProfileProvider);
  final otherIncome = ref.watch(otherIncomeProvider);
  final otherMonthly = otherIncome.fold<int>(
    0,
    (sum, source) => sum + source.monthlyAmount,
  );
  final confirmedPayslipNet =
      paycheck.grossReceived > 0 ? paycheck.netCredited : 0;
  final trustedSmsMonthly = map != null && map.incomeIsDetected
      ? map.observedPrimaryMonthlyIncome
      : 0;
  return MoneySignalEngine.resolveIncome(
    editedMonthlyIncome: adjustments.manualPrimaryMonthlyIncome,
    confirmedPayslipNet: confirmedPayslipNet,
    confirmedPayslipGross:
        confirmedPayslipNet <= 0 ? paycheck.grossReceived : 0,
    trustedSalarySmsMonthly: trustedSmsMonthly,
    annualCtc: profile.annualCTC,
    otherMonthlyIncome: otherMonthly,
  );
});

final paycheckTaxImpactProvider = Provider<PaycheckTaxImpact>((ref) {
  final paycheck = ref.watch(paycheckProvider);
  final hasConfirmedPayslip = paycheck.grossReceived > 0;
  final taxState = ref.watch(taxResultProvider);
  final taxResult = taxState.asData?.value;
  if (hasConfirmedPayslip && taxState.hasError) {
    return PaycheckTaxImpact(
      expectedMonthlyTds: 0,
      actualMonthlyTds: paycheck.taxWithheld,
      status: TdsPaceStatus.unavailable,
      regimeLabel: 'selected regime',
    );
  }
  if (hasConfirmedPayslip && taxResult == null) {
    return PaycheckTaxImpact(
      expectedMonthlyTds: 0,
      actualMonthlyTds: paycheck.taxWithheld,
      status: TdsPaceStatus.calculating,
      regimeLabel: 'selected regime',
    );
  }
  return MoneySignalEngine.taxImpact(
    actualMonthlyTds: paycheck.taxWithheld,
    expectedAnnualTax: taxResult?.currentTax.round() ?? 0,
    regimeLabel: taxResult?.betterRegimeLabel ?? 'selected regime',
    hasConfirmedPayslip: hasConfirmedPayslip,
  );
});

final paycheckTaxHintsProvider = Provider<List<PaycheckTaxHint>>((ref) {
  final paycheck = ref.watch(paycheckProvider);
  final profile = ref.watch(userProfileProvider);
  return MoneySignalEngine.taxHints(paycheck, profile);
});
