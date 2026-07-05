<script lang="ts">
  import { onMount } from 'svelte';
  import type { Post } from '$lib/api/types.js';
  import { getPostsByIds } from '$lib/api/statuses.js';
  import {
    getSeenPosts,
    clearSeenPosts,
    type SeenEntry,
  } from '$lib/utils/seen-posts.js';
  import PostCard from '$lib/components/post/PostCard.svelte';

  let seen = $state<SeenEntry[]>([]);
  let postsById = $state<Record<string, Post>>({});
  let loading = $state(true);
  let error = $state('');
  let confirmingClear = $state(false);

  async function load() {
    loading = true;
    error = '';
    try {
      seen = getSeenPosts();
      if (seen.length === 0) {
        postsById = {};
        return;
      }

      const posts = await getPostsByIds(seen.map((s) => s.id));
      const map: Record<string, Post> = {};
      for (const p of posts) map[p.id] = p;
      postsById = map;
    } catch (e: unknown) {
      error =
        e instanceof Error
          ? e.message
          : "We couldn't load your history right now.";
    } finally {
      loading = false;
    }
  }

  function doClear() {
    clearSeenPosts();
    seen = [];
    postsById = {};
    confirmingClear = false;
  }

  function formatSeenAt(ts: number): string {
    const now = Date.now();
    const diff = Math.floor((now - ts) / 1000);
    if (diff < 60) return 'Just now';
    if (diff < 3600) return `${Math.floor(diff / 60)} min ago`;
    const hours = Math.floor(diff / 3600);
    return `${hours}h ago`;
  }

  // Derived: entries we actually have posts for, newest first.
  let visibleEntries = $derived(
    seen.filter((s) => postsById[s.id] !== undefined),
  );
  let missingCount = $derived(
    seen.filter((s) => postsById[s.id] === undefined).length,
  );

  onMount(load);
</script>

<svelte:head>
  <title>History &middot; Settings</title>
</svelte:head>

<section class="history-page">
  <header class="history-header">
    <div>
      <p class="history-sub">
        Posts you've interacted with in the last 24 hours — by
        reacting, replying, or opening them. Stored in your browser
        only and cleared automatically after 24 hours.
      </p>
    </div>
    {#if seen.length > 0}
      <button
        type="button"
        class="btn btn-ghost-danger"
        onclick={() => (confirmingClear = true)}
      >
        Clear history
      </button>
    {/if}
  </header>

  {#if confirmingClear}
    <div class="confirm-banner" role="alertdialog" aria-live="polite">
      <span>Clear all entries? This affects only your local history.</span>
      <div class="confirm-actions">
        <button
          type="button"
          class="btn btn-ghost"
          onclick={() => (confirmingClear = false)}
        >
          Cancel
        </button>
        <button type="button" class="btn btn-danger" onclick={doClear}>
          Clear
        </button>
      </div>
    </div>
  {/if}

  {#if loading}
    <div class="state-msg">Loading&hellip;</div>
  {:else if error}
    <div class="state-msg error" role="alert">{error}</div>
  {:else if seen.length === 0}
    <div class="empty-state">
      <h2>Nothing here yet</h2>
      <p>
        React to, reply to, or open a post and it'll show up here.
        Entries clear themselves 24 hours after you interacted.
      </p>
    </div>
  {:else}
    {#if missingCount > 0}
      <p class="missing-note">
        {missingCount} post{missingCount === 1 ? '' : 's'} couldn't be
        loaded — they may have been deleted or you no longer have
        permission to view them.
      </p>
    {/if}

    <ol class="history-list">
      {#each visibleEntries as entry (entry.id)}
        <li class="history-item">
          <div class="history-stamp">{formatSeenAt(entry.seen_at)}</div>
          <div class="history-card">
            <PostCard post={postsById[entry.id]} compact filterContext="history" />
          </div>
        </li>
      {/each}
    </ol>
  {/if}
</section>

<style>
  .history-page {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .history-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: var(--space-4);
  }

  .history-sub {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    line-height: 1.5;
    margin: 0;
    max-width: 60ch;
  }

  .confirm-banner {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    background: var(--color-warning-surface, rgba(217, 119, 6, 0.08));
    border: 1px solid var(--color-warning, #d97706);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
  }

  .confirm-actions {
    display: flex;
    gap: var(--space-2);
  }

  .state-msg {
    padding: var(--space-6);
    text-align: center;
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
  }

  .state-msg.error {
    color: var(--color-danger, #b00);
  }

  .empty-state {
    padding: var(--space-8) var(--space-4);
    text-align: center;
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
  }

  .empty-state h2 {
    font-size: var(--text-lg);
    font-weight: 600;
    margin: 0 0 var(--space-2) 0;
  }

  .empty-state p {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    line-height: 1.5;
    margin: 0 auto;
    max-width: 42ch;
  }

  .missing-note {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    margin: 0;
    padding: var(--space-2) var(--space-3);
    background: var(--color-surface);
    border-radius: var(--radius-md);
  }

  .history-list {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .history-item {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .history-stamp {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    padding-inline-start: var(--space-2);
  }

  .history-card {
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: var(--color-surface-raised, var(--color-surface));
    overflow: hidden;
  }
</style>
