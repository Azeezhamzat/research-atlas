import ResearchAtlasCore
import SwiftUI

struct BiasAuditorView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingNewAudit = false

    private var selectedAudit: BiasAudit? { model.biasAudits.first { $0.id == model.selectedBiasAuditID } }

    var body: some View {
        HSplitView {
            List(model.biasAudits, selection: $model.selectedBiasAuditID) { audit in
                VStack(alignment: .leading, spacing: 5) {
                    Text(audit.title).font(.headline).lineLimit(3)
                    HStack {
                        Text(audit.origin.rawValue)
                        Spacer()
                        Text("\(model.concerns(for: audit.id).count) concerns")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 5).tag(audit.id)
            }
            .overlay {
                if model.biasAudits.isEmpty {
                    ContentUnavailableView("No critical reviews", systemImage: "checkmark.shield", description: Text("Run a local evidence audit on an argument to generate investigation questions—not a diagnosis of personal bias."))
                }
            }
            .frame(minWidth: 300, idealWidth: 350)
            if let selectedAudit {
                BiasAuditDetailView(audit: selectedAudit).frame(minWidth: 600)
            } else {
                ContentUnavailableView("Select a critical review", systemImage: "arrow.left")
            }
        }
        .toolbar { Button("Audit Argument", systemImage: "plus") { showingNewAudit = true } }
        .sheet(isPresented: $showingNewAudit) { NewBiasAuditSheet() }
        .onAppear { if model.requestedBiasAuditArgumentID != nil { showingNewAudit = true } }
        .onChange(of: model.requestedBiasAuditArgumentID) { _, argumentID in
            if argumentID != nil { showingNewAudit = true }
        }
    }
}

private struct BiasAuditDetailView: View {
    @EnvironmentObject private var model: AppModel
    let audit: BiasAudit
    @State private var showingDelete = false

    private var argument: ResearchArgument? { model.arguments.first { $0.id == audit.argumentID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Critical questions, not a bias diagnosis").font(.caption.weight(.bold)).foregroundStyle(.orange)
                        Text(audit.title).font(.largeTitle.weight(.semibold))
                        Text(audit.scopeNote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(audit.origin.rawValue).font(.caption).padding(7).background(.quaternary, in: Capsule())
                }
                if let argument {
                    GroupBox("Argument examined") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(argument.proposition).font(.headline).textSelection(.enabled)
                            if !argument.qualification.isEmpty { Text("Qualification: \(argument.qualification)").foregroundStyle(.secondary) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let analysisID = audit.analysisID,
                   let analysis = model.aiAnalyses.first(where: { $0.id == analysisID }) {
                    AIAnalysisReviewPanel(analysis: analysis, responseTitle: "Critical-review summary")
                }
                ForEach(model.concerns(for: audit.id)) { concern in
                    BiasConcernCard(concern: concern)
                }
                Button("Delete Critical Review", systemImage: "trash", role: .destructive) { showingDelete = true }
            }
            .padding(26).frame(maxWidth: 920, alignment: .leading)
        }
        .confirmationDialog("Delete this application-owned review?", isPresented: $showingDelete) {
            Button("Delete Review", role: .destructive) { model.deleteBiasAudit(audit) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The argument, sources, and evidence relationships are not changed.") }
    }
}

private struct BiasConcernCard: View {
    @EnvironmentObject private var model: AppModel
    let concern: BiasConcern
    @State private var disposition: ReviewDisposition
    @State private var notes: String

    init(concern: BiasConcern) {
        self.concern = concern
        _disposition = State(initialValue: concern.disposition)
        _notes = State(initialValue: concern.reviewNotes)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(concern.kind.rawValue).font(.title3.weight(.semibold))
                    Spacer()
                    Text(concern.disposition.rawValue).font(.caption.weight(.medium))
                }
                Text(concern.potentialProblem).textSelection(.enabled)
                if !concern.whyItMatters.isEmpty { LabeledContent("Why it may matter") { Text(concern.whyItMatters).textSelection(.enabled) } }
                if !concern.alternativeInterpretations.isEmpty { LabeledContent("Alternative reading") { Text(concern.alternativeInterpretations).textSelection(.enabled) } }
                if !concern.investigationQuestions.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Questions to investigate").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        ForEach(concern.investigationQuestions, id: \.self) { Label($0, systemImage: "questionmark.bubble") }
                    }
                }
                if !concern.evidenceRelationshipIDs.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Evidence considered").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        ForEach(concern.evidenceRelationshipIDs, id: \.self) { id in
                            if let evidence = model.evidenceRecords.first(where: { $0.id == id }) {
                                Button("\(evidence.relation.rawValue): \(evidence.summary)") { model.openEvidenceInReadingDesk(evidence) }
                                    .buttonStyle(.link)
                            }
                        }
                    }
                }
                Text(concern.uncertainty).font(.caption).foregroundStyle(.secondary)
                Divider()
                Picker("Decision", selection: $disposition) { ForEach(ReviewDisposition.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                TextField("Review notes or reason for dismissal", text: $notes, axis: .vertical).lineLimit(2...5)
                Button("Save Decision") { model.saveBiasConcernReview(concern, disposition: disposition, notes: notes) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct NewBiasAuditSheet: View {
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
            Text("Audit an Argument").font(.title2.weight(.semibold))
            Text(useConfiguredModel
                 ? "The configured model will receive the selected passage snapshots and recorded argument context after a separate consent preview. Its concerns remain suggestions and cannot diagnose your motives or psychology."
                 : "Research Atlas will inspect only the argument and evidence relationships you have recorded locally. It generates cautious investigation prompts and does not infer your motives or diagnose psychological bias.")
                .foregroundStyle(.secondary)
            Picker("Argument", selection: $argumentID) {
                Text("Choose an argument").tag(nil as UUID?)
                ForEach(model.arguments) { Text($0.proposition).tag($0.id as UUID?) }
            }
            Toggle("Generate source-grounded model suggestions", isOn: $useConfiguredModel)
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
                Label("No content is sent until you approve the provider, model, task, passage list, and request size.", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.aiProviderReadyForRequests {
                    Button("Finish AI Setup in Integrations") { dismiss(); model.selectedSection = .settings }
                        .buttonStyle(.link)
                }
            }
            HStack {
                Spacer(); Button("Cancel") { dismiss() }
                Button(useConfiguredModel ? "Prepare Transmission" : "Create Local Review") {
                    if let argumentID, let argument = model.arguments.first(where: { $0.id == argumentID }) {
                        if useConfiguredModel {
                            let selectedSet = retrievalSetID
                            dismiss()
                            DispatchQueue.main.async {
                                model.prepareAIBiasAudit(for: argument, retrievalSetID: selectedSet)
                            }
                        } else {
                            model.createLocalBiasAudit(for: argument)
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent).disabled(
                    argumentID == nil || (useConfiguredModel && (retrievalSetID == nil || !model.aiProviderReadyForRequests))
                )
            }
        }
        .padding(24).frame(width: 680)
        .onAppear {
            argumentID = model.requestedBiasAuditArgumentID ?? model.selectedArgumentID ?? model.arguments.first?.id
            model.requestedBiasAuditArgumentID = nil
            retrievalSetID = model.suggestedRetrievalSetID(matching: expectedLiteratureIDs)
        }
    }
}
