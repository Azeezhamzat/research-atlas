# Research Atlas Universal Desktop

This is the cross-platform Research Atlas client for macOS, Windows, and Linux. It uses the same schema version as the existing native macOS client and keeps all research data in a local SQLite database.

End users should follow the root [installation guide](../INSTALL.md) and [universal user guide](../UNIVERSAL_USER_GUIDE.md). Contributors need Node.js 24.15 or newer:

```sh
npm ci
npm test
npm start
```

Build the installer for the computer you are using:

```sh
npm run make
```

`npm run licenses` regenerates the locked dependency inventory shipped with the client.

Electron Forge produces platform-specific packages. Windows packages must be built on Windows, macOS packages on macOS, and Linux packages on Linux. The repository workflow builds Apple-silicon/Intel macOS, x64/ARM64 Windows, and x64/ARM64 Linux independently.

The renderer has no Node.js access. All filesystem, database, network, credential, and shell operations are exposed through narrow validated IPC methods in `preload.cjs`. PDF source folders are read-only.
