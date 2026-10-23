import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { DatabaseSync, backup as sqliteBackup } from 'node:sqlite';
import { RESOURCE_DEFINITIONS, assertId, cleanText, integerOrNull, requireResource, safeFtsQuery } from './validation.js';

const moduleDirectory = path.dirname(fileURLToPath(import.meta.url));
const schemaPath = path.join(moduleDirectory, 'schema.sql');

const now = () => new Date().toISOString();
const identifier = () => crypto.randomUUID();

export class AtlasDatabase {
  constructor(databasePath) {
    this.path = databasePath;
    fs.mkdirSync(path.dirname(databasePath), { recursive: true });
    this.db = new DatabaseSync(databasePath, { timeout: 5_000, enableForeignKeyConstraints: true });
    this.db.exec(fs.readFileSync(schemaPath, 'utf8'));
    this.#validateCompatibility();
    this.ensureDefaultProject();
  }

  close() {
    if (this.db?.isOpen) this.db.close();
  }

  #validateCompatibility() {
    const row = this.db.prepare('SELECT COALESCE(MAX(version), 0) AS version FROM schema_migrations').get();
    if (Number(row.version) > 16) {
      throw new Error(`This database uses schema ${row.version}; this build supports up to schema 16.`);
    }
    const integrity = this.db.prepare('PRAGMA quick_check').get();
    if (!integrity || Object.values(integrity)[0] !== 'ok') throw new Error('The local database failed SQLite integrity checking.');
  }

  transaction(action) {
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const result = action();
      this.db.exec('COMMIT');
      return result;
    } catch (error) {
      try { this.db.exec('ROLLBACK'); } catch {}
      throw error;
    }
  }

  ensureDefaultProject() {
    const existing = this.db.prepare('SELECT id FROM research_projects ORDER BY created_at LIMIT 1').get();
    if (existing) return existing.id;
    const id = identifier();
    const timestamp = now();
    this.db.prepare('INSERT INTO research_projects(id,title,summary,created_at,modified_at) VALUES(?,?,?,?,?)')
      .run(id, 'My Research Project', '', timestamp, timestamp);
    return id;
  }

  dashboard() {
    const count = (table) => Number(this.db.prepare(`SELECT COUNT(*) AS value FROM ${table}`).get().value);
    const unresolved = Number(this.db.prepare("SELECT COUNT(*) AS value FROM evidence_relationships WHERE verification<>'Verified'").get().value);
    const missing = Number(this.db.prepare("SELECT COUNT(*) AS value FROM literature_items WHERE source_availability<>'Available'").get().value);
    return {
      metrics: {
        literature: count('literature_items'), notes: count('obsidian_notes'),
        questions: count('research_questions'), arguments: count('research_arguments'),
        claims: count('research_claims'), ideas: count('research_ideas')
      },
      integrity: { unresolvedEvidence: unresolved, unavailableSources: missing },
      recent: this.db.prepare(`
        SELECT entity_type, entity_id, event_type, title, detail, recorded_at
        FROM history_events ORDER BY recorded_at DESC LIMIT 12`).all(),
      projects: this.db.prepare('SELECT * FROM research_projects ORDER BY modified_at DESC').all(),
      databasePath: this.path
    };
  }

  list(resource) {
    const definition = requireResource(resource);
    return this.db.prepare(`SELECT * FROM ${definition.table} ORDER BY ${definition.order}`).all();
  }

  save(resource, rawRecord) {
    const definition = requireResource(resource);
    const input = rawRecord && typeof rawRecord === 'object' ? rawRecord : {};
    const existing = input.id ? this.db.prepare(`SELECT * FROM ${definition.table} WHERE id=?`).get(assertId(input.id)) : null;
    const record = { ...definition.defaults };
    for (const field of definition.fields) {
      if (Object.hasOwn(input, field)) {
        record[field] = field === 'page' ? integerOrNull(input[field], 1, 100_000) :
          (input[field] === null ? null : cleanText(input[field]));
      } else if (existing && Object.hasOwn(existing, field)) {
        record[field] = existing[field];
      }
    }
    for (const required of definition.required) {
      if (record[required] === null || cleanText(record[required]) === '') {
        throw new Error(`${required.replaceAll('_', ' ')} is required.`);
      }
    }
    const id = existing?.id ?? identifier();
    const timestamp = now();
    this.transaction(() => {
      if (existing) {
        const assignments = definition.fields.map((field) => `${field}=?`).join(',');
        this.db.prepare(`UPDATE ${definition.table} SET ${assignments}, modified_at=? WHERE id=?`)
          .run(...definition.fields.map((field) => record[field] ?? null), timestamp, id);
      } else {
        const columns = ['id', ...definition.fields, 'created_at', 'modified_at'];
        const placeholders = columns.map(() => '?').join(',');
        this.db.prepare(`INSERT INTO ${definition.table}(${columns.join(',')}) VALUES(${placeholders})`)
          .run(id, ...definition.fields.map((field) => record[field] ?? null), timestamp, timestamp);
      }
      this.#recordHistory(resource, id, existing ? 'Updated' : 'Created', record[definition.title] ?? resource);
      this.#updateSearch(resource, id);
    });
    return this.db.prepare(`SELECT * FROM ${definition.table} WHERE id=?`).get(id);
  }

  delete(resource, id) {
    const definition = requireResource(resource);
    const validId = assertId(id);
    const row = this.db.prepare(`SELECT ${definition.title} AS title FROM ${definition.table} WHERE id=?`).get(validId);
    if (!row) return false;
    this.transaction(() => {
      this.db.prepare(`DELETE FROM ${definition.table} WHERE id=?`).run(validId);
      this.db.prepare('DELETE FROM search_index WHERE entity_id=? AND entity_type=?').run(validId, resource);
      this.#recordHistory(resource, validId, 'Deleted', row.title);
    });
    return true;
  }

  #recordHistory(entityType, entityId, eventType, title, detail = '') {
    this.db.prepare(`INSERT INTO history_events(id,entity_type,entity_id,event_type,title,detail,recorded_at)
      VALUES(?,?,?,?,?,?,?)`).run(identifier(), entityType, entityId, eventType, cleanText(title, 500), cleanText(detail), now());
  }

  #updateSearch(resource, id) {
    const definition = RESOURCE_DEFINITIONS[resource];
    if (!definition) return;
    const row = this.db.prepare(`SELECT * FROM ${definition.table} WHERE id=?`).get(id);
    if (!row) return;
    const title = cleanText(row[definition.title], 2_000);
    const body = definition.fields.map((field) => row[field]).filter((value) => typeof value === 'string').join('\n');
    this.db.prepare('DELETE FROM search_index WHERE entity_id=? AND entity_type=?').run(id, resource);
    this.db.prepare('INSERT INTO search_index(entity_id,entity_type,title,body) VALUES(?,?,?,?)')
      .run(id, resource, title, body);
  }

  library(filters = {}) {
    const clauses = [];
    const values = [];
    if (cleanText(filters.query, 500)) {
      clauses.push('(title LIKE ? OR authors LIKE ? OR abstract_text LIKE ? OR tags_json LIKE ?)');
      const like = `%${cleanText(filters.query, 500).replaceAll('%', '\\%').replaceAll('_', '\\_')}%`;
      values.push(like, like, like, like);
    }
    if (integerOrNull(filters.yearFrom, 1000, 9999)) { clauses.push('publication_year>=?'); values.push(Number(filters.yearFrom)); }
    if (integerOrNull(filters.yearTo, 1000, 9999)) { clauses.push('publication_year<=?'); values.push(Number(filters.yearTo)); }
    if (filters.availability) { clauses.push('source_availability=?'); values.push(cleanText(filters.availability, 100)); }
    const where = clauses.length ? `WHERE ${clauses.join(' AND ')}` : '';
    return this.db.prepare(`SELECT * FROM literature_items ${where} ORDER BY modified_at DESC, title LIMIT 2000`).all(...values);
  }

  paper(id) {
    const validId = assertId(id, 'paper');
    const item = this.db.prepare('SELECT * FROM literature_items WHERE id=?').get(validId);
    if (!item) throw new Error('Paper not found.');
    return {
      ...item,
      passages: this.db.prepare('SELECT * FROM source_passages WHERE literature_id=? ORDER BY page').all(validId),
      evidence: this.db.prepare(`SELECT e.*, a.proposition FROM evidence_relationships e
        JOIN research_arguments a ON a.id=e.argument_id WHERE e.literature_id=? ORDER BY e.created_at DESC`).all(validId),
      claims: this.db.prepare('SELECT * FROM research_claims WHERE literature_id=? ORDER BY modified_at DESC').all(validId)
    };
  }

  upsertIndexedPaper(item, pages) {
    const existingByHash = item.pdf_sha256
      ? this.db.prepare('SELECT id FROM literature_items WHERE pdf_sha256=? LIMIT 1').get(item.pdf_sha256)
      : null;
    const existingByPath = this.db.prepare('SELECT id FROM literature_items WHERE pdf_path=? LIMIT 1').get(item.pdf_path);
    const id = existingByHash?.id ?? existingByPath?.id ?? item.id ?? identifier();
    const timestamp = now();
    this.transaction(() => {
      this.db.prepare(`INSERT INTO literature_items(
        id,title,authors,publication_year,abstract_text,tags_json,item_type,source,source_availability,
        pdf_path,pdf_byte_count,pdf_sha256,pdf_last_verified_at,created_at,modified_at)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET title=excluded.title, source_availability='Available',
          pdf_path=excluded.pdf_path,pdf_byte_count=excluded.pdf_byte_count,pdf_sha256=excluded.pdf_sha256,
          pdf_last_verified_at=excluded.pdf_last_verified_at,modified_at=excluded.modified_at`)
        .run(id, cleanText(item.title, 2_000) || 'Untitled paper', cleanText(item.authors, 2_000),
          integerOrNull(item.publication_year, 1000, 9999), cleanText(item.abstract_text), '[]',
          cleanText(item.item_type, 100) || 'Document', 'Local folder', 'Available', item.pdf_path,
          item.pdf_byte_count, item.pdf_sha256, timestamp, timestamp, timestamp);
      this.db.prepare('DELETE FROM source_passages WHERE literature_id=?').run(id);
      this.db.prepare("DELETE FROM search_index WHERE entity_id=? OR (entity_type='passage' AND entity_id LIKE ?)").run(id, `${id}:%`);
      this.db.prepare('INSERT INTO search_index(entity_id,entity_type,title,body) VALUES(?,?,?,?)')
        .run(id, 'literature', cleanText(item.title, 2_000), cleanText(item.abstract_text));
      const insertPassage = this.db.prepare(`INSERT INTO source_passages
        (id,literature_id,page,passage_text,extraction_method,indexed_at) VALUES(?,?,?,?,?,?)`);
      const insertSearch = this.db.prepare('INSERT INTO search_index(entity_id,entity_type,title,body) VALUES(?,?,?,?)');
      pages.forEach((text, index) => {
        const passageId = `${id}:${index + 1}`;
        insertPassage.run(passageId, id, index + 1, text, 'PDF.js', timestamp);
        insertSearch.run(passageId, 'passage', `${item.title} · page ${index + 1}`, text);
      });
      this.#recordHistory('literature', id, existingByHash || existingByPath ? 'Reindexed' : 'Imported', item.title, `${pages.length} pages indexed`);
    });
    return { id, pages: pages.length, duplicate: Boolean(existingByHash) };
  }

  markUnavailableExcept(rootPath, seenPaths) {
    const rows = this.db.prepare("SELECT id,pdf_path FROM literature_items WHERE source='Local folder' AND pdf_path LIKE ?").all(`${rootPath}%`);
    const update = this.db.prepare("UPDATE literature_items SET source_availability='Missing',modified_at=? WHERE id=?");
    this.transaction(() => rows.forEach((row) => { if (!seenPaths.has(row.pdf_path)) update.run(now(), row.id); }));
  }

  search(input, type = '') {
    const query = safeFtsQuery(input);
    if (!query) return [];
    const typeClause = type ? 'AND entity_type=?' : '';
    const params = type ? [query, cleanText(type, 100)] : [query];
    return this.db.prepare(`SELECT entity_id,entity_type,title,
      snippet(search_index,3,'<mark>','</mark>',' … ',24) AS excerpt,
      bm25(search_index,4.0,1.0) AS rank FROM search_index
      WHERE search_index MATCH ? ${typeClause} ORDER BY rank LIMIT 200`).all(...params);
  }

  evidenceForAi(literatureIds = [], limit = 12) {
    const ids = literatureIds.filter((id) => typeof id === 'string' && /^[0-9a-f-]{36}$/i.test(id)).slice(0, 50);
    const maximum = Math.max(1, Math.min(Number(limit) || 12, 50));
    const where = ids.length ? `WHERE p.literature_id IN (${ids.map(() => '?').join(',')})` : '';
    return this.db.prepare(`SELECT p.id,p.literature_id,p.page,p.passage_text,l.title,l.pdf_sha256
      FROM source_passages p JOIN literature_items l ON l.id=p.literature_id ${where}
      ORDER BY p.indexed_at DESC,p.page LIMIT ?`).all(...ids, maximum);
  }

  providerConfiguration() {
    return this.db.prepare('SELECT * FROM ai_provider_configuration WHERE singleton_id=1').get() ?? {
      provider: 'ollama', endpoint: 'http://127.0.0.1:11434', model: 'qwen3:latest',
      external_transmission_enabled: 0, maximum_passages: 12, maximum_output_tokens: 1200,
      reasoning_effort: 'medium', local_runtime_idle_minutes: 10
    };
  }

  saveProviderConfiguration(config) {
    const timestamp = now();
    this.db.prepare(`INSERT INTO ai_provider_configuration(singleton_id,provider,endpoint,model,
      external_transmission_enabled,maximum_passages,maximum_output_tokens,modified_at,reasoning_effort,local_runtime_idle_minutes)
      VALUES(1,?,?,?,?,?,?,?,?,?) ON CONFLICT(singleton_id) DO UPDATE SET
      provider=excluded.provider,endpoint=excluded.endpoint,model=excluded.model,
      external_transmission_enabled=excluded.external_transmission_enabled,
      maximum_passages=excluded.maximum_passages,maximum_output_tokens=excluded.maximum_output_tokens,
      modified_at=excluded.modified_at,reasoning_effort=excluded.reasoning_effort,
      local_runtime_idle_minutes=excluded.local_runtime_idle_minutes`)
      .run(config.provider, config.endpoint, config.model, config.external_transmission_enabled ? 1 : 0,
        Math.max(1, Math.min(Number(config.maximum_passages) || 12, 50)),
        Math.max(128, Math.min(Number(config.maximum_output_tokens) || 1200, 32_000)),
        timestamp, config.reasoning_effort ?? 'medium',
        Math.max(1, Math.min(Number(config.local_runtime_idle_minutes) || 10, 120)));
    return this.providerConfiguration();
  }

  recordAnalysis({ kind = 'Assistant', provider, model, query, response, passages, targetType = null, targetId = null, error = null }) {
    const id = identifier();
    const timestamp = now();
    this.transaction(() => {
      this.db.prepare(`INSERT INTO ai_analyses(id,kind,provider,model,prompt_version,user_query,response_text,
        structured_response_json,status,transmitted_passage_count,transmitted_character_count,error_message,
        created_at,completed_at,target_type,target_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`)
        .run(id, kind, provider, model, 'universal-1', query, response ?? '', '{}', error ? 'Failed' : 'Review required',
          passages.length, passages.reduce((total, passage) => total + passage.passage_text.length, 0),
          error, timestamp, timestamp, targetType, targetId);
      const insertCitation = this.db.prepare(`INSERT INTO ai_analysis_citations(id,analysis_id,citation_label,
        source_passage_id,literature_id,page,quoted_passage,source_document_hash,citation_status)
        VALUES(?,?,?,?,?,?,?,?,?)`);
      passages.forEach((passage, index) => insertCitation.run(identifier(), id, `S${index + 1}`,
        passage.id, passage.literature_id, passage.page, passage.passage_text, passage.pdf_sha256, 'Supplied'));
      this.#recordHistory('ai_analysis', id, error ? 'Failed' : 'Generated', `${kind} · ${model}`);
    });
    return id;
  }

  analyses() {
    return this.db.prepare('SELECT * FROM ai_analyses ORDER BY created_at DESC LIMIT 100').all();
  }

  indexingJobs() {
    return this.db.prepare('SELECT * FROM indexing_jobs ORDER BY created_at DESC LIMIT 50').all();
  }

  createJob(kind, sourceName, total = null) {
    const id = identifier(); const timestamp = now();
    this.db.prepare(`INSERT INTO indexing_jobs(id,kind,source_name,status,completed_units,total_units,created_at,updated_at)
      VALUES(?,?,?,?,?,?,?,?)`).run(id, kind, sourceName, 'Running', 0, total, timestamp, timestamp);
    return id;
  }

  updateJob(id, status, completed, total = null, failure = null) {
    this.db.prepare(`UPDATE indexing_jobs SET status=?,completed_units=?,total_units=COALESCE(?,total_units),
      failure_message=?,updated_at=? WHERE id=?`).run(status, completed, total, failure, now(), id);
  }

  async backup(destination) {
    await sqliteBackup(this.db, destination, { rate: 100 });
    return destination;
  }

  exportPortable() {
    const result = {
      format: 'Research Atlas portable export', version: 1, exportedAt: now(), schemaVersion: 16,
      projects: this.list('projects'), questions: this.list('questions'), arguments: this.list('arguments'),
      evidence: this.db.prepare('SELECT * FROM evidence_relationships ORDER BY created_at').all(),
      literature: this.library(), concepts: this.list('concepts'), claims: this.list('claims'),
      ideas: this.list('ideas'), contradictions: this.list('contradictions'), writing: this.list('writing')
    };
    return JSON.stringify(result, null, 2);
  }
}
