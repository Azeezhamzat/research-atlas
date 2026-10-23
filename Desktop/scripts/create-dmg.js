import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

if (process.platform !== 'darwin') process.exit(0);

const out = path.resolve('out');
const appBundle = fs.readdirSync(out, { withFileTypes: true })
  .filter((entry) => entry.isDirectory() && entry.name.startsWith('Research Atlas-darwin-'))
  .map((entry) => path.join(out, entry.name, 'Research Atlas.app'))
  .find((candidate) => fs.existsSync(candidate));

if (!appBundle) throw new Error('Packaged Research Atlas.app was not found. Run Electron Forge packaging first.');

const architecture = process.arch;
const version = JSON.parse(fs.readFileSync(path.resolve('package.json'), 'utf8')).version;
const outputDirectory = path.join(out, 'make', 'dmg', architecture);
const output = path.join(outputDirectory, `Research-Atlas-${version}-${architecture}.dmg`);
const staging = fs.mkdtempSync(path.join(os.tmpdir(), 'research-atlas-dmg-'));

try {
  fs.mkdirSync(outputDirectory, { recursive: true });
  fs.cpSync(appBundle, path.join(staging, 'Research Atlas.app'), { recursive: true });
  fs.symlinkSync('/Applications', path.join(staging, 'Applications'));
  fs.rmSync(output, { force: true });
  const result = spawnSync('/usr/bin/hdiutil', [
    'create', '-volname', 'Research Atlas', '-srcfolder', staging,
    '-ov', '-format', 'UDZO', output
  ], { stdio: 'inherit' });
  if (result.status !== 0) throw new Error(`hdiutil failed with status ${result.status}`);
  process.stdout.write(`Created ${output}\n`);
} finally {
  fs.rmSync(staging, { recursive: true, force: true });
}
