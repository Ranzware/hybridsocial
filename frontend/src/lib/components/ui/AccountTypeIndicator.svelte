<script lang="ts">
  import type { Identity } from '$lib/api/types.js';

  let {
    account,
    size = 14,
  }: {
    account: Pick<Identity, 'type' | 'is_bot' | 'domain'>;
    size?: number;
  } = $props();

  // `is_bot` is the legacy flag; treat it as equivalent to type === 'bot'
  // so mixed data still renders sensibly.
  let effectiveType = $derived.by(() => {
    if (account.is_bot) return 'bot';
    return account.type;
  });

  let isLocal = $derived(!account.domain);

  let label = $derived.by(() => {
    switch (effectiveType) {
      case 'bot':
        return 'Bot';
      case 'group':
        return 'Group';
      case 'page':
        return 'Page';
      default:
        return null; // 'user' gets no explicit pill — it's the default.
    }
  });

  let tooltip = $derived.by(() => {
    const parts: string[] = [];
    if (label) parts.push(label);
    else parts.push('Person');
    parts.push(isLocal ? 'Local' : 'Remote');
    return parts.join(' — ');
  });

  // Non-user types always show an icon. Local/remote text is only
  // shown for variants that need disambiguation; for a local regular
  // user we render nothing at all to avoid visual noise (the handle
  // already shows @domain for remote users).
  let shouldRender = $derived(
    effectiveType !== 'user' || !isLocal,
  );
</script>

{#if shouldRender}
  <span class="type-indicator" title={tooltip} aria-label={tooltip}>
    {#if effectiveType === 'bot'}
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <rect x="3" y="8" width="18" height="12" rx="2" />
        <path d="M12 8V4M8 4h8" />
        <circle cx="8.5" cy="14" r="1" fill="currentColor" />
        <circle cx="15.5" cy="14" r="1" fill="currentColor" />
      </svg>
    {:else if effectiveType === 'group'}
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
        <circle cx="9" cy="7" r="4" />
        <path d="M23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75" />
      </svg>
    {:else if effectiveType === 'page'}
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
        <polyline points="9 22 9 12 15 12 15 22" />
      </svg>
    {/if}

    {#if label}
      <span class="type-label">{label}</span>
    {/if}

    {#if !isLocal && effectiveType !== 'user'}
      <span class="locality">Remote</span>
    {/if}
  </span>
{/if}

<style>
  .type-indicator {
    display: inline-flex;
    align-items: center;
    gap: 3px;
    padding: 1px 6px;
    border: 1px solid var(--color-border);
    border-radius: 9999px;
    font-size: 0.7rem;
    font-weight: 600;
    color: var(--color-text-tertiary);
    line-height: 1;
    vertical-align: middle;
    white-space: nowrap;
  }

  .type-label {
    letter-spacing: 0.02em;
  }

  .locality {
    color: var(--color-text-tertiary);
    font-weight: 500;
    padding-inline-start: 4px;
    border-inline-start: 1px solid var(--color-border);
  }
</style>
