<script lang="ts">
  import { onMount } from 'svelte';
  import { listStoryFeed, type StoryGroup } from '$lib/api/stories.js';
  import { currentUser } from '$lib/stores/auth.js';
  import StoryViewer from './StoryViewer.svelte';
  import StoryComposer from './StoryComposer.svelte';

  let groups: StoryGroup[] = $state([]);
  let loading = $state(true);
  let viewerOpen = $state(false);
  let viewerStartIndex = $state(0);
  let composerOpen = $state(false);

  let me = $derived($currentUser);

  let selfGroup = $derived(groups.find((g) => g.is_self) || null);
  let otherGroups = $derived(groups.filter((g) => !g.is_self));

  async function load() {
    try {
      const result = await listStoryFeed();
      groups = result.groups;
    } catch {
      groups = [];
    } finally {
      loading = false;
    }
  }

  function openViewer(authorId: string) {
    const idx = groups.findIndex((g) => g.identity.id === authorId);
    if (idx >= 0) {
      viewerStartIndex = idx;
      viewerOpen = true;
    }
  }

  function handleSelfTileClick() {
    if (selfGroup && selfGroup.stories.length > 0) {
      openViewer(selfGroup.identity.id);
    } else {
      composerOpen = true;
    }
  }

  function openComposer() {
    composerOpen = true;
  }

  function handleStoryCreated() {
    composerOpen = false;
    load();
  }

  function handleStoryDeleted() {
    load();
  }

  onMount(() => {
    load();

    function refresh() { load(); }
    window.addEventListener('story-created', refresh);
    window.addEventListener('story-deleted', refresh);
    return () => {
      window.removeEventListener('story-created', refresh);
      window.removeEventListener('story-deleted', refresh);
    };
  });
</script>

{#if !loading && (selfGroup || otherGroups.length > 0 || me)}
  <div class="stories-carousel" aria-label="Stories">
    <div class="stories-track">
      {#if me}
        <div class="story-tile self-tile">
          <button
            type="button"
            class="tile-button"
            onclick={handleSelfTileClick}
            aria-label={selfGroup ? 'View your story' : 'Add to your story'}
          >
            <div class="ring-wrapper" class:has-story={!!selfGroup} class:viewed={selfGroup?.all_viewed}>
              <div class="avatar-inner">
                {#if me.avatar_url}
                  <img src={me.avatar_url} alt="" />
                {:else}
                  <div class="avatar-placeholder">{(me.display_name || me.handle || '?')[0].toUpperCase()}</div>
                {/if}
              </div>
            </div>
            <div class="story-name">Your story</div>
          </button>
          <button
            type="button"
            class="add-badge"
            onclick={openComposer}
            aria-label="Add story"
          >
            <span class="material-symbols-outlined">add</span>
          </button>
        </div>
      {/if}

      {#each otherGroups as group (group.identity.id)}
        <div class="story-tile">
          <button
            type="button"
            class="tile-button"
            onclick={() => openViewer(group.identity.id)}
            aria-label={`View ${group.identity.display_name || group.identity.handle}'s story`}
          >
            <div class="ring-wrapper has-story" class:viewed={group.all_viewed}>
              <div class="avatar-inner">
                {#if group.identity.avatar_url}
                  <img src={group.identity.avatar_url} alt="" />
                {:else}
                  <div class="avatar-placeholder">{(group.identity.display_name || group.identity.handle || '?')[0].toUpperCase()}</div>
                {/if}
              </div>
            </div>
            <div class="story-name">{group.identity.display_name || group.identity.handle}</div>
          </button>
        </div>
      {/each}
    </div>
  </div>
{/if}

{#if viewerOpen}
  <StoryViewer
    {groups}
    startGroupIndex={viewerStartIndex}
    onclose={() => { viewerOpen = false; load(); }}
    ondelete={handleStoryDeleted}
  />
{/if}

{#if composerOpen}
  <StoryComposer onclose={() => composerOpen = false} oncreated={handleStoryCreated} />
{/if}

<style>
  .stories-carousel {
    width: 100%;
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: 16px;
    padding: 14px 8px;
    overflow: hidden;
  }

  .stories-track {
    display: flex;
    gap: 14px;
    overflow-x: auto;
    scrollbar-width: none;
    padding: 0 8px;
  }

  .stories-track::-webkit-scrollbar { display: none; }

  .story-tile {
    position: relative;
    flex: 0 0 auto;
    width: 76px;
  }

  .tile-button {
    width: 100%;
    background: transparent;
    border: none;
    padding: 0;
    cursor: pointer;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
  }

  .ring-wrapper {
    width: 72px;
    height: 72px;
    border-radius: 50%;
    padding: 3px;
    background: var(--color-border);
    display: flex;
    align-items: center;
    justify-content: center;
    transition: transform 200ms ease;
  }

  .tile-button:hover .ring-wrapper {
    transform: scale(1.04);
  }

  .ring-wrapper.has-story {
    background: linear-gradient(135deg, #f9a826 0%, #ee2a7b 50%, #6228d7 100%);
    padding: 3px;
  }

  .ring-wrapper.has-story.viewed {
    background: var(--color-border);
  }

  .avatar-inner {
    width: 100%;
    height: 100%;
    border-radius: 50%;
    overflow: hidden;
    background: var(--color-surface-container);
    border: 2px solid var(--color-surface);
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .avatar-inner img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .avatar-placeholder {
    width: 100%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--color-primary);
    color: var(--color-on-primary);
    font-size: 1.5rem;
    font-weight: 700;
  }

  .add-badge {
    position: absolute;
    bottom: 22px;
    right: 6px;
    width: 22px;
    height: 22px;
    border-radius: 50%;
    background: var(--color-primary);
    color: var(--color-on-primary);
    border: 2px solid var(--color-surface);
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    padding: 0;
  }

  .add-badge .material-symbols-outlined {
    font-size: 14px;
    font-weight: 700;
  }

  .story-name {
    font-size: 0.72rem;
    color: var(--color-text);
    max-width: 76px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    text-align: center;
  }

  .self-tile .story-name {
    color: var(--color-text-secondary);
  }
</style>
