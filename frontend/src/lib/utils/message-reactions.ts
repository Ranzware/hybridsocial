// Resolves a reaction shortcode to its display form (unicode emoji
// character or hosted image URL). Used by both the message reaction
// picker (when rendering selectable options) and the message bubble
// (when rendering already-applied reactions).
//
// The default 7 are baked in. Premium reactions come from the
// admin-curated catalog at /api/v1/premium_reactions; we cache the
// fetch in-memory so every bubble doesn't fire its own request.

import { getPremiumReactions, type PremiumReactionsResponse } from '$lib/api/conversations.js';

export type ResolvedReaction =
  | { kind: 'char'; value: string }
  | { kind: 'image'; src: string }
  | { kind: 'shortcode'; value: string };

const DEFAULT_EMOJI: Record<string, string> = {
  like: '\u{1F44D}',
  love: '\u{2764}\u{FE0F}',
  care: '\u{1F917}',
  angry: '\u{1F621}',
  sad: '\u{1F622}',
  lol: '\u{1F602}',
  wow: '\u{1F92F}',
};

let catalogPromise: Promise<PremiumReactionsResponse> | null = null;
let catalog: PremiumReactionsResponse | null = null;

/** Fetch (and cache) the premium-reaction catalog. Subsequent calls
 *  return the same in-flight promise so every bubble gets a single
 *  request, not one per render. */
export function loadReactionCatalog(): Promise<PremiumReactionsResponse> {
  if (catalogPromise) return catalogPromise;
  catalogPromise = getPremiumReactions()
    .then((res) => {
      catalog = res;
      return res;
    })
    .catch((err) => {
      // Reset so the next caller can retry. Returning a sane default
      // keeps the picker functional even when the catalog is down.
      catalogPromise = null;
      catalog = { defaults: Object.keys(DEFAULT_EMOJI), premium: [], max_premium: 0 };
      throw err;
    });
  return catalogPromise;
}

/** Synchronous lookup against the cached catalog + defaults. Returns
 *  a `shortcode` fallback when the shortcode is unknown OR the catalog
 *  hasn't been loaded yet — call sites can still render `:foo:` text
 *  without blocking on the network. */
export function resolveReaction(shortcode: string): ResolvedReaction {
  if (!shortcode) return { kind: 'shortcode', value: '' };

  const def = DEFAULT_EMOJI[shortcode];
  if (def) return { kind: 'char', value: def };

  if (catalog) {
    const premium = catalog.premium.find((p) => p.shortcode === shortcode);
    if (premium) {
      if (premium.image_url) return { kind: 'image', src: premium.image_url };
      if (premium.character) return { kind: 'char', value: premium.character };
    }
  }

  return { kind: 'shortcode', value: shortcode };
}

/** Test-only / SSR helper. */
export function _resetCatalogCache(): void {
  catalog = null;
  catalogPromise = null;
}

export { DEFAULT_EMOJI };
