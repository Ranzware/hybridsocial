<script lang="ts">
  let {
    type,
    label,
    size = 'sm'
  }: {
    type: 'owner' | 'admin' | 'moderator' | 'editor' | 'bot' | 'verified_l0' | 'verified_l1' | 'verified_l2' | 'verified_l3';
    label?: string;
    size?: 'sm' | 'md';
  } = $props();

  const badgeImages: Record<string, string> = {
    owner: '/badges/OwnerBadg.svg',
    admin: '/badges/AdminBadge.svg',
    moderator: '/badges/ModeratorBadge.svg',
    bot: '/badges/RobotBadge.svg',
    verified_l0: '/badges/BasicBadge.svg',
    verified_l1: '/badges/InitBadge.svg',
    verified_l2: '/badges/ProBadge.svg',
    verified_l3: '/badges/MaxBadge.svg',
  };

  const defaultLabels: Record<string, string> = {
    owner: 'Owner',
    admin: 'Admin',
    moderator: 'Mod',
    editor: 'Editor',
    bot: 'Bot',
    verified_l0: 'Basic',
    verified_l1: 'Verified',
    verified_l2: 'Verified',
    verified_l3: 'Verified Pro'
  };

  let displayLabel = $derived(label || defaultLabels[type] || type);
  let imgSrc = $derived(badgeImages[type]);
  // The redesigned badges are pill-shaped (~3:1 aspect) instead of
  // the old square hexes, so the visual footprint at the same height
  // is roughly 3× wider than before. Compensate by dropping height
  // back down so the rendered width sits closer to what users were
  // used to with the old square badges.
  let imgHeight = $derived(size === 'sm' ? 12 : 16);
</script>

{#if imgSrc}
  <span class="role-badge badge-{size}" title={displayLabel}>
    <!-- The HTML `height` attribute is overridden by app.css's
         `img { height: auto }`, so use an inline CSS height that
         the .badge-img selector can carry through. -->
    <img
      src={imgSrc}
      alt={displayLabel}
      class="badge-img"
      style="height: {imgHeight}px"
    />
  </span>
{:else}
  <span class="role-badge badge-fallback badge-{type} badge-{size}" title={displayLabel}>
    <span class="badge-dot"></span>
  </span>
{/if}

<style>
  .role-badge {
    display: inline-flex;
    align-items: center;
    gap: 3px;
    flex-shrink: 0;
    vertical-align: middle;
  }

  .badge-img {
    display: block;
    flex-shrink: 0;
    width: auto;
    /* Defensive defaults: the global app.css `img { height: auto }`
       was wiping the height attribute on these <img>s, so the inline
       `style="height: …"` the template emits is what wins. The
       max-height here ensures even a fluke override can't blow them
       up to the SVG's intrinsic 34px. */
    max-height: 18px;
  }

  .badge-md .badge-img {
    max-height: 22px;
  }

  .badge-sm {
    font-size: 0.55rem;
  }

  .badge-md {
    font-size: 0.65rem;
  }

  .badge-label {
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.03em;
    color: var(--color-text-secondary);
  }

  /* Fallback pill for types without custom SVG */
  .badge-fallback {
    padding: 1px 5px;
    border-radius: var(--radius-full);
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.03em;
  }

  .badge-fallback .badge-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: currentColor;
  }

  .badge-editor {
    background: #fce7f3;
    color: #9d174d;
  }

  .badge-bot {
    background: var(--color-surface);
    color: var(--color-text-secondary);
  }
</style>
