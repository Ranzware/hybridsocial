<script lang="ts">
  import type { Group } from '$lib/api/types.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';

  let {
    group,
    onclick,
  }: {
    group: Group;
    onclick?: () => void;
  } = $props();

  function formatCount(n: number | undefined): string {
    if (typeof n !== 'number') return '0';
    if (n < 1000) return String(n);
    if (n < 1_000_000) return (n / 1000).toFixed(n < 10_000 ? 1 : 0) + 'K';
    return (n / 1_000_000).toFixed(1) + 'M';
  }
</script>

<button type="button" class="group-card" onclick={onclick}>
  <div class="group-card-banner">
    {#if group.header_url}
      <img src={group.header_url} alt="" class="group-card-banner-img" loading="lazy" />
    {:else}
      <div class="group-card-banner-fallback"></div>
    {/if}
  </div>
  <div class="group-card-body">
    <div class="group-card-avatar-wrap">
      <Avatar src={group.avatar_url} name={group.name} size="lg" />
    </div>
    <div class="group-card-info">
      <div class="group-name-row">
        <span class="group-name" title={group.name}>{group.name}</span>
        {#if group.visibility === 'private'}
          <svg class="lock-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-label="Private group">
            <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
            <path d="M7 11V7a5 5 0 0110 0v4" />
          </svg>
        {/if}
      </div>
      {#if group.description}
        <p class="group-description">{group.description}</p>
      {/if}
      <div class="group-card-meta">
        <span class="group-visibility">{group.visibility === 'private' ? 'Private' : 'Public'}</span>
        <span class="group-members">
          <strong>{formatCount(group.member_count)}</strong>
          {group.member_count === 1 ? 'member' : 'members'}
        </span>
      </div>
    </div>
  </div>
</button>

<style>
  .group-card {
    display: flex;
    flex-direction: column;
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    overflow: hidden;
    text-align: start;
    color: var(--color-text);
    cursor: pointer;
    width: 100%;
    padding: 0;
    transition: box-shadow var(--transition-fast), transform var(--transition-fast);
  }

  .group-card:hover {
    box-shadow: var(--shadow-md);
    transform: translateY(-2px);
  }

  .group-card-banner {
    height: 96px;
    background: var(--color-surface-container);
    overflow: hidden;
  }

  .group-card-banner-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }

  .group-card-banner-fallback {
    width: 100%;
    height: 100%;
    background: linear-gradient(135deg, var(--color-primary-soft), var(--color-primary));
    opacity: 0.5;
  }

  .group-card-body {
    padding: var(--space-4);
    padding-block-start: 0;
  }

  /* Avatar overlaps the banner like a profile header. */
  .group-card-avatar-wrap {
    margin-block-start: -32px;
    margin-block-end: var(--space-2);
    width: fit-content;
    border: 3px solid var(--color-surface-raised);
    border-radius: 50%;
    background: var(--color-surface-raised);
  }

  .group-card-info {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
    min-width: 0;
  }

  .group-name-row {
    display: flex;
    align-items: center;
    gap: var(--space-1);
  }

  .group-name {
    font-size: var(--text-base);
    font-weight: 700;
    color: var(--color-text);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .lock-icon {
    color: var(--color-text-tertiary);
    flex-shrink: 0;
  }

  .group-description {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    line-height: 1.45;
    margin-block-start: 2px;
    /* Two-line clamp keeps card heights uniform across the grid. */
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }

  .group-card-meta {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    margin-block-start: var(--space-2);
    flex-wrap: wrap;
  }

  .group-visibility {
    font-size: var(--text-xs);
    color: var(--color-primary);
    background: var(--color-primary-soft);
    padding: 2px var(--space-2);
    border-radius: var(--radius-sm);
    font-weight: 600;
  }

  .group-members {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .group-members strong {
    color: var(--color-text);
    font-weight: 700;
  }
</style>
