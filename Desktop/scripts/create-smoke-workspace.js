import fs from 'node:fs';
import path from 'node:path';
import { AtlasDatabase } from '../src/database.js';
import { indexFiles } from '../src/library-indexer.js';

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

const profile = path.resolve(process.argv[2] || 'out/smoke-profile');
const databasePath = path.join(profile, 'research-atlas.sqlite3');
if (fs.existsSync(databasePath)) throw new Error(`Refusing to replace existing smoke database: ${databasePath}`);
fs.mkdirSync(profile, { recursive: true });
const pdfPath = path.join(profile, 'Synthetic-source.pdf');
fs.writeFileSync(pdfPath, minimalPdf('Synthetic Research Atlas source passage for reading desk verification.'));

const database = new AtlasDatabase(databasePath);
try {
  await indexFiles(database, [pdfPath]);
  const project = database.list('projects')[0];
  const question = database.save('questions', {
    project_id: project.id,
    question: 'How should source provenance be verified across platforms?',
    objectives: 'Validate the installed reading and search workflow.'
  });
  database.save('arguments', {
    question_id: question.id,
    proposition: 'Cross-platform readers should preserve a stable link to the original file.',
    qualification: 'The file must remain available at its recorded location.'
  });
} finally {
  database.close();
}

process.stdout.write(`${profile}\n`);
