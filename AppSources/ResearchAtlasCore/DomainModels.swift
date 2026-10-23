import Foundation

public enum SourceKind: String, Codable, CaseIterable, Sendable {
    case manual = "Manual"
    case zotero = "Zotero"
}

public enum SourceAvailability: String, Codable, CaseIterable, Sendable {
    case available = "Available"
    case deletedInSource = "Deleted in Zotero"
    case differentLibrary = "Different Zotero library"
    case libraryUnavailable = "Zotero library unavailable"
}

public enum PDFFileAvailability: String, Codable, Sendable {
    case notLinked = "No PDF linked"
    case available = "Available"
    case changed = "Changed since verification"
    case missing = "Missing or unreadable"
}

public struct PDFFileFingerprint: Hashable, Codable, Sendable {
    public let byteCount: Int64
    public let sha256: String

    public init(byteCount: Int64, sha256: String) {
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

public struct ZoteroCheckpoint: Codable, Equatable, Sendable {
    public var serverID: String
    public var libraryVersion: Int

    public init(serverID: String, libraryVersion: Int) {
        self.serverID = serverID
        self.libraryVersion = libraryVersion
    }
}

public enum ZoteroLibraryKind: String, Codable, CaseIterable, Sendable {
    case user = "User"
    case group = "Group"
}

public enum ZoteroLibraryAvailability: String, Codable, CaseIterable, Sendable {
    case available = "Available"
    case unavailable = "Unavailable"
    case differentServer = "Different Zotero profile"
}

public struct ZoteroLibrary: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(serverID)|\(libraryID)" }
    public var serverID: String
    public var libraryID: String
    public var kind: ZoteroLibraryKind
    public var name: String
    public var metadataVersion: Int?
    public var libraryVersion: Int?
    public var availability: ZoteroLibraryAvailability
    public var lastSyncedAt: Date?

    public init(
        serverID: String,
        libraryID: String,
        kind: ZoteroLibraryKind,
        name: String,
        metadataVersion: Int? = nil,
        libraryVersion: Int? = nil,
        availability: ZoteroLibraryAvailability = .available,
        lastSyncedAt: Date? = nil
    ) {
        self.serverID = serverID
        self.libraryID = libraryID
        self.kind = kind
        self.name = name
        self.metadataVersion = metadataVersion
        self.libraryVersion = libraryVersion
        self.availability = availability
        self.lastSyncedAt = lastSyncedAt
    }
}

public struct ZoteroLibraryCheckpoint: Hashable, Codable, Sendable {
    public var serverID: String
    public var libraryID: String
    public var libraryVersion: Int

    public init(serverID: String, libraryID: String, libraryVersion: Int) {
        self.serverID = serverID
        self.libraryID = libraryID
        self.libraryVersion = libraryVersion
    }
}

public struct ZoteroCollection: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(serverID)|\(libraryID)|\(key)" }
    public var serverID: String
    public var libraryID: String
    public var key: String
    public var name: String
    public var parentKey: String?
    public var version: Int?

    public init(
        serverID: String,
        libraryID: String,
        key: String,
        name: String,
        parentKey: String? = nil,
        version: Int? = nil
    ) {
        self.serverID = serverID
        self.libraryID = libraryID
        self.key = key
        self.name = name
        self.parentKey = parentKey
        self.version = version
    }
}

public struct LiteratureCollectionMembership: Hashable, Codable, Sendable {
    public var literatureID: UUID
    public var collectionID: String

    public init(literatureID: UUID, collectionID: String) {
        self.literatureID = literatureID
        self.collectionID = collectionID
    }
}

public struct LiteratureItem: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var zoteroKey: String?
    public var zoteroAttachmentKey: String?
    public var zoteroServerID: String?
    public var zoteroLibraryID: String?
    public var zoteroLibraryName: String?
    public var zoteroVersion: Int?
    public var title: String
    public var authors: String
    public var year: Int?
    public var abstract: String
    public var doi: String?
    public var citationKey: String?
    public var tags: [String]
    public var itemType: String
    public var source: SourceKind
    public var pdfPath: String?
    public var pdfByteCount: Int64?
    public var pdfContentHash: String?
    public var pdfLastVerifiedAt: Date?
    public var externalURL: String?
    public var sourceAvailability: SourceAvailability
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        zoteroKey: String? = nil,
        zoteroAttachmentKey: String? = nil,
        zoteroServerID: String? = nil,
        zoteroLibraryID: String? = nil,
        zoteroLibraryName: String? = nil,
        zoteroVersion: Int? = nil,
        title: String,
        authors: String = "",
        year: Int? = nil,
        abstract: String = "",
        doi: String? = nil,
        citationKey: String? = nil,
        tags: [String] = [],
        itemType: String = "document",
        source: SourceKind = .manual,
        pdfPath: String? = nil,
        pdfByteCount: Int64? = nil,
        pdfContentHash: String? = nil,
        pdfLastVerifiedAt: Date? = nil,
        externalURL: String? = nil,
        sourceAvailability: SourceAvailability = .available,
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.zoteroKey = zoteroKey
        self.zoteroAttachmentKey = zoteroAttachmentKey
        self.zoteroServerID = zoteroServerID
        self.zoteroLibraryID = zoteroLibraryID
        self.zoteroLibraryName = zoteroLibraryName
        self.zoteroVersion = zoteroVersion
        self.title = title
        self.authors = authors
        self.year = year
        self.abstract = abstract
        self.doi = doi
        self.citationKey = citationKey
        self.tags = tags
        self.itemType = itemType
        self.source = source
        self.pdfPath = pdfPath
        self.pdfByteCount = pdfByteCount
        self.pdfContentHash = pdfContentHash
        self.pdfLastVerifiedAt = pdfLastVerifiedAt
        self.externalURL = externalURL
        self.sourceAvailability = sourceAvailability
        self.modifiedAt = modifiedAt
    }
}

public enum NoteMatchMethod: String, Codable, CaseIterable, Sendable {
    case doi = "DOI"
    case citationKey = "Citation key"
    case zoteroItemLink = "Zotero item link"
    case title = "Title suggestion"
    case manual = "Manual"
}

public enum LinkReviewState: String, Codable, CaseIterable, Sendable {
    case suggested = "Suggested"
    case confirmed = "Confirmed"
    case rejected = "Rejected"
}

public struct PaperNoteLink: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var noteID: UUID
    public var literatureID: UUID
    public var method: NoteMatchMethod
    public var matchedIdentifier: String
    public var state: LinkReviewState
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        noteID: UUID,
        literatureID: UUID,
        method: NoteMatchMethod,
        matchedIdentifier: String,
        state: LinkReviewState = .suggested,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.noteID = noteID
        self.literatureID = literatureID
        self.method = method
        self.matchedIdentifier = matchedIdentifier
        self.state = state
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

public struct ObsidianNote: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var path: String
    public var title: String
    public var content: String
    public var tags: [String]
    public var wikilinks: [String]
    public var citationKeys: [String]
    public var dois: [String]
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        path: String,
        title: String,
        content: String,
        tags: [String] = [],
        wikilinks: [String] = [],
        citationKeys: [String] = [],
        dois: [String] = [],
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.title = title
        self.content = content
        self.tags = tags
        self.wikilinks = wikilinks
        self.citationKeys = citationKeys
        self.dois = dois
        self.modifiedAt = modifiedAt
    }
}

public struct ResearchProject: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var summary: String
    public var createdAt: Date
    public var modifiedAt: Date

    public init(id: UUID = UUID(), title: String, summary: String = "", createdAt: Date = Date(), modifiedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.summary = summary
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

public struct ResearchQuestion: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var projectID: UUID
    public var parentQuestionID: UUID?
    public var question: String
    public var notes: String
    public var status: String
    public var objectives: String
    public var theoreticalInterests: String
    public var conceptualDefinitions: String
    public var unresolvedDisagreements: String
    public var potentialHypotheses: String
    public var methodologicalConsiderations: String
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        parentQuestionID: UUID? = nil,
        question: String,
        notes: String = "",
        status: String = "Active",
        objectives: String = "",
        theoreticalInterests: String = "",
        conceptualDefinitions: String = "",
        unresolvedDisagreements: String = "",
        potentialHypotheses: String = "",
        methodologicalConsiderations: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.parentQuestionID = parentQuestionID
        self.question = question
        self.notes = notes
        self.status = status
        self.objectives = objectives
        self.theoreticalInterests = theoreticalInterests
        self.conceptualDefinitions = conceptualDefinitions
        self.unresolvedDisagreements = unresolvedDisagreements
        self.potentialHypotheses = potentialHypotheses
        self.methodologicalConsiderations = methodologicalConsiderations
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

public struct ResearchQuestionVersion: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var questionID: UUID
    public var parentQuestionID: UUID?
    public var question: String
    public var notes: String
    public var status: String
    public var objectives: String
    public var theoreticalInterests: String
    public var conceptualDefinitions: String
    public var unresolvedDisagreements: String
    public var potentialHypotheses: String
    public var methodologicalConsiderations: String
    public var changeNote: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(), questionID: UUID, parentQuestionID: UUID? = nil,
        question: String, notes: String, status: String, objectives: String,
        theoreticalInterests: String, conceptualDefinitions: String,
        unresolvedDisagreements: String, potentialHypotheses: String,
        methodologicalConsiderations: String, changeNote: String, createdAt: Date = Date()
    ) {
        self.id = id
        self.questionID = questionID
        self.parentQuestionID = parentQuestionID
        self.question = question
        self.notes = notes
        self.status = status
        self.objectives = objectives
        self.theoreticalInterests = theoreticalInterests
        self.conceptualDefinitions = conceptualDefinitions
        self.unresolvedDisagreements = unresolvedDisagreements
        self.potentialHypotheses = potentialHypotheses
        self.methodologicalConsiderations = methodologicalConsiderations
        self.changeNote = changeNote
        self.createdAt = createdAt
    }
}

public struct QuestionLiteratureAssociation: Hashable, Codable, Sendable {
    public var questionID: UUID
    public var literatureID: UUID
    public var notes: String
    public var createdAt: Date

    public init(questionID: UUID, literatureID: UUID, notes: String = "", createdAt: Date = Date()) {
        self.questionID = questionID
        self.literatureID = literatureID
        self.notes = notes
        self.createdAt = createdAt
    }
}

public struct QuestionConceptAssociation: Hashable, Codable, Sendable {
    public var questionID: UUID
    public var conceptID: UUID
    public var notes: String
    public var createdAt: Date

    public init(questionID: UUID, conceptID: UUID, notes: String = "", createdAt: Date = Date()) {
        self.questionID = questionID
        self.conceptID = conceptID
        self.notes = notes
        self.createdAt = createdAt
    }
}

public struct ResearchArgument: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var questionID: UUID?
    public var proposition: String
    public var qualification: String
    public var status: String
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        questionID: UUID? = nil,
        proposition: String,
        qualification: String = "",
        status: String = "Developing",
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.questionID = questionID
        self.proposition = proposition
        self.qualification = qualification
        self.status = status
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

public struct ArgumentVersion: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var argumentID: UUID
    public var questionID: UUID?
    public var proposition: String
    public var qualification: String
    public var status: String
    public var changeNote: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        argumentID: UUID,
        questionID: UUID? = nil,
        proposition: String,
        qualification: String = "",
        status: String,
        changeNote: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.argumentID = argumentID
        self.questionID = questionID
        self.proposition = proposition
        self.qualification = qualification
        self.status = status
        self.changeNote = changeNote
        self.createdAt = createdAt
    }
}

public enum EvidenceRelation: String, Codable, CaseIterable, Sendable {
    case supports = "Supports"
    case challenges = "Challenges"
    case qualifies = "Qualifies"
    case context = "Provides context"
    case alternative = "Alternative explanation"
}

public enum VerificationState: String, Codable, CaseIterable, Sendable {
    case unverified = "Unverified"
    case verified = "Verified"
    case rejected = "Rejected"
}

public struct PDFSelectionRegion: Hashable, Codable, Sendable {
    public var page: Int
    public var normalizedX: Double
    public var normalizedY: Double
    public var normalizedWidth: Double
    public var normalizedHeight: Double

    public init(
        page: Int,
        normalizedX: Double,
        normalizedY: Double,
        normalizedWidth: Double,
        normalizedHeight: Double
    ) {
        self.page = page
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.normalizedWidth = normalizedWidth
        self.normalizedHeight = normalizedHeight
    }
}

public struct EvidenceRelationship: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var argumentID: UUID
    public var literatureID: UUID
    public var relation: EvidenceRelation
    public var summary: String
    public var page: Int?
    public var quotedPassage: String
    public var verification: VerificationState
    public var selectionRegions: [PDFSelectionRegion]
    public var selectionDocumentHash: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        argumentID: UUID,
        literatureID: UUID,
        relation: EvidenceRelation,
        summary: String,
        page: Int? = nil,
        quotedPassage: String = "",
        verification: VerificationState = .unverified,
        selectionRegions: [PDFSelectionRegion] = [],
        selectionDocumentHash: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.argumentID = argumentID
        self.literatureID = literatureID
        self.relation = relation
        self.summary = summary
        self.page = page
        self.quotedPassage = quotedPassage
        self.verification = verification
        self.selectionRegions = selectionRegions
        self.selectionDocumentHash = selectionDocumentHash
        self.createdAt = createdAt
    }
}

public enum ClaimCategory: String, Codable, CaseIterable, Sendable {
    case researchQuestion = "Research question"
    case hypothesis = "Hypothesis"
    case theoreticalProposition = "Theoretical proposition"
    case empiricalFinding = "Empirical finding"
    case authorInterpretation = "Author interpretation"
    case methodologicalAssumption = "Methodological assumption"
    case limitation = "Limitation"
    case personalInterpretation = "My interpretation"
    case aiSuggestion = "AI-generated suggestion"
}

public enum ClaimExtractionMethod: String, Codable, CaseIterable, Sendable {
    case manual = "Manually authored"
    case manualSelection = "Manual PDF selection"
    case aiCandidate = "AI-extracted candidate"
}

public struct ResearchClaim: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var claimText: String
    public var category: ClaimCategory
    public var literatureID: UUID?
    public var sourcePassageID: String?
    public var page: Int?
    public var quotedSourceText: String
    public var authorTerminology: String
    public var methodologicalContext: String
    public var evidenceType: String
    public var relatedConstructs: [String]
    public var studyContext: String
    public var extractionMethod: ClaimExtractionMethod
    public var modelIdentifier: String?
    public var promptVersion: String?
    public var verification: VerificationState
    public var userNotes: String
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(), claimText: String, category: ClaimCategory,
        literatureID: UUID? = nil, sourcePassageID: String? = nil, page: Int? = nil,
        quotedSourceText: String = "", authorTerminology: String = "",
        methodologicalContext: String = "", evidenceType: String = "",
        relatedConstructs: [String] = [], studyContext: String = "",
        extractionMethod: ClaimExtractionMethod = .manual,
        modelIdentifier: String? = nil, promptVersion: String? = nil,
        verification: VerificationState = .unverified, userNotes: String = "",
        createdAt: Date = Date(), modifiedAt: Date = Date()
    ) {
        self.id = id
        self.claimText = claimText
        self.category = category
        self.literatureID = literatureID
        self.sourcePassageID = sourcePassageID
        self.page = page
        self.quotedSourceText = quotedSourceText
        self.authorTerminology = authorTerminology
        self.methodologicalContext = methodologicalContext
        self.evidenceType = evidenceType
        self.relatedConstructs = relatedConstructs
        self.studyContext = studyContext
        self.extractionMethod = extractionMethod
        self.modelIdentifier = modelIdentifier
        self.promptVersion = promptVersion
        self.verification = verification
        self.userNotes = userNotes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

public struct ClaimVersion: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var claimID: UUID
    public var claimText: String
    public var category: ClaimCategory
    public var authorTerminology: String
    public var methodologicalContext: String
    public var evidenceType: String
    public var relatedConstructs: [String]
    public var studyContext: String
    public var verification: VerificationState
    public var userNotes: String
    public var changeNote: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(), claimID: UUID, claimText: String, category: ClaimCategory,
        authorTerminology: String, methodologicalContext: String, evidenceType: String,
        relatedConstructs: [String], studyContext: String, verification: VerificationState,
        userNotes: String, changeNote: String, createdAt: Date = Date()
    ) {
        self.id = id
        self.claimID = claimID
        self.claimText = claimText
        self.category = category
        self.authorTerminology = authorTerminology
        self.methodologicalContext = methodologicalContext
        self.evidenceType = evidenceType
        self.relatedConstructs = relatedConstructs
        self.studyContext = studyContext
        self.verification = verification
        self.userNotes = userNotes
        self.changeNote = changeNote
        self.createdAt = createdAt
    }
}

public struct LiteratureComparisonProfile: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID { literatureID }
    public var literatureID: UUID
    public var researchQuestion: String
    public var theoreticalFramework: String
    public var studyDesign: String
    public var sample: String
    public var independentVariables: String
    public var dependentVariables: String
    public var operationalDefinitions: String
    public var mainFindings: String
    public var limitations: String
    public var userNotes: String
    public var modifiedAt: Date

    public init(
        literatureID: UUID,
        researchQuestion: String = "",
        theoreticalFramework: String = "",
        studyDesign: String = "",
        sample: String = "",
        independentVariables: String = "",
        dependentVariables: String = "",
        operationalDefinitions: String = "",
        mainFindings: String = "",
        limitations: String = "",
        userNotes: String = "",
        modifiedAt: Date = Date()
    ) {
        self.literatureID = literatureID
        self.researchQuestion = researchQuestion
        self.theoreticalFramework = theoreticalFramework
        self.studyDesign = studyDesign
        self.sample = sample
        self.independentVariables = independentVariables
        self.dependentVariables = dependentVariables
        self.operationalDefinitions = operationalDefinitions
        self.mainFindings = mainFindings
        self.limitations = limitations
        self.userNotes = userNotes
        self.modifiedAt = modifiedAt
    }
}

public struct RetrievalSet: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var query: String
    public var zoteroLibraryFilterID: String?
    public var zoteroCollectionFilterID: String?
    public var yearFrom: Int?
    public var yearTo: Int?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        query: String,
        zoteroLibraryFilterID: String? = nil,
        zoteroCollectionFilterID: String? = nil,
        yearFrom: Int? = nil,
        yearTo: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.query = query
        self.zoteroLibraryFilterID = zoteroLibraryFilterID
        self.zoteroCollectionFilterID = zoteroCollectionFilterID
        self.yearFrom = yearFrom
        self.yearTo = yearTo
        self.createdAt = createdAt
    }
}

public enum RetrievalCitationStatus: String, Codable, CaseIterable, Sendable {
    case current = "Current source"
    case sourceMissing = "Source passage no longer indexed"
    case passageChanged = "Source passage changed"
    case documentChanged = "Document fingerprint changed"
}

public struct RetrievedPassage: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(retrievalSetID.uuidString)|\(sourcePassageID)" }
    public var retrievalSetID: UUID
    public var sourcePassageID: String
    public var literatureID: UUID
    public var page: Int
    public var passageText: String
    public var extractionMethod: String
    public var sourceIndexedAt: Date
    public var sourceDocumentHash: String?
    public var rank: Double
    public var citationStatus: RetrievalCitationStatus
    public var addedAt: Date

    public init(
        retrievalSetID: UUID,
        sourcePassageID: String,
        literatureID: UUID,
        page: Int,
        passageText: String,
        extractionMethod: String,
        sourceIndexedAt: Date,
        sourceDocumentHash: String? = nil,
        rank: Double,
        citationStatus: RetrievalCitationStatus = .current,
        addedAt: Date = Date()
    ) {
        self.retrievalSetID = retrievalSetID
        self.sourcePassageID = sourcePassageID
        self.literatureID = literatureID
        self.page = page
        self.passageText = passageText
        self.extractionMethod = extractionMethod
        self.sourceIndexedAt = sourceIndexedAt
        self.sourceDocumentHash = sourceDocumentHash
        self.rank = rank
        self.citationStatus = citationStatus
        self.addedAt = addedAt
    }
}

public struct RetrievedNoteSnippet: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(retrievalSetID.uuidString)|note|\(noteID.uuidString)" }
    public var retrievalSetID: UUID
    public var noteID: UUID
    public var notePath: String
    public var noteTitle: String
    public var snippetText: String
    public var sourceModifiedAt: Date
    public var rank: Double
    public var citationStatus: RetrievalCitationStatus
    public var addedAt: Date

    public init(
        retrievalSetID: UUID, noteID: UUID, notePath: String, noteTitle: String,
        snippetText: String, sourceModifiedAt: Date, rank: Double,
        citationStatus: RetrievalCitationStatus = .current, addedAt: Date = Date()
    ) {
        self.retrievalSetID = retrievalSetID
        self.noteID = noteID
        self.notePath = notePath
        self.noteTitle = noteTitle
        self.snippetText = snippetText
        self.sourceModifiedAt = sourceModifiedAt
        self.rank = rank
        self.citationStatus = citationStatus
        self.addedAt = addedAt
    }
}

public enum KnowledgeNodeType: String, Codable, CaseIterable, Sendable {
    case paper = "Paper"
    case concept = "Concept"
    case argument = "Argument"
    case researchQuestion = "Research question"
    case note = "Obsidian note"
    case claim = "Claim"
    case idea = "Research idea"
}

public enum KnowledgeRelationshipType: String, Codable, CaseIterable, Sendable {
    case supports = "Supports"
    case challenges = "Challenges"
    case qualifies = "Qualifies"
    case contradicts = "Contradicts"
    case extends = "Extends"
    case dependsOn = "Depends on"
    case context = "Provides context for"
    case relatedConstruct = "Uses a related construct"
    case alternative = "Offers an alternative explanation"
    case investigates = "Investigates"
    case operationalises = "Operationalises"
    case relatesTo = "Relates to"
    case requiresInvestigation = "Requires further investigation"
}

public enum RecordOrigin: String, Codable, CaseIterable, Sendable {
    case user = "User-authored"
    case imported = "Imported source"
    case localSuggestion = "Local system suggestion"
    case aiSuggested = "AI-suggested"
}

public struct ResearchConcept: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var definition: String
    public var notes: String
    public var verification: VerificationState
    public var origin: RecordOrigin
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        definition: String = "",
        notes: String = "",
        verification: VerificationState = .unverified,
        origin: RecordOrigin = .user,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.definition = definition
        self.notes = notes
        self.verification = verification
        self.origin = origin
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

public struct KnowledgeRelationship: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var sourceType: KnowledgeNodeType
    public var sourceID: String
    public var targetType: KnowledgeNodeType
    public var targetID: String
    public var relationship: KnowledgeRelationshipType
    public var evidenceRelationshipID: UUID?
    public var sourcePassageID: String?
    public var verification: VerificationState
    public var origin: RecordOrigin
    public var notes: String
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        sourceType: KnowledgeNodeType,
        sourceID: String,
        targetType: KnowledgeNodeType,
        targetID: String,
        relationship: KnowledgeRelationshipType,
        evidenceRelationshipID: UUID? = nil,
        sourcePassageID: String? = nil,
        verification: VerificationState = .unverified,
        origin: RecordOrigin = .user,
        notes: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.sourceType = sourceType
        self.sourceID = sourceID
        self.targetType = targetType
        self.targetID = targetID
        self.relationship = relationship
        self.evidenceRelationshipID = evidenceRelationshipID
        self.sourcePassageID = sourcePassageID
        self.verification = verification
        self.origin = origin
        self.notes = notes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

public enum ResearchIdeaStatus: String, Codable, CaseIterable, Sendable {
    case initialObservation = "Initial observation"
    case emergingIdea = "Emerging idea"
    case underInvestigation = "Under investigation"
    case developingProposition = "Developing proposition"
    case candidateHypothesis = "Candidate hypothesis"
    case integratedIntoArgument = "Integrated into argument"
    case rejectedOrSuperseded = "Rejected or superseded"
}

public struct ResearchIdea: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var projectID: UUID?
    public var questionID: UUID?
    public var title: String
    public var body: String
    public var status: ResearchIdeaStatus
    public var assumptions: String
    public var alternativeExplanations: String
    public var evidenceNeeded: String
    public var investigationNotes: String
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(), projectID: UUID? = nil, questionID: UUID? = nil,
        title: String, body: String = "", status: ResearchIdeaStatus = .initialObservation,
        assumptions: String = "", alternativeExplanations: String = "", evidenceNeeded: String = "",
        investigationNotes: String = "", createdAt: Date = Date(), modifiedAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.questionID = questionID
        self.title = title
        self.body = body
        self.status = status
        self.assumptions = assumptions
        self.alternativeExplanations = alternativeExplanations
        self.evidenceNeeded = evidenceNeeded
        self.investigationNotes = investigationNotes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

public struct IdeaVersion: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var ideaID: UUID
    public var title: String
    public var body: String
    public var status: ResearchIdeaStatus
    public var assumptions: String
    public var alternativeExplanations: String
    public var evidenceNeeded: String
    public var investigationNotes: String
    public var changeNote: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(), ideaID: UUID, title: String, body: String, status: ResearchIdeaStatus,
        assumptions: String, alternativeExplanations: String, evidenceNeeded: String,
        investigationNotes: String, changeNote: String, createdAt: Date = Date()
    ) {
        self.id = id
        self.ideaID = ideaID
        self.title = title
        self.body = body
        self.status = status
        self.assumptions = assumptions
        self.alternativeExplanations = alternativeExplanations
        self.evidenceNeeded = evidenceNeeded
        self.investigationNotes = investigationNotes
        self.changeNote = changeNote
        self.createdAt = createdAt
    }
}

public enum IdeaLinkTargetType: String, Codable, CaseIterable, Sendable {
    case literature = "Literature"
    case passage = "Source passage"
    case note = "Obsidian note"
    case concept = "Concept"
    case argument = "Argument"
}

public struct ResearchIdeaLink: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var ideaID: UUID
    public var targetType: IdeaLinkTargetType
    public var targetID: String
    public var notes: String
    public var createdAt: Date

    public init(id: UUID = UUID(), ideaID: UUID, targetType: IdeaLinkTargetType, targetID: String, notes: String = "", createdAt: Date = Date()) {
        self.id = id
        self.ideaID = ideaID
        self.targetType = targetType
        self.targetID = targetID
        self.notes = notes
        self.createdAt = createdAt
    }
}

public enum ContradictionCaseStatus: String, Codable, CaseIterable, Sendable {
    case open = "Open"
    case contextualDifference = "Contextual difference"
    case unresolved = "Unresolved"
    case supportedContradiction = "Supported contradiction"
    case dismissed = "Dismissed"
}

public struct ContradictionCase: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var questionID: UUID?
    public var title: String
    public var summary: String
    public var status: ContradictionCaseStatus
    public var resolutionNotes: String
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(), questionID: UUID? = nil, title: String, summary: String = "",
        status: ContradictionCaseStatus = .open, resolutionNotes: String = "",
        createdAt: Date = Date(), modifiedAt: Date = Date()
    ) {
        self.id = id
        self.questionID = questionID
        self.title = title
        self.summary = summary
        self.status = status
        self.resolutionNotes = resolutionNotes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

public struct ContradictionSource: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var caseID: UUID
    public var literatureID: UUID
    public var sourcePassageID: String?
    public var role: String
    public var finding: String
    public var contextualDifference: String
    public var verification: VerificationState
    public var createdAt: Date

    public init(
        id: UUID = UUID(), caseID: UUID, literatureID: UUID, sourcePassageID: String? = nil,
        role: String, finding: String = "", contextualDifference: String = "",
        verification: VerificationState = .unverified, createdAt: Date = Date()
    ) {
        self.id = id
        self.caseID = caseID
        self.literatureID = literatureID
        self.sourcePassageID = sourcePassageID
        self.role = role
        self.finding = finding
        self.contextualDifference = contextualDifference
        self.verification = verification
        self.createdAt = createdAt
    }
}

public struct HistoryEvent: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var entityType: String
    public var entityID: String
    public var eventType: String
    public var title: String
    public var detail: String
    public var recordedAt: Date

    public init(
        id: UUID = UUID(), entityType: String, entityID: String, eventType: String,
        title: String, detail: String, recordedAt: Date = Date()
    ) {
        self.id = id
        self.entityType = entityType
        self.entityID = entityID
        self.eventType = eventType
        self.title = title
        self.detail = detail
        self.recordedAt = recordedAt
    }
}

public enum AIProviderKind: String, Codable, CaseIterable, Sendable {
    case disabled = "Disabled"
    case openAI = "OpenAI"
    case anthropic = "Anthropic Claude"
    case googleGemini = "Google Gemini"
    case ollamaLocal = "Ollama Local"
    case lmStudioLocal = "LM Studio Local"
    case compatibleEndpoint = "OpenAI-compatible endpoint"

    public var displayName: String {
        switch self {
        case .openAI: "OpenAI Responses"
        case .ollamaLocal: "Local Research AI (Ollama)"
        default: rawValue
        }
    }

    public var defaultEndpoint: String {
        switch self {
        case .disabled, .openAI, .compatibleEndpoint:
            "https://api.openai.com/v1/responses"
        case .anthropic:
            "https://api.anthropic.com/v1/messages"
        case .googleGemini:
            "https://generativelanguage.googleapis.com/v1beta"
        case .ollamaLocal:
            "http://127.0.0.1:11434/api/chat"
        case .lmStudioLocal:
            "http://127.0.0.1:1234/v1/chat/completions"
        }
    }

    public var defaultModel: String {
        switch self {
        case .disabled, .openAI, .compatibleEndpoint: "gpt-6-astra"
        case .anthropic: "claude-sonnet-5-5"
        case .googleGemini: "gemini-3.8-flash"
        case .ollamaLocal: "gpt-oss:20b"
        case .lmStudioLocal: "qwen3.6-27b"
        }
    }

    public var endpointIsEditable: Bool { self == .compatibleEndpoint }

    public var requiresCredential: Bool {
        switch self {
        case .disabled, .ollamaLocal, .lmStudioLocal: false
        default: true
        }
    }

    public var isLocal: Bool { self == .ollamaLocal || self == .lmStudioLocal }

    public var credentialLabel: String {
        switch self {
        case .disabled: "API credential"
        case .openAI, .compatibleEndpoint: "OpenAI API key"
        case .anthropic: "Anthropic API key"
        case .googleGemini: "Gemini API key"
        case .ollamaLocal, .lmStudioLocal: "No credential required"
        }
    }

    public var transportDescription: String {
        switch self {
        case .disabled: "No external provider"
        case .openAI: "Official OpenAI Responses API with JSON Schema output"
        case .anthropic: "Official Claude Messages API with structured JSON output"
        case .googleGemini: "Official Gemini generateContent API with structured JSON output"
        case .ollamaLocal: "App-managed local Ollama engine with structured gpt-oss reasoning"
        case .lmStudioLocal: "Local LM Studio chat API on this Mac with JSON Schema output"
        case .compatibleEndpoint: "Custom HTTPS endpoint implementing the OpenAI Responses contract"
        }
    }
}

public enum AIReasoningEffort: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high

    public var displayName: String { rawValue.capitalized }
}

public struct AIProviderConfiguration: Equatable, Codable, Sendable {
    public var provider: AIProviderKind
    public var endpoint: String
    public var model: String
    public var externalTransmissionEnabled: Bool
    public var maximumPassages: Int
    public var maximumOutputTokens: Int
    public var reasoningEffort: AIReasoningEffort
    public var localRuntimeIdleMinutes: Int
    public var modifiedAt: Date

    public init(
        provider: AIProviderKind = .disabled,
        endpoint: String = AIProviderKind.openAI.defaultEndpoint,
        model: String = AIProviderKind.openAI.defaultModel,
        externalTransmissionEnabled: Bool = false,
        maximumPassages: Int = 12,
        maximumOutputTokens: Int = 1200,
        reasoningEffort: AIReasoningEffort = .medium,
        localRuntimeIdleMinutes: Int = 10,
        modifiedAt: Date = Date()
    ) {
        self.provider = provider
        self.endpoint = endpoint
        self.model = model
        self.externalTransmissionEnabled = externalTransmissionEnabled
        self.maximumPassages = maximumPassages
        self.maximumOutputTokens = maximumOutputTokens
        self.reasoningEffort = reasoningEffort
        self.localRuntimeIdleMinutes = localRuntimeIdleMinutes
        self.modifiedAt = modifiedAt
    }

    public mutating func applyDefaults(for provider: AIProviderKind) {
        self.provider = provider
        endpoint = provider.defaultEndpoint
        model = provider.defaultModel
        if provider == .ollamaLocal {
            reasoningEffort = .medium
            maximumOutputTokens = max(maximumOutputTokens, 4096)
        }
        if provider == .disabled { externalTransmissionEnabled = false }
    }

    /// Compares settings that affect provider execution while deliberately ignoring the
    /// persistence timestamp. Saving updates `modifiedAt`; treating that audit field as an
    /// unsaved edit would incorrectly disable actions immediately after a successful save.
    public func hasSameOperationalSettings(as other: AIProviderConfiguration) -> Bool {
        provider == other.provider &&
        endpoint == other.endpoint &&
        model == other.model &&
        externalTransmissionEnabled == other.externalTransmissionEnabled &&
        maximumPassages == other.maximumPassages &&
        maximumOutputTokens == other.maximumOutputTokens &&
        reasoningEffort == other.reasoningEffort &&
        localRuntimeIdleMinutes == other.localRuntimeIdleMinutes
    }

    /// A provider is operational only when requests are explicitly enabled and any required
    /// credential is known to be stored. Local loopback providers deliberately need no key.
    public func isReadyForRequests(credentialStored: Bool) -> Bool {
        provider != .disabled &&
        externalTransmissionEnabled &&
        (!provider.requiresCredential || credentialStored)
    }
}

public enum AIAnalysisKind: String, Codable, CaseIterable, Sendable {
    case literatureAnswer = "Literature answer"
    case claimExtraction = "Claim extraction"
    case biasAudit = "Bias audit"
    case contradictionReview = "Contradiction review"
    case deliberation = "Deliberation"
    case citationSupport = "Citation-support review"
    case collectiveTurn = "Collective-lab model turn"
}

public enum AIAnalysisTargetType: String, Codable, CaseIterable, Sendable {
    case deliberationSession = "Deliberation session"
    case biasAudit = "Bias audit"
    case contradictionCase = "Contradiction case"
    case collectiveExperiment = "Collective experiment"
}

public enum AIAnalysisStatus: String, Codable, CaseIterable, Sendable {
    case prepared = "Prepared"
    case completed = "Completed"
    case insufficientEvidence = "Insufficient evidence"
    case refused = "Refused"
    case failed = "Failed"
}

public struct AIAnalysis: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var kind: AIAnalysisKind
    public var provider: String
    public var model: String
    public var promptVersion: String
    public var retrievalSetID: UUID?
    public var targetType: AIAnalysisTargetType?
    public var targetID: UUID?
    public var userQuery: String
    public var responseText: String
    public var structuredResponseJSON: String
    public var status: AIAnalysisStatus
    public var transmittedPassageCount: Int
    public var transmittedCharacterCount: Int
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var errorMessage: String?
    public var createdAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(), kind: AIAnalysisKind, provider: String, model: String,
        promptVersion: String, retrievalSetID: UUID? = nil,
        targetType: AIAnalysisTargetType? = nil, targetID: UUID? = nil, userQuery: String,
        responseText: String = "", structuredResponseJSON: String = "",
        status: AIAnalysisStatus = .prepared, transmittedPassageCount: Int = 0,
        transmittedCharacterCount: Int = 0, inputTokens: Int? = nil, outputTokens: Int? = nil,
        errorMessage: String? = nil, createdAt: Date = Date(), completedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.provider = provider
        self.model = model
        self.promptVersion = promptVersion
        self.retrievalSetID = retrievalSetID
        self.targetType = targetType
        self.targetID = targetID
        self.userQuery = userQuery
        self.responseText = responseText
        self.structuredResponseJSON = structuredResponseJSON
        self.status = status
        self.transmittedPassageCount = transmittedPassageCount
        self.transmittedCharacterCount = transmittedCharacterCount
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

public struct GroundedDeliberationContribution: Hashable, Codable, Sendable {
    public var content: String
    public var citations: [String]
    public var uncertainty: String

    public init(content: String, citations: [String], uncertainty: String) {
        self.content = content
        self.citations = citations
        self.uncertainty = uncertainty
    }
}

public struct GroundedDeliberationRole: Hashable, Codable, Sendable {
    public var perspective: DeliberationPerspective
    public var initialAssessment: GroundedDeliberationContribution
    public var crossExamination: GroundedDeliberationContribution
    public var revisedAssessment: GroundedDeliberationContribution

    public init(
        perspective: DeliberationPerspective,
        initialAssessment: GroundedDeliberationContribution,
        crossExamination: GroundedDeliberationContribution,
        revisedAssessment: GroundedDeliberationContribution
    ) {
        self.perspective = perspective
        self.initialAssessment = initialAssessment
        self.crossExamination = crossExamination
        self.revisedAssessment = revisedAssessment
    }

    enum CodingKeys: String, CodingKey {
        case perspective
        case initialAssessment = "initial_assessment"
        case crossExamination = "cross_examination"
        case revisedAssessment = "revised_assessment"
    }
}

public struct GroundedDeliberationOutput: Hashable, Codable, Sendable {
    public var insufficientEvidence: Bool
    public var insufficiencyReason: String
    public var roles: [GroundedDeliberationRole]
    public var synthesis: GroundedDeliberationContribution

    public init(
        insufficientEvidence: Bool, insufficiencyReason: String,
        roles: [GroundedDeliberationRole], synthesis: GroundedDeliberationContribution
    ) {
        self.insufficientEvidence = insufficientEvidence
        self.insufficiencyReason = insufficiencyReason
        self.roles = roles
        self.synthesis = synthesis
    }

    enum CodingKeys: String, CodingKey {
        case insufficientEvidence = "insufficient_evidence"
        case insufficiencyReason = "insufficiency_reason"
        case roles, synthesis
    }
}

public struct GroundedBiasConcern: Hashable, Codable, Sendable {
    public var kind: BiasConcernKind
    public var potentialProblem: String
    public var whyItMatters: String
    public var alternativeInterpretations: String
    public var investigationQuestions: [String]
    public var uncertainty: String
    public var citations: [String]

    public init(
        kind: BiasConcernKind, potentialProblem: String, whyItMatters: String,
        alternativeInterpretations: String, investigationQuestions: [String],
        uncertainty: String, citations: [String]
    ) {
        self.kind = kind
        self.potentialProblem = potentialProblem
        self.whyItMatters = whyItMatters
        self.alternativeInterpretations = alternativeInterpretations
        self.investigationQuestions = investigationQuestions
        self.uncertainty = uncertainty
        self.citations = citations
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case potentialProblem = "potential_problem"
        case whyItMatters = "why_it_matters"
        case alternativeInterpretations = "alternative_interpretations"
        case investigationQuestions = "investigation_questions"
        case uncertainty, citations
    }
}

public struct GroundedBiasAuditOutput: Hashable, Codable, Sendable {
    public var insufficientEvidence: Bool
    public var insufficiencyReason: String
    public var concerns: [GroundedBiasConcern]

    public init(insufficientEvidence: Bool, insufficiencyReason: String, concerns: [GroundedBiasConcern]) {
        self.insufficientEvidence = insufficientEvidence
        self.insufficiencyReason = insufficiencyReason
        self.concerns = concerns
    }

    enum CodingKeys: String, CodingKey {
        case insufficientEvidence = "insufficient_evidence"
        case insufficiencyReason = "insufficiency_reason"
        case concerns
    }
}

public struct GroundedContradictionReviewOutput: Hashable, Codable, Sendable {
    public var insufficientEvidence: Bool
    public var insufficiencyReason: String
    public var suggestedStatus: ContradictionCaseStatus
    public var assessment: String
    public var possibleExplanations: [String]
    public var contextualDifferences: [String]
    public var unresolvedQuestions: [String]
    public var citations: [String]

    public init(
        insufficientEvidence: Bool, insufficiencyReason: String,
        suggestedStatus: ContradictionCaseStatus, assessment: String,
        possibleExplanations: [String], contextualDifferences: [String],
        unresolvedQuestions: [String], citations: [String]
    ) {
        self.insufficientEvidence = insufficientEvidence
        self.insufficiencyReason = insufficiencyReason
        self.suggestedStatus = suggestedStatus
        self.assessment = assessment
        self.possibleExplanations = possibleExplanations
        self.contextualDifferences = contextualDifferences
        self.unresolvedQuestions = unresolvedQuestions
        self.citations = citations
    }

    enum CodingKeys: String, CodingKey {
        case insufficientEvidence = "insufficient_evidence"
        case insufficiencyReason = "insufficiency_reason"
        case suggestedStatus = "suggested_status"
        case assessment
        case possibleExplanations = "possible_explanations"
        case contextualDifferences = "contextual_differences"
        case unresolvedQuestions = "unresolved_questions"
        case citations
    }
}

public struct GroundedCollectiveTurnOutput: Hashable, Codable, Sendable {
    public var insufficientEvidence: Bool
    public var insufficiencyReason: String
    public var response: String
    public var confidence: Double
    public var uncertainty: String
    public var citations: [String]

    public init(
        insufficientEvidence: Bool, insufficiencyReason: String, response: String,
        confidence: Double, uncertainty: String, citations: [String]
    ) {
        self.insufficientEvidence = insufficientEvidence
        self.insufficiencyReason = insufficiencyReason
        self.response = response
        self.confidence = confidence
        self.uncertainty = uncertainty
        self.citations = citations
    }

    enum CodingKeys: String, CodingKey {
        case insufficientEvidence = "insufficient_evidence"
        case insufficiencyReason = "insufficiency_reason"
        case response, confidence, uncertainty, citations
    }
}

public struct AIAnalysisCitation: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var analysisID: UUID
    public var label: String
    public var sourcePassageID: String
    public var literatureID: UUID
    public var page: Int
    public var quotedPassage: String
    public var sourceDocumentHash: String?
    public var citationStatus: RetrievalCitationStatus

    public init(
        id: UUID = UUID(), analysisID: UUID, label: String, sourcePassageID: String,
        literatureID: UUID, page: Int, quotedPassage: String, sourceDocumentHash: String? = nil,
        citationStatus: RetrievalCitationStatus = .current
    ) {
        self.id = id
        self.analysisID = analysisID
        self.label = label
        self.sourcePassageID = sourcePassageID
        self.literatureID = literatureID
        self.page = page
        self.quotedPassage = quotedPassage
        self.sourceDocumentHash = sourceDocumentHash
        self.citationStatus = citationStatus
    }
}

public struct AIAnalysisNoteCitation: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var analysisID: UUID
    public var label: String
    public var noteID: UUID
    public var notePath: String
    public var noteTitle: String
    public var quotedSnippet: String
    public var sourceModifiedAt: Date
    public var citationStatus: RetrievalCitationStatus

    public init(
        id: UUID = UUID(), analysisID: UUID, label: String, noteID: UUID,
        notePath: String, noteTitle: String, quotedSnippet: String,
        sourceModifiedAt: Date, citationStatus: RetrievalCitationStatus = .current
    ) {
        self.id = id
        self.analysisID = analysisID
        self.label = label
        self.noteID = noteID
        self.notePath = notePath
        self.noteTitle = noteTitle
        self.quotedSnippet = quotedSnippet
        self.sourceModifiedAt = sourceModifiedAt
        self.citationStatus = citationStatus
    }
}

public enum AnalysisReviewDecision: String, Codable, CaseIterable, Sendable {
    case pending = "Pending review"
    case accepted = "Accepted as a useful suggestion"
    case dismissed = "Dismissed"
    case needsRevision = "Needs revision"
}

public struct AnalysisReview: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var analysisID: UUID
    public var decision: AnalysisReviewDecision
    public var notes: String
    public var reviewedAt: Date

    public init(id: UUID = UUID(), analysisID: UUID, decision: AnalysisReviewDecision, notes: String = "", reviewedAt: Date = Date()) {
        self.id = id
        self.analysisID = analysisID
        self.decision = decision
        self.notes = notes
        self.reviewedAt = reviewedAt
    }
}

public struct GroundedAnswerClaim: Hashable, Codable, Sendable {
    public var text: String
    public var citations: [String]
    public var interpretation: Bool

    public init(text: String, citations: [String], interpretation: Bool) {
        self.text = text
        self.citations = citations
        self.interpretation = interpretation
    }
}

public struct GroundedAnswer: Hashable, Codable, Sendable {
    public var answer: String
    public var insufficientEvidence: Bool
    public var insufficiencyReason: String
    public var claims: [GroundedAnswerClaim]

    public init(answer: String, insufficientEvidence: Bool, insufficiencyReason: String, claims: [GroundedAnswerClaim]) {
        self.answer = answer
        self.insufficientEvidence = insufficientEvidence
        self.insufficiencyReason = insufficiencyReason
        self.claims = claims
    }

    enum CodingKeys: String, CodingKey {
        case answer
        case insufficientEvidence = "insufficient_evidence"
        case insufficiencyReason = "insufficiency_reason"
        case claims
    }
}

public struct AITransmissionSourcePreview: Identifiable, Hashable, Sendable {
    public var id: String { label }
    public var label: String
    public var sourceClass: String
    public var title: String
    public var location: String?
    public var excerpt: String

    public var summaryLabel: String {
        let locationText = location.map { ", \($0.lowercased())" } ?? ""
        return "[\(label)] \(sourceClass): \(title)\(locationText)"
    }

    public init(label: String, sourceClass: String, title: String, location: String? = nil, excerpt: String) {
        self.label = label
        self.sourceClass = sourceClass
        self.title = title
        self.location = location
        self.excerpt = excerpt
    }
}

public struct AITransmissionPreview: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var analysisKind: AIAnalysisKind
    public var provider: AIProviderKind
    public var endpoint: String
    public var model: String
    public var reasoningEffort: AIReasoningEffort?
    public var maximumOutputTokens: Int
    public var query: String
    public var retrievalSetID: UUID
    public var sourceLabels: [String]
    public var sourcePreviews: [AITransmissionSourcePreview]
    public var passageCount: Int
    public var characterCount: Int

    public init(
        id: UUID = UUID(), analysisKind: AIAnalysisKind, provider: AIProviderKind,
        endpoint: String, model: String, reasoningEffort: AIReasoningEffort?,
        maximumOutputTokens: Int, query: String, retrievalSetID: UUID,
        sourceLabels: [String], sourcePreviews: [AITransmissionSourcePreview] = [],
        passageCount: Int, characterCount: Int
    ) {
        self.id = id
        self.analysisKind = analysisKind
        self.provider = provider
        self.endpoint = endpoint
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.maximumOutputTokens = maximumOutputTokens
        self.query = query
        self.retrievalSetID = retrievalSetID
        self.sourceLabels = sourceLabels
        self.sourcePreviews = sourcePreviews
        self.passageCount = passageCount
        self.characterCount = characterCount
    }
}

public enum BiasConcernKind: String, Codable, CaseIterable, Sendable {
    case selectiveEvidence = "Selective use of supporting evidence"
    case neglectedConflict = "Conflicting evidence needs attention"
    case overgeneralisation = "Possible overgeneralisation"
    case conceptualAmbiguity = "Conceptual ambiguity"
    case designMismatch = "Research designs may not be comparable"
    case correlationCausation = "Correlation and causation need separation"
    case evidenceScope = "Claim may exceed available evidence"
    case constructConflation = "Related constructs may be treated as identical"
    case alternativeExplanation = "Alternative explanations need consideration"
    case sourceConcentration = "Evidence is concentrated in few sources"
}

public enum ReviewDisposition: String, Codable, CaseIterable, Sendable {
    case pending = "Pending review"
    case accepted = "Accepted for investigation"
    case dismissed = "Dismissed"
    case addressed = "Addressed"
}

public struct BiasAudit: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var argumentID: UUID
    public var title: String
    public var scopeNote: String
    public var origin: RecordOrigin
    public var analysisID: UUID?
    public var createdAt: Date

    public init(
        id: UUID = UUID(), argumentID: UUID, title: String, scopeNote: String = "",
        origin: RecordOrigin = .user, analysisID: UUID? = nil, createdAt: Date = Date()
    ) {
        self.id = id
        self.argumentID = argumentID
        self.title = title
        self.scopeNote = scopeNote
        self.origin = origin
        self.analysisID = analysisID
        self.createdAt = createdAt
    }
}

public struct BiasConcern: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var auditID: UUID
    public var kind: BiasConcernKind
    public var potentialProblem: String
    public var whyItMatters: String
    public var alternativeInterpretations: String
    public var investigationQuestions: [String]
    public var evidenceRelationshipIDs: [UUID]
    public var uncertainty: String
    public var origin: RecordOrigin
    public var disposition: ReviewDisposition
    public var reviewNotes: String
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(), auditID: UUID, kind: BiasConcernKind, potentialProblem: String,
        whyItMatters: String = "", alternativeInterpretations: String = "",
        investigationQuestions: [String] = [], evidenceRelationshipIDs: [UUID] = [],
        uncertainty: String = "Requires human evaluation", origin: RecordOrigin = .user,
        disposition: ReviewDisposition = .pending, reviewNotes: String = "",
        createdAt: Date = Date(), modifiedAt: Date = Date()
    ) {
        self.id = id
        self.auditID = auditID
        self.kind = kind
        self.potentialProblem = potentialProblem
        self.whyItMatters = whyItMatters
        self.alternativeInterpretations = alternativeInterpretations
        self.investigationQuestions = investigationQuestions
        self.evidenceRelationshipIDs = evidenceRelationshipIDs
        self.uncertainty = uncertainty
        self.origin = origin
        self.disposition = disposition
        self.reviewNotes = reviewNotes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

public enum DeliberationStatus: String, Codable, CaseIterable, Sendable {
    case prepared = "Prepared"
    case inProgress = "In progress"
    case completed = "Completed"
    case failed = "Failed"
}

public struct DeliberationSession: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var argumentID: UUID
    public var title: String
    public var provider: String
    public var model: String
    public var promptVersion: String
    public var disclosure: String
    public var status: DeliberationStatus
    public var createdAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(), argumentID: UUID, title: String, provider: String = "Not requested",
        model: String = "Not requested", promptVersion: String = "deliberation-record-v1",
        disclosure: String = "Generated perspectives are simulated roles, not independent experts or independent evidence.",
        status: DeliberationStatus = .prepared, createdAt: Date = Date(), completedAt: Date? = nil
    ) {
        self.id = id
        self.argumentID = argumentID
        self.title = title
        self.provider = provider
        self.model = model
        self.promptVersion = promptVersion
        self.disclosure = disclosure
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

public enum DeliberationPerspective: String, Codable, CaseIterable, Sendable {
    case user = "Researcher"
    case theoretical = "Theoretical Critic"
    case methodological = "Methodological Critic"
    case evidence = "Evidence Reviewer"
    case alternative = "Alternative Explanation Reviewer"
    case synthesis = "Synthesis Perspective"
}

public enum DeliberationPhase: String, Codable, CaseIterable, Sendable {
    case initial = "Initial assessment"
    case crossExamination = "Cross-examination"
    case revision = "Revised assessment"
    case synthesis = "Synthesis"
    case userResponse = "Researcher response"
}

public struct DeliberationMessage: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var perspective: DeliberationPerspective
    public var phase: DeliberationPhase
    public var content: String
    public var sequence: Int
    public var modelGenerated: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(), sessionID: UUID, perspective: DeliberationPerspective,
        phase: DeliberationPhase, content: String, sequence: Int,
        modelGenerated: Bool, createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.perspective = perspective
        self.phase = phase
        self.content = content
        self.sequence = sequence
        self.modelGenerated = modelGenerated
        self.createdAt = createdAt
    }
}

public struct DeliberationCitation: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var messageID: UUID
    public var label: String
    public var literatureID: UUID
    public var sourcePassageID: String
    public var page: Int
    public var quotedPassage: String
    public var sourceDocumentHash: String?
    public var citationStatus: RetrievalCitationStatus

    public init(
        id: UUID = UUID(), messageID: UUID, label: String, literatureID: UUID,
        sourcePassageID: String, page: Int, quotedPassage: String,
        sourceDocumentHash: String? = nil, citationStatus: RetrievalCitationStatus = .current
    ) {
        self.id = id
        self.messageID = messageID
        self.label = label
        self.literatureID = literatureID
        self.sourcePassageID = sourcePassageID
        self.page = page
        self.quotedPassage = quotedPassage
        self.sourceDocumentHash = sourceDocumentHash
        self.citationStatus = citationStatus
    }
}

public enum WritingPurpose: String, Codable, CaseIterable, Sendable {
    case literatureReview = "Literature review"
    case conceptualFramework = "Conceptual framework"
    case researchQuestion = "Research question refinement"
    case methodComparison = "Methodological comparison"
    case conflictingFindings = "Conflicting findings"
    case discussion = "Discussion"
    case researchNote = "Structured research note"
}

public struct WritingDocument: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var projectID: UUID?
    public var questionID: UUID?
    public var title: String
    public var purpose: WritingPurpose
    public var status: String
    public var notes: String
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(), projectID: UUID? = nil, questionID: UUID? = nil,
        title: String, purpose: WritingPurpose = .researchNote, status: String = "Planning",
        notes: String = "", createdAt: Date = Date(), modifiedAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.questionID = questionID
        self.title = title
        self.purpose = purpose
        self.status = status
        self.notes = notes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

public struct WritingSection: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var documentID: UUID
    public var title: String
    public var body: String
    public var position: Int
    public var notes: String
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(), documentID: UUID, title: String, body: String = "",
        position: Int, notes: String = "", createdAt: Date = Date(), modifiedAt: Date = Date()
    ) {
        self.id = id
        self.documentID = documentID
        self.title = title
        self.body = body
        self.position = position
        self.notes = notes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

public enum WritingEvidenceTargetType: String, Codable, CaseIterable, Sendable {
    case claim = "Structured claim"
    case argumentEvidence = "Argument evidence"
    case literature = "Literature item"
    case argument = "Research argument"
}

public struct WritingEvidenceLink: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var sectionID: UUID
    public var targetType: WritingEvidenceTargetType
    public var targetID: String
    public var citationKey: String?
    public var rationale: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(), sectionID: UUID, targetType: WritingEvidenceTargetType,
        targetID: String, citationKey: String? = nil, rationale: String = "", createdAt: Date = Date()
    ) {
        self.id = id
        self.sectionID = sectionID
        self.targetType = targetType
        self.targetID = targetID
        self.citationKey = citationKey
        self.rationale = rationale
        self.createdAt = createdAt
    }
}

public enum CitationSupportAssessment: String, Codable, CaseIterable, Sendable {
    case pending = "Pending review"
    case appearsSupported = "Appears supported"
    case partiallySupported = "Partially supported or overbroad"
    case unsupported = "Potentially unsupported"
    case staleSource = "Source snapshot is stale"
    case requiresHumanReview = "Requires human source review"
}

public struct CitationSupportReview: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var sectionID: UUID
    public var statement: String
    public var evidenceLinkID: UUID?
    public var assessment: CitationSupportAssessment
    public var concern: String
    public var origin: RecordOrigin
    public var modelIdentifier: String?
    public var promptVersion: String?
    public var reviewNotes: String
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(), sectionID: UUID, statement: String, evidenceLinkID: UUID? = nil,
        assessment: CitationSupportAssessment = .pending, concern: String = "",
        origin: RecordOrigin = .user, modelIdentifier: String? = nil, promptVersion: String? = nil,
        reviewNotes: String = "", createdAt: Date = Date(), modifiedAt: Date = Date()
    ) {
        self.id = id
        self.sectionID = sectionID
        self.statement = statement
        self.evidenceLinkID = evidenceLinkID
        self.assessment = assessment
        self.concern = concern
        self.origin = origin
        self.modelIdentifier = modelIdentifier
        self.promptVersion = promptVersion
        self.reviewNotes = reviewNotes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

public enum CollectiveInteractionMode: String, Codable, CaseIterable, Sendable {
    case independent = "Independent assessments"
    case sequential = "Sequential deliberation"
    case sharedInformation = "Shared information"
    case structuredDisagreement = "Structured disagreement"
    case assignedRoles = "Assigned argumentative roles"
    case majorityInfluence = "Majority-influence simulation"
    case contrarian = "Contrarian prompting"
    case confidenceRevision = "Confidence and judgment revision"
}

public enum CollectiveExperimentStatus: String, Codable, CaseIterable, Sendable {
    case designing = "Designing"
    case ready = "Ready"
    case running = "Running"
    case completed = "Completed"
    case interrupted = "Interrupted"
    case archived = "Archived"
}

public struct CollectiveExperiment: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var researchPurpose: String
    public var taskInstructions: String
    public var interactionMode: CollectiveInteractionMode
    public var provider: String
    public var model: String
    public var modelSettingsJSON: String
    public var promptVersion: String
    public var status: CollectiveExperimentStatus
    public var validationNote: String
    public var createdAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(), title: String, researchPurpose: String = "", taskInstructions: String = "",
        interactionMode: CollectiveInteractionMode = .independent, provider: String = "Not configured",
        model: String = "Not configured", modelSettingsJSON: String = "{}",
        promptVersion: String = "collective-lab-record-v1", status: CollectiveExperimentStatus = .designing,
        validationNote: String = "Exploratory simulation only; not validated as a measure of human collective intelligence.",
        createdAt: Date = Date(), completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.researchPurpose = researchPurpose
        self.taskInstructions = taskInstructions
        self.interactionMode = interactionMode
        self.provider = provider
        self.model = model
        self.modelSettingsJSON = modelSettingsJSON
        self.promptVersion = promptVersion
        self.status = status
        self.validationNote = validationNote
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

public struct CollectiveAgent: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var experimentID: UUID
    public var label: String
    public var role: String
    public var informationAvailable: String
    public var position: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(), experimentID: UUID, label: String, role: String = "",
        informationAvailable: String = "", position: Int, createdAt: Date = Date()
    ) {
        self.id = id
        self.experimentID = experimentID
        self.label = label
        self.role = role
        self.informationAvailable = informationAvailable
        self.position = position
        self.createdAt = createdAt
    }
}

public enum CollectiveTurnKind: String, Codable, CaseIterable, Sendable {
    case initialJudgment = "Initial judgment"
    case deliberation = "Deliberation contribution"
    case revisedJudgment = "Revised judgment"
    case finalResponse = "Final response"
    case researcherObservation = "Researcher observation"
    case interruption = "Error or interruption"
}

public struct CollectiveTurn: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var experimentID: UUID
    public var agentID: UUID?
    public var round: Int
    public var sequence: Int
    public var kind: CollectiveTurnKind
    public var informationAvailable: String
    public var promptText: String
    public var responseText: String
    public var confidence: Double?
    public var modelGenerated: Bool
    public var errorMessage: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(), experimentID: UUID, agentID: UUID? = nil, round: Int,
        sequence: Int, kind: CollectiveTurnKind, informationAvailable: String = "",
        promptText: String = "", responseText: String, confidence: Double? = nil,
        modelGenerated: Bool = false, errorMessage: String? = nil, createdAt: Date = Date()
    ) {
        self.id = id
        self.experimentID = experimentID
        self.agentID = agentID
        self.round = round
        self.sequence = sequence
        self.kind = kind
        self.informationAvailable = informationAvailable
        self.promptText = promptText
        self.responseText = responseText
        self.confidence = confidence
        self.modelGenerated = modelGenerated
        self.errorMessage = errorMessage
        self.createdAt = createdAt
    }
}

public struct CollectiveTurnCitation: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var turnID: UUID
    public var label: String
    public var literatureID: UUID
    public var sourcePassageID: String
    public var page: Int
    public var quotedPassage: String
    public var sourceDocumentHash: String?
    public var citationStatus: RetrievalCitationStatus

    public init(
        id: UUID = UUID(), turnID: UUID, label: String, literatureID: UUID,
        sourcePassageID: String, page: Int, quotedPassage: String,
        sourceDocumentHash: String? = nil, citationStatus: RetrievalCitationStatus = .current
    ) {
        self.id = id
        self.turnID = turnID
        self.label = label
        self.literatureID = literatureID
        self.sourcePassageID = sourcePassageID
        self.page = page
        self.quotedPassage = quotedPassage
        self.sourceDocumentHash = sourceDocumentHash
        self.citationStatus = citationStatus
    }
}

public enum IndexingJobKind: String, Codable, CaseIterable, Sendable {
    case pdf = "PDF indexing"
    case researchFolder = "Research-folder indexing"
    case obsidian = "Obsidian indexing"
    case searchRebuild = "Search-index rebuild"
}

public enum IndexingJobStatus: String, Codable, CaseIterable, Sendable {
    case queued = "Queued"
    case running = "Running"
    case completed = "Completed"
    case cancelled = "Cancelled"
    case failed = "Failed"
}

public struct IndexingJob: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var kind: IndexingJobKind
    public var sourceName: String
    public var status: IndexingJobStatus
    public var completedUnits: Int
    public var totalUnits: Int?
    public var failureMessage: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        kind: IndexingJobKind,
        sourceName: String,
        status: IndexingJobStatus = .queued,
        completedUnits: Int = 0,
        totalUnits: Int? = nil,
        failureMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.sourceName = sourceName
        self.status = status
        self.completedUnits = completedUnits
        self.totalUnits = totalUnits
        self.failureMessage = failureMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct SearchResult: Identifiable, Hashable, Sendable {
    public var id: String { "\(entityType):\(entityID)" }
    public let entityID: String
    public let entityType: String
    public let title: String
    public let snippet: String

    public init(entityID: String, entityType: String, title: String, snippet: String) {
        self.entityID = entityID
        self.entityType = entityType
        self.title = title
        self.snippet = snippet
    }
}

public struct HomeMetrics: Equatable, Sendable {
    public let literatureCount: Int
    public let noteCount: Int
    public let questionCount: Int
    public let argumentCount: Int

    public init(literatureCount: Int = 0, noteCount: Int = 0, questionCount: Int = 0, argumentCount: Int = 0) {
        self.literatureCount = literatureCount
        self.noteCount = noteCount
        self.questionCount = questionCount
        self.argumentCount = argumentCount
    }
}

public struct DatabaseRestorePreview: Identifiable, Equatable, Sendable {
    public var id: String { url.standardizedFileURL.path }
    public let url: URL
    public let schemaVersion: Int
    public let literatureCount: Int
    public let noteCount: Int
    public let projectCount: Int
    public let questionCount: Int
    public let argumentCount: Int
    public let evidenceCount: Int

    public var totalRecordCount: Int {
        literatureCount + noteCount + projectCount + questionCount + argumentCount + evidenceCount
    }

    public init(
        url: URL,
        schemaVersion: Int,
        literatureCount: Int,
        noteCount: Int,
        projectCount: Int,
        questionCount: Int,
        argumentCount: Int,
        evidenceCount: Int
    ) {
        self.url = url
        self.schemaVersion = schemaVersion
        self.literatureCount = literatureCount
        self.noteCount = noteCount
        self.projectCount = projectCount
        self.questionCount = questionCount
        self.argumentCount = argumentCount
        self.evidenceCount = evidenceCount
    }
}

public struct ResearchExportBundle: Codable, Sendable {
    public let formatVersion: Int
    public let exportedAt: Date
    public let literature: [LiteratureItem]
    public let notes: [ObsidianNote]
    public let noteLinks: [PaperNoteLink]
    public let projects: [ResearchProject]
    public let questions: [ResearchQuestion]
    public let arguments: [ResearchArgument]
    public let argumentVersions: [ArgumentVersion]
    public let evidence: [EvidenceRelationship]
    public let zoteroLibraries: [ZoteroLibrary]
    public let zoteroCollections: [ZoteroCollection]
    public let literatureCollectionMemberships: [LiteratureCollectionMembership]
    public let comparisonProfiles: [LiteratureComparisonProfile]
    public let retrievalSets: [RetrievalSet]
    public let retrievedPassages: [RetrievedPassage]
    public let retrievedNoteSnippets: [RetrievedNoteSnippet]
    public let concepts: [ResearchConcept]
    public let knowledgeRelationships: [KnowledgeRelationship]
    public let indexingJobs: [IndexingJob]
    public let questionVersions: [ResearchQuestionVersion]
    public let questionLiteratureAssociations: [QuestionLiteratureAssociation]
    public let questionConceptAssociations: [QuestionConceptAssociation]
    public let claims: [ResearchClaim]
    public let claimVersions: [ClaimVersion]
    public let ideas: [ResearchIdea]
    public let ideaVersions: [IdeaVersion]
    public let ideaLinks: [ResearchIdeaLink]
    public let contradictionCases: [ContradictionCase]
    public let contradictionSources: [ContradictionSource]
    public let historyEvents: [HistoryEvent]
    public let aiProviderConfiguration: AIProviderConfiguration?
    public let aiAnalyses: [AIAnalysis]
    public let aiAnalysisCitations: [AIAnalysisCitation]
    public let aiAnalysisNoteCitations: [AIAnalysisNoteCitation]
    public let analysisReviews: [AnalysisReview]
    public let biasAudits: [BiasAudit]
    public let biasConcerns: [BiasConcern]
    public let deliberationSessions: [DeliberationSession]
    public let deliberationMessages: [DeliberationMessage]
    public let deliberationCitations: [DeliberationCitation]
    public let writingDocuments: [WritingDocument]
    public let writingSections: [WritingSection]
    public let writingEvidenceLinks: [WritingEvidenceLink]
    public let citationSupportReviews: [CitationSupportReview]
    public let collectiveExperiments: [CollectiveExperiment]
    public let collectiveAgents: [CollectiveAgent]
    public let collectiveTurns: [CollectiveTurn]
    public let collectiveTurnCitations: [CollectiveTurnCitation]

    public init(
        formatVersion: Int = 9,
        exportedAt: Date = Date(),
        literature: [LiteratureItem],
        notes: [ObsidianNote],
        noteLinks: [PaperNoteLink],
        projects: [ResearchProject],
        questions: [ResearchQuestion],
        arguments: [ResearchArgument],
        argumentVersions: [ArgumentVersion],
        evidence: [EvidenceRelationship],
        zoteroLibraries: [ZoteroLibrary] = [],
        zoteroCollections: [ZoteroCollection] = [],
        literatureCollectionMemberships: [LiteratureCollectionMembership] = [],
        comparisonProfiles: [LiteratureComparisonProfile] = [],
        retrievalSets: [RetrievalSet] = [],
        retrievedPassages: [RetrievedPassage] = [],
        retrievedNoteSnippets: [RetrievedNoteSnippet] = [],
        concepts: [ResearchConcept] = [],
        knowledgeRelationships: [KnowledgeRelationship] = [],
        indexingJobs: [IndexingJob] = [],
        questionVersions: [ResearchQuestionVersion] = [],
        questionLiteratureAssociations: [QuestionLiteratureAssociation] = [],
        questionConceptAssociations: [QuestionConceptAssociation] = [],
        claims: [ResearchClaim] = [],
        claimVersions: [ClaimVersion] = [],
        ideas: [ResearchIdea] = [],
        ideaVersions: [IdeaVersion] = [],
        ideaLinks: [ResearchIdeaLink] = [],
        contradictionCases: [ContradictionCase] = [],
        contradictionSources: [ContradictionSource] = [],
        historyEvents: [HistoryEvent] = [],
        aiProviderConfiguration: AIProviderConfiguration? = nil,
        aiAnalyses: [AIAnalysis] = [],
        aiAnalysisCitations: [AIAnalysisCitation] = [],
        aiAnalysisNoteCitations: [AIAnalysisNoteCitation] = [],
        analysisReviews: [AnalysisReview] = [],
        biasAudits: [BiasAudit] = [], biasConcerns: [BiasConcern] = [],
        deliberationSessions: [DeliberationSession] = [], deliberationMessages: [DeliberationMessage] = [],
        deliberationCitations: [DeliberationCitation] = [], writingDocuments: [WritingDocument] = [],
        writingSections: [WritingSection] = [], writingEvidenceLinks: [WritingEvidenceLink] = [],
        citationSupportReviews: [CitationSupportReview] = [],
        collectiveExperiments: [CollectiveExperiment] = [], collectiveAgents: [CollectiveAgent] = [],
        collectiveTurns: [CollectiveTurn] = [], collectiveTurnCitations: [CollectiveTurnCitation] = []
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.literature = literature
        self.notes = notes
        self.noteLinks = noteLinks
        self.projects = projects
        self.questions = questions
        self.arguments = arguments
        self.argumentVersions = argumentVersions
        self.evidence = evidence
        self.zoteroLibraries = zoteroLibraries
        self.zoteroCollections = zoteroCollections
        self.literatureCollectionMemberships = literatureCollectionMemberships
        self.comparisonProfiles = comparisonProfiles
        self.retrievalSets = retrievalSets
        self.retrievedPassages = retrievedPassages
        self.retrievedNoteSnippets = retrievedNoteSnippets
        self.concepts = concepts
        self.knowledgeRelationships = knowledgeRelationships
        self.indexingJobs = indexingJobs
        self.questionVersions = questionVersions
        self.questionLiteratureAssociations = questionLiteratureAssociations
        self.questionConceptAssociations = questionConceptAssociations
        self.claims = claims
        self.claimVersions = claimVersions
        self.ideas = ideas
        self.ideaVersions = ideaVersions
        self.ideaLinks = ideaLinks
        self.contradictionCases = contradictionCases
        self.contradictionSources = contradictionSources
        self.historyEvents = historyEvents
        self.aiProviderConfiguration = aiProviderConfiguration
        self.aiAnalyses = aiAnalyses
        self.aiAnalysisCitations = aiAnalysisCitations
        self.aiAnalysisNoteCitations = aiAnalysisNoteCitations
        self.analysisReviews = analysisReviews
        self.biasAudits = biasAudits
        self.biasConcerns = biasConcerns
        self.deliberationSessions = deliberationSessions
        self.deliberationMessages = deliberationMessages
        self.deliberationCitations = deliberationCitations
        self.writingDocuments = writingDocuments
        self.writingSections = writingSections
        self.writingEvidenceLinks = writingEvidenceLinks
        self.citationSupportReviews = citationSupportReviews
        self.collectiveExperiments = collectiveExperiments
        self.collectiveAgents = collectiveAgents
        self.collectiveTurns = collectiveTurns
        self.collectiveTurnCitations = collectiveTurnCitations
    }
}
