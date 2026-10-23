# Architecture

## Universal desktop client

`Desktop/` is the cross-platform distribution path for macOS, Windows, and Linux.

- Electron 45 supplies a consistent 64-bit desktop runtime.
- `src/renderer/` is a sandboxed, context-isolated UI with no direct Node.js, filesystem, database, credential, or network access.
- `src/preload.cjs` exposes only narrow, immutable research operations. It deliberately uses CommonJS because Electron's sandboxed preload runtime does not execute ESM preload imports.
- `src/main.js` validates IPC inputs and owns native dialogs, local files, credentials, PDF delivery, and model requests.
- `src/database.js` uses Node's built-in SQLite binding and the same schema version 16 used by the Swift client.
- `src/library-indexer.js` discovers read-only PDFs, fingerprints them, extracts page text with PDF.js, and commits each document independently.
- `src/ai-provider.js` isolates Ollama, LM Studio, OpenAI, Anthropic, Gemini, and compatible request formats. Hosted HTTP is rejected; loopback HTTP is accepted only for local servers.
- Electron `safeStorage` protects persistent credentials with macOS Keychain, Windows DPAPI, or a supported Linux secret service. Linux `basic_text` fallback is rejected; session-only credentials remain available.

The clients may share the default macOS database, but must not be open against it simultaneously. Windows and Linux use their standard per-user application-data folders. Installers are built and tested on their target operating system through a matrix workflow.

## Native macOS client

## Shape

Research Atlas is a Swift package with three targets:

- `ResearchAtlasApp`: native SwiftUI application and AppKit file/open-panel bridges.
- `ResearchAtlasCore`: domain models, SQLite persistence, PDF indexing, and read-only integrations.
- `ResearchAtlasChecks`: repeatable integration checks that run without a personal library.

Implementation sources live under `AppSources/` so the package never mixes code with the project mirror's protected, read-only `sources/` reference directory.

The UI owns navigation and presentation state through a main-actor `AppModel`. Core services do not depend on SwiftUI. SQLite is encapsulated in `AtlasDatabase`, which serializes access and applies versioned migrations. Local-folder discovery and PDF extraction run away from the main actor.

## Data flow

1. An explicitly selected local PDF folder, single PDF, or Obsidian vault supplies source data.
2. Integration parsers produce typed domain records.
3. `AtlasDatabase` stores application-owned records and derived page/note indexes. Each processed PDF commits as a bounded unit so a long folder refresh can be cancelled without corrupting earlier completed work.
4. SQLite FTS5 returns grouped results with stable entity identifiers.
5. SwiftUI navigates back to the paper, PDF, note, question, or argument.

Original PDFs and notes remain in place. The database stores paths, extracted page text, metadata, and application-owned analysis.

## Decisions and trade-offs

- **Swift Package rather than a generated `.xcodeproj`:** Xcode opens Swift packages natively, while source-of-truth project files remain reviewable and do not require a project generator. A packaging script produces a standalone `.app`.
- **Direct SQLite C API:** avoids a third-party dependency and keeps migrations explicit. The wrapper is intentionally narrow; richer query abstractions can be introduced if schema complexity grows.
- **Manual FTS indexing:** source and search tables stay clearly separated, and the entire derived index can be rebuilt.
- **Read-only folder access:** a security-scoped bookmark grants repeat access to one explicitly selected folder. Discovery skips hidden content, packages, symbolic links, and non-PDF files and never mutates the source tree.
- **Content-addressed import:** standardized paths identify a location while SHA-256 identifies the exact bytes. Unchanged files and duplicate content are skipped; a relocated matching document can reuse the existing paper identity.
- **Bounded refresh commits:** each new or changed PDF is extracted and committed with its page index before the next begins. Per-file failures are counted and a cancellation retains only completed work.
- **Legacy schema compatibility:** older database fields and migrations for retired external-library imports remain readable so existing backups and provenance records are not destroyed. No external-library client is exposed or invoked by the current app.
- **Validated restore with rollback:** backup candidates are inspected through an immutable read-only SQLite connection. Restore creates a pre-change online backup, replaces the live database through SQLite's backup API, applies migrations, rebuilds FTS, and validates integrity and foreign keys. Failure restores the pre-change copy when possible.
- **Content-addressed PDF repair:** SHA-256 and byte count identify a verified PDF independently of its path. A relink updates the path, verification record, and derived page index in one transaction while preserving the paper and evidence identities.
- **Fingerprint-bound selection geometry:** application-owned annotations use normalized PDF page coordinates and a captured document hash. The app highlights only geometry known to belong to the current bytes, while retaining page-level provenance after a source changes.
- **Snapshot-based grounded retrieval:** saved retrieval sets retain the query, filters, exact indexed page text, extraction metadata, source fingerprint, and separately typed Obsidian-note excerpts. Current source state is compared on read so changed or missing paper passages and note excerpts cannot appear current; notes never inherit a paper's epistemic status.
- **Typed, provenance-bearing graph edges:** polymorphic node links retain their relationship type, origin, verification state, and either linked evidence, an indexed passage, or a user rationale. Node existence is validated before insertion.
- **Revision history from observed writes:** questions, arguments, claims, and ideas capture explicitly saved states and rationale. A separate event timeline reports only operations Research Atlas actually recorded.
- **Manual-first analytical entities:** claim extraction, contradiction classification, idea challenges, and question coverage work without a provider. Question coverage is derived deterministically from explicit literature links, source availability, paper metadata, and user-authored comparison profiles; it is never interpreted as comprehensive literature coverage. Generated claim candidates enter the same review model as unverified records.
- **Consent-gated provider boundary:** model-specific HTTP lives behind `AIProvider`. OpenAI Responses, Anthropic Messages, Gemini `generateContent`, loopback Ollama chat, and loopback LM Studio chat have explicit request/response codecs; a custom endpoint must implement the OpenAI Responses contract. The app packages only current retrieval snapshots plus the displayed task context, presents a per-request transmission preview, revalidates the approved snapshots and context immediately before sending, and persists provider/model/prompt/citation/usage/target provenance. Paper passages (`S`) and researcher-note excerpts (`N`) use separate citation namespaces and storage tables.
- **Owned local-runtime lifecycle:** the standalone bundle carries an ad-hoc-signed Ollama executable but no model weights. `OllamaRuntimeController` probes only `127.0.0.1:11434`, starts the bundled process when unavailable, verifies and preloads the configured model, exposes lifecycle state to SwiftUI, and schedules idle termination only when it owns that process. A pre-existing server is used but never terminated by Research Atlas.
- **Keychain-only hosted credentials:** hosted API credentials are managed by the app target through Security.framework and isolated by provider. Core models, SQLite rows, logs, portable exports, and backups never intentionally contain them. Direct hosted-provider endpoints are fixed to the provider's official HTTPS host; local Ollama uses no key and is fixed to the loopback route to reduce credential and research-content redirection risk.
- **Cautious local reasoning services:** the non-AI bias auditor and citation-support checker generate inspectable investigation prompts from recorded state. They deliberately avoid similarity scores, psychological diagnosis, or claims of definitive citation correctness.
- **Reproducible deliberation records:** Argument Room separates local prompts, researcher-authored responses, and model-generated messages while retaining provider/model/prompt disclosure, phase, uncertainty, and exact citation snapshots. All generated roles disclose that they came from the same model.
- **Guarded experimental records:** Collective Intelligence Lab records configurations, roles, information conditions, ordered turns, confidence and interruption state, model settings, and exact citation snapshots without claiming equivalence to human collective intelligence or silently invoking a provider.
- **Renderable graph with bounded density:** Knowledge Atlas derives a deterministic visual layout from typed stored nodes and edges, caps the visible graph, and exposes filters and focused neighbourhoods rather than loading an unbounded decorative canvas.
- **Writing complements Obsidian:** application-owned outlines, sections, evidence links, and citation-review decisions can be exported to Markdown; no existing vault file is edited.
- **Synchronous database API behind serialized access:** simple and reliable for v1.7. Expensive PDF, vault, search rebuild, and restore work runs off the main actor. A dedicated database actor is a reasonable later refinement.
- **No embeddings yet:** reliable keyword/full-text retrieval is a stronger first foundation and does not require sending research text elsewhere.

## Current module boundary

`ResearchAtlasCore` contains the provider protocol and structured grounding contract but no stored credentials, and never writes to the research folder or Obsidian. `ResearchAtlasApp` is the only target that accesses Keychain, opens user pickers, or opens external applications. Providers accept only explicit, provenance-bearing retrieval inputs prepared by the core service.
