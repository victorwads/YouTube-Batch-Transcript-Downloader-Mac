const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  exportText: (text, suggestedName) => ipcRenderer.invoke('export-text', { text, suggestedName }),
});
