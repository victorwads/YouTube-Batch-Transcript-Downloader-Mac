import { extractEntries } from './link-extractor.js';
import { getCachedTranscript, saveCachedTranscript } from './transcript-cache.js';
import type { TranscriptInputItem, TranscriptResultItem } from './types.js';

const transcriptLabels = [
  'show transcript',
  'open transcript',
  'transcript',
  'mostrar transcrição',
  'mostrar transcricao',
  'exibir transcrição',
  'exibir transcricao',
  'abrir transcrição',
  'abrir transcricao',
];

const blockedKeywords = [
  'video unavailable',
  'this video is unavailable',
  'restricted',
  'blocked',
  'conteúdo indisponível',
  'conteudo indisponivel',
  'vídeo indisponível',
  'video indisponivel',
];

const webviewScript = `
void (async () => {
  window.__codexTranscriptResult = '__PENDING__';
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const normalize = (value) => (value || '').replace(/\\s+/g, ' ').trim().toLowerCase();
  const textOf = (node) => (node && typeof node.innerText === 'string') ? node.innerText.trim() : '';
  const normalizeTimestamp = (raw) => {
    const cleaned = (raw || '').trim();
    if (!cleaned) return '';

    const parts = cleaned
      .split(':')
      .map((part) => part.replace(/\\D/g, ''))
      .filter((part) => part.length > 0);

    if (parts.length < 2 || parts.length > 3) return '';

    const numbers = parts.map((part) => Number.parseInt(part, 10));
    if (numbers.some((value) => Number.isNaN(value))) return '';

    const [hours, minutes, seconds] = parts.length === 3
      ? numbers
      : [0, numbers[0], numbers[1]];

    return [
      String(hours).padStart(3, '0'),
      String(minutes).padStart(2, '0'),
      String(seconds).padStart(2, '0')
    ].join(':');
  };
  const extractStructuredTranscript = () => {
    const segments = Array.from(document.querySelectorAll('transcript-segment-view-model'));
    if (!segments.length) return '';

    const lines = segments.map((segment) => {
      const timestampNode = segment.querySelector('div[class*="Timestamp"]:not([class*="A11yLabel"])');
      const textNode = segment.querySelector('span');
      const timestamp = normalizeTimestamp(textOf(timestampNode));
      const text = textOf(textNode);

      if (!timestamp || !text) return '';
      return \`\${timestamp} \${text}\`;
    }).filter(Boolean);

    return lines.join('\\n').trim();
  };
  const transcriptLabels = ${JSON.stringify(transcriptLabels)};

  const waitFor = async (predicate, timeoutMs, intervalMs = 250) => {
    const startedAt = Date.now();
    while (Date.now() - startedAt < timeoutMs) {
      const value = predicate();
      if (value) {
        return value;
      }
      await sleep(intervalMs);
    }
    return null;
  };

  const findTranscriptButton = () => {
    const buttons = Array.from(document.querySelectorAll([
      'button',
      'tp-yt-paper-button',
      'ytd-button-renderer button',
      'ytd-menu-service-item-renderer button',
      'ytd-menu-navigation-item-renderer button'
    ].join(',')));

    return buttons.find((button) => {
      const signature = [
        button.textContent,
        button.getAttribute('aria-label'),
        button.title
      ].map(normalize).join(' ');

      return transcriptLabels.some((label) => signature.includes(label));
    }) || null;
  };

  await waitFor(() => document.readyState === 'complete' ? 'ready' : '', 15000);
  await waitFor(() => document.getElementById('info-container') ? 'info' : '', 15000);

  const pageText = normalize(document.body?.innerText || '');
  if (${JSON.stringify(blockedKeywords)}.some((keyword) => pageText.includes(keyword))) {
    window.__codexTranscriptResult = '__SITE_BLOCKED__';
    return;
  }

  document.getElementById('info-container')?.click();
  await sleep(1200);

  const transcriptButton = await waitFor(findTranscriptButton, 15000);
  if (!transcriptButton) {
    window.__codexTranscriptResult = '__TRANSCRIPT_BUTTON_NOT_FOUND__';
    return;
  }

  transcriptButton.click();
  await sleep(1500);

  const structuredTranscript = await waitFor(() => {
    const structured = extractStructuredTranscript();
    if (structured) {
      return structured;
    }
    return '';
  }, 20000);

  if (structuredTranscript) {
    window.__codexTranscriptResult = structuredTranscript;
    return;
  }

  const transcriptText = await waitFor(() => {
    const node = document.getElementsByTagName('yt-item-section-renderer')[0];
    const text = textOf(node);
    return text ? text : '';
  }, 5000);

  if (!transcriptText) {
    window.__codexTranscriptResult = '__TRANSCRIPT_NOT_FOUND__';
    return;
  }

  window.__codexTranscriptResult = transcriptText;
})();
`;

type WebviewSlot = {
  index: number;
  card: HTMLElement;
  titleEl: HTMLElement;
  urlEl: HTMLElement;
  statusEl: HTMLElement;
  webview: HTMLWebViewElement;
  slotName: string;
  currentItem: TranscriptInputItem | null;
};

type TranscriptRunState = {
  canceled: boolean;
  active: boolean;
  results: TranscriptResultItem[];
  items: TranscriptInputItem[];
  progress: number;
  retryItems: TranscriptInputItem[];
};

type SlotResolver = (slot: WebviewSlot | null) => void;

class WebviewSlotPool {
  private available: WebviewSlot[] = [];
  private waiters: SlotResolver[] = [];

  constructor(slots: WebviewSlot[]) {
    this.available = [...slots].reverse();
  }

  acquire(): Promise<WebviewSlot | null> {
    const slot = this.available.pop();
    if (slot) return Promise.resolve(slot);

    return new Promise<WebviewSlot | null>((resolve) => {
      this.waiters.push(resolve);
    });
  }

  release(slot: WebviewSlot): void {
    const waiter = this.waiters.shift();
    if (waiter) {
      waiter(slot);
      return;
    }

    this.available.push(slot);
  }

  cancel(): void {
    while (this.waiters.length) {
      this.waiters.shift()?.(null);
    }
  }
}

const state: TranscriptRunState = {
  canceled: false,
  active: false,
  results: [],
  items: [],
  progress: 0,
  retryItems: [],
};

let slotPool: WebviewSlotPool;
let slots: WebviewSlot[] = [];

const linksTextArea = document.getElementById('links-input') as HTMLTextAreaElement;
const extractedList = document.getElementById('extracted-list') as HTMLDivElement;
const resultsList = document.getElementById('results-list') as HTMLDivElement;
const statusText = document.getElementById('status-text') as HTMLSpanElement;
const progressBar = document.getElementById('progress-bar') as HTMLProgressElement;
const processButton = document.getElementById('process-button') as HTMLButtonElement;
const stopButton = document.getElementById('stop-button') as HTMLButtonElement;
const clearButton = document.getElementById('clear-button') as HTMLButtonElement;
const exportButton = document.getElementById('export-button') as HTMLButtonElement;
const outputTextArea = document.getElementById('output-text') as HTMLTextAreaElement;
const webviewsContainer = document.getElementById('webviews-grid') as HTMLDivElement;

function init(): void {
  slots = Array.from({ length: 6 }, (_, index) => createSlot(index));
  slotPool = new WebviewSlotPool(slots);

  renderExtractedItems();
  renderResults();
  renderSlots();
  updateHeader('Ready.');
  updateButtons();

  linksTextArea.addEventListener('input', () => {
    renderExtractedItems();
  });

  processButton.addEventListener('click', () => {
    void startProcessing();
  });

  stopButton.addEventListener('click', cancelProcessing);
  clearButton.addEventListener('click', () => {
    clearOutput();
  });
  exportButton.addEventListener('click', () => {
    void exportToTxt();
  });
}

function createSlot(index: number): WebviewSlot {
  const card = document.createElement('section');
  card.className = 'webview-card';

  const header = document.createElement('div');
  header.className = 'webview-card-header';

  const titleWrap = document.createElement('div');
  titleWrap.className = 'webview-card-title-wrap';

  const titleEl = document.createElement('div');
  titleEl.className = 'webview-card-title';
  titleEl.textContent = `WebView ${index + 1}`;

  const statusEl = document.createElement('div');
  statusEl.className = 'webview-card-status';
  statusEl.textContent = 'Free';

  titleWrap.append(titleEl, statusEl);

  const urlEl = document.createElement('div');
  urlEl.className = 'webview-card-url';
  urlEl.textContent = '';

  header.append(titleWrap);

  const webview = document.createElement('webview') as HTMLWebViewElement;
  webview.className = 'webview';
  webview.setAttribute('partition', `persist:yt-batch-${index}`);
  webview.setAttribute('allowpopups', 'true');
  webview.setAttribute('webpreferences', 'contextIsolation=yes, javascript=yes');

  card.append(header, urlEl, webview);
  webviewsContainer.appendChild(card);

  return {
    index,
    card,
    titleEl,
    urlEl,
    statusEl,
    webview,
    slotName: `WebView ${index + 1}`,
    currentItem: null,
  };
}

function renderSlots(): void {
  for (const slot of slots) {
    slot.titleEl.textContent = slot.currentItem?.title || slot.slotName;
    slot.urlEl.textContent = slot.currentItem?.url || '';
  }
}

function renderExtractedItems(): void {
  const items = extractEntries(linksTextArea.value);
  extractedList.replaceChildren();

  if (items.length === 0) {
    extractedList.appendChild(createEmptyState('No links detected yet.'));
    return;
  }

  for (const [index, item] of items.entries()) {
    extractedList.appendChild(createItemBlock(`${index + 1}. ${item.title}`, item.url));
  }
}

function renderResults(): void {
  resultsList.replaceChildren();

  const ordered = [...state.results].sort((a, b) => a.order - b.order);
  outputTextArea.value = ordered.map((entry) => formatBlock(entry.title, entry.url, entry.transcript)).join('\n\n');

  if (ordered.length === 0) {
    resultsList.appendChild(createEmptyState('No transcripts generated yet.'));
    return;
  }

  for (const [index, item] of ordered.entries()) {
    const block = document.createElement('article');
    block.className = 'result-card';

    const heading = document.createElement('h3');
    heading.textContent = `${index + 1}. ${item.title}`;

    const url = document.createElement('div');
    url.className = 'result-url';
    url.textContent = item.url;

    const transcript = document.createElement('pre');
    transcript.className = 'result-transcript';
    transcript.textContent = item.transcript;

    block.append(heading, url, transcript);
    resultsList.appendChild(block);
  }
}

function createEmptyState(text: string): HTMLElement {
  const el = document.createElement('div');
  el.className = 'empty-state';
  el.textContent = text;
  return el;
}

function createItemBlock(title: string, url: string): HTMLElement {
  const block = document.createElement('div');
  block.className = 'item-block';

  const titleEl = document.createElement('div');
  titleEl.className = 'item-title';
  titleEl.textContent = title;

  const urlEl = document.createElement('div');
  urlEl.className = 'item-url';
  urlEl.textContent = url;

  block.append(titleEl, urlEl);
  return block;
}

function updateHeader(message: string): void {
  statusText.textContent = message;
}

function updateButtons(): void {
  processButton.disabled = state.active;
  stopButton.disabled = !state.active;
  clearButton.disabled = state.active;
  exportButton.disabled = state.results.length === 0;
}

async function startProcessing(): Promise<void> {
  if (state.active) return;

  const items = extractEntries(linksTextArea.value);
  state.items = items;
  state.results = [];
  state.progress = 0;
  state.retryItems = [];
  state.canceled = false;
  state.active = true;

  renderExtractedItems();
  renderResults();
  updateButtons();
  updateHeader(items.length ? `Starting batch with ${items.length} links...` : 'Paste at least one valid link.');

  if (items.length === 0) {
    state.active = false;
    updateButtons();
    return;
  }

  try {
    await processBatch(items);
    if (!state.canceled && state.retryItems.length > 0) {
      updateHeader(`Retrying ${state.retryItems.length} failed links...`);
      const retryTargets = dedupeRetryTargets(state.retryItems, state.results);
      state.retryItems = [];
      if (retryTargets.length > 0) {
        await processBatch(retryTargets);
      }
    }
  } finally {
    state.active = false;
    updateButtons();
    updateHeader(state.canceled ? 'Processing stopped.' : 'Done.');
    renderResults();
  }
}

function cancelProcessing(): void {
  state.canceled = true;
  slotPool.cancel();
  for (const slot of slots) {
    try {
      slot.webview.stop();
    } catch {
      // Ignore: calling webview methods before dom-ready throws in Electron.
    }
    slot.statusEl.textContent = 'Stopped';
  }
  state.active = false;
  updateButtons();
  updateHeader('Processing stopped.');
}

function clearOutput(): void {
  if (state.active) return;

  state.results = [];
  state.progress = 0;
  outputTextArea.value = '';
  renderResults();
  updateButtons();
  updateHeader('Results cleared.');
}

async function processItem(item: TranscriptInputItem): Promise<void> {
  if (state.canceled) return;

  updateHeader(`Preparing ${item.title}`);

  if (!isSupportedYouTubeURL(item.url)) {
    appendResult({
      ...item,
      transcript: 'ERRO: Not YouTube.',
    });
    return;
  }

  const cached = getCachedTranscript(item.url);
  if (cached) {
    appendResult({
      ...item,
      transcript: cached,
    });
    return;
  }

  const slot = await slotPool.acquire();
  if (!slot || state.canceled) return;

  slot.currentItem = item;
  slot.titleEl.textContent = item.title;
  slot.urlEl.textContent = item.url;
  slot.statusEl.textContent = 'Loading...';
  renderSlots();

  try {
    await loadSlot(slot, item.url);
    if (state.canceled) return;

    slot.statusEl.textContent = 'Extracting...';
    const transcript = await extractTranscript(slot.webview);
    if (state.canceled) return;

    saveCachedTranscript(item.url, transcript);
    appendResult({
      ...item,
      transcript,
    });
    slot.statusEl.textContent = 'Done';
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const transcript = `ERRO: ${message}`;
    appendResult({
      ...item,
      transcript,
    });
    state.retryItems = upsertRetryItem(state.retryItems, item);
    slot.statusEl.textContent = 'Error';
  } finally {
    slotPool.release(slot);
  }
}

async function processBatch(items: TranscriptInputItem[]): Promise<void> {
  const tasks = items.map((item) => processItem(item));
  await Promise.all(tasks);
}

function appendResult(result: TranscriptResultItem): void {
  state.results = upsertResult(state.results, result);
  state.progress = state.items.length === 0 ? 0 : state.results.length / state.items.length;
  renderResults();
  updateHeader(`Processed ${state.results.length}/${state.items.length}`);
}

function upsertResult(results: TranscriptResultItem[], nextResult: TranscriptResultItem): TranscriptResultItem[] {
  const withoutSameOrder = results.filter((result) => result.order !== nextResult.order);
  return [...withoutSameOrder, nextResult].sort((a, b) => a.order - b.order);
}

function upsertRetryItem(items: TranscriptInputItem[], nextItem: TranscriptInputItem): TranscriptInputItem[] {
  const withoutSameOrder = items.filter((item) => item.order !== nextItem.order);
  return [...withoutSameOrder, nextItem].sort((a, b) => a.order - b.order);
}

function dedupeRetryTargets(
  retryItems: TranscriptInputItem[],
  results: TranscriptResultItem[],
): TranscriptInputItem[] {
  const successfulOrders = new Set(
    results
      .filter((result) => !result.transcript.startsWith('ERRO:'))
      .map((result) => result.order),
  );

  return retryItems.filter((item) => !successfulOrders.has(item.order));
}

function loadSlot(slot: WebviewSlot, url: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const webview = slot.webview;
    let didFinishLoad = false;
    let didDomReady = false;
    let settled = false;

    const cleanup = () => {
      webview.removeEventListener('did-finish-load', onFinish);
      webview.removeEventListener('did-fail-load', onFail);
      webview.removeEventListener('dom-ready', onDomReady);
    };

    const maybeResolve = () => {
      if (settled || !didFinishLoad || !didDomReady) return;
      settled = true;
      cleanup();
      resolve();
    };

    const onDomReady = () => {
      didDomReady = true;
      maybeResolve();
    };

    const onFinish = () => {
      didFinishLoad = true;
      maybeResolve();
    };

    const onFail = (event: Event) => {
      const detail = event as Event & { errorCode?: number; errorDescription?: string };
      settled = true;
      cleanup();
      reject(new Error(detail.errorDescription || `Load failed (${detail.errorCode ?? 0})`));
    };

    webview.addEventListener('did-finish-load', onFinish);
    webview.addEventListener('dom-ready', onDomReady);
    webview.addEventListener('did-fail-load', onFail as EventListener);
    // Use `src` instead of `loadURL()` to avoid calling webview methods before it's attached.
    webview.setAttribute('src', url);
  });
}

async function extractTranscript(webview: HTMLWebViewElement): Promise<string> {
  await waitForWebviewScriptReady(webview);
  await webview.executeJavaScript(`window.__codexTranscriptResult = '__PENDING__';`);
  await webview.executeJavaScript(webviewScript);

  const started = Date.now();
  while (Date.now() - started < 25000) {
    if (state.canceled) throw new Error('Canceled');

    const result = await webview.executeJavaScript(`window.__codexTranscriptResult || ''`);
    const text = String(result || '').trim();

    if (text && text !== '__PENDING__') {
      if (text === '__SITE_BLOCKED__') throw new Error('Site blocked.');
      if (text === '__TRANSCRIPT_BUTTON_NOT_FOUND__') throw new Error('Transcript button not found.');
      if (text === '__TRANSCRIPT_NOT_FOUND__') throw new Error('Transcript not found.');
      return text;
    }

    await delay(300);
  }

  throw new Error('Transcript not found.');
}

async function waitForWebviewScriptReady(webview: HTMLWebViewElement, timeoutMs = 10000): Promise<void> {
  const startedAt = Date.now();
  let lastError: unknown = null;

  while (Date.now() - startedAt < timeoutMs) {
    if (state.canceled) throw new Error('Canceled');

    try {
      await webview.executeJavaScript('1');
      return;
    } catch (error) {
      lastError = error;
      const message = error instanceof Error ? error.message : String(error);
      const isDomReadyRace = /dom-ready|attached to the DOM/i.test(message);

      if (!isDomReadyRace) {
        throw error;
      }

      await delay(120);
    }
  }

  const fallbackMessage = lastError instanceof Error ? lastError.message : 'WebView not ready.';
  throw new Error(fallbackMessage);
}

function isSupportedYouTubeURL(url: string): boolean {
  try {
    const parsed = new URL(url);
    const host = parsed.host.toLowerCase();
    return host.includes('youtube.com') || host.includes('youtu.be');
  } catch {
    return false;
  }
}

function formatBlock(title: string, url: string, transcript: string): string {
  return `TITLE:\n${title}\n\nLINK:\n${url}\n\nTRANSCRIPT:\n${transcript}`;
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function exportToTxt(): Promise<void> {
  const text = outputTextArea.value.trim();
  if (!text) {
    updateHeader('No transcript to export.');
    return;
  }

  const response = await window.electronAPI.exportText(text, 'transcriptions.txt');
  if (response.canceled) {
    updateHeader('Export canceled.');
    return;
  }

  updateHeader(`Exported to ${response.filePath ?? 'file'}.`);
}

window.addEventListener('DOMContentLoaded', init);
