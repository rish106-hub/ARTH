import { categorizeTransactions } from '../spendCategorizer.js';

// Realistic messy Indian bank/UPI payees the on-device rules would leave as
// "other". Text is already redacted the way the client sends it. The last three
// are the cases that must come back `low` rather than confidently wrong — an
// unqualified ambiguous brand, a payment rail with no payee, and a generic name.
const items = [
  { id: '1', merchant: 'QUIKPAY SERVICES PVT LTD', sender: 'VM-HDFCBK', amountBand: '₹500-1k', text: 'to QUIKPAY SERVICES PVT LTD' },
  { id: '2', merchant: 'K RAMESH', sender: 'VM-HDFCBK', amountBand: '₹1k-5k', text: 'to K RAMESH via UPI' },
  { id: '3', merchant: 'URBAN CLAP HOME SERVICES', sender: 'VM-ICICIB', amountBand: '₹1k-5k', text: 'NACH debit URBAN CLAP HOME SERVICES' },
  { id: '4', merchant: 'CULTFIT HSR', sender: 'VM-AXISBK', amountBand: '₹1k-5k', text: 'to CULTFIT HSR' },
  { id: '5', merchant: 'INDIGO AIRLINES', sender: 'VM-HDFCBK', amountBand: '₹5k-20k', text: 'POS spend at INDIGO AIRLINES' },
  { id: '6', merchant: 'SMARTWORKS COWORKING', sender: 'VM-HDFCBK', amountBand: '₹20k+', text: 'to SMARTWORKS COWORKING' },
  { id: '7', merchant: 'APOLLO PHARMACY KORAMANGALA', sender: 'VM-HDFCBK', amountBand: '₹200-500', text: 'UPI to APOLLO PHARMACY KORAMANGALA' },
  { id: '8', merchant: 'VODAFONE IDEA POSTPAID', sender: 'VM-VIINDI', amountBand: '₹500-1k', text: 'to VODAFONE IDEA POSTPAID' },
  { id: '9', merchant: 'LICIOUS FRESH MEAT', sender: 'VM-HDFCBK', amountBand: '₹500-1k', text: 'to LICIOUS FRESH MEAT' },
  { id: '10', merchant: 'APOLLO', sender: 'VM-HDFCBK', amountBand: '₹5k-20k', text: 'paid to APOLLO' },
  { id: '11', merchant: 'PAYTM', sender: 'VM-PAYTM', amountBand: '₹200-500', text: 'paid via PAYTM' },
  { id: '12', merchant: 'LOCAL STORE', sender: 'VM-HDFCBK', amountBand: '₹200-500', text: 'debited at LOCAL STORE' },
];

async function main() {
  const startedAt = Date.now();
  const results = await categorizeTransactions(items);
  const elapsedMs = Date.now() - startedAt;
  if (results === null) {
    console.error(
      'categorizeTransactions returned null — OPENAI_API_KEY missing, the ' +
      'spend cap is exhausted, or the call failed.',
    );
    process.exit(1);
  }
  console.log(
    `categorized ${results.length}/${items.length} items in ${elapsedMs}ms ` +
    '(two votes, escalating the ones they disagreed on):\n',
  );
  const byId = new Map(items.map((item) => [item.id, item.merchant]));
  for (const result of results) {
    const applied = result.confidence === 'low' ? 'ASKS USER' : 'applied  ';
    console.log(
      `  ${applied} [${result.confidence.padEnd(6)}] ${result.category.padEnd(13)} | ` +
      `${result.merchant ?? '(no merchant)'}  <-  "${byId.get(result.id)}"`,
    );
  }
}

main();
