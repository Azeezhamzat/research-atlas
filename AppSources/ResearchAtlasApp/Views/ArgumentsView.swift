import ResearchAtlasCore
import SwiftUI

struct ArgumentsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingArgumentSheet = false

    var body: some View {
        HSplitView {
            List(model.arguments, selection: $model.selectedArgumentID) { argument in
                VStack(alignment: .leading, spacing: 6) {
                    Text(argument.proposition).font(.headline).lineLimit(3)
                    Text(argument.status).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 5)
                .tag(argument.id)
            }
            .overlay {
                if model.arguments.isEmpty {
                    ContentUnavailableView("No arguments", systemImage: "point.3.connected.trianglepath.dotted", description: Text("Create a proposition, then link literature as evidence."))
                }
            }
            .frame(minWidth: 310, idealWidth: 370)

            if let argument = model.selectedArgument {
                ArgumentDetailView(argument: argument)
                    .frame(minWidth: 520)
            } else {
                ContentUnavailableView("Select an argument", systemImage: "arrow.left", description: Text("Choose an argument or create one."))
            }
        }
        .toolbar {
            Button { showingArgumentSheet = true } label: { Label("New Argument", systemImage: "plus") }
        }
        .sheet(isPresented: $showingArgumentSheet) { NewArgumentSheet() }
    }
}

private struct ArgumentDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingEvidenceSheet = false
    @State private var showingEditSheet = false
    let argument: ResearchArgument

    private var evidence: [EvidenceRelationship] { model.evidence(for: argument.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Proposition").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(argument.proposition).font(.largeTitle.weight(.semibold)).textSelection(.enabled)
                    if !argument.qualification.isEmpty {
                        Text(argument.qualification).font(.title3).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    HStack {
                        Text(argument.status)
                            .font(.caption.weight(.medium)).padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                        Spacer()
                        Button("Edit Argument", systemImage: "pencil") { showingEditSheet = true }
                    }
                }
                GroundedAIContextCard(
                    title: "Challenge this argument",
                    detail: "Ask the Grounded Assistant about the proposition, run a cautious critical review, or simulate structured counter-perspectives in Argument Room.",
                    suggestedQuery: "Assess what the selected evidence supports, qualifies, challenges, or leaves unresolved about this proposition: \(argument.proposition)",
                    argument: argument,
                    expectedLiteratureIDs: Set(evidence.map(\.literatureID))
                )
                Divider()
                HStack {
                    Text("Linked evidence").font(.title2.weight(.semibold))
                    Spacer()
                    Button("Add Evidence", systemImage: "link.badge.plus") { showingEvidenceSheet = true }
                        .disabled(model.literature.isEmpty)
                }
                if evidence.isEmpty {
                    Text(model.literature.isEmpty ? "Add literature before linking evidence." : "No evidence has been linked. Add a source and record how it bears on the proposition.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                } else {
                    ForEach(evidence) { relationship in
                        EvidenceCard(evidence: relationship, item: model.literature.first { $0.id == relationship.literatureID })
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recorded history").font(.title2.weight(.semibold))
                    let versions = model.versions(for: argument.id)
                    if versions.isEmpty {
                        Text("No versions were recorded before version tracking began. The next substantive edit will capture the current state as a labelled baseline.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(versions) { version in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(version.changeNote).font(.headline)
                                    Spacer()
                                    Text(version.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text(version.proposition).textSelection(.enabled)
                                if !version.qualification.isEmpty {
                                    Text(version.qualification).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                                Text(version.status).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .sheet(isPresented: $showingEvidenceSheet) { NewEvidenceSheet(argumentID: argument.id) }
        .sheet(isPresented: $showingEditSheet) { EditArgumentSheet(argument: argument) }
    }
}

private struct EvidenceCard: View {
    @EnvironmentObject private var model: AppModel
    let evidence: EvidenceRelationship
    let item: LiteratureItem?
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(evidence.relation.rawValue).font(.headline)
                Spacer()
                Text(evidence.verification.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(evidence.verification == .verified ? .green : .secondary)
            }
            Text(item?.title ?? "Source no longer available").font(.subheadline.weight(.medium))
            Text(evidence.summary).textSelection(.enabled)
            if !evidence.quotedPassage.isEmpty {
                Text("“\(evidence.quotedPassage)”")
                    .font(.callout).foregroundStyle(.secondary).italic().textSelection(.enabled)
            }
            if let page = evidence.page { Text("Page \(page)").font(.caption).foregroundStyle(.secondary) }
            if !evidence.selectionRegions.isEmpty {
                let geometryCurrent = evidence.selectionDocumentHash == nil || evidence.selectionDocumentHash == item?.pdfContentHash
                Label(
                    geometryCurrent ? "PDF selection geometry captured" : "Selection geometry belongs to an earlier PDF fingerprint",
                    systemImage: geometryCurrent ? "viewfinder" : "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(geometryCurrent ? Color.secondary : Color.orange)
            }
            HStack {
                if item?.pdfPath != nil {
                    Button("Open Source", systemImage: "doc.text.magnifyingglass") {
                        model.openEvidenceInReadingDesk(evidence)
                    }
                }
                Spacer()
                Button("Edit", systemImage: "pencil") { showingEditSheet = true }
                Button("Delete", systemImage: "trash", role: .destructive) { showingDeleteConfirmation = true }
            }
            .controlSize(.small)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor)))
        .sheet(isPresented: $showingEditSheet) { EditEvidenceSheet(evidence: evidence) }
        .confirmationDialog(
            "Delete this evidence annotation?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Evidence", role: .destructive) { model.deleteEvidence(evidence) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The source PDF is not changed. This removes only the Research Atlas relationship and annotation.")
        }
    }
}

private struct EditEvidenceSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let evidence: EvidenceRelationship
    @State private var relation: EvidenceRelation
    @State private var summary: String
    @State private var pageText: String
    @State private var quote: String
    @State private var verification: VerificationState

    init(evidence: EvidenceRelationship) {
        self.evidence = evidence
        _relation = State(initialValue: evidence.relation)
        _summary = State(initialValue: evidence.summary)
        _pageText = State(initialValue: evidence.page.map(String.init) ?? "")
        _quote = State(initialValue: evidence.quotedPassage)
        _verification = State(initialValue: evidence.verification)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Edit Evidence Annotation").font(.title2.weight(.semibold))
            Picker("Relationship", selection: $relation) {
                ForEach(EvidenceRelation.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            TextField("Why this source is relevant", text: $summary, axis: .vertical).lineLimit(2...5)
            HStack {
                TextField("Page (optional)", text: $pageText).frame(width: 140)
                Picker("Verification", selection: $verification) {
                    ForEach(VerificationState.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
            TextField("Exact passage", text: $quote, axis: .vertical).lineLimit(3...8)
            if !evidence.selectionRegions.isEmpty {
                Text("Saved PDF geometry and its document fingerprint remain attached to this annotation.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    var updated = evidence
                    updated.relation = relation
                    updated.summary = summary
                    updated.page = Int(pageText)
                    updated.quotedPassage = quote
                    updated.verification = verification
                    model.updateEvidence(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 660)
    }
}

private struct NewArgumentSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var proposition = ""
    @State private var qualification = ""
    @State private var questionID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Research Argument").font(.title2.weight(.semibold))
            Picker("Research question", selection: $questionID) {
                Text("Not linked").tag(UUID?.none)
                ForEach(model.questions) { question in Text(question.question).tag(UUID?.some(question.id)) }
            }
            TextField("Proposition", text: $proposition, axis: .vertical).lineLimit(3...7)
            TextField("Qualification or boundary conditions", text: $qualification, axis: .vertical).lineLimit(2...5)
            Text("This creates a user-authored argument. Evidence remains unverified until you mark it otherwise.")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Create") { model.saveArgument(questionID: questionID, proposition: proposition, qualification: qualification); dismiss() }.buttonStyle(.borderedProminent).disabled(proposition.trimmingCharacters(in: .whitespaces).isEmpty) }
        }
        .padding(24).frame(width: 620)
    }
}

private struct EditArgumentSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let argument: ResearchArgument
    @State private var proposition: String
    @State private var qualification: String
    @State private var status: String
    @State private var questionID: UUID?
    @State private var changeNote = ""

    init(argument: ResearchArgument) {
        self.argument = argument
        _proposition = State(initialValue: argument.proposition)
        _qualification = State(initialValue: argument.qualification)
        _status = State(initialValue: argument.status)
        _questionID = State(initialValue: argument.questionID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Revise Argument").font(.title2.weight(.semibold))
            Picker("Research question", selection: $questionID) {
                Text("Not linked").tag(UUID?.none)
                ForEach(model.questions) { question in Text(question.question).tag(UUID?.some(question.id)) }
            }
            TextField("Proposition", text: $proposition, axis: .vertical).lineLimit(3...7)
            TextField("Qualification or boundary conditions", text: $qualification, axis: .vertical).lineLimit(2...5)
            Picker("Status", selection: $status) {
                ForEach(["Developing", "Active", "Qualified", "Superseded"], id: \.self) { Text($0).tag($0) }
            }
            TextField("Why are you making this revision?", text: $changeNote, axis: .vertical).lineLimit(2...4)
            Text("The existing state and this revision will remain available in the recorded history.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save Revision") {
                    model.updateArgument(argument, questionID: questionID, proposition: proposition, qualification: qualification, status: status, changeNote: changeNote)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(proposition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || changeNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 640)
    }
}

private struct NewEvidenceSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let argumentID: UUID
    @State private var literatureID: UUID?
    @State private var relation: EvidenceRelation = .supports
    @State private var summary = ""
    @State private var pageText = ""
    @State private var quote = ""
    @State private var verification: VerificationState = .unverified

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Link Evidence").font(.title2.weight(.semibold))
            Picker("Source", selection: $literatureID) {
                Text("Choose a paper").tag(UUID?.none)
                ForEach(model.literature) { item in Text(item.title).tag(UUID?.some(item.id)) }
            }
            Picker("Relationship", selection: $relation) { ForEach(EvidenceRelation.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            TextField("Why this source is relevant", text: $summary, axis: .vertical).lineLimit(2...5)
            HStack { TextField("Page (optional)", text: $pageText).frame(width: 130); Picker("Status", selection: $verification) { ForEach(VerificationState.allCases, id: \.self) { Text($0.rawValue).tag($0) } } }
            TextField("Exact passage (optional; do not paraphrase here)", text: $quote, axis: .vertical).lineLimit(3...7)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Link Evidence") {
                    guard let literatureID else { return }
                    model.saveEvidence(argumentID: argumentID, literatureID: literatureID, relation: relation, summary: summary, page: Int(pageText), quote: quote, verification: verification)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(literatureID == nil || summary.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24).frame(width: 660)
        .onAppear { literatureID = model.literature.first?.id }
    }
}
