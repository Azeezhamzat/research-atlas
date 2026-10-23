import ResearchAtlasCore
import SwiftUI

struct QuestionsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingProjectSheet = false
    @State private var showingQuestionSheet = false

    private var selectedProject: ResearchProject? {
        model.projects.first { $0.id == model.selectedProjectID }
    }

    private var visibleQuestions: [ResearchQuestion] {
        guard let selectedProjectID = model.selectedProjectID else { return [] }
        return model.questions.filter { $0.projectID == selectedProjectID }
    }

    var body: some View {
        HSplitView {
            List(model.projects, selection: $model.selectedProjectID) { project in
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.title).font(.headline)
                    Text(project.summary.isEmpty ? "No project summary" : project.summary)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                .padding(.vertical, 4)
                .tag(project.id)
            }
            .overlay {
                if model.projects.isEmpty {
                    ContentUnavailableView("No research projects", systemImage: "folder.badge.plus", description: Text("Create a project to organise research questions."))
                }
            }
            .frame(minWidth: 280, idealWidth: 330)

            if let project = selectedProject {
                HSplitView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(project.title).font(.title2.weight(.semibold))
                            Text(project.summary.isEmpty ? "No project summary" : project.summary).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(14)
                        Divider()
                        List(visibleQuestions, selection: $model.selectedQuestionID) { question in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(question.question).font(.headline)
                                Spacer()
                                Text(question.status)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(.quaternary, in: Capsule())
                            }
                            if !question.notes.isEmpty { Text(question.notes).foregroundStyle(.secondary).lineLimit(3) }
                        }
                        .padding(.vertical, 7)
                        .tag(question.id)
                    }
                    .overlay {
                        if visibleQuestions.isEmpty {
                            ContentUnavailableView("No research questions", systemImage: "questionmark.bubble", description: Text("Add a question to this project."))
                        }
                    }
                    }
                    .frame(minWidth: 300, idealWidth: 350)
                    if let question = visibleQuestions.first(where: { $0.id == model.selectedQuestionID }) {
                        QuestionWorkspaceView(question: question).frame(minWidth: 520)
                    } else {
                        ContentUnavailableView("Select a research question", systemImage: "arrow.left")
                    }
                }
            } else {
                ContentUnavailableView("Select a project", systemImage: "folder", description: Text("Choose a project from the list or create one."))
            }
        }
        .onAppear {
            if model.selectedProjectID == nil { model.selectedProjectID = model.projects.first?.id }
            if model.selectedQuestionID == nil { model.selectedQuestionID = visibleQuestions.first?.id }
        }
        .onChange(of: model.projects) { _, projects in
            if model.selectedProjectID == nil { model.selectedProjectID = projects.first?.id }
        }
        .onChange(of: model.selectedProjectID) { _, _ in
            if model.selectedQuestionID == nil || !visibleQuestions.contains(where: { $0.id == model.selectedQuestionID }) {
                model.selectedQuestionID = visibleQuestions.first?.id
            }
        }
        .onChange(of: visibleQuestions) { _, questions in
            if model.selectedQuestionID == nil || !questions.contains(where: { $0.id == model.selectedQuestionID }) { model.selectedQuestionID = questions.first?.id }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { showingProjectSheet = true } label: { Label("New Project", systemImage: "folder.badge.plus") }
                Button { showingQuestionSheet = true } label: { Label("New Question", systemImage: "plus.bubble") }
                    .disabled(model.selectedProjectID == nil)
            }
        }
        .sheet(isPresented: $showingProjectSheet) {
            NewProjectSheet { title, summary in
                model.saveProject(title: title, summary: summary)
                model.selectedProjectID = model.projects.first?.id
            }
        }
        .sheet(isPresented: $showingQuestionSheet) {
            if let projectID = model.selectedProjectID {
                NewQuestionSheet { text, notes in model.saveQuestion(projectID: projectID, text: text, notes: notes) }
            }
        }
    }
}

private struct QuestionWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    let question: ResearchQuestion
    @State private var showingEditor = false

    private var literatureLinks: [QuestionLiteratureAssociation] { model.questionLiteratureAssociations.filter { $0.questionID == question.id } }
    private var conceptLinks: [QuestionConceptAssociation] { model.questionConceptAssociations.filter { $0.questionID == question.id } }
    private var linkedLiteratureIDs: Set<UUID> { Set(literatureLinks.map(\.literatureID)) }
    private var linkedConceptIDs: Set<UUID> { Set(conceptLinks.map(\.conceptID)) }
    private var linkedLiterature: [LiteratureItem] { model.literature.filter { linkedLiteratureIDs.contains($0.id) } }
    private var coverageReport: LiteratureCoverageReport {
        LiteratureCoverageAnalyzer.analyze(literature: linkedLiterature, comparisonProfiles: model.comparisonProfiles)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(question.status).font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        Text(question.question).font(.largeTitle.weight(.semibold)).textSelection(.enabled)
                        if let parentID = question.parentQuestionID,
                           let parent = model.questions.first(where: { $0.id == parentID }) {
                            Label("Subquestion of \(parent.question)", systemImage: "arrow.turn.down.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Edit", systemImage: "pencil") { showingEditor = true }
                }
                GroundedAIContextCard(
                    title: "Investigate this question with grounded AI",
                    detail: "The linked-paper list is not sent automatically. Choose a saved retrieval set whose exact passages actually address this question, then review the transmission preview.",
                    suggestedQuery: question.question,
                    expectedLiteratureIDs: linkedLiteratureIDs
                )
                questionField("Context and notes", question.notes)
                questionField("Research objectives", question.objectives)
                questionField("Theoretical interests", question.theoreticalInterests)
                questionField("Conceptual definitions", question.conceptualDefinitions)
                questionField("Unresolved disagreements", question.unresolvedDisagreements)
                questionField("Potential hypotheses", question.potentialHypotheses)
                questionField("Methodological considerations", question.methodologicalConsiderations)
                Divider()
                HStack {
                    Text("Associated literature").font(.title2.weight(.semibold))
                    Spacer()
                    Menu("Link Literature", systemImage: "books.vertical") {
                        ForEach(model.literature.filter { !linkedLiteratureIDs.contains($0.id) }) { paper in
                            Button(paper.title) { model.linkLiterature(paper.id, to: question.id) }
                        }
                    }
                    .disabled(model.literature.allSatisfy { linkedLiteratureIDs.contains($0.id) })
                }
                if literatureLinks.isEmpty { Text("No literature is associated yet.").foregroundStyle(.secondary) }
                ForEach(literatureLinks, id: \.literatureID) { link in
                    HStack {
                        if let paper = model.literature.first(where: { $0.id == link.literatureID }) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(paper.title)
                                Text(paper.year.map(String.init) ?? "Year unrecorded")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Unavailable source")
                        }
                        Spacer()
                        Button("Remove", systemImage: "xmark.circle") { model.unlinkLiterature(link) }.labelStyle(.iconOnly).buttonStyle(.plain)
                    }
                }
                LiteratureCoverageAuditView(report: coverageReport) {
                    model.comparisonLiteratureIDs = linkedLiteratureIDs
                    model.evidenceExplorerMode = 1
                    model.selectedSection = .evidence
                }
                HStack {
                    Text("Associated concepts").font(.title2.weight(.semibold))
                    Spacer()
                    Menu("Link Concept", systemImage: "circle.hexagongrid") {
                        ForEach(model.concepts.filter { !linkedConceptIDs.contains($0.id) }) { concept in
                            Button(concept.name) { model.linkConcept(concept.id, to: question.id) }
                        }
                    }
                    .disabled(model.concepts.allSatisfy { linkedConceptIDs.contains($0.id) })
                }
                if conceptLinks.isEmpty { Text("No concepts are associated yet.").foregroundStyle(.secondary) }
                ForEach(conceptLinks, id: \.conceptID) { link in
                    HStack {
                        Text(model.concepts.first { $0.id == link.conceptID }?.name ?? "Unavailable concept")
                        Spacer()
                        Button("Remove", systemImage: "xmark.circle") { model.unlinkConcept(link) }.labelStyle(.iconOnly).buttonStyle(.plain)
                    }
                }
                Divider()
                Text("Linked arguments").font(.title2.weight(.semibold))
                let arguments = model.arguments.filter { $0.questionID == question.id }
                if arguments.isEmpty { Text("No arguments are linked to this question.").foregroundStyle(.secondary) }
                ForEach(arguments) { argument in
                    Button(argument.proposition) { model.selectedArgumentID = argument.id; model.selectedSection = .arguments }
                        .buttonStyle(.link)
                }
                Divider()
                Text("Recorded revisions").font(.title2.weight(.semibold))
                ForEach(model.questionVersions.filter { $0.questionID == question.id }.sorted { $0.createdAt > $1.createdAt }) { version in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(version.changeNote).font(.headline); Spacer(); Text(version.createdAt.formatted()).font(.caption).foregroundStyle(.secondary) }
                        Text(version.question).textSelection(.enabled)
                    }
                    .padding(11).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
                }
            }
            .padding(26)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .sheet(isPresented: $showingEditor) { QuestionEditorSheet(question: question) }
    }

    @ViewBuilder private func questionField(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(value).textSelection(.enabled)
            }
        }
    }
}

private struct LiteratureCoverageAuditView: View {
    let report: LiteratureCoverageReport
    let openComparisonMatrix: () -> Void
    @State private var isExpanded = true

    private var yearRange: String {
        guard let earliest = report.earliestYear, let latest = report.latestYear else { return "Not recorded" }
        return earliest == latest ? String(earliest) : "\(earliest)–\(latest)"
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label(report.scopeStatement, systemImage: "scope")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        metric("Linked papers", value: "\(report.linkedCount)", detail: "question set", icon: "books.vertical")
                        metric("Available", value: "\(report.availableCount)/\(report.linkedCount)", detail: "source records", icon: "checkmark.circle")
                    }
                    GridRow {
                        metric("Year range", value: yearRange, detail: "\(report.knownYearCount)/\(report.linkedCount) recorded", icon: "calendar")
                        metric("Profiles", value: "\(report.profiledCount)/\(report.linkedCount)", detail: "\(report.fullyProfiledCount) complete", icon: "tablecells")
                    }
                }

                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 15) {
                        if !report.attentionNotes.isEmpty {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("Needs attention").font(.subheadline.weight(.semibold))
                                ForEach(Array(report.attentionNotes.enumerated()), id: \.offset) { _, note in
                                    Label(note, systemImage: "exclamationmark.circle")
                                        .font(.caption).foregroundStyle(.orange)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text("Comparison-field coverage").font(.subheadline.weight(.semibold))
                                Spacer()
                                Button("Open Comparison Matrix", action: openComparisonMatrix).buttonStyle(.link)
                            }
                            ForEach(report.fields) { field in
                                HStack(spacing: 9) {
                                    Text(field.field.rawValue).font(.caption).frame(width: 145, alignment: .leading)
                                    ProgressView(value: field.fraction).frame(maxWidth: .infinity)
                                    Text("\(field.recordedCount)/\(field.linkedCount)")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                        .frame(width: 38, alignment: .trailing)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(field.field.rawValue), \(field.recordedCount) of \(field.linkedCount) linked papers recorded")
                            }
                        }

                        distribution("Publication years", values: report.yearDistribution, emptyMessage: "No publication years recorded")
                        distribution("Study designs", values: report.designDistribution, emptyMessage: "No study designs recorded in comparison profiles")
                        distribution("Theoretical frameworks", values: report.frameworkDistribution, emptyMessage: "No frameworks recorded in comparison profiles")
                        distribution("Topics from paper tags", values: report.topicDistribution, emptyMessage: "No topic tags recorded for the linked papers")

                        if !report.papers.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Paper profile readiness").font(.subheadline.weight(.semibold))
                                ForEach(report.papers) { paper in
                                    HStack(spacing: 9) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(paper.title).font(.caption).lineLimit(2)
                                            Text(paper.year.map(String.init) ?? "Year unrecorded")
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 12)
                                        ProgressView(value: paper.completionFraction).frame(width: 85)
                                        Text("\(paper.recordedComparisonFieldCount)/\(paper.comparisonFieldCount)")
                                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel("\(paper.title), \(paper.recordedComparisonFieldCount) of \(paper.comparisonFieldCount) comparison fields recorded")
                                }
                            }
                        }
                    }
                    .padding(.top, 12)
                } label: {
                    Text("Coverage audit for this question").font(.headline)
                }
            }
            .padding(4)
        }
    }

    private func metric(_ title: String, value: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func distribution(_ title: String, values: [LiteratureCoverageCategory], emptyMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.weight(.semibold))
            if values.isEmpty {
                Text(emptyMessage).font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 115), alignment: .leading)], alignment: .leading, spacing: 7) {
                    ForEach(values) { value in
                        Text("\(value.label) · \(value.count)")
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
    }
}

private struct QuestionEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let original: ResearchQuestion
    @State private var draft: ResearchQuestion
    @State private var changeNote = ""

    init(question: ResearchQuestion) {
        original = question
        _draft = State(initialValue: question)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Revise Research Question").font(.title2.weight(.semibold))
            ScrollView {
                VStack(spacing: 11) {
                    Picker("Parent question", selection: $draft.parentQuestionID) {
                        Text("Main question").tag(UUID?.none)
                        ForEach(model.questions.filter { $0.projectID == draft.projectID && $0.id != draft.id }) { question in
                            Text(question.question).tag(UUID?.some(question.id))
                        }
                    }
                    TextField("Research question", text: $draft.question, axis: .vertical).lineLimit(2...5)
                    Picker("Status", selection: $draft.status) { ForEach(["Active", "Exploratory", "Refining", "Resolved", "Superseded"], id: \.self) { Text($0).tag($0) } }
                    field("Context and notes", text: $draft.notes)
                    field("Research objectives", text: $draft.objectives)
                    field("Theoretical interests", text: $draft.theoreticalInterests)
                    field("Conceptual definitions", text: $draft.conceptualDefinitions)
                    field("Unresolved disagreements", text: $draft.unresolvedDisagreements)
                    field("Potential hypotheses", text: $draft.potentialHypotheses)
                    field("Methodological considerations", text: $draft.methodologicalConsiderations)
                    field("Why are you making this revision?", text: $changeNote)
                }
            }
            HStack {
                Spacer(); Button("Cancel") { dismiss() }
                Button("Save Revision") { model.updateQuestion(draft, changeNote: changeNote); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || changeNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 720, height: 760)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text, axis: .vertical).lineLimit(2...5).frame(maxWidth: .infinity)
    }
}

private struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var summary = ""
    let save: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Research Project").font(.title2.weight(.semibold))
            TextField("Project title", text: $title)
            TextField("Purpose or scope", text: $summary, axis: .vertical).lineLimit(3...6)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Create") { save(title, summary); dismiss() }.buttonStyle(.borderedProminent).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty) }
        }
        .padding(24).frame(width: 520)
    }
}

private struct NewQuestionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var notes = ""
    let save: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Research Question").font(.title2.weight(.semibold))
            TextField("Research question", text: $text, axis: .vertical).lineLimit(2...5)
            TextField("Context or objectives", text: $notes, axis: .vertical).lineLimit(3...7)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Add Question") { save(text, notes); dismiss() }.buttonStyle(.borderedProminent).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty) }
        }
        .padding(24).frame(width: 560)
    }
}
