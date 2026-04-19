import { writable } from 'svelte/store';
import type { ThemeConfig } from '$lib/api/types.js';
import { browser } from '$app/environment';

export const themeStore = writable<ThemeConfig | null>(null);

// Maps admin theme keys → the CSS custom properties the app actually
// reads. A single key can write to several properties when the app
// uses multiple aliases (e.g. color_primary_contrast flows into both
// --color-on-primary and --color-text-on-primary).
const PROPERTY_MAP: Record<string, string[]> = {
  color_primary: ['--color-primary'],
  color_primary_hover: ['--color-primary-hover'],
  color_primary_soft: ['--color-primary-soft'],
  color_primary_contrast: ['--color-on-primary', '--color-text-on-primary'],
  color_secondary: ['--color-secondary'],
  color_accent: ['--color-accent'],
  color_success: ['--color-success'],
  color_warning: ['--color-warning'],
  color_danger: ['--color-danger', '--color-error'],
  color_info: ['--color-info'],
  color_bg: ['--color-bg', '--color-background'],
  color_bg_wash: ['--color-bg-wash'],
  color_surface: ['--color-surface'],
  color_border: ['--color-border'],
  color_text: ['--color-text'],
  color_text_secondary: ['--color-text-secondary'],
  color_text_link: ['--color-text-link'],
  gradient_start: ['--gradient-start'],
  gradient_end: ['--gradient-end'],
  gradient_direction: ['--gradient-direction'],
  font_family: ['--font-sans'],
};

// border_radius (sharp/rounded/pill) and density (compact/comfortable/
// spacious) are discrete choices, not colors — applied as data
// attributes so the app's CSS can key off them if it wants.
const ATTR_KEYS: Array<keyof ThemeConfig> = ['border_radius', 'density'];

export function applyTheme(config: ThemeConfig | null): void {
  themeStore.set(config);
  if (!browser || !config) return;

  const root = document.documentElement;

  for (const [key, cssVars] of Object.entries(PROPERTY_MAP)) {
    const value = (config as Record<string, unknown>)[key];
    if (typeof value === 'string' && value !== '') {
      for (const v of cssVars) root.style.setProperty(v, value);
    }
  }

  for (const key of ATTR_KEYS) {
    const value = (config as Record<string, unknown>)[key as string];
    if (typeof value === 'string' && value !== '') {
      root.setAttribute(`data-${(key as string).replace('_', '-')}`, value);
    }
  }
}

export function clearTheme(): void {
  themeStore.set(null);
  if (!browser) return;

  const root = document.documentElement;
  for (const cssVars of Object.values(PROPERTY_MAP)) {
    for (const v of cssVars) root.style.removeProperty(v);
  }
  for (const key of ATTR_KEYS) {
    root.removeAttribute(`data-${(key as string).replace('_', '-')}`);
  }
}
