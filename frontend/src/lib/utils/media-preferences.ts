// Media display preferences. Currently one knob: whether remote
// media should auto-load with the post, or stay as a tap-to-load
// placeholder. Local uploads always auto-load — they're served from
// our own origin and the user already paid that bandwidth cost.
//
// Stored in localStorage only. Default is ON (auto-load) so the
// out-of-the-box experience matches user expectations; disabling is
// an opt-in for users on metered data.

import { writable, type Writable } from 'svelte/store';

const STORAGE_KEY = 'hs:auto_load_remote_media';

function isBrowser(): boolean {
  return typeof window !== 'undefined' && typeof window.localStorage !== 'undefined';
}

function readStored(): boolean {
  if (!isBrowser()) return true;
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (raw === null) return true;
    return raw !== '0';
  } catch {
    return true;
  }
}

/** Reactive store other components can subscribe to so toggling the
 *  setting in /settings/privacy takes effect immediately on every
 *  visible LazyMedia without needing a refresh. */
export const autoLoadRemoteMedia: Writable<boolean> = writable(readStored());

export function isAutoLoadRemoteMedia(): boolean {
  return readStored();
}

export function setAutoLoadRemoteMedia(enabled: boolean): void {
  if (!isBrowser()) return;
  try {
    window.localStorage.setItem(STORAGE_KEY, enabled ? '1' : '0');
  } catch {
    // Quota exceeded / disabled — silently drop.
  }
  autoLoadRemoteMedia.set(enabled);
}
