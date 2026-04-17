// Client-side "seen posts" history. Tracks posts the current user
// interacted with (reacted, replied, or opened detail view) over the
// past 24 hours. Storage is localStorage only — never sent to the
// server. Entries older than 24h are pruned on every read/write so
// the set stays bounded and self-clearing.

const STORAGE_KEY = 'hs:seen_posts';
const TTL_MS = 24 * 60 * 60 * 1000;

export interface SeenEntry {
  id: string;
  seen_at: number; // epoch millis
}

function now(): number {
  return Date.now();
}

function isBrowser(): boolean {
  return typeof window !== 'undefined' && typeof window.localStorage !== 'undefined';
}

function readRaw(): SeenEntry[] {
  if (!isBrowser()) return [];
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(
      (e): e is SeenEntry =>
        e && typeof e.id === 'string' && typeof e.seen_at === 'number',
    );
  } catch {
    return [];
  }
}

function writeRaw(entries: SeenEntry[]): void {
  if (!isBrowser()) return;
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(entries));
  } catch {
    // Quota exceeded or disabled — drop silently; feature is best-effort.
  }
}

function prune(entries: SeenEntry[], at: number = now()): SeenEntry[] {
  const cutoff = at - TTL_MS;
  return entries.filter((e) => e.seen_at >= cutoff);
}

/**
 * Record that the user interacted with a post. Replaces any prior
 * entry for the same post ID so seen_at always reflects the most
 * recent interaction.
 */
export function markSeen(postId: string): void {
  if (!postId) return;
  const at = now();
  const pruned = prune(readRaw(), at).filter((e) => e.id !== postId);
  pruned.push({ id: postId, seen_at: at });
  writeRaw(pruned);
}

/**
 * Return the seen-history newest-first, automatically pruning any
 * entries that have aged out of the 24h window.
 */
export function getSeenPosts(): SeenEntry[] {
  const pruned = prune(readRaw());
  // Write back so the on-disk copy is the pruned one too.
  writeRaw(pruned);
  return [...pruned].sort((a, b) => b.seen_at - a.seen_at);
}

/** Drop every entry. Used by the Clear History button. */
export function clearSeenPosts(): void {
  writeRaw([]);
}
