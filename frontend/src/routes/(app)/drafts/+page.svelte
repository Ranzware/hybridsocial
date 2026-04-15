<script lang="ts">
  import { onMount } from 'svelte';
  import type { PostDraft } from '$lib/api/types.js';
  import { listDrafts, deleteDraft } from '$lib/api/drafts.js';
  import { relativeTime, fullDateTime } from '$lib/utils/time.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  let drafts: PostDraft[] = $state([]);
  let loading = $state(true);
  let error = $state('');
  let deletingId: string | null = $state(null);

  async function load() {
    loading = true;
    error = '';
    try {
      drafts = await listDrafts();
    } catch {
      error = 'Failed to load drafts.';
    } finally {
      loading = false;
    }
  }

  function resume(draft: PostDraft) {
    // Opening the composer with a draftId lets the composer fetch the
    // full draft (so subsequent state updates go through the same path
    // as an open-composer event from anywhere else).
    window.dispatchEvent(
      new CustomEvent('open-composer', { detail: { draftId: draft.id } }),
    );
  }

  async function remove(draft: PostDraft) {
    if (deletingId) return;
    deletingId = draft.id;
    try {
      await deleteDraft(draft.id);
      drafts = drafts.filter((d) => d.id !== draft.id);
    } catch {
      error = 'Failed to delete draft.';
    } finally {
      deletingId = null;
    }
  }

  function preview(draft: PostDraft): string {
    const text = (draft.content || '').trim();
    if (text.length === 0) {
      if (draft.media_ids?.length) return `(${draft.media_ids.length} attachment${draft.media_ids.length > 1 ? 's' : ''})`;
      return '(empty)';
    }
    return text.length > 140 ? text.slice(0, 140) + '…' : text;
  }

  onMount(load);
</script>

<svelte:head>
  <title>Drafts — HybridSocial</title>
</svelte:head>

<div class="drafts-page">
  <div class="page-header">
    <h1 class="page-title">Drafts</h1>
    <p class="page-sub">Saved post drafts. Resume to continue editing, or delete to discard.</p>
  </div>

  {#if loading}
    <div class="state-center"><Spinner /></div>
  {:else if error}
    <div class="state-center">
      <p>{error}</p>
      <button type="button" class="btn btn-outline" onclick={load}>Retry</button>
    </div>
  {:else if drafts.length === 0}
    <div class="state-center empty">
      <span class="material-symbols-outlined empty-icon">edit_note</span>
      <p class="empty-text">No drafts yet</p>
      <p class="empty-sub">Use <strong>Save draft</strong> in the composer to save in-flight posts here.</p>
    </div>
  {:else}
    <ul class="drafts-list">
      {#each drafts as draft (draft.id)}
        <li class="draft-card">
          <div class="draft-body">
            {#if draft.spoiler_text}
              <p class="draft-cw">CW: {draft.spoiler_text}</p>
            {/if}
            <p class="draft-content">{preview(draft)}</p>
            <div class="draft-meta">
              <span class="draft-visibility">{draft.visibility}</span>
              <span class="draft-sep">·</span>
              <time title={fullDateTime(draft.updated_at)}>{relativeTime(draft.updated_at)}</time>
              {#if draft.media_ids?.length}
                <span class="draft-sep">·</span>
                <span>{draft.media_ids.length} media</span>
              {/if}
              {#if draft.poll_options?.length}
                <span class="draft-sep">·</span>
                <span>poll</span>
              {/if}
              {#if draft.scheduled_at}
                <span class="draft-sep">·</span>
                <span>scheduled</span>
              {/if}
            </div>
          </div>
          <div class="draft-actions">
            <button type="button" class="btn btn-primary" onclick={() => resume(draft)}>Resume</button>
            <button
              type="button"
              class="btn btn-ghost-danger"
              disabled={deletingId === draft.id}
              onclick={() => remove(draft)}
            >
              {deletingId === draft.id ? 'Deleting…' : 'Delete'}
            </button>
          </div>
        </li>
      {/each}
    </ul>
  {/if}
</div>

<style>
  .drafts-page {
    max-width: var(--feed-max-width);
    margin: 0 auto;
  }

  .page-header {
    margin-block-end: var(--space-4);
  }

  .page-title {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
  }

  .page-sub {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    margin-block-start: var(--space-1);
  }

  .state-center {
    text-align: center;
    padding: var(--space-12) var(--space-4);
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
    align-items: center;
  }

  .empty-icon {
    font-size: 48px;
    color: var(--color-text-tertiary);
  }

  .empty-text {
    font-size: var(--text-base);
    color: var(--color-text);
  }

  .empty-sub {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
  }

  .drafts-list {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .draft-card {
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    padding: var(--space-4);
    display: flex;
    gap: var(--space-4);
    align-items: flex-start;
    justify-content: space-between;
  }

  .draft-body {
    flex: 1;
    min-width: 0;
  }

  .draft-cw {
    font-size: var(--text-sm);
    color: var(--color-warning, #f59e0b);
    font-weight: 600;
    margin: 0 0 var(--space-2) 0;
  }

  .draft-content {
    font-size: var(--text-base);
    color: var(--color-text);
    white-space: pre-wrap;
    word-break: break-word;
    margin: 0 0 var(--space-2) 0;
  }

  .draft-meta {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    display: flex;
    gap: var(--space-1);
    flex-wrap: wrap;
  }

  .draft-visibility {
    text-transform: capitalize;
  }

  .draft-sep {
    opacity: 0.6;
  }

  .draft-actions {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    flex-shrink: 0;
  }
</style>
