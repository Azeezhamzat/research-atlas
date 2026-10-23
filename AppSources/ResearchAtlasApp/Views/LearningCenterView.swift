import AppKit
import SwiftUI

private struct TutorialStep: Hashable {
    let title: String
    let detail: String
}

private struct LearningTopic: Identifiable, Hashable {
    let id: String
    let category: String
    let title: String
    let summary: String
    let icon: String
    let destination: AppSection?
    let imageName: String?
    let prerequisites: [String]
    let steps: [TutorialStep]
    let verify: [String]
    let cautions: [String]
    let shortcuts: [String]

    init(
        id: String, category: String, title: String, summary: String, icon: String,
        destination: AppSection? = nil, imageName: String? = nil,
        prerequisites: [String] = [], steps: [TutorialStep], verify: [String],
        cautions: [String] = [], shortcuts: [String] = []
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.summary = summary
        self.icon = icon
        self.destination = destination
        self.imageName = imageName
        self.prerequisites = prerequisites
        self.steps = steps
        self.verify = verify
        self.cautions = cautions
        self.shortcuts = shortcuts
    }
}

struct LearningCenterView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTopicID = "start"
    @State private var selectedCategory = "Start here"
    @State private var query = ""
    @AppStorage("learningCenterCompletedTopics") private var completedTopics = ""

    private var completed: Set<String> {
        Set(completedTopics.split(separator: ",").map(String.init))
    }

    private var filteredTopics: [LearningTopic] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return LearningCatalog.topics }
        return LearningCatalog.topics.filter { topic in
            topic.title.localizedCaseInsensitiveContains(trimmed)
                || topic.summary.localizedCaseInsensitiveContains(trimmed)
                || topic.steps.contains { $0.title.localizedCaseInsensitiveContains(trimmed) || $0.detail.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    private var displayedTopics: [LearningTopic] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return filteredTopics }
        return LearningCatalog.topics.filter { $0.category == selectedCategory }
    }

    private var selectedTopic: LearningTopic {
        LearningCatalog.topics.first { $0.id == selectedTopicID } ?? LearningCatalog.topics[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Learn Research Atlas").font(.title2.weight(.semibold))
                    ProgressView(value: Double(completed.count), total: Double(LearningCatalog.topics.count))
                        .frame(width: 240)
                    Text("\(completed.count) of \(LearningCatalog.topics.count) lessons completed")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open full illustrated guide", systemImage: "book.pages") {
                    model.openUserGuide()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            Divider()

            HStack(spacing: 12) {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(LearningCatalog.categories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 230)

                Picker("Lesson", selection: $selectedTopicID) {
                    ForEach(displayedTopics) { topic in
                        Label(topic.title, systemImage: completed.contains(topic.id) ? "checkmark.circle.fill" : topic.icon)
                            .tag(topic.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 310, maxWidth: 430)
                .disabled(displayedTopics.isEmpty)

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find a feature or task", text: $query)
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                .frame(minWidth: 220, maxWidth: 340)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            Divider()

            if displayedTopics.isEmpty {
                ContentUnavailableView("No lesson found", systemImage: "magnifyingglass", description: Text("Try a feature name such as folder, evidence, export, or AI."))
            } else {
                TopicDetailView(
                    topic: selectedTopic,
                    isCompleted: completed.contains(selectedTopic.id),
                    openWorkspace: { destination in model.selectedSection = destination },
                    toggleCompleted: { toggleCompleted(selectedTopic.id) }
                )
                .id(selectedTopic.id)
                .frame(minWidth: 620, maxWidth: .infinity)
            }
        }
        .onChange(of: selectedCategory) { _, category in
            guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  selectedTopic.category != category,
                  let first = LearningCatalog.topics.first(where: { $0.category == category }) else { return }
            selectedTopicID = first.id
        }
        .onChange(of: selectedTopicID) { _, topicID in
            guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let topic = LearningCatalog.topics.first(where: { $0.id == topicID }) else { return }
            selectedCategory = topic.category
        }
        .onChange(of: query) { _, _ in
            guard let first = displayedTopics.first,
                  !displayedTopics.contains(where: { $0.id == selectedTopicID }) else { return }
            selectedTopicID = first.id
        }
    }

    private func toggleCompleted(_ id: String) {
        var updated = completed
        if updated.contains(id) { updated.remove(id) } else { updated.insert(id) }
        completedTopics = updated.sorted().joined(separator: ",")
    }
}

private struct TopicDetailView: View {
    let topic: LearningTopic
    let isCompleted: Bool
    let openWorkspace: (AppSection) -> Void
    let toggleCompleted: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let imageName = topic.imageName {
                    TutorialAssetImage(name: imageName)
                        .frame(maxWidth: .infinity)
                        .frame(height: topic.id == "start" ? 285 : 245)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.12)))
                }

                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: topic.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(.indigo)
                        .frame(width: 52, height: 52)
                        .background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(topic.category.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.indigo)
                        Text(topic.title).font(.largeTitle.weight(.semibold))
                        Text(topic.summary)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                HStack {
                    if let destination = topic.destination {
                        Button("Open \(destination.rawValue)", systemImage: "arrow.right.circle.fill") { openWorkspace(destination) }
                            .buttonStyle(.borderedProminent)
                    }
                    Button(isCompleted ? "Mark Incomplete" : "Mark Lesson Complete", systemImage: isCompleted ? "checkmark.circle.fill" : "circle") {
                        toggleCompleted()
                    }
                    Spacer()
                }

                if !topic.prerequisites.isEmpty {
                    guidePanel(title: "Before you begin", icon: "checklist", tint: .blue, rows: topic.prerequisites)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Step by step").font(.title2.weight(.semibold))
                    ForEach(topic.steps.indices, id: \.self) { index in
                        let step = topic.steps[index]
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(index + 1)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.indigo, in: Circle())
                            VStack(alignment: .leading, spacing: 5) {
                                Text(step.title).font(.headline)
                                Text(step.detail)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1)))
                    }
                }

                guidePanel(title: "How to know it worked", icon: "checkmark.seal", tint: .green, rows: topic.verify)
                if !topic.cautions.isEmpty {
                    guidePanel(title: "Important boundaries", icon: "exclamationmark.shield", tint: .orange, rows: topic.cautions)
                }
                if !topic.shortcuts.isEmpty {
                    guidePanel(title: "Useful shortcuts", icon: "keyboard", tint: .purple, rows: topic.shortcuts)
                }

                Label(
                    "Source records, researcher interpretations, and model suggestions remain distinct throughout Research Atlas.",
                    systemImage: "checkmark.shield.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func guidePanel(title: String, icon: String, tint: Color, rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(tint)
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                ForEach(rows, id: \.self) { row in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(tint).padding(.top, 7)
                        Text(row).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.22)))
    }
}

private struct TutorialAssetImage: View {
    let name: String

    var body: some View {
        Group {
            if let image = TutorialImageLoader.load(name: name) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [.indigo.opacity(0.28), .mint.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Label("Tutorial image unavailable", systemImage: "photo").foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

@MainActor
private enum TutorialImageLoader {
    private static let cache = NSCache<NSString, NSImage>()

    static func load(name: String) -> NSImage? {
        let key = name as NSString
        if let cached = cache.object(forKey: key) { return cached }

        if let resourceURL = Bundle.main.resourceURL {
            let packaged = resourceURL.appendingPathComponent("Tutorial", isDirectory: true).appendingPathComponent(name)
            if let image = NSImage(contentsOf: packaged) {
                cache.setObject(image, forKey: key)
                return image
            }
        }
        #if DEBUG
        // SwiftPM development runs do not copy the standalone app resources. Keep this source-tree
        // fallback out of release binaries so a developer's absolute checkout path is never shipped.
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard let image = NSImage(contentsOf: sourceRoot.appendingPathComponent("Support/Tutorial", isDirectory: true).appendingPathComponent(name)) else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
        #else
        return nil
        #endif
    }
}

private enum LearningCatalog {
    static let categories = ["Start here", "Sources and reading", "Research reasoning", "AI-assisted work", "Operations and safety"]

    static let topics: [LearningTopic] = [
        LearningTopic(
            id: "start", category: "Start here", title: "The complete first-hour workflow",
            summary: "Move from an empty workspace to a traceable question, passage, argument, and backup.",
            icon: "map.fill", destination: .home, imageName: "learning-center-hero-public.png",
            prerequisites: ["macOS 14 or later.", "Choose the folder where your research PDFs already live.", "Keep your PDFs and Obsidian vault where they already live; Research Atlas indexes them without reorganising them."],
            steps: [
                .init(title: "Connect sources", detail: "Open Integrations. Choose your local research folder, then optionally choose your Obsidian vault. Both sources are read-only."),
                .init(title: "Confirm files and availability", detail: "Open Literature Library, select an indexed paper, and confirm its local path, fingerprint, page count, and availability."),
                .init(title: "Read and capture evidence", detail: "Open an available PDF in Reading Desk, select exact text, and save it to an argument. Research Atlas records the paper, one-based page, quotation, selection geometry where available, and document fingerprint."),
                .init(title: "Create the intellectual structure", detail: "Create a project and research question, then build an argument with a qualified proposition. Link supporting, challenging, or contextual evidence rather than storing an unstructured summary."),
                .init(title: "Retrieve before using AI", detail: "Save a query in Evidence Explorer and inspect every paper passage and researcher-note excerpt. Use the AI card beside a question, argument, retrieval set, or writing section to carry that context into the grounded workflow. Only current snapshots can be sent to an optional provider."),
                .init(title: "Review, do not merely generate", detail: "The contextual AI card opens Research Assistant, Bias Auditor, or Argument Room with the relevant task prefilled. Contradiction Detective and Collective Intelligence Lab provide their own guarded entry points. Record a human review decision on every model analysis you intend to use."),
                .init(title: "Back up", detail: "In Integrations, create a consistent SQLite backup and a portable export. The backup preserves the complete workspace; Markdown, JSON, and CSV keep your work accessible outside the app.")
            ],
            verify: ["Research Home shows your imported paper/note counts.", "A selected paper displays its local path and content fingerprint.", "An evidence record opens back to its exact PDF page.", "Your backup opens successfully in the restore preview without changing the live database."],
            cautions: ["Research Atlas never proves that an absence in your library is a research gap.", "Obsidian notes are researcher context, not published evidence.", "AI is optional, disabled by default, and never required for the core workflow."],
            shortcuts: ["⌘K or ⌘F — Global Search", "⇧⌘O — Add local PDF", "⌘? — Learning Center"]
        ),
        LearningTopic(
            id: "mental-model", category: "Start here", title: "Understand the evidence model",
            summary: "Learn what counts as a source, interpretation, suggestion, and verified relationship.",
            icon: "checkmark.shield", destination: .evidence,
            steps: [
                .init(title: "Direct source information", detail: "Bibliographic metadata, PDF text, exact quotations, and page locations remain source records. They are not silently rewritten by analysis tools."),
                .init(title: "Researcher-authored material", detail: "Questions, arguments, ideas, notes, qualifications, comparison fields, and review decisions represent your intellectual work."),
                .init(title: "Generated candidates", detail: "Model answers, extracted claims, concerns, contradiction assessments, and deliberation messages are visibly model-generated and preserve provider, model, prompt, citations, and review state."),
                .init(title: "Verification is explicit", detail: "Unverified, verified, rejected, stale, accepted, dismissed, and superseded states are stored rather than inferred from appearance."),
                .init(title: "Freshness is dynamic", detail: "Saved quotations survive for audit, but the app marks them stale when an indexed passage, document fingerprint, or note excerpt no longer matches the current source.")
            ],
            verify: ["You can identify who authored every analytical record.", "Every evidence-bearing item exposes a source or states that none is linked.", "Stale snapshots remain inspectable but are excluded from new grounded requests."],
            cautions: ["A relationship can be useful while still unverified.", "Multiple model roles are simulations from one configured model, not independent experts."]
        ),
        LearningTopic(
            id: "home", category: "Start here", title: "Research Home",
            summary: "Use the active project as a command centre for resuming exact records and prioritising integrity work.",
            icon: "house", destination: .home,
            steps: [
                .init(title: "Choose the active project", detail: "Use the project switcher above the grouped sidebar. Home, questions, arguments, ideas, and writing now follow that context."),
                .init(title: "Read the project snapshot", detail: "Linked sources, active questions, arguments, ideas, and writing workspaces are project-scoped navigation controls, not performance scores."),
                .init(title: "Follow the research flow", detail: "Move from sources through questions and evidence to arguments and writing without losing the current project context."),
                .init(title: "Resume the exact record", detail: "Continue cards open the selected paper, question, argument, idea, or writing workspace directly rather than stopping at a module list."),
                .init(title: "Resolve integrity work", detail: "Use Needs attention to find unverified records, stale citations, PDF identity problems, and failed indexing jobs."),
                .init(title: "Review recorded history", detail: "Recent activity shows only changes Research Atlas actually observed; it does not invent reasons for intellectual change.")
            ],
            verify: ["Switching the active project updates the project-scoped dashboard.", "Continue cards open an exact selected record.", "When no issues exist, the dashboard says so instead of inventing recommendations."]
        ),
        LearningTopic(
            id: "local-folder", category: "Sources and reading", title: "Connect a local research folder",
            summary: "Index a folder of PDFs recursively while keeping every source file exactly where it is.",
            icon: "folder.fill", destination: .settings, imageName: "local-folder-library-public.png",
            prerequisites: ["Know the folder containing your research PDFs.", "Grant folder access in the native macOS picker.", "PDFs may be organised in any nested folder structure."],
            steps: [
                .init(title: "Choose the folder", detail: "In Integrations, click Choose Folder. Research Atlas stores a security-scoped bookmark so it can return to the same location after relaunch."),
                .init(title: "Let discovery complete", detail: "Research Atlas scans nested folders for readable .pdf files, skips hidden files, symbolic links, packages, and non-PDF files, and reports progress without editing the source tree."),
                .init(title: "Understand duplicate handling", detail: "Each PDF receives a SHA-256 content fingerprint. An unchanged path is skipped; the same bytes at another readable path do not create a duplicate paper."),
                .init(title: "Inspect the imported paper", detail: "Open Literature Library to review the title, local path, availability, fingerprint, verification time, and machine-readable page text."),
                .init(title: "Refresh later", detail: "Use Refresh Folder after adding, moving, or changing PDFs. New and changed files are indexed; unchanged and duplicate files are skipped."),
                .init(title: "Handle scanned PDFs", detail: "If PDFKit finds little or no machine-readable text, Research Atlas retains the paper and warns that OCR has not been performed.")
            ],
            verify: ["Integrations shows the selected path and a completed discovery summary.", "A second refresh reports unchanged PDFs without creating duplicates.", "A selected paper opens from its original local path.", "Global Search finds a phrase from a machine-readable PDF."],
            cautions: ["Research Atlas never edits, moves, renames, or deletes files in the folder.", "Folder access does not imply comprehensive scholarly coverage.", "A changed PDF fingerprint requires source review before relying on earlier selection geometry."],
            shortcuts: ["Use the Literature toolbar's Refresh Folder button for a repeat scan.", "⇧⌘O adds one PDF without changing the saved folder."]
        ),
        LearningTopic(
            id: "obsidian", category: "Sources and reading", title: "Connect an Obsidian vault safely",
            summary: "Discover notes without rewriting the vault and review every paper-note association.",
            icon: "note.text", destination: .settings,
            prerequisites: ["Know the folder containing your Obsidian vault.", "Grant folder access in the native picker when macOS asks."],
            steps: [
                .init(title: "Choose the vault", detail: "Integrations → Choose vault stores a security-scoped bookmark and recursively discovers Markdown files."),
                .init(title: "Understand parsing", detail: "Research Atlas indexes headings, YAML frontmatter, tags, wikilinks, citation keys, DOI strings, and note content."),
                .init(title: "Review explicit matches", detail: "DOI and citation-key matches appear as suggestions. Confirm, reject, or remove them in the paper detail."),
                .init(title: "Use title matching only when needed", detail: "Optional exact normalized-title suggestions are off by default and remain clearly lower confidence."),
                .init(title: "Open the original note", detail: "Open in Obsidian routes to the note's original path. Research Atlas does not edit, move, rename, or delete it."),
                .init(title: "Use notes in retrieval", detail: "Unfiltered retrieval queries can snapshot exact matching excerpts. They use N labels and remain researcher context rather than published evidence.")
            ],
            verify: ["Research Home's note count increases after indexing.", "Global Search finds text inside the note.", "A confirmed note link survives a later rescan."],
            cautions: ["Publication-year filters intentionally exclude notes.", "A title suggestion is not evidence that a note concerns a paper until you review it."]
        ),
        LearningTopic(
            id: "library", category: "Sources and reading", title: "Literature Library",
            summary: "Filter sources, inspect provenance, diagnose PDFs, and manage paper-note links.",
            icon: "books.vertical", destination: .library,
            steps: [
                .init(title: "Filter before searching", detail: "Expand More filters for author, year, topic/tag, PDF status, or Obsidian-link status. Search titles, authors, abstracts, or DOIs within that visible set."),
                .init(title: "Read status indicators", detail: "PDF icons distinguish available, unlinked, missing, and changed files."),
                .init(title: "Inspect metadata", detail: "Review DOI, citation key, tags, local path, fingerprint, and last verification time."),
                .init(title: "Repair a PDF link", detail: "Locate PDF previews the candidate's path, size, page count, and SHA-256 match before any application-owned link or index is changed."),
                .init(title: "Review related notes", detail: "Link notes manually or review suggestions. Your confirm/reject decisions are retained across rescans.")
            ],
            verify: ["The selected paper remains selected when compatible filters change.", "A repaired PDF opens in Reading Desk and keeps the same paper/evidence IDs.", "Changing or deleting an application note-link never modifies the Obsidian file."],
            cautions: ["A changed PDF fingerprint invalidates stored selection geometry until you review the replacement."]
        ),
        LearningTopic(
            id: "reading", category: "Sources and reading", title: "Reading Desk",
            summary: "Read PDFs, search within them, capture exact passages, and return to cited locations.",
            icon: "doc.richtext", destination: .reading,
            steps: [
                .init(title: "Choose an available paper", detail: "Select a paper with a readable local PDF in Literature Library, then click Read PDF."),
                .init(title: "Navigate and search", detail: "Use PDFKit page navigation, zoom, and in-document find. Page numbers stored by Research Atlas are one-based."),
                .init(title: "Select exact text", detail: "Drag over the smallest passage that supports the point. Avoid clipping qualifications or relying on an entire page when a precise quotation is available."),
                .init(title: "Link evidence or create a claim", detail: "Save the selection to an argument relationship or a structured claim. Add your summary separately from the quotation."),
                .init(title: "Reopen provenance", detail: "Click source links from evidence, claims, retrieval, writing, or AI review to return to the page; geometry is highlighted only when the PDF fingerprint still matches."),
                .init(title: "Handle scanned files", detail: "If little text is extractable, the app warns that OCR was not performed. Attach or inspect the source manually rather than treating missing index text as absent evidence.")
            ],
            verify: ["The saved quotation exactly matches selected PDF text.", "The source opens on the recorded page.", "A changed document produces a warning rather than a false highlight."],
            cautions: ["Research Atlas does not invent page numbers and does not silently substitute OCR text."]
        ),
        LearningTopic(
            id: "questions", category: "Research reasoning", title: "Research Questions",
            summary: "Organise questions and audit the recorded coverage of their linked literature.",
            icon: "questionmark.bubble", destination: .questions, imageName: "question-coverage-audit-public.png",
            steps: [
                .init(title: "Create a project", detail: "Give it a scope rather than merely a topic label. Projects own research questions but do not own source files."),
                .init(title: "Create a question", detail: "Record the question, parent question if any, status, objectives, theoretical interests, definitions, disagreements, hypotheses, and methodological considerations."),
                .init(title: "Associate literature and concepts", detail: "Add papers and concepts because you judged them relevant; keyword overlap alone never creates a substantive relationship."),
                .init(title: "Audit the linked set", detail: "Inspect publication years, topic tags, source availability, recorded designs and frameworks, comparison-field completion, and each paper's profile readiness. Needs-attention notes report missing local records, not scholarly gaps."),
                .init(title: "Complete comparisons at the source", detail: "Open the Comparison Matrix from the audit and record only what the paper supports. Blank fields remain unavailable rather than being guessed."),
                .init(title: "Connect arguments", detail: "Arguments can point back to a question, keeping propositions and evidence inside the question's intellectual context."),
                .init(title: "Revise with a reason", detail: "Every substantive update requires a change note and becomes a dated recorded version.")
            ],
            verify: ["The question workspace shows its associated papers, coverage audit, concepts, and arguments.", "Every coverage count can be traced to a linked paper or recorded comparison field.", "Recorded revisions preserve both text and the reason for change."],
            cautions: ["Coverage describes only the linked set and its recorded metadata, not the entire scholarly literature.", "A missing field is a documentation prompt, not evidence that a method, population, framework, or finding is absent from research."]
        ),
        LearningTopic(
            id: "evidence", category: "Research reasoning", title: "Evidence Explorer",
            summary: "Create retrieval sets, comparison matrices, and structured claims without collapsing their provenance.",
            icon: "tablecells", destination: .evidence,
            steps: [
                .init(title: "Save a retrieval set", detail: "Name a full-text query and optionally apply a year range. The result is an immutable-at-capture snapshot, including an empty result when nothing matched."),
                .init(title: "Inspect source classes", detail: "Published-source passages show paper/page provenance. Researcher-note excerpts are displayed in a separate section and never described as published evidence."),
                .init(title: "Read freshness", detail: "Current, source missing, passage changed, and document fingerprint changed states are evaluated against the current local index."),
                .init(title: "Build comparisons", detail: "Select papers and manually record research question, framework, design, sample, variables, definitions, findings, limitations, and interpretive notes. Blank means unavailable."),
                .init(title: "Create or revise claims", detail: "Claims preserve category, terminology, methods, evidence type, context, source passage, extraction origin, model/prompt where applicable, verification, and revision history."),
                .init(title: "Delete safely", detail: "Deleting an application-owned claim or retrieval set does not alter PDFs, the PDF index, or Obsidian notes.")
            ],
            verify: ["Every retrieved item exposes the exact captured text and a freshness state.", "Comparison cells remain blank/unavailable when you did not record a value.", "AI candidate claims remain unverified until you review them."],
            cautions: ["Retrieval relevance is an inspectable FTS ranking, not proof of conceptual equivalence."]
        ),
        LearningTopic(
            id: "arguments", category: "Research reasoning", title: "Argument Workspace",
            summary: "Build qualified propositions from typed, reviewable evidence relationships.",
            icon: "point.3.connected.trianglepath.dotted", destination: .arguments,
            steps: [
                .init(title: "Write a proposition", detail: "Make the claim precise enough to challenge. Add a qualification for boundary conditions rather than hiding them in notes."),
                .init(title: "Link a research question", detail: "Attach the argument to the question it helps answer; the argument remains independently versioned."),
                .init(title: "Add typed evidence", detail: "Use Supports, Challenges, Qualifies, Contradicts, Extends, Depends on, Context, Related Construct, Alternative Explanation, or Further Investigation."),
                .init(title: "Separate quotation and summary", detail: "The exact passage remains source text; your description of why it matters is an application-owned interpretation."),
                .init(title: "Verify relationships", detail: "Mark an evidence relationship verified only after opening the source and checking the quotation, context, and relevance."),
                .init(title: "Revise transparently", detail: "Edits require a change note. Previous proposition, qualification, and status remain in recorded history.")
            ],
            verify: ["Each evidence card shows relation, source, page where known, quotation, and verification state.", "The recorded history contains the earlier argument state and explicit reason."],
            cautions: ["A paper can support one part of a proposition while qualifying or challenging another."]
        ),
        LearningTopic(
            id: "atlas", category: "Research reasoning", title: "Knowledge Atlas",
            summary: "Explore a bounded, provenance-aware graph and focus on meaningful neighbourhoods.",
            icon: "circle.hexagongrid", destination: .atlas,
            steps: [
                .init(title: "Start with connected evidence", detail: "Connected is the default map scope. It excludes isolated records so the graph begins with relationships you can actually interpret."),
                .init(title: "Discover unconnected material", detail: "Switch to All records for labelled type clusters, or search while Connected is active to surface a specific isolated record."),
                .init(title: "Filter before interpreting", detail: "Filter node type, relationship type, origin, verification state, or text. Use the overview panel to monitor connection coverage."),
                .init(title: "Select and focus", detail: "Node size reflects visible relationship degree. Select a node to emphasise its links, then use Neighborhood to remove unrelated context."),
                .init(title: "Open evidence", detail: "Use the inspector to navigate to the underlying paper, question, argument, note, claim, or idea."),
                .init(title: "Create a relationship", detail: "Choose source and target nodes, a typed relation, verification, and either linked evidence, an indexed passage, or a written rationale.")
            ],
            verify: ["Every visible edge has a stored type, origin, and verification state.", "Self-links and links to missing nodes are rejected."],
            cautions: ["The graph never creates a substantive relationship merely because two texts share keywords."]
        ),
        LearningTopic(
            id: "ideas", category: "Research reasoning", title: "Idea Laboratory",
            summary: "Develop observations into testable propositions while preserving assumptions and alternatives.",
            icon: "lightbulb.max", destination: .ideas,
            steps: [
                .init(title: "Capture the idea", detail: "Give the idea a title, body, status, assumptions, alternative explanations, evidence needed, and investigation notes."),
                .init(title: "Link its intellectual context", detail: "Attach a project/question and links to papers, passages, notes, concepts, or arguments."),
                .init(title: "Use meaningful statuses", detail: "Progress from initial observation through emerging, investigation, proposition, candidate hypothesis, integration, or rejection/supersession."),
                .init(title: "Challenge locally", detail: "Generate a deterministic checklist about assumptions, constructs, support, challenges, alternatives, change conditions, and empirical testability."),
                .init(title: "Revise with history", detail: "Every saved revision records the previous state and your reason.")
            ],
            verify: ["The idea shows its linked records and current status.", "Challenge prompts identify missing evidence without fabricating literature."],
            cautions: ["A plausible idea is not a finding, and a missing linked source is not proof of novelty."]
        ),
        LearningTopic(
            id: "contradictions", category: "Research reasoning", title: "Contradiction Detective",
            summary: "Compare apparently conflicting findings without erasing differences in context or design.",
            icon: "arrow.left.arrow.right", destination: .contradictions,
            steps: [
                .init(title: "Create a case", detail: "State the apparent conflict and optionally link the research question. Do not classify it before inspecting sources."),
                .init(title: "Add comparison sources", detail: "Record each source's role, finding, contextual difference, exact passage, and verification state."),
                .init(title: "Complete comparison profiles", detail: "Use Evidence Explorer's comparison matrix for framework, design, sample, variables, definitions, findings, and limitations."),
                .init(title: "Run the local review", detail: "Generate context-sensitive prompts about task, sample, measures, manipulation, and operational definitions."),
                .init(title: "Optionally request a model assessment", detail: "Choose a paper-grounded retrieval set, review the transmission, and inspect the result separately. The suggested status never changes the case automatically."),
                .init(title: "Record your resolution", detail: "Choose unresolved, apparent, contextual difference, partially resolved, resolved, or not comparable and write the reasoning.")
            ],
            verify: ["Every comparison source belongs to the correct paper/passage.", "Missing methodological details display as unavailable.", "A model result has its own human review record."],
            cautions: ["Different outcomes are not automatically contradictions."]
        ),
        LearningTopic(
            id: "history", category: "Research reasoning", title: "Intellectual History",
            summary: "Inspect only recorded changes and navigate back to the current entities they concern.",
            icon: "clock.arrow.circlepath", destination: .history,
            steps: [
                .init(title: "Filter event types", detail: "Use the record-type menu to focus on questions, arguments, claims, ideas, contradictions, evidence, or graph relationships."),
                .init(title: "Read event details cautiously", detail: "Events report what Research Atlas observed and any reason you explicitly recorded."),
                .init(title: "Open the current record", detail: "Navigate from an event to the relevant workspace, then inspect version history for recorded earlier states."),
                .init(title: "Compare revisions", detail: "Use question, argument, claim, and idea version cards to examine wording, status, qualification, and change notes over time.")
            ],
            verify: ["Every timeline item has an entity, operation, timestamp, and recorded detail.", "No event claims a causal explanation you did not record."],
            cautions: ["The timeline cannot reconstruct edits made before version tracking or unobserved changes inside external files."]
        ),
        LearningTopic(
            id: "assistant", category: "AI-assisted work", title: "Grounded Research Assistant",
            summary: "Ask bounded questions over approved source snapshots and review every claim and citation.",
            icon: "sparkles", destination: .assistant,
            prerequisites: ["Create and inspect a retrieval set first.", "Configure OpenAI, Anthropic Claude, Google Gemini, Local Research AI, LM Studio Local, or an OpenAI-compatible HTTPS provider. Hosted credentials stay in Research Atlas's application-only macOS Keychain record. Local Research AI can start its bundled engine and needs no key; the selected model must already exist in the local Ollama store.", "Enable hosted transmission or local model requests only if you intend to send the previewed text."],
            steps: [
                .init(title: "Open it where you are working", detail: "Use the Grounded AI card on Research Home, a research question, an argument, a saved retrieval set, or a writing section. It carries the suggested task and current evidence-set choice into Research Assistant. The sidebar remains available when you want to start without page context."),
                .init(title: "Choose a retrieval set", detail: "Only current snapshots within the configured limit are eligible. From a question, argument, contradiction case, or writing section, Research Atlas prefers a set that contains linked papers and shows the exact overlap. An orange warning means the set contains none of the linked papers. Paper passages use S labels; researcher-note excerpts use N labels."),
                .init(title: "Ask a precise question", detail: "Phrase a question that the selected evidence could actually answer. Retrieval is not expanded silently."),
                .init(title: "Inspect the transmission preview", detail: "Review provider, endpoint, model, task, every source label, source class, snapshot count, and request size. Expand Inspect Exact Source Text to read every complete passage and note excerpt included in the request. Cancel sends nothing."),
                .init(title: "Approve one request", detail: "The app reloads the database and compares every approved quotation, fingerprint, note excerpt/modification time, task context, and output limit before sending."),
                .init(title: "Review the result", detail: "Inspect the answer, every citation-bearing claim, current/stale status, provider/model/prompt, token usage where available, and any insufficiency or failure."),
                .init(title: "Record a human decision", detail: "Accept as useful, dismiss, or request revision with notes. Only current paper-backed claims can be converted into unverified literature claim candidates; note-only claims stay in the analysis.")
            ],
            verify: ["Every substantive returned claim cites only labels present in the preview.", "A malformed, uncited, unknown-label, or contradictory insufficient-evidence response is rejected.", "Credentials never appear in the database or exports."],
            cautions: ["N-labelled notes are your context, not published findings.", "Model output remains a suggestion even when every citation is valid."]
        ),
        LearningTopic(
            id: "bias", category: "AI-assisted work", title: "Research Bias Auditor",
            summary: "Generate evidence-linked critical questions without claiming to diagnose psychological bias.",
            icon: "checkmark.shield", destination: .bias,
            steps: [
                .init(title: "Select an argument", detail: "The auditor examines the proposition, qualification, and evidence relationships already recorded."),
                .init(title: "Choose local or model mode", detail: "Local mode runs deterministic rules without transmission. Model mode requires a current paper-passage retrieval set and consent preview."),
                .init(title: "Inspect each concern", detail: "Review problem type, why it may matter, alternative interpretations, investigation questions, evidence references, and uncertainty."),
                .init(title: "Record disposition", detail: "Accept for investigation, dismiss, mark addressed, or leave pending; add review notes."),
                .init(title: "Revisit the argument", detail: "Use accepted concerns to refine qualifications or collect additional evidence rather than treating them as verdicts.")
            ],
            verify: ["Model concerns have source labels and provenance.", "Local concerns are labelled Local system suggestion.", "Your decisions survive reruns."],
            cautions: ["The auditor identifies questions and reasoning risks, not personal or psychological diagnoses."]
        ),
        LearningTopic(
            id: "argument-room", category: "AI-assisted work", title: "Argument Room",
            summary: "Run a transparent, multi-phase critical deliberation while preserving disagreement.",
            icon: "person.3.sequence", destination: .argumentRoom,
            steps: [
                .init(title: "Select an argument", detail: "Start from a proposition and its recorded qualifications/evidence."),
                .init(title: "Choose a local scaffold", detail: "Generate role prompts for your own responses without calling a model."),
                .init(title: "Or prepare model deliberation", detail: "Choose a current paper-grounded retrieval set, inspect the preview, and approve a single request."),
                .init(title: "Inspect all required phases", detail: "Theoretical, Methodological, Evidence, and Alternative Explanation roles each provide initial assessment, cross-examination, and revision, followed by synthesis."),
                .init(title: "Challenge a contribution", detail: "Add researcher responses as separate messages; do not overwrite generated text."),
                .init(title: "Review provenance", detail: "Each model message retains exact citations, uncertainty, sequence, provider/model/prompt, and same-model disclosure.")
            ],
            verify: ["All four critical roles and every phase are present or the response is rejected.", "The synthesis preserves unresolved issues instead of manufacturing consensus."],
            cautions: ["Generated roles are simulations from one model, not independent experts or evidence sources."]
        ),
        LearningTopic(
            id: "collective", category: "AI-assisted work", title: "Collective Intelligence Laboratory",
            summary: "Run one consent-gated, source-grounded simulated role at a time while preserving a reproducible record.",
            icon: "brain.head.profile", destination: .collectiveLab,
            steps: [
                .init(title: "Define the experiment", detail: "Record title, purpose, task instructions, interaction mode, and status. Provider, model, settings, and prompt version are frozen automatically at execution."),
                .init(title: "Add explicit roles", detail: "Give every simulated role a stable label, assignment, information condition, and position."),
                .init(title: "Prepare one model turn", detail: "Choose one role, round, turn kind, and a saved paper-grounded retrieval set. Independent mode hides all prior turns; deliberative modes include the recorded sequence."),
                .init(title: "Approve the transmission", detail: "Inspect provider, endpoint, model, task, exact paper-passage snapshots, and request size. Approval runs exactly one response."),
                .init(title: "Inspect the recorded result", detail: "The lab validates citations, confidence, uncertainty, and evidence sufficiency before saving the exact prompt, response, model provenance, and source snapshots."),
                .init(title: "Record interruption and completion", detail: "Provider failures and invalid outputs create a visible interruption rather than disappearing; human observations remain clearly separate."),
                .init(title: "Export", detail: "Use the portable package to obtain experiment, agent, turn, and citation CSV files plus JSON/Markdown context.")
            ],
            verify: ["Every completed model turn has an exact prompt, one role, a round/sequence, calibrated confidence, uncertainty, and current source snapshots.", "Provider, model, runtime setting, and prompt contract are captured from the actual approved request.", "Failures remain visible as interruptions."],
            cautions: ["Every role is a simulation produced by the same configured model, not an independent expert or evidence source.", "The lab never runs autonomously: each turn requires its own transmission preview and approval."]
        ),
        LearningTopic(
            id: "writing", category: "Research reasoning", title: "Research Writing",
            summary: "Build evidence-linked outlines and run cautious local citation-support checks.",
            icon: "square.and.pencil", destination: .writing,
            steps: [
                .init(title: "Create a document", detail: "Choose purpose, title, project/question context, status, and notes."),
                .init(title: "Build ordered sections", detail: "Add section titles, draft text, position, and notes. Research Atlas complements rather than replaces Obsidian."),
                .init(title: "Link evidence", detail: "Attach a structured claim, argument evidence, literature item, or argument; preserve DOI or citation keys when available."),
                .init(title: "Run local support review", detail: "The checker segments statements and compares each with the closest linked text, flagging causal overstatement, overbreadth, missing qualification, low term overlap, or unverified/stale support."),
                .init(title: "Inspect the closest source", detail: "Open the linked claim, evidence, paper, or argument before deciding whether the warning is relevant."),
                .init(title: "Export Markdown", detail: "Save a portable outline with sections and citation keys. No Obsidian note is overwritten.")
            ],
            verify: ["Every linked source records its target type, ID, rationale, and citation key where available.", "Support reviews remain suggestions with human decisions and notes."],
            cautions: ["Lexical overlap cannot establish definitive citation correctness."]
        ),
        LearningTopic(
            id: "search", category: "Operations and safety", title: "Global Search",
            summary: "Find metadata, PDF pages, notes, reasoning records, and writing from one local index.",
            icon: "magnifyingglass", destination: .search,
            steps: [
                .init(title: "Enter discriminating terms", detail: "Results update as you type across paper titles/authors/abstracts, PDF text, notes, projects/questions, arguments, comparisons, concepts, claims, ideas, contradictions, and writing."),
                .init(title: "Control precision", detail: "Unquoted words use prefix matching. Put a phrase in quotation marks to require the same adjacent words in the same order, then narrow the result-type menu when needed."),
                .init(title: "Read the result type", detail: "Each result identifies its entity class and matching snippet so source text is not confused with researcher-authored material."),
                .init(title: "Navigate exactly", detail: "Select a result to open its exact record. PDF passages open their indexed page, questions and writing open the matched record, comparisons preload the matched paper, concepts open a focused graph neighbourhood, and notes open the original Obsidian file."),
                .init(title: "Rebuild if needed", detail: "If derived search data is stale or damaged, use Integrations → Rebuild search index. Application-owned records remain intact.")
            ],
            verify: ["A quoted phrase preserves word order.", "A PDF passage opens the indexed page rather than only its paper.", "A second research question remains selected after navigation.", "Deleting/rebuilding the derived index does not delete source or research records."],
            shortcuts: ["⌘K or ⌘F — Open Global Search"]
        ),
        LearningTopic(
            id: "integrations", category: "Operations and safety", title: "Integrations, indexing, and AI settings",
            summary: "Understand every control in Settings and what crosses a system boundary.",
            icon: "gearshape", destination: .settings,
            steps: [
                .init(title: "Local research folder", detail: "Choose or change the folder, inspect the saved path and discovery summary, and refresh after files change. The bookmark grants read access only; indexing writes only to Research Atlas's database."),
                .init(title: "Obsidian", detail: "Choose the vault, rescan Markdown, and decide whether lower-confidence title suggestions are enabled."),
                .init(title: "Local storage", detail: "Inspect the database path and current SQLite/WAL/SHM footprint; rebuild only the derived search index when needed."),
                .init(title: "Indexing activity", detail: "Inspect status, progress, failures, and interruptions. Single-PDF imports commit atomically; a folder refresh safely retains files completed before cancellation."),
                .init(title: "AI provider", detail: "Choose Disabled, OpenAI Responses, Anthropic Claude, Google Gemini, Local Research AI, LM Studio Local, or a custom OpenAI-compatible HTTPS endpoint. Hosted direct endpoints are locked to documented hosts; local providers are locked to 127.0.0.1 and require no credential. Set a model and limits, then save the settings."),
                .init(title: "Read the availability map", detail: "The Where grounded AI is available section shows the saved provider's readiness and links to every model-assisted workspace. Orange means setup is incomplete; green means requests can be prepared. Local providers can be ready without a credential."),
                .init(title: "Use app-managed gpt-oss", detail: "Local Research AI defaults to gpt-oss:20b with Medium reasoning. Save and choose Prepare Local Engine or Test Connection. Research Atlas starts its bundled engine, loads the model from the normal Ollama store, reports each lifecycle state, and stops only an engine it started after the selected idle period."),
                .init(title: "Use Qwen in LM Studio", detail: "Start LM Studio's local server on port 1234, load the model, select LM Studio Local, and enter the server model identifier shown by LM Studio. Qwen reasoning models are supported without exposing free-form hidden reasoning as a Research Atlas result."),
                .init(title: "Switch providers safely", detail: "Research Atlas keeps a separate protected Keychain account for OpenAI, Claude, Gemini, and the compatible endpoint. Local Research AI and LM Studio attach no key and cannot target another host. Selecting a provider changes its default endpoint and model without overwriting another provider's key."),
                .init(title: "Understand consent", detail: "Enabling transmission does not send research content. Every grounded request still requires its own exact preview and approval.")
            ],
            verify: ["No credential appears in database/export files.", "Indexing failures have an explicit message and completed work remains available.", "Core workflows continue when the AI provider is Disabled."],
            cautions: ["Keep sensitive research folders protected with normal macOS permissions.", "Use only HTTPS for external model endpoints. Ollama and LM Studio are the only HTTP exceptions and are fixed to their loopback interfaces."]
        ),
        LearningTopic(
            id: "export-recovery", category: "Operations and safety", title: "Export, backup, and restore",
            summary: "Keep your work portable and recoverable without risking the live workspace.",
            icon: "externaldrive.badge.timemachine", destination: .settings,
            steps: [
                .init(title: "Portable export", detail: "Export a folder containing human-readable Markdown, complete application JSON, and dedicated CSV tables for literature, reasoning, AI provenance, writing, and experiments."),
                .init(title: "Database backup", detail: "Create a consistent SQLite online backup. Unlike portable export, it includes the complete workspace and derived indexes."),
                .init(title: "Preview a restore", detail: "Select a database. Research Atlas opens it read-only, checks SQLite integrity, foreign keys, required tables, schema compatibility, and record counts."),
                .init(title: "Confirm only after review", detail: "On confirmation, the app creates a pre-restore recovery copy, restores through SQLite's backup API, migrates older supported schemas, rebuilds search, and validates the result."),
                .init(title: "Recover from failure", detail: "If restore fails, Research Atlas attempts to roll back to the automatic recovery copy and reports its location.")
            ],
            verify: ["A backup passes integrity and foreign-key checks in restore preview.", "Portable exports contain source identifiers and never credentials.", "The live database is unchanged when you cancel the preview."],
            cautions: ["Portable exports omit rebuildable FTS rows and PDF page indexes; use a database backup for complete recovery."]
        ),
        LearningTopic(
            id: "troubleshooting", category: "Operations and safety", title: "Troubleshooting and limitations",
            summary: "Diagnose common failures without weakening provenance or altering source files.",
            icon: "wrench.and.screwdriver", destination: .settings,
            steps: [
                .init(title: "Folder unavailable", detail: "Choose the folder again if it moved or macOS permission changed. The existing Research Atlas records remain available for audit; source files are never altered."),
                .init(title: "PDF missing or changed", detail: "Use Locate PDF or Review Changed PDF. Confirm the path, page count, size, and SHA-256 match. Different bytes deliberately invalidate exact geometry."),
                .init(title: "No retrieval results", detail: "Check that PDFs contain machine-readable text, rebuild search, try fewer terms, and review filters. An empty result remains empty."),
                .init(title: "AI request refused or malformed", detail: "The failure is recorded with provider/model/prompt and approved source snapshots. No generated claim is accepted. Adjust the task or provider only after inspecting the error."),
                .init(title: "Obsidian note will not open", detail: "Confirm the file still exists at the indexed path and reselect/rescan the vault if permissions changed. The saved snapshot remains available for audit."),
                .init(title: "Know current boundaries", detail: "Research Atlas does not perform OCR, claim comprehensive scholarly coverage, validate semantic equivalence, write to source folders or Obsidian, notarize itself, or treat model simulations as validated human experiments.")
            ],
            verify: ["Errors explain what failed and leave source files unchanged.", "Interrupted indexing is marked failed on relaunch rather than pretending completion.", "The documented limitation is visible where it affects interpretation."],
            cautions: ["Never weaken citation or identity checks merely to make a workflow appear successful."]
        )
    ]
}
