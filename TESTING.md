# Testing

## Universal desktop client

The universal client has deterministic Node.js tests for the platform-neutral database, search, endpoint policy, folder discovery, hashing, and AI-provider request boundary. Run with Node.js 24.15 or newer:

```sh
cd Desktop
npm ci
npm run check
npm test
```

`npm run make` packages the application for the host operating system. The GitHub Actions matrix repeats checks and packaging on Apple-silicon and Intel macOS, x64 and ARM64 Windows, and x64 and ARM64 Ubuntu runners. Passing the matrix confirms that installers can be produced; the release gate still requires clean-machine, signed-binary interaction testing on all target systems.

Universal checks cover:

- Schema-16 creation and compatibility with the native client's primary tables.
- Default-project creation, question and argument persistence, full-text search, change history, portable export, and PDF-page provenance.
- Content-hash deduplication.
- Real PDF.js page-text extraction from a generated PDF fixture.
- Recursive, deterministic PDF discovery with hidden folder, package, non-PDF, and symbolic-link exclusion.
- Hosted HTTPS enforcement and loopback-only cleartext model endpoints.
- Disabled hosted transmission without explicit consent.
- Ollama request encoding against an isolated test server.
- Sandboxed renderer boundaries and a narrow preload API (reviewed statically by `npm run check`; release builds require the platform security review in `RELEASE_CHECKLIST.md`).

## Native macOS client

## Current host

The host has Apple Swift 6.3.3 and Command Line Tools, but no full Xcode. Its default macOS 26.5 SDK was built with Swift 6.3.2 and is rejected by the compiler. The bundled macOS 15.4 SDK compiles this macOS 14 package. That SDK does not include XCTest or Swift Testing, so the repository includes a standalone verification target with deterministic, isolated fixtures.

Run it on this host with:

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/research-atlas-clang-cache \
SWIFT_MODULECACHE_PATH=/private/tmp/research-atlas-swift-cache \
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
swift run --disable-sandbox \
  --scratch-path /private/tmp/research-atlas-build \
  --cache-path /private/tmp/research-atlas-cache \
  --config-path /private/tmp/research-atlas-config \
  --security-path /private/tmp/research-atlas-security \
  ResearchAtlasChecks
```

Before every app build, `Scripts/check-keychain-policy.sh` also enforces the credential-access boundary: launch and settings use only a non-secret `UserDefaults` presence marker and never contact Keychain, new credentials use a fresh versioned service with an application-only access list, retired-record queries are forbidden, and the single credential-value read must remain in the explicitly approved AI-transmission path.

Before a public push, `Scripts/verify-public-repository.sh` checks the staged/tracked source set for private research artefacts, common secret formats, developer home paths, oversized files, required public tutorial assets, and third-party notices.

Verified checks:

- Database creation and all sixteen migrations.
- Recursive local research-folder discovery, case-insensitive PDF matching, deterministic ordering, and hidden/non-PDF exclusion.
- Project → question → argument → evidence persistence.
- Evidence quotation, page, relationship, and verification-state preservation.
- Legacy external-library key duplicate prevention and metadata refresh for backup compatibility.
- FTS search across literature metadata, PDF page text, notes, questions, analytical records, and writing, including prefix matching, quoted phrase adjacency/order, and exact source-passage resolution.
- Obsidian frontmatter/tag/wikilink/citation-key/DOI parsing.
- Recursive Markdown discovery with non-Markdown exclusion.
- Explicit DOI, citation-key, legacy item-link, manual, and opt-in exact-title note matching.
- Preservation of user rejection decisions across repeated note scans.
- Argument version creation, rationale preservation, and duplicate-save suppression.
- JSON, Markdown, and safely quoted CSV export generation.
- Online database backup and restored-record verification.
- Legacy per-library checkpoint persistence, attachment-deletion handling, source partitioning, and collection provenance for restore compatibility.
- Schema-4-to-8 migration with a quoted evidence relationship retained against its original source UUID.
- Database-restore preview counts and rejection of a non-SQLite file.
- Restored research/evidence persistence, derived-index rebuilding, and reopening the automatic pre-restore recovery copy.
- Deterministic PDF fingerprint matching and changed-file detection.
- Missing-file diagnosis, atomic path/index repair, stale-index removal, and evidence-UUID preservation.
- Normalized multi-page evidence geometry persistence, update-in-place, and deletion without touching source PDFs.
- Grounded retrieval with inspectable query and filter provenance, exact source/page snapshots, and explicit empty results.
- Citation-freshness failures for changed passage text, changed document fingerprints, and removed indexed pages.
- Literature-comparison persistence and search indexing.
- Typed knowledge relationships with evidence provenance, node validation, and self-link rejection.
- Interrupted indexing-job recovery without changing completed jobs.
- Structured claim provenance, revision history, search, source/passage consistency, deletion safety, and mandatory AI-candidate model/prompt metadata.
- Rich research-question fields, paper/concept associations, question versions, idea states, idea links, and idea versions.
- Recorded intellectual-history events for observed question and idea revisions.
- Context-sensitive contradiction cases with cross-paper passage mismatch rejection.
- Disabled-by-default AI settings, hosted HTTPS enforcement, fixed loopback Ollama validation, and credential-free exports.
- Provider readiness distinguishes hosted configurations that require a stored credential from loopback Ollama/LM Studio configurations that do not.
- AI transmission previews retain readable source provenance and the exact passage/note text being approved.
- Static Keychain policy enforcement that prevents startup/settings secret reads and automatic authentication prompts.
- Direct OpenAI, Anthropic Claude, Google Gemini, local Ollama, and LM Studio request encoding; hosted authentication headers; official/loopback endpoint enforcement; structured-output payloads; local reasoning/keep-alive settings; response text/token decoding; and API-key URL exclusion.
- Grounded AI request packaging that excludes stale passages and refuses an empty current-evidence set.
- Contextual AI selection reports exact overlap between current retrieval passages and the papers linked to the active research record; zero overlap is presented as a warning, not relevance.
- Structured response validation for unknown labels, uncited claims, malformed grounding, and valid insufficient-evidence refusals.
- AI analysis/model/prompt/source provenance, human reviews, token metadata, stale source detection, and portable AI exports.
- Bias-audit generation, uncertainty labels, user review decisions, and rejection of evidence from another argument.
- Deliberation role/authorship disclosure, ordered messages, exact quotation validation, and stale citation detection.
- Writing documents/sections, evidence links, search, cautious citation-review output, mandatory AI-review provenance, source-safe cascading deletion, and portable exports.
- Collective-experiment configuration, settings validation, role isolation, model-attribution requirements, confidence bounds, exact quotation validation, citation staleness, cascade safety, and structured exports.
- Grounded Argument Room contracts requiring every critical role and citation-bearing phase, with duplicate-role and invented-label rejection.
- Grounded bias and contradiction contracts rejecting uncited concerns and unavailable source labels.
- Typed AI-analysis target provenance and target-aware portable CSV export.
- Researcher-note retrieval snapshots, publication-filter isolation, separate `N` citations, note-only grounded answers, exact-excerpt staleness, transmission rejection of stale note context, and JSON/Markdown/CSV provenance exports.
- Legacy direct external-library routing and refresh contracts remain covered so older databases and exports do not lose provenance during migration.
- Question-linked literature coverage counts, deterministic year ordering, case-normalised tag/design distributions, profile completeness, source-availability boundaries, and explicit rejection of wider-literature gap claims.

## Large synthetic-library profile

`Scripts/run-performance-profile.sh` exercises the real SQLite, FTS5, library-loading, and grounded-retrieval paths against an isolated deterministic corpus. It never opens the user's research database, source folders, notes, or credentials. The default run uses 3,000 papers, 36,000 page-level passages, and forty timed samples per operation.

On 20 October 2026, the post-change profile on this Mac completed all five correctness checks with:

- Global FTS search: 18.27 ms median, 47.60 ms p95.
- Grounded retrieval-set creation: 58.68 ms median, 156.35 ms p95.
- Filtered literature load: 26.89 ms median, 27.61 ms p95.
- Complete 3,000-record metadata load: 77.60 ms median, 79.62 ms p95.
- Full 39,000-row metadata/passage FTS rebuild: 1.08 seconds.
- Synthetic ingestion: 115.28 seconds; the app commits each completed paper independently so cancellation preserves earlier work.

The machine-readable optimized-release report is `Benchmarks/research-atlas-performance-20261020T174114Z.json`. Measurements are descriptive rather than universal pass/fail budgets because storage, memory pressure, thermals, and hardware vary; correctness failures always fail the profile.

## Not tested on this host

- A large personal PDF folder was not scanned automatically; folder access requires explicit user selection in the app.
- Personal Obsidian vault import: no user vault was accessed.
- A complete VoiceOver/accessibility audit across every screen.
- Interactive PDF selection/highlight UI automation and broken file relocation through the UI.
- Interactive export/save/restore panels, Xcode archive, notarization, and distribution signing.
- Live provider requests are not part of automated verification: no API credential is accessed and no research content is transmitted by the deterministic suite. The configured OpenAI connection and one consent-approved grounded request were exercised manually on 20 October 2026. A credential-free `gpt-oss:20b` local connection health check also completed successfully without sending research content. Local Research AI still requires its selected model to exist in the normal local Ollama store; LM Studio Local requires its separate local server to be running.
- The new universal client has not yet been exercised on physical Windows or Linux machines from this macOS host. The cross-platform workflow is the automated gate once the repository is pushed; signed clean-machine acceptance testing remains mandatory before release.

These must remain reported as untested until exercised with explicit access and a full Xcode installation.
