const CACHE_KEY = 'cachedTranscriptByLink';

export function cacheKeyFor(urlString: string): string {
  try {
    const url = new URL(urlString);
    const host = (url.host || '').toLowerCase();

    if (host.includes('youtu.be')) {
      const videoID = url.pathname.split('/').filter(Boolean)[0] || '';
      return videoID ? `youtube:${videoID}` : urlString;
    }

    if (host.includes('youtube.com')) {
      const videoID = url.searchParams.get('v');
      if (videoID) {
        return `youtube:${videoID}`;
      }
    }
  } catch {
    return urlString;
  }

  return urlString;
}

export function readCache(): Record<string, string> {
  try {
    const raw = localStorage.getItem(CACHE_KEY);
    return raw ? (JSON.parse(raw) as Record<string, string>) : {};
  } catch {
    return {};
  }
}

export function getCachedTranscript(urlString: string): string | null {
  const cache = readCache();
  return cache[cacheKeyFor(urlString)] || null;
}

export function saveCachedTranscript(urlString: string, transcript: string): void {
  const cache = readCache();
  cache[cacheKeyFor(urlString)] = transcript;
  localStorage.setItem(CACHE_KEY, JSON.stringify(cache));
}
