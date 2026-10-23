# Changelog

## 1.10.0 — repository-readiness hardening

- Excluded local databases, backups, portable exports, synced project sources, model weights, machine-specific benchmark reports, and private screenshot originals from version control.
- Replaced tutorial captures containing a developer username, local paths, and live research titles with public-safe demonstration images based on the real Research Atlas interface.
- Added a macOS GitHub Actions workflow plus a repeatable public-repository guard for secrets, private paths, oversized files, required release assets, and ignored research data.
- Made the release packager independent of a hard-coded CPU build directory and corrected the Keychain policy script's case-sensitive path.
- Removed development-only `#filePath` fallbacks from release compilation so packaged executables do not reveal the builder's absolute checkout path.
- Made performance profiling choose an available macOS SDK instead of assuming one host-specific SDK path.
- Added security-reporting guidance, contribution privacy rules, and the third-party notice shipped with the bundled Ollama runtime.
- Added an explicit packaging warning when the locally discovered Ollama runtime resolves inside the Trash, preventing that condition from being mistaken for a distribution-ready dependency.
- Made the public-repository audit portable to clean macOS runners that provide POSIX `grep` but not ripgrep.
- Corrected PDF.js standard-font paths on Windows by normalising directory separators and enforcing the required trailing slash.
- Corrected Debian and RPM maker configuration so both installers target the packaged `research-atlas` executable on x64 and ARM64.
- Pinned GitHub Actions to immutable commits for the current supported checkout, Node setup, and artifact upload releases.

## 1.10.0 — 2026-10-23

- Added contextual Grounded AI cards to Research Home, research questions, arguments, saved retrieval sets, and writing sections so a relevant task and evidence-set choice can be carried into the model workflow instead of re-entered in a blank assistant.
- Added direct argument-aware entry points to Research Bias Auditor and Argument Room, including automatic selection of the originating argument.
- Added context-aware retrieval-set selection and visible linked-paper coverage so a large but unrelated evidence set is never presented as an adequate match without warning.
- Added an expandable exact-text inspector to every AI consent preview so the complete paper passages and researcher-note excerpts can be read before approval.
- Added a visible four-stage Research Assistant workflow—choose evidence, ask, approve, review—and provider-readiness status inside every model preparation sheet.
- Added a complete AI availability map in Integrations with readiness status, workflow descriptions, and direct links to each assisted workspace.
- Corrected local-provider readiness so credential-free Ollama and LM Studio configurations are not incorrectly blocked for lacking an API key; hosted providers still require their saved credential.
- Preserved the mandatory retrieval-set, content-preview, freshness-revalidation, explicit approval, strict citation validation, and human-review boundaries for every contextual action.
- Expanded the Learning Center, handbook, and verification assertions for contextual AI discovery and local-versus-hosted readiness.
- Updated the standalone app to version 1.10.0 (build 25) with all thirty-three checks passing.

## 1.9.0 — 2026-10-23

- Rebuilt Global Search as a live, debounced local search with clear result-type labels, type filtering, explicit empty/loading states, and quoted exact-phrase support while retaining useful prefix matching for ordinary terms.
- Added exact navigation for indexed PDF pages, projects, questions, arguments, comparison profiles, concepts, claims, ideas, contradiction cases, writing workspaces, writing sections, and Obsidian notes.
- Fixed second-question deep links so project selection no longer resets them to the first question; comparison matches now preload the correct paper and concept matches open a focused Knowledge Atlas neighbourhood.
- Corrected Knowledge Atlas claim navigation to open Structured Claims, and made paper navigation fall back to the repair-capable Literature Library when its local PDF is unavailable.
- Added deterministic coverage for prefix search, quoted phrase adjacency/order, and exact page-passage lookup; retained thirty-three passing checks.
- Expanded the Learning Center and handbook with the real search grammar, filters, direct-navigation behaviour, and verification steps.
- Updated the standalone app to version 1.9.0 (build 24).

## 1.8.0 — 2026-10-22

- Rebuilt a research question's associated-literature section into a question-scoped coverage audit rather than a bare link list.
- Added deterministic summaries for publication years, paper tags, recorded theoretical frameworks, recorded study designs, source availability, per-field comparison completeness, and per-paper profile readiness.
- Added direct navigation from the audit to Evidence Explorer's comparison matrix with the question's linked papers already selected, so missing framework, design, sample, variables, definitions, findings, and limitations can be completed at their source.
- Made the interpretation boundary unavoidable in both code and interface: the audit describes only linked papers and recorded metadata, and never presents library incompleteness as a gap in the wider literature.
- Added a realistic in-app tutorial image and updated the Learning Center, complete guide, architecture, data-model notes, and verification documentation.
- Rebuilt the Learning Center as a category-and-lesson browser with direct task search and a single accessibility-safe lesson canvas, preserving every step, boundary, success check, workspace action, and real app screenshot without destabilising macOS accessibility clients.
- Updated the standalone app to version 1.8.0 (build 23) and expanded deterministic verification to thirty-three checks.

## 1.7.0 — 2026-10-20

- Made `gpt-oss:20b` the recommended local research model, with Medium reasoning and a 4,096-token starting limit.
- Bundled the Ollama command-line inference runtime inside Research Atlas so the default local provider no longer requires the Ollama or LM Studio application to be launched manually.
- Added app-managed engine lifecycle states, one-click preparation, model preloading, configurable 1–120 minute idle shutdown, and a stop control that can terminate only an engine Research Atlas itself started.
- Added explicit Low, Medium, and High gpt-oss reasoning settings and forwarded both reasoning effort and keep-alive lifetime through the structured Ollama request contract.
- Kept existing Ollama model weights in their normal local store rather than copying them into the app; Qwen 3.6 through LM Studio remains an optional provider and was not removed.
- Added schema migration 16, portable configuration provenance, and deterministic persistence/request tests for reasoning effort and engine lifetime.
- Updated the standalone app to version 1.7.0 (build 22) while retaining all thirty-two deterministic checks.

## 1.6.1 — 2026-10-20

- Added a first-class, credential-free LM Studio Local provider fixed to `http://127.0.0.1:1234/v1/chat/completions`.
- Added OpenAI-compatible chat-completions JSON Schema requests, token provenance, refusal and truncation handling, and Qwen-compatible final-JSON decoding.
- Accepted LM Studio `reasoning_content` only when its complete value is valid JSON, preventing free-form hidden reasoning from becoming a Research Atlas result.
- Added deterministic persistence, request, response, endpoint-isolation, and reasoning-boundary fixtures; expanded the in-app Learning Center and handbook with Qwen 3.6 setup.
- Updated the standalone app to version 1.6.1 (build 21) while retaining all thirty-two deterministic checks.

## 1.6.0 — 2026-10-20

- Made Research Assistant results progressively disclose both structured claims and exact source snapshots, and flattened the provenance summary into simpler labelled rows. The summary, review controls, and provenance counts remain immediately visible, while large grounded requests no longer force every claim and quotation into the initial screen or accessibility tree.
- Added a credential-free Ollama Local provider using the official non-streaming chat and JSON Schema response contract.
- Locked Ollama to `http://127.0.0.1:11434/api/chat`; persistence and request construction reject LAN, custom, and Internet targets.
- Refused provider HTTP redirects so the destination shown in the consent preview remains the actual request destination.
- Preserved the same explicit content preview, per-request approval, snapshot freshness checks, citation validation, provenance, and human review used for hosted providers.
- Added local-model connection testing, request/response/token contract fixtures, App Transport Security local-network scope, Learning Center guidance, and complete handbook documentation.
- Added an isolated 3,000-paper / 36,000-passage performance profile with machine-readable results for global search, grounded retrieval, library loading, ingestion, and complete FTS rebuilds.
- Made paper metadata and extracted pages an atomic per-document commit so an indexing failure cannot leave new metadata paired with an older page index.
- Updated the standalone app to version 1.6.0 (build 20) while retaining all thirty-two deterministic checks.

## 1.5.3 — 2026-10-20

- Rebuilt Collective Intelligence Lab from a passive transcript recorder into a controlled, consent-gated model workflow that runs exactly one configured-provider turn at a time.
- Added role, information-condition, round, turn-type, retrieval-set, and prior-turn context packaging with independent-mode isolation and explicit same-model disclosure.
- Added strict structured validation for evidence sufficiency, exact source labels, calibrated confidence, and uncertainty before any model contribution is accepted.
- Preserved the exact prompt/context, response, source snapshots, provider, model, output-token setting, prompt contract, authorship, and interruption record for reproducibility.
- Separated model execution from manual observations so pasted records can no longer be mislabeled as app-generated output.
- Added a privacy-preserving Integrations connection test that verifies the saved endpoint, credential, model, authentication, and structured-response path without sending research content.
- Fixed the connection-test button so a successful settings save cannot disable it merely because the persisted audit timestamp changed; the form now resynchronises with the saved configuration and explains genuine unsaved changes.
- Changed Research Assistant to open as a clean request composer instead of automatically expanding the newest historical failure or provenance-heavy record; a newly completed request still selects its result for review.
- Kept completed Research Assistant results scannable by collapsing full paper and researcher-note snapshots behind an explicit inspection control while preserving their counts, status, and exact-source actions.
- Moved provider keys to a fresh application-only Keychain access record and made all secret operations explicitly refuse authentication UI, so Research Atlas reports an inaccessible older credential instead of displaying a macOS login-password dialog.
- Expanded deterministic AI-contract coverage while retaining all thirty-two passing system checks.

## 1.5.2 — 2026-10-20

- Rebuilt the application shell around an active research project and grouped the sidebar by Start, Sources, Research reasoning, AI and critical review, Outputs and record, and System.
- Replaced the generic Home counters with a project-scoped command centre containing a research-flow map, exact-record resume cards, integrity queue, recent recorded activity, and source-provenance boundary.
- Added global search and creation controls, persistent project switching, wider untruncated navigation, and direct PDF/question creation from the sidebar.
- Corrected project and question creation so the new record becomes the active selection immediately.

## 1.5.1 — 2026-10-18

- Rebuilt the Knowledge Atlas map to eliminate the all-record graph hairball: Connected is now the default, All records uses labelled type clusters, dense views use progressive labels, degree controls node size, selected neighbourhoods receive visual emphasis, hover reveals labels, and the inspector reports connection coverage with direct creation actions.
- Stopped reading AI API-key values during launch, reload, and provider selection, eliminating repeated macOS Keychain password prompts during ordinary use.
- Moved provider keys to a fresh macOS Keychain service with an application-only access list and stopped querying retired records, eliminating obsolete-ACL login-password dialogs while keeping credentials outside application data and exports.
- Keychain presence indicators now use a non-secret `UserDefaults` marker; secret access occurs only during user-initiated credential changes or an approved AI transmission.
- Corrected the local ad-hoc build for macOS's entitlement model: it no longer requests the provisioned data-protection Keychain entitlement that an unsigned development build cannot possess.
- Fixed AI audit updates so a provider-side HTTP rejection preserves the exact source-snapshot and character counts that reached the provider; failures before networking still record zero transmitted content.
- Made retired-integration cleanup non-interactive so an inaccessible legacy credential can never interrupt startup.
- Added an AppKit launch fallback that creates and foregrounds the native Research Atlas window when SwiftUI restoration produces no visible main window.
- Corrected AI transmission accounting so credential and other pre-network failures retain their approved citation snapshots but record zero transmitted passages and characters.

## 1.5.0 — 2026-10-18

- Added direct OpenAI Responses, Anthropic Claude Messages, and Google Gemini `generateContent` providers with provider-native authentication and structured JSON output.
- Added explicit decoding for provider response IDs, text blocks, input/output token counts, refusals, blocked prompts, and output-token truncation.
- Locked direct providers to their official HTTPS endpoints; custom hosts remain available only through the clearly labelled OpenAI-compatible provider.
- Isolated OpenAI, Claude, Gemini, and compatible-endpoint credentials into separate macOS Keychain records, with one-way migration of the earlier single credential.
- Updated Integrations and the complete Learning Center/handbook with provider-specific setup, model selection, consent, and credential boundaries.
- Replaced tutorial lifestyle artwork with clean captures of the actual Research Atlas window, without people or surrounding desktop content.
- Updated the standalone app to version 1.5.0 (build 16) and expanded deterministic verification to thirty-two checks.

## 1.4.0 — 2026-10-17

- Replaced the active Zotero integration with a security-scoped, read-only local research-folder workflow.
- Added recursive PDF discovery, deterministic ordering, SHA-256 duplicate prevention, unchanged-file skipping, relocated-file reuse, and per-file failure isolation.
- Added folder refresh progress, cancellation, persisted folder access, and a clear summary of indexed, unchanged, duplicate, and unreadable files.
- Removed Zotero account/API-key setup, automatic network refresh, library/collection filters, item-verification controls, and direct desktop-routing actions from the app.
- Removed the stored Zotero credential and account defaults from the installed application environment.
- Reworked the Literature Library and Evidence Explorer for local sources and year-based retrieval.
- Replaced the Zotero tutorial lesson and artwork with a realistic local-folder guide, and revised the complete handbook and operational documentation.
- Updated the standalone app to version 1.4.0 (build 15) and expanded the verification suite to thirty-one checks.
- Preserved legacy schema/migration support so older backups and existing evidence records remain readable without re-enabling the retired integration.

## 1.3.0 — 2026-10-17

- Replaced ambiguous Zotero record opening with stable `zotero://select` links derived from the exact server/library/item identity.
- Added exact-key Zotero verification and refresh for personal and group libraries through API v3 item and child-attachment routes, without advancing a whole-library checkpoint or changing unrelated records.
- Corrected profile-safety requests to use Zotero's documented `Zotero-Server-ID` precondition header and surfaced endpoint, server identity, API version, schema version, item key, library ID, object version, attachment key, and exact route in the UI.
- Added account-level Zotero linkage using the numeric User ID and a dedicated read-only Web API key, verified through `/keys/current`, stored only in a separate Keychain service, and used for version-consistent, paginated, incremental personal/group metadata and collection sync plus exact item refreshes over HTTPS.
- Connected Zotero Web API accounts now refresh automatically once per launch, and local ad-hoc builds use a stable bundle-identifier signing requirement so saved Keychain credentials survive subsequent rebuilds.
- Simplified account setup to **Connect & Import Library**: enter the numeric Zotero ID and read-only API key directly in Research Atlas, then import the accessible library without any external credential-migration step.
- Added atomic single-item refresh persistence and deterministic coverage for direct user/group routing, desktop selection URLs, server preconditions, membership preservation, duplicate prevention, and checkpoint isolation.
- Added a native Learning Center with 23 searchable, task-oriented lessons, local completion tracking, direct workspace actions, explicit success criteria, cautions, and keyboard shortcuts.
- Added three original instructional illustrations plus a complete bundled Markdown handbook covering every workspace, evidence boundary, setup path, recovery operation, and known limitation.
- Expanded Literature Library filtering with author, year, topic/tag, source, source status, PDF status, and Obsidian-link filters while retaining Zotero library and collection filters.
- Updated the standalone app to version 1.3.0 (build 14) and expanded the verification suite to thirty checks.

## 1.2.0 — 2026-10-17

- Added an interactive visual Knowledge Atlas with deterministic graph layout, typed and colour-coded nodes/edges, search and provenance filters, zoom, pan, focused neighbourhoods, evidence-aware inspection, and source-workspace navigation.
- Added consent-previewed, source-grounded Argument Room generation with four disclosed roles produced by the same model, initial/cross-examination/revision phases, non-consensus synthesis, per-message citations, uncertainty, and researcher responses.
- Added optional grounded model suggestions to Research Bias Auditor while retaining the local rule-based path; concerns remain non-diagnostic, citation-bearing, and individually reviewable.
- Added optional grounded contradiction assessments that preserve design/context alternatives and unresolved questions without silently changing the researcher's case status or resolution.
- Added typed target links from AI analyses to deliberation sessions, bias audits, and contradiction cases, with portable export and human review.
- Added a guarded Collective Intelligence Laboratory for reproducible experimental configurations, role and information conditions, ordered turns, confidence records, interruptions, model provenance, exact source snapshots, and structured exports.
- Expanded local writing citation review to compare draft statements with the closest linked evidence text and surface causal-language, overbreadth, missing-qualification, low-match, and verification risks without claiming definitive correctness.
- Added grounded researcher-note excerpts to saved retrieval sets and Research Assistant requests with separate `N` labels, explicit non-published-evidence disclosure, pre-send freshness validation, review UI, and portable snapshot exports.
- Added a live local-storage total for the SQLite database and its working logs, and included stale note excerpts in the dashboard's next-investigation queue.
- Added schema migrations 13 through 15 and expanded the deterministic verification suite to twenty-nine checks.

## 1.1.0 — 2026-10-17

- Added a Research Bias Auditor that produces local, evidence-linked investigation questions without claiming to diagnose psychological bias.
- Added persistent concern types, uncertainty text, evidence references, and human accept/dismiss/address decisions with notes.
- Added Argument Room session, message, phase, perspective, authorship, provider/model/prompt, and exact citation records.
- Added a transparent local critical-deliberation scaffold and researcher-response workflow; local prompts are never labelled as model-generated experts.
- Added Research Writing workspaces with projects/questions, ordered outline sections, source links, citation keys, draft text, notes, and standalone Markdown export.
- Added cautious statement-level citation-support checks that surface missing or unverified support without claiming definitive correctness.
- Added search and portable Markdown/JSON/CSV export for writing, bias-audit, deliberation, and citation-review records.
- Added schema migration 12 and expanded the deterministic verification suite to twenty-six checks.

## 1.0.0 — 2026-10-13

- Added an optional Responses-compatible AI provider protocol with editable endpoint/model configuration and no provider dependency in core research workflows.
- Added macOS Keychain credential storage; credentials are absent from SQLite, logs, and portable exports.
- Added a disabled-by-default external transmission switch and a mandatory per-request preview showing destination, model, question, sources, and request size.
- Added pre-send source-snapshot revalidation so changed passages or document hashes require a new approval.
- Added a grounded Research Assistant that answers only from current saved retrieval passages and accepts only structured citation-bearing output.
- Rejects malformed responses, unknown citation labels, uncited substantive claims, and claims returned with an insufficient-evidence result.
- Added exact analysis citation snapshots, model/prompt provenance, provider token usage, failure states, and human review decisions.
- Added conversion of supported analysis claims into visibly unverified AI candidates with source passage and quotation provenance.
- Expanded Markdown/JSON/CSV export with AI provider metadata, analyses, citations, and reviews while explicitly excluding credentials.
- Added schema migration 11 and expanded the deterministic verification suite to twenty-three checks.

## 0.9.0 — 2026-10-13

- Added structured claims for manual entries and exact PDF selections with category, terminology, method/context fields, source provenance, extraction origin, verification, and revision history.
- Required model and prompt identifiers for every AI-candidate claim record even though providers remain disabled.
- Expanded research questions with parent/subquestion structure, objectives, theory, definitions, disagreements, hypotheses, methodology, literature/concept associations, and revisions.
- Added first-class research ideas with statuses, paper/passage/note/concept/argument links, deterministic challenge prompts, and recorded development history.
- Added manual contradiction-review cases with comparison sources, methodological profiles, contextual differences, review states, and cross-paper passage validation.
- Added an intellectual-history timeline populated only by application-observed creation and revision events.
- Expanded Research Home with active questions, recent ideas, unresolved verification/citation work, and recent history.
- Extended global search and portable exports for claims, questions, ideas, contradiction reviews, links, versions, and history.
- Added schema migration 10 and expanded the deterministic verification suite to twenty checks.

## 0.8.0 — 2026-10-13

- Added saved local retrieval sets with query, Zotero filters, publication-year bounds, and exact passage snapshots.
- Added citation freshness states for removed passages, changed indexed text, and changed PDF fingerprints.
- Added a human-authored literature comparison matrix covering theories, methods, samples, variables, findings, limitations, and explanations without filling missing fields.
- Added user-authored concepts and typed knowledge relationships across papers, concepts, arguments, questions, and notes.
- Required knowledge relationships to retain linked evidence, an indexed passage, or an explicit rationale, together with origin and verification state.
- Added persisted indexing activity, PDF-import cancellation before commit, failure details, and interrupted-job recovery.
- Extended search and portable JSON, Markdown, and CSV exports for comparison, retrieval, concepts, graph relationships, and indexing history.
- Added schema migration 9 and expanded the deterministic verification suite to seventeen checks.

## 0.7.0 — 2026-10-13

- Added read-only Zotero group-library discovery with independent checkpoints and unavailable-library preservation.
- Added Zotero collection hierarchies, item memberships, and library/collection filtering.
- Partitioned Zotero identities by server and library so identical user/group keys remain distinct.
- Added manual paper-note linking and optional, review-required exact-title suggestions while preserving scan decisions.
- Added normalized PDF selection geometry and document-fingerprint provenance to evidence annotations.
- Added source navigation with fingerprint-aware highlights and page fallback for stale geometry.
- Added evidence editing and explicit-confirmation deletion without modifying source PDFs.
- Extended portable exports with Zotero library, collection, membership, and geometry provenance.
- Added schema migrations 7 and 8 and expanded the standalone verification suite to fourteen checks.

## 0.6.0 — 2026-10-11

- Added schema migration 6 for PDF byte counts, SHA-256 fingerprints, and verification timestamps.
- Added distinct no-PDF, available, missing, and changed-since-verification states.
- Added review-first PDF attachment and relocation repair with exact, size-only, unverified, and different-file outcomes.
- Added atomic PDF path, fingerprint, and derived page-index replacement while preserving paper and evidence identities.
- Preserved Zotero attachment keys only for exact fingerprint matches, avoiding false attachment identity after substitution.
- Added on-read fingerprinting and page indexing for accessible legacy and Zotero PDF paths.
- Added fingerprint provenance to portable JSON and literature CSV exports.
- Added an eleventh verification check covering deterministic identity, missing-file detection, stale-index replacement, and evidence preservation.

## 0.5.0 — 2026-10-10

- Added read-only database-backup validation with integrity, foreign-key, required-table, and schema-version checks.
- Added a restore preview showing literature, note, project, question, argument, and evidence counts.
- Added an explicit confirmation step before replacing the live workspace.
- Added automatic pre-restore recovery backups and rollback after a failed restore.
- Added post-restore schema migration, search-index rebuilding, and integrity verification.
- Added a tenth verification check covering invalid-file rejection, restore replacement, evidence preservation, search rebuilding, and recovery-copy reopening.

## 0.4.0 — 2026-10-10

- Added persisted Zotero server-ID and library-version checkpoints.
- Added `since`-based changed-item and deletion refreshes with version-consistency checks.
- Added expected-server protection and atomic data/checkpoint commits.
- Partitioned Zotero item identity by server ID to prevent cross-library key collisions.
- Preserved deleted and previous-library records with explicit availability states instead of deleting evidence-bearing rows.
- Added concurrent PDF attachment resolution, attachment-deletion handling, and source-status UI.
- Added verification checks covering checkpoints, deletions, library switches, same-key partitions, and evidence-preserving migration from schema 4.

## 0.3.0 — 2026-10-10

- Added editable arguments with mandatory revision rationales.
- Added recorded argument-version history and schema migration 4.
- Added consistent SQLite online backups.
- Added portable Markdown, JSON, and CSV exports.
- Added export and recovery controls to Integrations.
- Added a seventh verification check covering history, exports, and backup restoration.

## 0.2.0 — 2026-10-10

- Added Zotero citation-key and tag persistence.
- Added exact DOI, citation-key, and Zotero-item URL matching between Obsidian notes and papers.
- Added reviewable paper-note suggestions with durable confirmed and rejected states.
- Added PDF selection capture with page provenance.
- Added direct source-passage-to-argument evidence creation from the Reading Desk.
- Added schema migration 3 and a sixth integration check for matching and review preservation.

## 0.1.0 — 2026-10-10

- Created the native SwiftUI macOS application foundation.
- Added SQLite schema migrations and FTS5 search.
- Added local PDF import, PDFKit reader/find, and page-level indexing.
- Added read-only Zotero local-API import with duplicate prevention and PDF attachment resolution.
- Added read-only Obsidian vault discovery and Markdown metadata parsing.
- Added research projects, questions, arguments, and provenance-bearing evidence links.
- Added local verification checks, standalone app packaging, and architecture/safety/integration documentation.

Known limitations are maintained in `ROADMAP.md`, `INTEGRATIONS.md`, and `TESTING.md`.
