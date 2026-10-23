import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const ignoredDirectoryExtensions = new Set(['.app', '.bundle', '.framework', '.pkg', '.photoslibrary']);

export async function discoverPDFs(rootPath) {
  const root = path.resolve(rootPath);
  const rootStats = await fsp.stat(root);
  if (!rootStats.isDirectory()) throw new Error('Choose a folder, not a file.');
  const files = [];
  async function walk(directory) {
    const entries = await fsp.readdir(directory, { withFileTypes: true });
    entries.sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));
    for (const entry of entries) {
      if (entry.name.startsWith('.') || entry.isSymbolicLink()) continue;
      const fullPath = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        if (!ignoredDirectoryExtensions.has(path.extname(entry.name).toLowerCase())) await walk(fullPath);
      } else if (entry.isFile() && path.extname(entry.name).toLowerCase() === '.pdf') {
        files.push(fullPath);
      }
    }
  }
  await walk(root);
  return files;
}

export async function sha256File(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('sha256');
    const stream = fs.createReadStream(filePath);
    stream.on('error', reject);
    stream.on('data', (chunk) => hash.update(chunk));
    stream.on('end', () => resolve(hash.digest('hex')));
  });
}

export async function extractPdf(filePath) {
  const pdfjs = await import('pdfjs-dist/legacy/build/pdf.mjs');
  const bytes = new Uint8Array(await fsp.readFile(filePath));
  const loadingTask = pdfjs.getDocument({
    data: bytes,
    disableFontFace: true,
    useSystemFonts: false,
    standardFontDataUrl: fileURLToPath(new URL('../node_modules/pdfjs-dist/standard_fonts/', import.meta.url))
  });
  const document = await loadingTask.promise;
  const pageCount = document.numPages;
  const metadata = await document.getMetadata().catch(() => ({ info: {} }));
  const pages = [];
  for (let pageNumber = 1; pageNumber <= pageCount; pageNumber += 1) {
    const page = await document.getPage(pageNumber);
    const content = await page.getTextContent();
    const text = content.items
      .map((item) => typeof item.str === 'string' ? item.str : '')
      .join(' ')
      .replace(/\s+/g, ' ')
      .trim();
    pages.push(text);
    page.cleanup();
  }
  const scanned = pages.join('').trim().length < Math.max(20, pageCount * 8);
  await loadingTask.destroy();
  return {
    title: typeof metadata.info?.Title === 'string' ? metadata.info.Title.trim() : '',
    authors: typeof metadata.info?.Author === 'string' ? metadata.info.Author.trim() : '',
    pages,
    scanned
  };
}

export async function indexFiles(database, filePaths, { rootPath = null, onProgress = () => {} } = {}) {
  const normalized = [...new Set(filePaths.map((filePath) => path.resolve(filePath)))];
  const jobId = database.createJob(rootPath ? 'Folder refresh' : 'PDF import', rootPath ?? `${normalized.length} selected PDFs`, normalized.length);
  const result = { jobId, imported: 0, duplicates: 0, scanned: 0, failures: [], files: [] };
  const seenPaths = new Set();
  try {
    for (let index = 0; index < normalized.length; index += 1) {
      const filePath = normalized[index];
      seenPaths.add(filePath);
      try {
        const stats = await fsp.stat(filePath);
        if (!stats.isFile() || path.extname(filePath).toLowerCase() !== '.pdf') throw new Error('Not a PDF file.');
        const [hash, extracted] = await Promise.all([sha256File(filePath), extractPdf(filePath)]);
        const fallbackTitle = path.basename(filePath, path.extname(filePath)).replaceAll('_', ' ').trim();
        const stored = database.upsertIndexedPaper({
          title: extracted.title || fallbackTitle,
          authors: extracted.authors,
          item_type: 'Document',
          pdf_path: filePath,
          pdf_byte_count: stats.size,
          pdf_sha256: hash
        }, extracted.pages);
        result.imported += stored.duplicate ? 0 : 1;
        result.duplicates += stored.duplicate ? 1 : 0;
        result.scanned += extracted.scanned ? 1 : 0;
        result.files.push({ path: filePath, id: stored.id, pages: stored.pages, scanned: extracted.scanned });
      } catch (error) {
        result.failures.push({ path: filePath, message: error instanceof Error ? error.message : String(error) });
      }
      database.updateJob(jobId, 'Running', index + 1, normalized.length);
      onProgress({ ...result, completed: index + 1, total: normalized.length });
    }
    if (rootPath) database.markUnavailableExcept(path.resolve(rootPath), seenPaths);
    const status = result.failures.length === normalized.length && normalized.length > 0 ? 'Failed' : 'Completed';
    database.updateJob(jobId, status, normalized.length, normalized.length,
      result.failures.length ? `${result.failures.length} file(s) could not be indexed.` : null);
    return result;
  } catch (error) {
    database.updateJob(jobId, 'Failed', result.imported + result.duplicates, normalized.length,
      error instanceof Error ? error.message : String(error));
    throw error;
  }
}
