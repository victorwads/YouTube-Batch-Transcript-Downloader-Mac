const CACHE_KEY = 'cachedTranscriptByLink';

export function cacheKeyFor(urlString) {
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

export function readCache() {
  try {
    const raw = localStorage.getItem(CACHE_KEY);
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

export function getCachedTranscript(urlString) {
  const cache = readCache();
  return cache[cacheKeyFor(urlString)] || null;
}

export function saveCachedTranscript(urlString, transcript) {
  const cache = readCache();
  cache[cacheKeyFor(urlString)] = transcript;
  localStorage.setItem(CACHE_KEY, JSON.stringify(cache));
}
