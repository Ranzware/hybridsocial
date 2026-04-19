<script lang="ts">
  import { fly } from 'svelte/transition';
  import { cubicOut } from 'svelte/easing';

  // Pill banner that announces "N new posts" at the top of a feed.
  // Two visual flourishes on each count bump:
  //   1. the number flies in from below while the old number flies
  //      out the top — slot-machine feel
  //   2. a brief concentric ripple radiates across the pill, giving
  //      the "water surface disturbed by the new digit" sensation
  //
  // When the counter reaches 10+, we stop showing the exact number
  // and display "10+" to keep the pill a fixed width.

  let {
    count = 0,
    onclick
  }: {
    count: number;
    onclick?: () => void;
  } = $props();

  // Svelte's {#each} on a keyed single-item array is the cheapest
  // way to drive enter/exit transitions when a value changes — the
  // old node animates out while the new one animates in, in parallel.
  let display = $derived(count >= 10 ? '10+' : String(count));
  let label = $derived(count === 1 ? 'post' : 'posts');

  // Ripple key — each count change increments it, which in turn
  // remounts the ripple element via {#key}, restarting its CSS
  // animation from t=0. Starts at a non-zero value so the very
  // first render doesn't fire a phantom ripple (we don't want to
  // announce "0 new posts" with a splash).
  let rippleKey = $state(0);
  let firstRender = true;

  $effect(() => {
    // Track `display` so Svelte re-runs this effect when it changes.
    display;
    if (firstRender) {
      firstRender = false;
      return;
    }
    rippleKey++;
  });
</script>

{#if count > 0}
  <button type="button" class="npb" onclick={() => onclick?.()} aria-label="{display} new {label}. Scroll to top to view.">
    <!-- Ripple overlay. Remounts on every count bump; the CSS
         keyframes fire fresh each time. Positioned absolutely so it
         doesn't shift the flex children. Pointer-events: none so
         clicks go through to the button. -->
    {#key rippleKey}
      <span class="npb-ripple" aria-hidden="true"></span>
    {/key}

    <span class="material-symbols-outlined npb-arrow" aria-hidden="true">arrow_upward</span>

    <span class="npb-num-slot" aria-hidden="true">
      {#each [display] as n (n)}
        <span
          class="npb-num"
          in:fly={{ y: 18, duration: 320, easing: cubicOut }}
          out:fly={{ y: -18, duration: 320, easing: cubicOut }}
        >{n}</span>
      {/each}
    </span>

    <span class="npb-label">new {label}</span>
  </button>
{/if}

<style>
  .npb {
    /* Positioning context for the absolute ripple + number slot. */
    position: relative;
    overflow: hidden;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    align-self: center;
    padding: 10px 22px;
    background: var(--color-primary);
    color: var(--color-on-primary, #fff);
    border: none;
    border-radius: 9999px;
    font-size: var(--text-sm, 0.9rem);
    font-weight: 700;
    line-height: 1;
    cursor: pointer;
    box-shadow: 0 6px 20px rgba(0, 0, 0, 0.18);
    /* Subtle pop on mount so the first appearance feels like a
       signal rather than just a page element. */
    animation: npb-pop 280ms cubic-bezier(0.22, 1, 0.36, 1);
  }

  .npb:hover {
    transform: translateY(-1px);
  }

  .npb:active {
    transform: translateY(0);
  }

  @keyframes npb-pop {
    0%   { transform: scale(0.85); opacity: 0; }
    70%  { transform: scale(1.04); opacity: 1; }
    100% { transform: scale(1);    opacity: 1; }
  }

  .npb-arrow {
    font-size: 18px;
    /* The arrow lives in flex flow, ripple is absolute — give
       the arrow a higher stack level so it paints above. */
    position: relative;
    z-index: 1;
  }

  /* Number slot: fixed-width container so the pill width doesn't
     jitter as digits change (1 → 2 → 10+). The two transitioning
     children overlap via grid-area. */
  .npb-num-slot {
    position: relative;
    display: inline-grid;
    grid-template-areas: 'n';
    /* 2ch + a bit for the "+" suffix — wide enough for "10+",
       narrow enough that 1-digit values feel compact. */
    min-width: 2.2ch;
    text-align: center;
    z-index: 1;
  }

  .npb-num {
    grid-area: n;
    font-variant-numeric: tabular-nums;
  }

  .npb-label {
    position: relative;
    z-index: 1;
  }

  /* Water-surface ripple. A translucent white circle that starts
     at scale(0) and expands well past the pill bounds while fading
     out. `overflow: hidden` on the parent clips it to the pill
     shape, giving the impression the surface itself is rippling. */
  .npb-ripple {
    position: absolute;
    inset: 50% 50% auto auto;
    width: 40px;
    height: 40px;
    margin: -20px -20px 0 0;
    border-radius: 50%;
    background: radial-gradient(
      circle,
      rgba(255, 255, 255, 0.6) 0%,
      rgba(255, 255, 255, 0.3) 40%,
      rgba(255, 255, 255, 0) 75%
    );
    pointer-events: none;
    transform-origin: center;
    animation: npb-ripple 700ms cubic-bezier(0.22, 0.8, 0.36, 1) forwards;
    z-index: 0;
  }

  @keyframes npb-ripple {
    0%   { transform: scale(0);   opacity: 0.9; }
    60%  { opacity: 0.6; }
    100% { transform: scale(9);   opacity: 0; }
  }

  /* Respect reduced-motion users — skip the mount pop, the digit
     fly, and the ripple. The number change still happens, just
     instantly. */
  @media (prefers-reduced-motion: reduce) {
    .npb,
    .npb-ripple,
    .npb-num {
      animation: none !important;
      transition: none !important;
    }
  }
</style>
