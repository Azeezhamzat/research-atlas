# Integrations

## Local research folder

The user selects one folder with the native macOS folder picker. Research Atlas stores a security-scoped bookmark and discovers readable PDFs recursively. The integration is strictly read-only: source files are never copied, moved, renamed, edited, or deleted.

Current behavior:

- Skips hidden content, application packages, symbolic links, and non-PDF files.
- Accepts `.pdf` extensions case-insensitively and returns a deterministic path order.
- Records a standardized source path, byte count, SHA-256 fingerprint, and verification time.
- Extracts machine-readable text page by page with PDFKit for local full-text search and evidence retrieval.
- Skips unchanged files on later refreshes.
- Avoids duplicate paper records when identical bytes exist at more than one readable path.
- Reuses an existing paper identity when matching bytes relocate and the old path is unavailable.
- Continues after an unreadable PDF and records the failure count in the indexing job.
- Keeps completed per-file work if a long folder refresh is cancelled.
- Supports one-file import through **Add PDF** with the same duplicate checks.

Limitations:

- PDF metadata may not include authors, DOI, publication year, abstract, or citation key; those fields remain unavailable rather than being guessed.
- PDFKit does not perform OCR. Image-only PDFs remain readable in the Reading Desk but may have little searchable text.
- A moved folder or changed macOS permission may require choosing the folder again.
- A folder scan is incremental by fingerprint, but it does not watch the filesystem continuously; click **Refresh Folder** after changes.
- Research Atlas does not delete a paper record merely because a file is temporarily unavailable, preserving application-owned evidence and history.

## Obsidian

The user selects a vault with the macOS folder picker. Research Atlas stores a security-scoped bookmark, recursively reads `.md` files, and parses headings, simple YAML frontmatter, tags, wikilinks, citation keys, and DOI strings.

The integration is strictly read-only. No note is rewritten, renamed, moved, or deleted. Research Atlas proposes paper-note relationships when it finds an exact DOI or citation key. Optional exact normalized-title suggestions can be enabled in Settings; they remain labelled suggestions and require explicit confirmation. Users can also add or remove a manual relationship. Suggestions stay visually and structurally distinct from confirmed links, and confirmation/rejection decisions survive later scans.

Saved retrieval queries may capture exact excerpts from matching notes. Those snapshots are labelled researcher context, stored separately from paper passages, checked against the current note before use, and cited with `N` labels in Research Assistant requests.

## PDFKit

Local PDFs remain at their original paths. PDFKit provides rendering, navigation, text selection, and in-document search. Extracted text is stored page by page as a derived index. A user can select an exact passage and link it to an argument with the one-based page number, normalized per-page selection geometry, and current document fingerprint preserved. Geometry-backed evidence reopens at the source location and is highlighted only while its fingerprint still matches; otherwise Research Atlas warns and falls back to the recorded page. Evidence annotations can be edited or deleted without modifying the PDF. PDFs with very little extracted text are flagged as likely scanned; no OCR text is silently substituted.

PDF availability is checked without copying or reorganizing the file. Imported and verified files receive an application-owned SHA-256 fingerprint, byte count, and verification time. Missing and subsequently changed files have distinct UI states. A repair candidate is fully inspected before confirmation; an exact fingerprint match is distinguished from an unverified or different file. Confirmed repair atomically updates the path, fingerprint, verification time, and page index while retaining all paper and evidence identities.

## Optional AI providers

Research Atlas supports six explicit provider modes:

- **OpenAI Responses:** official `https://api.openai.com/v1/responses` endpoint, bearer authentication, and strict JSON Schema response format.
- **Anthropic Claude:** official `https://api.anthropic.com/v1/messages` endpoint, `x-api-key` plus `anthropic-version` headers, and `output_config.format` JSON Schema output.
- **Google Gemini:** official Generative Language API base, model-specific `generateContent` route, `x-goog-api-key` authentication, and JSON response schema configuration.
- **Local Research AI (Ollama):** fixed `http://127.0.0.1:11434/api/chat` loopback route, no credential, non-streaming chat, and a JSON schema in the `format` field. The standalone app bundles the Ollama inference executable, starts it only when needed, loads the selected model from the existing local Ollama store, and stops only a process it started after the configured idle period. It does not download model weights.
- **LM Studio Local:** fixed `http://127.0.0.1:1234/v1/chat/completions` route, no credential, and OpenAI-compatible JSON Schema output. LM Studio and its selected model must be running separately; this remains an optional route for Qwen and other compatible models.
- **OpenAI-compatible endpoint:** a user-editable HTTPS endpoint that must implement the Responses request and response contract.

Official hosted-provider endpoints and both local loopback endpoints are locked in the interface and validated again before persistence and transmission. Hosted API keys are stored as separate provider accounts in a fresh macOS Keychain service with an application-only access list, never in URLs, SQLite, logs, exports, or backups; local providers use no key. Research Atlas does not query retired Keychain records whose obsolete access lists can trigger login-password prompts; after upgrading from an older build, paste each hosted-provider key once in Integrations to save it in the protected store. Changing the selected provider applies an editable model starting value without sending a request or overwriting another provider's credential.

HTTP redirects are not followed. A changed destination must be configured, previewed, and approved explicitly; neither local provider can be configured away from its loopback endpoint. Local Research AI defaults to `gpt-oss:20b`, Medium reasoning, a 4,096-token output allowance, and a ten-minute idle lifetime. The reasoning setting controls model deliberation depth; only the schema-constrained final answer is retained as a research result.

Every model workflow remains disabled by default. Enabling the global switch sends nothing on its own: each request still displays its destination, provider, endpoint, model, task, source snapshots, and size, then reloads and validates the approved evidence immediately before transmission. Live provider calls are not part of the deterministic verification suite because tests never access a personal key or transmit research content.
