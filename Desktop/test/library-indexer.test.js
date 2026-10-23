import test from 'node:test';
import assert from 'node:assert/strict';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';
import { discoverPDFs, extractPdf, sha256File } from '../src/library-indexer.js';

function minimalPdf(text) {
  const stream = `BT /F1 12 Tf 72 720 Td (${text}) Tj ET`;
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    `<< /Length ${Buffer.byteLength(stream)} >>\nstream\n${stream}\nendstream`
  ];
  let source = '%PDF-1.4\n';
  const offsets = [0];
  objects.forEach((object, index) => {
    offsets.push(Buffer.byteLength(source));
    source += `${index + 1} 0 obj\n${object}\nendobj\n`;
  });
  const xref = Buffer.byteLength(source);
  source += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  source += offsets.slice(1).map((offset) => `${String(offset).padStart(10, '0')} 00000 n \n`).join('');
  source += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return source;
}

test('folder discovery is recursive, deterministic, and ignores hidden and linked files', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'research-atlas-library-'));
  try {
    fs.mkdirSync(path.join(root, 'Methods'));
    fs.mkdirSync(path.join(root, '.private'));
    fs.mkdirSync(path.join(root, 'Ignore.app'));
    fs.writeFileSync(path.join(root, 'B.PDF'), 'second');
    fs.writeFileSync(path.join(root, 'Methods', 'A.pdf'), 'first');
    fs.writeFileSync(path.join(root, '.private', 'hidden.pdf'), 'hidden');
    fs.writeFileSync(path.join(root, 'Ignore.app', 'inside.pdf'), 'package');
    fs.writeFileSync(path.join(root, 'note.md'), 'ignore');
    try { fs.symlinkSync(path.join(root, 'Methods', 'A.pdf'), path.join(root, 'linked.pdf')); } catch {}
    const files = await discoverPDFs(root);
    assert.deepEqual(files.map((value) => path.relative(root, value)), ['B.PDF', path.join('Methods', 'A.pdf')]);
    assert.equal(await sha256File(files[0]), '16367aacb67a4a017c8da8ab95682ccb390863780f7114dda0a0e0c55644c7c4');
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
});

test('PDF.js extracts page text from a real PDF document', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'research-atlas-pdf-'));
  const pdfPath = path.join(directory, 'source.pdf');
  try {
    fs.writeFileSync(pdfPath, minimalPdf('Research Atlas provenance check'));
    const result = await extractPdf(pdfPath);
    assert.equal(result.pages.length, 1);
    assert.match(result.pages[0], /Research Atlas provenance check/);
    assert.equal(result.scanned, false);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});
