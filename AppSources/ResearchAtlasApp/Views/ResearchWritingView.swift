import ResearchAtlasCore
import SwiftUI

struct ResearchWritingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingNewDocument = false

    private var selectedDocument: WritingDocument? { model.writingDocuments.first { $0.id == model.selectedWritingDocumentID } }

    var body: some View {
        HSplitView {
            List(model.writingDocuments, selection: $model.selectedWritingDocumentID) { document in
                VStack(alignment: .leading, spacing: 5) {
                    Text(document.title).font(.headline).lineLimit(3)
                    HStack { Text(document.purpose.rawValue); Spacer(); Text(document.status) }
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 5).tag(document.id)
            }
            .overlay {
                if model.writingDocuments.isEmpty {
                    ContentUnavailableView("No writing workspaces", systemImage: "square.and.pencil", description: Text("Create an outline and assemble evidence without replacing your main writing system."))
                }
            }
            .frame(minWidth: 280, idealWidth: 330)
            if let selectedDocument {
                WritingDocumentWorkspace(document: selectedDocument).frame(minWidth: 650)
            } else {
                ContentUnavailableView("Select a writing workspace", systemImage: "arrow.left")
            }
        }
        .toolbar { Button("New Writing Workspace", systemImage: "plus") { showingNewDocument = true } }
        .sheet(isPresented: $showingNewDocument) { WritingDocumentSheet(document: nil) }
        .onChange(of: model.selectedWritingDocumentID) { _, documentID in
            model.selectedWritingSectionID = documentID.flatMap { model.sections(for: $0).first?.id }
        }
    }
}

private struct WritingDocumentWorkspace: View {
    @EnvironmentObject private var model: AppModel
    let document: WritingDocument
    @State private var showingDocumentEditor = false
    @State private var showingNewSection = false
    @State private var showingDelete = false

    private var selectedSection: WritingSection? {
        model.sections(for: document.id).first { $0.id == model.selectedWritingSectionID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.title).font(.title2.weight(.semibold))
                    Text("\(document.purpose.rawValue) · \(document.status)").font(.caption).foregroundStyle(.secondary)
                    if !document.notes.isEmpty { Text(document.notes).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer()
                Button("Edit") { showingDocumentEditor = true }
                Button("Export Markdown", systemImage: "square.and.arrow.up") { model.exportWritingDocument(document) }
                Menu {
                    Button("Delete Workspace", systemImage: "trash", role: .destructive) { showingDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            .padding(16).background(.bar)
            Divider()
            HSplitView {
                VStack(spacing: 0) {
                    HStack { Text("Outline").font(.headline); Spacer(); Button { showingNewSection = true } label: { Image(systemName: "plus") }.buttonStyle(.plain) }
                        .padding(12)
                    Divider()
                    List(model.sections(for: document.id), selection: $model.selectedWritingSectionID) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.title).font(.headline)
                            Text(section.body.isEmpty ? "No draft text" : section.body).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }
                        .padding(.vertical, 5).tag(section.id)
                    }
                    .overlay {
                        if model.sections(for: document.id).isEmpty {
                            ContentUnavailableView("No outline sections", systemImage: "list.bullet.indent", description: Text("Add a section for a claim, comparison, or unresolved question."))
                        }
                    }
                }
                .frame(minWidth: 240, idealWidth: 290)
                if let selectedSection {
                    WritingSectionEditor(section: selectedSection).id(selectedSection.id).frame(minWidth: 460)
                } else {
                    ContentUnavailableView("Select an outline section", systemImage: "arrow.left")
                }
            }
        }
        .sheet(isPresented: $showingDocumentEditor) { WritingDocumentSheet(document: document) }
        .sheet(isPresented: $showingNewSection) { NewWritingSectionSheet(documentID: document.id) }
        .confirmationDialog("Delete this writing workspace?", isPresented: $showingDelete) {
            Button("Delete Workspace", role: .destructive) { model.deleteWritingDocument(document) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Only the application-owned outline, draft sections, and review records are removed. Sources and Obsidian notes are unchanged.") }
    }
}

private struct WritingSectionEditor: View {
    @EnvironmentObject private var model: AppModel
    let section: WritingSection
    @State private var title: String
    @State private var draftBody: String
    @State private var notes: String
    @State private var showingLink = false
    @State private var showingDelete = false

    init(section: WritingSection) {
        self.section = section
        _title = State(initialValue: section.title)
        _draftBody = State(initialValue: section.body)
        _notes = State(initialValue: section.notes)
    }

    private var linkedLiteratureIDs: Set<UUID> {
        var result: Set<UUID> = []
        for link in model.writingLinks(for: section.id) {
            guard let targetID = UUID(uuidString: link.targetID) else { continue }
            switch link.targetType {
            case .claim:
                if let literatureID = model.claims.first(where: { $0.id == targetID })?.literatureID {
                    result.insert(literatureID)
                }
            case .argumentEvidence:
                if let literatureID = model.evidenceRecords.first(where: { $0.id == targetID })?.literatureID {
                    result.insert(literatureID)
                }
            case .literature:
                result.insert(targetID)
            case .argument:
                result.formUnion(model.evidence(for: targetID).map(\.literatureID))
            }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Section title", text: $title).font(.title.weight(.semibold))
                TextEditor(text: $draftBody)
                    .font(.body).frame(minHeight: 240)
                    .padding(8).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
                TextField("Planning notes, unresolved questions, or qualifications", text: $notes, axis: .vertical).lineLimit(2...6)
                HStack {
                    Button("Save Section", systemImage: "checkmark") {
                        var updated = section; updated.title = title; updated.body = draftBody; updated.notes = notes
                        model.saveWritingSection(updated)
                    }
                    .buttonStyle(.borderedProminent).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Delete Section", systemImage: "trash", role: .destructive) { showingDelete = true }
                    Spacer()
                }
                Divider()
                HStack {
                    Text("Evidence links").font(.title2.weight(.semibold))
                    Spacer()
                    Button("Link Evidence", systemImage: "link.badge.plus") { showingLink = true }
                }
                if model.writingLinks(for: section.id).isEmpty {
                    Text("No evidence is attached to this section. A citation-support review will report that limitation explicitly.").foregroundStyle(.secondary)
                }
                ForEach(model.writingLinks(for: section.id)) { link in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.writingTargetLabel(link)).font(.headline)
                            Text(link.targetType.rawValue + (link.citationKey.map { " · @\($0)" } ?? "")).font(.caption).foregroundStyle(.secondary)
                            if !link.rationale.isEmpty { Text(link.rationale) }
                        }
                        Spacer()
                        Button("Remove", role: .destructive) { model.deleteWritingEvidenceLink(link) }.buttonStyle(.link)
                    }
                    .padding(10).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                }
                GroundedAIContextCard(
                    title: "Check this section against selected evidence",
                    detail: "Open the Grounded Assistant with this draft as the research task. Confirm that the chosen retrieval set matches the section before approving any request.",
                    suggestedQuery: "Review the selected evidence for support, qualifications, contradictions, and missing evidence relevant to this draft section titled ‘\(title)’. Draft text:\n\(String(draftBody.prefix(2_000)))",
                    expectedLiteratureIDs: linkedLiteratureIDs
                )
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Citation-support review").font(.title2.weight(.semibold))
                        Text("Local checks find statements needing review; they do not establish citation correctness by text similarity.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Run Local Review", systemImage: "checkmark.magnifyingglass") { model.runLocalCitationSupportReview(for: section) }
                }
                if model.citationReviews(for: section.id).isEmpty { Text("No citation-support checks recorded.").foregroundStyle(.secondary) }
                ForEach(model.citationReviews(for: section.id)) { review in
                    CitationReviewCard(review: review)
                }
            }
            .padding(22).frame(maxWidth: 900, alignment: .leading)
        }
        .sheet(isPresented: $showingLink) { WritingEvidenceLinkSheet(sectionID: section.id) }
        .confirmationDialog("Delete this section?", isPresented: $showingDelete) {
            Button("Delete Section", role: .destructive) { model.deleteWritingSection(section) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct CitationReviewCard: View {
    @EnvironmentObject private var model: AppModel
    let review: CitationSupportReview
    @State private var assessment: CitationSupportAssessment
    @State private var notes: String

    init(review: CitationSupportReview) {
        self.review = review
        _assessment = State(initialValue: review.assessment)
        _notes = State(initialValue: review.reviewNotes)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("“\(review.statement)”").font(.headline).textSelection(.enabled)
                Text(review.concern).foregroundStyle(.secondary)
                if let linkID = review.evidenceLinkID,
                   let link = model.writingEvidenceLinks.first(where: { $0.id == linkID }) {
                    Button("Inspect closest linked record: \(model.writingTargetLabel(link))", systemImage: "doc.text.magnifyingglass") {
                        model.openWritingEvidenceLink(link)
                    }
                    .buttonStyle(.link)
                }
                Picker("Assessment", selection: $assessment) { ForEach(CitationSupportAssessment.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                TextField("Human review notes", text: $notes, axis: .vertical).lineLimit(2...5)
                HStack {
                    Text(review.origin.rawValue).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Save Review") { model.updateCitationSupportReview(review, assessment: assessment, notes: notes) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct WritingDocumentSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let original: WritingDocument?
    @State private var title: String
    @State private var purpose: WritingPurpose
    @State private var status: String
    @State private var notes: String
    @State private var projectID: UUID?
    @State private var questionID: UUID?

    init(document: WritingDocument?) {
        original = document
        _title = State(initialValue: document?.title ?? "")
        _purpose = State(initialValue: document?.purpose ?? .literatureReview)
        _status = State(initialValue: document?.status ?? "Planning")
        _notes = State(initialValue: document?.notes ?? "")
        _projectID = State(initialValue: document?.projectID)
        _questionID = State(initialValue: document?.questionID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(original == nil ? "New Writing Workspace" : "Edit Writing Workspace").font(.title2.weight(.semibold))
            TextField("Title", text: $title)
            Picker("Purpose", selection: $purpose) { ForEach(WritingPurpose.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Picker("Project", selection: $projectID) {
                Text("Not linked").tag(nil as UUID?)
                ForEach(model.projects) { Text($0.title).tag($0.id as UUID?) }
            }
            Picker("Research question", selection: $questionID) {
                Text("Not linked").tag(nil as UUID?)
                ForEach(model.questions.filter { projectID == nil || $0.projectID == projectID }) { Text($0.question).tag($0.id as UUID?) }
            }
            Picker("Status", selection: $status) { ForEach(["Planning", "Drafting", "Evidence review", "Ready to export", "Archived"], id: \.self) { Text($0).tag($0) } }
            TextField("Purpose, boundaries, or unresolved questions", text: $notes, axis: .vertical).lineLimit(3...7)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") {
                var document = original ?? WritingDocument(title: title)
                document.title = title; document.purpose = purpose; document.status = status; document.notes = notes
                document.projectID = projectID; document.questionID = questionID
                model.saveWritingDocument(document); dismiss()
            }.buttonStyle(.borderedProminent).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
        .padding(24).frame(width: 650)
    }
}

private struct NewWritingSectionSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let documentID: UUID
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("New Outline Section").font(.title2.weight(.semibold))
            TextField("Section title", text: $title)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Add Section") { model.addWritingSection(documentID: documentID, title: title); dismiss() }.buttonStyle(.borderedProminent).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
        .padding(24).frame(width: 520)
    }
}

private struct WritingEvidenceLinkSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let sectionID: UUID
    @State private var type: WritingEvidenceTargetType = .claim
    @State private var targetID = ""
    @State private var rationale = ""

    private var options: [(id: String, label: String, citationKey: String?)] { model.writingTargetOptions(for: type) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Link Evidence to Section").font(.title2.weight(.semibold))
            Picker("Record type", selection: $type) { ForEach(WritingEvidenceTargetType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Picker("Evidence", selection: $targetID) {
                Text("Choose a record").tag("")
                ForEach(options, id: \.id) { Text($0.label).tag($0.id) }
            }
            TextField("How this record supports, qualifies, or challenges the section", text: $rationale, axis: .vertical).lineLimit(3...6)
            Text("Linking a record does not verify that it supports every nearby sentence. Use Citation-support review to record that judgment explicitly.")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Link") {
                let citationKey = options.first { $0.id == targetID }?.citationKey
                model.saveWritingEvidenceLink(WritingEvidenceLink(sectionID: sectionID, targetType: type, targetID: targetID, citationKey: citationKey, rationale: rationale)); dismiss()
            }.buttonStyle(.borderedProminent).disabled(targetID.isEmpty) }
        }
        .padding(24).frame(width: 680)
        .onChange(of: type) { _, _ in targetID = "" }
    }
}
