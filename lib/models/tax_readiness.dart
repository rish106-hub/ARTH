class TaxDocumentItem {
  final String id;
  final String title;
  final String subtitle;
  final String whyItMatters;

  const TaxDocumentItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.whyItMatters,
  });
}

const taxDocumentItems = [
  TaxDocumentItem(
    id: 'form16',
    title: 'Form 16',
    subtitle: 'Salary, TDS, exemptions, and employer deduction summary.',
    whyItMatters: 'This becomes the base document for most salaried returns.',
  ),
  TaxDocumentItem(
    id: 'rentReceipts',
    title: 'Rent receipts',
    subtitle: 'Monthly rent proof, landlord details, and rent agreement.',
    whyItMatters: 'Useful for HRA and rent-related deduction checks.',
  ),
  TaxDocumentItem(
    id: 'investment80c',
    title: '80C proofs',
    subtitle:
        'ELSS, PPF, EPF, life insurance, tuition fee, or home loan principal.',
    whyItMatters: 'Helps close the most common deduction gap.',
  ),
  TaxDocumentItem(
    id: 'healthInsurance80d',
    title: '80D insurance',
    subtitle: 'Health insurance premium receipts for self, family, or parents.',
    whyItMatters: 'Often missed when parents are covered separately.',
  ),
  TaxDocumentItem(
    id: 'homeLoanCertificate',
    title: 'Home loan certificate',
    subtitle: 'Annual interest and principal certificate from lender.',
    whyItMatters: 'Supports Section 24(b) and principal deduction checks.',
  ),
  TaxDocumentItem(
    id: 'educationLoanInterest',
    title: 'Education loan interest',
    subtitle: 'Interest certificate from bank or lender.',
    whyItMatters: 'Section 80E has no upper cap during eligible years.',
  ),
  TaxDocumentItem(
    id: 'donationReceipts',
    title: 'Donation receipts',
    subtitle: '80G receipts with trust details and eligible amount.',
    whyItMatters: 'Small receipts can become easy missed savings.',
  ),
  TaxDocumentItem(
    id: 'ais26asReview',
    title: 'AIS / 26AS review',
    subtitle: 'TDS, interest, dividends, tax payments, and mismatch check.',
    whyItMatters: 'Mismatch detection before filing lowers notice risk.',
  ),
];

int completedDocumentCount(Map<String, bool> state) =>
    taxDocumentItems.where((item) => state[item.id] ?? false).length;

int documentReadinessPercent(Map<String, bool> state) {
  if (taxDocumentItems.isEmpty) return 0;
  return ((completedDocumentCount(state) / taxDocumentItems.length) * 100)
      .round();
}
