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

  // While the collector is still warming up (or a window happens to
  // catch a quiet period) a 2- or 3-point line gets drawn corner to
  // corner, which looks like noise. Suppress until we have enough
  // points to read as a trend.
  const MIN_POINTS = 5;

  let path = $derived.by(() => {
    if (!points || points.length < MIN_POINTS) return '';
    let min = Infinity;
    let max = -Infinity;
    for (const p of points) {
      if (p.v < min) min = p.v;
      if (p.v > max) max = p.v;
    }
    const range = max - min;

    // Y-axis padding: without it, any non-zero variation gets stretched
    // to the full sparkline height, so a 1-byte change in DB size
    // looks identical to a 10x spike. Floor the visible range at 5%
    // of |max| (or 1 if max is 0) so tiny noise reads as flat-ish.
    const headroom = Math.max(Math.abs(max) * 0.05, 1);
    const visibleRange = Math.max(range, headroom);
    const visibleMin = (min + max) / 2 - visibleRange / 2;

    const stepX = width / (points.length - 1);
    const coords = points.map((p, i) => ({
      x: i * stepX,
      y: height - ((p.v - visibleMin) / visibleRange) * height,
    }));

    // Catmull-Rom spline → cubic bezier conversion. Each segment's
    // control points are derived from the slope through the
    // neighbours of its endpoints, so the curve passes smoothly
    // through every sample without the kinks of straight polylines.
    // Endpoints clamp to themselves so the curve doesn't overshoot
    // before the first / after the last point.
    const tension = 1;
    let d = `M${coords[0].x.toFixed(1)},${coords[0].y.toFixed(1)} `;
    for (let i = 0; i < coords.length - 1; i++) {
      const p0 = coords[i - 1] ?? coords[i];
      const p1 = coords[i];
      const p2 = coords[i + 1];
      const p3 = coords[i + 2] ?? coords[i + 1];

      const cp1x = p1.x + ((p2.x - p0.x) / 6) * tension;
      const cp1y = p1.y + ((p2.y - p0.y) / 6) * tension;
      const cp2x = p2.x - ((p3.x - p1.x) / 6) * tension;
      const cp2y = p2.y - ((p3.y - p1.y) / 6) * tension;

      d +=
        `C${cp1x.toFixed(1)},${cp1y.toFixed(1)} ` +
        `${cp2x.toFixed(1)},${cp2y.toFixed(1)} ` +
        `${p2.x.toFixed(1)},${p2.y.toFixed(1)} `;
    }
    return d.trim();
  });

  let warmingUp = $derived(!!points && points.length > 0 && points.length < MIN_POINTS);
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
    <path
      d={path}
      fill="none"
      stroke={color}
      stroke-width="1.5"
      stroke-linejoin="round"
      stroke-linecap="round"
    />
  </svg>
{:else if warmingUp}
  <span class="sparkline-warmup" title="Collecting samples — needs ~5 minutes" aria-hidden="true">···</span>
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

  .sparkline-warmup {
    color: var(--color-text-tertiary);
    font-size: 1rem;
    letter-spacing: 2px;
    font-weight: 700;
  }
</style>
