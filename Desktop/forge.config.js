import fsp from 'node:fs/promises';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { FuseV1Options, FuseVersion } from '@electron/fuses';
import { FusesPlugin } from '@electron-forge/plugin-fuses';

const makers = [];

async function removeUnusedMacPermissions({ buildPath: appSourcePath, platform }) {
  if (platform !== 'darwin') return;
  const infoPath = path.resolve(appSourcePath, '..', '..', 'Info.plist');
  let source = await fsp.readFile(infoPath, 'utf8');
  const unusedKeys = [
    'NSAudioCaptureUsageDescription', 'NSBluetoothAlwaysUsageDescription',
    'NSBluetoothPeripheralUsageDescription', 'NSCameraUsageDescription',
    'NSMicrophoneUsageDescription'
  ];
  for (const key of unusedKeys) {
    source = source.replace(new RegExp(`\\s*<key>${key}</key>\\s*<string>[^<]*</string>`, 'g'), '');
  }
  await fsp.writeFile(infoPath, source);
}

async function signLocalMacBundle({ buildPath, platform }) {
  if (platform !== 'darwin' || process.env.APPLE_IDENTITY) return;
  const appPath = path.join(buildPath, 'Research Atlas.app');
  const signed = spawnSync('/usr/bin/codesign', ['--force', '--deep', '--sign', '-', appPath], { stdio: 'inherit' });
  if (signed.status !== 0) throw new Error(`Ad-hoc signing failed with status ${signed.status}.`);
  const verified = spawnSync('/usr/bin/codesign', ['--verify', '--deep', '--strict', appPath], { stdio: 'inherit' });
  if (verified.status !== 0) throw new Error(`Ad-hoc signature verification failed with status ${verified.status}.`);
}

if (process.platform === 'win32') {
  makers.push({
    name: '@electron-forge/maker-squirrel',
    config: {
      name: 'ResearchAtlas',
      setupExe: 'Research-Atlas-Setup.exe',
      setupIcon: 'assets/icon.ico',
      noMsi: true,
      ...(process.env.WINDOWS_CERTIFICATE_FILE ? {
        certificateFile: process.env.WINDOWS_CERTIFICATE_FILE,
        certificatePassword: process.env.WINDOWS_CERTIFICATE_PASSWORD
      } : {})
    }
  });
  makers.push({ name: '@electron-forge/maker-zip', platforms: ['win32'] });
}

if (process.platform === 'darwin') {
  makers.push({ name: '@electron-forge/maker-zip', platforms: ['darwin'] });
}

if (process.platform === 'linux') {
  makers.push({
    name: '@electron-forge/maker-deb',
    config: {
      options: {
        productName: 'Research Atlas',
        genericName: 'Research workspace',
        categories: ['Office', 'Education', 'Science'],
        maintainer: 'Research Atlas'
      }
    }
  });
  makers.push({ name: '@electron-forge/maker-rpm' });
  makers.push({ name: '@electron-forge/maker-zip', platforms: ['linux'] });
}

export default {
  packagerConfig: {
    name: 'Research Atlas',
    executableName: process.platform === 'darwin' ? 'Research Atlas' : 'research-atlas',
    appBundleId: 'app.researchatlas.desktop',
    appCategoryType: 'public.app-category.productivity',
    extendInfo: {
      NSAppTransportSecurity: {
        NSAllowsArbitraryLoads: false,
        NSAllowsLocalNetworking: true
      }
    },
    icon: process.platform === 'darwin'
      ? 'assets/icon.icns'
      : process.platform === 'win32' ? 'assets/icon.ico' : 'assets/icon.png',
    asar: true,
    asarIntegrityDigest: true,
    prune: true,
    afterInitialize: [removeUnusedMacPermissions],
    afterComplete: [signLocalMacBundle],
    ignore: [
      /^\/out($|\/)/,
      /^\/test($|\/)/,
      /^\/\.github($|\/)/,
      /^\/README\.md$/
    ],
    osxSign: process.env.APPLE_IDENTITY
      ? { identity: process.env.APPLE_IDENTITY, hardenedRuntime: true }
      : undefined,
    osxNotarize: process.env.APPLE_API_KEY
      ? {
          appleApiKey: process.env.APPLE_API_KEY,
          appleApiKeyId: process.env.APPLE_API_KEY_ID,
          appleApiIssuer: process.env.APPLE_API_ISSUER
        }
      : undefined
  },
  rebuildConfig: {},
  makers,
  plugins: [
    new FusesPlugin({
      version: FuseVersion.V1,
      [FuseV1Options.RunAsNode]: false,
      // The renderer never stores cookies. Leaving this off avoids touching macOS Keychain at launch.
      [FuseV1Options.EnableCookieEncryption]: false,
      [FuseV1Options.EnableNodeOptionsEnvironmentVariable]: false,
      [FuseV1Options.EnableNodeCliInspectArguments]: false,
      [FuseV1Options.EnableEmbeddedAsarIntegrityValidation]: true,
      [FuseV1Options.OnlyLoadAppFromAsar]: true,
      [FuseV1Options.GrantFileProtocolExtraPrivileges]: false
    })
  ]
};
