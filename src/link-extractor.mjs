const urlPattern = /https?:\/\/[^\s<>"']+/g;

export function extractEntries(text) {
  const items = [];
  const lines = String(text || '').split(/\r?\n/);

  for (const line of lines) {
    const matches = [...line.matchAll(urlPattern)];
    if (!matches.length) continue;

    for (const match of matches) {
      let candidate = match[0].trim();
      while (candidate && '.,;:)]}'.includes(candidate.at(-1))) {
        candidate = candidate.slice(0, -1);
      }

      let url;
      try {
        url = new URL(candidate);
      } catch {
        continue;
      }

      const prefix = line.slice(0, match.index).trim();
      const title = cleanTitle(prefix, items.length + 1);
      items.push({ title, url });
    }
  }

  return items;
}

export function extractLinks(text) {
  return extractEntries(text).map((entry) => entry.url);
}

function cleanTitle(prefix, fallbackIndex) {
  let title = String(prefix || '').trim();
  title = title.replace(/^\s*\d+\s*[\.\)]\s*/, '');
  title = title.replace(/[\-–—:|]+\s*$/, '').trim();
  return title || `Link ${fallbackIndex}`;
}
