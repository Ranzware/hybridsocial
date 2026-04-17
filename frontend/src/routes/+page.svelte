<script lang="ts">
  import { goto } from '$app/navigation';
  import { browser } from '$app/environment';
  import { authStore } from '$lib/stores/auth.js';

  // Wait until the root layout's initAuth() resolves before picking
  // a destination — reading authStore synchronously on mount sends
  // every visitor to /login even when they have a valid session
  // cookie, because initialized is still false at that point.
  let decided = false;
  $effect(() => {
    if (!browser || decided) return;
    const unsub = authStore.subscribe((state) => {
      if (!state.initialized || decided) return;
      decided = true;
      goto(state.user ? '/home' : '/login', { replaceState: true });
      queueMicrotask(() => unsub());
    });
  });
</script>
