<script lang="ts">
  import { fly } from 'svelte/transition';
  import { cubicOut } from 'svelte/easing';

  // Floating "N new posts" pill that pops into view from above the
  // viewport when new posts arrive. Click scrolls back to top and
  // flushes the queued posts into the feed.
  //
  // Position is `fixed` under the site header, horizontally centred.

  let {
    count = 0,
    onclick
  }: {
    count: number;
    onclick?: () => void;
  } = $props();

  // Display clamps to "10+" so the pill keeps a stable width even
  // when a burst of events fills the queue faster than the user can
  // click.
  let display = $derived(count >= 10 ? '10+' : String(count));
  let label = $derived(count === 1 ? 'post' : 'posts');
</script>

{#if count > 0}
  <div
    class="npb-floater"
    in:fly={{ y: -24, duration: 280, easing: cubicOut }}
    out:fly={{ y: -24, duration: 180, easing: cubicOut }}
  >
    <button type="button" class="npb" onclick={() => onclick?.()} aria-label="{display} new {label}. Scroll to top to view.">
      <span class="material-symbols-outlined npb-arrow" aria-hidden="true">arrow_upward</span>
      <span class="npb-num">{display}</span>
      <span class="npb-label">new {label}</span>
    </button>
  </div>
{/if}

<style>
  .npb-floater {
    position: fixed;
    inset-block-start: calc(var(--header-height) + 12px);
    inset-inline-start: 50%;
    transform: translateX(-50%);
    z-index: 50;
    pointer-events: none;
  }

  .npb {
    pointer-events: auto;
    position: relative;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    padding: 10px 22px;
    background: var(--color-primary);
    color: var(--color-on-primary, #fff);
    border: none;
    border-radius: 9999px;
    font-size: var(--text-sm, 0.9rem);
    font-weight: 700;
    line-height: 1;
    cursor: pointer;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.22), 0 2px 6px rgba(0, 0, 0, 0.12);
    transition: transform 160ms ease, box-shadow 160ms ease;
  }

  .npb:hover {
    transform: translateY(-1px);
    box-shadow: 0 14px 34px rgba(0, 0, 0, 0.26), 0 3px 8px rgba(0, 0, 0, 0.14);
  }

  .npb:active {
    transform: translateY(0);
  }

  .npb-arrow {
    font-size: 18px;
  }

  .npb-num {
    font-variant-numeric: tabular-nums;
    min-width: 1.2ch;
    text-align: center;
  }
</style>
