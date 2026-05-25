import type { ExportResult } from './types.js';

declare global {
  interface Window {
    electronAPI: {
      exportText(text: string, suggestedName?: string): Promise<ExportResult>;
    };
  }

  interface HTMLWebViewElement extends HTMLElement {
    loadURL(url: string): void;
    executeJavaScript(code: string): Promise<unknown>;
    stop(): void;
  }
}

export {};
