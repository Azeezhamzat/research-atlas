# Data Model

Schema migrations are applied by `AtlasDatabase` and recorded in `schema_migrations`. Schema 16 adds explicit local-model reasoning effort and managed-engine idle lifetime.

## Source records

- `literature_items`: bibliographic metadata, citation keys, tags, local PDF path, PDF byte count, SHA-256 fingerprint, last-verification time, source kind, source URL, and source-availability state. Retired external-library identity columns remain nullable for old-backup compatibility.
- `zotero_libraries`, `zotero_collections`, and `literature_collection_memberships`: legacy restore/export provenance retained for databases created before v1.4; the current application does not populate or refresh these tables.
- `obsidian_notes`: note path, content, parsed tags, wikilinks, citation keys, DOIs, and modification time.
- `source_passages`: PDF text by one-based page, extraction method, and indexing time.
- `note_links`: reviewed note-to-paper relationships with the exact matched identifier, match method, and suggested/confirmed/rejected state.

## Research records

- `research_projects`: user-authored project title and scope.
- `research_questions`: a question, notes, and status owned by a project.
- `research_arguments`: a proposition, qualification, status, and optional research question.
- `argument_versions`: application-observed argument states with an explicit change note and timestamp.
- `evidence_relationships`: an argument-to-literature link with relation type, summary, exact quotation, optional page, verification state, normalized PDF selection geometry, and the PDF fingerprint against which geometry was captured.
- `literature_comparison_profiles`: user-authored theory, method, sample, variable, definition, finding, limitation, and interpretive fields for a paper. Empty fields mean unavailable, not inferred.
- `retrieval_sets`: saved full-text queries with publication-year filters. Retired library/collection filter columns remain nullable for old snapshots.
- `retrieval_set_passages`: immutable-at-capture page-text snapshots with source passage ID, extraction method, index time, document fingerprint, and rank. Current source state is compared on read.
- `retrieval_set_note_snippets`: immutable-at-capture Obsidian-note excerpt snapshots with note identity/path/title, modification time, and rank. Exact excerpts are compared with the current note on read; these records remain a separate researcher-context class rather than published evidence.
- `research_concepts`: named, defined concepts with notes, origin, and verification state.
- `knowledge_relationships`: typed polymorphic links among papers, concepts, arguments, questions, and notes with evidence/passage/rationale provenance, origin, and verification state.
- `indexing_jobs`: local PDF, Obsidian, and search-rebuild status with progress, cancellation/failure state, and diagnostic text.
- `question_versions`: explicitly saved research-question states and revision rationales.
- `question_literature_associations` and `question_concept_associations`: user-created research-question coverage links. The question coverage audit is a derived view over these links, literature metadata, source availability, and `literature_comparison_profiles`; it creates no inferred relationships and is not stored as a claim about the wider literature.
- `research_claims`: structured claims with category, paper/passage/page provenance, exact quotation, terminology, methods and context, extraction origin, model/prompt identifiers where applicable, and verification state.
- `claim_versions`: observed claim revisions with an explicit reason.
- `research_ideas`, `idea_versions`, and `idea_links`: first-class idea development, observed versions, and polymorphic links to papers, passages, notes, concepts, or arguments.
- `contradiction_cases` and `contradiction_sources`: manual comparison cases, source roles, findings, contextual differences, passages, and review state.
- `history_events`: a chronological ledger of application-observed create/revise/review operations; it is not a reconstructed history.
- `ai_provider_configuration`: non-secret provider endpoint, model, opt-in transmission switch, request limits, local reasoning effort, managed-engine idle lifetime, and modification time. Credentials are never stored in SQLite.
- `ai_analyses`: model-generated analysis records with kind, provider/model/prompt provenance, retrieval set, typed target entity, user task, status, request size, token usage, failure detail, and timestamps.
- `ai_analysis_citations`: immutable transmitted passage snapshots with labels, paper/page/source IDs, document hash, and dynamically evaluated freshness.
- `ai_analysis_note_citations`: immutable transmitted researcher-note snapshots with separate `N` labels, note identity/path/title, modification time, exact excerpt, and dynamically evaluated freshness.
- `analysis_reviews`: one current human review decision and notes per model-generated analysis.
- `bias_audits`, `bias_concerns`, and `bias_concern_evidence`: critical-review sessions, evidence-linked concerns, uncertainty, investigation questions, and preserved accept/dismiss/address decisions.
- `deliberation_sessions`, `deliberation_messages`, and `deliberation_citations`: ordered Argument Room records with role/phase/authorship disclosure, provider/model/prompt metadata, and exact source snapshots.
- `writing_documents`, `writing_sections`, and `writing_evidence_links`: application-owned outlines and draft sections with polymorphic links to claims, argument evidence, papers, or arguments and preserved citation keys.
- `citation_support_reviews`: statement-level review suggestions and human decisions with separate local/user/AI origin and mandatory model/prompt provenance for AI records.
- `collective_experiments`, `collective_agents`, `collective_turns`, and `collective_turn_citations`: guarded experimental records for interaction mode, task, provider/model/settings/prompt, roles, information conditions, ordered judgments, revisions, confidence, interruptions, authorship, and exact source snapshots.

## Derived data

- `search_index`: rebuildable FTS5 rows for literature, notes, PDF passages, projects, questions, arguments, comparison profiles, concepts, claims, ideas, and contradiction reviews.
- `integration_state`: legacy integration checkpoints retained for older backup compatibility.

Source records, user-authored reasoning, and derived indexes are never collapsed into one epistemic category. Stable UUIDs identify application-owned records. Local PDF bytes are identified by SHA-256 while paths represent current locations.

Legacy external-source deletions were represented as availability rather than row deletion, so retiring that integration does not cascade-delete application-owned evidence. These records remain readable in restored older databases but no longer have an active sync path.

Portable exports intentionally omit rebuildable FTS rows and PDF text indexes. JSON preserves all application-owned research entities; Markdown and CSV provide human-readable and tabular access. SQLite backups preserve the complete database, including derived indexes.

Restore accepts recognized schema versions 1 through 15. Older backups are migrated after restoration; backups from newer, unsupported schemas are rejected before the live database changes. Derived FTS data is rebuilt after a successful restore. Pre-restore recovery copies are stored beside the live database under `Recovery Backups/`.
