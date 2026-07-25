import { categorizeTransactions } from '../spendCategorizer.js';

// Realistic messy Indian bank/UPI SMS the on-device rules would leave as
// "other" (unknown merchant, no keyword match). Text is already redacted like
// the client would send it.
const items = [
  { id: '1', text: 'to QUIKPAY SERVICES PVT LTD' },
  { id: '2', text: 'to K RAMESH via UPI' },
  { id: '3', text: 'NACH debit URBAN CLAP HOME SERVICES' },
  { id: '4', text: 'to CULTFIT HSR' },
  { id: '5', text: 'POS spend at INDIGO AIRLINES' },
  { id: '6', text: 'to SMARTWORKS COWORKING' },
  { id: '7', text: 'UPI to APOLLO PHARMACY KORAMANGALA' },
  { id: '8', text: 'to VODAFONE IDEA POSTPAID' },
  { id: '9', text: 'to LICIOUS FRESH MEAT' },
  { id: '10', text: 'to a random person xyz9382' },
];

async function main() {
  const t0 = Date.now();
  const res = await categorizeTransactions(items);
  const ms = Date.now() - t0;
  if (res === null) {
    console.error('categorizeTransactions returned null — GEMINI_API_KEY missing or call failed.');
    process.exit(1);
  }
  console.log(`Gemini categorized ${res.length}/${items.length} items in ${ms}ms:\n`);
  const byId = new Map(items.map((i) => [i.id, i.text]));
  for (const r of res) {
    console.log(
      `  [${r.confidence.padEnd(6)}] ${r.category.padEnd(13)} | ${r.merchant ?? '(no merchant)'}  <-  "${byId.get(r.id)}"`,
    );
  }
}

main();
