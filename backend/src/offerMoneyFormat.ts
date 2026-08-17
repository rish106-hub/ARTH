/// Money formatting shared by the offer questions and the offer advice, so both
/// quote the same figure the same way. No imports, so it stays usable from any
/// layer.

/// Indian-format money, because "₹18.5L" is how the offers themselves read and
/// "1850000" is not. Falls back to a grouped figure with the currency code when
/// the letters are not in rupees, rather than mislabelling a foreign amount.
export function formatOfferMoney(amount: number, currency: string): string {
  const normalized = currency.trim().toUpperCase();
  if (normalized !== 'INR' && normalized !== '₹') {
    return `${normalized} ${amount.toLocaleString('en-US')}`;
  }
  if (amount >= 10_000_000) {
    return `₹${trimZero(amount / 10_000_000)}Cr`;
  }
  if (amount >= 100_000) {
    return `₹${trimZero(amount / 100_000)}L`;
  }
  return `₹${amount.toLocaleString('en-IN')}`;
}

export function formatBasisPointsAsPercent(basisPoints: number): string {
  return `${trimZero(basisPoints / 100)}%`;
}

function trimZero(value: number): string {
  return value.toFixed(1).replace(/\.0$/, '');
}
