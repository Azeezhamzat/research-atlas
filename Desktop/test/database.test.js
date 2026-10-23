import test from 'node:test';
import assert from 'node:assert/strict';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';
import { AtlasDatabase } from '../src/database.js';

function fixture() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'research-atlas-universal-'));
  const database = new AtlasDatabase(path.join(directory, 'atlas.sqlite3'));
  return { database, cleanup: () => { database.close(); fs.rmSync(directory, { recursive: true, force: true }); } };
}

test('fresh database has schema 16 and a default project', () => {
  const item = fixture();
  try {
    assert.equal(item.database.db.prepare('SELECT MAX(version) AS version FROM schema_migrations').get().version, 16);
    assert.equal(item.database.list('projects').length, 1);
    assert.equal(item.database.dashboard().metrics.literature, 0);
  } finally { item.cleanup(); }
});

test('question and argument workflow records searchable history', () => {
  const item = fixture();
  try {
    const project = item.database.list('projects')[0];
    const question = item.database.save('questions', {
      project_id: project.id,
      question: 'When does calibrated AI advice improve group accuracy?',
      objectives: 'Identify boundary conditions.'
    });
    const argument = item.database.save('arguments', {
      question_id: question.id,
      proposition: 'Advice quality moderates group performance.',
      qualification: 'Only under observable reliability cues.'
    });
    assert.equal(item.database.list('questions')[0].id, question.id);
    assert.equal(item.database.list('arguments')[0].id, argument.id);
    assert.equal(item.database.search('calibrated').some((result) => result.entity_id === question.id), true);
    assert.equal(item.database.dashboard().recent.length, 2);
  } finally { item.cleanup(); }
});

test('indexed papers preserve page provenance and deduplicate by hash', () => {
  const item = fixture();
  try {
    const first = item.database.upsertIndexedPaper({
      title: 'Collective reasoning', authors: 'Researcher', item_type: 'Article', pdf_path: '/tmp/a.pdf',
      pdf_byte_count: 1200, pdf_sha256: 'abc123'
    }, ['First exact page.', 'Second exact page.']);
    const second = item.database.upsertIndexedPaper({
      title: 'Collective reasoning', authors: 'Researcher', item_type: 'Article', pdf_path: '/tmp/copy.pdf',
      pdf_byte_count: 1200, pdf_sha256: 'abc123'
    }, ['First exact page.', 'Second exact page.']);
    assert.equal(first.id, second.id);
    assert.equal(second.duplicate, true);
    assert.equal(item.database.paper(first.id).passages[1].page, 2);
    assert.equal(item.database.search('exact page').filter((result) => result.entity_type === 'passage').length, 2);
    const exported = JSON.parse(item.database.exportPortable());
    assert.equal(exported.literature.length, 1);
  } finally { item.cleanup(); }
});
