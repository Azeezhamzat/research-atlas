import ResearchAtlasCore
import SwiftUI

struct CollectiveIntelligenceLabView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingNewExperiment = false

    private var selectedExperiment: CollectiveExperiment? {
        model.collectiveExperiments.first { $0.id == model.selectedCollectiveExperimentID }
    }

    var body: some View {
        HSplitView {
            List(model.collectiveExperiments, selection: $model.selectedCollectiveExperimentID) { experiment in
                VStack(alignment: .leading, spacing: 5) {
                    Text(experiment.title).font(.headline).lineLimit(3)
                    Text(experiment.interactionMode.rawValue).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text(experiment.status.rawValue)
                        Spacer()
                        Text("\(model.turns(for: experiment.id).count) turns")
                    }
                    .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 5).tag(experiment.id)
            }
            .overlay {
                if model.collectiveExperiments.isEmpty {
                    ContentUnavailableView(
                        "No experimental records", systemImage: "brain.head.profile",
                        description: Text("Design a transparent role simulation, then run grounded model turns or record human observations.")
                    )
                }
            }
            .frame(minWidth: 300, idealWidth: 350)
            if let selectedExperiment {
                CollectiveExperimentDetail(experiment: selectedExperiment).frame(minWidth: 680)
            } else {
                ContentUnavailableView("Select an experiment", systemImage: "arrow.left")
            }
        }
        .toolbar { Button("New Experiment", systemImage: "plus") { showingNewExperiment = true } }
        .sheet(isPresented: $showingNewExperiment) { CollectiveExperimentSheet(experiment: nil) }
    }
}

private struct CollectiveExperimentDetail: View {
    @EnvironmentObject private var model: AppModel
    let experiment: CollectiveExperiment
    @State private var showingEdit = false
    @State private var showingAgent = false
    @State private var showingManualTurn = false
    @State private var showingModelTurn = false
    @State private var showingDelete = false

    private var agents: [CollectiveAgent] { model.agents(for: experiment.id) }
    private var turns: [CollectiveTurn] { model.turns(for: experiment.id) }
    private var providerReady: Bool {
        model.aiProviderReadyForRequests
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("CONTROLLED ROLE SIMULATION").font(.caption.weight(.bold)).foregroundStyle(.orange)
                        Text(experiment.title).font(.largeTitle.weight(.semibold))
                        Text(experiment.interactionMode.rawValue).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Edit Design") { showingEdit = true }
                }
                Label(
                    "All model roles use the same configured model. They are simulated perspectives—not independent experts, independent evidence, or a validated measure of collective intelligence.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .padding(12).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                if !experiment.researchPurpose.isEmpty {
                    LabeledContent("Research purpose") { Text(experiment.researchPurpose).textSelection(.enabled) }
                }
                GroupBox("Task instructions") {
                    Text(experiment.taskInstructions.isEmpty ? "No task instructions recorded." : experiment.taskInstructions)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                GroupBox("Model execution and provenance") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                        GridRow {
                            Text("Configured now").foregroundStyle(.secondary)
                            Text("\(model.aiProviderConfiguration.provider.displayName) · \(model.aiProviderConfiguration.model)")
                        }
                        GridRow {
                            Text("Connection").foregroundStyle(.secondary)
                            Label(
                                providerReady ? "Ready for individually approved requests" : "Finish or enable the AI connection in Integrations",
                                systemImage: providerReady ? "checkmark.circle.fill" : "exclamationmark.circle"
                            ).foregroundStyle(providerReady ? .green : .orange)
                        }
                        GridRow { Text("Last recorded provider").foregroundStyle(.secondary); Text(experiment.provider) }
                        GridRow { Text("Last recorded model").foregroundStyle(.secondary); Text(experiment.model) }
                        GridRow { Text("Prompt contract").foregroundStyle(.secondary); Text(experiment.promptVersion) }
                        GridRow { Text("Model settings").foregroundStyle(.secondary); Text(experiment.modelSettingsJSON).textSelection(.enabled) }
                        GridRow { Text("Status").foregroundStyle(.secondary); Text(experiment.status.rawValue) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Roles and information conditions").font(.title2.weight(.semibold))
                            Spacer()
                            Button("Add Role", systemImage: "person.badge.plus") { showingAgent = true }
                        }
                        if agents.isEmpty { Text("Add at least one explicit role before running a model turn.").foregroundStyle(.secondary) }
                        ForEach(agents) { agent in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(agent.position). \(agent.label)").font(.headline)
                                    if !agent.role.isEmpty { Text(agent.role) }
                                    Text(agent.informationAvailable.isEmpty ? "Information: task and approved source passages" : "Information: \(agent.informationAvailable)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Remove", role: .destructive) { model.deleteCollectiveAgent(agent) }.buttonStyle(.link)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recorded interaction").font(.title2.weight(.semibold))
                        Text("One approved request creates one attributable turn; nothing runs autonomously.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Record Manual Turn", systemImage: "square.and.pencil") { showingManualTurn = true }
                    Button("Run Model Turn", systemImage: "sparkles") { showingModelTurn = true }
                        .buttonStyle(.borderedProminent).disabled(agents.isEmpty || !providerReady)
                }
                if !providerReady {
                    Button("Open AI Integrations") { model.selectedSection = .settings }.buttonStyle(.link)
                }
                if turns.isEmpty { Text("No judgments, deliberation turns, or interruptions recorded.").foregroundStyle(.secondary) }
                ForEach(turns) { turn in CollectiveTurnCard(turn: turn, agents: agents) }
                HStack {
                    if experiment.status != .completed {
                        Button("Mark Complete", systemImage: "checkmark.circle") { model.completeCollectiveExperiment(experiment) }
                    }
                    Button("Delete Experiment", systemImage: "trash", role: .destructive) { showingDelete = true }
                    Spacer()
                }
            }
            .padding(26).frame(maxWidth: 1020, alignment: .leading)
        }
        .sheet(isPresented: $showingEdit) { CollectiveExperimentSheet(experiment: experiment) }
        .sheet(isPresented: $showingAgent) { CollectiveAgentSheet(experimentID: experiment.id) }
        .sheet(isPresented: $showingManualTurn) { CollectiveManualTurnSheet(experiment: experiment) }
        .sheet(isPresented: $showingModelTurn) { CollectiveModelTurnSheet(experiment: experiment) }
        .confirmationDialog("Delete this experimental record?", isPresented: $showingDelete) {
            Button("Delete Experiment", role: .destructive) { model.deleteCollectiveExperiment(experiment) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct CollectiveTurnCard: View {
    @EnvironmentObject private var model: AppModel
    let turn: CollectiveTurn
    let agents: [CollectiveAgent]
    @State private var showingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Round \(turn.round) · \(turn.kind.rawValue)").font(.headline)
                Text(turn.agentID.flatMap { id in agents.first { $0.id == id }?.label } ?? "Researcher/system").font(.subheadline)
                Spacer()
                Label(
                    turn.modelGenerated ? "Model-generated" : (turn.errorMessage == nil ? "Human-recorded" : "Interrupted"),
                    systemImage: turn.modelGenerated ? "sparkles" : (turn.errorMessage == nil ? "person.fill" : "exclamationmark.triangle.fill")
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(turn.modelGenerated ? .purple : (turn.errorMessage == nil ? .secondary : .orange))
            }
            if !turn.informationAvailable.isEmpty {
                Text("Information condition: \(turn.informationAvailable)").font(.caption).foregroundStyle(.secondary)
            }
            if !turn.promptText.isEmpty {
                DisclosureGroup("Exact prompt and context sent") {
                    Text(turn.promptText).font(.caption).textSelection(.enabled).padding(.top, 5)
                }
            }
            Text(turn.responseText).textSelection(.enabled)
            HStack {
                if let confidence = turn.confidence {
                    Text("Confidence: \(Int((confidence * 100).rounded()))%").font(.caption.weight(.medium))
                }
                ForEach(model.citations(forCollectiveTurn: turn.id)) { citation in
                    Button("[\(citation.label)] p. \(citation.page) · \(citation.citationStatus.rawValue)") {
                        model.openAnalysisCitation(AIAnalysisCitation(
                            analysisID: UUID(), label: citation.label, sourcePassageID: citation.sourcePassageID,
                            literatureID: citation.literatureID, page: citation.page, quotedPassage: citation.quotedPassage,
                            sourceDocumentHash: citation.sourceDocumentHash, citationStatus: citation.citationStatus
                        ))
                    }.buttonStyle(.link)
                }
                Spacer()
                Button("Delete", role: .destructive) { showingDelete = true }.buttonStyle(.link)
            }
        }
        .padding(13).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .confirmationDialog("Delete this recorded turn?", isPresented: $showingDelete) {
            Button("Delete Turn", role: .destructive) { model.deleteCollectiveTurn(turn) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct CollectiveExperimentSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let original: CollectiveExperiment?
    @State private var title: String
    @State private var purpose: String
    @State private var task: String
    @State private var mode: CollectiveInteractionMode
    @State private var status: CollectiveExperimentStatus

    init(experiment: CollectiveExperiment?) {
        original = experiment
        _title = State(initialValue: experiment?.title ?? "")
        _purpose = State(initialValue: experiment?.researchPurpose ?? "")
        _task = State(initialValue: experiment?.taskInstructions ?? "")
        _mode = State(initialValue: experiment?.interactionMode ?? .independent)
        _status = State(initialValue: experiment?.status ?? .designing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(original == nil ? "Design Controlled Role Simulation" : "Edit Simulation Design").font(.title2.weight(.semibold))
            Label("Provider, model, prompt version, and runtime settings are captured automatically when a model turn is run.", systemImage: "lock.shield")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Experiment title", text: $title)
            TextField("Research purpose", text: $purpose, axis: .vertical).lineLimit(2...4)
            TextField("Task instructions", text: $task, axis: .vertical).lineLimit(3...7)
            Picker("Interaction mode", selection: $mode) {
                ForEach(CollectiveInteractionMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("Status", selection: $status) {
                ForEach(CollectiveExperimentStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save Design") {
                    var experiment = original ?? CollectiveExperiment(title: title)
                    experiment.title = title; experiment.researchPurpose = purpose; experiment.taskInstructions = task
                    experiment.interactionMode = mode; experiment.status = status
                    model.saveCollectiveExperiment(experiment); dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 720)
    }
}

private struct CollectiveAgentSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let experimentID: UUID
    @State private var label = ""
    @State private var role = ""
    @State private var information = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Simulation Role").font(.title2.weight(.semibold))
            TextField("Label, e.g. Methodological critic", text: $label)
            TextField("Assigned role", text: $role)
            TextField("Information available to this role", text: $information, axis: .vertical).lineLimit(3...6)
            Text("The information condition is inserted into every prompt for this role and saved on each completed turn.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer(); Button("Cancel") { dismiss() }
                Button("Add Role") {
                    model.addCollectiveAgent(experimentID: experimentID, label: label, role: role, information: information); dismiss()
                }
                .buttonStyle(.borderedProminent).disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 620)
    }
}

private struct CollectiveManualTurnSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let experiment: CollectiveExperiment
    @State private var agentID: UUID?
    @State private var round = 1
    @State private var kind: CollectiveTurnKind = .researcherObservation
    @State private var information = ""
    @State private var prompt = ""
    @State private var response = ""
    @State private var confidenceText = ""
    @State private var passageID = ""

    private var passageOptions: [RetrievedPassage] {
        var seen = Set<String>()
        return model.retrievedPassages.filter { $0.citationStatus == .current && seen.insert($0.sourcePassageID).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Record Human or External Observation").font(.title2.weight(.semibold))
            Label("This form never calls a model and never labels the record as model-generated.", systemImage: "person.fill")
                .font(.callout).foregroundStyle(.secondary)
            Picker("Role", selection: $agentID) {
                Text("Researcher/system observation").tag(nil as UUID?)
                ForEach(model.agents(for: experiment.id)) { Text($0.label).tag($0.id as UUID?) }
            }
            Stepper("Round \(round)", value: $round, in: 1...100)
            Picker("Turn kind", selection: $kind) { ForEach(CollectiveTurnKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            TextField("Information available for this turn", text: $information, axis: .vertical).lineLimit(2...5)
            TextField("Exact prompt, if applicable", text: $prompt, axis: .vertical).lineLimit(2...5)
            TextField("Recorded response or observation", text: $response, axis: .vertical).lineLimit(4...9)
            TextField("Confidence 0–100, optional", text: $confidenceText)
            Picker("Exact source passage, optional", selection: $passageID) {
                Text("No source passage").tag("")
                ForEach(passageOptions, id: \.sourcePassageID) { passage in
                    Text("\(model.literature.first { $0.id == passage.literatureID }?.title ?? "Unavailable"), p. \(passage.page)").tag(passage.sourcePassageID)
                }
            }
            HStack {
                Spacer(); Button("Cancel") { dismiss() }
                Button("Record Turn") {
                    let confidence = Double(confidenceText).map { $0 / 100 }
                    model.addCollectiveTurn(
                        experimentID: experiment.id, agentID: agentID, round: round, kind: kind,
                        information: information, prompt: prompt, response: response, confidence: confidence,
                        modelGenerated: false, sourcePassageID: passageID.isEmpty ? nil : passageID
                    ); dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (Double(confidenceText).map { !(0...100).contains($0) } ?? false))
            }
        }
        .padding(24).frame(width: 720)
    }
}

private struct CollectiveModelTurnSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let experiment: CollectiveExperiment
    @State private var agentID: UUID?
    @State private var retrievalSetID: UUID?
    @State private var round = 1
    @State private var kind: CollectiveTurnKind = .initialJudgment
    @State private var additionalInstruction = ""

    private var selectedPassageCount: Int {
        guard let retrievalSetID else { return 0 }
        return model.passages(for: retrievalSetID).filter { $0.citationStatus == .current }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sparkles.rectangle.stack").font(.system(size: 28)).foregroundStyle(.purple)
                VStack(alignment: .leading) {
                    Text("Prepare One Grounded Model Turn").font(.title2.weight(.semibold))
                    Text("A separate external-transmission preview appears before anything is sent.").foregroundStyle(.secondary)
                }
            }
            GroupBox("Execution boundary") {
                VStack(alignment: .leading, spacing: 7) {
                    LabeledContent("Provider") { Text(model.aiProviderConfiguration.provider.displayName) }
                    LabeledContent("Model") { Text(model.aiProviderConfiguration.model) }
                    LabeledContent("Turn limit") { Text("Exactly one response") }
                    Text("This role uses the same configured model as every other role. The result is a simulated, reviewable contribution—not an independent expert judgment.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Picker("Simulated role", selection: $agentID) {
                Text("Choose a role").tag(nil as UUID?)
                ForEach(model.agents(for: experiment.id)) { agent in Text(agent.label).tag(agent.id as UUID?) }
            }
            Stepper("Round \(round)", value: $round, in: 1...100)
            Picker("Turn kind", selection: $kind) {
                ForEach(CollectiveTurnKind.allCases.filter { $0 != .researcherObservation && $0 != .interruption }, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }
            Picker("Saved retrieval set", selection: $retrievalSetID) {
                Text("Choose evidence").tag(nil as UUID?)
                ForEach(model.retrievalSets) { set in Text(set.name).tag(set.id as UUID?) }
            }
            if retrievalSetID != nil {
                Label("\(selectedPassageCount) current paper passages are available; the configured request limit still applies.", systemImage: "doc.text.magnifyingglass")
                    .font(.caption).foregroundStyle(selectedPassageCount > 0 ? Color.secondary : Color.orange)
            }
            TextField("Additional instruction for this turn, optional", text: $additionalInstruction, axis: .vertical).lineLimit(2...5)
            Text("The preview will list the exact source snapshots, destination, model, task, and request size. Source changes or new turns after approval invalidate the request.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer(); Button("Cancel") { dismiss() }
                Button("Review Transmission") {
                    guard let agentID else { return }
                    let setID = retrievalSetID
                    dismiss()
                    DispatchQueue.main.async {
                        model.prepareAICollectiveTurn(
                            experimentID: experiment.id, agentID: agentID, round: round, kind: kind,
                            additionalInstruction: additionalInstruction, retrievalSetID: setID
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(agentID == nil || retrievalSetID == nil || selectedPassageCount == 0)
            }
        }
        .padding(24).frame(width: 740)
        .onAppear {
            agentID = model.agents(for: experiment.id).first?.id
            retrievalSetID = model.selectedRetrievalSetID ?? model.retrievalSets.first?.id
            round = max(1, (model.turns(for: experiment.id).map(\.round).max() ?? 0) + 1)
        }
    }
}
