import { db, type Queryable } from './db.js';
import { env } from './config.js';

/// Per-million-token list prices in micro-dollars (1 USD = 1_000_000 µUSD).
/// Integers only — the cap comparison must be exact, and money never touches a
/// float. Source: OpenAI pricing, standard tier.
type ModelPrice = {
  inputPerMillion: number;
  cachedInputPerMillion: number;
  outputPerMillion: number;
};

const MODEL_PRICES: Record<string, ModelPrice> = {
  'gpt-5.4-nano': {
    inputPerMillion: 200_000,
    cachedInputPerMillion: 20_000,
    outputPerMillion: 1_250_000,
  },
  'gpt-5.4-mini': {
    inputPerMillion: 750_000,
    cachedInputPerMillion: 75_000,
    outputPerMillion: 4_500_000,
  },
  'gpt-5.4': {
    inputPerMillion: 2_500_000,
    cachedInputPerMillion: 250_000,
    outputPerMillion: 15_000_000,
  },
  'gpt-5.5': {
    inputPerMillion: 5_000_000,
    cachedInputPerMillion: 500_000,
    outputPerMillion: 30_000_000,
  },
  'gpt-5.4-pro': {
    inputPerMillion: 30_000_000,
    cachedInputPerMillion: 30_000_000,
    outputPerMillion: 180_000_000,
  },
  'gpt-5.5-pro': {
    inputPerMillion: 30_000_000,
    cachedInputPerMillion: 30_000_000,
    outputPerMillion: 180_000_000,
  },
  'gpt-5-nano': {
    inputPerMillion: 50_000,
    cachedInputPerMillion: 5_000,
    outputPerMillion: 400_000,
  },
  'gpt-5-mini': {
    inputPerMillion: 250_000,
    cachedInputPerMillion: 25_000,
    outputPerMillion: 2_000_000,
  },
  'gpt-5': {
    inputPerMillion: 1_250_000,
    cachedInputPerMillion: 125_000,
    outputPerMillion: 10_000_000,
  },
};

/// Price used for a model we have no entry for. Deliberately the most expensive
/// rate we know: an unpriced model must never be able to slip under the cap by
/// being assumed cheap. Switching OPENAI_MODEL to something unlisted therefore
/// throttles hard rather than overspending — add the model here to fix that.
const FALLBACK_PRICE: ModelPrice = MODEL_PRICES['gpt-5.5-pro'];

export function priceForModel(model: string): ModelPrice {
  return MODEL_PRICES[model] ?? FALLBACK_PRICE;
}

export type TokenUsage = {
  inputTokens: number;
  cachedInputTokens: number;
  outputTokens: number;
};

/// Cost of [usage] on [model], in micro-dollars, rounded UP. Rounding up means
/// a long run of tiny calls can only ever over-count against the cap, never
/// under-count it.
export function costMicroUsd(model: string, usage: TokenUsage): number {
  const price = priceForModel(model);
  // Cached input is billed at the cached rate; the uncached remainder at full.
  const cached = Math.max(0, Math.min(usage.cachedInputTokens, usage.inputTokens));
  const uncached = Math.max(0, usage.inputTokens - cached);
  const micro =
    (uncached * price.inputPerMillion) / 1_000_000 +
    (cached * price.cachedInputPerMillion) / 1_000_000 +
    (Math.max(0, usage.outputTokens) * price.outputPerMillion) / 1_000_000;
  return Math.ceil(micro);
}

/// Worst case a single call could cost before it is made: every input token
/// billed uncached, and the full output allowance spent. Checked against the
/// remaining budget so a call is only started when its most expensive possible
/// outcome still fits.
export function worstCaseMicroUsd(
  model: string,
  estimatedInputTokens: number,
  maxOutputTokens: number,
): number {
  return costMicroUsd(model, {
    inputTokens: estimatedInputTokens,
    cachedInputTokens: 0,
    outputTokens: maxOutputTokens,
  });
}

export const capMicroUsd = () => Math.round(env.AI_SPEND_CAP_USD * 1_000_000);

export type SpendSnapshot = {
  spentMicroUsd: number;
  remainingMicroUsd: number;
  userItemsToday: number;
};

/// Reads global spend and this user's recent item count in one round trip.
/// The global SUM is why this table carries no row-level isolation policy — a
/// per-user view of it would turn one shared cap into a cap each.
export async function readSpend(
  userId: string | null,
  handle: Queryable = db,
): Promise<SpendSnapshot> {
  const result = await handle.query(
    `select
       coalesce((select sum(micro_usd) from ai_spend_ledger), 0) as spent,
       coalesce((
         select sum(items) from ai_spend_ledger
         where user_id = $1 and created_at > now() - interval '1 day'
       ), 0) as user_items`,
    [userId],
  );
  const row = result.rows[0] ?? {};
  const spent = Number(row.spent ?? 0);
  const userItems = Number(row.user_items ?? 0);
  const cap = capMicroUsd();
  return {
    spentMicroUsd: spent,
    remainingMicroUsd: Math.max(0, cap - spent),
    userItemsToday: userItems,
  };
}

export async function recordSpend(
  entry: {
    userId: string | null;
    model: string;
    usage: TokenUsage;
    items: number;
  },
  handle: Queryable = db,
): Promise<void> {
  await handle.query(
    `insert into ai_spend_ledger (
       user_id, model, input_tokens, cached_input_tokens, output_tokens,
       micro_usd, items
     ) values ($1, $2, $3, $4, $5, $6, $7)`,
    [
      entry.userId,
      entry.model,
      Math.max(0, Math.round(entry.usage.inputTokens)),
      Math.max(0, Math.round(entry.usage.cachedInputTokens)),
      Math.max(0, Math.round(entry.usage.outputTokens)),
      costMicroUsd(entry.model, entry.usage),
      Math.max(0, Math.round(entry.items)),
    ],
  );
}

export type BudgetDenial =
  | { allowed: true; snapshot: SpendSnapshot }
  | { allowed: false; reason: 'cap_reached' | 'user_quota'; snapshot: SpendSnapshot };

/// Whether a call costing at most [worstCase] µUSD may proceed for [userId].
/// Two independent limits: the global lifetime cap, and a per-user daily item
/// quota so one account with a decade of SMS cannot drain the shared budget.
export function evaluateBudget(
  snapshot: SpendSnapshot,
  worstCase: number,
  items: number,
): BudgetDenial {
  if (snapshot.remainingMicroUsd < worstCase) {
    return { allowed: false, reason: 'cap_reached', snapshot };
  }
  if (snapshot.userItemsToday + items > env.AI_ITEMS_PER_USER_PER_DAY) {
    return { allowed: false, reason: 'user_quota', snapshot };
  }
  return { allowed: true, snapshot };
}
