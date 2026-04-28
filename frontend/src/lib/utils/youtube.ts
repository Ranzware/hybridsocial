// Recognize the public YouTube URL shapes we want to embed:
//   https://www.youtube.com/watch?v=ID
//   https://youtube.com/watch?v=ID
//   https://m.youtube.com/watch?v=ID
//   https://youtu.be/ID
//   https://www.youtube.com/shorts/ID
//   https://www.youtube.com/embed/ID
//   https://www.youtube.com/live/ID
// Returns the 11-char video ID, or null. Optional `t=` start offset
// (seconds) is preserved separately so the embed can resume there.

export interface YouTubeRef {
  id: string;
  start?: number;
}

const ID_RE = /^[A-Za-z0-9_-]{11}$/;

function parseStart(value: string | null): number | undefined {
  if (!value) return undefined;
  // YouTube accepts both "90" and "1m30s".
  if (/^\d+$/.test(value)) {
    const n = parseInt(value, 10);
    return n > 0 ? n : undefined;
  }
  const m = value.match(/^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$/);
  if (!m) return undefined;
  const [, h, mm, s] = m;
  const total = (parseInt(h ?? '0', 10) * 3600) + (parseInt(mm ?? '0', 10) * 60) + parseInt(s ?? '0', 10);
  return total > 0 ? total : undefined;
}

export function parseYouTubeUrl(raw: string): YouTubeRef | null {
  if (!raw || typeof raw !== 'string') return null;
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  const host = url.hostname.replace(/^www\./, '').toLowerCase();
  const start = parseStart(url.searchParams.get('t') ?? url.searchParams.get('start'));

  if (host === 'youtu.be') {
    const id = url.pathname.replace(/^\//, '').split('/')[0];
    return ID_RE.test(id) ? { id, start } : null;
  }

  if (host === 'youtube.com' || host === 'm.youtube.com' || host === 'music.youtube.com') {
    if (url.pathname === '/watch') {
      const id = url.searchParams.get('v') ?? '';
      return ID_RE.test(id) ? { id, start } : null;
    }
    const m = url.pathname.match(/^\/(?:embed|shorts|live|v)\/([^/?#]+)/);
    if (m && ID_RE.test(m[1])) return { id: m[1], start };
  }

  return null;
}

// Scan free-form post content (HTML or plain) for the first YouTube
// URL. We only need the first one — link previews are single-card.
export function findYouTubeInContent(content: string | null | undefined): YouTubeRef | null {
  if (!content) return null;
  const matches = content.match(/https?:\/\/[^\s<>"'`]+/g);
  if (!matches) return null;
  for (const candidate of matches) {
    const ref = parseYouTubeUrl(candidate);
    if (ref) return ref;
  }
  return null;
}

export function youtubeThumbnail(id: string): string {
  return `https://i.ytimg.com/vi/${id}/hqdefault.jpg`;
}

export function youtubeEmbedUrl(id: string, start?: number): string {
  const params = new URLSearchParams({ autoplay: '1', rel: '0', modestbranding: '1' });
  if (start && start > 0) params.set('start', String(start));
  return `https://www.youtube-nocookie.com/embed/${id}?${params.toString()}`;
}

export function youtubeWatchUrl(id: string, start?: number): string {
  return start && start > 0
    ? `https://www.youtube.com/watch?v=${id}&t=${start}s`
    : `https://www.youtube.com/watch?v=${id}`;
}
