import ResearchAtlasCore
import SwiftUI

struct ResearchAssistantView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var selectedSetID: UUID?
    @State private var expectedLiteratureIDs: Set<UUID> = []

    private var analyses: [AIAnalysis] {
        model.aiAnalyses.filter { $0.kind == .literatureAnswer }
    }

    private var selectedAnalysis: AIAnalysis? {
        analyses.first { $0.id == model.selectedAIAnalysisID }
    }

    var body: some View {
        VStack(spacing: 0) {
            requestComposer
            Divider()
            HSplitView {
                analysisList.frame(minWidth: 300, idealWidth: 345)
                if let selectedAnalysis {
                    ResearchAssistantAnalysisView(analysis: selectedAnalysis)
                        .id(selectedAnalysis.id)
                        .frame(minWidth: 560)
                } else {
                    ContentUnavailableView(
                        "No saved analyses",
                        systemImage: "sparkles",
                        description: Text("Prepare a grounded answer from a saved retrieval set. Nothing is sent without a transmission preview.")
                    )
                }
            }
        }
        .onAppear {
            if !consumeLaunchRequest() {
                selectedSetID = model.selectedRetrievalSetID ?? model.suggestedRetrievalSetID
                if query.isEmpty, let selectedSetID,
                   let set = model.retrievalSets.first(where: { $0.id == selectedSetID }) { query = set.query }
            }
        }
        .onChange(of: model.assistantLaunchRequest?.id) { _, _ in _ = consumeLaunchRequest() }
        .onChange(of: selectedSetID) { _, newValue in
            model.selectedRetrievalSetID = newValue
            if let newValue, let set = model.retrievalSets.first(where: { $0.id == newValue }), query.isEmpty {
                query = set.query
            }
        }
    }

    private var requestComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Grounded Research Assistant").font(.title2.weight(.semibold))
                    Text("Answers are restricted to current paper passages and researcher-note excerpts, which remain separately labelled. Results are model-generated suggestions until you review them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                providerBadge
            }
            HStack(spacing: 8) {
                workflowStep(1, "Choose evidence", "Saved snapshots")
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                workflowStep(2, "Ask", "Focused task")
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                workflowStep(3, "Approve", "Exact preview")
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                workflowStep(4, "Review", "Citations and decision")
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Evidence set").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Picker("Evidence set", selection: $selectedSetID) {
                        Text("Choose a retrieval set").tag(nil as UUID?)
                        ForEach(model.retrievalSets) { set in
                            Text("\(set.name) (\(model.groundedSourceCount(for: set.id)) current sources)")
                                .tag(set.id as UUID?)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 250)
                    GroundingFitSummary(
                        retrievalSetID: selectedSetID,
                        expectedLiteratureIDs: expectedLiteratureIDs
                    )
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Research question").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    TextField("What does the selected evidence support?", text: $query, axis: .vertical)
                        .lineLimit(2...4)
                }
                Button("Prepare Preview", systemImage: "doc.text.magnifyingglass") {
                    model.prepareGroundedAnswer(query: query, retrievalSetID: selectedSetID)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    model.isBusy || !model.aiProviderReadyForRequests || selectedSetID == nil ||
                    query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            if !model.aiProviderReadyForRequests {
                HStack {
                    Label(model.aiProviderStatusText, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                    Button("Finish setup in Integrations") { model.selectedSection = .settings }
                        .buttonStyle(.link)
                }
            }
        }
        .padding(18)
        .background(.bar)
    }

    @ViewBuilder private var providerBadge: some View {
        AIProviderStatusPill()
    }

    private func workflowStep(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 6) {
            Text(String(number))
                .font(.caption2.weight(.bold))
                .frame(width: 20, height: 20)
                .background(Color.purple.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @discardableResult
    private func consumeLaunchRequest() -> Bool {
        guard let request = model.assistantLaunchRequest else { return false }
        selectedSetID = request.retrievalSetID ?? model.suggestedRetrievalSetID
        expectedLiteratureIDs = request.expectedLiteratureIDs
        if !request.query.isEmpty { query = request.query }
        model.assistantLaunchRequest = nil
        return true
    }

    private var analysisList: some View {
        List(analyses, selection: $model.selectedAIAnalysisID) { analysis in
            VStack(alignment: .leading, spacing: 5) {
                Text(analysis.userQuery).font(.headline).lineLimit(2)
                HStack {
                    Label(analysis.status.rawValue, systemImage: statusIcon(analysis.status))
                    Spacer()
                    Text(analysis.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.caption).foregroundStyle(statusColor(analysis.status))
                Text("\(analysis.transmittedPassageCount) source snapshots · \(analysis.model)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 5)
            .tag(analysis.id)
        }
        .overlay {
            if analyses.isEmpty {
                ContentUnavailableView("No analysis history", systemImage: "clock")
            }
        }
    }

    private func statusIcon(_ status: AIAnalysisStatus) -> String {
        switch status {
        case .completed: "checkmark.seal"
        case .insufficientEvidence: "questionmark.diamond"
        case .failed, .refused: "exclamationmark.triangle"
        case .prepared: "clock"
        }
    }

    private func statusColor(_ status: AIAnalysisStatus) -> Color {
        switch status {
        case .completed: .green
        case .insufficientEvidence: .orange
        case .failed, .refused: .red
        case .prepared: .secondary
        }
    }
}

private struct ResearchAssistantAnalysisView: View {
    @EnvironmentObject private var model: AppModel
    let analysis: AIAnalysis
    @State private var decision: AnalysisReviewDecision
    @State private var reviewNotes: String
    @State private var showingClaims = false
    @State private var showingSourceSnapshots = false

    init(analysis: AIAnalysis) {
        self.analysis = analysis
        _decision = State(initialValue: .pending)
        _reviewNotes = State(initialValue: "")
    }

    private var answer: GroundedAnswer? { model.groundedAnswer(for: analysis) }
    private var citations: [AIAnalysisCitation] { model.citations(forAnalysis: analysis.id) }
    private var noteCitations: [AIAnalysisNoteCitation] { model.noteCitations(forAnalysis: analysis.id) }
    private var hasPaperBackedClaim: Bool {
        let paperLabels = Set(citations.filter { $0.citationStatus == .current }.map(\.label))
        return answer?.claims.contains { !$0.citations.allSatisfy { !paperLabels.contains($0) } } == true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Model-generated analysis").font(.caption.weight(.bold)).foregroundStyle(.purple)
                        Text(analysis.userQuery).font(.largeTitle.weight(.semibold)).textSelection(.enabled)
                    }
                    Spacer()
                    Text(analysis.status.rawValue).font(.caption.weight(.semibold)).padding(8).background(.quaternary, in: Capsule())
                }

                if let error = analysis.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                } else if let answer {
                    if answer.insufficientEvidence {
                        GroupBox("Insufficient evidence") {
                            Text(answer.insufficiencyReason).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }
                    } else {
                        Text(answer.answer).font(.title3).textSelection(.enabled)
                        GroupBox("Citation-bearing claims") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("\(answer.claims.count) structured claims")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button(showingClaims ? "Hide Claims" : "Inspect Claims") {
                                        showingClaims.toggle()
                                    }
                                }
                                if showingClaims {
                                    ForEach(Array(answer.claims.enumerated()), id: \.offset) { _, claim in
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(claim.text).textSelection(.enabled)
                                            HStack {
                                                Text(claim.citations.map { "[\($0)]" }.joined(separator: " "))
                                                if claim.interpretation { Text("Interpretation / synthesis") }
                                            }
                                            .font(.caption.weight(.medium)).foregroundStyle(claim.interpretation ? .orange : .secondary)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else if analysis.status == .prepared {
                    Text("This request was recorded before completion. No answer is available.").foregroundStyle(.secondary)
                }

                GroupBox("Source snapshots") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("\(citations.count) paper passages · \(noteCitations.count) researcher-note excerpts")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(showingSourceSnapshots ? "Hide Snapshots" : "Inspect Snapshots") {
                                showingSourceSnapshots.toggle()
                            }
                        }
                        if showingSourceSnapshots {
                            if citations.isEmpty && noteCitations.isEmpty { Text("No source snapshots recorded.").foregroundStyle(.secondary) }
                            ForEach(citations) { citation in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text("[\(citation.label)]").font(.headline.monospaced())
                                        Text(model.literature.first { $0.id == citation.literatureID }?.title ?? "Unavailable source").lineLimit(1)
                                        Spacer()
                                        Text("p. \(citation.page)")
                                        Text(citation.citationStatus.rawValue).foregroundStyle(citation.citationStatus == .current ? .green : .red)
                                    }
                                    .font(.caption)
                                    Text("“\(citation.quotedPassage)”").italic().lineLimit(5).textSelection(.enabled)
                                    Button("Open exact source", systemImage: "doc.text.magnifyingglass") { model.openAnalysisCitation(citation) }
                                        .buttonStyle(.link)
                                }
                            }
                            ForEach(noteCitations) { citation in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text("[\(citation.label)]").font(.headline.monospaced())
                                        Label(citation.noteTitle, systemImage: "note.text").lineLimit(1)
                                        Spacer()
                                        Text("Researcher note").foregroundStyle(.indigo)
                                        Text(citation.citationStatus.rawValue).foregroundStyle(citation.citationStatus == .current ? .green : .red)
                                    }
                                    .font(.caption)
                                    Text("“\(citation.quotedSnippet)”").italic().lineLimit(5).textSelection(.enabled)
                                    Text("Not published evidence · snapshot from \(citation.sourceModifiedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                    Button("Open exact note", systemImage: "arrow.up.forward.app") { model.openNoteCitation(citation) }
                                        .buttonStyle(.link)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Human review") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Decision", selection: $decision) {
                            ForEach(AnalysisReviewDecision.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        TextField("Review notes", text: $reviewNotes, axis: .vertical).lineLimit(2...5)
                        HStack {
                            Button("Record Review") { model.saveAnalysisReview(analysisID: analysis.id, decision: decision, notes: reviewNotes) }
                            if analysis.status == .completed {
                                Button("Save Paper-Backed Claims as Unverified Candidates") { model.saveGroundedAnswerClaims(from: analysis) }
                                    .disabled(!hasPaperBackedClaim)
                                    .help(hasPaperBackedClaim ? "Only claims with a current paper-passage citation are converted." : "Researcher-note-only claims remain in this analysis and are not converted into literature claims.")
                            }
                            Spacer()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    metadataRow("Provider", analysis.provider)
                    metadataRow("Model", analysis.model)
                    metadataRow("Prompt contract", analysis.promptVersion)
                    metadataRow("Transmitted", "\(analysis.transmittedPassageCount) source snapshots · \(analysis.transmittedCharacterCount) characters")
                    if let input = analysis.inputTokens { metadataRow("Input tokens", input.formatted()) }
                    if let output = analysis.outputTokens { metadataRow("Output tokens", output.formatted()) }
                }
                .font(.caption)
            }
            .padding(26)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .onAppear {
            if let review = model.review(forAnalysis: analysis.id) {
                decision = review.decision
                reviewNotes = review.notes
            }
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(label).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text(value).textSelection(.enabled)
        }
    }
}
