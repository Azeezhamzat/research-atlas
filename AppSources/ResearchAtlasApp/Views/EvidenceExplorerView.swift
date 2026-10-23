import ResearchAtlasCore
import SwiftUI

struct EvidenceExplorerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Workspace", selection: $model.evidenceExplorerMode) {
                Text("Retrieval Sets").tag(0)
                Text("Literature Comparison").tag(1)
                Text("Structured Claims").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 430)
            .padding(12)
            .background(.bar)
            switch model.evidenceExplorerMode {
            case 0: RetrievalSetsView()
            case 1: LiteratureComparisonView()
            default: ClaimsWorkspaceView()
            }
        }
    }
}

private struct ClaimsWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingNewClaim = false

    private var selectedClaim: ResearchClaim? { model.claims.first { $0.id == model.selectedClaimID } }

    var body: some View {
        HSplitView {
            List(model.claims, selection: $model.selectedClaimID) { claim in
                VStack(alignment: .leading, spacing: 5) {
                    Text(claim.claimText).font(.headline).lineLimit(3)
                    HStack {
                        Text(claim.category.rawValue)
                        Spacer()
                        Text(claim.verification.rawValue)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 5)
                .tag(claim.id)
            }
            .overlay {
                if model.claims.isEmpty {
                    ContentUnavailableView("No structured claims", systemImage: "quote.bubble", description: Text("Save a claim manually or select a passage in the Reading Desk."))
                }
            }
            .frame(minWidth: 310, idealWidth: 370)
            if let selectedClaim {
                ClaimDetailView(claim: selectedClaim).frame(minWidth: 540)
            } else {
                ContentUnavailableView("Select a claim", systemImage: "arrow.left")
            }
        }
        .toolbar { Button("New Claim", systemImage: "plus") { showingNewClaim = true } }
        .sheet(isPresented: $showingNewClaim) { ClaimEditorSheet(claim: nil) }
    }
}

private struct ClaimDetailView: View {
    @EnvironmentObject private var model: AppModel
    let claim: ResearchClaim
    @State private var showingEditor = false
    @State private var showingDelete = false

    private var paper: LiteratureItem? { claim.literatureID.flatMap { id in model.literature.first { $0.id == id } } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(claim.category.rawValue).font(.caption.weight(.semibold)).foregroundStyle(.indigo)
                        Text(claim.claimText).font(.largeTitle.weight(.semibold)).textSelection(.enabled)
                    }
                    Spacer()
                    Text(claim.verification.rawValue).font(.caption.weight(.medium)).padding(7).background(.quaternary, in: Capsule())
                }
                if let paper {
                    GroupBox("Source") {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(paper.title).font(.headline)
                            if let page = claim.page { Text("Page \(page)").font(.caption).foregroundStyle(.secondary) }
                            if !claim.quotedSourceText.isEmpty {
                                Text("“\(claim.quotedSourceText)”").italic().textSelection(.enabled)
                            }
                            Button("Open Source", systemImage: "doc.text.magnifyingglass") { model.openClaimSource(claim) }
                                .disabled(claim.page == nil || paper.pdfPath == nil)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Label("This user-authored claim is not linked to a source passage.", systemImage: "person.crop.circle")
                        .foregroundStyle(.secondary)
                }
                claimField("Author terminology", claim.authorTerminology)
                claimField("Methodological context", claim.methodologicalContext)
                claimField("Evidence type", claim.evidenceType)
                claimField("Related constructs", claim.relatedConstructs.joined(separator: ", "))
                claimField("Study context", claim.studyContext)
                claimField("User notes", claim.userNotes)
                LabeledContent("Extraction", value: claim.extractionMethod.rawValue)
                if claim.extractionMethod == .aiCandidate {
                    LabeledContent("Model", value: claim.modelIdentifier ?? "Missing")
                    LabeledContent("Prompt version", value: claim.promptVersion ?? "Missing")
                }
                HStack {
                    Button("Edit Claim", systemImage: "pencil") { showingEditor = true }
                    Button("Delete", systemImage: "trash", role: .destructive) { showingDelete = true }
                    Spacer()
                }
                Divider()
                Text("Recorded revisions").font(.title2.weight(.semibold))
                ForEach(model.versions(forClaim: claim.id)) { version in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(version.changeNote).font(.headline); Spacer(); Text(version.createdAt.formatted()).font(.caption).foregroundStyle(.secondary) }
                        Text(version.claimText).textSelection(.enabled)
                        Text("\(version.category.rawValue) · \(version.verification.rawValue)").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
                }
            }
            .padding(26)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .sheet(isPresented: $showingEditor) { ClaimEditorSheet(claim: claim) }
        .confirmationDialog("Delete this application-owned claim?", isPresented: $showingDelete) {
            Button("Delete Claim", role: .destructive) { model.deleteClaim(claim) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The original paper, PDF, passage index, and Obsidian notes are not changed.") }
    }

    @ViewBuilder private func claimField(_ label: String, _ value: String) -> some View {
        if !value.isEmpty { LabeledContent(label) { Text(value).textSelection(.enabled) } }
    }
}

private struct ClaimEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let original: ResearchClaim?
    @State private var text: String
    @State private var category: ClaimCategory
    @State private var terminology: String
    @State private var methodologicalContext: String
    @State private var evidenceType: String
    @State private var constructs: String
    @State private var studyContext: String
    @State private var verification: VerificationState
    @State private var notes: String
    @State private var changeNote = ""

    init(claim: ResearchClaim?) {
        original = claim
        _text = State(initialValue: claim?.claimText ?? "")
        _category = State(initialValue: claim?.category ?? .personalInterpretation)
        _terminology = State(initialValue: claim?.authorTerminology ?? "")
        _methodologicalContext = State(initialValue: claim?.methodologicalContext ?? "")
        _evidenceType = State(initialValue: claim?.evidenceType ?? "")
        _constructs = State(initialValue: claim?.relatedConstructs.joined(separator: ", ") ?? "")
        _studyContext = State(initialValue: claim?.studyContext ?? "")
        _verification = State(initialValue: claim?.verification ?? .unverified)
        _notes = State(initialValue: claim?.userNotes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(original == nil ? "New Manual Claim" : "Revise Claim").font(.title2.weight(.semibold))
            Picker("Category", selection: $category) { ForEach(ClaimCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            TextField("Claim text", text: $text, axis: .vertical).lineLimit(2...5)
            TextField("Author terminology", text: $terminology, axis: .vertical).lineLimit(2...4)
            TextField("Methodological context", text: $methodologicalContext, axis: .vertical).lineLimit(2...4)
            TextField("Evidence type", text: $evidenceType)
            TextField("Related constructs, comma separated", text: $constructs)
            TextField("Study context", text: $studyContext, axis: .vertical).lineLimit(2...4)
            TextField("User notes", text: $notes, axis: .vertical).lineLimit(2...4)
            Picker("Verification", selection: $verification) { ForEach(VerificationState.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            if original != nil { TextField("Why are you revising this claim?", text: $changeNote, axis: .vertical).lineLimit(2...4) }
            HStack {
                Spacer(); Button("Cancel") { dismiss() }
                Button(original == nil ? "Create Claim" : "Save Revision") {
                    var claim = original ?? ResearchClaim(claimText: text, category: category)
                    claim.claimText = text; claim.category = category; claim.authorTerminology = terminology
                    claim.methodologicalContext = methodologicalContext; claim.evidenceType = evidenceType
                    claim.relatedConstructs = constructs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    claim.studyContext = studyContext; claim.verification = verification; claim.userNotes = notes
                    model.saveClaim(claim, changeNote: original == nil ? nil : changeNote)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (original != nil && changeNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding(24).frame(width: 720)
    }
}

private struct RetrievalSetsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingNewSet = false
    @State private var setPendingDeletion: RetrievalSet?

    private var selectedSet: RetrievalSet? {
        model.retrievalSets.first { $0.id == model.selectedRetrievalSetID }
    }

    var body: some View {
        HSplitView {
            List(model.retrievalSets, selection: $model.selectedRetrievalSetID) { set in
                let paperCount = model.passages(for: set.id).count
                let noteCount = model.noteSnippets(for: set.id).count
                VStack(alignment: .leading, spacing: 5) {
                    Text(set.name).font(.headline).lineLimit(2)
                    Text(set.query).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Text("\(paperCount) paper passage\(paperCount == 1 ? "" : "s") · \(noteCount) note excerpt\(noteCount == 1 ? "" : "s")")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 5)
                .tag(set.id)
                .contextMenu {
                    Button("Delete Retrieval Set", systemImage: "trash", role: .destructive) { setPendingDeletion = set }
                }
            }
            .overlay {
                if model.retrievalSets.isEmpty {
                    ContentUnavailableView(
                        "No retrieval sets",
                        systemImage: "text.magnifyingglass",
                        description: Text("Save an inspectable full-text query with exact paper passages and researcher-note excerpts.")
                    )
                }
            }
            .frame(minWidth: 280, idealWidth: 330)

            if let selectedSet {
                RetrievalSetDetail(set: selectedSet)
                    .frame(minWidth: 560)
            } else {
                ContentUnavailableView("Select a retrieval set", systemImage: "arrow.left")
            }
        }
        .toolbar {
            Button("New Retrieval Set", systemImage: "plus") { showingNewSet = true }
        }
        .sheet(isPresented: $showingNewSet) { NewRetrievalSetSheet() }
        .confirmationDialog(
            "Delete this retrieval set?",
            isPresented: Binding(get: { setPendingDeletion != nil }, set: { if !$0 { setPendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Retrieval Set", role: .destructive) {
                if let setPendingDeletion { model.deleteRetrievalSet(setPendingDeletion) }
                setPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { setPendingDeletion = nil }
        } message: {
            Text("This removes the saved query and its paper-passage and note-excerpt snapshots. It does not change PDFs, Obsidian files, or the search index.")
        }
    }
}

private struct RetrievalSetDetail: View {
    @EnvironmentObject private var model: AppModel
    let set: RetrievalSet

    private var passages: [RetrievedPassage] { model.passages(for: set.id) }
    private var noteSnippets: [RetrievedNoteSnippet] { model.noteSnippets(for: set.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(set.name).font(.largeTitle.weight(.semibold))
                    LabeledContent("Query", value: set.query)
                    if set.yearFrom != nil || set.yearTo != nil {
                        LabeledContent("Publication years", value: "\(set.yearFrom.map(String.init) ?? "Any")–\(set.yearTo.map(String.init) ?? "Any")")
                    }
                    Text("Snapshot saved \(set.createdAt.formatted(date: .abbreviated, time: .shortened)). Results are not silently replaced when the index changes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                GroundedAIContextCard(
                    title: "Use this exact evidence with AI",
                    detail: "This is the safest starting point for model assistance: only current snapshots from this saved set are eligible, and paper passages remain distinct from researcher notes.",
                    suggestedQuery: set.query,
                    retrievalSetID: set.id
                )
                Divider()
                if passages.isEmpty && noteSnippets.isEmpty {
                    ContentUnavailableView(
                        "No matching source snapshots",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("The local index returned no grounded paper passages or note excerpts for this query and filter combination.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    if !passages.isEmpty {
                        Label("Published-source passages", systemImage: "doc.text")
                            .font(.title3.weight(.semibold))
                        Text("These snapshots come from indexed research PDFs and retain page-level provenance.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(passages) { passage in
                        RetrievedPassageCard(passage: passage)
                    }
                    if !noteSnippets.isEmpty {
                        Divider().padding(.vertical, 4)
                        Label("Researcher-note excerpts", systemImage: "note.text")
                            .font(.title3.weight(.semibold))
                        Text("Notes are researcher context, not published evidence. Their exact excerpts and modification dates are preserved separately.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(noteSnippets) { snippet in
                            RetrievedNoteSnippetCard(snippet: snippet)
                        }
                    }
                }
            }
            .padding(26)
            .frame(maxWidth: 920, alignment: .leading)
        }
    }
}

private struct RetrievedNoteSnippetCard: View {
    @EnvironmentObject private var model: AppModel
    let snippet: RetrievedNoteSnippet

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Label(snippet.noteTitle, systemImage: "note.text").font(.headline)
                Spacer()
                Text("Researcher note").font(.caption.weight(.semibold)).foregroundStyle(.indigo)
            }
            Text(snippet.snippetText).lineLimit(8).textSelection(.enabled)
            HStack {
                Label(snippet.citationStatus.rawValue, systemImage: snippet.citationStatus == .current ? "checkmark.shield" : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(snippet.citationStatus == .current ? Color.green : Color.orange)
                Text("modified \(snippet.sourceModifiedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Open Note", systemImage: "arrow.up.forward.app") { model.openRetrievedNote(snippet) }
                    .controlSize(.small)
            }
        }
        .padding(15)
        .background(Color.indigo.opacity(0.055), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.indigo.opacity(0.25)))
    }
}

private struct RetrievedPassageCard: View {
    @EnvironmentObject private var model: AppModel
    let passage: RetrievedPassage

    private var paper: LiteratureItem? { model.literature.first { $0.id == passage.literatureID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(paper?.title ?? "Unavailable source").font(.headline)
                Spacer()
                Text("Page \(passage.page)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            Text(passage.passageText)
                .lineLimit(8)
                .textSelection(.enabled)
            HStack {
                Label(passage.citationStatus.rawValue, systemImage: passage.citationStatus == .current ? "checkmark.shield" : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(passage.citationStatus == .current ? Color.green : Color.orange)
                Text("\(passage.extractionMethod) · indexed \(passage.sourceIndexedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if paper?.pdfPath != nil {
                    Button("Open Source", systemImage: "doc.text.magnifyingglass") { model.openRetrievedPassage(passage) }
                        .controlSize(.small)
                }
            }
        }
        .padding(15)
        .background(.background, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color(nsColor: .separatorColor)))
    }
}

private struct NewRetrievalSetSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var query = ""
    @State private var yearFrom = ""
    @State private var yearTo = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("New Grounded Retrieval Set").font(.title2.weight(.semibold))
            Text("Research Atlas saves the query, year range, exact indexed paper passages, and matching researcher-note excerpts. Notes are labelled separately and never presented as published evidence. An empty result stays empty.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Set name", text: $name)
            TextField("Full-text query", text: $query)
            HStack {
                TextField("Year from", text: $yearFrom).frame(width: 150)
                TextField("Year to", text: $yearTo).frame(width: 150)
                Spacer()
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Retrieve and Save") {
                    model.createRetrievalSet(
                        name: name, query: query, yearFrom: Int(yearFrom), yearTo: Int(yearTo)
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 640)
    }
}

private struct LiteratureComparisonView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editingPaper: LiteratureItem?

    private let rows: [(String, (LiteratureComparisonProfile) -> String)] = [
        ("Research question", { $0.researchQuestion }),
        ("Theoretical framework", { $0.theoreticalFramework }),
        ("Study design", { $0.studyDesign }),
        ("Sample", { $0.sample }),
        ("Independent variables", { $0.independentVariables }),
        ("Dependent variables", { $0.dependentVariables }),
        ("Operational definitions", { $0.operationalDefinitions }),
        ("Main findings", { $0.mainFindings }),
        ("Limitations", { $0.limitations }),
        ("Possible explanations / notes", { $0.userNotes })
    ]

    private var selectedPapers: [LiteratureItem] { model.literature.filter { model.comparisonLiteratureIDs.contains($0.id) } }

    var body: some View {
        HSplitView {
            List(model.literature) { paper in
                HStack(alignment: .top) {
                    Toggle("", isOn: Binding(
                        get: { model.comparisonLiteratureIDs.contains(paper.id) },
                        set: { selected in
                            if selected {
                                model.comparisonLiteratureIDs.insert(paper.id)
                            } else {
                                model.comparisonLiteratureIDs.remove(paper.id)
                            }
                        }
                    ))
                    .labelsHidden()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(paper.title).font(.headline).lineLimit(2)
                        Text(paper.authors).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button("Edit", systemImage: "square.and.pencil") { editingPaper = paper }
                        .labelStyle(.iconOnly).buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if model.literature.isEmpty {
                    ContentUnavailableView("No literature", systemImage: "books.vertical", description: Text("Import papers before building a comparison."))
                }
            }
            .frame(minWidth: 300, idealWidth: 350)

            if selectedPapers.isEmpty {
                ContentUnavailableView(
                    "Choose papers to compare",
                    systemImage: "tablecells",
                    description: Text("Comparison fields are user-authored. Missing information remains explicitly unavailable.")
                )
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            Text("Field").font(.headline).padding(12).frame(width: 190, alignment: .leading)
                            ForEach(selectedPapers) { paper in
                                Text(paper.title).font(.headline).padding(12).frame(width: 270, alignment: .leading)
                            }
                        }
                        Divider()
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            GridRow {
                                Text(row.0).font(.subheadline.weight(.semibold)).padding(12).frame(width: 190, alignment: .leading)
                                ForEach(selectedPapers) { paper in
                                    let value = row.1(model.comparisonProfile(for: paper.id))
                                    Text(value.isEmpty ? "Unavailable" : value)
                                        .foregroundStyle(value.isEmpty ? .secondary : .primary)
                                        .textSelection(.enabled)
                                        .padding(12)
                                        .frame(width: 270, alignment: .topLeading)
                                }
                            }
                            Divider()
                        }
                    }
                    .background(.background)
                }
            }
        }
        .sheet(item: $editingPaper) { paper in
            ComparisonProfileSheet(paper: paper, profile: model.comparisonProfile(for: paper.id))
        }
    }
}

private struct ComparisonProfileSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let paper: LiteratureItem
    @State private var profile: LiteratureComparisonProfile

    init(paper: LiteratureItem, profile: LiteratureComparisonProfile) {
        self.paper = paper
        _profile = State(initialValue: profile)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Comparison Profile").font(.title2.weight(.semibold))
            Text(paper.title).font(.headline).foregroundStyle(.secondary).lineLimit(2)
            Text("Record only what the source supports. Leave unavailable fields blank.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 12) {
                    field("Research question", text: $profile.researchQuestion)
                    field("Theoretical framework", text: $profile.theoreticalFramework)
                    field("Study design", text: $profile.studyDesign)
                    field("Sample", text: $profile.sample)
                    field("Independent variables", text: $profile.independentVariables)
                    field("Dependent variables", text: $profile.dependentVariables)
                    field("Operational definitions", text: $profile.operationalDefinitions)
                    field("Main findings", text: $profile.mainFindings)
                    field("Limitations", text: $profile.limitations)
                    field("Possible explanations / notes", text: $profile.userNotes)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save Profile") { model.saveComparisonProfile(profile); dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 720, height: 720)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField(label, text: text, axis: .vertical).lineLimit(2...5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
