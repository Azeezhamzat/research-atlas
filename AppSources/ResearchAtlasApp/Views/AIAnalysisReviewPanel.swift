import ResearchAtlasCore
import SwiftUI

struct AIAnalysisReviewPanel: View {
    @EnvironmentObject private var model: AppModel
    let analysis: AIAnalysis
    var responseTitle = "Model suggestion"
    @State private var decision: AnalysisReviewDecision = .pending
    @State private var reviewNotes = ""

    private var citations: [AIAnalysisCitation] { model.citations(forAnalysis: analysis.id) }
    private var noteCitations: [AIAnalysisNoteCitation] { model.noteCitations(forAnalysis: analysis.id) }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Model-generated analysis", systemImage: "sparkles")
                        .font(.headline).foregroundStyle(.purple)
                    Spacer()
                    Text(analysis.status.rawValue).font(.caption.weight(.semibold))
                }
                if let error = analysis.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                } else if !analysis.responseText.isEmpty {
                    LabeledContent(responseTitle) {
                        Text(analysis.responseText).textSelection(.enabled)
                    }
                }
                if !citations.isEmpty || !noteCitations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Source snapshots").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        ForEach(citations) { citation in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Button("[\(citation.label)] \(model.literature.first { $0.id == citation.literatureID }?.title ?? "Unavailable source"), p. \(citation.page)") {
                                        model.openAnalysisCitation(citation)
                                    }
                                    .buttonStyle(.link)
                                    Spacer()
                                    Text(citation.citationStatus.rawValue)
                                        .foregroundStyle(citation.citationStatus == .current ? .green : .red)
                                }
                                Text("“\(citation.quotedPassage)”").font(.caption).italic().lineLimit(3).textSelection(.enabled)
                            }
                        }
                        ForEach(noteCitations) { citation in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Button("[\(citation.label)] \(citation.noteTitle)") { model.openNoteCitation(citation) }
                                        .buttonStyle(.link)
                                    Text("Researcher note").foregroundStyle(.indigo)
                                    Spacer()
                                    Text(citation.citationStatus.rawValue)
                                        .foregroundStyle(citation.citationStatus == .current ? .green : .red)
                                }
                                Text("“\(citation.quotedSnippet)”").font(.caption).italic().lineLimit(3).textSelection(.enabled)
                                Text("Researcher context, not published evidence")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow { Text("Provider").foregroundStyle(.secondary); Text(analysis.provider) }
                    GridRow { Text("Model").foregroundStyle(.secondary); Text(analysis.model) }
                    GridRow { Text("Prompt contract").foregroundStyle(.secondary); Text(analysis.promptVersion) }
                    GridRow { Text("Transmitted").foregroundStyle(.secondary); Text("\(analysis.transmittedPassageCount) source snapshots · \(analysis.transmittedCharacterCount) characters") }
                    if let tokens = analysis.inputTokens { GridRow { Text("Input tokens").foregroundStyle(.secondary); Text(tokens.formatted()) } }
                    if let tokens = analysis.outputTokens { GridRow { Text("Output tokens").foregroundStyle(.secondary); Text(tokens.formatted()) } }
                }
                .font(.caption)
                Divider()
                Text("Human review").font(.headline)
                Picker("Decision", selection: $decision) {
                    ForEach(AnalysisReviewDecision.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                TextField("Review notes", text: $reviewNotes, axis: .vertical).lineLimit(2...5)
                Button("Record Review") {
                    model.saveAnalysisReview(analysisID: analysis.id, decision: decision, notes: reviewNotes)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if let review = model.review(forAnalysis: analysis.id) {
                decision = review.decision
                reviewNotes = review.notes
            }
        }
    }
}
