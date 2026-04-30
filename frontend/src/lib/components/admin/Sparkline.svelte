<script lang="ts">
  // Hand-rolled SVG sparkline. No external dep — the data shape is
  // simple (1h × ~60 points × 22 series) and a real chart lib would
  // dwarf the payload it renders. If the dashboard grows beyond a
  // single tab of small charts we can swap to uPlot.

  type Point = { t: string; v: number };

  let {
    points = [],
    width = 120,
    height = 28,
    color = 'var(--color-primary)',
  }: {
    points?: Point[];
    width?: number;
    height?: number;
    color?: string;
  } = $props();

  let path = $derived.by(() => {
    if (!points || points.length < 2) return '';
    let min = Infinity;
    let max = -Infinity;
    for (const p of points) {
      if (p.v < min) min = p.v;
      if (p.v > max) max = p.v;
    }
    // Flat series: draw a single horizontal line in the middle so
    // the chart shows "we have data, no movement" rather than
    // collapsing to a single dot at the top.
    if (min === max) {
      return `M0,${height / 2} L${width},${height / 2}`;
    }
    const range = max - min;
    const stepX = width / (points.length - 1);
    let d = '';
    for (let i = 0; i < points.length; i++) {
      const x = i * stepX;
      const y = height - ((points[i].v - min) / range) * height;
      d += (i === 0 ? 'M' : 'L') + x.toFixed(1) + ',' + y.toFixed(1) + ' ';
    }
    return d.trim();
  });
</script>

{#if path}
  <svg
    class="sparkline"
    {width}
    {height}
    viewBox="0 0 {width} {height}"
    preserveAspectRatio="none"
    aria-hidden="true"
  >
    <path d={path} fill="none" stroke={color} stroke-width="1.5" stroke-linejoin="round" />
  </svg>
{:else}
  <span class="sparkline-empty" aria-hidden="true">—</span>
{/if}

<style>
  .sparkline {
    display: block;
    overflow: visible;
  }

  .sparkline-empty {
    color: var(--color-text-tertiary);
    font-size: 0.75rem;
  }
</style>
