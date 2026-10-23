import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingNewProject = false
    @State private var showingNewQuestion = false

    private let startSections: [AppSection] = [.home, .learning]
    private let sourceSections: [AppSection] = [.library, .reading, .search]
    private let reasoningSections: [AppSection] = [.questions, .evidence, .arguments, .atlas, .ideas, .contradictions]
    private let analysisSections: [AppSection] = [.assistant, .bias, .argumentRoom, .collectiveLab]
    private let outputSections: [AppSection] = [.writing, .history]

    private var selectedProjectTitle: String {
        model.projects.first { $0.id == model.selectedProjectID }?.title ?? "No active project"
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                projectSwitcher
                Divider()
                List(selection: $model.selectedSection) {
                    navigationGroup("Start", sections: startSections)
                    navigationGroup("Sources", sections: sourceSections)
                    navigationGroup("Research reasoning", sections: reasoningSections)
                    navigationGroup("AI and critical review", sections: analysisSections)
                    navigationGroup("Outputs and record", sections: outputSections)
                    Section("System") {
                        navigationRow(.settings)
                    }
                }
                .listStyle(.sidebar)
                quickActions
                statusBar
            }
            .navigationTitle("Research Atlas")
            .navigationSplitViewColumnWidth(min: 245, ideal: 275, max: 340)
        } detail: {
            Group {
                switch model.selectedSection {
                case .home: HomeView()
                case .learning: LearningCenterView()
                case .library: LibraryView()
                case .reading: ReadingDeskView()
                case .questions: QuestionsView()
                case .evidence: EvidenceExplorerView()
                case .assistant: ResearchAssistantView()
                case .arguments: ArgumentsView()
                case .atlas: KnowledgeAtlasView()
                case .ideas: IdeasView()
                case .contradictions: ContradictionsView()
                case .bias: BiasAuditorView()
                case .history: IntellectualHistoryView()
                case .argumentRoom: ArgumentRoomView()
                case .collectiveLab: CollectiveIntelligenceLabView()
                case .writing: ResearchWritingView()
                case .search: GlobalSearchView()
                case .settings: SettingsView()
                }
            }
            .navigationTitle(model.selectedSection.rawValue)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        model.selectedSection = .search
                    } label: {
                        Label("Search Research Atlas", systemImage: "magnifyingglass")
                    }
                    .keyboardShortcut("k", modifiers: .command)

                    Menu {
                        Button("Add PDF", systemImage: "doc.badge.plus") {
                            model.chooseAndAddPDF()
                        }
                        Divider()
                        Button("New Research Project", systemImage: "folder.badge.plus") {
                            showingNewProject = true
                        }
                        Button("New Research Question", systemImage: "plus.bubble") {
                            showingNewQuestion = true
                        }
                        .disabled(model.selectedProjectID == nil)
                        Divider()
                        Button("New Idea", systemImage: "lightbulb.max") {
                            model.selectedSection = .ideas
                        }
                        Button("New Concept or Relationship", systemImage: "circle.hexagongrid") {
                            model.selectedSection = .atlas
                        }
                        Button("New Writing Workspace", systemImage: "square.and.pencil") {
                            model.selectedSection = .writing
                        }
                    } label: {
                        Label("Create", systemImage: "plus")
                    }
                }
            }
        }
        .alert("Research Atlas", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK") { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .sheet(isPresented: $showingNewProject) {
            QuickProjectSheet()
        }
        .sheet(isPresented: $showingNewQuestion) {
            if let projectID = model.selectedProjectID {
                QuickQuestionSheet(projectID: projectID)
            }
        }
        .sheet(item: Binding(
            get: { model.pendingAITransmission },
            set: { if $0 == nil && model.pendingAITransmission != nil { model.cancelAITransmission() } }
        )) { preview in
            AITransmissionPreviewSheet(preview: preview)
                .environmentObject(model)
                .interactiveDismissDisabled(model.isBusy)
        }
    }

    @ViewBuilder
    private func navigationGroup(_ title: String, sections: [AppSection]) -> some View {
        Section(title) {
            ForEach(sections) { section in navigationRow(section) }
        }
    }

    private func navigationRow(_ section: AppSection) -> some View {
        Label(section.rawValue, systemImage: section.icon)
            .lineLimit(1)
            .help(section.rawValue)
            .tag(section)
    }

    private var projectSwitcher: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("ACTIVE PROJECT")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            if model.projects.isEmpty {
                Button {
                    showingNewProject = true
                } label: {
                    Label("Create your first project", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            } else {
                Menu {
                    ForEach(model.projects) { project in
                        Button {
                            activate(project.id)
                        } label: {
                            if project.id == model.selectedProjectID {
                                Label(project.title, systemImage: "checkmark")
                            } else {
                                Text(project.title)
                            }
                        }
                    }
                    Divider()
                    Button("New Project…", systemImage: "folder.badge.plus") {
                        showingNewProject = true
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.indigo)
                        Text(selectedProjectTitle)
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .help("Switch the active research project")

                if let projectID = model.selectedProjectID {
                    let count = model.questions.filter { $0.projectID == projectID }.count
                    Text("\(count) research question\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            Button {
                model.chooseAndAddPDF()
            } label: {
                Label("Add PDF", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            Button {
                showingNewQuestion = true
            } label: {
                Image(systemName: "plus.bubble")
            }
            .help("New research question")
            .disabled(model.selectedProjectID == nil)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.isBusy { ProgressView().controlSize(.small) }
            Circle()
                .fill(model.isBusy ? Color.orange : Color.green)
                .frame(width: 7, height: 7)
            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.bar)
    }

    private func activate(_ projectID: UUID) {
        model.selectedProjectID = projectID
        model.selectedQuestionID = model.questions
            .filter { $0.projectID == projectID }
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .first?.id
        model.selectedSection = .home
    }
}

private struct QuickProjectSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var summary = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Research Project").font(.title2.weight(.semibold))
            Text("Create the durable container for related questions, arguments, ideas, and writing.")
                .foregroundStyle(.secondary)
            TextField("Project title", text: $title)
            TextField("Purpose or scope", text: $summary, axis: .vertical).lineLimit(3...7)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create Project") {
                    model.saveProject(title: title.trimmingCharacters(in: .whitespacesAndNewlines), summary: summary)
                    model.selectedSection = .home
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

private struct QuickQuestionSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID
    @State private var question = ""
    @State private var context = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Research Question").font(.title2.weight(.semibold))
            if let project = model.projects.first(where: { $0.id == projectID }) {
                Label(project.title, systemImage: "folder.fill")
                    .foregroundStyle(.secondary)
            }
            TextField("Research question", text: $question, axis: .vertical).lineLimit(2...5)
            TextField("Context or immediate objective", text: $context, axis: .vertical).lineLimit(3...7)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add Question") {
                    model.saveQuestion(projectID: projectID, text: question.trimmingCharacters(in: .whitespacesAndNewlines), notes: context)
                    model.selectedSection = .questions
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 600)
    }
}
