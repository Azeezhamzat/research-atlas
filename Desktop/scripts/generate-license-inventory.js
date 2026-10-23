import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const lock = JSON.parse(fs.readFileSync(path.join(root, 'package-lock.json'), 'utf8'));
const rows = [];
const seen = new Set();
const packagedDevelopmentDependencies = new Set(['electron']);

for (const [location, metadata] of Object.entries(lock.packages ?? {})) {
  if (!location || !metadata.version) continue;
  const marker = 'node_modules/';
  const name = location.includes(marker) ? location.slice(location.lastIndexOf(marker) + marker.length) : location;
  const record = {
    name,
    version: metadata.version,
    license: metadata.license ?? 'Not declared in lock metadata',
    developmentOnly: Boolean(metadata.dev) && !packagedDevelopmentDependencies.has(name)
  };
  const key = `${record.name}@${record.version}:${record.developmentOnly}`;
  if (!seen.has(key)) {
    seen.add(key);
    rows.push(record);
  }
}

rows.sort((left, right) => left.name.localeCompare(right.name) || left.version.localeCompare(right.version));
const lines = [
  '# Universal Client Third-Party Licence Inventory',
  '',
  'Generated from the exact `package-lock.json` used for Research Atlas. This inventory records SPDX identifiers when the package declares one; the package licence files remain the authoritative legal text.',
  '',
  `Generated dependency records: ${rows.length}.`,
  '',
  '| Package | Version | Licence | Use |',
  '| --- | --- | --- | --- |',
  ...rows.map((row) => `| ${row.name.replaceAll('|', '\\|')} | ${row.version} | ${String(row.license).replaceAll('|', '\\|')} | ${row.developmentOnly ? 'Build only' : 'Runtime'} |`),
  ''
];

fs.writeFileSync(path.join(root, 'THIRD_PARTY_LICENSE_INVENTORY.md'), lines.join('\n'), 'utf8');
