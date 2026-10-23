import ResearchAtlasCore
import SwiftUI

struct GlobalSearchView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var resultType = "all"
    @State private var isSearching = false

    private var availableResultTypes: [String] {
        ["all"] + Array(Set(model.searchResults.map(\.entityType))).sorted {
            resultTypeLabel($0) < resultTypeLabel($1)
        }
    }

    private var visibleResults: [SearchResult] {
        resultType == "all" ? model.searchResults : model.searchResults.filter { $0.entityType == resultType }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search papers, PDF pages, notes, questions, claims, concepts, arguments, ideas, and writing", text: $query)
                        .textFieldStyle(.plain)
                        .onSubmit { runSearchImmediately() }
                    if !query.isEmpty {
                        Button("Clear search", systemImage: "xmark.circle.fill") {
                            query = ""
                            resultType = "all"
                            model.searchResults = []
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .font(.title3)
                HStack {
                    Text("Use quotation marks for an exact phrase, for example “collective accuracy”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !model.searchResults.isEmpty {
                        Text("\(visibleResults.count) of \(model.searchResults.count) results")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Picker("Result type", selection: $resultType) {
                            ForEach(availableResultTypes, id: \.self) { type in
                                Text(type == "all" ? "All result types" : resultTypeLabel(type)).tag(type)
                            }
                        }
                        .frame(width: 210)
                    }
                }
            }
            .padding(16)
            .background(.bar)
            List(visibleResults) { result in
                Button {
                    model.openSearchResult(result)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: resultIcon(result.entityType))
                            .font(.title3)
                            .foregroundStyle(.indigo)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(result.title).font(.headline)
                                Spacer()
                                Text(resultTypeLabel(result.entityType)).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(result.snippet).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "Search your research", systemImage: "text.magnifyingglass",
                        description: Text("Full-text search includes source records, PDF pages, notes, questions, analytical records, and writing.")
                    )
                } else if isSearching {
                    ProgressView("Searching local research…")
                } else if visibleResults.isEmpty {
                    ContentUnavailableView(
                        resultType == "all" ? "No matches" : "No \(resultTypeLabel(resultType).lowercased()) matches",
                        systemImage: "text.magnifyingglass",
                        description: Text(resultType == "all" ? "Try fewer terms, a prefix, or a different exact phrase." : "Choose another result type or broaden the search.")
                    )
                }
            }
        }
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                isSearching = false
                model.searchResults = []
                return
            }
            isSearching = true
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            model.search(trimmed)
            if resultType != "all", !model.searchResults.contains(where: { $0.entityType == resultType }) {
                resultType = "all"
            }
            isSearching = false
        }
    }

    private func runSearchImmediately() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = false
        model.search(trimmed)
        if resultType != "all", !model.searchResults.contains(where: { $0.entityType == resultType }) {
            resultType = "all"
        }
    }

    private func resultTypeLabel(_ type: String) -> String {
        switch type {
        case "literature": "Paper"
        case "passage": "PDF passage"
        case "note": "Obsidian note"
        case "project": "Research project"
        case "question": "Research question"
        case "argument": "Argument"
        case "comparison": "Comparison profile"
        case "concept": "Concept"
        case "claim": "Structured claim"
        case "idea": "Research idea"
        case "contradiction": "Contradiction review"
        case "writing": "Writing workspace"
        case "writing-section": "Writing section"
        default: type.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    private func resultIcon(_ type: String) -> String {
        switch type {
        case "literature": "books.vertical"
        case "passage": "doc.text.magnifyingglass"
        case "note": "note.text"
        case "project": "folder"
        case "question": "questionmark.bubble"
        case "argument": "point.3.connected.trianglepath.dotted"
        case "comparison": "tablecells"
        case "concept": "circle.hexagongrid"
        case "claim": "quote.bubble"
        case "idea": "lightbulb"
        case "contradiction": "arrow.left.arrow.right"
        case "writing", "writing-section": "square.and.pencil"
        default: "doc.text"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var aiConfiguration = AIProviderConfiguration()
    @State private var aiCredential = ""

    var body: some View {
        Form {
            Section("Help") {
                Button("Open the complete Learning Center", systemImage: "graduationcap") { model.selectedSection = .learning }
                Text("Step-by-step lessons cover every workspace, source-provenance rule, keyboard shortcut, integration, export, and recovery workflow.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Local research folder — read only") {
                LabeledContent("Folder") {
                    Text(model.localResearchFolderPath ?? "Not selected")
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                LabeledContent("Status", value: model.localFolderStatus)
                if let refreshed = model.localFolderLastRefreshedAt {
                    LabeledContent("Last refreshed", value: refreshed.formatted(date: .abbreviated, time: .shortened))
                }
                Text("Research Atlas discovers PDFs recursively, fingerprints them to avoid duplicate records, and indexes their text for search and evidence retrieval. It never renames, moves, edits, or deletes anything in the selected folder.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(model.localResearchFolderPath == nil ? "Choose Folder…" : "Change Folder…", systemImage: "folder") {
                        model.chooseLocalResearchFolder()
                    }
                    .disabled(model.isBusy)
                    Button("Refresh Folder", systemImage: "arrow.triangle.2.circlepath") {
                        model.refreshLocalResearchFolder()
                    }
                    .disabled(model.isBusy || model.localResearchFolderPath == nil)
                }
            }
            Section("Obsidian — read only") {
                LabeledContent("Vault") { Text(model.obsidianVaultPath ?? "Not selected").lineLimit(2).textSelection(.enabled) }
                Text("Markdown files are discovered and indexed. Research Atlas does not rename, move, or write to the vault.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Choose vault…") { model.chooseObsidianVault() }.disabled(model.isBusy)
                Toggle("Suggest links from matching titles", isOn: Binding(
                    get: { model.titleMatchSuggestionsEnabled },
                    set: { model.setTitleMatchSuggestionsEnabled($0) }
                ))
                Text("Off by default. Title matches are labelled lower confidence and remain suggestions until you confirm them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Local storage") {
                LabeledContent("Database") { Text(model.databasePath).lineLimit(2).textSelection(.enabled) }
                LabeledContent("Database and working logs", value: model.localStorageDescription)
                Button("Rebuild search index") { model.rebuildIndex() }
            }
            Section("Indexing activity") {
                if model.indexingJobs.isEmpty {
                    Text("No recorded indexing jobs.").foregroundStyle(.secondary)
                } else {
                    ForEach(model.indexingJobs.prefix(6)) { job in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Label(job.sourceName, systemImage: indexingIcon(job.status))
                                Spacer()
                                Text(job.status.rawValue).font(.caption.weight(.medium)).foregroundStyle(indexingColor(job.status))
                            }
                            if let total = job.totalUnits, total > 0 {
                                ProgressView(value: Double(job.completedUnits), total: Double(total))
                            } else if job.status == .running {
                                ProgressView().controlSize(.small)
                            }
                            if let failure = job.failureMessage {
                                Text(failure).font(.caption).foregroundStyle(job.status == .failed ? .red : .secondary)
                            }
                        }
                    }
                }
                if model.isIndexingCancellable {
                    Button("Cancel Current PDF Indexing", role: .destructive) { model.cancelCurrentIndexing() }
                }
                Text("A single-PDF cancellation is discarded before commit. A cancelled folder refresh keeps PDFs already indexed in earlier completed steps. Jobs interrupted by an app exit are reported as failed on the next launch.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Export and recovery") {
                Text("Portable exports contain human-readable files. Database backups preserve the complete workspace. Restore validates a selected backup and shows its contents before making any change.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Export Portable Package…") { model.exportWorkspace() }
                    Button("Back Up Database…") { model.backupDatabase() }
                    Button("Restore Database…") { model.chooseDatabaseRestore() }
                        .disabled(model.isBusy)
                }
                if let path = model.lastRecoveryBackupPath {
                    LabeledContent("Pre-restore recovery copy") {
                        Text(path).lineLimit(2).textSelection(.enabled)
                    }
                }
            }
            Section("Where grounded AI is available") {
                HStack(alignment: .top, spacing: 14) {
                    AIProviderStatusPill()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI appears beside the research work it can help with")
                            .font(.headline)
                        Text("Start from Research Home, a question, an argument, a saved retrieval set, or a writing section. Research Atlas carries that context into the appropriate tool instead of making you copy it into a separate chat.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                aiEntryPoint(
                    icon: "sparkles.rectangle.stack",
                    title: "Research Assistant",
                    detail: "Ask a bounded question over one inspected retrieval set; review citation-bearing claims before using them.",
                    destination: .assistant
                )
                aiEntryPoint(
                    icon: "point.3.connected.trianglepath.dotted",
                    title: "Arguments",
                    detail: "Open a proposition, then launch Critical Review or Argument Room with that exact argument already selected.",
                    destination: .arguments
                )
                aiEntryPoint(
                    icon: "arrow.left.arrow.right",
                    title: "Contradiction Detective",
                    detail: "Request a grounded assessment for an existing comparison case without changing its human review state.",
                    destination: .contradictions
                )
                aiEntryPoint(
                    icon: "brain.head.profile",
                    title: "Collective Intelligence Lab",
                    detail: "Run one explicitly approved, source-grounded simulated role turn at a time.",
                    destination: .collectiveLab
                )
                aiEntryPoint(
                    icon: "square.and.pencil",
                    title: "Research Writing",
                    detail: "Prepare a source-support question from the active section, then choose and inspect the evidence set.",
                    destination: .writing
                )

                HStack {
                    Button("Build an Evidence Set", systemImage: "text.magnifyingglass") {
                        model.evidenceExplorerMode = 0
                        model.selectedSection = .evidence
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Open Research Assistant", systemImage: "sparkles") {
                        model.selectedSection = .assistant
                    }
                }
                Text("Nothing is transmitted from these pages automatically. Every model action requires a saved source set, a content preview, and approval. Generated text remains a suggestion and cannot silently edit your records.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("AI providers") {
                Picker("Provider", selection: $aiConfiguration.provider) {
                    ForEach(AIProviderKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                TextField(aiConfiguration.provider.isLocal ? "Local API endpoint" : "HTTPS API endpoint", text: $aiConfiguration.endpoint)
                    .disabled(aiConfiguration.provider == .disabled || !aiConfiguration.provider.endpointIsEditable)
                Text(aiConfiguration.provider.transportDescription)
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Model identifier", text: $aiConfiguration.model)
                    .disabled(aiConfiguration.provider == .disabled)
                if aiConfiguration.provider == .ollamaLocal {
                    LabeledContent("Local engine") {
                        Label(model.ollamaRuntimeStatus.title, systemImage: model.ollamaRuntimeStatus.systemImage)
                            .foregroundStyle(localRuntimeColor)
                    }
                    Text(model.ollamaRuntimeStatus.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Reasoning effort", selection: $aiConfiguration.reasoningEffort) {
                        ForEach(AIReasoningEffort.allCases, id: \.self) { effort in
                            Text(effort.displayName).tag(effort)
                        }
                    }
                    Stepper(
                        "Stop after \(aiConfiguration.localRuntimeIdleMinutes) idle minute\(aiConfiguration.localRuntimeIdleMinutes == 1 ? "" : "s")",
                        value: $aiConfiguration.localRuntimeIdleMinutes,
                        in: 1...120
                    )
                    Text("Medium reasoning is the recommended balance. High can improve difficult analysis but takes longer. Research Atlas uses only the model's schema-constrained final answer; private reasoning text is not saved as research evidence.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Prepare Local Engine", systemImage: "power") {
                            model.prepareManagedLocalAIEngine()
                        }
                        .disabled(
                            model.isBusy || !aiConfiguration.externalTransmissionEnabled ||
                            !aiConfiguration.hasSameOperationalSettings(as: model.aiProviderConfiguration)
                        )
                        Button("Stop Managed Engine", systemImage: "stop.circle", role: .destructive) {
                            model.stopManagedLocalAIEngine()
                        }
                        .disabled(model.isBusy || !model.ollamaRuntimeManagedByApp)
                    }
                }
                if aiConfiguration.provider.requiresCredential {
                    SecureField(
                        model.aiCredentialStored
                            ? "Replace stored \(aiConfiguration.provider.credentialLabel)"
                            : aiConfiguration.provider.credentialLabel,
                        text: $aiCredential
                    )
                    LabeledContent("Credential") {
                        Label(model.aiCredentialStored ? "Stored in macOS Keychain" : "Not stored", systemImage: model.aiCredentialStored ? "key.fill" : "key.slash")
                            .foregroundStyle(model.aiCredentialStored ? .green : .secondary)
                    }
                } else if aiConfiguration.provider.isLocal {
                    LabeledContent("Credential") {
                        Label("Not required for loopback local models", systemImage: "lock.open")
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(aiConfiguration.provider.isLocal ? "Allow local model requests" : "Allow external AI transmission", isOn: $aiConfiguration.externalTransmissionEnabled)
                    .disabled(aiConfiguration.provider == .disabled)
                Text(aiConfiguration.provider.isLocal
                     ? (aiConfiguration.provider == .ollamaLocal
                        ? "Off by default. Research Atlas starts its bundled, loopback-only engine when needed and stops only an engine it started after the chosen idle period. The model stays in your existing local Ollama store. Every research request still requires a content preview and approval."
                        : "Off by default. LM Studio remains an optional local provider: load a model and start its server separately. Requests are restricted to 127.0.0.1 and still require a content preview and approval. No credential is stored or sent.")
                     : "Off by default. Even when enabled, every request requires a separate preview and approval. API credentials are kept in a fresh, application-only macOS Keychain record, are never included in exports, and are not read during app launch or ordinary settings browsing. Retired Keychain records are not queried, so upgrading may require pasting the key once here.")
                    .font(.caption).foregroundStyle(.secondary)
                Stepper("Maximum passages per request: \(aiConfiguration.maximumPassages)", value: $aiConfiguration.maximumPassages, in: 1...40)
                    .disabled(aiConfiguration.provider == .disabled)
                Stepper("Maximum output tokens: \(aiConfiguration.maximumOutputTokens)", value: $aiConfiguration.maximumOutputTokens, in: 128...16_000, step: 128)
                    .disabled(aiConfiguration.provider == .disabled)
                if aiConfiguration.provider == .ollamaLocal && aiConfiguration.maximumOutputTokens < 2_048 {
                    Label("Reasoning models need room for internal reasoning and the final structured answer. Use at least 2,048 tokens; 4,096 is recommended.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                HStack {
                    Button("Save AI Settings") {
                        if let savedConfiguration = model.saveAIProviderSettings(aiConfiguration, credential: aiCredential) {
                            aiConfiguration = savedConfiguration
                            aiCredential = ""
                        }
                    }
                    .disabled(aiConfiguration.provider != .disabled && (
                        aiConfiguration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        aiConfiguration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ))
                    if aiConfiguration.provider.requiresCredential {
                        Button("Remove Credential", role: .destructive) {
                            model.removeAICredential(for: aiConfiguration.provider)
                            aiCredential = ""
                        }
                            .disabled(!model.aiCredentialStored)
                    }
                    Button("Test Connection", systemImage: "network.badge.shield.half.filled") {
                        model.testAIProviderConnection()
                    }
                    .disabled(
                        model.isBusy || (aiConfiguration.provider.requiresCredential && !model.aiCredentialStored) ||
                        aiConfiguration.provider == .disabled || !aiConfiguration.externalTransmissionEnabled ||
                        !aiConfiguration.hasSameOperationalSettings(as: model.aiProviderConfiguration)
                    )
                }
                if !aiConfiguration.hasSameOperationalSettings(as: model.aiProviderConfiguration) {
                    Label("Save these provider changes before testing the connection.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text("Test Connection sends only a static health-check sentence to the configured provider. It does not send papers, notes, project details, retrieval passages, or database content.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("All core reading, search, comparison, question, argument, claim, idea, contradiction, and export workflows remain local and work without an AI provider.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 6)
        .onAppear {
            aiConfiguration = model.aiProviderConfiguration
        }
        .onChange(of: aiConfiguration.provider) { oldProvider, newProvider in
            guard oldProvider != newProvider else { return }
            aiConfiguration.applyDefaults(for: newProvider)
            aiCredential = ""
            model.refreshAICredentialState(for: newProvider)
        }
        .sheet(item: Binding(
            get: { model.pendingRestorePreview },
            set: { value in if value == nil { model.cancelDatabaseRestore() } }
        )) { preview in
            DatabaseRestorePreviewView(preview: preview)
                .environmentObject(model)
                .interactiveDismissDisabled(model.isBusy)
        }
    }

    private func indexingIcon(_ status: IndexingJobStatus) -> String {
        switch status {
        case .queued: "clock"
        case .running: "arrow.triangle.2.circlepath"
        case .completed: "checkmark.circle"
        case .cancelled: "xmark.circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    private func aiEntryPoint(icon: String, title: String, detail: String, destination: AppSection) -> some View {
        Button {
            model.selectedSection = destination
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(.purple)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var localRuntimeColor: Color {
        switch model.ollamaRuntimeStatus {
        case .stopped: .secondary
        case .starting, .loading: .orange
        case .ready: .green
        case .generating: .purple
        case .unavailable: .red
        }
    }

    private func indexingColor(_ status: IndexingJobStatus) -> Color {
        switch status {
        case .completed: .green
        case .failed: .red
        case .cancelled: .orange
        default: .secondary
        }
    }
}

private struct DatabaseRestorePreviewView: View {
    @EnvironmentObject private var model: AppModel
    let preview: DatabaseRestorePreview

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.badge.checkmark")
                    .font(.system(size: 30))
                    .foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Restore this database?").font(.title2.weight(.semibold))
                    Text(preview.url.lastPathComponent).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            Text("The backup passed SQLite integrity, foreign-key, and Research Atlas compatibility checks. Restoring replaces the current workspace, but first creates a complete recovery copy of it.")
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
                previewRow("Schema", value: String(preview.schemaVersion))
                previewRow("Literature", value: preview.literatureCount.formatted())
                previewRow("Obsidian notes", value: preview.noteCount.formatted())
                previewRow("Projects", value: preview.projectCount.formatted())
                previewRow("Questions", value: preview.questionCount.formatted())
                previewRow("Arguments", value: preview.argumentCount.formatted())
                previewRow("Evidence links", value: preview.evidenceCount.formatted())
            }
            .padding(14)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Button("Cancel") { model.cancelDatabaseRestore() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
                Button("Restore Database", role: .destructive) { model.confirmDatabaseRestore(preview) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isBusy)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    @ViewBuilder
    private func previewRow(_ label: String, value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }
}
