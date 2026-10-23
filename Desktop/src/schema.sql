PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;

CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS literature_items (
  id TEXT PRIMARY KEY, zotero_key TEXT, zotero_attachment_key TEXT, zotero_server_id TEXT,
  zotero_library_id TEXT, zotero_version INTEGER, title TEXT NOT NULL,
  authors TEXT NOT NULL DEFAULT '', publication_year INTEGER, abstract_text TEXT NOT NULL DEFAULT '',
  doi TEXT, citation_key TEXT, tags_json TEXT NOT NULL DEFAULT '[]', item_type TEXT NOT NULL,
  source TEXT NOT NULL, source_availability TEXT NOT NULL DEFAULT 'Available', pdf_path TEXT,
  pdf_byte_count INTEGER, pdf_sha256 TEXT, pdf_last_verified_at TEXT, external_url TEXT,
  created_at TEXT NOT NULL, modified_at TEXT NOT NULL,
  UNIQUE(zotero_server_id, zotero_library_id, zotero_key)
);
CREATE INDEX IF NOT EXISTS literature_zotero_key_idx ON literature_items(zotero_key);
CREATE INDEX IF NOT EXISTS literature_source_status_idx ON literature_items(source, source_availability);
CREATE INDEX IF NOT EXISTS literature_zotero_library_idx ON literature_items(zotero_server_id, zotero_library_id);

CREATE TABLE IF NOT EXISTS obsidian_notes (
  id TEXT PRIMARY KEY, path TEXT NOT NULL UNIQUE, title TEXT NOT NULL, content TEXT NOT NULL,
  tags_json TEXT NOT NULL, wikilinks_json TEXT NOT NULL, citation_keys_json TEXT NOT NULL,
  dois_json TEXT NOT NULL, modified_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS research_projects (
  id TEXT PRIMARY KEY, title TEXT NOT NULL, summary TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL, modified_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS research_questions (
  id TEXT PRIMARY KEY, project_id TEXT NOT NULL REFERENCES research_projects(id) ON DELETE CASCADE,
  question TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '', status TEXT NOT NULL,
  created_at TEXT NOT NULL, modified_at TEXT NOT NULL, parent_question_id TEXT,
  objectives TEXT NOT NULL DEFAULT '', theoretical_interests TEXT NOT NULL DEFAULT '',
  conceptual_definitions TEXT NOT NULL DEFAULT '', unresolved_disagreements TEXT NOT NULL DEFAULT '',
  potential_hypotheses TEXT NOT NULL DEFAULT '', methodological_considerations TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS research_arguments (
  id TEXT PRIMARY KEY, question_id TEXT REFERENCES research_questions(id) ON DELETE SET NULL,
  proposition TEXT NOT NULL, qualification TEXT NOT NULL DEFAULT '', status TEXT NOT NULL,
  created_at TEXT NOT NULL, modified_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS evidence_relationships (
  id TEXT PRIMARY KEY, argument_id TEXT NOT NULL REFERENCES research_arguments(id) ON DELETE CASCADE,
  literature_id TEXT NOT NULL REFERENCES literature_items(id) ON DELETE CASCADE, relation TEXT NOT NULL,
  summary TEXT NOT NULL, page INTEGER, quoted_passage TEXT NOT NULL DEFAULT '', verification TEXT NOT NULL,
  created_at TEXT NOT NULL, selection_geometry_json TEXT NOT NULL DEFAULT '[]', selection_document_hash TEXT
);
CREATE TABLE IF NOT EXISTS source_passages (
  id TEXT PRIMARY KEY, literature_id TEXT NOT NULL REFERENCES literature_items(id) ON DELETE CASCADE,
  page INTEGER NOT NULL, passage_text TEXT NOT NULL, extraction_method TEXT NOT NULL,
  indexed_at TEXT NOT NULL, UNIQUE(literature_id, page)
);
CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
  entity_id UNINDEXED, entity_type UNINDEXED, title, body,
  tokenize='unicode61 remove_diacritics 2'
);

CREATE TABLE IF NOT EXISTS note_links (
  id TEXT PRIMARY KEY, note_id TEXT NOT NULL REFERENCES obsidian_notes(id) ON DELETE CASCADE,
  literature_id TEXT NOT NULL REFERENCES literature_items(id) ON DELETE CASCADE,
  match_method TEXT NOT NULL, matched_identifier TEXT NOT NULL, review_state TEXT NOT NULL,
  created_at TEXT NOT NULL, modified_at TEXT NOT NULL, UNIQUE(note_id, literature_id)
);
CREATE INDEX IF NOT EXISTS note_links_literature_idx ON note_links(literature_id, review_state);
CREATE TABLE IF NOT EXISTS argument_versions (
  id TEXT PRIMARY KEY, argument_id TEXT NOT NULL REFERENCES research_arguments(id) ON DELETE CASCADE,
  question_id TEXT REFERENCES research_questions(id) ON DELETE SET NULL, proposition TEXT NOT NULL,
  qualification TEXT NOT NULL DEFAULT '', status TEXT NOT NULL, change_note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS argument_versions_argument_idx ON argument_versions(argument_id, created_at DESC);
CREATE TABLE IF NOT EXISTS integration_state (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS zotero_libraries (
  server_id TEXT NOT NULL, library_id TEXT NOT NULL, kind TEXT NOT NULL, name TEXT NOT NULL,
  metadata_version INTEGER, library_version INTEGER, availability TEXT NOT NULL, last_synced_at TEXT,
  PRIMARY KEY(server_id, library_id)
);
CREATE TABLE IF NOT EXISTS zotero_collections (
  server_id TEXT NOT NULL, library_id TEXT NOT NULL, collection_key TEXT NOT NULL, name TEXT NOT NULL,
  parent_collection_key TEXT, zotero_version INTEGER, PRIMARY KEY(server_id, library_id, collection_key),
  FOREIGN KEY(server_id, library_id) REFERENCES zotero_libraries(server_id, library_id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS literature_collection_memberships (
  literature_id TEXT NOT NULL REFERENCES literature_items(id) ON DELETE CASCADE,
  server_id TEXT NOT NULL, library_id TEXT NOT NULL, collection_key TEXT NOT NULL,
  PRIMARY KEY(literature_id, server_id, library_id, collection_key),
  FOREIGN KEY(server_id, library_id, collection_key)
    REFERENCES zotero_collections(server_id, library_id, collection_key) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS literature_comparison_profiles (
  literature_id TEXT PRIMARY KEY REFERENCES literature_items(id) ON DELETE CASCADE,
  research_question TEXT NOT NULL DEFAULT '', theoretical_framework TEXT NOT NULL DEFAULT '',
  study_design TEXT NOT NULL DEFAULT '', sample TEXT NOT NULL DEFAULT '',
  independent_variables TEXT NOT NULL DEFAULT '', dependent_variables TEXT NOT NULL DEFAULT '',
  operational_definitions TEXT NOT NULL DEFAULT '', main_findings TEXT NOT NULL DEFAULT '',
  limitations TEXT NOT NULL DEFAULT '', user_notes TEXT NOT NULL DEFAULT '', modified_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS retrieval_sets (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, query_text TEXT NOT NULL, zotero_library_filter_id TEXT,
  zotero_collection_filter_id TEXT, year_from INTEGER, year_to INTEGER, created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS retrieval_set_passages (
  retrieval_set_id TEXT NOT NULL REFERENCES retrieval_sets(id) ON DELETE CASCADE,
  source_passage_id TEXT NOT NULL, literature_id TEXT NOT NULL REFERENCES literature_items(id) ON DELETE CASCADE,
  page INTEGER NOT NULL, passage_text TEXT NOT NULL, extraction_method TEXT NOT NULL,
  source_indexed_at TEXT NOT NULL, source_document_hash TEXT, relevance_rank REAL NOT NULL,
  added_at TEXT NOT NULL, PRIMARY KEY(retrieval_set_id, source_passage_id)
);
CREATE INDEX IF NOT EXISTS retrieval_passage_literature_idx ON retrieval_set_passages(literature_id, page);

CREATE TABLE IF NOT EXISTS research_concepts (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, definition TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '',
  verification TEXT NOT NULL, origin TEXT NOT NULL, created_at TEXT NOT NULL, modified_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS knowledge_relationships (
  id TEXT PRIMARY KEY, source_type TEXT NOT NULL, source_id TEXT NOT NULL, target_type TEXT NOT NULL,
  target_id TEXT NOT NULL, relationship_type TEXT NOT NULL,
  evidence_relationship_id TEXT REFERENCES evidence_relationships(id) ON DELETE SET NULL,
  source_passage_id TEXT, verification TEXT NOT NULL, origin TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL, modified_at TEXT NOT NULL,
  CHECK(source_type<>target_type OR source_id<>target_id)
);
CREATE INDEX IF NOT EXISTS knowledge_relationship_source_idx ON knowledge_relationships(source_type, source_id);
CREATE INDEX IF NOT EXISTS knowledge_relationship_target_idx ON knowledge_relationships(target_type, target_id);
CREATE TABLE IF NOT EXISTS indexing_jobs (
  id TEXT PRIMARY KEY, kind TEXT NOT NULL, source_name TEXT NOT NULL, status TEXT NOT NULL,
  completed_units INTEGER NOT NULL DEFAULT 0, total_units INTEGER, failure_message TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS question_versions (
  id TEXT PRIMARY KEY, question_id TEXT NOT NULL REFERENCES research_questions(id) ON DELETE CASCADE,
  parent_question_id TEXT, question_text TEXT NOT NULL, notes TEXT NOT NULL, status TEXT NOT NULL,
  objectives TEXT NOT NULL, theoretical_interests TEXT NOT NULL, conceptual_definitions TEXT NOT NULL,
  unresolved_disagreements TEXT NOT NULL, potential_hypotheses TEXT NOT NULL,
  methodological_considerations TEXT NOT NULL, change_note TEXT NOT NULL, created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS question_literature_associations (
  question_id TEXT NOT NULL REFERENCES research_questions(id) ON DELETE CASCADE,
  literature_id TEXT NOT NULL REFERENCES literature_items(id) ON DELETE CASCADE,
  notes TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, PRIMARY KEY(question_id,literature_id)
);
CREATE TABLE IF NOT EXISTS question_concept_associations (
  question_id TEXT NOT NULL REFERENCES research_questions(id) ON DELETE CASCADE,
  concept_id TEXT NOT NULL REFERENCES research_concepts(id) ON DELETE CASCADE,
  notes TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, PRIMARY KEY(question_id,concept_id)
);
CREATE TABLE IF NOT EXISTS research_claims (
  id TEXT PRIMARY KEY, claim_text TEXT NOT NULL, category TEXT NOT NULL,
  literature_id TEXT REFERENCES literature_items(id) ON DELETE SET NULL, source_passage_id TEXT, page INTEGER,
  quoted_source_text TEXT NOT NULL DEFAULT '', author_terminology TEXT NOT NULL DEFAULT '',
  methodological_context TEXT NOT NULL DEFAULT '', evidence_type TEXT NOT NULL DEFAULT '',
  related_constructs_json TEXT NOT NULL DEFAULT '[]', study_context TEXT NOT NULL DEFAULT '',
  extraction_method TEXT NOT NULL, model_identifier TEXT, prompt_version TEXT, verification TEXT NOT NULL,
  user_notes TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, modified_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS claim_versions (
  id TEXT PRIMARY KEY, claim_id TEXT NOT NULL REFERENCES research_claims(id) ON DELETE CASCADE,
  claim_text TEXT NOT NULL, category TEXT NOT NULL, author_terminology TEXT NOT NULL,
  methodological_context TEXT NOT NULL, evidence_type TEXT NOT NULL, related_constructs_json TEXT NOT NULL,
  study_context TEXT NOT NULL, verification TEXT NOT NULL, user_notes TEXT NOT NULL,
  change_note TEXT NOT NULL, created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS research_ideas (
  id TEXT PRIMARY KEY, project_id TEXT REFERENCES research_projects(id) ON DELETE SET NULL,
  question_id TEXT REFERENCES research_questions(id) ON DELETE SET NULL, title TEXT NOT NULL,
  body TEXT NOT NULL DEFAULT '', status TEXT NOT NULL, assumptions TEXT NOT NULL DEFAULT '',
  alternative_explanations TEXT NOT NULL DEFAULT '', evidence_needed TEXT NOT NULL DEFAULT '',
  investigation_notes TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, modified_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS idea_versions (
  id TEXT PRIMARY KEY, idea_id TEXT NOT NULL REFERENCES research_ideas(id) ON DELETE CASCADE,
  title TEXT NOT NULL, body TEXT NOT NULL, status TEXT NOT NULL, assumptions TEXT NOT NULL,
  alternative_explanations TEXT NOT NULL, evidence_needed TEXT NOT NULL, investigation_notes TEXT NOT NULL,
  change_note TEXT NOT NULL, created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS idea_links (
  id TEXT PRIMARY KEY, idea_id TEXT NOT NULL REFERENCES research_ideas(id) ON DELETE CASCADE,
  target_type TEXT NOT NULL, target_id TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL, UNIQUE(idea_id,target_type,target_id)
);

CREATE TABLE IF NOT EXISTS contradiction_cases (
  id TEXT PRIMARY KEY, question_id TEXT REFERENCES research_questions(id) ON DELETE SET NULL,
  title TEXT NOT NULL, summary TEXT NOT NULL DEFAULT '', status TEXT NOT NULL,
  resolution_notes TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, modified_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS contradiction_sources (
  id TEXT PRIMARY KEY, case_id TEXT NOT NULL REFERENCES contradiction_cases(id) ON DELETE CASCADE,
  literature_id TEXT NOT NULL REFERENCES literature_items(id) ON DELETE CASCADE, source_passage_id TEXT,
  role TEXT NOT NULL, finding TEXT NOT NULL DEFAULT '', contextual_difference TEXT NOT NULL DEFAULT '',
  verification TEXT NOT NULL, created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS history_events (
  id TEXT PRIMARY KEY, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL, event_type TEXT NOT NULL,
  title TEXT NOT NULL, detail TEXT NOT NULL DEFAULT '', recorded_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS history_events_time_idx ON history_events(recorded_at DESC);

CREATE TABLE IF NOT EXISTS ai_provider_configuration (
  singleton_id INTEGER PRIMARY KEY CHECK(singleton_id=1), provider TEXT NOT NULL, endpoint TEXT NOT NULL,
  model TEXT NOT NULL, external_transmission_enabled INTEGER NOT NULL, maximum_passages INTEGER NOT NULL,
  maximum_output_tokens INTEGER NOT NULL, modified_at TEXT NOT NULL,
  reasoning_effort TEXT NOT NULL DEFAULT 'medium', local_runtime_idle_minutes INTEGER NOT NULL DEFAULT 10
);
CREATE TABLE IF NOT EXISTS ai_analyses (
  id TEXT PRIMARY KEY, kind TEXT NOT NULL, provider TEXT NOT NULL, model TEXT NOT NULL,
  prompt_version TEXT NOT NULL, retrieval_set_id TEXT REFERENCES retrieval_sets(id) ON DELETE SET NULL,
  user_query TEXT NOT NULL, response_text TEXT NOT NULL DEFAULT '', structured_response_json TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL, transmitted_passage_count INTEGER NOT NULL DEFAULT 0,
  transmitted_character_count INTEGER NOT NULL DEFAULT 0, input_tokens INTEGER, output_tokens INTEGER,
  error_message TEXT, created_at TEXT NOT NULL, completed_at TEXT, target_type TEXT, target_id TEXT
);
CREATE TABLE IF NOT EXISTS ai_analysis_citations (
  id TEXT PRIMARY KEY, analysis_id TEXT NOT NULL REFERENCES ai_analyses(id) ON DELETE CASCADE,
  citation_label TEXT NOT NULL, source_passage_id TEXT NOT NULL,
  literature_id TEXT NOT NULL REFERENCES literature_items(id) ON DELETE CASCADE,
  page INTEGER NOT NULL, quoted_passage TEXT NOT NULL, source_document_hash TEXT,
  citation_status TEXT NOT NULL, UNIQUE(analysis_id,citation_label)
);
CREATE TABLE IF NOT EXISTS ai_analysis_note_citations (
  id TEXT PRIMARY KEY, analysis_id TEXT NOT NULL REFERENCES ai_analyses(id) ON DELETE CASCADE,
  citation_label TEXT NOT NULL, note_id TEXT NOT NULL, note_path TEXT NOT NULL, note_title TEXT NOT NULL,
  quoted_snippet TEXT NOT NULL, source_modified_at TEXT NOT NULL, citation_status TEXT NOT NULL,
  UNIQUE(analysis_id,citation_label)
);
CREATE TABLE IF NOT EXISTS analysis_reviews (
  id TEXT PRIMARY KEY, analysis_id TEXT NOT NULL UNIQUE REFERENCES ai_analyses(id) ON DELETE CASCADE,
  decision TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '', reviewed_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS retrieval_set_note_snippets (
  retrieval_set_id TEXT NOT NULL REFERENCES retrieval_sets(id) ON DELETE CASCADE, note_id TEXT NOT NULL,
  note_path TEXT NOT NULL, note_title TEXT NOT NULL, snippet_text TEXT NOT NULL,
  source_modified_at TEXT NOT NULL, relevance_rank REAL NOT NULL, added_at TEXT NOT NULL,
  PRIMARY KEY(retrieval_set_id,note_id)
);

CREATE TABLE IF NOT EXISTS bias_audits (
  id TEXT PRIMARY KEY, argument_id TEXT NOT NULL REFERENCES research_arguments(id) ON DELETE CASCADE,
  title TEXT NOT NULL, scope_note TEXT NOT NULL DEFAULT '', origin TEXT NOT NULL,
  analysis_id TEXT REFERENCES ai_analyses(id) ON DELETE SET NULL, created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS bias_concerns (
  id TEXT PRIMARY KEY, audit_id TEXT NOT NULL REFERENCES bias_audits(id) ON DELETE CASCADE,
  kind TEXT NOT NULL, potential_problem TEXT NOT NULL, why_it_matters TEXT NOT NULL DEFAULT '',
  alternative_interpretations TEXT NOT NULL DEFAULT '', investigation_questions_json TEXT NOT NULL DEFAULT '[]',
  uncertainty TEXT NOT NULL, origin TEXT NOT NULL, disposition TEXT NOT NULL,
  review_notes TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, modified_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS bias_concern_evidence (
  concern_id TEXT NOT NULL REFERENCES bias_concerns(id) ON DELETE CASCADE,
  evidence_relationship_id TEXT NOT NULL REFERENCES evidence_relationships(id) ON DELETE CASCADE,
  PRIMARY KEY(concern_id,evidence_relationship_id)
);
CREATE TABLE IF NOT EXISTS deliberation_sessions (
  id TEXT PRIMARY KEY, argument_id TEXT NOT NULL REFERENCES research_arguments(id) ON DELETE CASCADE,
  title TEXT NOT NULL, provider TEXT NOT NULL, model TEXT NOT NULL, prompt_version TEXT NOT NULL,
  disclosure TEXT NOT NULL, status TEXT NOT NULL, created_at TEXT NOT NULL, completed_at TEXT
);
CREATE TABLE IF NOT EXISTS deliberation_messages (
  id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES deliberation_sessions(id) ON DELETE CASCADE,
  perspective TEXT NOT NULL, phase TEXT NOT NULL, content TEXT NOT NULL, sequence INTEGER NOT NULL,
  model_generated INTEGER NOT NULL, created_at TEXT NOT NULL, UNIQUE(session_id,sequence)
);
CREATE TABLE IF NOT EXISTS deliberation_citations (
  id TEXT PRIMARY KEY, message_id TEXT NOT NULL REFERENCES deliberation_messages(id) ON DELETE CASCADE,
  citation_label TEXT NOT NULL, literature_id TEXT NOT NULL REFERENCES literature_items(id) ON DELETE CASCADE,
  source_passage_id TEXT NOT NULL, page INTEGER NOT NULL, quoted_passage TEXT NOT NULL,
  source_document_hash TEXT, citation_status TEXT NOT NULL, UNIQUE(message_id,citation_label)
);

CREATE TABLE IF NOT EXISTS writing_documents (
  id TEXT PRIMARY KEY, project_id TEXT REFERENCES research_projects(id) ON DELETE SET NULL,
  question_id TEXT REFERENCES research_questions(id) ON DELETE SET NULL, title TEXT NOT NULL,
  purpose TEXT NOT NULL, status TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL, modified_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS writing_sections (
  id TEXT PRIMARY KEY, document_id TEXT NOT NULL REFERENCES writing_documents(id) ON DELETE CASCADE,
  title TEXT NOT NULL, body TEXT NOT NULL DEFAULT '', position INTEGER NOT NULL,
  notes TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, modified_at TEXT NOT NULL,
  UNIQUE(document_id,position)
);
CREATE TABLE IF NOT EXISTS writing_evidence_links (
  id TEXT PRIMARY KEY, section_id TEXT NOT NULL REFERENCES writing_sections(id) ON DELETE CASCADE,
  target_type TEXT NOT NULL, target_id TEXT NOT NULL, citation_key TEXT,
  rationale TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, UNIQUE(section_id,target_type,target_id)
);
CREATE TABLE IF NOT EXISTS citation_support_reviews (
  id TEXT PRIMARY KEY, section_id TEXT NOT NULL REFERENCES writing_sections(id) ON DELETE CASCADE,
  statement TEXT NOT NULL, evidence_link_id TEXT REFERENCES writing_evidence_links(id) ON DELETE SET NULL,
  assessment TEXT NOT NULL, concern TEXT NOT NULL DEFAULT '', origin TEXT NOT NULL, model_identifier TEXT,
  prompt_version TEXT, review_notes TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, modified_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS collective_experiments (
  id TEXT PRIMARY KEY, title TEXT NOT NULL, research_purpose TEXT NOT NULL DEFAULT '',
  task_instructions TEXT NOT NULL DEFAULT '', interaction_mode TEXT NOT NULL, provider TEXT NOT NULL,
  model TEXT NOT NULL, model_settings_json TEXT NOT NULL DEFAULT '{}', prompt_version TEXT NOT NULL,
  status TEXT NOT NULL, validation_note TEXT NOT NULL, created_at TEXT NOT NULL, completed_at TEXT
);
CREATE TABLE IF NOT EXISTS collective_agents (
  id TEXT PRIMARY KEY, experiment_id TEXT NOT NULL REFERENCES collective_experiments(id) ON DELETE CASCADE,
  label TEXT NOT NULL, role TEXT NOT NULL DEFAULT '', information_available TEXT NOT NULL DEFAULT '',
  position INTEGER NOT NULL, created_at TEXT NOT NULL, UNIQUE(experiment_id,position)
);
CREATE TABLE IF NOT EXISTS collective_turns (
  id TEXT PRIMARY KEY, experiment_id TEXT NOT NULL REFERENCES collective_experiments(id) ON DELETE CASCADE,
  agent_id TEXT REFERENCES collective_agents(id) ON DELETE SET NULL, round_number INTEGER NOT NULL,
  sequence INTEGER NOT NULL, kind TEXT NOT NULL, information_available TEXT NOT NULL DEFAULT '',
  prompt_text TEXT NOT NULL DEFAULT '', response_text TEXT NOT NULL, confidence REAL,
  model_generated INTEGER NOT NULL, error_message TEXT, created_at TEXT NOT NULL,
  UNIQUE(experiment_id,sequence)
);
CREATE TABLE IF NOT EXISTS collective_turn_citations (
  id TEXT PRIMARY KEY, turn_id TEXT NOT NULL REFERENCES collective_turns(id) ON DELETE CASCADE,
  citation_label TEXT NOT NULL, literature_id TEXT NOT NULL REFERENCES literature_items(id) ON DELETE CASCADE,
  source_passage_id TEXT NOT NULL, page INTEGER NOT NULL, quoted_passage TEXT NOT NULL,
  source_document_hash TEXT, citation_status TEXT NOT NULL, UNIQUE(turn_id,citation_label)
);

INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES
  (1, datetime('now')), (2, datetime('now')), (3, datetime('now')), (4, datetime('now')),
  (5, datetime('now')), (6, datetime('now')), (7, datetime('now')), (8, datetime('now')),
  (9, datetime('now')), (10, datetime('now')), (11, datetime('now')), (12, datetime('now')),
  (13, datetime('now')), (14, datetime('now')), (15, datetime('now')), (16, datetime('now'));
