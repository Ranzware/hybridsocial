<script lang="ts">
  import { youtubeEmbedUrl, youtubeThumbnail, youtubeWatchUrl, type YouTubeRef } from '$lib/utils/youtube.js';

  let {
    ref,
    title = ''
  }: {
    ref: YouTubeRef;
    title?: string;
  } = $props();

  let playing = $state(false);
  let thumbBroken = $state(false);

  // Stop the click from bubbling to the post-card row navigation. The
  // user wanted "play here", not "open the post detail".
  function play(e: MouseEvent | KeyboardEvent) {
    e.stopPropagation();
    if ('preventDefault' in e) e.preventDefault();
    playing = true;
  }

  function onKey(e: KeyboardEvent) {
    if (e.key === 'Enter' || e.key === ' ') play(e);
  }
</script>

<div class="yt-embed" onclick={(e) => e.stopPropagation()} role="presentation">
  {#if playing}
    <iframe
      class="yt-frame"
      src={youtubeEmbedUrl(ref.id, ref.start)}
      title={title || 'YouTube video'}
      loading="lazy"
      allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
      referrerpolicy="strict-origin-when-cross-origin"
      allowfullscreen
    ></iframe>
  {:else}
    <button
      type="button"
      class="yt-poster"
      onclick={play}
      onkeydown={onKey}
      aria-label={title ? `Play video: ${title}` : 'Play YouTube video'}
    >
      {#if !thumbBroken}
        <img
          class="yt-thumb"
          src={youtubeThumbnail(ref.id)}
          alt=""
          loading="lazy"
          onerror={() => (thumbBroken = true)}
        />
      {:else}
        <div class="yt-thumb yt-thumb-fallback"></div>
      {/if}
      <span class="yt-play" aria-hidden="true">
        <svg viewBox="0 0 68 48" width="56" height="40">
          <path d="M66.52 7.74a8 8 0 0 0-5.64-5.66C55.91.5 34 .5 34 .5s-21.91 0-26.88 1.58A8 8 0 0 0 1.48 7.74 83.43 83.43 0 0 0 0 24a83.43 83.43 0 0 0 1.48 16.26 8 8 0 0 0 5.64 5.66C12.09 47.5 34 47.5 34 47.5s21.91 0 26.88-1.58a8 8 0 0 0 5.64-5.66A83.43 83.43 0 0 0 68 24a83.43 83.43 0 0 0-1.48-16.26z" fill="#f00"/>
          <path d="M27.5 33.5l18-9.5-18-9.5z" fill="#fff"/>
        </svg>
      </span>
      <span class="yt-corner" aria-hidden="true">YouTube</span>
    </button>
    {#if title}
      <a
        class="yt-meta"
        href={youtubeWatchUrl(ref.id, ref.start)}
        target="_blank"
        rel="noopener noreferrer"
        onclick={(e) => e.stopPropagation()}
      >
        <span class="yt-title">{title}</span>
        <span class="yt-provider">youtube.com</span>
      </a>
    {/if}
  {/if}
</div>

<style>
  .yt-embed {
    margin-block-start: var(--space-3);
    border-radius: var(--radius-lg);
    overflow: hidden;
    background: #000;
    border: 1px solid var(--color-border);
  }

  .yt-frame {
    width: 100%;
    aspect-ratio: 16 / 9;
    border: 0;
    display: block;
  }

  .yt-poster {
    position: relative;
    display: block;
    width: 100%;
    aspect-ratio: 16 / 9;
    padding: 0;
    margin: 0;
    border: 0;
    background: #000;
    cursor: pointer;
    overflow: hidden;
  }

  .yt-thumb {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
    transition: transform 0.3s ease, filter 0.2s ease;
  }

  .yt-thumb-fallback {
    background: linear-gradient(135deg, #1a1a1a, #333);
  }

  .yt-poster:hover .yt-thumb {
    transform: scale(1.02);
    filter: brightness(0.85);
  }

  .yt-play {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    pointer-events: none;
    transition: transform 0.15s ease;
  }

  .yt-poster:hover .yt-play,
  .yt-poster:focus-visible .yt-play {
    transform: scale(1.08);
  }

  .yt-play :global(svg) {
    filter: drop-shadow(0 2px 6px rgba(0, 0, 0, 0.5));
  }

  .yt-corner {
    position: absolute;
    top: var(--space-2);
    inset-inline-start: var(--space-2);
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 0.04em;
    color: #fff;
    background: rgba(0, 0, 0, 0.55);
    padding: 2px 6px;
    border-radius: var(--radius-sm);
    text-transform: uppercase;
  }

  .yt-meta {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: var(--space-2) var(--space-3);
    background: var(--color-surface-container-low);
    color: var(--color-on-surface);
    text-decoration: none;
    border-block-start: 1px solid var(--color-border);
  }

  .yt-meta:hover {
    background: var(--color-surface-container);
    text-decoration: none;
  }

  .yt-title {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-on-surface);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .yt-provider {
    font-size: var(--text-xs);
    color: var(--color-on-surface-variant);
  }

  .yt-poster:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: -2px;
  }
</style>
