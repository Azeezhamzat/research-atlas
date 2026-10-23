import ResearchAtlasCore
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    private var activeProject: ResearchProject? {
        model.projects.first { $0.id == model.selectedProjectID }
    }

    private var projectQuestions: [ResearchQuestion] {
        guard let projectID = activeProject?.id else { return model.questions }
        return model.questions.filter { $0.projectID == projectID }
    }

    private var projectQuestionIDs: Set<UUID> { Set(projectQuestions.map(\.id)) }

    private var projectArguments: [ResearchArgument] {
        guard activeProject != nil else { return model.arguments }
        return model.arguments.filter { argument in
            argument.questionID.map { projectQuestionIDs.contains($0) } ?? false
        }
    }

    private var projectIdeas: [ResearchIdea] {
        guard let projectID = activeProject?.id else { return model.ideas }
        return model.ideas.filter { idea in
            idea.projectID == projectID || idea.questionID.map { projectQuestionIDs.contains($0) } == true
        }
    }

    private var projectDocuments: [WritingDocument] {
        guard let projectID = activeProject?.id else { return model.writingDocuments }
        return model.writingDocuments.filter { document in
            document.projectID == projectID || document.questionID.map { projectQuestionIDs.contains($0) } == true
        }
    }

    private var linkedLiteratureIDs: Set<UUID> {
        let links = model.questionLiteratureAssociations.filter { projectQuestionIDs.contains($0.questionID) }
        return Set(links.map(\.literatureID))
    }

    private var linkedLiterature: [LiteratureItem] {
        if activeProject == nil { return model.literature }
        return model.literature.filter { linkedLiteratureIDs.contains($0.id) }
    }

    private var activeQuestions: [ResearchQuestion] {
        projectQuestions
            .filter { $0.status != "Resolved" && $0.status != "Superseded" }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private var currentQuestion: ResearchQuestion? {
        activeQuestions.first { $0.id == model.selectedQuestionID } ?? activeQuestions.first
    }

    private var currentArgument: ResearchArgument? {
        projectArguments.first { $0.id == model.selectedArgumentID }
            ?? projectArguments.sorted { $0.modifiedAt > $1.modifiedAt }.first
    }

    private var currentIdea: ResearchIdea? {
        projectIdeas.first { $0.id == model.selectedIdeaID }
            ?? projectIdeas.sorted { $0.modifiedAt > $1.modifiedAt }.first
    }

    private var currentDocument: WritingDocument? {
        projectDocuments.first { $0.id == model.selectedWritingDocumentID }
            ?? projectDocuments.sorted { $0.modifiedAt > $1.modifiedAt }.first
    }

    private var currentLiterature: LiteratureItem? {
        linkedLiterature.first { $0.id == model.selectedLiteratureID }
            ?? linkedLiterature.sorted { $0.modifiedAt > $1.modifiedAt }.first
            ?? model.selectedLiterature
    }

    private var unverifiedCount: Int {
        model.evidenceRecords.filter { $0.verification == .unverified }.count
            + model.claims.filter { $0.verification == .unverified }.count
    }

    private var staleCitationCount: Int {
        model.retrievedPassages.filter { $0.citationStatus != .current }.count
            + model.retrievedNoteSnippets.filter { $0.citationStatus != .current }.count
    }

    private var sourceIssueCount: Int {
        model.literature.filter {
            let status = model.pdfFileAvailability(for: $0)
            return status == .missing || status == .changed
        }.count
    }

    private var failedIndexingCount: Int {
        model.indexingJobs.filter { $0.status == .failed }.count
    }

    private var needsAttention: Bool {
        unverifiedCount + staleCitationCount + sourceIssueCount + failedIndexingCount > 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                commandHeader

                if model.literature.isEmpty || model.projects.isEmpty {
                    gettingStarted
                }

                projectMetrics
                researchFlow
                aiWorkspace
                resumeWorkspace
                attentionQueue
                recentActivity
                provenanceFooter
            }
            .padding(30)
            .frame(maxWidth: 1280, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var commandHeader: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 7) {
                Text("RESEARCH COMMAND CENTRE")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.indigo)
                Text(activeProject?.title ?? "Your research workspace")
                    .font(.largeTitle.weight(.semibold))
                Text(headerSummary)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 780, alignment: .leading)
            }
            Spacer(minLength: 20)
            VStack(alignment: .trailing, spacing: 9) {
                Button("Search everything", systemImage: "magnifyingglass") {
                    model.selectedSection = .search
                }
                .buttonStyle(.borderedProminent)
                Button("Open project questions", systemImage: "questionmark.bubble") {
                    model.selectedSection = .questions
                }
                .buttonStyle(.bordered)
                .disabled(activeProject == nil)
            }
        }
    }

    private var headerSummary: String {
        if let activeProject, !activeProject.summary.isEmpty { return activeProject.summary }
        if activeProject != nil {
            return "Resume a question, inspect its evidence, or continue the argument and writing work attached to this project."
        }
        return "Choose or create an active project in the sidebar. Research Atlas will organise your next actions around it without changing your source files."
    }

    private var gettingStarted: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Build the research foundation").font(.title2.weight(.semibold))
                        Text("Research Atlas becomes useful when it has both source material and a question that gives the material purpose.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open the guided workflow", systemImage: "graduationcap") {
                        model.selectedSection = .learning
                    }
                }
                HStack(spacing: 12) {
                    SetupStep(number: 1, title: "Connect sources", complete: !model.literature.isEmpty) {
                        model.selectedSection = .settings
                    }
                    SetupStep(number: 2, title: "Create a project", complete: !model.projects.isEmpty) {
                        model.selectedSection = .questions
                    }
                    SetupStep(number: 3, title: "Frame a question", complete: !model.questions.isEmpty) {
                        model.selectedSection = .questions
                    }
                }
            }
            .padding(.vertical, 5)
        }
    }

    private var projectMetrics: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionHeading(
                title: activeProject == nil ? "Workspace snapshot" : "Project snapshot",
                subtitle: activeProject == nil ? "Counts across the entire local workspace." : "Counts connected to the active project and its questions."
            )
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 13)], spacing: 13) {
                MetricCard(title: "Linked sources", value: linkedLiterature.count, detail: activeProject == nil ? "in the library" : "through project questions", icon: "books.vertical", tint: .indigo) {
                    model.selectedSection = .library
                }
                MetricCard(title: "Active questions", value: activeQuestions.count, detail: "awaiting resolution", icon: "questionmark.bubble", tint: .orange) {
                    model.selectedSection = .questions
                }
                MetricCard(title: "Arguments", value: projectArguments.count, detail: "recorded propositions", icon: "point.3.connected.trianglepath.dotted", tint: .purple) {
                    model.selectedSection = .arguments
                }
                MetricCard(title: "Ideas", value: projectIdeas.count, detail: "observations and hypotheses", icon: "lightbulb.max", tint: .teal) {
                    model.selectedSection = .ideas
                }
                MetricCard(title: "Writing", value: projectDocuments.count, detail: "draft workspaces", icon: "square.and.pencil", tint: .blue) {
                    model.selectedSection = .writing
                }
            }
        }
    }

    private var researchFlow: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionHeading(title: "Research flow", subtitle: "Move from source material to a traceable written claim.")
            HStack(spacing: 0) {
                FlowStage(title: "Sources", count: linkedLiterature.count, icon: "books.vertical", tint: .indigo) { model.selectedSection = .library }
                FlowConnector()
                FlowStage(title: "Questions", count: projectQuestions.count, icon: "questionmark.bubble", tint: .orange) { model.selectedSection = .questions }
                FlowConnector()
                FlowStage(title: "Evidence", count: model.evidenceRecords.count + model.claims.count, icon: "quote.bubble", tint: .green) { model.selectedSection = .evidence }
                FlowConnector()
                FlowStage(title: "Arguments", count: projectArguments.count, icon: "point.3.connected.trianglepath.dotted", tint: .purple) { model.selectedSection = .arguments }
                FlowConnector()
                FlowStage(title: "Writing", count: projectDocuments.count, icon: "square.and.pencil", tint: .blue) { model.selectedSection = .writing }
            }
        }
    }

    private var aiWorkspace: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionHeading(
                title: "Grounded AI tools",
                subtitle: "AI appears inside the research workflow only after you choose an inspectable evidence set."
            )
            GroundedAIContextCard(
                title: "Ask, challenge, and compare without losing provenance",
                detail: "Use the Assistant for evidence-bounded questions, the Bias Auditor or Argument Room for a recorded proposition, and Contradiction Detective for context-sensitive disagreement.",
                suggestedQuery: currentQuestion?.question ?? "What does the selected evidence support, qualify, contradict, or leave unresolved for this project?",
                argument: currentArgument,
                expectedLiteratureIDs: linkedLiteratureIDs
            )
        }
    }

    private var resumeWorkspace: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionHeading(title: "Continue your work", subtitle: "Open the exact record you were using, not merely its module.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 285), spacing: 13)], spacing: 13) {
                if let question = currentQuestion {
                    ResumeCard(kicker: "QUESTION", title: question.question, detail: question.status, icon: "questionmark.bubble.fill", tint: .orange) {
                        model.selectedProjectID = question.projectID
                        model.selectedQuestionID = question.id
                        model.selectedSection = .questions
                    }
                }
                if let paper = currentLiterature {
                    ResumeCard(kicker: "SOURCE", title: paper.title, detail: paper.pdfPath == nil ? "Inspect metadata" : "Resume reading", icon: "book.pages.fill", tint: .indigo) {
                        model.selectedLiteratureID = paper.id
                        model.selectedSection = paper.pdfPath == nil ? .library : .reading
                    }
                }
                if let argument = currentArgument {
                    ResumeCard(kicker: "ARGUMENT", title: argument.proposition, detail: argument.status, icon: "point.3.connected.trianglepath.dotted", tint: .purple) {
                        model.selectedArgumentID = argument.id
                        model.selectedSection = .arguments
                    }
                }
                if let idea = currentIdea {
                    ResumeCard(kicker: "IDEA", title: idea.title, detail: idea.status.rawValue, icon: "lightbulb.fill", tint: .teal) {
                        model.selectedIdeaID = idea.id
                        model.selectedSection = .ideas
                    }
                }
                if let document = currentDocument {
                    ResumeCard(kicker: "WRITING", title: document.title, detail: "\(document.purpose.rawValue) · \(document.status)", icon: "square.and.pencil", tint: .blue) {
                        model.selectedWritingDocumentID = document.id
                        model.selectedSection = .writing
                    }
                }
                if currentQuestion == nil && currentLiterature == nil && currentArgument == nil && currentIdea == nil && currentDocument == nil {
                    ResumeCard(kicker: "START", title: "Create the first research question", detail: "Give the library a research purpose", icon: "plus.bubble", tint: .orange) {
                        model.selectedSection = .questions
                    }
                }
            }
        }
    }

    private var attentionQueue: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionHeading(title: "Needs attention", subtitle: "Integrity and review work that should not disappear inside a database.")
            GroupBox {
                VStack(spacing: 0) {
                    if !needsAttention {
                        Label("No source, indexing, verification, or citation-freshness problems are currently recorded.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        if unverifiedCount > 0 {
                            AttentionRow(count: unverifiedCount, title: "Unverified analytical records", detail: "Evidence relationships and structured claims awaiting human review.", tint: .orange) {
                                model.evidenceExplorerMode = 2
                                model.selectedSection = .evidence
                            }
                        }
                        if staleCitationCount > 0 {
                            AttentionRow(count: staleCitationCount, title: "Stale retrieval citations", detail: "A source snapshot no longer matches the indexed paper or researcher note.", tint: .red) {
                                model.evidenceExplorerMode = 0
                                model.selectedSection = .evidence
                            }
                        }
                        if sourceIssueCount > 0 {
                            AttentionRow(count: sourceIssueCount, title: "PDF identity problems", detail: "Files are missing, unreadable, or changed since verification.", tint: .red) {
                                model.selectedSection = .library
                            }
                        }
                        if failedIndexingCount > 0 {
                            AttentionRow(count: failedIndexingCount, title: "Failed indexing jobs", detail: "Inspect the recorded failure before relying on search coverage.", tint: .red) {
                                model.selectedSection = .settings
                            }
                        }
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionHeading(title: "Recent recorded activity", subtitle: "Only changes observed by Research Atlas are shown.")
            GroupBox {
                VStack(spacing: 0) {
                    if model.historyEvents.isEmpty {
                        Text("No application-observed changes have been recorded yet.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(Array(model.historyEvents.prefix(6).enumerated()), id: \.element.id) { index, event in
                            if index > 0 { Divider() }
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Circle().fill(Color.indigo.opacity(0.75)).frame(width: 7, height: 7)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.title).font(.headline).lineLimit(2)
                                    Text(event.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Text(event.recordedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 9)
                        }
                        Button("Open complete intellectual history", systemImage: "clock.arrow.circlepath") {
                            model.selectedSection = .history
                        }
                        .buttonStyle(.link)
                        .padding(.top, 8)
                    }
                }
            }
        }
    }

    private var provenanceFooter: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("Evidence remains inspectable").font(.headline)
                Text("Research Atlas keeps paper passages, researcher notes, interpretations, and model output as distinct source classes. An empty result is never replaced with invented evidence.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SectionHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: Int
    let detail: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(tint)
                        .frame(width: 34, height: 34)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
                }
                Text(value.formatted()).font(.title.weight(.semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.45)))
        }
        .buttonStyle(.plain)
    }
}

private struct ResumeCard: View {
    let kicker: String
    let title: String
    let detail: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 5) {
                    Text(kicker).font(.caption2.weight(.bold)).foregroundStyle(tint)
                    Text(title).font(.headline).lineLimit(3)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.45)))
        }
        .buttonStyle(.plain)
    }
}

private struct SetupStep: View {
    let number: Int
    let title: String
    let complete: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: complete ? "checkmark.circle.fill" : "\(number).circle.fill")
                    .foregroundStyle(complete ? Color.green : Color.indigo)
                Text(title).font(.headline)
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }
}

private struct FlowStage: View {
    let title: String
    let count: Int
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.title3).foregroundStyle(tint)
                Text(title).font(.caption.weight(.semibold))
                Text(count.formatted()).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

private struct FlowConnector: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(width: 24)
    }
}

private struct AttentionRow: View {
    let count: Int
    let title: String
    let detail: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Text(count.formatted())
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(minWidth: 32, minHeight: 30)
                    .background(tint, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
