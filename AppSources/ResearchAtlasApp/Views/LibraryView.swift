import ResearchAtlasCore
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var authorQuery = ""
    @State private var selectedYear = 0
    @State private var selectedTag = ""
    @State private var selectedPDFStatus = ""
    @State private var selectedNoteStatus = ""
    @State private var showsAdditionalFilters = false

    private var availableYears: [Int] {
        Array(Set(model.literature.compactMap(\.year))).sorted(by: >)
    }

    private var availableTags: [String] {
        Array(Set(model.literature.flatMap(\.tags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var additionalFilterCount: Int {
        [authorQuery, selectedTag, selectedPDFStatus, selectedNoteStatus]
            .filter { !$0.isEmpty }.count + (selectedYear == 0 ? 0 : 1)
    }

    private var filtered: [LiteratureItem] {
        model.literature.filter {
            (authorQuery.isEmpty || $0.authors.localizedCaseInsensitiveContains(authorQuery))
                && (selectedYear == 0 || $0.year == selectedYear)
                && (selectedTag.isEmpty || $0.tags.contains(selectedTag))
                && (selectedPDFStatus.isEmpty || model.pdfFileAvailability(for: $0).rawValue == selectedPDFStatus)
                && (selectedNoteStatus.isEmpty || hasMatchingNoteStatus($0.id))
                && (query.isEmpty
                    || $0.title.localizedCaseInsensitiveContains(query)
                    || $0.authors.localizedCaseInsensitiveContains(query)
                    || $0.abstract.localizedCaseInsensitiveContains(query)
                    || ($0.doi?.localizedCaseInsensitiveContains(query) ?? false))
        }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    DisclosureGroup(isExpanded: $showsAdditionalFilters) {
                        VStack(spacing: 7) {
                            TextField("Author contains", text: $authorQuery)
                            Picker("Year", selection: $selectedYear) {
                                Text("Any year").tag(0)
                                ForEach(availableYears, id: \.self) { Text(String($0)).tag($0) }
                            }
                            Picker("Topic / tag", selection: $selectedTag) {
                                Text("Any topic or tag").tag("")
                                ForEach(availableTags, id: \.self) { Text($0).tag($0) }
                            }
                            Picker("PDF status", selection: $selectedPDFStatus) {
                                Text("Any PDF status").tag("")
                                ForEach([PDFFileAvailability.available, .notLinked, .missing, .changed], id: \.self) {
                                    Text($0.rawValue).tag($0.rawValue)
                                }
                            }
                            Picker("Obsidian notes", selection: $selectedNoteStatus) {
                                Text("Any note status").tag("")
                                Text("Has confirmed note").tag("linked")
                                Text("Has suggestion").tag("suggested")
                                Text("No visible note link").tag("none")
                            }
                            if additionalFilterCount > 0 {
                                Button("Clear additional filters", systemImage: "xmark.circle") { clearAdditionalFilters() }
                                    .buttonStyle(.link)
                            }
                        }
                        .padding(.top, 7)
                    } label: {
                        HStack {
                            Label("More filters", systemImage: "line.3.horizontal.decrease")
                            Spacer()
                            if additionalFilterCount > 0 {
                                Text(additionalFilterCount.formatted())
                                    .font(.caption2.weight(.bold)).foregroundStyle(.white)
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Color.indigo, in: Capsule())
                            }
                        }
                    }
                }
                .labelsHidden()
                .padding(10)

                Divider()

                List(filtered, selection: $model.selectedLiteratureID) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).font(.headline).lineLimit(2)
                        HStack(spacing: 6) {
                            Text(item.authors.isEmpty ? "Unknown author" : item.authors).lineLimit(1)
                            if let year = item.year { Text("· \(year)") }
                            Spacer()
                            let pdfAvailability = model.pdfFileAvailability(for: item)
                            Image(systemName: pdfAvailability == .available ? "doc.fill" : (pdfAvailability == .notLinked ? "doc.badge.ellipsis" : "doc.badge.exclamationmark"))
                                .foregroundStyle(pdfAvailability == .available ? Color.indigo : (pdfAvailability == .missing ? Color.red : (pdfAvailability == .changed ? Color.orange : Color.secondary)))
                                .help(pdfAvailability.rawValue)
                            if item.sourceAvailability != .available {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .help(item.sourceAvailability.rawValue)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .tag(item.id)
                }
                .overlay {
                    if filtered.isEmpty {
                        ContentUnavailableView("No matching papers", systemImage: "line.3.horizontal.decrease.circle", description: Text("Choose a research folder or change the search filters."))
                    }
                }
            }
            .searchable(text: $query, prompt: "Title, author, abstract, DOI")
            .onChange(of: additionalFilterCount) { selectFirstVisiblePaper() }
            .frame(minWidth: 320, idealWidth: 390)

            if let item = model.selectedLiterature {
                PaperDetailView(item: item)
                    .frame(minWidth: 430)
            } else {
                ContentUnavailableView("No paper selected", systemImage: "books.vertical", description: Text("Select a paper or add a local PDF."))
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { model.chooseAndAddPDF() } label: { Label("Add PDF", systemImage: "plus") }
                Button { model.refreshLocalResearchFolder() } label: { Label("Refresh Folder", systemImage: "arrow.triangle.2.circlepath") }
                    .disabled(model.isBusy || model.localResearchFolderPath == nil)
            }
        }
        .sheet(item: Binding(
            get: { model.pendingPDFRelink },
            set: { value in if value == nil { model.cancelPDFRelink() } }
        )) { preview in
            PDFRelinkPreviewView(preview: preview)
                .environmentObject(model)
                .interactiveDismissDisabled(model.isBusy)
        }
    }

    private func selectFirstVisiblePaper() {
        if let selected = model.selectedLiteratureID, filtered.contains(where: { $0.id == selected }) { return }
        model.selectedLiteratureID = filtered.first?.id
    }

    private func hasMatchingNoteStatus(_ literatureID: UUID) -> Bool {
        let links = model.noteAssociations(for: literatureID).map(\.link)
        switch selectedNoteStatus {
        case "linked": return links.contains { $0.state == .confirmed }
        case "suggested": return links.contains { $0.state == .suggested }
        case "none": return links.isEmpty
        default: return true
        }
    }

    private func clearAdditionalFilters() {
        authorQuery = ""
        selectedYear = 0
        selectedTag = ""
        selectedPDFStatus = ""
        selectedNoteStatus = ""
    }
}

private struct PaperDetailView: View {
    @EnvironmentObject private var model: AppModel
    let item: LiteratureItem

    private var noteAssociations: [(link: PaperNoteLink, note: ObsidianNote)] {
        model.noteAssociations(for: item.id)
    }

    private var pdfAvailability: PDFFileAvailability {
        model.pdfFileAvailability(for: item)
    }

    private var manuallyLinkableNotes: [ObsidianNote] {
        let confirmedNoteIDs = Set(noteAssociations.filter { $0.link.state == .confirmed }.map { $0.note.id })
        return model.notes.filter { !confirmedNoteIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(item.title).font(.largeTitle.weight(.semibold)).textSelection(.enabled)
                    Text(item.authors.isEmpty ? "Unknown author" : item.authors)
                        .font(.title3).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack {
                        Text(item.year.map(String.init) ?? "Year unavailable")
                        Text("·")
                        Text(item.itemType.capitalized)
                        Text("·")
                        Text("Local PDF")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                HStack {
                    if pdfAvailability == .available {
                        Button("Read PDF") { model.selectedSection = .reading }
                            .buttonStyle(.borderedProminent)
                    }
                    Button(item.pdfPath == nil ? "Attach PDF…" : (pdfAvailability == .missing ? "Locate PDF…" : (pdfAvailability == .changed ? "Review Changed PDF…" : "Change PDF…"))) {
                        if pdfAvailability == .changed {
                            model.reviewChangedPDF(for: item)
                        } else {
                            model.choosePDFLocation(for: item)
                        }
                    }
                    .disabled(model.isBusy)
                    if item.externalURL != nil {
                        Button("Open Source URL", systemImage: "arrow.up.forward.app") {
                            model.openExternal(item)
                        }
                    }
                }

                Divider()
                if let doi = item.doi {
                    LabeledContent("DOI") { Text(doi).textSelection(.enabled) }
                }
                if let citationKey = item.citationKey {
                    LabeledContent("Citation key") { Text(citationKey).textSelection(.enabled) }
                }
                if !item.tags.isEmpty {
                    LabeledContent("Tags") { Text(item.tags.joined(separator: ", ")).textSelection(.enabled) }
                }
                LabeledContent("Local PDF") {
                    VStack(alignment: .trailing, spacing: 3) {
                        Label(
                            pdfAvailability.rawValue,
                            systemImage: pdfAvailability == .available ? "checkmark.circle.fill" : (pdfAvailability == .notLinked ? "minus.circle" : "exclamationmark.triangle.fill")
                        )
                        .foregroundStyle(pdfAvailability == .available ? Color.green : (pdfAvailability == .missing ? Color.red : (pdfAvailability == .changed ? Color.orange : Color.secondary)))
                        if let path = item.pdfPath {
                            Text(path).font(.caption).textSelection(.enabled).lineLimit(2)
                        }
                    }
                }
                if let hash = item.pdfContentHash {
                    LabeledContent("PDF fingerprint") {
                        Text(String(hash.prefix(16)) + "…")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                if let verified = item.pdfLastVerifiedAt {
                    LabeledContent("Verified") {
                        Text(verified.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Abstract").font(.headline)
                    Text(item.abstract.isEmpty ? "No abstract is available for this item." : item.abstract)
                        .foregroundStyle(item.abstract.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Related Obsidian notes").font(.headline)
                        Spacer()
                        if !noteAssociations.isEmpty { Text(noteAssociations.count.formatted()).font(.caption).foregroundStyle(.secondary) }
                        Menu("Link Note…") {
                            if manuallyLinkableNotes.isEmpty {
                                Text(model.notes.isEmpty ? "No indexed notes" : "All notes are linked")
                            } else {
                                ForEach(manuallyLinkableNotes) { note in
                                    Button(note.title) { model.linkNoteManually(note, to: item.id) }
                                }
                            }
                        }
                        .disabled(model.notes.isEmpty)
                    }
                    if noteAssociations.isEmpty {
                        Text("No reviewed or suggested note links. You can link an indexed note manually; optional title suggestions are controlled in Integrations.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(noteAssociations, id: \.link.id) { association in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(association.note.title).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(association.link.state.rawValue)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(association.link.state == .confirmed ? .green : .secondary)
                                }
                                Text("Matched by \(association.link.method.rawValue.lowercased()): \(association.link.matchedIdentifier)")
                                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                if association.link.method == .title && association.link.state == .suggested {
                                    Label("Lower-confidence title match — review before relying on it", systemImage: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                HStack {
                                    Button("Open in Obsidian") { model.openObsidianNote(association.note) }
                                    Spacer()
                                    if association.link.state != .confirmed {
                                        Button("Confirm") { model.reviewNoteLink(association.link, as: .confirmed) }
                                    }
                                    if association.link.state != .rejected {
                                        Button("Reject", role: .destructive) { model.reviewNoteLink(association.link, as: .rejected) }
                                    }
                                    Button("Remove", role: .destructive) { model.deleteNoteLink(association.link) }
                                }
                                .controlSize(.small)
                            }
                            .padding(12)
                            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }
}

private struct PDFRelinkPreviewView: View {
    @EnvironmentObject private var model: AppModel
    let preview: PDFRelinkPreview

    private var matchColor: Color {
        switch preview.match {
        case .exact: .green
        case .different: .red
        case .sizeOnly, .unverified: .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Review PDF Link").font(.title2.weight(.semibold))
            Text(preview.paperTitle).font(.headline).lineLimit(2)
            Label(preview.match.rawValue, systemImage: preview.match == .exact ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(matchColor)

            if preview.match == .different {
                Text("This file does not match the recorded fingerprint or size. Continuing intentionally replaces the paper's PDF link and its derived page index; the paper, arguments, and evidence links keep their identities.")
                    .font(.callout).foregroundStyle(.red)
            } else if preview.match != .exact {
                Text("Research Atlas has no earlier content fingerprint that can prove this is the same PDF. Review the paths before continuing.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    Text("Previous").foregroundStyle(.secondary)
                    Text(preview.previousPath ?? "No PDF linked").lineLimit(2).textSelection(.enabled)
                }
                GridRow {
                    Text("Selected").foregroundStyle(.secondary)
                    Text(preview.candidateURL.path).lineLimit(2).textSelection(.enabled)
                }
                GridRow {
                    Text("Size").foregroundStyle(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: preview.fingerprint.byteCount, countStyle: .file))
                }
                GridRow {
                    Text("Pages").foregroundStyle(.secondary)
                    Text(preview.indexResult.pages.count.formatted())
                }
                GridRow {
                    Text("SHA-256").foregroundStyle(.secondary)
                    Text(preview.fingerprint.sha256).font(.caption.monospaced()).lineLimit(1).textSelection(.enabled)
                }
            }
            .padding(14)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Button("Cancel") { model.cancelPDFRelink() }.keyboardShortcut(.cancelAction)
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
                Button(role: preview.match == .different ? .destructive : nil) {
                    model.confirmPDFRelink(preview)
                } label: {
                    Text(preview.match == .different ? "Use Different PDF" : "Use This PDF")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isBusy)
            }
        }
        .padding(24)
        .frame(width: 640)
    }
}
