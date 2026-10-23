import ResearchAtlasCore
import SwiftUI

struct IdeasView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingNewIdea = false

    private var selectedIdea: ResearchIdea? { model.ideas.first { $0.id == model.selectedIdeaID } }

    var body: some View {
        HSplitView {
            List(model.ideas, selection: $model.selectedIdeaID) { idea in
                VStack(alignment: .leading, spacing: 5) {
                    Text(idea.title).font(.headline).lineLimit(2)
                    Text(idea.status.rawValue).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 5)
                .tag(idea.id)
            }
            .overlay {
                if model.ideas.isEmpty {
                    ContentUnavailableView("No research ideas", systemImage: "lightbulb.max", description: Text("Capture an observation, then develop and challenge it against linked evidence."))
                }
            }
            .frame(minWidth: 300, idealWidth: 360)
            if let selectedIdea { IdeaDetailView(idea: selectedIdea).frame(minWidth: 560) }
            else { ContentUnavailableView("Select an idea", systemImage: "arrow.left") }
        }
        .toolbar { Button("New Idea", systemImage: "plus") { showingNewIdea = true } }
        .sheet(isPresented: $showingNewIdea) { IdeaEditorSheet(idea: nil) }
    }
}

private struct IdeaDetailView: View {
    @EnvironmentObject private var model: AppModel
    let idea: ResearchIdea
    @State private var showingEditor = false
    @State private var showingLinkSheet = false
    @State private var showingDelete = false

    private var links: [ResearchIdeaLink] { model.ideaLinks.filter { $0.ideaID == idea.id } }
    private var versions: [IdeaVersion] { model.ideaVersions.filter { $0.ideaID == idea.id }.sorted { $0.createdAt > $1.createdAt } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(idea.status.rawValue).font(.caption.weight(.semibold)).foregroundStyle(.purple)
                        Text(idea.title).font(.largeTitle.weight(.semibold))
                    }
                    Spacer()
                    Button("Edit", systemImage: "pencil") { showingEditor = true }
                    Button("Delete", systemImage: "trash", role: .destructive) { showingDelete = true }
                }
                ideaField("Idea", idea.body)
                ideaField("Assumptions", idea.assumptions)
                ideaField("Alternative explanations", idea.alternativeExplanations)
                ideaField("Evidence needed", idea.evidenceNeeded)
                ideaField("Investigation notes", idea.investigationNotes)
                Divider()
                HStack {
                    Text("Linked research").font(.title2.weight(.semibold))
                    Spacer()
                    Button("Add Link", systemImage: "link.badge.plus") { showingLinkSheet = true }
                }
                if links.isEmpty { Text("No papers, passages, notes, concepts, or arguments are linked yet.").foregroundStyle(.secondary) }
                ForEach(links) { link in
                    HStack {
                        Label(model.ideaLinkLabel(link), systemImage: linkIcon(link.targetType))
                        Spacer()
                        Text(link.targetType.rawValue).font(.caption).foregroundStyle(.secondary)
                        Button("Remove", systemImage: "xmark.circle") { model.deleteIdeaLink(link) }.labelStyle(.iconOnly).buttonStyle(.plain)
                    }
                }
                Divider()
                GroupBox("Challenge My Idea — local review prompts") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("These prompts are generated from missing or unlinked fields in this record; they are not claims about your psychology or the wider literature.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(model.challengeQuestions(for: idea), id: \.self) { question in
                            Label(question, systemImage: "questionmark.bubble").frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 5)
                }
                Divider()
                Text("Recorded development").font(.title2.weight(.semibold))
                ForEach(versions) { version in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(version.changeNote).font(.headline); Spacer(); Text(version.createdAt.formatted()).font(.caption).foregroundStyle(.secondary) }
                        Text(version.title)
                        Text(version.status.rawValue).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(11).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
                }
            }
            .padding(26)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .sheet(isPresented: $showingEditor) { IdeaEditorSheet(idea: idea) }
        .sheet(isPresented: $showingLinkSheet) { IdeaLinkSheet(ideaID: idea.id) }
        .confirmationDialog("Delete this idea and its recorded versions?", isPresented: $showingDelete) {
            Button("Delete Idea", role: .destructive) { model.deleteIdea(idea) }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder private func ideaField(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(value).textSelection(.enabled)
            }
        }
    }

    private func linkIcon(_ type: IdeaLinkTargetType) -> String {
        switch type {
        case .literature: "books.vertical"
        case .passage: "doc.text"
        case .note: "note.text"
        case .concept: "circle.hexagongrid"
        case .argument: "point.3.connected.trianglepath.dotted"
        }
    }
}

private struct IdeaEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let original: ResearchIdea?
    @State private var draft: ResearchIdea
    @State private var changeNote = ""

    init(idea: ResearchIdea?) {
        original = idea
        _draft = State(initialValue: idea ?? ResearchIdea(title: ""))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(original == nil ? "New Research Idea" : "Develop Research Idea").font(.title2.weight(.semibold))
            ScrollView {
                VStack(spacing: 11) {
                    TextField("Title", text: $draft.title)
                    Picker("Project", selection: $draft.projectID) {
                        Text("Not linked").tag(UUID?.none)
                        ForEach(model.projects) { Text($0.title).tag(UUID?.some($0.id)) }
                    }
                    Picker("Research question", selection: $draft.questionID) {
                        Text("Not linked").tag(UUID?.none)
                        ForEach(model.questions) { Text($0.question).tag(UUID?.some($0.id)) }
                    }
                    Picker("Status", selection: $draft.status) { ForEach(ResearchIdeaStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    field("Idea or observation", text: $draft.body)
                    field("Assumptions", text: $draft.assumptions)
                    field("Alternative explanations", text: $draft.alternativeExplanations)
                    field("Evidence needed or evidence that would change your view", text: $draft.evidenceNeeded)
                    field("Possible empirical investigation", text: $draft.investigationNotes)
                    if original != nil { field("Why are you making this revision?", text: $changeNote) }
                }
            }
            HStack {
                Spacer(); Button("Cancel") { dismiss() }
                Button(original == nil ? "Create Idea" : "Save Revision") {
                    model.saveIdea(draft, changeNote: original == nil ? nil : changeNote); dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (original != nil && changeNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding(24).frame(width: 720, height: 700)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text, axis: .vertical).lineLimit(2...5).frame(maxWidth: .infinity)
    }
}

private struct IdeaLinkSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let ideaID: UUID
    @State private var targetType: IdeaLinkTargetType = .literature
    @State private var targetID = ""
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Link Research to Idea").font(.title2.weight(.semibold))
            Picker("Record type", selection: $targetType) { ForEach(IdeaLinkTargetType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .onChange(of: targetType) { _, _ in targetID = model.ideaLinkOptions(for: targetType).first?.id ?? "" }
            Picker("Record", selection: $targetID) {
                Text("Select…").tag("")
                ForEach(model.ideaLinkOptions(for: targetType), id: \.id) { option in Text(option.label).tag(option.id) }
            }
            TextField("Why is this relevant?", text: $notes, axis: .vertical).lineLimit(2...5)
            HStack {
                Spacer(); Button("Cancel") { dismiss() }
                Button("Add Link") { model.saveIdeaLink(ResearchIdeaLink(ideaID: ideaID, targetType: targetType, targetID: targetID, notes: notes)); dismiss() }
                    .buttonStyle(.borderedProminent).disabled(targetID.isEmpty)
            }
        }
        .padding(24).frame(width: 620)
        .onAppear { targetID = model.ideaLinkOptions(for: targetType).first?.id ?? "" }
    }
}
