<script lang="ts">
  import { goto } from '$app/navigation';
  import { clearAuth, sessionExpired, serverReachable } from '$lib/stores/auth.js';

  let expired = $state(false);
  let reachable = $state(true);

  serverReachable.subscribe((v) => (reachable = v));
  sessionExpired.subscribe((v) => {
    expired = v;
    if (v) {
      setTimeout(() => {
        clearAuth();
        goto('/login?expired=1');
      }, 3000);
    }
  });
</script>

{#if !reachable}
  <div class="overlay" role="alertdialog" aria-labelledby="conn-title" aria-describedby="conn-desc">
    <div class="card">
      <div class="icon" aria-hidden="true">
        <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">
          <path d="M2 8.82a15 15 0 0 1 20 0" />
          <path d="M5 12.859a10 10 0 0 1 14 0" />
          <path d="M8.5 16.429a5 5 0 0 1 7 0" />
          <line x1="12" y1="20" x2="12" y2="20.01" />
          <line x1="3" y1="3" x2="21" y2="21" stroke="var(--color-danger, #dc2626)" stroke-width="2" />
        </svg>
      </div>

      <h2 id="conn-title" class="title">Connection lost</h2>
      <p id="conn-desc" class="text">Unable to reach the server.</p>
      <p class="status" aria-live="polite">
        <span>Reconnecting</span><span class="dots" aria-hidden="true"><span>.</span><span>.</span><span>.</span></span>
      </p>
    </div>
  </div>
{:else if expired}
  <div class="overlay" role="alertdialog" aria-labelledby="expired-title">
    <div class="card">
      <div class="icon" aria-hidden="true">
        <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">
          <rect x="3" y="11" width="18" height="11" rx="2" />
          <path d="M7 11V7a5 5 0 0 1 10 0v4" />
        </svg>
      </div>
      <h2 id="expired-title" class="title">Session expired</h2>
      <p class="text">Your session has timed out.</p>
      <p class="status" aria-live="polite">
        <span>Redirecting to login</span><span class="dots" aria-hidden="true"><span>.</span><span>.</span><span>.</span></span>
      </p>
    </div>
  </div>
{/if}

<style>
  .overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.55);
    backdrop-filter: blur(8px);
    -webkit-backdrop-filter: blur(8px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 9999;
    padding: var(--space-4);
    animation: fadeIn 0.25s ease;
  }

  @keyframes fadeIn {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes slideUp {
    from { opacity: 0; transform: translateY(12px) scale(0.98); }
    to { opacity: 1; transform: translateY(0) scale(1); }
  }

  .card {
    background: var(--color-surface-raised);
    border-radius: var(--radius-xl);
    padding: var(--space-8);
    max-width: 420px;
    width: 100%;
    text-align: center;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.25);
    animation: slideUp 0.3s cubic-bezier(0.22, 1, 0.36, 1);
  }

  .icon {
    margin-block-end: var(--space-4);
    display: flex;
    justify-content: center;
  }

  .title {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: var(--space-2);
  }

  .text {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    margin-block-end: var(--space-3);
  }

  .status {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
    display: inline-flex;
    align-items: baseline;
    justify-content: center;
    gap: 1px;
    margin: 0;
  }

  .dots {
    display: inline-flex;
    width: 1.25em;
    letter-spacing: 1px;
  }

  .dots span {
    opacity: 0.2;
    animation: dot-pulse 1.2s infinite;
  }

  .dots span:nth-child(2) { animation-delay: 0.2s; }
  .dots span:nth-child(3) { animation-delay: 0.4s; }

  @keyframes dot-pulse {
    0%, 60%, 100% { opacity: 0.2; }
    30% { opacity: 1; }
  }

  @media (prefers-reduced-motion: reduce) {
    .overlay { animation: none; }
    .card { animation: none; }
    .dots span { animation: none; opacity: 0.6; }
  }
</style>
