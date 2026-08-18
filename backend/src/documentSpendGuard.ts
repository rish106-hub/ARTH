import {
  evaluateBudget,
  recordSpend,
  tryReadSpend,
  worstCaseMicroUsd,
} from './aiSpendLedger.js';
import type { GeminiUsage, SpendGuard } from './geminiStructuredCall.js';

/// The production spend guard for document interpretation: the AI spend ledger,
/// adapted to the interface the Gemini client asks for.
///
/// Kept separate from the client itself so that `geminiInterpreter.ts` needs no
/// database and no environment config, and so that a test can hand the parser a
/// stub instead of a Postgres connection.
///
/// A call is approved only when even its most expensive possible outcome stays
/// inside the cap — every input token billed uncached, and the whole output
/// allowance spent. Each document counts as one item against the per-user daily
/// quota.
export function ledgerSpendGuard(userId: string | null): SpendGuard {
  return {
    async allows(model, inputTokens, outputTokens) {
      const snapshot = await tryReadSpend(userId);
      // An unreadable ledger is no proof the call stays inside the cap, so it
      // has to count as a refusal. Failing closed is the only safe reading.
      if (!snapshot) return false;
      const budget = evaluateBudget(
        snapshot,
        worstCaseMicroUsd(model, inputTokens, outputTokens),
        1,
      );
      if (!budget.allowed) {
        console.warn(`[ai-spend] document interpretation refused: ${budget.reason}`);
        return false;
      }
      return true;
    },
    async record(model: string, usage: GeminiUsage) {
      await recordSpend({ userId, model, usage, items: 1 });
    },
  };
}
