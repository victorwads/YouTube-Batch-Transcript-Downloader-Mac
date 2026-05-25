const { app, BrowserWindow, dialog, ipcMain } = require('electron');
const fs = require('fs/promises');
const path = require('path');

const isMac = process.platform === 'darwin';

function createWindow() {
  const win = new BrowserWindow({
    width: 1500,
    height: 980,
    minWidth: 1300,
    minHeight: 860,
    title: 'YouTube Transcript Batch Mac',
    backgroundColor: '#f4f1eb',
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      webviewTag: true,
      sandbox: false,
      backgroundThrottling: false,
    },
  });

  win.loadFile(path.join(__dirname, 'index.html'));
  return win;
}

app.setName('YouTube Transcript Batch Mac');

app.whenReady().then(() => {
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on('window-all-closed', () => {
  if (!isMac) {
    app.quit();
  }
});

ipcMain.handle('export-text', async (_event, { text, suggestedName }) => {
  const response = await dialog.showSaveDialog({
    title: 'Export transcript',
    defaultPath: suggestedName || 'transcriptions.txt',
    filters: [{ name: 'Text', extensions: ['txt'] }],
  });

  if (response.canceled || !response.filePath) {
    return { canceled: true };
  }

  await fs.writeFile(response.filePath, text, 'utf8');
  return { canceled: false, filePath: response.filePath };
});
