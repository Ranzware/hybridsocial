// External link trust + opt-out store. Two pieces of state, both
// localStorage-only (no server roundtrip — purely a UX preference):
//
//   1. A per-domain trust map: { "github.com": <epoch_ms> } — entries
//      auto-expire 24h after they're set.
//   2. A global on/off switch: when off, the warning modal never shows
//      regardless of the trust map.
//
// Both helpers are SSR-safe: outside the browser they degrade to
// "no trust, warning enabled" so the modal can render but never
// short-circuits during prerender.

const TRUST_KEY = 'hs:external_link_trust';
const DISABLED_KEY = 'hs:external_link_warning_disabled';
const TTL_MS = 24 * 60 * 60 * 1000;

type TrustMap = Record<string, number>;

function isBrowser(): boolean {
  return typeof window !== 'undefined' && typeof window.localStorage !== 'undefined';
}

function readTrust(): TrustMap {
  if (!isBrowser()) return {};
  try {
    const raw = window.localStorage.getItem(TRUST_KEY);
    if (!raw) return {};
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object') return {};
    return parsed as TrustMap;
  } catch {
    return {};
  }
}

function writeTrust(map: TrustMap): void {
  if (!isBrowser()) return;
  try {
    window.localStorage.setItem(TRUST_KEY, JSON.stringify(map));
  } catch {
    // Quota exceeded / disabled — silently drop. Worst case the user
    // sees the warning again, which is the safe default.
  }
}

function prune(map: TrustMap, now: number = Date.now()): TrustMap {
  const out: TrustMap = {};
  for (const [domain, expires] of Object.entries(map)) {
    if (typeof expires === 'number' && expires > now) {
      out[domain] = expires;
    }
  }
  return out;
}

/** Returns true if `domain` is currently trusted. Auto-prunes stale entries. */
export function isDomainTrusted(domain: string): boolean {
  if (!domain) return false;
  const pruned = prune(readTrust());
  // Write-back the pruned copy so storage doesn't grow unbounded.
  writeTrust(pruned);
  return Object.prototype.hasOwnProperty.call(pruned, domain.toLowerCase());
}

/** Marks a domain as trusted for the next 24 hours. */
export function trustDomain(domain: string): void {
  if (!domain) return;
  const pruned = prune(readTrust());
  pruned[domain.toLowerCase()] = Date.now() + TTL_MS;
  writeTrust(pruned);
}

/** Drops every trusted entry. Used by the "Clear all trusted sites" button. */
export function clearTrustedDomains(): void {
  writeTrust({});
}

/** Returns true if the warning is globally disabled. */
export function isWarningDisabled(): boolean {
  if (!isBrowser()) return false;
  try {
    return window.localStorage.getItem(DISABLED_KEY) === '1';
  } catch {
    return false;
  }
}

/** Toggles the global on/off switch. */
export function setWarningDisabled(disabled: boolean): void {
  if (!isBrowser()) return;
  try {
    if (disabled) {
      window.localStorage.setItem(DISABLED_KEY, '1');
    } else {
      window.localStorage.removeItem(DISABLED_KEY);
    }
  } catch {
    // No-op
  }
}
