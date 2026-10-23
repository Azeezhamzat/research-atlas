import { app, BrowserWindow, dialog, ipcMain, Menu, net, protocol, safeStorage, session, shell } from 'electron';
import started from 'electron-squirrel-startup';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { AtlasDatabase } from './database.js';
import { discoverPDFs, indexFiles } from './library-indexer.js';
import { normalizeConfiguration, PROVIDERS, runProvider } from './ai-provider.js';
import { assertId, cleanText } from './validation.js';

app.setName('Research Atlas');
if (started) app.quit();
if (process.platform === 'win32') app.setAppUserModelId('com.squirrel.ResearchAtlas.ResearchAtlas');
protocol.registerSchemesAsPrivileged([
  { scheme: 'atlas-app', privileges: { standard: true, secure: true, supportFetchAPI: true } },
  { scheme: 'atlas-pdf', privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true } }
]);

const moduleDirectory = path.dirname(fileURLToPath(import.meta.url));
const rendererDirectory = path.join(moduleDirectory, 'renderer');
const rendererAssets = new Set(['index.html', 'styles.css', 'app.js']);
let mainWindow;
let database;
const sessionSecrets = new Map();

const credentialFile = () => path.join(app.getPath('userData'), 'credentials.json');

function readCredentialBlobs() {
  try {
    const parsed = JSON.parse(fs.readFileSync(credentialFile(), 'utf8'));
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch { return {}; }
}

async function credentialSecurity(probe = false) {
  if (!probe) {
    return {
      available: true,
      backend: 'not-contacted',
      explanation: process.platform === 'linux'
        ? 'The Linux secret service is checked only when you choose Store securely. If none is active, use a session-only key.'
        : 'The operating-system credential store is contacted only after you choose Store securely or explicitly use a stored key.'
    };
  }
  const available = await safeStorage.isAsyncEncryptionAvailable();
  const backend = process.platform === 'linux' ? safeStorage.getSelectedStorageBackend() : 'operating-system';
  return {
    available: available && backend !== 'basic_text',
    backend,
    explanation: backend === 'basic_text'
      ? 'No supported Linux secret service is active. Persistent API-key storage is disabled; session-only keys still work.'
      : 'Persistent credentials are encrypted by the operating system and kept outside the research database.'
  };
}

async function loadCredential(provider) {
  if (sessionSecrets.has(provider)) return sessionSecrets.get(provider);
  const blobs = readCredentialBlobs();
  if (!blobs[provider]) return '';
  const security = await credentialSecurity(true);
  if (!security.available) return '';
  try {
    const encrypted = Buffer.from(blobs[provider], 'base64');
    const decrypted = await safeStorage.decryptStringAsync(encrypted);
    if (decrypted.shouldReEncrypt) await storeCredential(provider, decrypted.result, 'secure');
    return decrypted.result;
  } catch { return ''; }
}

async function storeCredential(provider, credential, mode) {
  if (!Object.hasOwn(PROVIDERS, provider)) throw new Error('Unsupported AI provider.');
  const value = cleanText(credential, 20_000);
  if (!value) throw new Error('Enter an API key first.');
  if (mode === 'session') {
    sessionSecrets.set(provider, value);
    return credentialStatus(provider);
  }
  const security = await credentialSecurity(true);
  if (!security.available) throw new Error(security.explanation);
  const blobs = readCredentialBlobs();
  blobs[provider] = (await safeStorage.encryptStringAsync(value)).toString('base64');
  fs.mkdirSync(path.dirname(credentialFile()), { recursive: true });
  fs.writeFileSync(credentialFile(), `${JSON.stringify(blobs, null, 2)}\n`, { mode: 0o600 });
  sessionSecrets.delete(provider);
  return credentialStatus(provider);
}

async function credentialStatus(provider) {
  const definition = PROVIDERS[provider] ?? PROVIDERS.ollama;
  const blobs = readCredentialBlobs();
  const security = await credentialSecurity(false);
  return {
    required: definition.credential,
    session: sessionSecrets.has(provider),
    persistent: Boolean(blobs[provider]),
    security
  };
}

async function removeCredential(provider) {
  sessionSecrets.delete(provider);
  const blobs = readCredentialBlobs();
  delete blobs[provider];
  if (Object.keys(blobs).length) {
    fs.writeFileSync(credentialFile(), `${JSON.stringify(blobs, null, 2)}\n`, { mode: 0o600 });
  } else {
    await fsp.rm(credentialFile(), { force: true });
  }
  return credentialStatus(provider);
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1500,
    height: 980,
    minWidth: 1040,
    minHeight: 700,
    show: false,
    title: 'Research Atlas',
    backgroundColor: '#111612',
    webPreferences: {
      preload: path.join(moduleDirectory, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      webSecurity: true,
      spellcheck: true
    }
  });
  mainWindow.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  mainWindow.webContents.on('will-navigate', (event, url) => {
    if (url !== mainWindow.webContents.getURL()) event.preventDefault();
  });
  const captureRoute = cleanText(process.env.RESEARCH_ATLAS_CAPTURE_ROUTE, 40);
  const applicationUrl = new URL('atlas-app://bundle/index.html');
  if (captureRoute) applicationUrl.searchParams.set('route', captureRoute);
  mainWindow.loadURL(applicationUrl.toString());
  mainWindow.once('ready-to-show', async () => {
    const capturePath = process.env.RESEARCH_ATLAS_CAPTURE_PATH;
    if (!capturePath) {
      mainWindow.show();
      return;
    }
    mainWindow.showInactive();
    const requestedDelay = Number.parseInt(process.env.RESEARCH_ATLAS_CAPTURE_DELAY_MS ?? '700', 10);
    const captureDelay = Number.isFinite(requestedDelay) ? Math.min(Math.max(requestedDelay, 250), 10_000) : 700;
    await new Promise((resolve) => setTimeout(resolve, captureDelay));
    const image = await mainWindow.webContents.capturePage();
    fs.writeFileSync(path.resolve(capturePath), image.toPNG());
    app.quit();
  });
}

function sendProgress(progress) {
  if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send('index:progress', progress);
}

function registerIpc() {
  ipcMain.handle('app:bootstrap', async () => ({
    platform: process.platform,
    versions: { app: app.getVersion(), electron: process.versions.electron, node: process.versions.node },
    userDataPath: app.getPath('userData'),
    providers: PROVIDERS,
    dashboard: database.dashboard(),
    provider: database.providerConfiguration(),
    credential: await credentialStatus(database.providerConfiguration().provider)
  }));
  ipcMain.handle('dashboard:get', () => database.dashboard());
  ipcMain.handle('resources:list', (_event, resource) => database.list(resource));
  ipcMain.handle('resources:save', (_event, resource, record) => database.save(resource, record));
  ipcMain.handle('resources:delete', (_event, resource, id) => database.delete(resource, id));
  ipcMain.handle('library:list', (_event, filters) => database.library(filters));
  ipcMain.handle('library:paper', (_event, id) => database.paper(id));
  ipcMain.handle('library:choose-files', async () => {
    const selected = await dialog.showOpenDialog(mainWindow, {
      title: 'Choose research PDFs', properties: ['openFile', 'multiSelections'],
      filters: [{ name: 'PDF documents', extensions: ['pdf'] }]
    });
    return selected.canceled ? [] : selected.filePaths;
  });
  ipcMain.handle('library:choose-folder', async () => {
    const selected = await dialog.showOpenDialog(mainWindow, {
      title: 'Choose a read-only research folder', properties: ['openDirectory']
    });
    return selected.canceled ? '' : selected.filePaths[0];
  });
  ipcMain.handle('library:index-files', async (_event, paths) => {
    if (!Array.isArray(paths) || paths.length > 10_000) throw new Error('Invalid PDF selection.');
    return indexFiles(database, paths.map((value) => cleanText(value, 20_000)), { onProgress: sendProgress });
  });
  ipcMain.handle('library:index-folder', async (_event, rootPath) => {
    const selectedRoot = path.resolve(cleanText(rootPath, 20_000));
    const files = await discoverPDFs(selectedRoot);
    return indexFiles(database, files, { rootPath: selectedRoot, onProgress: sendProgress });
  });
  ipcMain.handle('library:preview-url', (_event, id) => {
    const paper = database.paper(id);
    if (!paper.pdf_path || !fs.existsSync(paper.pdf_path)) throw new Error('The PDF is not available at its recorded location.');
    const documentName = encodeURIComponent(path.basename(paper.pdf_path));
    return `atlas-pdf://paper/${assertId(id, 'paper')}/${documentName}`;
  });
  ipcMain.handle('search:run', (_event, query, type) => database.search(query, type));
  ipcMain.handle('index:jobs', () => database.indexingJobs());

  ipcMain.handle('ai:get', async () => {
    const configuration = database.providerConfiguration();
    return { configuration, credential: await credentialStatus(configuration.provider), providers: PROVIDERS };
  });
  ipcMain.handle('ai:save', async (_event, raw) => {
    const config = normalizeConfiguration(raw);
    const stored = database.saveProviderConfiguration({
      provider: config.provider, endpoint: config.endpoint, model: config.model,
      external_transmission_enabled: config.externalTransmissionEnabled,
      maximum_passages: config.maximumPassages, maximum_output_tokens: config.maximumOutputTokens,
      reasoning_effort: config.reasoningEffort, local_runtime_idle_minutes: raw?.local_runtime_idle_minutes
    });
    return { configuration: stored, credential: await credentialStatus(config.provider) };
  });
  ipcMain.handle('ai:store-credential', (_event, provider, credential, mode) => storeCredential(provider, credential, mode));
  ipcMain.handle('ai:remove-credential', (_event, provider) => removeCredential(provider));
  ipcMain.handle('ai:test', async (_event, raw, transientCredential = '') => {
    const config = normalizeConfiguration(raw);
    const credential = cleanText(transientCredential, 20_000) || await loadCredential(config.provider);
    const response = await runProvider(config, credential, '', [], { test: true });
    return { ok: true, message: response || 'Connection succeeded.' };
  });
  ipcMain.handle('ai:preview', (_event, rawRequest) => {
    const config = normalizeConfiguration(database.providerConfiguration());
    const passages = database.evidenceForAi(rawRequest?.literatureIds, config.maximumPassages);
    return {
      provider: config.provider, model: config.model, endpoint: config.endpoint, local: config.local,
      query: cleanText(rawRequest?.query, 20_000), passages,
      characters: passages.reduce((sum, passage) => sum + passage.passage_text.length, 0)
    };
  });
  ipcMain.handle('ai:run', async (_event, rawRequest, transientCredential = '') => {
    const config = normalizeConfiguration(database.providerConfiguration());
    const query = cleanText(rawRequest?.query, 20_000);
    if (!query) throw new Error('Enter a research task or question.');
    const passages = database.evidenceForAi(rawRequest?.literatureIds, config.maximumPassages);
    const credential = cleanText(transientCredential, 20_000) || await loadCredential(config.provider);
    try {
      const response = await runProvider(config, credential, query, passages);
      const analysisId = database.recordAnalysis({
        kind: cleanText(rawRequest?.kind, 100) || 'Assistant', provider: config.provider,
        model: config.model, query, response, passages,
        targetType: cleanText(rawRequest?.targetType, 100) || null,
        targetId: rawRequest?.targetId && /^[0-9a-f-]{36}$/i.test(rawRequest.targetId) ? rawRequest.targetId : null
      });
      return { analysisId, response, passages };
    } catch (error) {
      database.recordAnalysis({ kind: 'Assistant', provider: config.provider, model: config.model,
        query, response: '', passages, error: error instanceof Error ? error.message : String(error) });
      throw error;
    }
  });
  ipcMain.handle('ai:history', () => database.analyses());

  ipcMain.handle('data:backup', async () => {
    const target = await dialog.showSaveDialog(mainWindow, {
      title: 'Back up Research Atlas database', defaultPath: `research-atlas-backup-${new Date().toISOString().slice(0, 10)}.sqlite3`,
      filters: [{ name: 'SQLite database', extensions: ['sqlite3'] }]
    });
    if (target.canceled || !target.filePath) return '';
    return database.backup(target.filePath);
  });
  ipcMain.handle('data:export', async () => {
    const target = await dialog.showSaveDialog(mainWindow, {
      title: 'Export portable research data', defaultPath: `research-atlas-export-${new Date().toISOString().slice(0, 10)}.json`,
      filters: [{ name: 'JSON', extensions: ['json'] }]
    });
    if (target.canceled || !target.filePath) return '';
    await fsp.writeFile(target.filePath, database.exportPortable(), 'utf8');
    return target.filePath;
  });
  ipcMain.handle('data:show-folder', () => shell.showItemInFolder(database.path));
  ipcMain.handle('external:open', (_event, url) => {
    const parsed = new URL(url);
    if (parsed.protocol !== 'https:') throw new Error('Only HTTPS links can be opened.');
    return shell.openExternal(parsed.toString());
  });
}

function installMenu() {
  const template = [
    ...(process.platform === 'darwin' ? [{ role: 'appMenu' }] : []),
    { label: 'File', submenu: [
      { label: 'Add PDFs…', accelerator: 'CmdOrCtrl+O', click: () => mainWindow?.webContents.send('command', 'add-pdfs') },
      { label: 'Add Research Folder…', accelerator: 'CmdOrCtrl+Shift+O', click: () => mainWindow?.webContents.send('command', 'add-folder') },
      { type: 'separator' }, { role: process.platform === 'darwin' ? 'close' : 'quit' }
    ] },
    { role: 'editMenu' },
    { label: 'View', submenu: [
      { label: 'Global Search', accelerator: 'CmdOrCtrl+K', click: () => mainWindow?.webContents.send('command', 'search') },
      { label: 'Learning Center', accelerator: 'CmdOrCtrl+?', click: () => mainWindow?.webContents.send('command', 'learning') },
      { type: 'separator' }, { role: 'reload' }, { role: 'toggleDevTools' }, { role: 'resetZoom' },
      { role: 'zoomIn' }, { role: 'zoomOut' }, { role: 'togglefullscreen' }
    ] },
    { role: 'windowMenu' },
    { label: 'Help', submenu: [
      { label: 'Learning Center', accelerator: 'F1', click: () => mainWindow?.webContents.send('command', 'learning') }
    ] }
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

app.whenReady().then(async () => {
  session.defaultSession.setPermissionCheckHandler(() => false);
  session.defaultSession.setPermissionRequestHandler((_webContents, _permission, callback) => callback(false));
  const databasePath = path.join(app.getPath('userData'), 'research-atlas.sqlite3');
  database = new AtlasDatabase(databasePath);
  protocol.handle('atlas-app', (request) => {
    try {
      const url = new URL(request.url);
      const asset = decodeURIComponent(url.pathname).replace(/^\/+/, '');
      if (url.hostname !== 'bundle' || !rendererAssets.has(asset)) return new Response('Not found', { status: 404 });
      return net.fetch(pathToFileURL(path.join(rendererDirectory, asset)).toString());
    } catch { return new Response('Invalid application request', { status: 400 }); }
  });
  protocol.handle('atlas-pdf', (request) => {
    try {
      const url = new URL(request.url);
      const id = url.pathname.split('/').filter(Boolean)[0];
      const paper = database.paper(id);
      if (!paper.pdf_path || !fs.existsSync(paper.pdf_path)) return new Response('PDF not found', { status: 404 });
      return net.fetch(pathToFileURL(paper.pdf_path).toString());
    } catch { return new Response('Invalid PDF request', { status: 400 }); }
  });
  registerIpc();
  installMenu();
  createWindow();
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
}).catch((error) => {
  dialog.showErrorBox('Research Atlas could not start', error instanceof Error ? error.message : String(error));
  app.quit();
});

app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
app.on('before-quit', () => database?.close());
