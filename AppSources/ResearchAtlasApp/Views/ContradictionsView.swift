import ResearchAtlasCore
import SwiftUI

struct ContradictionsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingNewCase = false

    private var selectedCase: ContradictionCase? { model.contradictionCases.first { $0.id == model.selectedContradictionCaseID } }

    var body: some View {
        HSplitView {
            List(model.contradictionCases, selection: $model.selectedContradictionCaseID) { item in
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.headline).lineLimit(2)
                    Text(item.status.rawValue).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 5).tag(item.id)
            }
            .overlay {
                if model.contradictionCases.isEmpty {
                    ContentUnavailableView("No contradiction reviews", systemImage: "arrow.left.arrow.right", description: Text("Create a comparison case when findings or interpretations appear to conflict."))
                }
            }
            .frame(minWidth: 300, idealWidth: 360)
            if let selectedCase { ContradictionDetailView(contradiction: selectedCase).frame(minWidth: 580) }
            else { ContentUnavailableView("Select a review", systemImage: "arrow.left") }
        }
        .toolbar { Button("New Review", systemImage: "plus") { showingNewCase = true } }
        .sheet(isPresented: $showingNewCase) { ContradictionCaseEditor(contradiction: nil) }
    }
}

private struct ContradictionDetailView: View {
    @EnvironmentObject private var model: AppModel
    let contradiction: ContradictionCase
    @State private var showingEditor = false
    @State private var showingSourceSheet = false
    @State private var showingAIReviewSheet = false
    @State private var showingDelete = false

    private var sources: [ContradictionSource] { model.contradictionSources.filter { $0.caseID == contradiction.id } }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(contradiction.status.rawValue).font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        Text(contradiction.title).font(.largeTitle.weight(.semibold))
                        if !contradiction.summary.isEmpty { Text(contradiction.summary).foregroundStyle(.secondary).textSelection(.enabled) }
                    }
                    Spacer()
                    Button("AI Review", systemImage: "sparkles") { showingAIReviewSheet = true }
                    Button("Edit Review", systemImage: "pencil") { showingEditor = true }
                    Button("Delete", systemImage: "trash", role: .destructive) { showingDelete = true }
                }
                if !contradiction.resolutionNotes.isEmpty {
                    GroupBox("Current assessment") { Text(contradiction.resolutionNotes).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4) }
                }
                Label("Different outcomes are not treated as contradictions until design, population, manipulation, measurement, definitions, and context have been examined.", systemImage: "checkmark.shield")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Text("Evidence comparison matrix").font(.title2.weight(.semibold))
                    Spacer()
                    Button("Add Source", systemImage: "plus") { showingSourceSheet = true }.disabled(model.literature.isEmpty)
                }
                if sources.isEmpty {
                    ContentUnavailableView("No comparison sources", systemImage: "tablecells", description: Text("Add at least two sources and record the apparent findings and contextual differences."))
                        .frame(minHeight: 230)
                } else {
                    Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            matrixHeader("Source", width: 250)
                            matrixHeader("Role / finding", width: 260)
                            matrixHeader("Design / sample", width: 260)
                            matrixHeader("Definitions / variables", width: 280)
                            matrixHeader("Limitations / contextual differences", width: 300)
                        }
                        Divider()
                        ForEach(sources) { source in
                            let paper = model.literature.first { $0.id == source.literatureID }
                            let profile = model.comparisonProfile(for: source.literatureID)
                            GridRow {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(paper?.title ?? "Unavailable source").font(.headline)
                                    Text(source.verification.rawValue).font(.caption).foregroundStyle(.secondary)
                                    if let passageID = source.sourcePassageID,
                                       let passage = model.retrievedPassages.first(where: { $0.sourcePassageID == passageID }) {
                                        Button("Open passage") { model.openRetrievedPassage(passage) }.buttonStyle(.link)
                                    }
                                    Button("Remove", role: .destructive) { model.deleteContradictionSource(source) }.buttonStyle(.link)
                                }.padding(11).frame(width: 250, alignment: .topLeading)
                                matrixText("\(source.role)\n\(source.finding)", width: 260)
                                matrixText([profile.studyDesign, profile.sample].filter { !$0.isEmpty }.joined(separator: "\n"), width: 260)
                                matrixText([profile.operationalDefinitions, profile.independentVariables, profile.dependentVariables].filter { !$0.isEmpty }.joined(separator: "\n"), width: 280)
                                matrixText([profile.limitations, source.contextualDifference].filter { !$0.isEmpty }.joined(separator: "\n"), width: 300)
                            }
                            Divider()
                        }
                    }
                    .background(.background)
                }
                GroupBox("Questions to investigate") {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Do the studies define the outcome in the same way?")
                        Text("Are the populations, task conditions, and intervention quality comparable?")
                        Text("Could the apparent conflict reflect different independent or dependent variables?")
                        Text("Which missing methodological details prevent a defensible comparison?")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                }
                ForEach(model.analyses(targetType: .contradictionCase, targetID: contradiction.id)) { analysis in
                    VStack(alignment: .leading, spacing: 12) {
                        if let output = model.contradictionOutput(for: analysis), !output.insufficientEvidence {
                            HStack {
                                Text("Suggested assessment").font(.headline)
                                Spacer()
                                Text(output.suggestedStatus.rawValue).font(.caption.weight(.semibold)).padding(6).background(.purple.opacity(0.12), in: Capsule())
                            }
                            if !output.possibleExplanations.isEmpty {
                                LabeledContent("Possible explanations") { Text(output.possibleExplanations.joined(separator: "\n• ")).textSelection(.enabled) }
                            }
                            if !output.contextualDifferences.isEmpty {
                                LabeledContent("Contextual differences") { Text(output.contextualDifferences.joined(separator: "\n• ")).textSelection(.enabled) }
                            }
                            if !output.unresolvedQuestions.isEmpty {
                                LabeledContent("Unresolved questions") { Text(output.unresolvedQuestions.joined(separator: "\n• ")).textSelection(.enabled) }
                            }
                        }
                        AIAnalysisReviewPanel(analysis: analysis, responseTitle: "Model assessment")
                    }
                }
            }
            .padding(26)
            .frame(minWidth: 760, maxWidth: 1500, alignment: .leading)
        }
        .sheet(isPresented: $showingEditor) { ContradictionCaseEditor(contradiction: contradiction) }
        .sheet(isPresented: $showingSourceSheet) { ContradictionSourceSheet(caseID: contradiction.id) }
        .sheet(isPresented: $showingAIReviewSheet) { ContradictionAIReviewSheet(contradiction: contradiction) }
        .confirmationDialog("Delete this contradiction review?", isPresented: $showingDelete) {
            Button("Delete Review", role: .destructive) { model.deleteContradictionCase(contradiction) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func matrixHeader(_ text: String, width: CGFloat) -> some View {
        Text(text).font(.headline).padding(11).frame(width: width, alignment: .leading)
    }

    private func matrixText(_ value: String, width: CGFloat) -> some View {
        Text(value.isEmpty ? "Unavailable" : value).foregroundStyle(value.isEmpty ? .secondary : .primary)
            .textSelection(.enabled).padding(11).frame(width: width, alignment: .topLeading)
    }
}

private struct ContradictionAIReviewSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let contradiction: ContradictionCase
    @State private var retrievalSetID: UUID?

    private var expectedLiteratureIDs: Set<UUID> {
        Set(model.contradictionSources
            .filter { $0.caseID == contradiction.id }
            .map(\.literatureID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Prepare Grounded Contradiction Review").font(.title2.weight(.semibold))
            Text("The configured model will investigate whether the apparent conflict may reflect differences in design, population, task, measurement, definitions, intervention, or context. It will not change your case status or resolution notes.")
                .foregroundStyle(.secondary)
            GroupBox("Case") {
                VStack(alignment: .leading, spacing: 5) {
                    Text(contradiction.title).font(.headline)
                    if !contradiction.summary.isEmpty { Text(contradiction.summary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
            Label("A separate consent screen appears before the recorded case context and exact passage snapshots are sent.", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Prepare Transmission") {
                    let selectedSet = retrievalSetID
                    dismiss()
                    DispatchQueue.main.async {
                        model.prepareAIContradictionReview(for: contradiction, retrievalSetID: selectedSet)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(retrievalSetID == nil || !model.aiProviderReadyForRequests)
            }
            if !model.aiProviderReadyForRequests {
                Button("Finish AI Setup in Integrations") { dismiss(); model.selectedSection = .settings }
                    .buttonStyle(.link)
            }
        }
        .padding(24).frame(width: 680)
        .onAppear { retrievalSetID = model.suggestedRetrievalSetID(matching: expectedLiteratureIDs) }
    }
}

private struct ContradictionCaseEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let original: ContradictionCase?
    @State private var draft: ContradictionCase

    init(contradiction: ContradictionCase?) {
        original = contradiction
        _draft = State(initialValue: contradiction ?? ContradictionCase(title: ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(original == nil ? "New Contradiction Review" : "Update Contradiction Review").font(.title2.weight(.semibold))
            TextField("What appears to conflict?", text: $draft.title)
            Picker("Research question", selection: $draft.questionID) {
                Text("Not linked").tag(UUID?.none)
                ForEach(model.questions) { Text($0.question).tag(UUID?.some($0.id)) }
            }
            TextField("Why do these findings or interpretations merit comparison?", text: $draft.summary, axis: .vertical).lineLimit(3...6)
            Picker("Assessment", selection: $draft.status) { ForEach(ContradictionCaseStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            TextField("Current resolution or remaining uncertainty", text: $draft.resolutionNotes, axis: .vertical).lineLimit(3...7)
            HStack {
                Spacer(); Button("Cancel") { dismiss() }
                Button("Save Review") { model.saveContradictionCase(draft); dismiss() }.buttonStyle(.borderedProminent)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 680)
    }
}

private struct ContradictionSourceSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let caseID: UUID
    @State private var literatureID: UUID?
    @State private var passageID = ""
    @State private var role = "Finding"
    @State private var finding = ""
    @State private var contextualDifference = ""
    @State private var verification: VerificationState = .unverified

    private var passages: [RetrievedPassage] {
        guard let literatureID else { return [] }
        var seen = Set<String>()
        return model.retrievedPassages.filter { $0.literatureID == literatureID && seen.insert($0.sourcePassageID).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Comparison Source").font(.title2.weight(.semibold))
            Picker("Paper", selection: $literatureID) {
                Text("Select…").tag(UUID?.none)
                ForEach(model.literature) { Text($0.title).tag(UUID?.some($0.id)) }
            }
            .onChange(of: literatureID) { _, _ in passageID = "" }
            Picker("Saved source passage", selection: $passageID) {
                Text("No exact passage linked").tag("")
                ForEach(passages) { passage in Text("Page \(passage.page): \(passage.passageText.prefix(90))").tag(passage.sourcePassageID) }
            }
            TextField("Role in the comparison", text: $role)
            TextField("Finding or interpretation, preserving qualifications", text: $finding, axis: .vertical).lineLimit(3...6)
            TextField("Design, population, measure, definition, or context difference", text: $contextualDifference, axis: .vertical).lineLimit(3...6)
            Picker("Verification", selection: $verification) { ForEach(VerificationState.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            HStack {
                Spacer(); Button("Cancel") { dismiss() }
                Button("Add Source") {
                    guard let literatureID else { return }
                    model.saveContradictionSource(ContradictionSource(
                        caseID: caseID, literatureID: literatureID, sourcePassageID: passageID.isEmpty ? nil : passageID,
                        role: role, finding: finding, contextualDifference: contextualDifference, verification: verification
                    ))
                    dismiss()
                }
                .buttonStyle(.borderedProminent).disabled(literatureID == nil || finding.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 720)
    }
}
