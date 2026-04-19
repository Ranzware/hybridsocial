// Compact RFC 3492 punycode decoder, adapted to our single use case:
// hostname decoding for the anti-phishing modal. We don't need the
// encode side. No external dependency.
//
// The heavy lifting is `decodeLabel(input)` which takes a single
// `xn--…` label (WITHOUT the `xn--` prefix) and returns the Unicode
// form. `decodePunycodeHost(host)` splits on dots, decodes each
// `xn--` label individually, and rejoins.
//
// If anything in the input is malformed, we fall back to returning
// the input unchanged — the modal then just shows the punycode form,
// which is fine. We never throw.

const BASE = 36;
const TMIN = 1;
const TMAX = 26;
const SKEW = 38;
const DAMP = 700;
const INITIAL_BIAS = 72;
const INITIAL_N = 128;
const DELIMITER = '-';

function basicDigit(codePoint: number): number {
  // 0..9 → 26..35
  if (codePoint >= 0x30 && codePoint <= 0x39) return codePoint - 0x30 + 26;
  // A..Z → 0..25
  if (codePoint >= 0x41 && codePoint <= 0x5a) return codePoint - 0x41;
  // a..z → 0..25
  if (codePoint >= 0x61 && codePoint <= 0x7a) return codePoint - 0x61;
  return BASE;
}

function adapt(delta: number, numPoints: number, firstTime: boolean): number {
  let d = firstTime ? Math.floor(delta / DAMP) : delta >> 1;
  d += Math.floor(d / numPoints);
  let k = 0;
  while (d > ((BASE - TMIN) * TMAX) >> 1) {
    d = Math.floor(d / (BASE - TMIN));
    k += BASE;
  }
  return k + Math.floor(((BASE - TMIN + 1) * d) / (d + SKEW));
}

function decodeLabel(encoded: string): string {
  let n = INITIAL_N;
  let i = 0;
  let bias = INITIAL_BIAS;

  // Split on the last delimiter — everything before it is already
  // Unicode (basic code points copied verbatim); everything after
  // is the variable-length encoded section.
  const lastDelim = encoded.lastIndexOf(DELIMITER);
  const basic = lastDelim > 0 ? encoded.slice(0, lastDelim) : '';
  const output: number[] = [];

  for (let j = 0; j < basic.length; j++) {
    const cp = basic.charCodeAt(j);
    if (cp >= 0x80) throw new Error('non-basic code point in basic section');
    output.push(cp);
  }

  let index = lastDelim > 0 ? lastDelim + 1 : 0;
  while (index < encoded.length) {
    const oldi = i;
    let w = 1;
    for (let k = BASE; ; k += BASE) {
      if (index >= encoded.length) throw new Error('truncated input');
      const digit = basicDigit(encoded.charCodeAt(index++));
      if (digit >= BASE) throw new Error('invalid digit');
      if (digit > Math.floor((0x7fffffff - i) / w)) throw new Error('overflow');
      i += digit * w;
      const t = k <= bias ? TMIN : k >= bias + TMAX ? TMAX : k - bias;
      if (digit < t) break;
      if (w > Math.floor(0x7fffffff / (BASE - t))) throw new Error('overflow');
      w *= BASE - t;
    }

    const out = output.length + 1;
    bias = adapt(i - oldi, out, oldi === 0);

    if (Math.floor(i / out) > 0x7fffffff - n) throw new Error('overflow');
    n += Math.floor(i / out);
    i %= out;

    output.splice(i, 0, n);
    i++;
  }

  return String.fromCodePoint(...output);
}

/**
 * Decode a full hostname, label by label. Non-IDN labels pass through
 * unchanged. On any decode failure, returns the input verbatim —
 * callers then treat the host as already-ASCII and display it as-is.
 */
export function decodePunycodeHost(host: string): string {
  if (!host) return host;
  if (!host.includes('xn--')) return host;

  try {
    return host
      .split('.')
      .map((label) => {
        if (!label.toLowerCase().startsWith('xn--')) return label;
        return decodeLabel(label.slice(4));
      })
      .join('.');
  } catch {
    return host;
  }
}
