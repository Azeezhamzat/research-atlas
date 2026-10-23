# AI Safety and Evidence Integrity

AI is optional and disabled by default in v1.6. Core literature management, PDF reading, fingerprint and selection-geometry verification, search, grounded retrieval, claims, comparison, contradiction review, ideas, knowledge relationships, projects, local critical-review prompts, recorded history, writing, collective-experiment records, backup, restore, export, and the complete Learning Center work locally without an AI provider.

The foundation already preserves distinctions needed for later AI work:

- Literature and extracted PDF passages remain source records.
- Projects, questions, and arguments are user-authored application records.
- Evidence links record their relationship, source, optional page, quotation, selection geometry, document fingerprint, and verification state.
- Unverified, verified, and rejected states are explicit.
- Search results identify the entity and page-level passage that matched.
- Saved retrieval sets preserve empty results and mark citations stale when an indexed paper passage, page, document fingerprint, or captured researcher-note excerpt changes.
- Knowledge relationships record user/import/local/AI origin separately from verification state; the current relationship editor creates user-authored links only.
- Claim records distinguish manual authorship, manual PDF selection, and AI-candidate extraction. The database rejects an AI candidate without both model and prompt identifiers.
- Contradiction reviews require explicit sources and contextual differences; different outcomes are never automatically classified as contradictions.

The Research Assistant enforces the following boundary:

- A provider must be configured and its request switch enabled. Hosted endpoints must use HTTPS; Local Research AI and LM Studio are the only HTTP exceptions and are fixed to their `127.0.0.1` routes.
- OpenAI, Anthropic Claude, and Google Gemini use their official direct APIs and provider-specific authentication. Their endpoints are not editable; only the explicitly labelled OpenAI-compatible provider accepts a custom HTTPS endpoint.
- Local Research AI uses the non-streaming Ollama `/api/chat` contract with a JSON schema, attaches no credential, cannot be redirected to a LAN or Internet host, and retains the same per-request preview and source revalidation boundary. Research Atlas may start its bundled engine on demand, but stops only a process it owns; model weights remain in the normal local store.
- Low, Medium, and High local reasoning effort is explicit and saved with provider settings. Ollama thinking text is never parsed as the scholarly result; only the schema-constrained final message enters validation and provenance storage.
- Provider HTTP redirects are refused because the exact destination is part of the approved transmission record.
- Every request shows a separate preview containing the analysis kind, destination, model, research task, source titles/pages or note titles, source-snapshot count, and request character count. Closing or cancelling the preview sends nothing.
- Immediately before transmission, the app reloads and compares every approved paper-passage snapshot, document hash, note excerpt/modification time, research context, and output limit. Changed evidence or context requires a new preview.
- Research Assistant paper passages use `[S#]` labels. Obsidian excerpts use a separate `[N#]` namespace and are explicitly identified as researcher context, never published evidence.
- The structured response must cite only supplied `[S#]` or `[N#]` labels. Uncited substantive claims, unknown labels, malformed responses, and claims returned alongside an insufficient-evidence flag are rejected.
- Provider, model, prompt contract, exact source snapshots, request size, token usage where supplied, result status, and human review are retained.
- Converted claims are always `AI-generated suggestion` / `AI-extracted candidate` / `Unverified` and retain model, prompt, source snapshot, and quotation provenance. Note-backed claims remain visibly note-backed and are not converted into paper claims.
- Credentials are stored only in a fresh macOS Keychain service with an application-only access list. Provider secrets are separated by account, absent from the core data model, and excluded from JSON, Markdown, CSV, and SQLite backups.
- App launch and ordinary settings browsing use only a non-secret `UserDefaults` presence marker and never contact Keychain. Retired Keychain records are never queried, so their obsolete access lists cannot display a login-password dialog. The protected value is requested only when the researcher saves, removes, or explicitly approves an AI transmission.

The same boundary applies to Argument Room, Bias Auditor, and Contradiction Detective:

- Argument Room requires exactly one Theoretical, Methodological, Evidence, and Alternative Explanation role. Each must provide citation-bearing initial, cross-examination, and revised assessments, followed by a citation-bearing synthesis. All roles are disclosed as outputs of the same model.
- Bias Auditor outputs are reviewable concerns, not diagnoses. Every concern requires source labels, uncertainty, an explanation of why it may matter, alternative interpretations, and questions for investigation.
- Contradiction Detective stores the model result separately from the user's case. A suggested classification never silently changes the case status or resolution notes.
- Each workflow records a target entity, exact transmitted source snapshots, provider, model, prompt contract, token counts where supplied, failure or insufficient-evidence status, and a human review decision.

The provider integration has been tested with deterministic local contracts and persistence fixtures. A cancelled live credential authorization transmitted no research content. Model output must never invent or silently fill missing bibliographic or methodological facts.

Research Bias Auditor and the citation-support checker retain local modes that run without a model. Their records are labelled `Local system suggestion`; they create questions for investigation, not findings of bias or definitive citation judgments. Argument Room's local prompts are explicitly labelled as local scaffolds. Model-generated alternatives are separately labelled, citation-validated, and reviewable.

Multiple generated perspectives must be disclosed as simulations, not independent experts. Similarity must not be presented as conceptual equivalence, and an absence from the user's library must not be presented as a research gap.
