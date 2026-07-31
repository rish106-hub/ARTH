import { db, type Queryable } from './db.js';
import { blindIndex } from './envelopeEncryption.js';
import { SPEND_CATEGORIES, type Confidence, type SpendCategory } from './spendCategorizer.js';

/// Namespace for the keyed digest, so a merchant hash can never collide with a
/// blind index computed for some other purpose.
const HASH_NAMESPACE = 'merchant-category';

/// Shortest merchant name worth caching. Must match
/// MerchantCategoryRules._minKeyLength in the app — the two normalise the same
/// strings and a mismatch would mean the app looks up a key the server never
/// wrote.
const MIN_KEY_LENGTH = 3;

const NON_ALPHANUMERIC = /[^a-z0-9]/g;

/// Normalised cache key for a merchant name. Mirrors
/// MerchantCategoryRules.keyFor in the Flutter app; keep the two in step.
export function normalizeMerchant(merchant: string | null | undefined): string | null {
  if (!merchant) return null;
  const key = merchant.toLowerCase().replace(NON_ALPHANUMERIC, '');
  return key.length < MIN_KEY_LENGTH ? null : key;
}

/// Keyed digest of a normalised merchant name, or null when the merchant is too
/// short or DATA_HMAC_KEY is unset.
///
/// The cache is shared across every user, so it deliberately stores no readable
/// merchant text: a payee can be a person's name. An unkeyed hash would not be
/// enough — real merchant names are a small enough space to enumerate — so this
/// is an HMAC under the server key, and with no key configured the cache simply
/// turns itself off rather than degrading to plaintext.
export function merchantHash(merchant: string | null | undefined): string | null {
  const normalized = normalizeMerchant(merchant);
  if (!normalized) return null;
  try {
    return blindIndex(HASH_NAMESPACE, normalized).toString('hex');
  } catch {
    return null;
  }
}

export type CachedCategory = {
  category: SpendCategory;
  confidence: Confidence;
};

const VALID_CATEGORIES = new Set<string>(SPEND_CATEGORIES);

/// Looks up categories for [merchants] by hash. Returns a map keyed on the
/// merchant hash. Never throws: a cache miss and a cache failure are the same
/// thing to the caller, which just pays for a model call instead.
export async function readMerchantCategories(
  merchants: Array<string | null | undefined>,
  handle: Queryable = db,
): Promise<Map<string, CachedCategory>> {
  const hashes = [...new Set(
    merchants.map(merchantHash).filter((hash): hash is string => hash !== null),
  )];
  if (hashes.length === 0) return new Map();
  try {
    const result = await handle.query(
      `select merchant_hash, category, confidence
         from merchant_category_cache
        where merchant_hash = any($1::text[])`,
      [hashes],
    );
    const out = new Map<string, CachedCategory>();
    for (const row of result.rows) {
      const category = String(row.category);
      // A category retired since the row was written must not leak back in.
      if (!VALID_CATEGORIES.has(category)) continue;
      out.set(String(row.merchant_hash), {
        category: category as SpendCategory,
        confidence: String(row.confidence) as Confidence,
      });
    }
    // Best-effort usage counter; a failure here must not fail the request.
    void handle.query(
      `update merchant_category_cache
          set hits = hits + 1, updated_at = now()
        where merchant_hash = any($1::text[])`,
      [hashes],
    ).catch(() => undefined);
    return out;
  } catch (error) {
    console.warn('[merchant-cache] lookup failed', error);
    return new Map();
  }
}

/// Stores confidently-resolved merchants so no other user pays to classify the
/// same payee. Only `high` results are shared: a guess the model itself was
/// unsure about must not become a silent answer for somebody else.
export async function writeMerchantCategories(
  entries: Array<{
    merchant: string | null | undefined;
    category: SpendCategory;
    confidence: Confidence;
    model: string;
  }>,
  handle: Queryable = db,
): Promise<void> {
  const rows = entries
    .filter((entry) => entry.confidence === 'high')
    .map((entry) => ({ hash: merchantHash(entry.merchant), entry }))
    .filter((row): row is { hash: string; entry: typeof entries[number] } =>
      row.hash !== null);
  if (rows.length === 0) return;
  for (const { hash, entry } of rows) {
    try {
      await handle.query(
        `insert into merchant_category_cache (
           merchant_hash, category, confidence, model, hits
         ) values ($1, $2, $3, $4, 1)
         on conflict (merchant_hash) do update set
           category = excluded.category,
           confidence = excluded.confidence,
           model = excluded.model,
           updated_at = now()`,
        [hash, entry.category, entry.confidence, entry.model],
      );
    } catch (error) {
      console.warn('[merchant-cache] write failed', error);
      return;
    }
  }
}
