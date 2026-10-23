import AppKit
import Foundation
import PDFKit
import ResearchAtlasCore
import SwiftUI
import UniformTypeIdentifiers

enum AppSection: String, CaseIterable, Identifiable {
    case home = "Research Home"
    case learning = "Learning Center"
    case library = "Literature Library"
    case reading = "Reading Desk"
    case questions = "Research Questions"
    case evidence = "Evidence Explorer"
    case assistant = "Research Assistant"
    case arguments = "Argument Workspace"
    case atlas = "Knowledge Atlas"
    case ideas = "Idea Laboratory"
    case contradictions = "Contradiction Detective"
    case bias = "Research Bias Auditor"
    case history = "Intellectual History"
    case argumentRoom = "Argument Room"
    case collectiveLab = "Collective Intelligence Lab"
    case writing = "Research Writing"
    case search = "Global Search"
    case settings = "Integrations"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: "house"
        case .learning: "graduationcap"
        case .library: "books.vertical"
        case .reading: "doc.richtext"
        case .questions: "questionmark.bubble"
        case .evidence: "tablecells"
        case .assistant: "sparkles"
        case .arguments: "point.3.connected.trianglepath.dotted"
        case .atlas: "circle.hexagongrid"
        case .ideas: "lightbulb.max"
        case .contradictions: "arrow.left.arrow.right"
        case .bias: "checkmark.shield"
        case .history: "clock.arrow.circlepath"
        case .argumentRoom: "person.3.sequence"
        case .collectiveLab: "brain.head.profile"
        case .writing: "square.and.pencil"
        case .search: "magnifyingglass"
        case .settings: "gearshape"
        }
    }
}

enum PDFRelinkMatch: String, Sendable {
    case exact = "Exact fingerprint match"
    case sizeOnly = "File size matches; no earlier fingerprint"
    case unverified = "No earlier fingerprint is available"
    case different = "Different from the recorded PDF"
}

struct PDFRelinkPreview: Identifiable, Sendable {
    let id = UUID()
    let literatureID: UUID
    let paperTitle: String
    let previousPath: String?
    let candidateURL: URL
    let fingerprint: PDFFileFingerprint
    let indexResult: PDFIndexResult
    let match: PDFRelinkMatch
}

private struct PreparedLocalPDF: Sendable {
    let title: String
    let fingerprint: PDFFileFingerprint
    let index: PDFIndexResult
}

private struct PreparedCollectiveTurn {
    let experimentID: UUID
    let agentID: UUID
    let round: Int
    let kind: CollectiveTurnKind
    let additionalInstruction: String
}

struct AssistantLaunchRequest: Identifiable, Equatable {
    let id = UUID()
    let query: String
    let retrievalSetID: UUID?
    let expectedLiteratureIDs: Set<UUID>
}

private enum PreparedAIRequest {
    case grounded(analysis: AIAnalysis, package: GroundedPromptPackage)
    case deliberation(analysis: AIAnalysis, session: DeliberationSession, package: GroundedPromptPackage)
    case biasAudit(analysis: AIAnalysis, audit: BiasAudit, package: GroundedPromptPackage)
    case contradiction(analysis: AIAnalysis, caseID: UUID, package: GroundedPromptPackage)
    case collectiveTurn(analysis: AIAnalysis, turn: PreparedCollectiveTurn, package: GroundedPromptPackage)

    var analysis: AIAnalysis {
        switch self {
        case .grounded(let analysis, _), .deliberation(let analysis, _, _),
             .biasAudit(let analysis, _, _), .contradiction(let analysis, _, _),
             .collectiveTurn(let analysis, _, _): analysis
        }
    }

    var package: GroundedPromptPackage {
        switch self {
        case .grounded(_, let package), .deliberation(_, _, let package),
             .biasAudit(_, _, let package), .contradiction(_, _, let package),
             .collectiveTurn(_, _, let package): package
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSection: AppSection = .home
    @Published var literature: [LiteratureItem] = []
    @Published var notes: [ObsidianNote] = []
    @Published var projects: [ResearchProject] = []
    @Published var questions: [ResearchQuestion] = []
    @Published var arguments: [ResearchArgument] = []
    @Published var argumentVersions: [ArgumentVersion] = []
    @Published var noteLinks: [PaperNoteLink] = []
    @Published var comparisonProfiles: [LiteratureComparisonProfile] = []
    @Published var retrievalSets: [RetrievalSet] = []
    @Published var retrievedPassages: [RetrievedPassage] = []
    @Published var retrievedNoteSnippets: [RetrievedNoteSnippet] = []
    @Published var concepts: [ResearchConcept] = []
    @Published var knowledgeRelationships: [KnowledgeRelationship] = []
    @Published var evidenceRecords: [EvidenceRelationship] = []
    @Published var indexingJobs: [IndexingJob] = []
    @Published var questionVersions: [ResearchQuestionVersion] = []
    @Published var questionLiteratureAssociations: [QuestionLiteratureAssociation] = []
    @Published var questionConceptAssociations: [QuestionConceptAssociation] = []
    @Published var claims: [ResearchClaim] = []
    @Published var claimVersions: [ClaimVersion] = []
    @Published var ideas: [ResearchIdea] = []
    @Published var ideaVersions: [IdeaVersion] = []
    @Published var ideaLinks: [ResearchIdeaLink] = []
    @Published var contradictionCases: [ContradictionCase] = []
    @Published var contradictionSources: [ContradictionSource] = []
    @Published var historyEvents: [HistoryEvent] = []
    @Published var aiProviderConfiguration = AIProviderConfiguration()
    @Published var aiAnalyses: [AIAnalysis] = []
    @Published var aiAnalysisCitations: [AIAnalysisCitation] = []
    @Published var aiAnalysisNoteCitations: [AIAnalysisNoteCitation] = []
    @Published var analysisReviews: [AnalysisReview] = []
    @Published var biasAudits: [BiasAudit] = []
    @Published var biasConcerns: [BiasConcern] = []
    @Published var deliberationSessions: [DeliberationSession] = []
    @Published var deliberationMessages: [DeliberationMessage] = []
    @Published var deliberationCitations: [DeliberationCitation] = []
    @Published var writingDocuments: [WritingDocument] = []
    @Published var writingSections: [WritingSection] = []
    @Published var writingEvidenceLinks: [WritingEvidenceLink] = []
    @Published var citationSupportReviews: [CitationSupportReview] = []
    @Published var collectiveExperiments: [CollectiveExperiment] = []
    @Published var collectiveAgents: [CollectiveAgent] = []
    @Published var collectiveTurns: [CollectiveTurn] = []
    @Published var collectiveTurnCitations: [CollectiveTurnCitation] = []
    @Published var pendingAITransmission: AITransmissionPreview?
    @Published var latestGroundedAnswer: GroundedAnswer?
    @Published var aiCredentialStored = false
    @Published var ollamaRuntimeStatus: OllamaRuntimeStatus = .stopped
    @Published var ollamaRuntimeManagedByApp = false
    @Published var searchResults: [SearchResult] = []
    @Published var metrics = HomeMetrics()
    @Published var selectedLiteratureID: UUID?
    @Published var selectedProjectID: UUID?
    @Published var selectedQuestionID: UUID?
    @Published var selectedArgumentID: UUID?
    @Published var readingEvidenceTarget: EvidenceRelationship?
    @Published var readingPassageTarget: RetrievedPassage?
    @Published var selectedRetrievalSetID: UUID?
    @Published var selectedAIAnalysisID: UUID?
    @Published var selectedClaimID: UUID?
    @Published var selectedIdeaID: UUID?
    @Published var selectedContradictionCaseID: UUID?
    @Published var selectedBiasAuditID: UUID?
    @Published var selectedDeliberationSessionID: UUID?
    @Published var selectedWritingDocumentID: UUID?
    @Published var selectedWritingSectionID: UUID?
    @Published var selectedCollectiveExperimentID: UUID?
    @Published var evidenceExplorerMode = 0
    @Published var comparisonLiteratureIDs = Set<UUID>()
    @Published var knowledgeAtlasPresentation = 0
    @Published var requestedKnowledgeNodeType: KnowledgeNodeType?
    @Published var requestedKnowledgeNodeID: String?
    @Published var assistantLaunchRequest: AssistantLaunchRequest?
    @Published var requestedBiasAuditArgumentID: UUID?
    @Published var requestedDeliberationArgumentID: UUID?
    @Published var isBusy = false
    @Published var statusMessage = "Local-first workspace"
    @Published var alertMessage: String?
    @Published var pendingRestorePreview: DatabaseRestorePreview?
    @Published var lastRecoveryBackupPath: String?
    @Published var pendingPDFRelink: PDFRelinkPreview?
    @Published var obsidianVaultPath: String?
    @Published var localResearchFolderPath: String?
    @Published var localFolderStatus = "Not selected"
    @Published var localFolderPDFCount = 0
    @Published var localFolderLastRefreshedAt: Date?
    @Published var scannedPDFWarning: String?
    @Published var titleMatchSuggestionsEnabled = UserDefaults.standard.bool(forKey: "titleMatchSuggestionsEnabled")

    private(set) var database: AtlasDatabase?
    private var didBootstrap = false
    private var restoreSecurityAccessActive = false
    private var pdfRelinkSecurityAccessActive = false
    private var verifyingPDFIDs: Set<UUID> = []
    private var pdfIndexingTask: Task<Void, Never>?
    private var currentIndexingJobID: UUID?
    private var pendingAIPackage: PreparedAIRequest?
    private lazy var ollamaRuntime = OllamaRuntimeController { [weak self] status, managed in
        self?.ollamaRuntimeStatus = status
        self?.ollamaRuntimeManagedByApp = managed
    }

    var selectedLiterature: LiteratureItem? {
        get { literature.first { $0.id == selectedLiteratureID } }
        set { selectedLiteratureID = newValue?.id }
    }

    var selectedArgument: ResearchArgument? {
        arguments.first { $0.id == selectedArgumentID }
    }

    var databasePath: String { database?.url.path ?? "Unavailable" }

    var localStorageDescription: String {
        guard let url = database?.url else { return "Unavailable" }
        let paths = [url.path, url.path + "-wal", url.path + "-shm"]
        let bytes = paths.reduce(Int64(0)) { total, path in
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
            return total + size
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var aiProviderReadyForRequests: Bool {
        aiProviderConfiguration.isReadyForRequests(credentialStored: aiCredentialStored)
    }

    var aiProviderStatusText: String {
        let configuration = aiProviderConfiguration
        if configuration.provider == .disabled { return "AI provider not configured" }
        if !configuration.externalTransmissionEnabled {
            return configuration.provider.isLocal ? "Local model requests are off" : "External AI transmission is off"
        }
        if configuration.provider.requiresCredential && !aiCredentialStored { return "API credential required" }
        if configuration.provider == .ollamaLocal {
            switch ollamaRuntimeStatus {
            case .stopped: return "Configured · starts after approval"
            case .starting: return "Starting the local engine"
            case .loading(let model): return "Loading \(model)"
            case .ready: return "Ready for individually approved requests"
            case .generating: return "Running an approved local request"
            case .unavailable: return "Local engine needs attention"
            }
        }
        if configuration.provider == .lmStudioLocal {
            return "Configured · local server checked on request"
        }
        return "Configured · each request requires approval"
    }

    var suggestedRetrievalSetID: UUID? {
        if let selectedRetrievalSetID, groundedSourceCount(for: selectedRetrievalSetID) > 0 {
            return selectedRetrievalSetID
        }
        return retrievalSets.first { groundedSourceCount(for: $0.id) > 0 }?.id
    }

    func currentPaperIDs(for retrievalSetID: UUID) -> Set<UUID> {
        Set(passages(for: retrievalSetID)
            .filter { $0.citationStatus == .current }
            .map(\.literatureID))
    }

    func retrievalSetOverlap(_ retrievalSetID: UUID, with literatureIDs: Set<UUID>) -> Int {
        currentPaperIDs(for: retrievalSetID).intersection(literatureIDs).count
    }

    func suggestedRetrievalSetID(matching literatureIDs: Set<UUID>) -> UUID? {
        guard !literatureIDs.isEmpty else { return suggestedRetrievalSetID }
        let available = retrievalSets.filter { groundedSourceCount(for: $0.id) > 0 }
        guard !available.isEmpty else { return nil }
        let ranked = available.sorted { lhs, rhs in
            let lhsOverlap = retrievalSetOverlap(lhs.id, with: literatureIDs)
            let rhsOverlap = retrievalSetOverlap(rhs.id, with: literatureIDs)
            if lhsOverlap != rhsOverlap { return lhsOverlap > rhsOverlap }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        if let best = ranked.first, retrievalSetOverlap(best.id, with: literatureIDs) > 0 { return best.id }
        return suggestedRetrievalSetID
    }

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        RetiredIntegrationCleanup.run()
        do {
            let url = try AtlasDatabase.defaultURL()
            database = try AtlasDatabase(url: url)
            try database?.markInterruptedIndexingJobs()
            obsidianVaultPath = restoredVaultURL()?.path
            localResearchFolderPath = restoredLocalResearchFolderURL()?.path
            localFolderStatus = localResearchFolderPath == nil ? "Not selected" : "Ready to refresh"
            try reload()
        } catch {
            alertMessage = error.localizedDescription
            statusMessage = "Database unavailable"
        }
    }

    func reload() throws {
        guard let database else { return }
        literature = try database.literatureItems()
        notes = try database.obsidianNotes()
        projects = try database.projects()
        questions = try database.questions()
        arguments = try database.arguments()
        argumentVersions = try database.argumentVersions()
        comparisonProfiles = try database.comparisonProfiles()
        retrievalSets = try database.retrievalSets()
        retrievedPassages = try database.retrievedPassages()
        retrievedNoteSnippets = try database.retrievedNoteSnippets()
        concepts = try database.concepts()
        knowledgeRelationships = try database.knowledgeRelationships()
        evidenceRecords = try database.allEvidence()
        indexingJobs = try database.indexingJobs()
        questionVersions = try database.questionVersions()
        questionLiteratureAssociations = try database.questionLiteratureAssociations()
        questionConceptAssociations = try database.questionConceptAssociations()
        claims = try database.claims()
        claimVersions = try database.claimVersions()
        ideas = try database.ideas()
        ideaVersions = try database.ideaVersions()
        ideaLinks = try database.ideaLinks()
        contradictionCases = try database.contradictionCases()
        contradictionSources = try database.contradictionSources()
        historyEvents = try database.historyEvents()
        aiProviderConfiguration = try database.aiProviderConfiguration()
        aiAnalyses = try database.aiAnalyses()
        aiAnalysisCitations = try database.aiAnalysisCitations()
        aiAnalysisNoteCitations = try database.aiAnalysisNoteCitations()
        analysisReviews = try database.analysisReviews()
        biasAudits = try database.biasAudits()
        biasConcerns = try database.biasConcerns()
        deliberationSessions = try database.deliberationSessions()
        deliberationMessages = try database.deliberationMessages()
        deliberationCitations = try database.deliberationCitations()
        writingDocuments = try database.writingDocuments()
        writingSections = try database.writingSections()
        writingEvidenceLinks = try database.writingEvidenceLinks()
        citationSupportReviews = try database.citationSupportReviews()
        collectiveExperiments = try database.collectiveExperiments()
        collectiveAgents = try database.collectiveAgents()
        collectiveTurns = try database.collectiveTurns()
        collectiveTurnCitations = try database.collectiveTurnCitations()
        aiCredentialStored = KeychainSecretStore.rememberedPresence(
            for: aiProviderConfiguration.provider
        )
        for suggestion in NoteMatcher.suggestions(
            notes: notes,
            literature: literature,
            includeTitleMatches: titleMatchSuggestionsEnabled
        ) {
            try database.saveNoteLinkSuggestion(suggestion)
        }
        noteLinks = try database.noteLinks()
        metrics = try database.metrics()
        if selectedLiteratureID == nil || !literature.contains(where: { $0.id == selectedLiteratureID }) {
            selectedLiteratureID = literature.first?.id
        }
        if selectedProjectID == nil || !projects.contains(where: { $0.id == selectedProjectID }) {
            selectedProjectID = projects.first?.id
        }
        let projectQuestions = questions.filter { $0.projectID == selectedProjectID }
        if selectedQuestionID == nil || !projectQuestions.contains(where: { $0.id == selectedQuestionID }) {
            selectedQuestionID = projectQuestions.first?.id
        }
        if selectedArgumentID == nil || !arguments.contains(where: { $0.id == selectedArgumentID }) {
            selectedArgumentID = arguments.first?.id
        }
        if selectedRetrievalSetID == nil || !retrievalSets.contains(where: { $0.id == selectedRetrievalSetID }) {
            selectedRetrievalSetID = retrievalSets.first?.id
        }
        // Research Assistant opens as a clean composer. Automatically selecting the newest
        // historical request made a failed or very large provenance record dominate the screen
        // before the researcher chose to inspect it. Completed requests still select themselves.
        if let selectedAIAnalysisID, !aiAnalyses.contains(where: { $0.id == selectedAIAnalysisID }) {
            self.selectedAIAnalysisID = nil
        }
        if selectedClaimID == nil || !claims.contains(where: { $0.id == selectedClaimID }) { selectedClaimID = claims.first?.id }
        if selectedIdeaID == nil || !ideas.contains(where: { $0.id == selectedIdeaID }) { selectedIdeaID = ideas.first?.id }
        if selectedContradictionCaseID == nil || !contradictionCases.contains(where: { $0.id == selectedContradictionCaseID }) {
            selectedContradictionCaseID = contradictionCases.first?.id
        }
        if selectedBiasAuditID == nil || !biasAudits.contains(where: { $0.id == selectedBiasAuditID }) {
            selectedBiasAuditID = biasAudits.first?.id
        }
        if selectedDeliberationSessionID == nil || !deliberationSessions.contains(where: { $0.id == selectedDeliberationSessionID }) {
            selectedDeliberationSessionID = deliberationSessions.first?.id
        }
        if selectedWritingDocumentID == nil || !writingDocuments.contains(where: { $0.id == selectedWritingDocumentID }) {
            selectedWritingDocumentID = writingDocuments.first?.id
        }
        let availableSections = writingSections.filter { $0.documentID == selectedWritingDocumentID }
        if selectedWritingSectionID == nil || !availableSections.contains(where: { $0.id == selectedWritingSectionID }) {
            selectedWritingSectionID = availableSections.first?.id
        }
        if selectedCollectiveExperimentID == nil || !collectiveExperiments.contains(where: { $0.id == selectedCollectiveExperimentID }) {
            selectedCollectiveExperimentID = collectiveExperiments.first?.id
        }
    }

    func search(_ text: String) {
        do {
            searchResults = try database?.search(text) ?? []
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func openSearchResult(_ result: SearchResult) {
        openRecord(entityType: result.entityType, entityID: result.entityID)
    }

    func openResearchAssistant(
        query: String,
        retrievalSetID: UUID? = nil,
        expectedLiteratureIDs: Set<UUID> = []
    ) {
        let setID = retrievalSetID ?? suggestedRetrievalSetID(matching: expectedLiteratureIDs)
        selectedRetrievalSetID = setID
        assistantLaunchRequest = AssistantLaunchRequest(
            query: query.trimmingCharacters(in: .whitespacesAndNewlines),
            retrievalSetID: setID,
            expectedLiteratureIDs: expectedLiteratureIDs
        )
        selectedSection = .assistant
    }

    func openBiasAuditor(for argument: ResearchArgument) {
        selectedArgumentID = argument.id
        requestedBiasAuditArgumentID = argument.id
        selectedSection = .bias
    }

    func openArgumentRoom(for argument: ResearchArgument) {
        selectedArgumentID = argument.id
        requestedDeliberationArgumentID = argument.id
        selectedSection = .argumentRoom
    }

    func openRecord(entityType: String, entityID: String) {
        if entityType == "passage" {
            do {
                guard let passage = try database?.sourcePassage(id: entityID) else {
                    alertMessage = "This indexed PDF passage is no longer available. Rebuild the search index and try again."
                    return
                }
                openRetrievedPassage(passage)
            } catch {
                alertMessage = error.localizedDescription
            }
            return
        }

        guard let id = UUID(uuidString: entityID) else {
            alertMessage = "This search result has an invalid local identifier."
            return
        }
        switch entityType {
        case "literature":
            guard literature.contains(where: { $0.id == id }) else { return }
            selectedLiteratureID = id
            selectedSection = .library
        case "project":
            guard projects.contains(where: { $0.id == id }) else { return }
            selectedProjectID = id
            selectedQuestionID = questions
                .filter { $0.projectID == id }
                .sorted { $0.modifiedAt > $1.modifiedAt }
                .first?.id
            selectedSection = .questions
        case "question":
            guard let question = questions.first(where: { $0.id == id }) else { return }
            selectedProjectID = question.projectID
            selectedQuestionID = question.id
            selectedSection = .questions
        case "argument":
            guard arguments.contains(where: { $0.id == id }) else { return }
            selectedArgumentID = id
            selectedSection = .arguments
        case "comparison":
            guard literature.contains(where: { $0.id == id }) else { return }
            comparisonLiteratureIDs = [id]
            evidenceExplorerMode = 1
            selectedSection = .evidence
        case "concept":
            guard concepts.contains(where: { $0.id == id }) else { return }
            knowledgeAtlasPresentation = 0
            requestedKnowledgeNodeType = .concept
            requestedKnowledgeNodeID = id.uuidString
            selectedSection = .atlas
        case "claim":
            guard claims.contains(where: { $0.id == id }) else { return }
            selectedClaimID = id
            evidenceExplorerMode = 2
            selectedSection = .evidence
        case "idea":
            guard ideas.contains(where: { $0.id == id }) else { return }
            selectedIdeaID = id
            selectedSection = .ideas
        case "contradiction":
            guard contradictionCases.contains(where: { $0.id == id }) else { return }
            selectedContradictionCaseID = id
            selectedSection = .contradictions
        case "writing":
            guard writingDocuments.contains(where: { $0.id == id }) else { return }
            selectedWritingDocumentID = id
            selectedWritingSectionID = writingSections.first { $0.documentID == id }?.id
            selectedSection = .writing
        case "writing-section":
            guard let section = writingSections.first(where: { $0.id == id }) else { return }
            selectedWritingDocumentID = section.documentID
            selectedWritingSectionID = section.id
            selectedSection = .writing
        case "note":
            guard let note = notes.first(where: { $0.id == id }) else { return }
            openObsidianNote(note)
        default:
            alertMessage = "Research Atlas cannot open this result type yet."
        }
    }

    func chooseAndAddPDF() {
        let panel = NSOpenPanel()
        panel.title = "Add a local research PDF"
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addPDF(url)
    }

    func addPDF(_ url: URL) {
        guard let database else { return }
        pdfIndexingTask?.cancel()
        let accessed = url.startAccessingSecurityScopedResource()
        var job = IndexingJob(kind: .pdf, sourceName: url.lastPathComponent, status: .running)
        currentIndexingJobID = job.id
        try? database.saveIndexingJob(job)
        indexingJobs = (try? database.indexingJobs()) ?? indexingJobs
        isBusy = true
        statusMessage = "Indexing \(url.lastPathComponent)…"
        pdfIndexingTask = Task {
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let processed = try await prepareLocalPDF(at: url)
                try Task.checkCancellation()
                let standardizedPath = url.standardizedFileURL.path
                let byPath = literature.first { $0.pdfPath.map { URL(fileURLWithPath: $0).standardizedFileURL.path } == standardizedPath }
                let byHash = literature.first { $0.pdfContentHash == processed.fingerprint.sha256 }
                if byPath == nil, let duplicate = byHash,
                   PDFFileInspector.availability(for: duplicate) == .available {
                    job.status = .completed
                    job.completedUnits = 1
                    job.totalUnits = 1
                    job.failureMessage = "Skipped: this PDF is already indexed."
                    job.updatedAt = Date()
                    try database.saveIndexingJob(job)
                    try reload()
                    selectedLiteratureID = duplicate.id
                    statusMessage = "PDF already indexed — selected the existing paper"
                    isBusy = false
                    currentIndexingJobID = nil
                    pdfIndexingTask = nil
                    return
                }
                var item = byPath ?? byHash ?? LiteratureItem(title: processed.title)
                if item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { item.title = processed.title }
                item.itemType = "document"
                item.source = .manual
                item.pdfPath = standardizedPath
                item.pdfByteCount = processed.fingerprint.byteCount
                item.pdfContentHash = processed.fingerprint.sha256
                item.pdfLastVerifiedAt = Date()
                item.sourceAvailability = .available
                item.modifiedAt = Date()
                try database.upsertLiterature(item, indexingPDFPages: processed.index.pages)
                job.status = .completed
                job.completedUnits = processed.index.pages.count
                job.totalUnits = processed.index.pages.count
                job.updatedAt = Date()
                try database.saveIndexingJob(job)
                try reload()
                selectedLiteratureID = item.id
                selectedSection = .reading
                scannedPDFWarning = processed.index.hasMachineReadableText ? nil : "This PDF has little or no machine-readable text. OCR has not been performed."
                statusMessage = "Indexed \(processed.index.pages.count) PDF pages"
            } catch is CancellationError {
                job.status = .cancelled
                job.updatedAt = Date()
                try? database.saveIndexingJob(job)
                indexingJobs = (try? database.indexingJobs()) ?? indexingJobs
                statusMessage = "PDF indexing cancelled before database changes"
            } catch {
                job.status = .failed
                job.failureMessage = error.localizedDescription
                job.updatedAt = Date()
                try? database.saveIndexingJob(job)
                indexingJobs = (try? database.indexingJobs()) ?? indexingJobs
                alertMessage = error.localizedDescription
                statusMessage = "PDF import failed"
            }
            isBusy = false
            if currentIndexingJobID == job.id { currentIndexingJobID = nil }
            pdfIndexingTask = nil
        }
    }

    func chooseLocalResearchFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose your local research folder"
        panel.prompt = "Use Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try saveLocalResearchFolderBookmark(url)
            localResearchFolderPath = url.path
            refreshLocalResearchFolder(at: url)
        } catch {
            alertMessage = error.localizedDescription
            localFolderStatus = "Folder access could not be saved"
        }
    }

    func refreshLocalResearchFolder() {
        guard let url = restoredLocalResearchFolderURL() else {
            chooseLocalResearchFolder()
            return
        }
        refreshLocalResearchFolder(at: url)
    }

    private func refreshLocalResearchFolder(at url: URL) {
        guard let database else { return }
        pdfIndexingTask?.cancel()
        let accessed = url.startAccessingSecurityScopedResource()
        var job = IndexingJob(kind: .researchFolder, sourceName: url.lastPathComponent, status: .running)
        currentIndexingJobID = job.id
        try? database.saveIndexingJob(job)
        indexingJobs = (try? database.indexingJobs()) ?? indexingJobs
        isBusy = true
        localFolderStatus = "Discovering PDFs…"
        statusMessage = "Scanning \(url.lastPathComponent) without changing source files…"

        pdfIndexingTask = Task {
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let pdfs = try await Task.detached(priority: .userInitiated) {
                    try LocalResearchFolderScanner.discoverPDFs(at: url)
                }.value
                try Task.checkCancellation()
                localFolderPDFCount = pdfs.count
                job.totalUnits = pdfs.count
                job.updatedAt = Date()
                try database.saveIndexingJob(job)

                var known = try database.literatureItems()
                var indexed = 0
                var unchanged = 0
                var duplicates = 0
                var failures = 0
                var firstImportedID: UUID?

                for (offset, pdfURL) in pdfs.enumerated() {
                    try Task.checkCancellation()
                    localFolderStatus = "Checking \(offset + 1) of \(pdfs.count)…"
                    do {
                        let fingerprint = try await Task.detached(priority: .utility) {
                            try PDFFileInspector.fingerprint(at: pdfURL)
                        }.value
                        let standardizedPath = pdfURL.standardizedFileURL.path
                        let byPathIndex = known.firstIndex {
                            $0.pdfPath.map { URL(fileURLWithPath: $0).standardizedFileURL.path } == standardizedPath
                        }
                        let byHashIndex = known.firstIndex { $0.pdfContentHash == fingerprint.sha256 }

                        if let byPathIndex, known[byPathIndex].pdfContentHash == fingerprint.sha256 {
                            known[byPathIndex].pdfByteCount = fingerprint.byteCount
                            known[byPathIndex].pdfLastVerifiedAt = Date()
                            known[byPathIndex].sourceAvailability = .available
                            try database.upsertLiterature(known[byPathIndex])
                            unchanged += 1
                        } else if byPathIndex == nil, let byHashIndex,
                                  PDFFileInspector.availability(for: known[byHashIndex]) == .available {
                            duplicates += 1
                        } else {
                            let prepared = try await prepareLocalPDF(at: pdfURL, knownFingerprint: fingerprint)
                            try Task.checkCancellation()
                            let existingIndex = byPathIndex ?? byHashIndex
                            var item = existingIndex.map { known[$0] } ?? LiteratureItem(title: prepared.title)
                            if item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { item.title = prepared.title }
                            item.itemType = "document"
                            item.source = .manual
                            item.pdfPath = standardizedPath
                            item.pdfByteCount = prepared.fingerprint.byteCount
                            item.pdfContentHash = prepared.fingerprint.sha256
                            item.pdfLastVerifiedAt = Date()
                            item.sourceAvailability = .available
                            item.modifiedAt = Date()
                            try database.upsertLiterature(item, indexingPDFPages: prepared.index.pages)
                            if let existingIndex { known[existingIndex] = item } else { known.append(item) }
                            firstImportedID = firstImportedID ?? item.id
                            indexed += 1
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        failures += 1
                    }
                    job.completedUnits = offset + 1
                    job.updatedAt = Date()
                    try database.saveIndexingJob(job)
                }

                job.status = .completed
                job.failureMessage = failures == 0 ? nil : "\(failures) PDF file\(failures == 1 ? "" : "s") could not be read."
                job.updatedAt = Date()
                try database.saveIndexingJob(job)
                try reload()
                if let firstImportedID { selectedLiteratureID = firstImportedID }
                localFolderLastRefreshedAt = Date()
                localFolderStatus = "\(pdfs.count) PDFs found · \(indexed) indexed · \(unchanged) unchanged · \(duplicates) duplicates skipped · \(failures) unreadable"
                statusMessage = failures == 0
                    ? "Local research folder refreshed"
                    : "Folder refreshed; \(failures) unreadable PDF\(failures == 1 ? "" : "s") skipped"
            } catch is CancellationError {
                job.status = .cancelled
                job.failureMessage = "Stopped by the user. Files already committed remain safely indexed."
                job.updatedAt = Date()
                try? database.saveIndexingJob(job)
                indexingJobs = (try? database.indexingJobs()) ?? indexingJobs
                localFolderStatus = "Refresh cancelled"
                statusMessage = "Research-folder refresh cancelled"
            } catch {
                job.status = .failed
                job.failureMessage = error.localizedDescription
                job.updatedAt = Date()
                try? database.saveIndexingJob(job)
                indexingJobs = (try? database.indexingJobs()) ?? indexingJobs
                localFolderStatus = "Refresh failed"
                alertMessage = error.localizedDescription
                statusMessage = "Research-folder refresh failed"
            }
            isBusy = false
            if currentIndexingJobID == job.id { currentIndexingJobID = nil }
            pdfIndexingTask = nil
        }
    }

    private func prepareLocalPDF(at url: URL, knownFingerprint: PDFFileFingerprint? = nil) async throws -> PreparedLocalPDF {
        try await Task.detached(priority: .userInitiated) {
            let fingerprint = try knownFingerprint ?? PDFFileInspector.fingerprint(at: url)
            let index = try PDFIndexer.extractText(from: url)
            let fingerprintAfterExtraction = try PDFFileInspector.fingerprint(at: url)
            guard fingerprintAfterExtraction == fingerprint else { throw PDFIndexingError.changedDuringRelink }
            let metadataTitle = PDFDocument(url: url)?.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
            let cleanTitle = metadataTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            return PreparedLocalPDF(
                title: cleanTitle?.isEmpty == false ? cleanTitle! : url.deletingPathExtension().lastPathComponent,
                fingerprint: fingerprint,
                index: index
            )
        }.value
    }

    func cancelCurrentIndexing() {
        guard pdfIndexingTask != nil else { return }
        pdfIndexingTask?.cancel()
        statusMessage = "Cancelling PDF indexing…"
    }

    func pdfFileAvailability(for item: LiteratureItem) -> PDFFileAvailability {
        PDFFileInspector.availability(for: item)
    }

    func choosePDFLocation(for item: LiteratureItem) {
        cancelPDFRelink()
        let panel = NSOpenPanel()
        panel.title = item.pdfPath == nil ? "Attach a local PDF" : "Locate the PDF for \(item.title)"
        panel.prompt = "Preview PDF"
        panel.allowedContentTypes = [.pdf]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        inspectPDFCandidate(url, for: item)
    }

    func reviewChangedPDF(for item: LiteratureItem) {
        guard let path = item.pdfPath else { return }
        inspectPDFCandidate(URL(fileURLWithPath: path), for: item)
    }

    private func inspectPDFCandidate(_ url: URL, for item: LiteratureItem) {
        let accessed = url.startAccessingSecurityScopedResource()
        isBusy = true
        statusMessage = "Inspecting selected PDF…"
        Task {
            do {
                let processed = try await Task.detached(priority: .userInitiated) {
                    (
                        try PDFFileInspector.fingerprint(at: url),
                        try PDFIndexer.extractText(from: url)
                    )
                }.value
                let match: PDFRelinkMatch
                if let expectedHash = item.pdfContentHash {
                    match = expectedHash == processed.0.sha256 ? .exact : .different
                } else if let expectedSize = item.pdfByteCount {
                    match = expectedSize == processed.0.byteCount ? .sizeOnly : .different
                } else {
                    match = .unverified
                }
                pdfRelinkSecurityAccessActive = accessed
                pendingPDFRelink = PDFRelinkPreview(
                    literatureID: item.id,
                    paperTitle: item.title,
                    previousPath: item.pdfPath,
                    candidateURL: url,
                    fingerprint: processed.0,
                    indexResult: processed.1,
                    match: match
                )
                statusMessage = "PDF inspected — review before updating the link"
            } catch {
                if accessed { url.stopAccessingSecurityScopedResource() }
                alertMessage = error.localizedDescription
                statusMessage = "PDF inspection failed"
            }
            isBusy = false
        }
    }

    func verifyAndIndexPDFIfNeeded(_ item: LiteratureItem) {
        guard item.pdfContentHash == nil,
              pdfFileAvailability(for: item) == .available,
              let path = item.pdfPath,
              let database,
              verifyingPDFIDs.insert(item.id).inserted else { return }
        let url = URL(fileURLWithPath: path)
        statusMessage = "Recording PDF fingerprint and page index…"
        Task {
            defer { verifyingPDFIDs.remove(item.id) }
            do {
                let processed = try await Task.detached(priority: .utility) {
                    let before = try PDFFileInspector.fingerprint(at: url)
                    let index = try PDFIndexer.extractText(from: url)
                    let after = try PDFFileInspector.fingerprint(at: url)
                    guard before == after else { throw PDFIndexingError.changedDuringRelink }
                    return (before, index)
                }.value
                try database.relinkPDF(
                    literatureID: item.id,
                    url: url,
                    fingerprint: processed.0,
                    pages: processed.1.pages
                )
                try reload()
                selectedLiteratureID = item.id
                scannedPDFWarning = processed.1.hasMachineReadableText ? nil : "This PDF has little or no machine-readable text. OCR has not been performed."
                statusMessage = "PDF fingerprint recorded and \(processed.1.pages.count) pages indexed"
            } catch {
                alertMessage = error.localizedDescription
                statusMessage = "PDF verification failed"
            }
        }
    }

    func cancelPDFRelink() {
        if pdfRelinkSecurityAccessActive, let url = pendingPDFRelink?.candidateURL {
            url.stopAccessingSecurityScopedResource()
        }
        pdfRelinkSecurityAccessActive = false
        pendingPDFRelink = nil
    }

    func confirmPDFRelink(_ preview: PDFRelinkPreview) {
        guard let database, pendingPDFRelink?.id == preview.id else { return }
        isBusy = true
        statusMessage = "Updating PDF link and page index…"
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    let currentFingerprint = try PDFFileInspector.fingerprint(at: preview.candidateURL)
                    guard currentFingerprint == preview.fingerprint else { throw PDFIndexingError.changedDuringRelink }
                    try database.relinkPDF(
                        literatureID: preview.literatureID,
                        url: preview.candidateURL,
                        fingerprint: currentFingerprint,
                        pages: preview.indexResult.pages,
                        preserveZoteroAttachmentKey: preview.match == .exact
                    )
                }.value
                if pdfRelinkSecurityAccessActive { preview.candidateURL.stopAccessingSecurityScopedResource() }
                pdfRelinkSecurityAccessActive = false
                pendingPDFRelink = nil
                try reload()
                selectedLiteratureID = preview.literatureID
                scannedPDFWarning = preview.indexResult.hasMachineReadableText ? nil : "This PDF has little or no machine-readable text. OCR has not been performed."
                statusMessage = "PDF link repaired and \(preview.indexResult.pages.count) pages indexed"
            } catch {
                if pdfRelinkSecurityAccessActive { preview.candidateURL.stopAccessingSecurityScopedResource() }
                pdfRelinkSecurityAccessActive = false
                pendingPDFRelink = nil
                alertMessage = error.localizedDescription
                statusMessage = "PDF link was not changed"
            }
            isBusy = false
        }
    }

    func chooseObsidianVault() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Obsidian vault"
        panel.prompt = "Choose Vault"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importObsidianVault(url)
    }

    func importObsidianVault(_ url: URL) {
        guard let database else { return }
        var job = IndexingJob(kind: .obsidian, sourceName: url.lastPathComponent, status: .running)
        try? database.saveIndexingJob(job)
        indexingJobs = (try? database.indexingJobs()) ?? indexingJobs
        isBusy = true
        statusMessage = "Discovering Markdown notes…"
        let accessed = url.startAccessingSecurityScopedResource()
        Task {
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let result = await Task.detached(priority: .userInitiated) {
                ObsidianIntegration.discoverNotes(in: url)
            }.value
            do {
                for note in result.notes { try database.upsertObsidianNote(note) }
                job.status = .completed
                job.completedUnits = result.notes.count
                job.totalUnits = result.notes.count + result.failures.count
                job.failureMessage = result.failures.isEmpty ? nil : "\(result.failures.count) Markdown file\(result.failures.count == 1 ? "" : "s") could not be read."
                job.updatedAt = Date()
                try database.saveIndexingJob(job)
                try saveVaultBookmark(url)
                obsidianVaultPath = url.path
                try reload()
                statusMessage = "Indexed \(result.notes.count) Obsidian notes"
                if !result.failures.isEmpty {
                    alertMessage = "Imported \(result.notes.count) notes. \(result.failures.count) files could not be read."
                }
            } catch {
                job.status = .failed
                job.failureMessage = error.localizedDescription
                job.updatedAt = Date()
                try? database.saveIndexingJob(job)
                indexingJobs = (try? database.indexingJobs()) ?? indexingJobs
                alertMessage = error.localizedDescription
                statusMessage = "Obsidian import failed"
            }
            isBusy = false
        }
    }

    func saveProject(title: String, summary: String) {
        do {
            let project = ResearchProject(title: title, summary: summary)
            try database?.saveProject(project)
            try reload()
            selectedProjectID = project.id
            selectedQuestionID = nil
            statusMessage = "Research project created"
        } catch { alertMessage = error.localizedDescription }
    }

    func saveQuestion(projectID: UUID, text: String, notes: String) {
        do {
            let question = ResearchQuestion(projectID: projectID, question: text, notes: notes)
            try database?.saveQuestion(question)
            try reload()
            selectedProjectID = projectID
            selectedQuestionID = question.id
            statusMessage = "Research question created"
        } catch { alertMessage = error.localizedDescription }
    }

    func updateQuestion(_ question: ResearchQuestion, changeNote: String) {
        do {
            var updated = question
            updated.modifiedAt = Date()
            try database?.saveQuestion(updated, changeNote: changeNote)
            try reload()
            statusMessage = "Research question updated and version recorded"
        } catch { alertMessage = error.localizedDescription }
    }

    func linkLiterature(_ literatureID: UUID, to questionID: UUID, notes: String = "") {
        do {
            try database?.saveQuestionLiteratureAssociation(QuestionLiteratureAssociation(questionID: questionID, literatureID: literatureID, notes: notes))
            try reload()
            statusMessage = "Literature associated with research question"
        } catch { alertMessage = error.localizedDescription }
    }

    func unlinkLiterature(_ association: QuestionLiteratureAssociation) {
        do {
            try database?.deleteQuestionLiteratureAssociation(questionID: association.questionID, literatureID: association.literatureID)
            try reload()
        } catch { alertMessage = error.localizedDescription }
    }

    func linkConcept(_ conceptID: UUID, to questionID: UUID, notes: String = "") {
        do {
            try database?.saveQuestionConceptAssociation(QuestionConceptAssociation(questionID: questionID, conceptID: conceptID, notes: notes))
            try reload()
            statusMessage = "Concept associated with research question"
        } catch { alertMessage = error.localizedDescription }
    }

    func unlinkConcept(_ association: QuestionConceptAssociation) {
        do {
            try database?.deleteQuestionConceptAssociation(questionID: association.questionID, conceptID: association.conceptID)
            try reload()
        } catch { alertMessage = error.localizedDescription }
    }

    func saveArgument(questionID: UUID?, proposition: String, qualification: String) {
        do {
            let argument = ResearchArgument(questionID: questionID, proposition: proposition, qualification: qualification)
            try database?.saveArgument(argument)
            try reload()
            selectedArgumentID = argument.id
        } catch { alertMessage = error.localizedDescription }
    }

    func updateArgument(_ argument: ResearchArgument, questionID: UUID?, proposition: String, qualification: String, status: String, changeNote: String) {
        do {
            var updated = argument
            updated.questionID = questionID
            updated.proposition = proposition
            updated.qualification = qualification
            updated.status = status
            updated.modifiedAt = Date()
            try database?.saveArgument(updated, changeNote: changeNote)
            try reload()
            selectedArgumentID = updated.id
            statusMessage = "Argument updated and version recorded"
        } catch { alertMessage = error.localizedDescription }
    }

    func versions(for argumentID: UUID) -> [ArgumentVersion] {
        argumentVersions.filter { $0.argumentID == argumentID }.sorted { $0.createdAt > $1.createdAt }
    }

    func saveEvidence(
        argumentID: UUID,
        literatureID: UUID,
        relation: EvidenceRelation,
        summary: String,
        page: Int?,
        quote: String,
        verification: VerificationState,
        selectionRegions: [PDFSelectionRegion] = [],
        selectionDocumentHash: String? = nil
    ) {
        do {
            try database?.saveEvidence(EvidenceRelationship(
                argumentID: argumentID, literatureID: literatureID, relation: relation, summary: summary,
                page: page, quotedPassage: quote, verification: verification,
                selectionRegions: selectionRegions, selectionDocumentHash: selectionDocumentHash
            ))
            try reload()
        } catch { alertMessage = error.localizedDescription }
    }

    func updateEvidence(_ evidence: EvidenceRelationship) {
        do {
            try database?.saveEvidence(evidence)
            try reload()
            statusMessage = "Evidence annotation updated"
        } catch { alertMessage = error.localizedDescription }
    }

    func deleteEvidence(_ evidence: EvidenceRelationship) {
        do {
            try database?.deleteEvidence(id: evidence.id)
            try reload()
            if readingEvidenceTarget?.id == evidence.id { readingEvidenceTarget = nil }
            statusMessage = "Evidence annotation deleted"
        } catch { alertMessage = error.localizedDescription }
    }

    func openEvidenceInReadingDesk(_ evidence: EvidenceRelationship) {
        selectedLiteratureID = evidence.literatureID
        readingPassageTarget = nil
        readingEvidenceTarget = evidence
        selectedSection = .reading
    }

    func evidence(for argumentID: UUID) -> [EvidenceRelationship] {
        evidenceRecords.filter { $0.argumentID == argumentID }
    }

    var isIndexingCancellable: Bool { pdfIndexingTask != nil }

    func comparisonProfile(for literatureID: UUID) -> LiteratureComparisonProfile {
        comparisonProfiles.first { $0.literatureID == literatureID }
            ?? LiteratureComparisonProfile(literatureID: literatureID)
    }

    func saveComparisonProfile(_ profile: LiteratureComparisonProfile) {
        do {
            var updated = profile
            updated.modifiedAt = Date()
            try database?.saveComparisonProfile(updated)
            try reload()
            statusMessage = "Literature comparison profile saved"
        } catch { alertMessage = error.localizedDescription }
    }

    func saveClaim(_ claim: ResearchClaim, changeNote: String? = nil) {
        do {
            var updated = claim
            updated.modifiedAt = Date()
            try database?.saveClaim(updated, changeNote: changeNote)
            try reload()
            selectedClaimID = updated.id
            statusMessage = changeNote == nil ? "Claim saved for review" : "Claim revised and version recorded"
        } catch { alertMessage = error.localizedDescription }
    }

    func createClaimFromSelection(
        item: LiteratureItem,
        claimText: String,
        category: ClaimCategory,
        page: Int?,
        quote: String,
        authorTerminology: String,
        methodologicalContext: String,
        evidenceType: String,
        relatedConstructs: [String],
        studyContext: String,
        verification: VerificationState,
        userNotes: String
    ) {
        let passageID = page.map { "\(item.id.uuidString):\($0)" }
        saveClaim(ResearchClaim(
            claimText: claimText, category: category, literatureID: item.id, sourcePassageID: passageID,
            page: page, quotedSourceText: quote, authorTerminology: authorTerminology,
            methodologicalContext: methodologicalContext, evidenceType: evidenceType,
            relatedConstructs: relatedConstructs, studyContext: studyContext,
            extractionMethod: .manualSelection, verification: verification, userNotes: userNotes
        ))
    }

    func deleteClaim(_ claim: ResearchClaim) {
        do {
            try database?.deleteClaim(id: claim.id)
            try reload()
            statusMessage = "Application-owned claim deleted; source records unchanged"
        } catch { alertMessage = error.localizedDescription }
    }

    func versions(forClaim claimID: UUID) -> [ClaimVersion] {
        claimVersions.filter { $0.claimID == claimID }.sorted { $0.createdAt > $1.createdAt }
    }

    func openClaimSource(_ claim: ResearchClaim) {
        guard let literatureID = claim.literatureID, let page = claim.page else { return }
        selectedLiteratureID = literatureID
        readingEvidenceTarget = nil
        readingPassageTarget = RetrievedPassage(
            retrievalSetID: UUID(), sourcePassageID: claim.sourcePassageID ?? "\(literatureID.uuidString):\(page)",
            literatureID: literatureID, page: page, passageText: claim.quotedSourceText,
            extractionMethod: claim.extractionMethod.rawValue, sourceIndexedAt: claim.createdAt,
            rank: 0, citationStatus: .current
        )
        selectedSection = .reading
    }

    func createRetrievalSet(name: String, query: String, yearFrom: Int?, yearTo: Int?) {
        do {
            let set = RetrievalSet(
                name: name, query: query, yearFrom: yearFrom, yearTo: yearTo
            )
            let passages = try database?.createRetrievalSet(set) ?? []
            try reload()
            selectedRetrievalSetID = set.id
            statusMessage = passages.isEmpty
                ? "Retrieval set saved with no matching source passages"
                : "Retrieval set saved with \(passages.count) source passage\(passages.count == 1 ? "" : "s")"
        } catch { alertMessage = error.localizedDescription }
    }

    func deleteRetrievalSet(_ set: RetrievalSet) {
        do {
            try database?.deleteRetrievalSet(id: set.id)
            try reload()
            statusMessage = "Retrieval set deleted"
        } catch { alertMessage = error.localizedDescription }
    }

    func passages(for retrievalSetID: UUID) -> [RetrievedPassage] {
        retrievedPassages.filter { $0.retrievalSetID == retrievalSetID }
            .sorted { $0.rank == $1.rank ? $0.page < $1.page : $0.rank < $1.rank }
    }

    func noteSnippets(for retrievalSetID: UUID) -> [RetrievedNoteSnippet] {
        retrievedNoteSnippets.filter { $0.retrievalSetID == retrievalSetID }
            .sorted { $0.rank == $1.rank ? $0.noteTitle < $1.noteTitle : $0.rank < $1.rank }
    }

    func groundedSourceCount(for retrievalSetID: UUID) -> Int {
        passages(for: retrievalSetID).filter { $0.citationStatus == .current }.count
            + noteSnippets(for: retrievalSetID).filter { $0.citationStatus == .current }.count
    }

    @discardableResult
    func saveAIProviderSettings(_ configuration: AIProviderConfiguration, credential: String) -> AIProviderConfiguration? {
        do {
            var updated = configuration
            updated.modifiedAt = Date()
            try database?.saveAIProviderConfiguration(updated)
            let trimmedCredential = credential.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedCredential.isEmpty { try KeychainSecretStore.save(trimmedCredential, for: updated.provider) }
            try reload()
            statusMessage = "AI provider settings saved; no research content was transmitted"
            return aiProviderConfiguration
        } catch {
            alertMessage = error.localizedDescription
            return nil
        }
    }

    func removeAICredential(for provider: AIProviderKind) {
        do {
            try KeychainSecretStore.delete(for: provider)
            aiCredentialStored = false
            statusMessage = "\(provider.displayName) credential removed from Keychain"
        } catch { alertMessage = error.localizedDescription }
    }

    func refreshAICredentialState(for provider: AIProviderKind) {
        aiCredentialStored = KeychainSecretStore.rememberedPresence(for: provider)
    }

    private func validatedAIEndpoint(for configuration: AIProviderConfiguration) throws -> URL {
        guard let endpoint = URL(string: configuration.endpoint) else { throw AIProviderError.invalidEndpoint }
        if configuration.provider.isLocal {
            let configured = endpoint.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let approved = configuration.provider.defaultEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard configured == approved else { throw AIProviderError.invalidEndpoint }
        } else {
            guard endpoint.scheme?.lowercased() == "https" else { throw AIProviderError.invalidEndpoint }
        }
        return endpoint
    }

    private func credentialForRequest(provider: AIProviderKind) throws -> String {
        guard provider.requiresCredential else { return "" }
        guard let credential = try KeychainSecretStore.read(for: provider) else {
            throw AIProviderError.missingCredential
        }
        return credential
    }

    private func acquireLocalRuntimeIfNeeded(_ configuration: AIProviderConfiguration) async throws -> Bool {
        guard configuration.provider == .ollamaLocal else { return false }
        statusMessage = "Preparing \(configuration.model) on this Mac…"
        try await ollamaRuntime.acquire(
            model: configuration.model,
            idleMinutes: configuration.localRuntimeIdleMinutes
        )
        return true
    }

    private func releaseLocalRuntimeIfNeeded(_ acquired: Bool, configuration: AIProviderConfiguration) {
        guard acquired else { return }
        ollamaRuntime.release(
            model: configuration.model,
            idleMinutes: configuration.localRuntimeIdleMinutes
        )
    }

    func prepareManagedLocalAIEngine() {
        let configuration = aiProviderConfiguration
        guard configuration.provider == .ollamaLocal else {
            alertMessage = "Select Local Research AI (Ollama) before starting the managed engine."
            return
        }
        isBusy = true
        Task {
            do {
                let acquired = try await acquireLocalRuntimeIfNeeded(configuration)
                releaseLocalRuntimeIfNeeded(acquired, configuration: configuration)
                statusMessage = "\(configuration.model) is ready for local research requests"
            } catch {
                alertMessage = error.localizedDescription
                statusMessage = "Local AI engine is unavailable"
            }
            isBusy = false
        }
    }

    func stopManagedLocalAIEngine() {
        let wasManaged = ollamaRuntimeManagedByApp
        ollamaRuntime.stopManagedEngine()
        if wasManaged {
            statusMessage = "Research Atlas stopped its managed local AI engine"
        } else {
            statusMessage = "Research Atlas does not own the currently running local engine"
        }
    }

    func shutdownManagedLocalAIEngine() {
        ollamaRuntime.shutdown()
    }

    func prepareGroundedAnswer(query: String, retrievalSetID: UUID?) {
        do {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedQuery.isEmpty else { throw AIProviderError.insufficientGrounding("Enter a research question before preparing a request.") }
            guard let retrievalSetID, retrievalSets.contains(where: { $0.id == retrievalSetID }) else {
                throw AIProviderError.insufficientGrounding("Choose a saved retrieval set before preparing a request.")
            }
            let configuration = aiProviderConfiguration
            guard configuration.provider != .disabled else { throw AIProviderError.disabled }
            guard configuration.externalTransmissionEnabled else { throw AIProviderError.disabled }
            let endpoint = try validatedAIEndpoint(for: configuration)
            let paperLimit = max(1, (configuration.maximumPassages * 2) / 3)
            let currentPassages = Array(passages(for: retrievalSetID)
                .filter { $0.citationStatus == .current }
                .prefix(paperLimit))
            let currentNotes = Array(noteSnippets(for: retrievalSetID)
                .filter { $0.citationStatus == .current }
                .prefix(max(0, configuration.maximumPassages - currentPassages.count)))
            let analysis = AIAnalysis(
                kind: .literatureAnswer, provider: configuration.provider.rawValue, model: configuration.model,
                promptVersion: GroundedAnswerBuilder.promptVersion, retrievalSetID: retrievalSetID,
                userQuery: trimmedQuery
            )
            let package = try GroundedAnswerBuilder.package(
                analysisID: analysis.id, query: trimmedQuery, passages: currentPassages,
                noteSnippets: currentNotes, literature: literature,
                model: configuration.model, maximumOutputTokens: configuration.maximumOutputTokens
            )
            pendingAIPackage = .grounded(analysis: analysis, package: package)
            let sourcePreviews = transmissionSourcePreviews(for: package)
            pendingAITransmission = AITransmissionPreview(
                analysisKind: .literatureAnswer, provider: configuration.provider, endpoint: endpoint.absoluteString,
                model: configuration.model,
                reasoningEffort: configuration.provider == .ollamaLocal ? configuration.reasoningEffort : nil,
                maximumOutputTokens: configuration.maximumOutputTokens,
                query: trimmedQuery, retrievalSetID: retrievalSetID,
                sourceLabels: sourcePreviews.map(\.summaryLabel),
                sourcePreviews: sourcePreviews,
                passageCount: package.citations.count + package.noteCitations.count,
                characterCount: package.characterCount
            )
            statusMessage = "Review the exact AI transmission summary before sending"
        } catch {
            pendingAIPackage = nil
            pendingAITransmission = nil
            alertMessage = error.localizedDescription
        }
    }

    func prepareAIDeliberation(for argument: ResearchArgument, retrievalSetID: UUID?) {
        do {
            let preparation = try aiPreparation(retrievalSetID: retrievalSetID)
            let session = DeliberationSession(
                argumentID: argument.id, title: "AI critical deliberation: \(argument.proposition)",
                provider: preparation.configuration.provider.rawValue, model: preparation.configuration.model,
                promptVersion: GroundedDeliberationBuilder.promptVersion,
                disclosure: "All critical perspectives were generated by the same configured model. They are simulated roles, not independent experts or independent evidence.",
                status: .prepared
            )
            let analysis = AIAnalysis(
                kind: .deliberation, provider: preparation.configuration.provider.rawValue,
                model: preparation.configuration.model, promptVersion: GroundedDeliberationBuilder.promptVersion,
                retrievalSetID: preparation.retrievalSetID, targetType: .deliberationSession,
                targetID: session.id, userQuery: argument.proposition
            )
            let package = try GroundedDeliberationBuilder.package(
                analysisID: analysis.id, argument: argument, evidence: evidence(for: argument.id),
                passages: preparation.passages, literature: literature, model: analysis.model,
                maximumOutputTokens: preparation.configuration.maximumOutputTokens
            )
            pendingAIPackage = .deliberation(analysis: analysis, session: session, package: package)
            pendingAITransmission = transmissionPreview(
                analysis: analysis, package: package, configuration: preparation.configuration,
                endpoint: preparation.endpoint, retrievalSetID: preparation.retrievalSetID
            )
            statusMessage = "Review the Argument Room transmission before sending"
        } catch {
            pendingAIPackage = nil
            pendingAITransmission = nil
            alertMessage = error.localizedDescription
        }
    }

    func prepareAIBiasAudit(for argument: ResearchArgument, retrievalSetID: UUID?) {
        do {
            let preparation = try aiPreparation(retrievalSetID: retrievalSetID)
            let audit = BiasAudit(
                argumentID: argument.id, title: "AI critical review: \(argument.proposition)",
                scopeNote: "Model-generated, source-grounded critical questions awaiting human review; this is not a diagnosis of researcher bias.",
                origin: .aiSuggested
            )
            let analysis = AIAnalysis(
                kind: .biasAudit, provider: preparation.configuration.provider.rawValue,
                model: preparation.configuration.model, promptVersion: GroundedBiasAuditBuilder.promptVersion,
                retrievalSetID: preparation.retrievalSetID, targetType: .biasAudit,
                targetID: audit.id, userQuery: argument.proposition
            )
            var linkedAudit = audit
            linkedAudit.analysisID = analysis.id
            let package = try GroundedBiasAuditBuilder.package(
                analysisID: analysis.id, argument: argument, evidence: evidence(for: argument.id),
                passages: preparation.passages, literature: literature, model: analysis.model,
                maximumOutputTokens: preparation.configuration.maximumOutputTokens
            )
            pendingAIPackage = .biasAudit(analysis: analysis, audit: linkedAudit, package: package)
            pendingAITransmission = transmissionPreview(
                analysis: analysis, package: package, configuration: preparation.configuration,
                endpoint: preparation.endpoint, retrievalSetID: preparation.retrievalSetID
            )
            statusMessage = "Review the Bias Auditor transmission before sending"
        } catch {
            pendingAIPackage = nil
            pendingAITransmission = nil
            alertMessage = error.localizedDescription
        }
    }

    func prepareAIContradictionReview(for contradiction: ContradictionCase, retrievalSetID: UUID?) {
        do {
            let preparation = try aiPreparation(retrievalSetID: retrievalSetID)
            let analysis = AIAnalysis(
                kind: .contradictionReview, provider: preparation.configuration.provider.rawValue,
                model: preparation.configuration.model, promptVersion: GroundedContradictionReviewBuilder.promptVersion,
                retrievalSetID: preparation.retrievalSetID, targetType: .contradictionCase,
                targetID: contradiction.id, userQuery: contradiction.title
            )
            let sources = contradictionSources.filter { $0.caseID == contradiction.id }
            let package = try GroundedContradictionReviewBuilder.package(
                analysisID: analysis.id, contradiction: contradiction, sources: sources,
                comparisonProfiles: comparisonProfiles, passages: preparation.passages,
                literature: literature, model: analysis.model,
                maximumOutputTokens: preparation.configuration.maximumOutputTokens
            )
            pendingAIPackage = .contradiction(analysis: analysis, caseID: contradiction.id, package: package)
            pendingAITransmission = transmissionPreview(
                analysis: analysis, package: package, configuration: preparation.configuration,
                endpoint: preparation.endpoint, retrievalSetID: preparation.retrievalSetID
            )
            statusMessage = "Review the Contradiction Detective transmission before sending"
        } catch {
            pendingAIPackage = nil
            pendingAITransmission = nil
            alertMessage = error.localizedDescription
        }
    }

    func prepareAICollectiveTurn(
        experimentID: UUID,
        agentID: UUID,
        round: Int,
        kind: CollectiveTurnKind,
        additionalInstruction: String,
        retrievalSetID: UUID?
    ) {
        do {
            guard let experiment = collectiveExperiments.first(where: { $0.id == experimentID }) else {
                throw AIProviderError.invalidResponse("The collective experiment is no longer available.")
            }
            guard let agent = agents(for: experimentID).first(where: { $0.id == agentID }) else {
                throw AIProviderError.invalidResponse("Choose a role that belongs to this experiment.")
            }
            let preparation = try aiPreparation(retrievalSetID: retrievalSetID)
            let analysis = AIAnalysis(
                kind: .collectiveTurn,
                provider: preparation.configuration.provider.rawValue,
                model: preparation.configuration.model,
                promptVersion: GroundedCollectiveTurnBuilder.promptVersion,
                retrievalSetID: preparation.retrievalSetID,
                targetType: .collectiveExperiment,
                targetID: experiment.id,
                userQuery: "\(experiment.title) — \(agent.label), round \(round), \(kind.rawValue)"
            )
            let package = try GroundedCollectiveTurnBuilder.package(
                analysisID: analysis.id,
                experiment: experiment,
                agent: agent,
                round: round,
                kind: kind,
                additionalInstruction: additionalInstruction.trimmingCharacters(in: .whitespacesAndNewlines),
                priorTurns: turns(for: experiment.id),
                passages: preparation.passages,
                literature: literature,
                model: analysis.model,
                maximumOutputTokens: preparation.configuration.maximumOutputTokens
            )
            let turn = PreparedCollectiveTurn(
                experimentID: experiment.id, agentID: agent.id, round: round, kind: kind,
                additionalInstruction: additionalInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            pendingAIPackage = .collectiveTurn(analysis: analysis, turn: turn, package: package)
            pendingAITransmission = transmissionPreview(
                analysis: analysis, package: package, configuration: preparation.configuration,
                endpoint: preparation.endpoint, retrievalSetID: preparation.retrievalSetID
            )
            statusMessage = "Review the exact Collective Intelligence Lab transmission before sending"
        } catch {
            pendingAIPackage = nil
            pendingAITransmission = nil
            alertMessage = error.localizedDescription
        }
    }

    func testAIProviderConnection() {
        let configuration = aiProviderConfiguration
        guard configuration.provider != .disabled, configuration.externalTransmissionEnabled else {
            alertMessage = "Choose an AI provider and enable external transmission before testing the connection."
            return
        }
        let endpoint: URL
        do { endpoint = try validatedAIEndpoint(for: configuration) }
        catch { alertMessage = error.localizedDescription; return }
        isBusy = true
        statusMessage = "Testing \(configuration.provider.displayName) with no research content…"
        Task {
            var acquiredLocalRuntime = false
            do {
                acquiredLocalRuntime = try await acquireLocalRuntimeIfNeeded(configuration)
                defer { releaseLocalRuntimeIfNeeded(acquiredLocalRuntime, configuration: configuration) }
                let credential = try credentialForRequest(provider: configuration.provider)
                let provider = try ConfiguredHTTPAIProvider(
                    provider: configuration.provider, endpoint: endpoint, apiKey: credential,
                    reasoningEffort: configuration.reasoningEffort,
                    localRuntimeIdleMinutes: configuration.localRuntimeIdleMinutes
                )
                let request = AIProviderRequest(
                    model: configuration.model,
                    instructions: "This is a connection test. Return the required JSON only. Do not add analysis.",
                    input: "Return status ok and the message Connection verified. No research content is included in this request.",
                    responseSchemaName: "research_atlas_connection_test",
                    responseSchema: [
                        "type": .string("object"),
                        "properties": .object([
                            "status": .object(["type": .string("string"), "enum": .array([.string("ok")])]),
                            "message": .object(["type": .string("string")])
                        ]),
                        "required": .array([.string("status"), .string("message")]),
                        "additionalProperties": .bool(false)
                    ],
                    maximumOutputTokens: configuration.provider == .ollamaLocal ? 2048 : 128
                )
                if configuration.provider == .ollamaLocal {
                    ollamaRuntime.markGenerating(model: configuration.model)
                }
                let response = try await provider.generate(request)
                guard let data = response.outputText.data(using: .utf8),
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      object["status"] as? String == "ok" else {
                    throw AIProviderError.invalidResponse("The connection test returned an unexpected structured result.")
                }
                let message = "\(configuration.provider.displayName) connection works with model \(configuration.model). No research content was sent."
                statusMessage = message
                alertMessage = message
            } catch {
                let message = "Connection test failed: \(error.localizedDescription)"
                statusMessage = message
                alertMessage = message
            }
            isBusy = false
        }
    }

    private func aiPreparation(retrievalSetID: UUID?) throws -> (
        configuration: AIProviderConfiguration,
        endpoint: URL,
        retrievalSetID: UUID,
        passages: [RetrievedPassage],
        noteSnippets: [RetrievedNoteSnippet]
    ) {
        guard let retrievalSetID, retrievalSets.contains(where: { $0.id == retrievalSetID }) else {
            throw AIProviderError.insufficientGrounding("Choose a saved retrieval set before preparing this request.")
        }
        let configuration = aiProviderConfiguration
        guard configuration.provider != .disabled, configuration.externalTransmissionEnabled else { throw AIProviderError.disabled }
        let endpoint = try validatedAIEndpoint(for: configuration)
        let paperLimit = max(1, (configuration.maximumPassages * 2) / 3)
        let current = Array(passages(for: retrievalSetID).filter { $0.citationStatus == .current }.prefix(paperLimit))
        let currentNotes = Array(noteSnippets(for: retrievalSetID).filter { $0.citationStatus == .current }
            .prefix(max(0, configuration.maximumPassages - current.count)))
        guard !current.isEmpty || !currentNotes.isEmpty else {
            throw AIProviderError.insufficientGrounding("The selected retrieval set has no current paper passages or note excerpts.")
        }
        return (configuration, endpoint, retrievalSetID, current, currentNotes)
    }

    private func transmissionPreview(
        analysis: AIAnalysis,
        package: GroundedPromptPackage,
        configuration: AIProviderConfiguration,
        endpoint: URL,
        retrievalSetID: UUID
    ) -> AITransmissionPreview {
        let sourcePreviews = transmissionSourcePreviews(for: package)
        return AITransmissionPreview(
            analysisKind: analysis.kind, provider: configuration.provider, endpoint: endpoint.absoluteString,
            model: configuration.model,
            reasoningEffort: configuration.provider == .ollamaLocal ? configuration.reasoningEffort : nil,
            maximumOutputTokens: configuration.maximumOutputTokens,
            query: analysis.userQuery, retrievalSetID: retrievalSetID,
            sourceLabels: sourcePreviews.map(\.summaryLabel),
            sourcePreviews: sourcePreviews,
            passageCount: package.citations.count + package.noteCitations.count,
            characterCount: package.characterCount
        )
    }

    private func transmissionSourcePreviews(for package: GroundedPromptPackage) -> [AITransmissionSourcePreview] {
        package.citations.map { citation in
            let title = literature.first { $0.id == citation.literatureID }?.title ?? "Unavailable source"
            return AITransmissionSourcePreview(
                label: citation.label,
                sourceClass: "Published-source passage",
                title: title,
                location: "Page \(citation.page)",
                excerpt: citation.quotedPassage
            )
        } + package.noteCitations.map { citation in
            AITransmissionSourcePreview(
                label: citation.label,
                sourceClass: "Researcher-note excerpt · not published evidence",
                title: citation.noteTitle,
                excerpt: citation.quotedSnippet
            )
        }
    }

    func cancelAITransmission() {
        pendingAITransmission = nil
        pendingAIPackage = nil
        statusMessage = "AI transmission cancelled; nothing was sent"
    }

    func confirmAITransmission(_ preview: AITransmissionPreview) {
        guard let prepared = pendingAIPackage, pendingAITransmission?.id == preview.id else { return }
        isBusy = true
        statusMessage = "Validating source snapshots before transmission…"
        Task {
            var analysis = prepared.analysis
            var didBeginExternalRequest = false
            var acquiredLocalRuntime = false
            do {
                guard aiProviderConfiguration.provider == preview.provider,
                      aiProviderConfiguration.endpoint == preview.endpoint,
                      aiProviderConfiguration.model == preview.model,
                      aiProviderConfiguration.maximumOutputTokens == preview.maximumOutputTokens,
                      (preview.provider != .ollamaLocal || aiProviderConfiguration.reasoningEffort == preview.reasoningEffort),
                      aiProviderConfiguration.externalTransmissionEnabled else {
                    throw AIProviderError.invalidResponse("Provider settings changed after the preview. Prepare the request again.")
                }
                try reload()
                let refreshed = try refreshedPackage(for: prepared, preview: preview)
                let approvedSnapshot = prepared.package.citations.map { ($0.sourcePassageID, $0.quotedPassage, $0.sourceDocumentHash) }
                let currentSnapshot = refreshed.citations.map { ($0.sourcePassageID, $0.quotedPassage, $0.sourceDocumentHash) }
                let approvedNotes = prepared.package.noteCitations.map { ($0.noteID, $0.quotedSnippet, $0.sourceModifiedAt) }
                let currentNotes = refreshed.noteCitations.map { ($0.noteID, $0.quotedSnippet, $0.sourceModifiedAt) }
                guard approvedSnapshot.elementsEqual(currentSnapshot, by: { lhs, rhs in
                    lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2
                }), approvedNotes.elementsEqual(currentNotes, by: { lhs, rhs in
                    lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2
                }), refreshed.request.input == prepared.package.request.input,
                    refreshed.request.maximumOutputTokens == prepared.package.request.maximumOutputTokens else {
                    throw AIProviderError.invalidResponse("The approved research context or retrieval evidence changed after the preview. Review a new transmission preview before sending.")
                }
                try database?.saveAIAnalysis(analysis, citations: refreshed.citations, noteCitations: refreshed.noteCitations)
                try persistPreparedTargetBeforeSend(prepared)
                acquiredLocalRuntime = try await acquireLocalRuntimeIfNeeded(aiProviderConfiguration)
                defer { releaseLocalRuntimeIfNeeded(acquiredLocalRuntime, configuration: aiProviderConfiguration) }
                let credential = try credentialForRequest(provider: preview.provider)
                guard let endpoint = URL(string: preview.endpoint) else { throw AIProviderError.invalidEndpoint }
                let provider = try ConfiguredHTTPAIProvider(
                    provider: preview.provider, endpoint: endpoint, apiKey: credential,
                    reasoningEffort: aiProviderConfiguration.reasoningEffort,
                    localRuntimeIdleMinutes: aiProviderConfiguration.localRuntimeIdleMinutes
                )
                analysis.transmittedPassageCount = refreshed.citations.count + refreshed.noteCitations.count
                analysis.transmittedCharacterCount = refreshed.characterCount
                try database?.saveAIAnalysis(
                    analysis, citations: refreshed.citations, noteCitations: refreshed.noteCitations
                )
                statusMessage = "Sending \(refreshed.citations.count + refreshed.noteCitations.count) approved source snapshots…"
                didBeginExternalRequest = true
                if preview.provider == .ollamaLocal {
                    ollamaRuntime.markGenerating(model: preview.model)
                }
                let response = try await provider.generate(refreshed.request)
                try persistCompletedAIResponse(
                    response, prepared: prepared, refreshed: refreshed, analysis: &analysis
                )
                try reload()
            } catch {
                analysis.status = if case AIProviderError.refused = error { .refused } else { .failed }
                analysis.errorMessage = error.localizedDescription
                analysis.completedAt = Date()
                if !didBeginExternalRequest {
                    analysis.transmittedPassageCount = 0
                    analysis.transmittedCharacterCount = 0
                }
                try? database?.saveAIAnalysis(
                    analysis, citations: prepared.package.citations,
                    noteCitations: prepared.package.noteCitations
                )
                try? markPreparedTargetFailed(prepared, message: error.localizedDescription)
                try? reload()
                alertMessage = error.localizedDescription
                statusMessage = "AI analysis did not complete"
            }
            pendingAITransmission = nil
            pendingAIPackage = nil
            isBusy = false
        }
    }

    private func refreshedPackage(for prepared: PreparedAIRequest, preview: AITransmissionPreview) throws -> GroundedPromptPackage {
        let paperLimit = max(1, (aiProviderConfiguration.maximumPassages * 2) / 3)
        let currentPassages = Array(passages(for: preview.retrievalSetID)
            .filter { $0.citationStatus == .current }.prefix(paperLimit))
        let currentNotes = Array(noteSnippets(for: preview.retrievalSetID)
            .filter { $0.citationStatus == .current }
            .prefix(max(0, aiProviderConfiguration.maximumPassages - currentPassages.count)))
        switch prepared {
        case .grounded(let analysis, _):
            return try GroundedAnswerBuilder.package(
                analysisID: analysis.id, query: analysis.userQuery, passages: currentPassages,
                noteSnippets: currentNotes,
                literature: literature, model: analysis.model,
                maximumOutputTokens: aiProviderConfiguration.maximumOutputTokens
            )
        case .deliberation(let analysis, let session, _):
            guard let argument = arguments.first(where: { $0.id == session.argumentID }) else {
                throw AIProviderError.invalidResponse("The argument was removed after the transmission preview.")
            }
            return try GroundedDeliberationBuilder.package(
                analysisID: analysis.id, argument: argument, evidence: evidence(for: argument.id),
                passages: currentPassages, literature: literature, model: analysis.model,
                maximumOutputTokens: aiProviderConfiguration.maximumOutputTokens
            )
        case .biasAudit(let analysis, let audit, _):
            guard let argument = arguments.first(where: { $0.id == audit.argumentID }) else {
                throw AIProviderError.invalidResponse("The argument was removed after the transmission preview.")
            }
            return try GroundedBiasAuditBuilder.package(
                analysisID: analysis.id, argument: argument, evidence: evidence(for: argument.id),
                passages: currentPassages, literature: literature, model: analysis.model,
                maximumOutputTokens: aiProviderConfiguration.maximumOutputTokens
            )
        case .contradiction(let analysis, let caseID, _):
            guard let contradiction = contradictionCases.first(where: { $0.id == caseID }) else {
                throw AIProviderError.invalidResponse("The contradiction case was removed after the transmission preview.")
            }
            return try GroundedContradictionReviewBuilder.package(
                analysisID: analysis.id, contradiction: contradiction,
                sources: contradictionSources.filter { $0.caseID == caseID }, comparisonProfiles: comparisonProfiles,
                passages: currentPassages, literature: literature, model: analysis.model,
                maximumOutputTokens: aiProviderConfiguration.maximumOutputTokens
            )
        case .collectiveTurn(let analysis, let turn, _):
            guard let experiment = collectiveExperiments.first(where: { $0.id == turn.experimentID }) else {
                throw AIProviderError.invalidResponse("The collective experiment was removed after the transmission preview.")
            }
            guard let agent = agents(for: experiment.id).first(where: { $0.id == turn.agentID }) else {
                throw AIProviderError.invalidResponse("The selected collective role was removed after the transmission preview.")
            }
            return try GroundedCollectiveTurnBuilder.package(
                analysisID: analysis.id,
                experiment: experiment,
                agent: agent,
                round: turn.round,
                kind: turn.kind,
                additionalInstruction: turn.additionalInstruction,
                priorTurns: turns(for: experiment.id),
                passages: currentPassages,
                literature: literature,
                model: analysis.model,
                maximumOutputTokens: aiProviderConfiguration.maximumOutputTokens
            )
        }
    }

    private func persistPreparedTargetBeforeSend(_ prepared: PreparedAIRequest) throws {
        switch prepared {
        case .deliberation(_, var session, _):
            session.status = .inProgress
            try database?.saveDeliberationSession(session)
        case .biasAudit(_, let audit, _):
            try database?.saveBiasAudit(audit)
        case .collectiveTurn(let analysis, let turn, _):
            guard var experiment = collectiveExperiments.first(where: { $0.id == turn.experimentID }) else {
                throw AIProviderError.invalidResponse("The collective experiment is no longer available.")
            }
            experiment.provider = analysis.provider
            experiment.model = analysis.model
            experiment.modelSettingsJSON = "{\"maximum_output_tokens\":\(aiProviderConfiguration.maximumOutputTokens),\"reasoning_effort\":\"\(aiProviderConfiguration.reasoningEffort.rawValue)\"}"
            experiment.promptVersion = analysis.promptVersion
            experiment.status = .running
            experiment.completedAt = nil
            try database?.saveCollectiveExperiment(experiment)
        case .grounded, .contradiction:
            break
        }
    }

    private func markPreparedTargetFailed(_ prepared: PreparedAIRequest, message: String) throws {
        switch prepared {
        case .deliberation(_, var session, _):
            session.status = .failed
            session.completedAt = Date()
            session.disclosure += " The model request did not complete: \(message)"
            try database?.saveDeliberationSession(session)
            selectedDeliberationSessionID = session.id
        case .biasAudit(_, var audit, _):
            audit.scopeNote = "The model request did not complete. No model concerns were accepted: \(message)"
            try database?.saveBiasAudit(audit)
            selectedBiasAuditID = audit.id
        case .collectiveTurn(let analysis, let request, let package):
            if var experiment = collectiveExperiments.first(where: { $0.id == request.experimentID }) {
                experiment.provider = analysis.provider
                experiment.model = analysis.model
                experiment.modelSettingsJSON = "{\"maximum_output_tokens\":\(aiProviderConfiguration.maximumOutputTokens),\"reasoning_effort\":\"\(aiProviderConfiguration.reasoningEffort.rawValue)\"}"
                experiment.promptVersion = analysis.promptVersion
                experiment.status = .interrupted
                try database?.saveCollectiveExperiment(experiment)
            }
            let sequence = (turns(for: request.experimentID).map(\.sequence).max() ?? 0) + 1
            try database?.saveCollectiveTurn(CollectiveTurn(
                experimentID: request.experimentID,
                agentID: request.agentID,
                round: request.round,
                sequence: sequence,
                kind: .interruption,
                promptText: package.request.input,
                responseText: "Model turn did not complete: \(message)",
                modelGenerated: false,
                errorMessage: message
            ))
            selectedCollectiveExperimentID = request.experimentID
        case .grounded, .contradiction:
            break
        }
    }

    private func persistCompletedAIResponse(
        _ response: AIProviderResponse,
        prepared: PreparedAIRequest,
        refreshed: GroundedPromptPackage,
        analysis: inout AIAnalysis
    ) throws {
        let allowed = Set(refreshed.citations.map(\.label) + refreshed.noteCitations.map(\.label))
        analysis.structuredResponseJSON = response.outputText
        analysis.inputTokens = response.inputTokens
        analysis.outputTokens = response.outputTokens
        analysis.completedAt = Date()

        switch prepared {
        case .grounded:
            let answer = try GroundedAnswerBuilder.decodeAndValidate(response.outputText, allowedCitationLabels: allowed)
            analysis.responseText = answer.answer
            analysis.status = answer.insufficientEvidence ? .insufficientEvidence : .completed
            try database?.saveAIAnalysis(analysis, citations: refreshed.citations, noteCitations: refreshed.noteCitations)
            latestGroundedAnswer = answer
            selectedAIAnalysisID = analysis.id
            statusMessage = answer.insufficientEvidence
                ? "The assistant declined to answer because the evidence was insufficient"
                : "Grounded answer saved for human review"

        case .deliberation(_, var session, _):
            let output = try GroundedDeliberationBuilder.decodeAndValidate(response.outputText, allowedCitationLabels: allowed)
            analysis.responseText = output.insufficientEvidence ? output.insufficiencyReason : output.synthesis.content
            analysis.status = output.insufficientEvidence ? .insufficientEvidence : .completed
            try database?.saveAIAnalysis(analysis, citations: refreshed.citations, noteCitations: refreshed.noteCitations)
            if output.insufficientEvidence {
                session.status = .failed
                session.completedAt = Date()
            } else {
                let roleOrder: [DeliberationPerspective] = [.theoretical, .methodological, .evidence, .alternative]
                var sequence = 1
                for perspective in roleOrder {
                    guard let role = output.roles.first(where: { $0.perspective == perspective }) else { continue }
                    for (phase, contribution) in [
                        (DeliberationPhase.initial, role.initialAssessment),
                        (.crossExamination, role.crossExamination),
                        (.revision, role.revisedAssessment)
                    ] {
                        let message = DeliberationMessage(
                            sessionID: session.id, perspective: perspective, phase: phase,
                            content: contributionText(contribution), sequence: sequence, modelGenerated: true
                        )
                        try database?.saveDeliberationMessage(
                            message,
                            citations: deliberationCitations(
                                labels: contribution.citations, messageID: message.id, sourceCitations: refreshed.citations
                            )
                        )
                        sequence += 1
                    }
                }
                let synthesis = DeliberationMessage(
                    sessionID: session.id, perspective: .synthesis, phase: .synthesis,
                    content: contributionText(output.synthesis), sequence: sequence, modelGenerated: true
                )
                try database?.saveDeliberationMessage(
                    synthesis,
                    citations: deliberationCitations(
                        labels: output.synthesis.citations, messageID: synthesis.id, sourceCitations: refreshed.citations
                    )
                )
                session.status = .inProgress
            }
            try database?.saveDeliberationSession(session)
            selectedDeliberationSessionID = session.id
            statusMessage = output.insufficientEvidence
                ? "Argument Room recorded insufficient evidence; no perspectives were accepted"
                : "Grounded model perspectives saved for researcher response"

        case .biasAudit(_, var audit, _):
            let output = try GroundedBiasAuditBuilder.decodeAndValidate(response.outputText, allowedCitationLabels: allowed)
            analysis.responseText = output.insufficientEvidence
                ? output.insufficiencyReason
                : output.concerns.map(\.potentialProblem).joined(separator: "\n")
            analysis.status = output.insufficientEvidence ? .insufficientEvidence : .completed
            try database?.saveAIAnalysis(analysis, citations: refreshed.citations, noteCitations: refreshed.noteCitations)
            audit.scopeNote = output.insufficientEvidence
                ? "The configured model reported insufficient evidence: \(output.insufficiencyReason)"
                : "Model-generated, source-grounded critical questions awaiting human review; this is not a diagnosis of researcher bias."
            try database?.saveBiasAudit(audit)
            if !output.insufficientEvidence {
                for item in output.concerns {
                    let sourceNote = item.citations.map { "[\($0)]" }.joined(separator: " ")
                    try database?.saveBiasConcern(BiasConcern(
                        auditID: audit.id, kind: item.kind, potentialProblem: item.potentialProblem,
                        whyItMatters: item.whyItMatters,
                        alternativeInterpretations: item.alternativeInterpretations,
                        investigationQuestions: item.investigationQuestions,
                        uncertainty: "\(item.uncertainty) Source snapshots: \(sourceNote)",
                        origin: .aiSuggested
                    ))
                }
            }
            selectedBiasAuditID = audit.id
            statusMessage = output.insufficientEvidence
                ? "Bias Auditor recorded insufficient evidence; no concerns were accepted"
                : "AI critical questions saved as suggestions for human review"

        case .contradiction(_, let caseID, _):
            let output = try GroundedContradictionReviewBuilder.decodeAndValidate(response.outputText, allowedCitationLabels: allowed)
            analysis.responseText = output.insufficientEvidence ? output.insufficiencyReason : output.assessment
            analysis.status = output.insufficientEvidence ? .insufficientEvidence : .completed
            try database?.saveAIAnalysis(analysis, citations: refreshed.citations, noteCitations: refreshed.noteCitations)
            selectedContradictionCaseID = caseID
            statusMessage = output.insufficientEvidence
                ? "Contradiction review recorded insufficient evidence"
                : "Contradiction assessment saved as a model suggestion for human review"

        case .collectiveTurn(_, let request, _):
            let output = try GroundedCollectiveTurnBuilder.decodeAndValidate(
                response.outputText, allowedCitationLabels: allowed
            )
            analysis.responseText = output.insufficientEvidence ? output.insufficiencyReason : output.response
            analysis.status = output.insufficientEvidence ? .insufficientEvidence : .completed
            try database?.saveAIAnalysis(
                analysis, citations: refreshed.citations, noteCitations: refreshed.noteCitations
            )
            guard let agent = agents(for: request.experimentID).first(where: { $0.id == request.agentID }) else {
                throw AIProviderError.invalidResponse("The selected collective role is no longer available.")
            }
            let sequence = (turns(for: request.experimentID).map(\.sequence).max() ?? 0) + 1
            let turn = CollectiveTurn(
                experimentID: request.experimentID,
                agentID: agent.id,
                round: request.round,
                sequence: sequence,
                kind: request.kind,
                informationAvailable: agent.informationAvailable,
                promptText: refreshed.request.input,
                responseText: output.insufficientEvidence
                    ? "Insufficient evidence: \(output.insufficiencyReason)\n\nUncertainty: \(output.uncertainty)"
                    : "\(output.response)\n\nUncertainty: \(output.uncertainty)",
                confidence: output.insufficientEvidence ? nil : output.confidence,
                modelGenerated: true
            )
            let byLabel = Dictionary(uniqueKeysWithValues: refreshed.citations.map { ($0.label, $0) })
            let citations = output.citations.compactMap { label -> CollectiveTurnCitation? in
                guard let citation = byLabel[label] else { return nil }
                return CollectiveTurnCitation(
                    turnID: turn.id,
                    label: label,
                    literatureID: citation.literatureID,
                    sourcePassageID: citation.sourcePassageID,
                    page: citation.page,
                    quotedPassage: citation.quotedPassage,
                    sourceDocumentHash: citation.sourceDocumentHash,
                    citationStatus: citation.citationStatus
                )
            }
            try database?.saveCollectiveTurn(turn, citations: citations)
            if var experiment = collectiveExperiments.first(where: { $0.id == request.experimentID }) {
                experiment.status = .running
                try database?.saveCollectiveExperiment(experiment)
            }
            selectedCollectiveExperimentID = request.experimentID
            statusMessage = output.insufficientEvidence
                ? "Collective role recorded an evidence gap; no substantive answer was accepted"
                : "Grounded collective-role turn saved with exact model and source provenance"
        }
    }

    private func contributionText(_ contribution: GroundedDeliberationContribution) -> String {
        let sources = contribution.citations.map { "[\($0)]" }.joined(separator: " ")
        return "\(contribution.content)\n\nUncertainty: \(contribution.uncertainty)\nSources: \(sources)"
    }

    private func deliberationCitations(
        labels: [String],
        messageID: UUID,
        sourceCitations: [AIAnalysisCitation]
    ) -> [DeliberationCitation] {
        let byLabel = Dictionary(uniqueKeysWithValues: sourceCitations.map { ($0.label, $0) })
        return labels.compactMap { label in
            guard let citation = byLabel[label] else { return nil }
            return DeliberationCitation(
                messageID: messageID, label: label, literatureID: citation.literatureID,
                sourcePassageID: citation.sourcePassageID, page: citation.page,
                quotedPassage: citation.quotedPassage, sourceDocumentHash: citation.sourceDocumentHash,
                citationStatus: citation.citationStatus
            )
        }
    }

    func groundedAnswer(for analysis: AIAnalysis) -> GroundedAnswer? {
        guard !analysis.structuredResponseJSON.isEmpty else { return nil }
        return try? JSONDecoder().decode(GroundedAnswer.self, from: Data(analysis.structuredResponseJSON.utf8))
    }

    func biasAuditOutput(for analysis: AIAnalysis) -> GroundedBiasAuditOutput? {
        guard analysis.kind == .biasAudit, !analysis.structuredResponseJSON.isEmpty else { return nil }
        return try? JSONDecoder().decode(GroundedBiasAuditOutput.self, from: Data(analysis.structuredResponseJSON.utf8))
    }

    func contradictionOutput(for analysis: AIAnalysis) -> GroundedContradictionReviewOutput? {
        guard analysis.kind == .contradictionReview, !analysis.structuredResponseJSON.isEmpty else { return nil }
        return try? JSONDecoder().decode(GroundedContradictionReviewOutput.self, from: Data(analysis.structuredResponseJSON.utf8))
    }

    func analyses(targetType: AIAnalysisTargetType, targetID: UUID) -> [AIAnalysis] {
        aiAnalyses.filter { $0.targetType == targetType && $0.targetID == targetID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func citations(forDeliberationMessage messageID: UUID) -> [DeliberationCitation] {
        deliberationCitations.filter { $0.messageID == messageID }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    func openDeliberationCitation(_ citation: DeliberationCitation) {
        selectedLiteratureID = citation.literatureID
        readingEvidenceTarget = nil
        readingPassageTarget = RetrievedPassage(
            retrievalSetID: UUID(), sourcePassageID: citation.sourcePassageID,
            literatureID: citation.literatureID, page: citation.page,
            passageText: citation.quotedPassage, extractionMethod: "Argument Room citation snapshot",
            sourceIndexedAt: Date(), sourceDocumentHash: citation.sourceDocumentHash,
            rank: 0, citationStatus: citation.citationStatus
        )
        selectedSection = .reading
    }

    func citations(forAnalysis analysisID: UUID) -> [AIAnalysisCitation] {
        aiAnalysisCitations.filter { $0.analysisID == analysisID }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    func noteCitations(forAnalysis analysisID: UUID) -> [AIAnalysisNoteCitation] {
        aiAnalysisNoteCitations.filter { $0.analysisID == analysisID }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    func openAnalysisCitation(_ citation: AIAnalysisCitation) {
        selectedLiteratureID = citation.literatureID
        readingEvidenceTarget = nil
        readingPassageTarget = RetrievedPassage(
            retrievalSetID: UUID(), sourcePassageID: citation.sourcePassageID,
            literatureID: citation.literatureID, page: citation.page, passageText: citation.quotedPassage,
            extractionMethod: "AI analysis citation snapshot", sourceIndexedAt: Date(),
            sourceDocumentHash: citation.sourceDocumentHash, rank: 0, citationStatus: citation.citationStatus
        )
        selectedSection = .reading
    }

    func openNoteCitation(_ citation: AIAnalysisNoteCitation) {
        let url = URL(fileURLWithPath: citation.notePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            alertMessage = "The cited Obsidian note is no longer available at \(citation.notePath). The saved excerpt remains in the analysis record."
            return
        }
        NSWorkspace.shared.open(url)
    }

    func review(forAnalysis analysisID: UUID) -> AnalysisReview? {
        analysisReviews.first { $0.analysisID == analysisID }
    }

    func saveAnalysisReview(analysisID: UUID, decision: AnalysisReviewDecision, notes: String) {
        do {
            let existing = review(forAnalysis: analysisID)
            try database?.saveAnalysisReview(AnalysisReview(
                id: existing?.id ?? UUID(), analysisID: analysisID, decision: decision,
                notes: notes, reviewedAt: Date()
            ))
            try reload()
            statusMessage = "Human review recorded"
        } catch { alertMessage = error.localizedDescription }
    }

    func saveGroundedAnswerClaims(from analysis: AIAnalysis) {
        do {
            guard analysis.status == .completed, let answer = groundedAnswer(for: analysis), !answer.insufficientEvidence else {
                throw AIProviderError.insufficientGrounding("Only a completed, grounded answer can produce candidate claims.")
            }
            let citationsByLabel = Dictionary(uniqueKeysWithValues: citations(forAnalysis: analysis.id).map { ($0.label, $0) })
            var saved = 0
            for candidate in answer.claims {
                let currentPaperCitations = candidate.citations.compactMap { citationsByLabel[$0] }
                    .filter { $0.citationStatus == .current }
                guard let citation = currentPaperCitations.first else { continue }
                let additional = candidate.citations.filter { $0 != citation.label }.joined(separator: ", ")
                let notes = [
                    "Generated from Research Assistant analysis \(analysis.id.uuidString).",
                    "Citation labels: \(candidate.citations.joined(separator: ", ")).",
                    candidate.interpretation ? "This candidate is an interpretation or synthesis." : "This candidate reports the supplied source passage.",
                    candidate.citations.contains(where: { $0.hasPrefix("N") }) ? "Researcher-note citations remain contextual analysis provenance and are not treated as published evidence for this claim." : nil,
                    additional.isEmpty ? nil : "Additional cited passages: \(additional)."
                ].compactMap { $0 }.joined(separator: " ")
                try database?.saveClaim(ResearchClaim(
                    claimText: candidate.text, category: .aiSuggestion, literatureID: citation.literatureID,
                    sourcePassageID: citation.sourcePassageID, page: citation.page,
                    quotedSourceText: citation.quotedPassage, extractionMethod: .aiCandidate,
                    modelIdentifier: analysis.model, promptVersion: analysis.promptVersion,
                    verification: .unverified, userNotes: notes
                ))
                saved += 1
            }
            guard saved > 0 else {
                throw AIProviderError.insufficientGrounding("This answer has no current paper-backed claims to convert. Researcher-note-only claims remain in the reviewed analysis and are not converted into literature claims.")
            }
            try reload()
            selectedClaimID = claims.first { $0.userNotes.contains(analysis.id.uuidString) }?.id
            statusMessage = "Saved \(saved) AI-generated candidate claim\(saved == 1 ? "" : "s") as unverified"
        } catch { alertMessage = error.localizedDescription }
    }

    func openRetrievedPassage(_ passage: RetrievedPassage) {
        selectedLiteratureID = passage.literatureID
        readingEvidenceTarget = nil
        readingPassageTarget = passage
        selectedSection = .reading
    }

    func openRetrievedNote(_ note: RetrievedNoteSnippet) {
        let url = URL(fileURLWithPath: note.notePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            alertMessage = "The Obsidian note is no longer available at \(note.notePath). The saved excerpt remains in this retrieval set."
            return
        }
        NSWorkspace.shared.open(url)
    }

    func saveConcept(name: String, definition: String, notes: String, verification: VerificationState = .unverified) {
        do {
            let concept = ResearchConcept(name: name, definition: definition, notes: notes, verification: verification)
            try database?.saveConcept(concept)
            try reload()
            statusMessage = "Concept saved"
        } catch { alertMessage = error.localizedDescription }
    }

    func deleteConcept(_ concept: ResearchConcept) {
        do {
            try database?.deleteConcept(id: concept.id)
            try reload()
            statusMessage = "Concept and its relationships deleted"
        } catch { alertMessage = error.localizedDescription }
    }

    func saveKnowledgeRelationship(_ relationship: KnowledgeRelationship) {
        do {
            try database?.saveKnowledgeRelationship(relationship)
            try reload()
            statusMessage = "Knowledge relationship saved"
        } catch { alertMessage = error.localizedDescription }
    }

    func deleteKnowledgeRelationship(_ relationship: KnowledgeRelationship) {
        do {
            try database?.deleteKnowledgeRelationship(id: relationship.id)
            try reload()
            statusMessage = "Knowledge relationship deleted"
        } catch { alertMessage = error.localizedDescription }
    }

    func saveIdea(_ idea: ResearchIdea, changeNote: String? = nil) {
        do {
            var updated = idea
            updated.modifiedAt = Date()
            try database?.saveIdea(updated, changeNote: changeNote)
            try reload()
            selectedIdeaID = updated.id
            statusMessage = changeNote == nil ? "Research idea saved" : "Research idea revised and version recorded"
        } catch { alertMessage = error.localizedDescription }
    }

    func deleteIdea(_ idea: ResearchIdea) {
        do {
            try database?.deleteIdea(id: idea.id)
            try reload()
            statusMessage = "Research idea deleted"
        } catch { alertMessage = error.localizedDescription }
    }

    func saveIdeaLink(_ link: ResearchIdeaLink) {
        do {
            try database?.saveIdeaLink(link)
            try reload()
            statusMessage = "Source linked to research idea"
        } catch { alertMessage = error.localizedDescription }
    }

    func deleteIdeaLink(_ link: ResearchIdeaLink) {
        do {
            try database?.deleteIdeaLink(id: link.id)
            try reload()
        } catch { alertMessage = error.localizedDescription }
    }

    func challengeQuestions(for idea: ResearchIdea) -> [String] {
        var questions: [String] = []
        if idea.assumptions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            questions.append("What assumptions does this idea depend on?")
        }
        let links = ideaLinks.filter { $0.ideaID == idea.id }
        if !links.contains(where: { $0.targetType == .literature || $0.targetType == .passage }) {
            questions.append("Which source evidence supports this idea, and where is the relevant passage?")
        }
        if idea.alternativeExplanations.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            questions.append("What plausible alternative explanations could produce the same observation?")
        }
        if !links.contains(where: { $0.targetType == .concept }) {
            questions.append("Which constructs require a precise definition before this idea can be evaluated?")
        }
        if idea.evidenceNeeded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            questions.append("What evidence would change or falsify this interpretation?")
        }
        if idea.investigationNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            questions.append("Could this idea be investigated empirically, and with what design?")
        }
        return questions.isEmpty ? ["Review whether the linked evidence still supports the idea after its latest revision."] : questions
    }

    func ideaLinkOptions(for type: IdeaLinkTargetType) -> [(id: String, label: String)] {
        switch type {
        case .literature: return literature.map { ($0.id.uuidString, $0.title) }
        case .passage:
            var seen = Set<String>()
            return retrievedPassages.filter { seen.insert($0.sourcePassageID).inserted }.map { passage in
                let title = literature.first { item in item.id == passage.literatureID }?.title ?? "Unavailable source"
                return (passage.sourcePassageID, "\(title), p. \(passage.page)")
            }
        case .note: return notes.map { ($0.id.uuidString, $0.title) }
        case .concept: return concepts.map { ($0.id.uuidString, $0.name) }
        case .argument: return arguments.map { ($0.id.uuidString, $0.proposition) }
        }
    }

    func ideaLinkLabel(_ link: ResearchIdeaLink) -> String {
        ideaLinkOptions(for: link.targetType).first { $0.id == link.targetID }?.label ?? "Unavailable \(link.targetType.rawValue.lowercased())"
    }

    func saveContradictionCase(_ contradiction: ContradictionCase) {
        do {
            var updated = contradiction
            updated.modifiedAt = Date()
            try database?.saveContradictionCase(updated)
            try reload()
            selectedContradictionCaseID = updated.id
            statusMessage = "Contradiction review saved"
        } catch { alertMessage = error.localizedDescription }
    }

    func deleteContradictionCase(_ contradiction: ContradictionCase) {
        do {
            try database?.deleteContradictionCase(id: contradiction.id)
            try reload()
            statusMessage = "Contradiction review deleted"
        } catch { alertMessage = error.localizedDescription }
    }

    func saveContradictionSource(_ source: ContradictionSource) {
        do {
            try database?.saveContradictionSource(source)
            try reload()
            statusMessage = "Comparison source added"
        } catch { alertMessage = error.localizedDescription }
    }

    func deleteContradictionSource(_ source: ContradictionSource) {
        do {
            try database?.deleteContradictionSource(id: source.id)
            try reload()
        } catch { alertMessage = error.localizedDescription }
    }

    func createLocalBiasAudit(for argument: ResearchArgument) {
        do {
            let draft = LocalBiasAuditor.makeDraft(
                argument: argument, evidence: evidence(for: argument.id), literature: literature,
                comparisonProfiles: comparisonProfiles
            )
            try database?.saveBiasAudit(draft.audit)
            for concern in draft.concerns { try database?.saveBiasConcern(concern) }
            try reload()
            selectedBiasAuditID = draft.audit.id
            statusMessage = "Created a local critical review with \(draft.concerns.count) investigation prompt\(draft.concerns.count == 1 ? "" : "s")"
        } catch { alertMessage = error.localizedDescription }
    }

    func concerns(for auditID: UUID) -> [BiasConcern] {
        biasConcerns.filter { $0.auditID == auditID }.sorted { $0.createdAt < $1.createdAt }
    }

    func saveBiasConcernReview(_ concern: BiasConcern, disposition: ReviewDisposition, notes: String) {
        do {
            var updated = concern
            updated.disposition = disposition
            updated.reviewNotes = notes
            updated.modifiedAt = Date()
            try database?.saveBiasConcern(updated)
            try reload()
            statusMessage = "Critical-review decision saved"
        } catch { alertMessage = error.localizedDescription }
    }

    func deleteBiasAudit(_ audit: BiasAudit) {
        do {
            try database?.deleteBiasAudit(id: audit.id)
            try reload()
            statusMessage = "Bias-audit record deleted; argument and evidence were unchanged"
        } catch { alertMessage = error.localizedDescription }
    }

    func createLocalDeliberation(for argument: ResearchArgument) {
        do {
            let scaffold = LocalDeliberationScaffoldBuilder.make(argument: argument, evidence: evidence(for: argument.id))
            try database?.saveDeliberationSession(scaffold.session)
            for message in scaffold.messages { try database?.saveDeliberationMessage(message) }
            try reload()
            selectedDeliberationSessionID = scaffold.session.id
            statusMessage = "Created a local critical-deliberation scaffold; no model was invoked"
        } catch { alertMessage = error.localizedDescription }
    }

    func messages(for sessionID: UUID) -> [DeliberationMessage] {
        deliberationMessages.filter { $0.sessionID == sessionID }.sorted { $0.sequence < $1.sequence }
    }

    func addResearcherResponse(sessionID: UUID, text: String) {
        do {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let sequence = (messages(for: sessionID).map(\.sequence).max() ?? 0) + 1
            try database?.saveDeliberationMessage(DeliberationMessage(
                sessionID: sessionID, perspective: .user, phase: .userResponse,
                content: trimmed, sequence: sequence, modelGenerated: false
            ))
            if var session = deliberationSessions.first(where: { $0.id == sessionID }) {
                session.status = .inProgress
                try database?.saveDeliberationSession(session)
            }
            try reload()
            statusMessage = "Researcher response added to the deliberation record"
        } catch { alertMessage = error.localizedDescription }
    }

    func completeDeliberation(_ session: DeliberationSession) {
        do {
            var updated = session
            updated.status = .completed
            updated.completedAt = Date()
            try database?.saveDeliberationSession(updated)
            try reload()
            statusMessage = "Deliberation marked complete"
        } catch { alertMessage = error.localizedDescription }
    }

    func deleteDeliberation(_ session: DeliberationSession) {
        do {
            try database?.deleteDeliberationSession(id: session.id)
            try reload()
            statusMessage = "Deliberation record deleted; source arguments and evidence were unchanged"
        } catch { alertMessage = error.localizedDescription }
    }

    func saveWritingDocument(_ document: WritingDocument) {
        do {
            var updated = document
            updated.modifiedAt = Date()
            try database?.saveWritingDocument(updated)
            try reload()
            selectedWritingDocumentID = updated.id
            statusMessage = "Writing workspace saved"
        } catch { alertMessage = error.localizedDescription }
    }

    func deleteWritingDocument(_ document: WritingDocument) {
        do {
            try database?.deleteWritingDocument(id: document.id)
            try reload()
            statusMessage = "Application-owned writing workspace deleted"
        } catch { alertMessage = error.localizedDescription }
    }

    func sections(for documentID: UUID) -> [WritingSection] {
        writingSections.filter { $0.documentID == documentID }.sorted { $0.position < $1.position }
    }

    func saveWritingSection(_ section: WritingSection) {
        do {
            var updated = section
            updated.modifiedAt = Date()
            try database?.saveWritingSection(updated)
            try reload()
            selectedWritingSectionID = updated.id
            statusMessage = "Writing section saved"
        } catch { alertMessage = error.localizedDescription }
    }

    func addWritingSection(documentID: UUID, title: String) {
        let position = (sections(for: documentID).map(\.position).max() ?? 0) + 1
        saveWritingSection(WritingSection(documentID: documentID, title: title, position: position))
    }

    func deleteWritingSection(_ section: WritingSection) {
        do {
            try database?.deleteWritingSection(id: section.id)
            try reload()
            statusMessage = "Writing section deleted"
        } catch { alertMessage = error.localizedDescription }
    }

    func writingLinks(for sectionID: UUID) -> [WritingEvidenceLink] {
        writingEvidenceLinks.filter { $0.sectionID == sectionID }
    }

    func citationReviews(for sectionID: UUID) -> [CitationSupportReview] {
        citationSupportReviews.filter { $0.sectionID == sectionID }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func saveWritingEvidenceLink(_ link: WritingEvidenceLink) {
        do {
            try database?.saveWritingEvidenceLink(link)
            try reload()
            statusMessage = "Evidence linked to writing section"
        } catch { alertMessage = error.localizedDescription }
    }

    func deleteWritingEvidenceLink(_ link: WritingEvidenceLink) {
        do {
            try database?.deleteWritingEvidenceLink(id: link.id)
            try reload()
        } catch { alertMessage = error.localizedDescription }
    }

    func writingTargetOptions(for type: WritingEvidenceTargetType) -> [(id: String, label: String, citationKey: String?)] {
        switch type {
        case .claim:
            return claims.map { ($0.id.uuidString, $0.claimText, $0.literatureID.flatMap { id in literature.first { $0.id == id }?.citationKey }) }
        case .argumentEvidence:
            return evidenceRecords.map { evidence in
                let source = literature.first { $0.id == evidence.literatureID }
                return (evidence.id.uuidString, "\(evidence.relation.rawValue): \(evidence.summary)", source?.citationKey)
            }
        case .literature: return literature.map { ($0.id.uuidString, $0.title, $0.citationKey) }
        case .argument: return arguments.map { ($0.id.uuidString, $0.proposition, nil) }
        }
    }

    func writingTargetLabel(_ link: WritingEvidenceLink) -> String {
        writingTargetOptions(for: link.targetType).first { $0.id == link.targetID }?.label ?? "Unavailable \(link.targetType.rawValue.lowercased())"
    }

    func openWritingEvidenceLink(_ link: WritingEvidenceLink) {
        guard let id = UUID(uuidString: link.targetID) else { return }
        switch link.targetType {
        case .claim:
            if let claim = claims.first(where: { $0.id == id }) { openClaimSource(claim) }
        case .argumentEvidence:
            if let evidence = evidenceRecords.first(where: { $0.id == id }) { openEvidenceInReadingDesk(evidence) }
        case .literature:
            selectedLiteratureID = id
            selectedSection = .reading
        case .argument:
            selectedArgumentID = id
            selectedSection = .arguments
        }
    }

    func runLocalCitationSupportReview(for section: WritingSection) {
        do {
            for existing in citationReviews(for: section.id) where existing.origin == .localSuggestion {
                try database?.deleteCitationSupportReview(id: existing.id)
            }
            let links = writingLinks(for: section.id)
            let generated = LocalCitationSupportAuditor.makeReviews(
                section: section, links: links, sources: citationSupportSources(for: links)
            )
            for review in generated { try database?.saveCitationSupportReview(review) }
            try reload()
            statusMessage = generated.isEmpty
                ? "No substantial statements were found for citation review"
                : "Created \(generated.count) cautious citation-support review\(generated.count == 1 ? "" : "s")"
        } catch { alertMessage = error.localizedDescription }
    }

    private func citationSupportSources(for links: [WritingEvidenceLink]) -> [CitationSupportSourceSnapshot] {
        links.compactMap { link in
            switch link.targetType {
            case .claim:
                guard let id = UUID(uuidString: link.targetID), let claim = claims.first(where: { $0.id == id }) else { return nil }
                let text = [claim.claimText, claim.quotedSourceText, claim.methodologicalContext, claim.studyContext]
                    .filter { !$0.isEmpty }.joined(separator: "\n")
                return CitationSupportSourceSnapshot(evidenceLinkID: link.id, text: text, verification: claim.verification)
            case .argumentEvidence:
                guard let id = UUID(uuidString: link.targetID), let evidence = evidenceRecords.first(where: { $0.id == id }) else { return nil }
                let text = [evidence.summary, evidence.quotedPassage, evidence.relation.rawValue]
                    .filter { !$0.isEmpty }.joined(separator: "\n")
                return CitationSupportSourceSnapshot(evidenceLinkID: link.id, text: text, verification: evidence.verification)
            case .literature:
                guard let id = UUID(uuidString: link.targetID), let item = literature.first(where: { $0.id == id }) else { return nil }
                return CitationSupportSourceSnapshot(
                    evidenceLinkID: link.id, text: [item.title, item.abstract].filter { !$0.isEmpty }.joined(separator: "\n"),
                    verification: .unverified
                )
            case .argument:
                guard let id = UUID(uuidString: link.targetID), let argument = arguments.first(where: { $0.id == id }) else { return nil }
                return CitationSupportSourceSnapshot(
                    evidenceLinkID: link.id,
                    text: [argument.proposition, argument.qualification].filter { !$0.isEmpty }.joined(separator: "\n"),
                    verification: .unverified
                )
            }
        }
    }

    func updateCitationSupportReview(_ review: CitationSupportReview, assessment: CitationSupportAssessment, notes: String) {
        do {
            var updated = review
            updated.assessment = assessment
            updated.reviewNotes = notes
            updated.modifiedAt = Date()
            try database?.saveCitationSupportReview(updated)
            try reload()
            statusMessage = "Citation-support review updated"
        } catch { alertMessage = error.localizedDescription }
    }

    func exportWritingDocument(_ document: WritingDocument) {
        let panel = NSSavePanel()
        panel.title = "Export writing workspace as Markdown"
        panel.nameFieldStringValue = document.title.replacingOccurrences(of: "/", with: "-") + ".md"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let relevantSections = sections(for: document.id)
        var lines = ["# \(document.title)", "", "Purpose: \(document.purpose.rawValue)", "Status: \(document.status)", "", document.notes, ""]
        for section in relevantSections {
            lines += ["## \(section.title)", "", section.body, ""]
            let links = writingLinks(for: section.id)
            if !links.isEmpty {
                lines += ["### Evidence links", ""]
                for link in links {
                    let cite = link.citationKey.map { " [@\($0)]" } ?? ""
                    lines.append("- \(writingTargetLabel(link))\(cite)\(link.rationale.isEmpty ? "" : " — \(link.rationale)")")
                }
                lines.append("")
            }
        }
        do {
            try Data(lines.joined(separator: "\n").utf8).write(to: url, options: .atomic)
            statusMessage = "Writing workspace exported as Markdown"
        } catch { alertMessage = error.localizedDescription }
    }

    func saveCollectiveExperiment(_ experiment: CollectiveExperiment) {
        do {
            try database?.saveCollectiveExperiment(experiment)
            try reload()
            selectedCollectiveExperimentID = experiment.id
            statusMessage = "Simulation design saved; no model was invoked"
        } catch { alertMessage = error.localizedDescription }
    }

    func agents(for experimentID: UUID) -> [CollectiveAgent] {
        collectiveAgents.filter { $0.experimentID == experimentID }.sorted { $0.position < $1.position }
    }

    func turns(for experimentID: UUID) -> [CollectiveTurn] {
        collectiveTurns.filter { $0.experimentID == experimentID }.sorted { $0.sequence < $1.sequence }
    }

    func addCollectiveAgent(experimentID: UUID, label: String, role: String, information: String) {
        do {
            let position = (agents(for: experimentID).map(\.position).max() ?? 0) + 1
            try database?.saveCollectiveAgent(CollectiveAgent(
                experimentID: experimentID, label: label, role: role,
                informationAvailable: information, position: position
            ))
            try reload()
            statusMessage = "Simulation role added"
        } catch { alertMessage = error.localizedDescription }
    }

    func deleteCollectiveAgent(_ agent: CollectiveAgent) {
        do {
            try database?.deleteCollectiveAgent(id: agent.id)
            try reload()
            statusMessage = "Simulation role removed; any recorded turns retain an unattributed historical record"
        } catch { alertMessage = error.localizedDescription }
    }

    func addCollectiveTurn(
        experimentID: UUID, agentID: UUID?, round: Int, kind: CollectiveTurnKind,
        information: String, prompt: String, response: String, confidence: Double?,
        modelGenerated: Bool, sourcePassageID: String?
    ) {
        do {
            let sequence = (turns(for: experimentID).map(\.sequence).max() ?? 0) + 1
            let turn = CollectiveTurn(
                experimentID: experimentID, agentID: agentID, round: round, sequence: sequence,
                kind: kind, informationAvailable: information, promptText: prompt,
                responseText: response, confidence: confidence, modelGenerated: modelGenerated
            )
            var citations: [CollectiveTurnCitation] = []
            if let sourcePassageID,
               let passage = retrievedPassages.first(where: { $0.sourcePassageID == sourcePassageID && $0.citationStatus == .current }) {
                citations = [CollectiveTurnCitation(
                    turnID: turn.id, label: "S1", literatureID: passage.literatureID,
                    sourcePassageID: passage.sourcePassageID, page: passage.page,
                    quotedPassage: passage.passageText, sourceDocumentHash: passage.sourceDocumentHash
                )]
            }
            try database?.saveCollectiveTurn(turn, citations: citations)
            if var experiment = collectiveExperiments.first(where: { $0.id == experimentID }), experiment.status == .ready {
                experiment.status = .running
                try database?.saveCollectiveExperiment(experiment)
            }
            try reload()
            statusMessage = "Experimental turn recorded"
        } catch { alertMessage = error.localizedDescription }
    }

    func deleteCollectiveTurn(_ turn: CollectiveTurn) {
        do {
            try database?.deleteCollectiveTurn(id: turn.id)
            try reload()
            statusMessage = "Experimental turn deleted"
        } catch { alertMessage = error.localizedDescription }
    }

    func citations(forCollectiveTurn turnID: UUID) -> [CollectiveTurnCitation] {
        collectiveTurnCitations.filter { $0.turnID == turnID }
    }

    func completeCollectiveExperiment(_ experiment: CollectiveExperiment) {
        do {
            var updated = experiment
            updated.status = .completed
            updated.completedAt = Date()
            try database?.saveCollectiveExperiment(updated)
            try reload()
            statusMessage = "Experimental record marked complete"
        } catch { alertMessage = error.localizedDescription }
    }

    func deleteCollectiveExperiment(_ experiment: CollectiveExperiment) {
        do {
            try database?.deleteCollectiveExperiment(id: experiment.id)
            try reload()
            statusMessage = "Experimental record deleted"
        } catch { alertMessage = error.localizedDescription }
    }

    func nodeOptions(for type: KnowledgeNodeType) -> [(id: String, label: String)] {
        switch type {
        case .paper: return literature.map { ($0.id.uuidString, $0.title) }
        case .concept: return concepts.map { ($0.id.uuidString, $0.name) }
        case .argument: return arguments.map { ($0.id.uuidString, $0.proposition) }
        case .researchQuestion: return questions.map { ($0.id.uuidString, $0.question) }
        case .note: return notes.map { ($0.id.uuidString, $0.title) }
        case .claim: return claims.map { ($0.id.uuidString, $0.claimText) }
        case .idea: return ideas.map { ($0.id.uuidString, $0.title) }
        }
    }

    func nodeLabel(type: KnowledgeNodeType, id: String) -> String {
        nodeOptions(for: type).first { $0.id == id }?.label ?? "Unavailable \(type.rawValue.lowercased())"
    }

    func openKnowledgeNode(type: KnowledgeNodeType, id: String) {
        guard let uuid = UUID(uuidString: id) else { return }
        switch type {
        case .paper:
            guard let item = literature.first(where: { $0.id == uuid }) else { return }
            selectedLiteratureID = item.id
            readingEvidenceTarget = nil
            readingPassageTarget = nil
            if pdfFileAvailability(for: item) == .available {
                selectedSection = .reading
            } else {
                selectedSection = .library
                statusMessage = "This paper needs an accessible local PDF before it can open in Reading Desk"
            }
        case .argument:
            selectedArgumentID = uuid
            selectedSection = .arguments
        case .researchQuestion:
            guard let question = questions.first(where: { $0.id == uuid }) else { return }
            selectedProjectID = question.projectID
            selectedQuestionID = question.id
            selectedSection = .questions
        case .claim:
            selectedClaimID = uuid
            evidenceExplorerMode = 2
            selectedSection = .evidence
        case .idea:
            selectedIdeaID = uuid
            selectedSection = .ideas
        case .concept:
            knowledgeAtlasPresentation = 0
            requestedKnowledgeNodeType = .concept
            requestedKnowledgeNodeID = uuid.uuidString
            selectedSection = .atlas
        case .note:
            if let note = notes.first(where: { $0.id == uuid }) { openObsidianNote(note) }
        }
    }

    func noteAssociations(for literatureID: UUID) -> [(link: PaperNoteLink, note: ObsidianNote)] {
        noteLinks
            .filter {
                $0.literatureID == literatureID
                    && (titleMatchSuggestionsEnabled || $0.method != .title || $0.state == .confirmed)
            }
            .compactMap { link in notes.first(where: { $0.id == link.noteID }).map { (link, $0) } }
    }

    func linkNoteManually(_ note: ObsidianNote, to literatureID: UUID) {
        do {
            try database?.saveNoteLink(PaperNoteLink(
                noteID: note.id,
                literatureID: literatureID,
                method: .manual,
                matchedIdentifier: note.path,
                state: .confirmed
            ))
            noteLinks = try database?.noteLinks() ?? []
            statusMessage = "Obsidian note linked manually"
        } catch { alertMessage = error.localizedDescription }
    }

    func deleteNoteLink(_ link: PaperNoteLink) {
        do {
            try database?.deleteNoteLink(id: link.id)
            noteLinks = try database?.noteLinks() ?? []
            statusMessage = "Obsidian note link removed"
        } catch { alertMessage = error.localizedDescription }
    }

    func setTitleMatchSuggestionsEnabled(_ enabled: Bool) {
        titleMatchSuggestionsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "titleMatchSuggestionsEnabled")
        guard enabled else {
            statusMessage = "Title-based suggestions hidden"
            return
        }
        do {
            guard let database else { return }
            for suggestion in NoteMatcher.suggestions(notes: notes, literature: literature, includeTitleMatches: true) {
                try database.saveNoteLinkSuggestion(suggestion)
            }
            noteLinks = try database.noteLinks()
            statusMessage = "Optional title suggestions updated"
        } catch { alertMessage = error.localizedDescription }
    }

    func reviewNoteLink(_ link: PaperNoteLink, as state: LinkReviewState) {
        do {
            var updated = link
            updated.state = state
            updated.modifiedAt = Date()
            try database?.saveNoteLink(updated)
            noteLinks = try database?.noteLinks() ?? []
            statusMessage = state == .confirmed ? "Obsidian note link confirmed" : "Obsidian note link \(state.rawValue.lowercased())"
        } catch { alertMessage = error.localizedDescription }
    }

    func rebuildIndex() {
        guard let database else { return }
        var job = IndexingJob(kind: .searchRebuild, sourceName: "Research Atlas full-text index", status: .running)
        try? database.saveIndexingJob(job)
        indexingJobs = (try? database.indexingJobs()) ?? indexingJobs
        isBusy = true
        statusMessage = "Rebuilding search index…"
        Task {
            do {
                try await Task.detached(priority: .utility) { try database.rebuildSearchIndex() }.value
                job.status = .completed
                job.completedUnits = 1
                job.totalUnits = 1
                job.updatedAt = Date()
                try database.saveIndexingJob(job)
                try reload()
                statusMessage = "Search index rebuilt"
            } catch {
                job.status = .failed
                job.failureMessage = error.localizedDescription
                job.updatedAt = Date()
                try? database.saveIndexingJob(job)
                indexingJobs = (try? database.indexingJobs()) ?? indexingJobs
                alertMessage = error.localizedDescription
                statusMessage = "Search-index rebuild failed"
            }
            isBusy = false
        }
    }

    func exportWorkspace() {
        guard let database else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a folder for a portable Research Atlas export"
        panel.prompt = "Export Here"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let parentURL = panel.url else { return }

        let accessed = parentURL.startAccessingSecurityScopedResource()
        defer { if accessed { parentURL.stopAccessingSecurityScopedResource() } }
        do {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
            let exportURL = parentURL.appendingPathComponent("Research Atlas Export \(formatter.string(from: Date()))", isDirectory: true)
            try FileManager.default.createDirectory(at: exportURL, withIntermediateDirectories: false)
            for (name, data) in try ResearchExporter.files(for: database.exportBundle()) {
                try data.write(to: exportURL.appendingPathComponent(name), options: .atomic)
            }
            statusMessage = "Portable export created"
            NSWorkspace.shared.activateFileViewerSelecting([exportURL])
        } catch { alertMessage = error.localizedDescription }
    }

    func backupDatabase() {
        guard let database else { return }
        let panel = NSSavePanel()
        panel.title = "Back Up Research Atlas"
        panel.nameFieldStringValue = "research-atlas-backup.sqlite3"
        panel.allowedContentTypes = [UTType(filenameExtension: "sqlite3") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try database.backup(to: url)
            statusMessage = "Database backup created"
        } catch { alertMessage = error.localizedDescription }
    }

    func chooseDatabaseRestore() {
        guard let database else { return }
        cancelDatabaseRestore()
        let panel = NSOpenPanel()
        panel.title = "Preview a Research Atlas database backup"
        panel.prompt = "Preview Restore"
        panel.allowedContentTypes = [UTType(filenameExtension: "sqlite3") ?? .data]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let accessed = url.startAccessingSecurityScopedResource()
        isBusy = true
        statusMessage = "Validating database backup…"
        Task {
            do {
                let preview = try await Task.detached(priority: .userInitiated) {
                    try database.previewRestore(from: url)
                }.value
                restoreSecurityAccessActive = accessed
                pendingRestorePreview = preview
                statusMessage = "Backup validated — review before restoring"
            } catch {
                if accessed { url.stopAccessingSecurityScopedResource() }
                alertMessage = error.localizedDescription
                statusMessage = "Backup validation failed"
            }
            isBusy = false
        }
    }

    func cancelDatabaseRestore() {
        if restoreSecurityAccessActive, let url = pendingRestorePreview?.url {
            url.stopAccessingSecurityScopedResource()
        }
        restoreSecurityAccessActive = false
        pendingRestorePreview = nil
    }

    func confirmDatabaseRestore(_ preview: DatabaseRestorePreview) {
        guard let database, pendingRestorePreview?.id == preview.id else { return }
        isBusy = true
        statusMessage = "Creating recovery copy and restoring…"
        Task {
            do {
                let recoveryURL = try await Task.detached(priority: .userInitiated) {
                    try database.restore(from: preview.url)
                }.value
                if restoreSecurityAccessActive { preview.url.stopAccessingSecurityScopedResource() }
                restoreSecurityAccessActive = false
                pendingRestorePreview = nil
                lastRecoveryBackupPath = recoveryURL.path
                searchResults = []
                try reload()
                statusMessage = "Database restored; previous workspace saved for recovery"
            } catch {
                if restoreSecurityAccessActive { preview.url.stopAccessingSecurityScopedResource() }
                restoreSecurityAccessActive = false
                pendingRestorePreview = nil
                alertMessage = error.localizedDescription
                statusMessage = "Database restore failed"
            }
            isBusy = false
        }
    }

    func openExternal(_ item: LiteratureItem) {
        if let value = item.externalURL, let url = URL(string: value) { NSWorkspace.shared.open(url) }
    }

    func openUserGuide() {
        if let packaged = Bundle.main.resourceURL?.appendingPathComponent("USER_GUIDE.md"),
           FileManager.default.fileExists(atPath: packaged.path) {
            NSWorkspace.shared.open(packaged)
            return
        }
        #if DEBUG
        // The source guide is convenient when running the Swift package directly, but #filePath
        // must not expose a developer's absolute checkout path in a distributable release binary.
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceGuide = projectRoot.appendingPathComponent("USER_GUIDE.md")
        if FileManager.default.fileExists(atPath: sourceGuide.path) {
            NSWorkspace.shared.open(sourceGuide)
            return
        }
        #endif
        alertMessage = "The full guide file could not be found. The complete guide is still available inside Learning Center."
    }

    func openObsidianNote(_ note: ObsidianNote) {
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: note.path)]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    private func saveVaultBookmark(_ url: URL) throws {
        let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: "obsidianVaultBookmark")
    }

    private func restoredVaultURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: "obsidianVaultBookmark") else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    private func saveLocalResearchFolderBookmark(_ url: URL) throws {
        let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: "localResearchFolderBookmark")
    }

    private func restoredLocalResearchFolderURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: "localResearchFolderBookmark") else { return nil }
        var stale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }
}
