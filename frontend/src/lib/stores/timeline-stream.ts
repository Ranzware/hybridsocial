import { writable, derived } from 'svelte/store';
import type { Post } from '$lib/api/types.js';
import { browser } from '$app/environment';

// Shared state for the currently-active SSE timeline stream. The
// module supports one active stream at a time — switching pages (or
// switching explore tabs) disconnects the old stream and opens a new
// one. This keeps the `queuedCount` store semantics clean: it always
// reflects unseen posts for the stream the user is currently on.

const MAX_QUEUE_SIZE = 30;
const TRUNCATE_TO = 60;
const TRUNCATE_THRESHOLD = 120;

interface TimelineStreamState {
  queued: Post[];
  connected: boolean;
}

const state = writable<TimelineStreamState>({
  queued: [],
  connected: false,
});

export const queuedPosts = derived(state, ($s) => $s.queued);
export const queuedCount = derived(state, ($s) => $s.queued.length);
export const isStreamConnected = derived(state, ($s) => $s.connected);

let eventSource: EventSource | null = null;
let isAtTop = true;
let currentFilter: ((post: Post) => boolean) | null = null;
// Tracks the last (kind + filter) we connected with, so we only reset
// the queue when the stream's audience actually changes (e.g. explore
// tab switching Local ↔ Global). A plain reconnect preserves queued
// posts — otherwise a route re-mount or HMR silently resets the count
// back to 0 and the pill never increments past 1.
let currentStreamSig: string | null = null;

export function setAtTop(atTop: boolean) {
  isAtTop = atTop;
}

/**
 * Flush queued posts into the timeline.
 * Returns the queued posts and clears the queue.
 */
export function flushQueue(): Post[] {
  let flushed: Post[] = [];
  state.update((s) => {
    flushed = s.queued;
    return { ...s, queued: [] };
  });
  return flushed;
}

/** Endpoint kind determines the URL + Phoenix.PubSub topic server-side. */
export type StreamKind = 'home' | 'public';

export interface ConnectOptions {
  /** Called per incoming post. Return false to discard (filter). */
  filter?: (post: Post) => boolean;
}

/**
 * Connect to a streaming endpoint. Replaces any existing connection.
 *   - 'home' → /streaming/user subscribes to user:<me> (home timeline
 *     fan-out; every post by a followed user pings this stream)
 *   - 'public' → /streaming/public subscribes to timeline:public
 *     (every public/unlisted post instance-wide)
 *
 * The optional filter lets callers narrow the feed: the explore Local
 * tab wants only locally-authored posts, so it passes a filter that
 * rejects posts where the acct contains `@`.
 */
export function connectStream(
  kind: StreamKind,
  apiBase: string,
  options: ConnectOptions = {}
): void {
  if (!browser) return;

  const sig = kind + ':' + (options.filter ? 'filtered' : 'unfiltered');

  // Same (kind + filter) signature → this is a plain reconnect; keep
  // the queue intact so counts accumulate across reconnects.
  // Different signature → the audience changed (e.g. Local → Global
  // on explore); reset the queue so stale posts don't appear.
  const audienceChanged = currentStreamSig !== null && currentStreamSig !== sig;

  disconnectStream();
  currentFilter = options.filter ?? null;
  currentStreamSig = sig;

  if (audienceChanged) {
    state.set({ queued: [], connected: false });
  } else {
    state.update((s) => ({ ...s, connected: false }));
  }

  try {
    const path =
      kind === 'home' ? '/api/v1/streaming/user?stream=home' : '/api/v1/streaming/public';
    const url = `${apiBase}${path}`;
    eventSource = new EventSource(url, { withCredentials: true });

    state.update((s) => ({ ...s, connected: true }));

    eventSource.addEventListener('update', (event) => {
      try {
        const post: Post = JSON.parse(event.data);
        if (currentFilter && !currentFilter(post)) return;

        if (isAtTop) {
          window.dispatchEvent(new CustomEvent('timeline-update', { detail: post }));
        } else {
          state.update((s) => {
            // Avoid duplicate queueing if the backend fanout delivers
            // a post twice (rare, e.g. author + follower broadcast).
            if (s.queued.some((p) => p.id === post.id)) return s;
            const queued = [post, ...s.queued].slice(0, MAX_QUEUE_SIZE);
            return { ...s, queued };
          });
        }
      } catch {
        // Ignore malformed events
      }
    });

    eventSource.addEventListener('status.update', (event) => {
      try {
        const post: Post = JSON.parse(event.data);
        window.dispatchEvent(new CustomEvent('timeline-status-update', { detail: post }));
      } catch {
        // Ignore
      }
    });

    eventSource.addEventListener('delete', (event) => {
      try {
        const id = event.data;
        window.dispatchEvent(new CustomEvent('post-deleted', { detail: { id } }));
      } catch {
        // Ignore
      }
    });

    eventSource.onerror = () => {
      state.update((s) => ({ ...s, connected: false }));
      // EventSource auto-reconnects
    };

    eventSource.onopen = () => {
      state.update((s) => ({ ...s, connected: true }));
    };
  } catch {
    // EventSource creation failed — SSE unsupported or blocked
  }
}

export function disconnectStream(): void {
  if (eventSource) {
    eventSource.close();
    eventSource = null;
  }
  currentFilter = null;
  state.update((s) => ({ ...s, connected: false }));
}

// ─── Backward-compat aliases ────────────────────────────────────────
// Existing callers (home page) used the pre-generalization names.
// Keeping them as thin wrappers avoids touching every consumer.

export function connectTimelineStream(apiBase: string): void {
  connectStream('home', apiBase);
}

export function disconnectTimelineStream(): void {
  disconnectStream();
}

/**
 * Truncate a posts array if it exceeds the threshold.
 * Call this after merging queued posts to prevent memory bloat.
 */
export function maybeTruncate(posts: Post[]): Post[] {
  if (posts.length > TRUNCATE_THRESHOLD) {
    return posts.slice(0, TRUNCATE_TO);
  }
  return posts;
}
