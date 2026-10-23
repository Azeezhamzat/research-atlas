const { contextBridge, ipcRenderer } = require('electron');

const invoke = (channel, ...args) => ipcRenderer.invoke(channel, ...args);

contextBridge.exposeInMainWorld('atlas', Object.freeze({
  bootstrap: () => invoke('app:bootstrap'),
  dashboard: () => invoke('dashboard:get'),
  resources: Object.freeze({
    list: (resource) => invoke('resources:list', resource),
    save: (resource, record) => invoke('resources:save', resource, record),
    delete: (resource, id) => invoke('resources:delete', resource, id)
  }),
  library: Object.freeze({
    list: (filters = {}) => invoke('library:list', filters),
    paper: (id) => invoke('library:paper', id),
    chooseFiles: () => invoke('library:choose-files'),
    chooseFolder: () => invoke('library:choose-folder'),
    indexFiles: (paths) => invoke('library:index-files', paths),
    indexFolder: (root) => invoke('library:index-folder', root),
    previewUrl: (id) => invoke('library:preview-url', id),
    onProgress: (handler) => {
      const listener = (_event, progress) => handler(progress);
      ipcRenderer.on('index:progress', listener);
      return () => ipcRenderer.removeListener('index:progress', listener);
    }
  }),
  search: (query, type = '') => invoke('search:run', query, type),
  indexingJobs: () => invoke('index:jobs'),
  ai: Object.freeze({
    get: () => invoke('ai:get'),
    save: (configuration) => invoke('ai:save', configuration),
    storeCredential: (provider, credential, mode) => invoke('ai:store-credential', provider, credential, mode),
    removeCredential: (provider) => invoke('ai:remove-credential', provider),
    test: (configuration, transientCredential = '') => invoke('ai:test', configuration, transientCredential),
    preview: (request) => invoke('ai:preview', request),
    run: (request, transientCredential = '') => invoke('ai:run', request, transientCredential),
    history: () => invoke('ai:history')
  }),
  data: Object.freeze({
    backup: () => invoke('data:backup'),
    export: () => invoke('data:export'),
    showFolder: () => invoke('data:show-folder')
  }),
  openExternal: (url) => invoke('external:open', url),
  onCommand: (handler) => {
    const listener = (_event, command) => handler(command);
    ipcRenderer.on('command', listener);
    return () => ipcRenderer.removeListener('command', listener);
  }
}));
