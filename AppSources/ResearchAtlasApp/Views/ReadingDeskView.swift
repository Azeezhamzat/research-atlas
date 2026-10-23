import PDFKit
import ResearchAtlasCore
import SwiftUI

struct ReadingDeskView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchTerm = ""
    @State private var selectedPassage = ""
    @State private var selectedPage: Int?
    @State private var selectedRegions: [PDFSelectionRegion] = []
    @State private var showingEvidenceSheet = false
    @State private var showingClaimSheet = false

    var body: some View {
        VStack(spacing: 0) {
            if let item = model.selectedLiterature,
               model.pdfFileAvailability(for: item) == .available,
               let path = item.pdfPath {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.headline).lineLimit(1)
                        Text(item.authors).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    TextField("Find in PDF", text: $searchTerm)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
                .padding(10)
                .background(.bar)
                if let warning = model.scannedPDFWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.08))
                }
                HSplitView {
                    PDFKitView(
                        url: URL(fileURLWithPath: path),
                        searchTerm: searchTerm,
                        evidenceTarget: model.readingEvidenceTarget?.literatureID == item.id ? model.readingEvidenceTarget : nil,
                        targetPage: model.readingPassageTarget?.literatureID == item.id ? model.readingPassageTarget?.page : nil,
                        targetGeometryIsCurrent: model.readingEvidenceTarget?.selectionDocumentHash == nil
                            || model.readingEvidenceTarget?.selectionDocumentHash == item.pdfContentHash
                    ) { text, page, regions in
                        selectedPassage = text
                        selectedPage = page
                        selectedRegions = regions
                    }
                    .frame(minWidth: 520)

                    PassageInspector(
                        passage: selectedPassage,
                        page: selectedPage,
                        canLink: !model.arguments.isEmpty,
                        addEvidence: { showingEvidenceSheet = true },
                        saveClaim: { showingClaimSheet = true }
                    )
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 380)
                }
                .sheet(isPresented: $showingEvidenceSheet) {
                    PassageEvidenceSheet(item: item, passage: selectedPassage, page: selectedPage, selectionRegions: selectedRegions)
                }
                .sheet(isPresented: $showingClaimSheet) {
                    PassageClaimSheet(item: item, passage: selectedPassage, page: selectedPage)
                }
                .onAppear { model.verifyAndIndexPDFIfNeeded(item) }
            } else {
                ContentUnavailableView(
                    "No readable PDF selected",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Choose a paper with an accessible local PDF, or repair its missing file link in the Literature Library.")
                )
            }
        }
        .toolbar {
            Button("Choose paper") { model.selectedSection = .library }
        }
    }
}

private struct PDFKitView: NSViewRepresentable {
    let url: URL
    let searchTerm: String
    let evidenceTarget: EvidenceRelationship?
    let targetPage: Int?
    let targetGeometryIsCurrent: Bool
    let selectionChanged: (String, Int?, [PDFSelectionRegion]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(selectionChanged: selectionChanged) }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = .windowBackgroundColor
        view.document = PDFDocument(url: url)
        context.coordinator.url = url
        context.coordinator.view = view
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pdfSelectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: view
        )
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.selectionChanged = selectionChanged
        if context.coordinator.url != url {
            view.document = PDFDocument(url: url)
            context.coordinator.url = url
            context.coordinator.lastSearch = ""
            context.coordinator.lastEvidenceID = nil
            context.coordinator.lastTargetPage = nil
        }
        context.coordinator.show(evidenceTarget, geometryIsCurrent: targetGeometryIsCurrent)
        if evidenceTarget == nil { context.coordinator.show(page: targetPage) }
        guard searchTerm != context.coordinator.lastSearch else { return }
        context.coordinator.lastSearch = searchTerm
        view.highlightedSelections = []
        guard !searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let selections = view.document?.findString(searchTerm, withOptions: [.caseInsensitive]) else { return }
        view.highlightedSelections = selections
        if let first = selections.first { view.go(to: first) }
    }

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    final class Coordinator: NSObject {
        weak var view: PDFView?
        var url: URL?
        var lastSearch = ""
        var lastEvidenceID: UUID?
        var lastTargetPage: Int?
        var selectionChanged: (String, Int?, [PDFSelectionRegion]) -> Void

        init(selectionChanged: @escaping (String, Int?, [PDFSelectionRegion]) -> Void) {
            self.selectionChanged = selectionChanged
        }

        @MainActor func show(_ evidence: EvidenceRelationship?, geometryIsCurrent: Bool) {
            guard let view, let document = view.document, evidence?.id != lastEvidenceID else { return }
            lastEvidenceID = evidence?.id
            guard let evidence else { return }
            let regions = geometryIsCurrent ? evidence.selectionRegions : []
            var selections: [PDFSelection] = []
            for region in regions {
                guard region.page > 0, let page = document.page(at: region.page - 1) else { continue }
                let pageBounds = page.bounds(for: view.displayBox)
                let rect = CGRect(
                    x: pageBounds.minX + region.normalizedX * pageBounds.width,
                    y: pageBounds.minY + region.normalizedY * pageBounds.height,
                    width: region.normalizedWidth * pageBounds.width,
                    height: region.normalizedHeight * pageBounds.height
                )
                if let selection = page.selection(for: rect) { selections.append(selection) }
            }
            if !selections.isEmpty {
                view.highlightedSelections = selections
                view.go(to: selections[0])
            } else if let pageNumber = evidence.page, pageNumber > 0,
                      let page = document.page(at: pageNumber - 1) {
                view.go(to: page)
            }
        }

        @MainActor func show(page pageNumber: Int?) {
            guard let pageNumber, pageNumber > 0, pageNumber != lastTargetPage,
                  let view, let page = view.document?.page(at: pageNumber - 1) else { return }
            lastTargetPage = pageNumber
            view.go(to: page)
        }

        @MainActor @objc func pdfSelectionChanged(_ notification: Notification) {
            guard let view, let selection = view.currentSelection else {
                selectionChanged("", nil, [])
                return
            }
            let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let regions = selection.pages.compactMap { selectedPage -> PDFSelectionRegion? in
                guard let document = view.document else { return nil }
                let pageNumber = document.index(for: selectedPage) + 1
                let pageBounds = selectedPage.bounds(for: view.displayBox)
                let selectedBounds = selection.bounds(for: selectedPage).intersection(pageBounds)
                guard pageBounds.width > 0, pageBounds.height > 0,
                      !selectedBounds.isNull, !selectedBounds.isEmpty else { return nil }
                return PDFSelectionRegion(
                    page: pageNumber,
                    normalizedX: (selectedBounds.minX - pageBounds.minX) / pageBounds.width,
                    normalizedY: (selectedBounds.minY - pageBounds.minY) / pageBounds.height,
                    normalizedWidth: selectedBounds.width / pageBounds.width,
                    normalizedHeight: selectedBounds.height / pageBounds.height
                )
            }
            selectionChanged(text, regions.first?.page, regions)
        }
    }
}

private struct PassageInspector: View {
    let passage: String
    let page: Int?
    let canLink: Bool
    let addEvidence: () -> Void
    let saveClaim: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Source passage").font(.headline)
            if passage.isEmpty {
                ContentUnavailableView(
                    "Select text in the PDF",
                    systemImage: "text.cursor",
                    description: Text("A selection can be linked to an argument with its exact page and wording preserved.")
                )
            } else {
                if let page { Text("Page \(page)").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                ScrollView {
                    Text(passage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .lineSpacing(3)
                }
                Button("Link to Argument", systemImage: "link.badge.plus", action: addEvidence)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canLink)
                Button("Save Structured Claim", systemImage: "quote.bubble", action: saveClaim)
                    .buttonStyle(.bordered)
                if !canLink {
                    Text("Create an argument before linking this passage.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct PassageClaimSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let item: LiteratureItem
    let passage: String
    let page: Int?
    @State private var claimText = ""
    @State private var category: ClaimCategory = .empiricalFinding
    @State private var authorTerminology = ""
    @State private var methodologicalContext = ""
    @State private var evidenceType = ""
    @State private var constructs = ""
    @State private var studyContext = ""
    @State private var verification: VerificationState = .unverified
    @State private var userNotes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save Structured Claim").font(.title2.weight(.semibold))
            Text("The selected text remains an exact source quotation. Your claim and interpretation are stored separately and can be revised without changing that source record.")
                .font(.callout).foregroundStyle(.secondary)
            Picker("Claim category", selection: $category) {
                ForEach(ClaimCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            TextField("Claim stated in your own careful wording", text: $claimText, axis: .vertical).lineLimit(2...5)
            GroupBox("Exact source passage\(page.map { " — page \($0)" } ?? "")") {
                Text(passage).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
            }
            HStack {
                TextField("Author's terminology", text: $authorTerminology, axis: .vertical).lineLimit(2...4)
                TextField("Evidence type", text: $evidenceType, axis: .vertical).lineLimit(2...4)
            }
            TextField("Methodological context", text: $methodologicalContext, axis: .vertical).lineLimit(2...5)
            TextField("Study context", text: $studyContext, axis: .vertical).lineLimit(2...5)
            TextField("Related constructs, comma separated", text: $constructs)
            TextField("Your notes or qualification", text: $userNotes, axis: .vertical).lineLimit(2...5)
            Picker("Verification", selection: $verification) {
                ForEach(VerificationState.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save Claim") {
                    model.createClaimFromSelection(
                        item: item, claimText: claimText, category: category, page: page, quote: passage,
                        authorTerminology: authorTerminology, methodologicalContext: methodologicalContext,
                        evidenceType: evidenceType,
                        relatedConstructs: constructs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                        studyContext: studyContext, verification: verification, userNotes: userNotes
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(claimText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 760)
    }
}

private struct PassageEvidenceSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let item: LiteratureItem
    let passage: String
    let page: Int?
    let selectionRegions: [PDFSelectionRegion]
    @State private var argumentID: UUID?
    @State private var relation: EvidenceRelation = .supports
    @State private var summary = ""
    @State private var verification: VerificationState = .unverified

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Link Source Passage").font(.title2.weight(.semibold))
            Text(item.title).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            Picker("Argument", selection: $argumentID) {
                Text("Choose an argument").tag(UUID?.none)
                ForEach(model.arguments) { argument in Text(argument.proposition).tag(UUID?.some(argument.id)) }
            }
            Picker("Relationship", selection: $relation) {
                ForEach(EvidenceRelation.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            TextField("Explain how this passage bears on the proposition", text: $summary, axis: .vertical)
                .lineLimit(2...5)
            Picker("Verification", selection: $verification) {
                ForEach(VerificationState.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            GroupBox(page.map { "Exact selection — page \($0)" } ?? "Exact selection") {
                ScrollView {
                    Text(passage).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                .frame(maxHeight: 150)
                .padding(.vertical, 4)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Link Evidence") {
                    guard let argumentID else { return }
                    model.saveEvidence(
                        argumentID: argumentID,
                        literatureID: item.id,
                        relation: relation,
                        summary: summary,
                        page: page,
                        quote: passage,
                        verification: verification,
                        selectionRegions: selectionRegions,
                        selectionDocumentHash: item.pdfContentHash
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(argumentID == nil || summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 680, height: 550)
        .onAppear { argumentID = model.arguments.first?.id }
    }
}
