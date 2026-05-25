import { contextBridge, ipcRenderer } from 'electron';
import type { ExportResult } from './types.js';

contextBridge.exposeInMainWorld('electronAPI', {
  exportText: (text: string, suggestedName?: string): Promise<ExportResult> =>
    ipcRenderer.invoke('export-text', { text, suggestedName }),
});
