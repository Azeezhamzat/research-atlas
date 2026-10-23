# Roadmap

## v1.10 — implemented

- Made grounded AI contextual and discoverable from Research Home, questions, arguments, saved retrieval sets, and writing sections.
- Added exact context handoff into Research Assistant, Bias Auditor, and Argument Room without creating an automatic-send path.
- Added linked-paper overlap ranking and visible grounding-fit warnings for contextual model workflows.
- Made the complete source text inspectable inside the final per-request consent preview.
- Added provider-readiness indicators and an Integrations map explaining where every AI-assisted workflow lives and what it does.
- Corrected credential-free local-provider readiness while retaining credentials for hosted providers.
- Kept source selection, request preview, freshness validation, per-request approval, citation validation, provenance, and human review mandatory.
- Updated the standalone app to version 1.10.0 (build 25) with all thirty-three checks passing.

## v1.9 — implemented

- Rebuilt Global Search with debounced live results, quoted exact phrases, prefix matching, result-type filtering, and clearer record classes.
- Added exact deep-link routing to PDF pages and every searchable first-class research record, including focused Knowledge Atlas concepts and preselected comparison profiles.
- Preserved exact secondary-question selection across project navigation and corrected claim/paper graph routes.
- Expanded deterministic search/navigation fixtures and the in-app/standalone guidance.
- Updated the standalone app to version 1.9.0 (build 24) with all thirty-three checks passing.

## v1.8 — implemented

- Added a deterministic literature-coverage audit inside each research question.
- Summarised only explicitly linked papers across publication years, paper tags, source availability, recorded theoretical frameworks, recorded study designs, comparison-field completeness, and per-paper profile readiness.
- Added direct comparison-matrix navigation and actionable missing-record notices without inventing profile values.
- Repeated the linked-library-only interpretation boundary in the interface, Learning Center, handbook, architecture, data model, and tests so missing local metadata is never represented as a wider research gap.
- Updated the standalone app to version 1.8.0 (build 23) with all thirty-three checks passing.

## v1.7 — implemented

- Made `gpt-oss:20b` the default local reasoning model with Low, Medium, and High effort controls.
- Embedded and supervised the Ollama inference runtime so Local Research AI starts from Research Atlas without a separately running model application.
- Added visible starting/loading/ready/generating/unavailable states, model preloading, one-click preparation, and configurable idle shutdown.
- Ensured Research Atlas stops only the engine process it owns; an Ollama server that was already running remains untouched.
- Preserved loopback isolation, per-request preview and approval, source freshness checks, strict citations, and human review.
- Kept LM Studio/Qwen as an optional alternative and updated the standalone app to version 1.7.0 (build 22) with all thirty-two checks passing.

## v1.6 — implemented

- Added a credential-free LM Studio adapter for existing local MLX/GGUF models, including Qwen 3.6, using a fixed loopback OpenAI-compatible chat-completions route and strict structured-output decoding.
- Added an optional credential-free Ollama adapter using the official non-streaming `/api/chat` structured-output contract.
- Restricted local-model traffic to the fixed `http://127.0.0.1:11434/api/chat` loopback endpoint; LAN and Internet redirection are rejected during persistence and request construction.
- Preserved per-request source preview, approval, freshness validation, strict citation checking, token provenance, and human review for local-model output.
- Added a reproducible 3,000-paper / 36,000-passage performance profile for the real FTS, retrieval, index-rebuild, and library-loading paths; all correctness checks and measured operations completed successfully on the development host.
- Made each imported paper's metadata and extracted page index one atomic transaction while preserving one-PDF-at-a-time commits for safe cancellation and recovery.
- Updated the standalone app to version 1.6.1 (build 21) while retaining all thirty-two deterministic system checks.

## v1.5 — implemented

- Added direct OpenAI Responses, Anthropic Claude Messages, and Google Gemini `generateContent` transports with provider-specific authentication, structured JSON output, token provenance, refusal handling, and incomplete-response handling.
- Locked direct-provider keys to official endpoints while retaining one explicitly labelled custom OpenAI-compatible HTTPS provider.
- Isolated provider credentials into separate macOS Keychain entries and retained the mandatory per-request content preview and approval boundary.
- Replaced lifestyle tutorial artwork with clean captures of the real Research Atlas window only.
- Updated the standalone app to version 1.5.3 (build 19), removed startup secret reads that could trigger repeated Keychain prompts, added a privacy-safe live connection test, rebuilt Collective Intelligence Lab as a grounded one-turn workflow, and retained thirty-two deterministic checks.

## v1.4 — implemented

- Replaced the active external reference-manager connection with a security-scoped, read-only local research folder.
- Added recursive deterministic PDF discovery with hidden-file, symbolic-link, package, and non-PDF exclusion.
- Added content-fingerprint duplicate prevention, unchanged-file skipping, safe relocated-file reuse, and per-file failure isolation.
- Added a folder-level indexing job with progress, cancellation, completion summaries, and repeatable refresh.
- Removed external account credentials, startup sync, library/collection controls, exact-item actions, and external-reference-manager content from the user interface.
- Rebuilt the first-hour workflow, Learning Center lesson, standalone handbook, and tutorial artwork around the local-folder workflow.
- Updated the standalone app to version 1.4.0 (build 15) and expanded deterministic verification to thirty-one checks.
- Retained legacy database columns and migrations only so older backups and evidence provenance remain recoverable.

## v0.1 — implemented

- Native SwiftUI shell with macOS navigation, light/dark appearance, search, keyboard shortcuts, contextual status, and resizable panes.
- Local SQLite database with migrations, foreign keys, WAL mode, and rebuildable FTS5 index.
- Literature library with local PDF import and read-only Zotero local-API refresh.
- Read-only Obsidian vault selection and recursive Markdown discovery.
- PDFKit reading, in-document find, page-level text extraction, and scanned-PDF warning.
- Global search across literature metadata, extracted PDF pages, Obsidian notes, projects, questions, and arguments.
- Research projects, research questions, arguments, and manual evidence relationships with pages, quotations, and verification states.
- Automated verification executable and project documentation.

## v0.2 — implemented

- Zotero citation-key and tag import.
- Explicit Obsidian-to-paper match suggestions using DOI, citation key, or Zotero item URLs.
- Confirm/reject review states that survive later rescans.
- Exact PDF selection capture with one-based page provenance.
- Direct selection-to-argument evidence workflow in the Reading Desk.

## v0.3 — implemented

- Argument editing with an explicit revision rationale.
- Recorded argument versions without reconstructing unobserved historical states.
- Consistent SQLite backups using SQLite's online backup API.
- Portable export package containing Markdown, JSON, literature/evidence/note-link CSV, and argument-history CSV.
- Export and backup controls in Integrations.

## v0.4 — implemented

- Incremental Zotero refresh using a persisted server ID and library version.
- Consistency checking across changed-item and deletion responses before checkpoint advancement.
- Atomic application of Zotero changes and checkpoints.
- Server-partitioned Zotero identities and non-destructive unavailable states for deleted or previous-library records.
- Concurrent PDF attachment-path resolution and explicit source-status UI.

## v0.5 — implemented

- Database restore with immutable read-only validation and a record-count preview.
- Schema compatibility, SQLite integrity, required-table, and foreign-key checks before confirmation.
- Automatic pre-restore recovery copy, post-restore migration, FTS rebuild, and rollback on failure.

## v0.6 — implemented

- Missing, unreadable, and changed-since-verification PDF diagnostics.
- SHA-256 and byte-count fingerprints with verification timestamps.
- Review-first PDF attachment and relocation repair with exact/different/unverified identity states.
- Atomic path, fingerprint, verification, and derived page-index replacement without changing evidence-bearing paper IDs.
- On-read fingerprinting and page indexing for accessible legacy or Zotero PDF paths.

## v0.7 — implemented

- Read-only Zotero group-library discovery with per-library incremental checkpoints.
- Collection hierarchy and membership import with library/collection filtering.
- Server-and-library-partitioned item identity and non-destructive inaccessible-group states.
- Manual note linking and optional, clearly labelled title-based match suggestions.
- Normalized PDF selection geometry tied to the verified document fingerprint where PDFKit supplies reliable bounds.
- Evidence-source navigation, annotation editing, and annotation deletion without changing source PDFs.
- Expanded deterministic verification coverage. Conventional XCTest/UI-test targets remain conditional on a full Xcode test runtime, which is not installed on the current host.

## v0.8 — implemented

- Source-grounded retrieval sets with inspectable query, filters, and passage provenance.
- Literature comparison workspace for theories, methods, findings, limitations, and contradictions.
- Typed paper-to-paper and concept relationships with an evidence-bearing graph foundation.
- Background indexing status, cancellation, and failure reporting for large libraries.
- Retrieval/citation failure fixtures required before enabling any AI provider.

## v0.9 — implemented

- Structured manual claims linked to exact source passages, with categories, terminology, context, correction history, and review state.
- Research Question workspaces with associated literature, arguments, concepts, hypotheses, objectives, and methodological considerations.
- First-class research ideas with explicit status and recorded versions.
- A non-AI contradiction review that builds comparison cases from verified records without treating different study contexts as contradictions.
- Expanded dashboard and intellectual-history events from recorded application changes only.

## v1.0 — implemented

- Optional Responses-compatible AI-provider protocol with disabled-by-default configuration, Keychain-backed credentials, explicit per-request transmission preview, usage records, and model separation from research logic.
- Source-grounded literature question answering restricted to current saved passage snapshots, with insufficient-evidence refusal and inspectable citations.
- Strict rejection of malformed, uncited, or unavailable citation labels before model output is accepted.
- AI claim candidates that enter the existing claim workflow as unverified, provenance-bearing records.
- Human accept/dismiss/revise review records and portable AI-analysis/citation/review exports that never contain credentials.
- Schema migration 11 and deterministic fixtures for provider configuration, secret boundaries, stale citations, insufficient evidence, malformed grounding, provenance, and human review.

## v1.1 — implemented

- Evidence-linked Research Bias Auditor with locally generated critical questions, explicit uncertainty, and persistent user decisions.
- Reproducible Argument Room sessions that distinguish local review prompts from researcher-authored responses and reserve model/provider provenance for future generated messages.
- Research Writing workspaces with outline sections, evidence and citation-key links, cautious statement-level citation-support review, search, and standalone Markdown export.
- Portable JSON, Markdown, and CSV records for bias audits, deliberations, writing, evidence links, and citation reviews.
- Schema migration 12 and deterministic integrity checks for cross-argument evidence, deliberation quotation matching, stale citations, human/model authorship, source-safe cascade behavior, and mandatory AI-review provenance.

## v1.2 — implemented

- Consent-previewed, citation-grounded generated perspectives in Argument Room, disclosed as roles produced by the same configured model rather than independent experts; messages retain phase, authorship, uncertainty, and exact citations.
- Reviewable AI contradiction and bias-audit suggestions using the same strict source-label validator and target-linked provenance records.
- Visual Knowledge Atlas with typed nodes and edges, relationship/origin/verification/type filters, search, focus, zoom, pan, node inspection, and source navigation.
- A guarded experimental Collective Intelligence Laboratory with reproducible configurations, roles, information conditions, ordered turns, confidence records, source snapshots, and structured exports.
- Evidence-aware local writing checks for causal language, scope, missing qualifications, low textual match, and unverified support, with direct source inspection and explicit limits on lexical comparison.
- Obsidian-note retrieval snapshots and optional Research Assistant grounding with a separate `N` citation namespace, visible researcher-context labelling, exact-excerpt freshness checks, and no conflation with published evidence.
- Schema migrations 13 through 15 plus deterministic contract coverage for experimental records, target provenance, required role sets, uncited concerns, invented labels, and note-grounding safety boundaries.

## v1.3 — implemented

- Direct Zotero desktop selection links and exact local-API item verification using stable server, library, item, and attachment identities.
- Numeric Zotero User ID + read-only Web API key verification, Keychain isolation, paginated incremental personal/group metadata sync, exact HTTPS item refresh, and preservation of local PDF identity.
- Documented `Zotero-Server-ID` precondition requests, exact personal/group routes, atomic one-item refresh, collection-membership preservation, and whole-library checkpoint isolation.
- A searchable native Learning Center covering every Research Atlas workspace with guided steps, success checks, cautions, progress tracking, and direct navigation.
- A bundled complete illustrated handbook and original instructional imagery that remains available without a network connection.
- Expanded Literature Library filtering across author, year, tag/topic, source, source availability, PDF state, note-link state, Zotero library, and collection.
- Thirty deterministic checks, including the complete direct-Zotero identity and routing contract.

## Later phases

- Semantic retrieval evaluation only if it outperforms the inspectable local baseline without implying conceptual equivalence.
- Full Xcode UI/accessibility tests when a compatible Xcode test runtime is installed.

Features in the later phases are not implemented and must not appear as verified capabilities.
