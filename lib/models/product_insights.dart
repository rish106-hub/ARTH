import 'package:flutter/material.dart';

import '../models/tax_result.dart';
import '../models/user_profile.dart';
import '../widgets/animated_number.dart';

class NextBestAction {
  final IconData icon;
  final String title;
  final String body;
  final String cta;
  final String route;

  const NextBestAction({
    required this.icon,
    required this.title,
    required this.body,
    required this.cta,
    required this.route,
  });
}

NextBestAction buildNextBestAction({
  required bool diagnosticComplete,
  required int documentPercent,
  TaxResult? result,
}) {
  if (!diagnosticComplete) {
    return const NextBestAction(
      icon: Icons.play_arrow_rounded,
      title: 'Run your 3-minute diagnostic',
      body: 'Get regime insight, deduction gaps, and a clean readiness plan.',
      cta: 'Start diagnostic',
      route: '/questions',
    );
  }
  if (result != null && result.assumptions.isNotEmpty) {
    return NextBestAction(
      icon: Icons.tune_rounded,
      title: 'Improve calculation accuracy',
      body: result.assumptions.first.detail,
      cta: 'Open accuracy coach',
      route: '/accuracy-coach',
    );
  }
  if (documentPercent < 60) {
    return const NextBestAction(
      icon: Icons.folder_special_outlined,
      title: 'Build proof readiness',
      body: 'Mark Form 16, rent, 80C, 80D, loan, and AIS proofs before filing.',
      cta: 'Open documents',
      route: '/documents',
    );
  }
  if (result != null && result.gaps.isNotEmpty) {
    return NextBestAction(
      icon: Icons.savings_outlined,
      title: result.gaps.first.title,
      body:
          'Highest visible deduction opportunity: ${formatRupeesCompact(result.gaps.first.gapAmount)}.',
      cta: 'Open actions',
      route: '/action-plan',
    );
  }
  return const NextBestAction(
    icon: Icons.assignment_outlined,
    title: 'Review your Tax Story',
    body:
        'You have a clean summary for CA, employer portal, or official filing.',
    cta: 'Open story',
    route: '/tax-story',
  );
}

class AccuracyTask {
  final String code;
  final IconData icon;
  final String title;
  final String body;
  final String fieldLabel;
  final String suffix;
  final int? currentValue;
  final int min;
  final int max;
  final UserProfile Function(UserProfile profile, int value) apply;

  const AccuracyTask({
    required this.code,
    required this.icon,
    required this.title,
    required this.body,
    required this.fieldLabel,
    this.suffix = '₹',
    required this.currentValue,
    required this.min,
    required this.max,
    required this.apply,
  });
}

List<AccuracyTask> buildAccuracyTasks(UserProfile profile) {
  final tasks = <AccuracyTask>[];
  if (profile.employmentType == EmploymentType.salaried &&
      profile.actualBasicSalary == null) {
    tasks.add(
      AccuracyTask(
        code: 'basic_salary',
        icon: Icons.payments_outlined,
        title: 'Add actual basic salary',
        body: 'Improves HRA and employer NPS accuracy.',
        fieldLabel: 'Annual basic salary',
        currentValue: profile.actualBasicSalary,
        min: 0,
        max: profile.annualCTC,
        apply: (p, value) => p.copyWith(actualBasicSalary: value),
      ),
    );
  }
  if (profile.paysRent && profile.hasHRA && profile.actualHraReceived == null) {
    tasks.add(
      AccuracyTask(
        code: 'hra_received',
        icon: Icons.home_work_outlined,
        title: 'Add actual HRA received',
        body: 'Replaces HRA estimate with your salary-slip value.',
        fieldLabel: 'Annual HRA received',
        currentValue: profile.actualHraReceived,
        min: 0,
        max: profile.annualCTC,
        apply: (p, value) => p.copyWith(actualHraReceived: value),
      ),
    );
  }
  if (profile.employmentType == EmploymentType.salaried &&
      profile.actualProfessionalTax == null) {
    tasks.add(
      AccuracyTask(
        code: 'professional_tax',
        icon: Icons.receipt_long_outlined,
        title: 'Add professional tax',
        body: 'Uses exact payslip deduction instead of a placeholder.',
        fieldLabel: 'Annual professional tax',
        currentValue: profile.actualProfessionalTax,
        min: 0,
        max: 2500,
        apply: (p, value) => p.copyWith(actualProfessionalTax: value),
      ),
    );
  }
  if (profile.hasHealthInsuranceSelf &&
      profile.healthInsuranceSelfPremium == null) {
    tasks.add(
      AccuracyTask(
        code: '80d_self',
        icon: Icons.health_and_safety_outlined,
        title: 'Add self/family 80D premium',
        body:
            'Lets ARTH model health-insurance deduction instead of guidance only.',
        fieldLabel: 'Self/family premium',
        currentValue: profile.healthInsuranceSelfPremium,
        min: 0,
        max: 100000,
        apply: (p, value) => p.copyWith(healthInsuranceSelfPremium: value),
      ),
    );
  }
  if (profile.hasHealthInsuranceParents &&
      profile.healthInsuranceParentsPremium == null) {
    tasks.add(
      AccuracyTask(
        code: '80d_parents',
        icon: Icons.elderly_outlined,
        title: 'Add parents 80D premium',
        body: 'Improves old-regime comparison for parent insurance.',
        fieldLabel: 'Parents premium',
        currentValue: profile.healthInsuranceParentsPremium,
        min: 0,
        max: 100000,
        apply: (p, value) => p.copyWith(healthInsuranceParentsPremium: value),
      ),
    );
  }
  if (profile.savingsInterest == null) {
    tasks.add(
      AccuracyTask(
        code: 'savings_interest',
        icon: Icons.account_balance_wallet_outlined,
        title: 'Add savings interest',
        body: 'Models interest income and 80TTA or 80TTB correctly.',
        fieldLabel: 'Savings interest',
        currentValue: profile.savingsInterest,
        min: 0,
        max: 1000000,
        apply: (p, value) => p.copyWith(savingsInterest: value),
      ),
    );
  }
  if (profile.fdInterest == null) {
    tasks.add(
      AccuracyTask(
        code: 'fd_interest',
        icon: Icons.savings_outlined,
        title: 'Add FD interest',
        body: 'Prevents undercounting taxable interest income.',
        fieldLabel: 'FD interest',
        currentValue: profile.fdInterest,
        min: 0,
        max: 5000000,
        apply: (p, value) => p.copyWith(fdInterest: value),
      ),
    );
  }
  if (profile.employmentType == EmploymentType.salaried &&
      profile.employerNpsContribution == null) {
    tasks.add(
      AccuracyTask(
        code: 'employer_nps',
        icon: Icons.business_center_outlined,
        title: 'Add employer NPS',
        body: 'Models 80CCD(2) only when your employer contributes.',
        fieldLabel: 'Employer NPS',
        currentValue: profile.employerNpsContribution,
        min: 0,
        max: 1000000,
        apply: (p, value) => p.copyWith(employerNpsContribution: value),
      ),
    );
  }
  if (profile.hasDonations && profile.donationDeductionRatePercent == null) {
    tasks.add(
      AccuracyTask(
        code: 'donation_rate',
        icon: Icons.volunteer_activism_outlined,
        title: 'Confirm donation eligibility',
        body: 'Choose 50% or 100% deduction rate from the receipt category.',
        fieldLabel: 'Deduction rate',
        suffix: '%',
        currentValue: profile.donationDeductionRatePercent,
        min: 0,
        max: 100,
        apply: (p, value) => p.copyWith(donationDeductionRatePercent: value),
      ),
    );
  }
  return tasks;
}

class TaxCalendarItem {
  final IconData icon;
  final String title;
  final String date;
  final String body;
  final String route;
  final String cta;

  const TaxCalendarItem({
    required this.icon,
    required this.title,
    required this.date,
    required this.body,
    required this.route,
    required this.cta,
  });
}

List<TaxCalendarItem> taxCalendarItems(String fyLabel) => [
      const TaxCalendarItem(
        icon: Icons.folder_copy_outlined,
        title: 'Proof collection',
        date: 'Apr-Mar',
        body:
            'Collect Form 16, rent, insurance, loan, 80C, and donation proofs.',
        route: '/documents',
        cta: 'Open documents',
      ),
      const TaxCalendarItem(
        icon: Icons.account_balance_outlined,
        title: 'AIS / 26AS review',
        date: 'Before filing',
        body: 'Check official credits and reported income before submission.',
        route: '/ais-guide',
        cta: 'Read guide',
      ),
      TaxCalendarItem(
        icon: Icons.tune_rounded,
        title: 'Accuracy pass',
        date: fyLabel,
        body:
            'Replace assumptions with exact salary, HRA, premium, and interest values.',
        route: '/accuracy-coach',
        cta: 'Improve accuracy',
      ),
      const TaxCalendarItem(
        icon: Icons.inventory_2_outlined,
        title: 'Filing handoff',
        date: 'Due date season',
        body: 'Prepare CA-ready notes without claiming ARTH files ITR.',
        route: '/filing-assistant',
        cta: 'Open pack',
      ),
    ];
