<script lang="ts">
  // Renders a URL with anti-phishing typography:
  //   - monospace font so look-alike characters (l/I/1, O/0) are
  //     easier to distinguish
  //   - registrable domain (eTLD+1) bolded + slightly darker
  //   - scheme / subdomain / path muted
  //   - IDN / punycode hosts decoded to Unicode with a muted
  //     "punycode:" hint below so the user can see both forms
  //   - safe wrapping (overflow-wrap: anywhere) so long URLs don't
  //     produce horizontal scroll, but domain is still visible
  //   - optional collapse of the path for very long URLs
  //
  // Host is lowercased (domains are case-insensitive); path / query /
  // fragment preserve original case (they're often significant).

  import { decodePunycodeHost } from '$lib/utils/punycode.js';

  let {
    url,
    collapsePathAt = 72
  }: {
    url: string;
    collapsePathAt?: number;
  } = $props();

  let expanded = $state(false);

  interface Parsed {
    valid: boolean;
    raw: string;
    scheme: string; // "https://"
    subdomain: string; // "en." or ""
    registrable: string; // "wikipedia.org"
    asciiHost: string | null; // "xn--paypa1-l2c.com" when different
    port: string; // ":8443" or ""
    path: string; // "/wiki/..."
    query: string; // "?a=b"
    hash: string; // "#section"
  }

  let parsed = $derived.by<Parsed>(() => parseUrl(url));
  let pathLen = $derived(parsed.path.length + parsed.query.length + parsed.hash.length);
  let pathIsLong = $derived(pathLen > collapsePathAt);

  // --- Parsing ---

  function parseUrl(raw: string): Parsed {
    if (!raw || typeof raw !== 'string') {
      return { valid: false, raw: raw || '', scheme: '', subdomain: '', registrable: '', asciiHost: null, port: '', path: '', query: '', hash: '' };
    }
    try {
      const u = new URL(raw);
      const asciiHost = u.hostname.toLowerCase(); // always punycode form
      const displayHost = decodePunycodeHost(asciiHost);
      const isIdn = displayHost !== asciiHost;

      const { subdomain, registrable } = splitHost(displayHost);

      return {
        valid: true,
        raw,
        scheme: u.protocol + '//',
        subdomain,
        registrable,
        asciiHost: isIdn ? asciiHost : null,
        port: u.port ? ':' + u.port : '',
        path: u.pathname,
        query: u.search,
        hash: u.hash
      };
    } catch {
      return { valid: false, raw, scheme: '', subdomain: '', registrable: '', asciiHost: null, port: '', path: '', query: '', hash: '' };
    }
  }

  // Split a hostname into "subdomain" + "registrable" (eTLD+1).
  // We don't ship the public suffix list (too large) — instead use a
  // heuristic that handles the common cases:
  //   - last label is ccTLD (len 2) AND second-to-last is a generic
  //     2-4 char label (co, com, net, org, ac, gov, edu…): treat
  //     last 3 labels as registrable
  //   - otherwise last 2 labels as registrable
  // Pathological cases (e.g. "amazonaws.com" / S3 buckets) will just
  // show a bigger bold section — conservative failure.
  function splitHost(host: string): { subdomain: string; registrable: string } {
    if (!host) return { subdomain: '', registrable: '' };

    // IP literal? Bold the whole thing.
    if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host) || host.startsWith('[')) {
      return { subdomain: '', registrable: host };
    }

    const labels = host.split('.');
    if (labels.length <= 2) return { subdomain: '', registrable: host };

    const last = labels[labels.length - 1];
    const secondLast = labels[labels.length - 2];
    const compoundSeconds = new Set(['co', 'com', 'net', 'org', 'ac', 'gov', 'edu', 'ne', 'or', 'go']);

    const regLabelCount =
      last.length === 2 && compoundSeconds.has(secondLast) && labels.length >= 3 ? 3 : 2;

    const registrable = labels.slice(-regLabelCount).join('.');
    const subdomain = labels.slice(0, -regLabelCount).join('.') + '.';
    return { subdomain, registrable };
  }

  function toggleExpand() {
    expanded = !expanded;
  }
</script>

{#if parsed.valid}
  <div class="safe-url">
    <div class="safe-url-line">
      <span class="safe-url-scheme">{parsed.scheme}</span>{#if parsed.subdomain}<span class="safe-url-subdomain">{parsed.subdomain}</span>{/if}<span class="safe-url-registrable">{parsed.registrable}</span>{#if parsed.port}<span class="safe-url-port">{parsed.port}</span>{/if}{#if pathIsLong && !expanded}<button
          type="button"
          class="safe-url-expand"
          onclick={toggleExpand}
          aria-expanded="false"
          aria-label="Show full URL path"
        >…</button>{:else}<span class="safe-url-path">{parsed.path}</span><span class="safe-url-path">{parsed.query}</span><span class="safe-url-path">{parsed.hash}</span>{#if pathIsLong && expanded}<button
          type="button"
          class="safe-url-collapse"
          onclick={toggleExpand}
          aria-expanded="true"
        >hide path</button>{/if}{/if}
    </div>

    {#if parsed.asciiHost}
      <div class="safe-url-punycode" aria-label="Internationalized domain punycode form">
        <span class="safe-url-puny-tag">punycode:</span>
        <span class="safe-url-puny-value">{parsed.asciiHost}</span>
      </div>
    {/if}
  </div>
{:else}
  <div class="safe-url safe-url-invalid">
    <span class="safe-url-path">{parsed.raw}</span>
  </div>
{/if}

<style>
  .safe-url {
    /* Monospace so look-alike characters (l/I/1, O/0, rn/m) are
       easier to tell apart. System-mono stack first to get the
       user's preferred glyph shapes. */
    font-family: ui-monospace, SFMono-Regular, SF Mono, Menlo, Consolas,
      'Liberation Mono', 'DejaVu Sans Mono', monospace;
    font-size: 0.875rem;
    line-height: 1.5;
    overflow-wrap: anywhere;
    word-break: break-word;
    max-width: 100%;
  }

  .safe-url-line {
    /* Single-line shape that wraps as needed. The label chips still
       flow together so the domain doesn't get orphaned. */
    display: inline;
  }

  /* Scheme: muted. Users rarely care whether it's https vs http for
     the purpose of identifying the site — they care about the domain. */
  .safe-url-scheme {
    color: var(--color-text-tertiary, #9ca3af);
  }

  /* Subdomain: slightly muted, smaller weight, so the eye skips to
     the registrable domain instead. */
  .safe-url-subdomain {
    color: var(--color-text-secondary, #6b7280);
  }

  /* Registrable domain (eTLD+1): bold + full-contrast text color.
     This is the anti-phishing anchor — it's what the user should
     verify. */
  .safe-url-registrable {
    color: var(--color-text, #111827);
    font-weight: 700;
  }

  .safe-url-port {
    color: var(--color-text-secondary, #6b7280);
  }

  .safe-url-path {
    color: var(--color-text-secondary, #6b7280);
  }

  /* Inline "…" toggle for long paths — compact, doesn't break line. */
  .safe-url-expand,
  .safe-url-collapse {
    display: inline;
    margin: 0 2px;
    padding: 0 6px;
    background: var(--color-surface-container, rgba(0, 0, 0, 0.06));
    border: none;
    border-radius: 6px;
    font-family: inherit;
    font-size: 0.75rem;
    color: var(--color-text-secondary, #6b7280);
    cursor: pointer;
  }

  .safe-url-expand:hover,
  .safe-url-collapse:hover {
    background: var(--color-surface-container-high, rgba(0, 0, 0, 0.1));
    color: var(--color-text, #111827);
  }

  .safe-url-punycode {
    margin-block-start: 6px;
    font-size: 0.75rem;
    color: var(--color-text-tertiary, #9ca3af);
  }

  .safe-url-puny-tag {
    opacity: 0.8;
  }

  .safe-url-puny-value {
    font-family: inherit; /* already monospace from parent */
  }

  .safe-url-invalid .safe-url-path {
    color: var(--color-danger, #ef4444);
  }
</style>
