import ResearchAtlasCore
import SwiftUI

struct ArgumentRoomView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingNewSession = false

    private var selectedSession: DeliberationSession? { model.deliberationSessions.first { $0.id == model.selectedDeliberationSessionID } }

    var body: some View {
        HSplitView {
            List(model.deliberationSessions, selection: $model.selectedDeliberationSessionID) { session in
                VStack(alignment: .leading, spacing: 5) {
                    Text(session.title).font(.headline).lineLimit(3)
                    HStack { Text(session.status.rawValue); Spacer(); Text(session.model) }
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 5).tag(session.id)
            }
            .overlay {
                if model.deliberationSessions.isEmpty {
                    ContentUnavailableView("No deliberations", systemImage: "person.3.sequence", description: Text("Create a structured critical review around an existing argument."))
                }
            }
            .frame(minWidth: 300, idealWidth: 350)
            if let selectedSession {
                ArgumentRoomDetailView(session: selectedSession).frame(minWidth: 600)
            } else {
                ContentUnavailableView("Select a deliberation", systemImage: "arrow.left")
            }
        }
        .toolbar { Button("New Deliberation", systemImage: "plus") { showingNewSession = true } }
        .sheet(isPresented: $showingNewSession) { NewDeliberationSheet() }
        .onAppear { if model.requestedDeliberationArgumentID != nil { showingNewSession = true } }
        .onChange(of: model.requestedDeliberationArgumentID) { _, argumentID in
            if argumentID != nil { showingNewSession = true }
        }
    }
}

private struct ArgumentRoomDetailView: View {
    @EnvironmentObject private var model: AppModel
    let session: DeliberationSession
    @State private var response = ""
    @State private var showingDelete = false

    private var argument: ResearchArgument? { model.arguments.first { $0.id == session.argumentID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(session.title).font(.largeTitle.weight(.semibold))
                Label(session.disclosure, systemImage: "info.circle.fill")
                    .font(.callout).foregroundStyle(.orange)
                if let argument {
                    GroupBox("Proposition") { Text(argument.proposition).font(.headline).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                }
                HStack {
                    LabeledContent("Provider", value: session.provider)
                    LabeledContent("Model", value: session.model)
                    LabeledContent("Status", value: session.status.rawValue)
                }
                ForEach(model.messages(for: session.id)) { message in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(message.perspective.rawValue).font(.headline)
                            Text(message.phase.rawValue).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(message.modelGenerated ? "Model-generated" : (message.perspective == .user ? "Researcher-authored" : "Local review prompt"))
                                .font(.caption.weight(.medium)).foregroundStyle(message.modelGenerated ? .purple : .secondary)
                        }
                        Text(message.content).textSelection(.enabled)
                        if !model.citations(forDeliberationMessage: message.id).isEmpty {
                            HStack(spacing: 10) {
                                ForEach(model.citations(forDeliberationMessage: message.id)) { citation in
                                    Button("[\(citation.label)] p. \(citation.page) · \(citation.citationStatus.rawValue)") {
                                        model.openDeliberationCitation(citation)
                                    }
                                    .buttonStyle(.link)
                                }
                            }
                            .font(.caption)
                        }
                    }
                    .padding(13).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                }
                if let analysis = model.analyses(targetType: .deliberationSession, targetID: session.id).first {
                    AIAnalysisReviewPanel(analysis: analysis, responseTitle: "Recorded synthesis")
                }
                GroupBox("Respond as researcher") {
                    VStack(alignment: .leading, spacing: 9) {
                        TextField("Challenge a prompt, record an answer, or preserve an unresolved question", text: $response, axis: .vertical).lineLimit(3...8)
                        HStack {
                            Button("Add Response") { model.addResearcherResponse(sessionID: session.id, text: response); response = "" }
                                .disabled(response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if session.status != .completed { Button("Mark Deliberation Complete") { model.completeDeliberation(session) } }
                            Spacer()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Delete Deliberation", systemImage: "trash", role: .destructive) { showingDelete = true }
            }
            .padding(26).frame(maxWidth: 920, alignment: .leading)
        }
        .confirmationDialog("Delete this deliberation record?", isPresented: $showingDelete) {
            Button("Delete Deliberation", role: .destructive) { model.deleteDeliberation(session) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct NewDeliberationSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var argumentID: UUID?
    @State private var useConfiguredModel = false
    @State private var retrievalSetID: UUID?

    private var expectedLiteratureIDs: Set<UUID> {
        guard let argumentID else { return [] }
        return Set(model.evidence(for: argumentID).map(\.literatureID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Argument Room").font(.title2.weight(.semibold))
            Text(useConfiguredModel
                 ? "The configured model will simulate all critical roles. They are not independent experts. Exact source passages are sent only after a separate consent preview."
                 : "Local mode creates transparent review prompts without invoking an AI provider. Your responses become part of the preserved session record.")
                .foregroundStyle(.secondary)
            Picker("Argument", selection: $argumentID) {
                Text("Choose an argument").tag(nil as UUID?)
                ForEach(model.arguments) { Text($0.proposition).tag($0.id as UUID?) }
            }
            Toggle("Generate a source-grounded model deliberation", isOn: $useConfiguredModel)
            if useConfiguredModel {
                AIProviderStatusPill()
                Picker("Evidence set", selection: $retrievalSetID) {
                    Text("Choose a retrieval set").tag(nil as UUID?)
                    ForEach(model.retrievalSets) { set in
                        Text("\(set.name) (\(model.passages(for: set.id).filter { $0.citationStatus == .current }.count) current)")
                            .tag(set.id as UUID?)
                    }
                }
                GroundingFitSummary(
                    retrievalSetID: retrievalSetID,
                    expectedLiteratureIDs: expectedLiteratureIDs
                )
                Label("A consent screen will show the provider, model, task, passage list, and request size before anything is sent.", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.aiProviderReadyForRequests {
                    Button("Finish AI Setup in Integrations") { dismiss(); model.selectedSection = .settings }
                        .buttonStyle(.link)
                }
            }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button(useConfiguredModel ? "Prepare Transmission" : "Create Local Room") {
                if let argumentID, let argument = model.arguments.first(where: { $0.id == argumentID }) {
                    if useConfiguredModel {
                        let selectedSet = retrievalSetID
                        dismiss()
                        DispatchQueue.main.async {
                            model.prepareAIDeliberation(for: argument, retrievalSetID: selectedSet)
                        }
                    } else {
                        model.createLocalDeliberation(for: argument)
                        dismiss()
                    }
                }
            }.buttonStyle(.borderedProminent).disabled(
                argumentID == nil || (useConfiguredModel && (retrievalSetID == nil || !model.aiProviderReadyForRequests))
            ) }
        }
        .padding(24).frame(width: 680)
        .onAppear {
            argumentID = model.requestedDeliberationArgumentID ?? model.selectedArgumentID ?? model.arguments.first?.id
            model.requestedDeliberationArgumentID = nil
            retrievalSetID = model.suggestedRetrievalSetID(matching: expectedLiteratureIDs)
        }
    }
}
