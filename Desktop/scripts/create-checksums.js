import crypto from 'node:crypto';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';

const makeDirectory = path.resolve('out', 'make');
const manifestPath = path.join(makeDirectory, 'SHA256SUMS.txt');

async function filesUnder(directory) {
  const entries = await fsp.readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(entries.map(async (entry) => {
    const target = path.join(directory, entry.name);
    if (entry.isDirectory()) return filesUnder(target);
    if (entry.isFile() && target !== manifestPath) return [target];
    return [];
  }));
  return nested.flat();
}

function digest(file) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('sha256');
    fs.createReadStream(file).on('error', reject).on('data', (chunk) => hash.update(chunk)).on('end', () => resolve(hash.digest('hex')));
  });
}

if (!fs.existsSync(makeDirectory)) throw new Error('No installer output was found under out/make.');
const files = (await filesUnder(makeDirectory)).sort();
if (!files.length) throw new Error('No release artifacts were found to checksum.');
const lines = [];
for (const file of files) {
  const relative = path.relative(makeDirectory, file).split(path.sep).join('/');
  lines.push(`${await digest(file)}  ${relative}`);
}
await fsp.writeFile(manifestPath, `${lines.join('\n')}\n`);
process.stdout.write(`Created ${manifestPath} for ${files.length} artifact(s).\n`);
