import Foundation
import ResearchAtlasCore
import SQLite3

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw CheckFailure(description: message) }
}

struct DatabaseFixture {
    let directory: URL
    let database: AtlasDatabase

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ResearchAtlasChecks-\(UUID().uuidString)", isDirectory: true)
        database = try AtlasDatabase(url: directory.appendingPathComponent("fixture.sqlite3"))
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

func checkResearchWorkflow() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }
    let source = LiteratureItem(title: "A source paper", authors: "Researcher, A.", year: 2025, abstract: "A controlled study.")
    try fixture.database.upsertLiterature(source)
    let project = ResearchProject(title: "Decision quality")
    try fixture.database.saveProject(project)
    let question = ResearchQuestion(projectID: project.id, question: "When does advice improve group decisions?")
    try fixture.database.saveQuestion(question)
    let argument = ResearchArgument(questionID: question.id, proposition: "Advice quality moderates group performance.")
    try fixture.database.saveArgument(argument)
    let evidence = EvidenceRelationship(argumentID: argument.id, literatureID: source.id, relation: .qualifies, summary: "The effect depends on advice accuracy.", page: 12, quotedPassage: "Effects differed by advice accuracy.", verification: .verified)
    try fixture.database.saveEvidence(evidence)

    try expect(try fixture.database.projects().first?.title == project.title, "Project round trip failed")
    try expect(try fixture.database.questions(projectID: project.id).first?.question == question.question, "Question round trip failed")
    try expect(try fixture.database.arguments().first?.proposition == argument.proposition, "Argument round trip failed")
    let storedEvidence = try fixture.database.evidence(argumentID: argument.id).first
    try expect(storedEvidence?.quotedPassage == evidence.quotedPassage, "Evidence quotation was not preserved")
    try expect(storedEvidence?.page == 12 && storedEvidence?.verification == .verified, "Evidence provenance was not preserved")
    try expect(try fixture.database.metrics() == HomeMetrics(literatureCount: 1, noteCount: 0, questionCount: 1, argumentCount: 1), "Metrics are incorrect")
}

func checkZoteroDeduplication() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }
    try fixture.database.upsertLiterature(LiteratureItem(zoteroKey: "ABCD1234", title: "Original title", source: .zotero))
    try fixture.database.upsertLiterature(LiteratureItem(zoteroKey: "ABCD1234", title: "Revised title", authors: "Author", source: .zotero))
    let items = try fixture.database.literatureItems()
    try expect(items.count == 1, "A Zotero refresh created a duplicate")
    try expect(items.first?.title == "Revised title" && items.first?.authors == "Author", "A Zotero refresh did not update metadata")
}

func checkFullTextSearch() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }
    let source = LiteratureItem(title: "Human–AI deliberation", abstract: "Collective reasoning with calibrated advice")
    let decoy = LiteratureItem(title: "Separated terms", abstract: "Collective methods can be assessed separately from reasoning outcomes")
    try fixture.database.upsertLiterature(
        source,
        indexingPDFPages: ["The manipulation altered confidence calibration.", "No effect on response time."]
    )
    try fixture.database.upsertLiterature(decoy)
    try fixture.database.upsertObsidianNote(ObsidianNote(path: "/fixtures/idea.md", title: "Interpretation", content: "Consider whether conformity is an alternative explanation."))
    try expect(try fixture.database.search("calibrated").contains { $0.entityType == "literature" }, "Literature metadata was not searchable")
    try expect(try fixture.database.search("calibr").contains { $0.entityID == source.id.uuidString }, "Prefix search stopped matching partial terms")
    let exactPhrase = try fixture.database.search("\"collective reasoning\"")
    try expect(exactPhrase.contains { $0.entityID == source.id.uuidString }, "Quoted exact-phrase search did not find adjacent terms")
    try expect(!exactPhrase.contains { $0.entityID == decoy.id.uuidString }, "Quoted exact-phrase search matched separated terms")
    try expect(try fixture.database.search("\"reasoning collective\"").isEmpty, "Quoted exact-phrase search ignored word order")
    try expect(try fixture.database.search("“collective reasoning”").contains { $0.entityID == source.id.uuidString }, "Smart-quoted exact phrase was not recognised")
    try expect(try fixture.database.search("confidence-calibr").contains { $0.entityType == "passage" }, "Punctuated prefix terms were not tokenised safely")
    try expect(try fixture.database.search("confidence").contains { $0.entityType == "passage" && $0.entityID.hasSuffix(":1") }, "PDF page text was not searchable")
    try expect(try fixture.database.search("conformity").contains { $0.entityType == "note" }, "Obsidian content was not searchable")
    let passage = try fixture.database.sourcePassage(id: "\(source.id.uuidString):1")
    try expect(passage?.literatureID == source.id && passage?.page == 1, "A PDF search result could not resolve its exact source page")
    try expect(passage?.passageText == "The manipulation altered confidence calibration.", "Resolved PDF search passage text did not match the indexed source")
}

func checkObsidianParsing() throws {
    let markdown = """
    ---
    title: Deliberation notes
    tags: [collective-intelligence, methods]
    ---
    # Working interpretation

    See [[Advice quality#Results|the results]], @smith2024, and https://doi.org/10.1234/example.56.
    #bias
    """
    let url = URL(fileURLWithPath: "/fixtures/deliberation.md")
    let note = ObsidianIntegration.parse(content: markdown, url: url)
    try expect(note.title == "Working interpretation", "Markdown heading title was not parsed")
    try expect(note.tags.contains("collective-intelligence") && note.tags.contains("bias"), "Tags were not parsed")
    try expect(note.wikilinks == ["Advice quality"], "Wikilink was not parsed")
    try expect(note.citationKeys == ["smith2024"], "Citation key was not parsed")
    try expect(note.dois == ["10.1234/example.56"], "DOI was not parsed")
}

func checkObsidianDiscovery() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ResearchAtlasVault-\(UUID().uuidString)", isDirectory: true)
    let nested = directory.appendingPathComponent("Literature", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try "# Paper note\nEvidence.".write(to: nested.appendingPathComponent("paper.md"), atomically: true, encoding: .utf8)
    try "Not a note".write(to: nested.appendingPathComponent("image.txt"), atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: directory) }
    let result = ObsidianIntegration.discoverNotes(in: directory)
    try expect(result.notes.count == 1 && result.notes.first?.title == "Paper note", "Recursive note discovery failed")
    try expect(result.failures.isEmpty, "Unexpected note discovery failure")
}

func checkLocalResearchFolderDiscovery() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ResearchAtlasLibrary-\(UUID().uuidString)", isDirectory: true)
    let nested = directory.appendingPathComponent("Methods", isDirectory: true)
    let hidden = directory.appendingPathComponent(".private", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
    try Data("first".utf8).write(to: directory.appendingPathComponent("A paper.PDF"))
    try Data("second".utf8).write(to: nested.appendingPathComponent("B paper.pdf"))
    try Data("ignore".utf8).write(to: nested.appendingPathComponent("notes.txt"))
    try Data("hidden".utf8).write(to: hidden.appendingPathComponent("hidden.pdf"))
    defer { try? FileManager.default.removeItem(at: directory) }

    let discovered = try LocalResearchFolderScanner.discoverPDFs(at: directory)
    try expect(discovered.map(\.lastPathComponent) == ["A paper.PDF", "B paper.pdf"], "Local PDF discovery was not recursive, filtered, and deterministic")
}

func checkExplicitNoteMatchingAndReview() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }
    let doiPaper = LiteratureItem(title: "DOI paper", doi: "https://doi.org/10.1234/Atlas.1")
    let citePaper = LiteratureItem(title: "Citation paper", citationKey: "Smith2025Collective", tags: ["collective-intelligence"])
    let zoteroPaper = LiteratureItem(zoteroKey: "ABCD1234", title: "Zotero-linked paper", source: .zotero)
    for item in [doiPaper, citePaper, zoteroPaper] { try fixture.database.upsertLiterature(item) }
    let note = ObsidianNote(
        path: "/fixtures/links.md",
        title: "Explicit links",
        content: "Citations @Smith2025Collective and zotero://select/library/items/ABCD1234",
        citationKeys: ["Smith2025Collective"],
        dois: ["10.1234/atlas.1"]
    )
    try fixture.database.upsertObsidianNote(note)
    let persistedLiterature = try fixture.database.literatureItems()
    try expect(persistedLiterature.first(where: { $0.id == citePaper.id })?.tags == ["collective-intelligence"], "Zotero-style tags were not persisted")
    let suggestions = NoteMatcher.suggestions(notes: [note], literature: persistedLiterature)
    try expect(Set(suggestions.map(\.method)) == Set([.doi, .citationKey, .zoteroItemLink]), "Explicit identifier matches were not generated")
    for suggestion in suggestions { try fixture.database.saveNoteLinkSuggestion(suggestion) }
    guard var reviewed = try fixture.database.noteLinks().first(where: { $0.method == .doi }) else {
        throw CheckFailure(description: "Note-link suggestion was not persisted")
    }
    reviewed.state = .rejected
    try fixture.database.saveNoteLink(reviewed)
    if let repeatedSuggestion = suggestions.first(where: { $0.method == .doi }) {
        try fixture.database.saveNoteLinkSuggestion(repeatedSuggestion)
    }
    let stored = try fixture.database.noteLinks().first { $0.id == reviewed.id }
    try expect(stored?.state == .rejected, "A repeated scan overwrote the user's note-link decision")
}

func checkManualAndOptionalTitleNoteLinks() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }
    let paper = LiteratureItem(title: "Calibrated AI Advice in Group Decisions")
    try fixture.database.upsertLiterature(paper)
    let note = ObsidianNote(
        path: "/fixtures/calibrated-advice.md",
        title: "Calibrated AI Advice in Group Decisions",
        content: "A personal interpretation without an explicit identifier."
    )
    try fixture.database.upsertObsidianNote(note)

    try expect(NoteMatcher.suggestions(notes: [note], literature: [paper]).isEmpty, "Title matching was enabled without user opt-in")
    let titleSuggestions = NoteMatcher.suggestions(notes: [note], literature: [paper], includeTitleMatches: true)
    try expect(titleSuggestions.count == 1 && titleSuggestions.first?.method == .title, "Opt-in title matching did not produce a labelled suggestion")
    try fixture.database.saveNoteLinkSuggestion(titleSuggestions[0])

    var manualLink = PaperNoteLink(
        noteID: note.id, literatureID: paper.id, method: .manual,
        matchedIdentifier: note.path, state: .confirmed
    )
    try fixture.database.saveNoteLink(manualLink)
    guard let stored = try fixture.database.noteLinks().first else {
        throw CheckFailure(description: "A manual note link was not stored")
    }
    try expect(stored.method == .manual && stored.state == .confirmed, "Manual linking did not override the unreviewed title suggestion")
    manualLink.id = stored.id
    try fixture.database.deleteNoteLink(id: manualLink.id)
    try expect(try fixture.database.noteLinks().isEmpty, "A manually removed note link remained in the database")
}

func checkArgumentHistoryExportAndBackup() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }
    let source = LiteratureItem(title: "Quoted, source", authors: "Researcher", doi: "10.1000/test")
    try fixture.database.upsertLiterature(source)
    var argument = ResearchArgument(proposition: "Initial proposition", qualification: "Initial boundary", status: "Developing")
    try fixture.database.saveArgument(argument)
    argument.proposition = "Revised proposition"
    argument.qualification = "Narrower boundary"
    argument.status = "Qualified"
    argument.modifiedAt = Date().addingTimeInterval(1)
    try fixture.database.saveArgument(argument, changeNote: "Narrowed after evidence review")
    try fixture.database.saveArgument(argument, changeNote: "This must not create a duplicate")
    try fixture.database.saveEvidence(EvidenceRelationship(argumentID: argument.id, literatureID: source.id, relation: .qualifies, summary: "A comma, and a qualification", page: 4, quotedPassage: "Exact source wording", verification: .verified))

    let versions = try fixture.database.argumentVersions(argumentID: argument.id)
    try expect(versions.count == 2, "Argument history did not record exactly the observed states")
    try expect(versions.first?.changeNote == "Narrowed after evidence review", "Argument revision rationale was not preserved")

    let bundle = try fixture.database.exportBundle()
    let files = try ResearchExporter.files(for: bundle)
    try expect(files["research-atlas.json"] != nil && files["research-atlas.md"] != nil, "Portable JSON or Markdown export is missing")
    try expect(String(data: files["evidence.csv"] ?? Data(), encoding: .utf8)?.contains("\"A comma, and a qualification\"") == true, "CSV values were not safely quoted")
    let decoded = try JSONDecoder.configuredForResearchAtlas.decode(ResearchExportBundle.self, from: files["research-atlas.json"] ?? Data())
    try expect(decoded.arguments.first?.proposition == "Revised proposition", "JSON export did not preserve the current argument")

    let backupURL = fixture.directory.appendingPathComponent("backup.sqlite3")
    try fixture.database.backup(to: backupURL)
    let restored = try AtlasDatabase(url: backupURL)
    try expect(try restored.metrics().literatureCount == 1 && restored.arguments().count == 1, "SQLite backup did not preserve the workspace")
}

func checkZoteroIncrementalStateAndSourcePartitioning() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }

    let firstSnapshot = ZoteroSnapshot(
        items: [LiteratureItem(
            zoteroKey: "SAMEKEY1",
            zoteroAttachmentKey: "PDFKEY01",
            zoteroVersion: 10,
            title: "Paper in the first library",
            source: .zotero,
            pdfPath: "/fixtures/first.pdf"
        )],
        serverID: "server-A",
        libraryVersion: 10,
        mode: .full
    )
    try fixture.database.applyZoteroSync(firstSnapshot)
    guard let firstPaper = try fixture.database.literatureItems().first else {
        throw CheckFailure(description: "The initial Zotero snapshot was not stored")
    }
    let argument = ResearchArgument(proposition: "A retained provenance claim")
    try fixture.database.saveArgument(argument)
    try fixture.database.saveEvidence(EvidenceRelationship(
        argumentID: argument.id,
        literatureID: firstPaper.id,
        relation: .supports,
        summary: "Evidence must remain attached to its original source partition."
    ))

    try fixture.database.applyZoteroSync(ZoteroSnapshot(
        items: [],
        deletedItemKeys: ["PDFKEY01"],
        serverID: "server-A",
        libraryVersion: 11,
        mode: .incremental
    ))
    let attachmentDeleted = try fixture.database.literatureItems().first { $0.id == firstPaper.id }
    try expect(attachmentDeleted?.sourceAvailability == .available, "Deleting an attachment incorrectly deleted its parent record")
    try expect(attachmentDeleted?.pdfPath == nil && attachmentDeleted?.zoteroAttachmentKey == nil, "A deleted Zotero attachment remained available")

    try fixture.database.applyZoteroSync(ZoteroSnapshot(
        items: [LiteratureItem(zoteroKey: "SAMEKEY1", zoteroVersion: 20, title: "Different paper with the same item key", source: .zotero)],
        serverID: "server-B",
        libraryVersion: 20,
        mode: .full
    ))
    let partitioned = try fixture.database.literatureItems()
    try expect(partitioned.count == 2, "Identical item keys from different Zotero libraries were collapsed")
    try expect(partitioned.first(where: { $0.id == firstPaper.id })?.sourceAvailability == .differentLibrary, "The previous library record was not marked unavailable")
    try expect(partitioned.first(where: { $0.zoteroServerID == "server-B" })?.sourceAvailability == .available, "The active library record was not marked available")
    try expect(try fixture.database.evidence(argumentID: argument.id).first?.literatureID == firstPaper.id, "A library switch rewired existing evidence to another source")
    try expect(try fixture.database.zoteroCheckpoint() == ZoteroCheckpoint(serverID: "server-B", libraryVersion: 20), "The committed Zotero checkpoint is incorrect")
}

func checkZoteroGroupLibrariesAndCollections() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }

    let userCollection = ZoteroCollection(
        serverID: "server-groups", libraryID: "user:0", key: "USERCOL1", name: "Core reading", version: 4
    )
    let groupParent = ZoteroCollection(
        serverID: "server-groups", libraryID: "group:42", key: "GROUPTOP", name: "Shared project", version: 7
    )
    let groupChild = ZoteroCollection(
        serverID: "server-groups", libraryID: "group:42", key: "GROUPSUB", name: "Methods",
        parentKey: "GROUPTOP", version: 7
    )
    let userPaper = LiteratureItem(zoteroKey: "SAMEKEY1", title: "User-library paper", source: .zotero)
    let groupPaper = LiteratureItem(zoteroKey: "SAMEKEY1", title: "Group-library paper", source: .zotero)

    try fixture.database.applyZoteroRefresh(ZoteroRefresh(
        serverID: "server-groups",
        snapshots: [
            ZoteroSnapshot(
                items: [userPaper], collections: [userCollection], itemCollectionKeys: ["SAMEKEY1": ["USERCOL1"]],
                serverID: "server-groups", libraryVersion: 4
            ),
            ZoteroSnapshot(
                items: [groupPaper], collections: [groupParent, groupChild], itemCollectionKeys: ["SAMEKEY1": ["GROUPSUB"]],
                serverID: "server-groups", libraryID: "group:42", libraryKind: .group,
                libraryName: "Collective Intelligence Lab", libraryMetadataVersion: 2, libraryVersion: 7
            )
        ],
        accessibleLibraryIDs: ["user:0", "group:42"]
    ))

    let imported = try fixture.database.literatureItems()
    try expect(imported.count == 2, "The same Zotero item key in a user and group library was collapsed")
    guard let importedGroupPaper = imported.first(where: { $0.zoteroLibraryID == "group:42" }) else {
        throw CheckFailure(description: "The group-library paper was not imported")
    }
    try expect(importedGroupPaper.zoteroLibraryName == "Collective Intelligence Lab", "The group-library name was not retained")
    let libraries = try fixture.database.zoteroLibraries()
    try expect(libraries.count == 2 && libraries.contains { $0.kind == .group && $0.libraryVersion == 7 }, "Per-library Zotero checkpoints were not stored")
    let memberships = try fixture.database.literatureCollectionMemberships()
    try expect(memberships.count == 2 && memberships.contains { $0.literatureID == importedGroupPaper.id && $0.collectionID.hasSuffix("|GROUPSUB") }, "Nested collection membership was not stored")

    let argument = ResearchArgument(proposition: "Group evidence remains attributable")
    try fixture.database.saveArgument(argument)
    try fixture.database.saveEvidence(EvidenceRelationship(
        argumentID: argument.id, literatureID: importedGroupPaper.id, relation: .supports,
        summary: "The source belongs to an accessible Zotero group library."
    ))

    try fixture.database.applyZoteroRefresh(ZoteroRefresh(
        serverID: "server-groups",
        snapshots: [ZoteroSnapshot(
            items: [], serverID: "server-groups", libraryVersion: 5, mode: .incremental
        )],
        accessibleLibraryIDs: ["user:0"]
    ))
    let retainedGroupPaper = try fixture.database.literatureItems().first { $0.id == importedGroupPaper.id }
    try expect(retainedGroupPaper?.sourceAvailability == .libraryUnavailable, "An inaccessible group library was not marked unavailable")
    try expect(try fixture.database.evidence(argumentID: argument.id).first?.literatureID == importedGroupPaper.id, "Losing group access removed or rewired evidence provenance")
    try expect(try fixture.database.zoteroCheckpoints().count == 1, "An inaccessible group checkpoint remained active")

    let bundle = try fixture.database.exportBundle()
    try expect(bundle.zoteroLibraries.count == 2 && bundle.zoteroCollections.count == 3, "Portable export omitted Zotero library or collection provenance")
}

func checkVersionFourMigrationPreservesEvidence() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ResearchAtlasV4-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("version-four.sqlite3")
    var connection: OpaquePointer?
    guard sqlite3_open(url.path, &connection) == SQLITE_OK, let rawConnection = connection else {
        throw CheckFailure(description: "Could not create the schema-4 migration fixture")
    }
    let sourceID = "11111111-1111-1111-1111-111111111111"
    let argumentID = "22222222-2222-2222-2222-222222222222"
    let evidenceID = "33333333-3333-3333-3333-333333333333"
    let schema = """
        PRAGMA foreign_keys=ON;
        CREATE TABLE schema_migrations(version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
        INSERT INTO schema_migrations VALUES(1,'2026-10-10T00:00:00Z'),(2,'2026-10-10T00:00:00Z'),(3,'2026-10-10T00:00:00Z'),(4,'2026-10-10T00:00:00Z');
        CREATE TABLE literature_items(
            id TEXT PRIMARY KEY,zotero_key TEXT UNIQUE,title TEXT NOT NULL,authors TEXT NOT NULL DEFAULT '',
            publication_year INTEGER,abstract_text TEXT NOT NULL DEFAULT '',doi TEXT,item_type TEXT NOT NULL,
            source TEXT NOT NULL,pdf_path TEXT,external_url TEXT,created_at TEXT NOT NULL,modified_at TEXT NOT NULL,
            citation_key TEXT,tags_json TEXT NOT NULL DEFAULT '[]'
        );
        CREATE TABLE research_projects(
            id TEXT PRIMARY KEY,title TEXT NOT NULL,summary TEXT NOT NULL DEFAULT '',created_at TEXT NOT NULL,modified_at TEXT NOT NULL
        );
        CREATE TABLE research_questions(
            id TEXT PRIMARY KEY,project_id TEXT NOT NULL REFERENCES research_projects(id) ON DELETE CASCADE,
            question TEXT NOT NULL,notes TEXT NOT NULL DEFAULT '',status TEXT NOT NULL,created_at TEXT NOT NULL,modified_at TEXT NOT NULL
        );
        CREATE TABLE research_arguments(
            id TEXT PRIMARY KEY,question_id TEXT,proposition TEXT NOT NULL,qualification TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL,created_at TEXT NOT NULL,modified_at TEXT NOT NULL
        );
        CREATE TABLE evidence_relationships(
            id TEXT PRIMARY KEY,argument_id TEXT NOT NULL REFERENCES research_arguments(id) ON DELETE CASCADE,
            literature_id TEXT NOT NULL REFERENCES literature_items(id) ON DELETE CASCADE,relation TEXT NOT NULL,
            summary TEXT NOT NULL,page INTEGER,quoted_passage TEXT NOT NULL DEFAULT '',verification TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
        INSERT INTO literature_items VALUES(
            '\(sourceID)','OLDKEY01','Pre-migration source','Author',2024,'Abstract','10.1000/migrate','journalArticle',
            'Zotero','/fixtures/original.pdf',NULL,'2026-10-10T00:00:00Z','2026-10-10T00:00:00Z','Author2024','["migration"]'
        );
        INSERT INTO research_arguments VALUES(
            '\(argumentID)',NULL,'A pre-migration claim','','Developing','2026-10-10T00:00:00Z','2026-10-10T00:00:00Z'
        );
        INSERT INTO evidence_relationships VALUES(
            '\(evidenceID)','\(argumentID)','\(sourceID)','Supports','Retained evidence',7,'Exact quotation','Verified','2026-10-10T00:00:00Z'
        );
        """
    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(rawConnection, schema, nil, nil, &errorMessage) == SQLITE_OK else {
        let message = errorMessage.map { String(cString: $0) } ?? "Unknown SQLite fixture error"
        sqlite3_free(errorMessage)
        sqlite3_close(rawConnection)
        throw CheckFailure(description: message)
    }
    sqlite3_close(rawConnection)
    connection = nil

    let migrated = try AtlasDatabase(url: url)
    let item = try migrated.literatureItems().first
    try expect(item?.id.uuidString == sourceID && item?.title == "Pre-migration source", "Schema migration 5 did not preserve the source record")
    try expect(item?.sourceAvailability == .available && item?.zoteroServerID == nil, "Schema migration 5 assigned invented source identity")
    let evidence = try migrated.evidence(argumentID: UUID(uuidString: argumentID)!).first
    try expect(evidence?.literatureID.uuidString == sourceID && evidence?.quotedPassage == "Exact quotation", "Schema migration 5 broke evidence provenance")
}

func checkValidatedDatabaseRestoreAndRecoveryCopy() throws {
    let source = try DatabaseFixture()
    let destination = try DatabaseFixture()
    defer {
        source.cleanup()
        destination.cleanup()
    }

    let restoredPaper = LiteratureItem(title: "Restorable source", abstract: "Distinct restored content")
    try source.database.upsertLiterature(restoredPaper)
    try source.database.upsertObsidianNote(ObsidianNote(path: "/fixtures/restored.md", title: "Restored note", content: "Recovered interpretation"))
    let project = ResearchProject(title: "Restored project")
    try source.database.saveProject(project)
    let question = ResearchQuestion(projectID: project.id, question: "Was recovery complete?")
    try source.database.saveQuestion(question)
    let argument = ResearchArgument(questionID: question.id, proposition: "Validated backups are recoverable")
    try source.database.saveArgument(argument)
    try source.database.saveEvidence(EvidenceRelationship(
        argumentID: argument.id,
        literatureID: restoredPaper.id,
        relation: .supports,
        summary: "Restore fixture evidence",
        page: 3,
        quotedPassage: "The recovery path retained provenance.",
        verification: .verified
    ))
    let backupURL = source.directory.appendingPathComponent("validated-backup.sqlite3")
    try source.database.backup(to: backupURL)
    try expect(FileManager.default.fileExists(atPath: backupURL.path), "Backup API did not create the restore fixture at \(backupURL.path)")

    let currentPaper = LiteratureItem(title: "Workspace before restore")
    try destination.database.upsertLiterature(currentPaper)
    let preview: DatabaseRestorePreview
    do {
        preview = try destination.database.previewRestore(from: backupURL)
    } catch {
        throw CheckFailure(description: "Initial restore preview failed: \(error)")
    }
    try expect(preview.schemaVersion == AtlasDatabase.currentSchemaVersion, "Restore preview reported the wrong schema")
    try expect(preview.literatureCount == 1 && preview.noteCount == 1 && preview.projectCount == 1, "Restore preview counts are incorrect")
    try expect(preview.questionCount == 1 && preview.argumentCount == 1 && preview.evidenceCount == 1, "Restore preview omitted research records")

    let invalidURL = source.directory.appendingPathComponent("not-a-database.sqlite3")
    try Data("not sqlite".utf8).write(to: invalidURL)
    var invalidWasRejected = false
    do {
        _ = try destination.database.previewRestore(from: invalidURL)
    } catch {
        invalidWasRejected = true
    }
    try expect(invalidWasRejected, "Restore preview accepted a non-SQLite file")

    let recoveryURL: URL
    do {
        recoveryURL = try destination.database.restore(from: backupURL)
    } catch {
        throw CheckFailure(description: "Validated restore failed: \(error)")
    }
    let restoredItems = try destination.database.literatureItems()
    try expect(restoredItems.count == 1 && restoredItems.first?.title == restoredPaper.title, "Restore did not replace the current workspace with the selected backup")
    try expect(try destination.database.search("Distinct restored").contains { $0.entityType == "literature" }, "Restore did not rebuild the derived search index")
    try expect(try destination.database.evidence(argumentID: argument.id).first?.quotedPassage == "The recovery path retained provenance.", "Restore lost evidence provenance")

    let recoveryPreview = try destination.database.previewRestore(from: recoveryURL)
    try expect(recoveryPreview.literatureCount == 1, "The generated recovery copy did not pass restore validation")
    let recovery: AtlasDatabase
    do {
        recovery = try AtlasDatabase(url: recoveryURL)
    } catch {
        throw CheckFailure(description: "Automatic recovery copy could not be opened: \(error)")
    }
    try expect(try recovery.literatureItems().first?.title == currentPaper.title, "The automatic pre-restore recovery copy is not usable")
}

func checkMissingPDFDiagnosisAndRepair() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }
    let originalURL = fixture.directory.appendingPathComponent("original.pdf")
    let replacementURL = fixture.directory.appendingPathComponent("relocated.pdf")
    let differentURL = fixture.directory.appendingPathComponent("different.pdf")
    let sourceBytes = Data("stable fixture PDF content".utf8)
    try sourceBytes.write(to: originalURL)
    try sourceBytes.write(to: replacementURL)
    try Data("different fixture content".utf8).write(to: differentURL)

    let originalFingerprint = try PDFFileInspector.fingerprint(at: originalURL)
    let replacementFingerprint = try PDFFileInspector.fingerprint(at: replacementURL)
    let differentFingerprint = try PDFFileInspector.fingerprint(at: differentURL)
    try expect(originalFingerprint == replacementFingerprint, "Identical relocated files produced different fingerprints")
    try expect(originalFingerprint.sha256 != differentFingerprint.sha256, "Different files produced the same test fingerprint")

    let paper = LiteratureItem(
        zoteroKey: "REPAIR01",
        zoteroAttachmentKey: "ATTACH01",
        zoteroServerID: "repair-server",
        title: "Paper with a relocated PDF",
        source: .zotero,
        pdfPath: originalURL.path,
        pdfByteCount: originalFingerprint.byteCount,
        pdfContentHash: originalFingerprint.sha256,
        pdfLastVerifiedAt: Date()
    )
    try fixture.database.upsertLiterature(paper)
    var changedPaper = paper
    changedPaper.pdfPath = differentURL.path
    try expect(PDFFileInspector.availability(for: changedPaper) == .changed, "A changed PDF was not distinguished from an available matching file")
    try fixture.database.indexPDFPages(literatureID: paper.id, pages: ["antiquatedpassage appears only in the old index"])
    let argument = ResearchArgument(proposition: "The source identity survives relocation")
    try fixture.database.saveArgument(argument)
    try fixture.database.saveEvidence(EvidenceRelationship(
        argumentID: argument.id,
        literatureID: paper.id,
        relation: .supports,
        summary: "Stable paper identity"
    ))

    try FileManager.default.removeItem(at: originalURL)
    try expect(PDFFileInspector.availability(for: originalURL.path) == .missing, "A removed PDF was not diagnosed as missing")
    try fixture.database.relinkPDF(
        literatureID: paper.id,
        url: replacementURL,
        fingerprint: replacementFingerprint,
        pages: ["replacementpassage appears in the rebuilt index"]
    )

    let repaired = try fixture.database.literatureItems().first { $0.id == paper.id }
    try expect(repaired?.pdfPath == replacementURL.path, "PDF repair did not update the application-owned path")
    try expect(repaired?.zoteroAttachmentKey == "ATTACH01", "An exact PDF repair discarded its verified Zotero attachment identity")
    try expect(repaired?.pdfContentHash == originalFingerprint.sha256 && repaired?.pdfLastVerifiedAt != nil, "PDF repair did not preserve the verified fingerprint")
    try expect(PDFFileInspector.availability(for: repaired?.pdfPath) == .available, "The repaired PDF was not reported as available")
    try expect(try fixture.database.search("replacementpassage").contains { $0.entityType == "passage" }, "PDF repair did not rebuild the page index")
    try expect(try fixture.database.search("antiquatedpassage").isEmpty, "PDF repair retained stale page-index content")
    try expect(try fixture.database.evidence(argumentID: argument.id).first?.literatureID == paper.id, "PDF repair changed evidence provenance")

    try fixture.database.relinkPDF(
        literatureID: paper.id,
        url: differentURL,
        fingerprint: differentFingerprint,
        pages: ["different replacement"],
        preserveZoteroAttachmentKey: false
    )
    try expect(try fixture.database.literatureItems().first { $0.id == paper.id }?.zoteroAttachmentKey == nil, "A different replacement retained an unsupported Zotero attachment claim")
}

func checkEvidenceGeometryEditingAndDeletion() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }
    let paper = LiteratureItem(title: "Geometry source")
    try fixture.database.upsertLiterature(paper)
    let argument = ResearchArgument(proposition: "A geometry-backed claim")
    try fixture.database.saveArgument(argument)
    var evidence = EvidenceRelationship(
        argumentID: argument.id,
        literatureID: paper.id,
        relation: .supports,
        summary: "Initial annotation",
        page: 3,
        quotedPassage: "Exact selected wording",
        verification: .verified,
        selectionRegions: [PDFSelectionRegion(
            page: 3, normalizedX: 0.1, normalizedY: 0.2,
            normalizedWidth: 0.4, normalizedHeight: 0.05
        )],
        selectionDocumentHash: "fixture-sha256"
    )
    try fixture.database.saveEvidence(evidence)
    let stored = try fixture.database.evidence(argumentID: argument.id).first
    try expect(stored?.selectionRegions == evidence.selectionRegions, "PDF selection geometry was not preserved")
    try expect(stored?.selectionDocumentHash == "fixture-sha256", "The geometry's document fingerprint was not preserved")

    evidence.summary = "Edited annotation"
    evidence.verification = .unverified
    try fixture.database.saveEvidence(evidence)
    let edited = try fixture.database.evidence(argumentID: argument.id)
    try expect(edited.count == 1 && edited.first?.summary == "Edited annotation", "Editing evidence created a duplicate or lost the update")
    let files = try ResearchExporter.files(for: fixture.database.exportBundle())
    try expect(String(data: files["evidence.csv"] ?? Data(), encoding: .utf8)?.contains("fixture-sha256") == true, "Portable export omitted geometry provenance")

    try fixture.database.deleteEvidence(id: evidence.id)
    try expect(try fixture.database.evidence(argumentID: argument.id).isEmpty, "Deleting an evidence annotation failed")
    try expect(try fixture.database.literatureItems().contains { $0.id == paper.id }, "Deleting evidence removed its source paper")
}

func checkGroundedRetrievalAndCitationFailures() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }
    var paper = LiteratureItem(
        title: "Calibration study", authors: "Researcher", year: 2025,
        pdfContentHash: "document-v1"
    )
    try fixture.database.upsertLiterature(paper)
    try fixture.database.indexPDFPages(literatureID: paper.id, pages: [
        "Confidence calibration improved when advice reliability was visible.",
        "A separate limitation concerned sample size."
    ])

    let set = RetrievalSet(name: "Calibration evidence", query: "confidence calibration", yearFrom: 2020, yearTo: 2030)
    let matches = try fixture.database.createRetrievalSet(set)
    try expect(matches.count == 1, "Grounded retrieval returned the wrong number of passages")
    try expect(matches.first?.literatureID == paper.id && matches.first?.page == 1, "Retrieved evidence lost its source or page")
    try expect(matches.first?.passageText.contains("reliability was visible") == true, "Retrieved evidence did not preserve exact indexed text")
    try expect(try fixture.database.retrievedPassages(retrievalSetID: set.id).first?.citationStatus == .current, "A current citation was reported as stale")

    let emptySet = RetrievalSet(name: "Deliberately absent evidence", query: "termthatdoesnotexist")
    let emptyMatches = try fixture.database.createRetrievalSet(emptySet)
    try expect(emptyMatches.isEmpty, "A failed retrieval fabricated a source passage")
    try expect(try fixture.database.retrievalSets().contains { $0.id == emptySet.id }, "An empty retrieval result was not preserved for inspection")

    try fixture.database.indexPDFPages(literatureID: paper.id, pages: [
        "Confidence calibration changed after the source was re-indexed."
    ])
    let changed = try fixture.database.retrievedPassages(retrievalSetID: set.id).first
    try expect(changed?.citationStatus == .passageChanged, "Changed source text was not detected")

    paper.pdfContentHash = "document-v2"
    try fixture.database.upsertLiterature(paper)
    let changedDocument = try fixture.database.retrievedPassages(retrievalSetID: set.id).first
    try expect(changedDocument?.citationStatus == .documentChanged, "A changed document fingerprint was not detected")

    let pageTwoSet = RetrievalSet(name: "Page two", query: "sample size")
    _ = try fixture.database.indexPDFPages(literatureID: paper.id, pages: ["Current first page", "Sample size remained a limitation."])
    _ = try fixture.database.createRetrievalSet(pageTwoSet)
    try fixture.database.indexPDFPages(literatureID: paper.id, pages: ["Only one page remains indexed."])
    try expect(try fixture.database.retrievedPassages(retrievalSetID: pageTwoSet.id).first?.citationStatus == .sourceMissing, "A removed source page was not reported as missing")

    let files = try ResearchExporter.files(for: fixture.database.exportBundle())
    try expect(files["retrieval-sets.csv"] != nil && files["retrieved-passages.csv"] != nil, "Portable export omitted retrieval provenance")
}

func checkComparisonAndKnowledgeGraphFoundation() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }
    let paper = LiteratureItem(title: "A method comparison source")
    try fixture.database.upsertLiterature(paper)
    let profile = LiteratureComparisonProfile(
        literatureID: paper.id,
        researchQuestion: "When does advice change judgment?",
        studyDesign: "Randomised experiment",
        sample: "Unavailable in the reviewed passage",
        mainFindings: "Advice reliability moderated uptake."
    )
    try fixture.database.saveComparisonProfile(profile)
    let storedProfile = try fixture.database.comparisonProfiles().first
    try expect(storedProfile?.studyDesign == "Randomised experiment" && storedProfile?.limitations.isEmpty == true, "Comparison fields did not preserve recorded and unavailable values")
    try expect(try fixture.database.search("moderated uptake").contains { $0.entityType == "comparison" }, "Comparison profiles were not searchable")

    let argument = ResearchArgument(proposition: "Reliability changes advice uptake")
    try fixture.database.saveArgument(argument)
    let evidence = EvidenceRelationship(
        argumentID: argument.id, literatureID: paper.id, relation: .supports,
        summary: "The reported interaction supports the qualified proposition.", verification: .verified
    )
    try fixture.database.saveEvidence(evidence)
    let concept = ResearchConcept(name: "Advice reliability", definition: "The accuracy or dependability of provided advice.")
    try fixture.database.saveConcept(concept)
    let relationship = KnowledgeRelationship(
        sourceType: .paper, sourceID: paper.id.uuidString,
        targetType: .concept, targetID: concept.id.uuidString,
        relationship: .investigates, evidenceRelationshipID: evidence.id,
        verification: .verified, notes: "Manually linked from verified argument evidence."
    )
    try fixture.database.saveKnowledgeRelationship(relationship)
    let storedRelationship = try fixture.database.knowledgeRelationships().first
    try expect(storedRelationship?.evidenceRelationshipID == evidence.id && storedRelationship?.origin == .user, "Knowledge relationship provenance was not retained")
    try expect(try fixture.database.search("dependability").contains { $0.entityType == "concept" }, "Research concepts were not searchable")

    var rejectedSelfLink = false
    do {
        try fixture.database.saveKnowledgeRelationship(KnowledgeRelationship(
            sourceType: .concept, sourceID: concept.id.uuidString,
            targetType: .concept, targetID: concept.id.uuidString,
            relationship: .relatesTo, notes: "Invalid self-link"
        ))
    } catch {
        rejectedSelfLink = true
    }
    try expect(rejectedSelfLink, "The graph accepted a relationship from a node to itself")

    try fixture.database.deleteConcept(id: concept.id)
    try expect(try fixture.database.knowledgeRelationships().isEmpty, "Deleting a concept left a dangling polymorphic relationship")
}

func checkIndexingJobRecovery() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }
    var completed = IndexingJob(kind: .pdf, sourceName: "complete.pdf", status: .running)
    try fixture.database.saveIndexingJob(completed)
    completed.status = .completed
    completed.completedUnits = 10
    completed.totalUnits = 10
    completed.updatedAt = Date().addingTimeInterval(1)
    try fixture.database.saveIndexingJob(completed)
    let interrupted = IndexingJob(kind: .searchRebuild, sourceName: "local index", status: .running)
    try fixture.database.saveIndexingJob(interrupted)
    try fixture.database.markInterruptedIndexingJobs()
    let jobs = try fixture.database.indexingJobs()
    try expect(jobs.first(where: { $0.id == completed.id })?.status == .completed, "Recovery changed a completed indexing job")
    let recovered = jobs.first { $0.id == interrupted.id }
    try expect(recovered?.status == .failed && recovered?.failureMessage?.contains("closed") == true, "An interrupted indexing job was not reported explicitly")
}

func checkStructuredClaimsAndRevisionProvenance() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }
    let paper = LiteratureItem(title: "Claim source")
    let otherPaper = LiteratureItem(title: "Different source")
    try fixture.database.upsertLiterature(paper)
    try fixture.database.upsertLiterature(otherPaper)
    try fixture.database.indexPDFPages(literatureID: paper.id, pages: ["Observed decisions changed when advice reliability was visible."])
    var claim = ResearchClaim(
        claimText: "Visible reliability changed observed decisions.", category: .empiricalFinding,
        literatureID: paper.id, sourcePassageID: "\(paper.id.uuidString):1", page: 1,
        quotedSourceText: "Observed decisions changed when advice reliability was visible.",
        authorTerminology: "advice reliability", methodologicalContext: "Controlled condition",
        evidenceType: "Observed outcome", relatedConstructs: ["reliability"],
        extractionMethod: .manualSelection, verification: .verified
    )
    try fixture.database.saveClaim(claim)
    claim.claimText = "Visible advice reliability changed decisions in the recorded condition."
    claim.userNotes = "Narrowed to the study condition."
    claim.modifiedAt = Date().addingTimeInterval(1)
    try fixture.database.saveClaim(claim, changeNote: "Added the study boundary")
    try expect(try fixture.database.claims().first?.sourcePassageID == "\(paper.id.uuidString):1", "Claim source passage provenance was not retained")
    let versions = try fixture.database.claimVersions(claimID: claim.id)
    try expect(versions.count == 2 && versions.first?.changeNote == "Added the study boundary", "Claim revisions were not recorded exactly")
    try expect(try fixture.database.search("recorded condition").contains { $0.entityType == "claim" }, "Structured claims were not searchable")

    var rejectedMismatch = false
    do {
        try fixture.database.saveClaim(ResearchClaim(
            claimText: "Mismatched source", category: .empiricalFinding,
            literatureID: otherPaper.id, sourcePassageID: "\(paper.id.uuidString):1", page: 1
        ))
    } catch { rejectedMismatch = true }
    try expect(rejectedMismatch, "A claim accepted a source passage from another paper")

    var rejectedAIWithoutProvenance = false
    do {
        try fixture.database.saveClaim(ResearchClaim(
            claimText: "Unattributed model output", category: .aiSuggestion,
            extractionMethod: .aiCandidate
        ))
    } catch { rejectedAIWithoutProvenance = true }
    try expect(rejectedAIWithoutProvenance, "An AI claim candidate was stored without model and prompt provenance")

    let files = try ResearchExporter.files(for: fixture.database.exportBundle())
    try expect(files["claims.csv"] != nil && files["claim-history.csv"] != nil, "Portable export omitted claims or claim history")
    try fixture.database.deleteClaim(id: claim.id)
    try expect(try fixture.database.literatureItems().count == 2, "Deleting a claim changed its source literature")
}

func checkQuestionIdeaAndHistoryWorkflows() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }
    let project = ResearchProject(title: "Advice project")
    try fixture.database.saveProject(project)
    let paper = LiteratureItem(title: "Question source")
    try fixture.database.upsertLiterature(paper)
    let concept = ResearchConcept(name: "Advice calibration")
    try fixture.database.saveConcept(concept)
    var question = ResearchQuestion(
        projectID: project.id, question: "When does calibrated advice improve decisions?",
        notes: "Initial scope", objectives: "Compare conditions", theoreticalInterests: "Reliance",
        conceptualDefinitions: "Calibration means correspondence between confidence and accuracy.",
        unresolvedDisagreements: "Whether effects generalise", potentialHypotheses: "Visibility moderates uptake",
        methodologicalConsiderations: "Compare outcome measures"
    )
    try fixture.database.saveQuestion(question)
    try fixture.database.saveQuestionLiteratureAssociation(QuestionLiteratureAssociation(questionID: question.id, literatureID: paper.id))
    try fixture.database.saveQuestionConceptAssociation(QuestionConceptAssociation(questionID: question.id, conceptID: concept.id))
    question.status = "Refining"
    question.notes = "Narrowed scope"
    question.modifiedAt = Date().addingTimeInterval(1)
    try fixture.database.saveQuestion(question, changeNote: "Narrowed after comparing measures")
    try expect(try fixture.database.questionVersions(questionID: question.id).count == 2, "Question revisions were not recorded")
    try expect(try fixture.database.questionLiteratureAssociations().first?.literatureID == paper.id, "Question-literature association was not preserved")
    try expect(try fixture.database.questionConceptAssociations().first?.conceptID == concept.id, "Question-concept association was not preserved")

    var idea = ResearchIdea(
        projectID: project.id, questionID: question.id, title: "Reliability visibility as a boundary condition",
        body: "Visibility may change whether advice is scrutinised.", status: .emergingIdea,
        assumptions: "Participants understand the reliability cue", alternativeExplanations: "Task difficulty",
        evidenceNeeded: "A manipulation check", investigationNotes: "Factorial design"
    )
    try fixture.database.saveIdea(idea)
    try fixture.database.saveIdeaLink(ResearchIdeaLink(ideaID: idea.id, targetType: .literature, targetID: paper.id.uuidString, notes: "Initial grounding"))
    idea.status = .candidateHypothesis
    idea.modifiedAt = Date().addingTimeInterval(2)
    try fixture.database.saveIdea(idea, changeNote: "Developed into a testable hypothesis")
    try expect(try fixture.database.ideaVersions(ideaID: idea.id).count == 2, "Idea development history was not recorded")
    try expect(try fixture.database.ideaLinks().first?.targetID == paper.id.uuidString, "Idea source link was not preserved")

    let history = try fixture.database.historyEvents()
    try expect(history.contains { $0.entityType == "question" && $0.eventType == "revised" }, "Question revision was absent from intellectual history")
    try expect(history.contains { $0.entityType == "idea" && $0.eventType == "revised" }, "Idea revision was absent from intellectual history")
    let files = try ResearchExporter.files(for: fixture.database.exportBundle())
    try expect(files["ideas.csv"] != nil && files["question-history.csv"] != nil && files["intellectual-history.csv"] != nil, "Portable export omitted question, idea, or history records")
}

func checkContextualContradictionReview() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }
    let first = LiteratureItem(title: "Accuracy improves")
    let second = LiteratureItem(title: "Dependence increases")
    try fixture.database.upsertLiterature(first)
    try fixture.database.upsertLiterature(second)
    try fixture.database.indexPDFPages(literatureID: first.id, pages: ["Accurate advice improved group accuracy."])
    try fixture.database.indexPDFPages(literatureID: second.id, pages: ["Incorrect advice increased dependence."])
    try fixture.database.saveComparisonProfile(LiteratureComparisonProfile(
        literatureID: first.id, studyDesign: "Accurate-advice condition", sample: "Teams",
        dependentVariables: "Group accuracy", mainFindings: "Accuracy improved"
    ))
    let review = ContradictionCase(
        title: "Improved accuracy versus increased dependence",
        summary: "Determine whether these outcomes genuinely conflict."
    )
    try fixture.database.saveContradictionCase(review)
    try fixture.database.saveContradictionSource(ContradictionSource(
        caseID: review.id, literatureID: first.id, sourcePassageID: "\(first.id.uuidString):1",
        role: "Finding A", finding: "Accuracy improved", contextualDifference: "Advice was accurate", verification: .verified
    ))
    try fixture.database.saveContradictionSource(ContradictionSource(
        caseID: review.id, literatureID: second.id, sourcePassageID: "\(second.id.uuidString):1",
        role: "Finding B", finding: "Dependence increased", contextualDifference: "Advice was incorrect", verification: .verified
    ))
    try expect(try fixture.database.contradictionSources(caseID: review.id).count == 2, "Contradiction comparison sources were not preserved")
    var mismatchedPassageRejected = false
    do {
        try fixture.database.saveContradictionSource(ContradictionSource(
            caseID: review.id, literatureID: second.id, sourcePassageID: "\(first.id.uuidString):1",
            role: "Invalid", finding: "Mismatched"
        ))
    } catch { mismatchedPassageRejected = true }
    try expect(mismatchedPassageRejected, "A contradiction source accepted a passage from another paper")
    let files = try ResearchExporter.files(for: fixture.database.exportBundle())
    try expect(files["contradiction-cases.csv"] != nil && files["contradiction-sources.csv"] != nil, "Portable export omitted contradiction review data")
}

func checkAIProviderConfigurationAndSecretBoundary() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }
    let defaultConfiguration = try fixture.database.aiProviderConfiguration()
    try expect(defaultConfiguration.provider == .disabled && !defaultConfiguration.externalTransmissionEnabled, "AI transmission was not disabled by default")
    try expect(!defaultConfiguration.isReadyForRequests(credentialStored: true), "A disabled provider was reported as ready")

    var rejectedInsecureEndpoint = false
    do {
        try fixture.database.saveAIProviderConfiguration(AIProviderConfiguration(
            provider: .compatibleEndpoint, endpoint: "http://example.test/v1/responses", model: "fixture-model"
        ))
    } catch { rejectedInsecureEndpoint = true }
    try expect(rejectedInsecureEndpoint, "An insecure AI provider endpoint was accepted")

    var rejectedRedirectedDirectCredential = false
    do {
        try fixture.database.saveAIProviderConfiguration(AIProviderConfiguration(
            provider: .anthropic, endpoint: "https://example.test/v1/messages", model: "claude-fixture"
        ))
    } catch { rejectedRedirectedDirectCredential = true }
    try expect(rejectedRedirectedDirectCredential, "A direct-provider credential could be redirected to a non-official host")

    var rejectedRemoteOllama = false
    do {
        try fixture.database.saveAIProviderConfiguration(AIProviderConfiguration(
            provider: .ollamaLocal, endpoint: "http://192.168.1.20:11434/api/chat", model: "fixture-local-model"
        ))
    } catch { rejectedRemoteOllama = true }
    try expect(rejectedRemoteOllama, "Ollama was allowed to leave the fixed loopback endpoint")

    var rejectedRemoteLMStudio = false
    do {
        try fixture.database.saveAIProviderConfiguration(AIProviderConfiguration(
            provider: .lmStudioLocal, endpoint: "http://192.168.1.20:1234/v1/chat/completions", model: "fixture-local-model"
        ))
    } catch { rejectedRemoteLMStudio = true }
    try expect(rejectedRemoteLMStudio, "LM Studio was allowed to leave the fixed loopback endpoint")

    try fixture.database.saveAIProviderConfiguration(AIProviderConfiguration(
        provider: .ollamaLocal, endpoint: AIProviderKind.ollamaLocal.defaultEndpoint,
        model: "fixture-local-model", externalTransmissionEnabled: true,
        maximumOutputTokens: 4096, reasoningEffort: .high, localRuntimeIdleMinutes: 17
    ))
    let localConfiguration = try fixture.database.aiProviderConfiguration()
    try expect(
        localConfiguration.provider == .ollamaLocal && !AIProviderKind.ollamaLocal.requiresCredential &&
        localConfiguration.reasoningEffort == .high && localConfiguration.localRuntimeIdleMinutes == 17 &&
        AIProviderKind.ollamaLocal.defaultModel == "gpt-oss:20b",
        "The credential-free local Ollama configuration did not round trip"
    )
    try expect(localConfiguration.isReadyForRequests(credentialStored: false), "A credential-free local provider was incorrectly reported as not ready")

    try fixture.database.saveAIProviderConfiguration(AIProviderConfiguration(
        provider: .lmStudioLocal, endpoint: AIProviderKind.lmStudioLocal.defaultEndpoint,
        model: "qwen3.6-27b", externalTransmissionEnabled: true
    ))
    let lmStudioConfiguration = try fixture.database.aiProviderConfiguration()
    try expect(
        lmStudioConfiguration.provider == .lmStudioLocal && !AIProviderKind.lmStudioLocal.requiresCredential,
        "The credential-free local LM Studio configuration did not round trip"
    )

    let configured = AIProviderConfiguration(
        provider: .openAI, endpoint: "https://api.openai.com/v1/responses", model: "fixture-model",
        externalTransmissionEnabled: true, maximumPassages: 7, maximumOutputTokens: 896
    )
    try fixture.database.saveAIProviderConfiguration(configured)
    let stored = try fixture.database.aiProviderConfiguration()
    try expect(stored.provider == .openAI && stored.maximumPassages == 7 && stored.externalTransmissionEnabled, "AI provider configuration did not round trip")
    try expect(!stored.isReadyForRequests(credentialStored: false), "A hosted provider without a stored credential was reported as ready")
    try expect(stored.isReadyForRequests(credentialStored: true), "A configured hosted provider with a stored credential was not reported as ready")
    var sameSettingsWithNewAuditTime = stored
    sameSettingsWithNewAuditTime.modifiedAt = stored.modifiedAt.addingTimeInterval(60)
    try expect(
        sameSettingsWithNewAuditTime.hasSameOperationalSettings(as: stored),
        "A persistence timestamp incorrectly made saved AI settings appear unsaved"
    )
    sameSettingsWithNewAuditTime.maximumOutputTokens += 128
    try expect(
        !sameSettingsWithNewAuditTime.hasSameOperationalSettings(as: stored),
        "A provider execution-setting change was not detected"
    )

    let exactSource = AITransmissionSourcePreview(
        label: "S1", sourceClass: "Published-source passage", title: "Fixture paper",
        location: "Page 7", excerpt: "The exact text approved for this fixture request."
    )
    let preview = AITransmissionPreview(
        analysisKind: .literatureAnswer, provider: .openAI,
        endpoint: AIProviderKind.openAI.defaultEndpoint, model: "fixture-model",
        reasoningEffort: nil, maximumOutputTokens: 896, query: "Fixture question",
        retrievalSetID: UUID(), sourceLabels: [exactSource.summaryLabel],
        sourcePreviews: [exactSource], passageCount: 1, characterCount: exactSource.excerpt.count
    )
    try expect(
        preview.sourcePreviews.first?.excerpt == exactSource.excerpt &&
        preview.sourceLabels.first?.contains("Fixture paper") == true &&
        preview.sourceLabels.first?.contains("page 7") == true,
        "The transmission preview did not preserve the exact source text and readable provenance"
    )

    let exported = try JSONEncoder().encode(fixture.database.exportBundle())
    let exportText = String(data: exported, encoding: .utf8) ?? ""
    try expect(!exportText.contains("fixture-secret-that-must-not-export"), "A credential appeared in the portable model")
    let files = try ResearchExporter.files(for: fixture.database.exportBundle())
    let providerCSV = String(data: files["ai-provider-configuration.csv"] ?? Data(), encoding: .utf8) ?? ""
    try expect(providerCSV.contains("credential_exported") && providerCSV.contains("false"), "Provider export did not state the credential boundary")
}

func checkDirectAIProviderHTTPContracts() throws {
    let schema: [String: JSONValue] = [
        "type": .string("object"),
        "properties": .object(["answer": .object(["type": .string("string")])]),
        "required": .array([.string("answer")]),
        "additionalProperties": .bool(false)
    ]
    let baseRequest = AIProviderRequest(
        model: "fixture-model", instructions: "Use only supplied evidence.", input: "[S1] Fixture passage",
        responseSchemaName: "fixture_answer", responseSchema: schema, maximumOutputTokens: 640
    )

    var claudeInput = baseRequest
    claudeInput.model = "claude-sonnet-5-5"
    let claude = try AIProviderHTTPCodec.makeRequest(
        provider: .anthropic, endpoint: URL(string: AIProviderKind.anthropic.defaultEndpoint)!,
        apiKey: "anthropic-fixture-secret", request: claudeInput
    )
    try expect(claude.url?.absoluteString == AIProviderKind.anthropic.defaultEndpoint, "Claude did not use the official Messages endpoint")
    try expect(claude.value(forHTTPHeaderField: "x-api-key") == "anthropic-fixture-secret", "Claude authentication header was missing")
    try expect(claude.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01", "Claude API version header was missing")
    let claudeBody = try JSONSerialization.jsonObject(with: claude.httpBody ?? Data()) as? [String: Any]
    let claudeOutput = claudeBody?["output_config"] as? [String: Any]
    try expect(claudeOutput?["format"] != nil && claudeBody?["messages"] != nil, "Claude structured-output request was malformed")
    let claudeResponse = try AIProviderHTTPCodec.decodeResponse(provider: .anthropic, data: Data(#"""
        {
        "id":"msg_fixture","content":[{"type":"text","text":"{\"answer\":\"Grounded\"}"}],
        "stop_reason":"end_turn","usage":{"input_tokens":21,"output_tokens":8}
        }
        """#.utf8))
    try expect(claudeResponse.providerResponseID == "msg_fixture" && claudeResponse.inputTokens == 21 && claudeResponse.outputTokens == 8, "Claude response provenance was not decoded")

    var geminiInput = baseRequest
    geminiInput.model = "gemini-3.8-flash"
    let gemini = try AIProviderHTTPCodec.makeRequest(
        provider: .googleGemini, endpoint: URL(string: AIProviderKind.googleGemini.defaultEndpoint)!,
        apiKey: "gemini-fixture-secret", request: geminiInput
    )
    try expect(gemini.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent", "Gemini generateContent endpoint was malformed")
    try expect(gemini.value(forHTTPHeaderField: "x-goog-api-key") == "gemini-fixture-secret", "Gemini authentication header was missing")
    try expect(!(gemini.url?.absoluteString.contains("gemini-fixture-secret") ?? true), "Gemini credential leaked into the request URL")
    let geminiBody = try JSONSerialization.jsonObject(with: gemini.httpBody ?? Data()) as? [String: Any]
    let generation = geminiBody?["generationConfig"] as? [String: Any]
    try expect(generation?["responseMimeType"] as? String == "application/json" && generation?["responseJsonSchema"] != nil, "Gemini structured-output request was malformed")
    let geminiResponse = try AIProviderHTTPCodec.decodeResponse(provider: .googleGemini, data: Data(#"""
        {
        "responseId":"gemini_fixture","candidates":[{"finishReason":"STOP","content":{"parts":[{"text":"{\"answer\":\"Grounded\"}"}]}}],
        "usageMetadata":{"promptTokenCount":18,"candidatesTokenCount":7}
        }
        """#.utf8))
    try expect(geminiResponse.providerResponseID == "gemini_fixture" && geminiResponse.inputTokens == 18 && geminiResponse.outputTokens == 7, "Gemini response provenance was not decoded")

    var openAIInput = baseRequest
    openAIInput.model = "gpt-fixture"
    let openAI = try AIProviderHTTPCodec.makeRequest(
        provider: .openAI, endpoint: URL(string: AIProviderKind.openAI.defaultEndpoint)!,
        apiKey: "openai-fixture-secret", request: openAIInput
    )
    try expect(openAI.value(forHTTPHeaderField: "Authorization") == "Bearer openai-fixture-secret", "OpenAI authentication header was missing")

    var ollamaInput = baseRequest
    ollamaInput.model = "fixture-local-model"
    let ollama = try AIProviderHTTPCodec.makeRequest(
        provider: .ollamaLocal, endpoint: URL(string: AIProviderKind.ollamaLocal.defaultEndpoint)!,
        apiKey: "", request: ollamaInput, reasoningEffort: .high, localRuntimeIdleMinutes: 17
    )
    try expect(ollama.url?.absoluteString == AIProviderKind.ollamaLocal.defaultEndpoint, "Ollama did not use the fixed loopback chat endpoint")
    try expect(ollama.value(forHTTPHeaderField: "Authorization") == nil, "Ollama unexpectedly attached a credential")
    let ollamaBody = try JSONSerialization.jsonObject(with: ollama.httpBody ?? Data()) as? [String: Any]
    try expect(
        ollamaBody?["stream"] as? Bool == false && ollamaBody?["format"] != nil &&
        ollamaBody?["think"] as? String == "high" && ollamaBody?["keep_alive"] as? String == "17m",
        "Ollama structured-output or managed-runtime settings were malformed"
    )
    let ollamaResponse = try AIProviderHTTPCodec.decodeResponse(provider: .ollamaLocal, data: Data(#"""
        {
        "model":"fixture-local-model","created_at":"2026-10-20T18:00:00Z",
        "message":{"role":"assistant","content":"{\"answer\":\"Grounded\"}"},
        "done":true,"done_reason":"stop","prompt_eval_count":15,"eval_count":6
        }
        """#.utf8))
    try expect(ollamaResponse.inputTokens == 15 && ollamaResponse.outputTokens == 6, "Ollama response provenance was not decoded")

    var lmStudioInput = baseRequest
    lmStudioInput.model = "qwen3.6-27b"
    let lmStudio = try AIProviderHTTPCodec.makeRequest(
        provider: .lmStudioLocal, endpoint: URL(string: AIProviderKind.lmStudioLocal.defaultEndpoint)!,
        apiKey: "", request: lmStudioInput
    )
    try expect(lmStudio.url?.absoluteString == AIProviderKind.lmStudioLocal.defaultEndpoint, "LM Studio did not use the fixed loopback chat endpoint")
    try expect(lmStudio.value(forHTTPHeaderField: "Authorization") == nil, "LM Studio unexpectedly attached a credential")
    let lmStudioBody = try JSONSerialization.jsonObject(with: lmStudio.httpBody ?? Data()) as? [String: Any]
    let lmStudioFormat = lmStudioBody?["response_format"] as? [String: Any]
    try expect(lmStudioBody?["stream"] as? Bool == false && lmStudioFormat?["type"] as? String == "json_schema", "LM Studio structured-output request was malformed")
    let lmStudioResponse = try AIProviderHTTPCodec.decodeResponse(provider: .lmStudioLocal, data: Data(#"""
        {
        "id":"chatcmpl_fixture","model":"qwen3.6-27b",
        "choices":[{"message":{"role":"assistant","content":"","reasoning_content":"{\"answer\":\"Grounded\"}"},"finish_reason":"stop"}],
        "usage":{"prompt_tokens":17,"completion_tokens":9}
        }
        """#.utf8))
    try expect(
        lmStudioResponse.outputText == "{\"answer\":\"Grounded\"}" && lmStudioResponse.inputTokens == 17 && lmStudioResponse.outputTokens == 9,
        "LM Studio Qwen reasoning-content response provenance was not decoded"
    )
    var rejectedFreeFormReasoning = false
    do {
        _ = try AIProviderHTTPCodec.decodeResponse(provider: .lmStudioLocal, data: Data(#"""
            {"choices":[{"message":{"role":"assistant","content":"","reasoning_content":"private scratch text"},"finish_reason":"stop"}]}
            """#.utf8))
    } catch { rejectedFreeFormReasoning = true }
    try expect(rejectedFreeFormReasoning, "LM Studio free-form reasoning was accepted as an application result")

    try expect(
        AIProviderKind.compatibleEndpoint.endpointIsEditable &&
        !AIProviderKind.anthropic.endpointIsEditable && !AIProviderKind.ollamaLocal.endpointIsEditable &&
        !AIProviderKind.lmStudioLocal.endpointIsEditable,
        "Provider endpoint-editing boundary was incorrect"
    )
}

func checkGroundedAnswerContractAndCitationRejection() throws {
    let paper = LiteratureItem(title: "Grounding fixture", pdfContentHash: "fixture-document")
    let current = RetrievedPassage(
        retrievalSetID: UUID(), sourcePassageID: "\(paper.id.uuidString):1", literatureID: paper.id,
        page: 1, passageText: "Visible reliability improved calibration in this condition.",
        extractionMethod: "PDF full-text index", sourceIndexedAt: Date(), sourceDocumentHash: "fixture-document",
        rank: 1, citationStatus: .current
    )
    let stale = RetrievedPassage(
        retrievalSetID: current.retrievalSetID, sourcePassageID: "\(paper.id.uuidString):2", literatureID: paper.id,
        page: 2, passageText: "This stale passage must not be transmitted.", extractionMethod: "PDF full-text index",
        sourceIndexedAt: Date(), sourceDocumentHash: "old-document", rank: 2, citationStatus: .documentChanged
    )
    let package = try GroundedAnswerBuilder.package(
        analysisID: UUID(), query: "What changed?", passages: [current, stale], literature: [paper],
        model: "fixture-model", maximumOutputTokens: 512
    )
    try expect(package.citations.count == 1 && package.citations.first?.label == "S1", "A stale passage entered the grounded request")
    try expect(package.request.input.contains(current.passageText) && !package.request.input.contains(stale.passageText), "The transmitted source package was not restricted to current evidence")

    let validJSON = """
        {"answer":"Visible reliability improved calibration in the supplied condition.","insufficient_evidence":false,"insufficiency_reason":"","claims":[{"text":"Calibration improved in the supplied condition.","citations":["S1"],"interpretation":false}]}
        """
    let valid = try GroundedAnswerBuilder.decodeAndValidate(validJSON, allowedCitationLabels: ["S1"])
    try expect(valid.claims.count == 1 && !valid.insufficientEvidence, "A valid grounded response was rejected")

    var rejectedUnknownCitation = false
    do {
        _ = try GroundedAnswerBuilder.decodeAndValidate(validJSON.replacingOccurrences(of: "S1", with: "S99"), allowedCitationLabels: ["S1"])
    } catch { rejectedUnknownCitation = true }
    try expect(rejectedUnknownCitation, "A model response cited a nonexistent source label")

    let uncitedJSON = """
        {"answer":"Unsupported answer.","insufficient_evidence":false,"insufficiency_reason":"","claims":[{"text":"Unsupported claim.","citations":[],"interpretation":true}]}
        """
    var rejectedUncitedClaim = false
    do { _ = try GroundedAnswerBuilder.decodeAndValidate(uncitedJSON, allowedCitationLabels: ["S1"]) }
    catch { rejectedUncitedClaim = true }
    try expect(rejectedUncitedClaim, "An uncited substantive claim was accepted")

    let insufficientJSON = """
        {"answer":"","insufficient_evidence":true,"insufficiency_reason":"The supplied passage does not report the requested outcome.","claims":[]}
        """
    let insufficient = try GroundedAnswerBuilder.decodeAndValidate(insufficientJSON, allowedCitationLabels: ["S1"])
    try expect(insufficient.insufficientEvidence && insufficient.claims.isEmpty, "A valid insufficient-evidence refusal was rejected")

    var rejectedEmptyEvidence = false
    do {
        _ = try GroundedAnswerBuilder.package(
            analysisID: UUID(), query: "Unsupported question", passages: [stale], literature: [paper],
            model: "fixture-model", maximumOutputTokens: 512
        )
    } catch { rejectedEmptyEvidence = true }
    try expect(rejectedEmptyEvidence, "A request without current evidence was prepared for transmission")
}

func checkAIAnalysisProvenanceReviewAndStaleness() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }
    let paper = LiteratureItem(title: "AI provenance source", pdfContentHash: "document-v1")
    try fixture.database.upsertLiterature(paper)
    try fixture.database.indexPDFPages(literatureID: paper.id, pages: ["The registered passage supports a bounded result."])
    let set = RetrievalSet(name: "AI evidence", query: "bounded result")
    let passages = try fixture.database.createRetrievalSet(set)
    try expect(passages.count == 1, "The AI provenance fixture did not retrieve its source passage")
    let analysis = AIAnalysis(
        kind: .literatureAnswer, provider: "Fixture provider", model: "fixture-model",
        promptVersion: GroundedAnswerBuilder.promptVersion, retrievalSetID: set.id,
        userQuery: "What is supported?", responseText: "A bounded result is supported.",
        structuredResponseJSON: "{\"answer\":\"A bounded result is supported.\",\"insufficient_evidence\":false,\"insufficiency_reason\":\"\",\"claims\":[{\"text\":\"A bounded result is supported.\",\"citations\":[\"S1\"],\"interpretation\":false}]}",
        status: .completed, transmittedPassageCount: 1, transmittedCharacterCount: 100,
        inputTokens: 40, outputTokens: 20, completedAt: Date()
    )
    let citation = AIAnalysisCitation(
        analysisID: analysis.id, label: "S1", sourcePassageID: passages[0].sourcePassageID,
        literatureID: paper.id, page: 1, quotedPassage: passages[0].passageText,
        sourceDocumentHash: passages[0].sourceDocumentHash
    )
    try fixture.database.saveAIAnalysis(analysis, citations: [citation])
    var transmittedAnalysis = analysis
    transmittedAnalysis.transmittedPassageCount = 12
    transmittedAnalysis.transmittedCharacterCount = 4_321
    try fixture.database.saveAIAnalysis(transmittedAnalysis, citations: [citation])
    let updatedAnalysis = try fixture.database.aiAnalyses().first { $0.id == analysis.id }
    try expect(
        updatedAnalysis?.transmittedPassageCount == 12 && updatedAnalysis?.transmittedCharacterCount == 4_321,
        "An AI analysis update lost the post-send transmission counts"
    )
    try fixture.database.saveAnalysisReview(AnalysisReview(
        analysisID: analysis.id, decision: .accepted, notes: "Useful after checking the exact passage."
    ))
    try expect(try fixture.database.aiAnalyses().first?.model == "fixture-model", "AI model provenance was not stored")
    try expect(try fixture.database.analysisReviews().first?.decision == .accepted, "Human AI-analysis review was not stored")
    try expect(try fixture.database.aiAnalysisCitations(analysisID: analysis.id).first?.citationStatus == .current, "A current AI citation was reported as stale")

    try fixture.database.indexPDFPages(literatureID: paper.id, pages: ["The source passage changed after the analysis."])
    try expect(try fixture.database.aiAnalysisCitations(analysisID: analysis.id).first?.citationStatus == .passageChanged, "A changed AI source snapshot was not detected")
    let files = try ResearchExporter.files(for: fixture.database.exportBundle())
    try expect(files["ai-analyses.csv"] != nil && files["ai-analysis-citations.csv"] != nil && files["ai-analysis-reviews.csv"] != nil, "Portable export omitted AI provenance records")
    let markdown = String(data: files["research-atlas.md"] ?? Data(), encoding: .utf8) ?? ""
    try expect(markdown.contains("model-generated suggestions") && markdown.contains("Human review"), "Human/model authorship was unclear in Markdown export")
}

func checkBiasAuditQuestionsAndReviewDecisions() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }
    let paper = LiteratureItem(title: "Single supporting source")
    try fixture.database.upsertLiterature(paper)
    let argument = ResearchArgument(proposition: "AI advice causes groups to converge")
    let otherArgument = ResearchArgument(proposition: "A separate argument")
    try fixture.database.saveArgument(argument)
    try fixture.database.saveArgument(otherArgument)
    let evidence = EvidenceRelationship(
        argumentID: argument.id, literatureID: paper.id, relation: .supports,
        summary: "A supporting record that still requires qualification.", verification: .verified
    )
    let otherEvidence = EvidenceRelationship(
        argumentID: otherArgument.id, literatureID: paper.id, relation: .supports,
        summary: "Evidence from another argument.", verification: .verified
    )
    try fixture.database.saveEvidence(evidence)
    try fixture.database.saveEvidence(otherEvidence)
    let draft = LocalBiasAuditor.makeDraft(
        argument: argument, evidence: [evidence], literature: [paper], comparisonProfiles: []
    )
    try expect(draft.audit.origin == .localSuggestion, "The deterministic bias audit was mislabeled as user or AI authored")
    try expect(draft.concerns.contains { $0.kind == .selectiveEvidence }, "The audit did not flag the absence of recorded counterevidence")
    try expect(draft.concerns.contains { $0.kind == .overgeneralisation }, "The audit did not flag a missing qualification")
    try expect(draft.concerns.allSatisfy { !$0.uncertainty.isEmpty }, "A bias-audit concern omitted its uncertainty statement")
    try fixture.database.saveBiasAudit(draft.audit)
    for concern in draft.concerns { try fixture.database.saveBiasConcern(concern) }
    guard var stored = try fixture.database.biasConcerns(auditID: draft.audit.id).first else {
        throw CheckFailure(description: "Bias-audit concerns were not persisted")
    }
    stored.disposition = .dismissed
    stored.reviewNotes = "The proposition is intentionally limited; boundary text will be added."
    stored.modifiedAt = Date().addingTimeInterval(1)
    try fixture.database.saveBiasConcern(stored)
    try expect(try fixture.database.biasConcerns(auditID: draft.audit.id).first?.disposition == .dismissed, "The user's bias-audit decision was not preserved")

    var rejectedCrossArgumentEvidence = false
    do {
        try fixture.database.saveBiasConcern(BiasConcern(
            auditID: draft.audit.id, kind: .evidenceScope, potentialProblem: "Invalid cross-argument source",
            evidenceRelationshipIDs: [otherEvidence.id]
        ))
    } catch { rejectedCrossArgumentEvidence = true }
    try expect(rejectedCrossArgumentEvidence, "A bias concern accepted evidence from another argument")
    let files = try ResearchExporter.files(for: fixture.database.exportBundle())
    try expect(files["bias-audits.csv"] != nil && files["bias-concerns.csv"] != nil, "Portable export omitted bias-audit records")
}

func checkDeliberationRecordAndCitationIntegrity() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }
    let paper = LiteratureItem(title: "Deliberation source", pdfContentHash: "deliberation-v1")
    try fixture.database.upsertLiterature(paper)
    try fixture.database.indexPDFPages(literatureID: paper.id, pages: ["The exact deliberation evidence passage."])
    let argument = ResearchArgument(proposition: "A proposition for structured criticism")
    try fixture.database.saveArgument(argument)
    let evidence = EvidenceRelationship(
        argumentID: argument.id, literatureID: paper.id, relation: .qualifies,
        summary: "A qualification", page: 1, quotedPassage: "The exact deliberation evidence passage.", verification: .verified
    )
    try fixture.database.saveEvidence(evidence)
    let scaffold = LocalDeliberationScaffoldBuilder.make(argument: argument, evidence: [evidence])
    try expect(scaffold.session.model == "No model invoked" && scaffold.messages.allSatisfy { !$0.modelGenerated }, "Local prompts were mislabeled as model-generated perspectives")
    try expect(scaffold.session.disclosure.contains("not independent experts"), "The deliberation disclosure omitted the independence limitation")
    try fixture.database.saveDeliberationSession(scaffold.session)
    for message in scaffold.messages { try fixture.database.saveDeliberationMessage(message) }
    let message = DeliberationMessage(
        sessionID: scaffold.session.id, perspective: .evidence, phase: .revision,
        content: "The supplied passage supports only a qualification [S1].", sequence: 6, modelGenerated: true
    )
    let citation = DeliberationCitation(
        messageID: message.id, label: "S1", literatureID: paper.id,
        sourcePassageID: "\(paper.id.uuidString):1", page: 1,
        quotedPassage: "The exact deliberation evidence passage.", sourceDocumentHash: "deliberation-v1"
    )
    try fixture.database.saveDeliberationMessage(message, citations: [citation])
    try expect(try fixture.database.deliberationMessages(sessionID: scaffold.session.id).count == 6, "Deliberation message order was not preserved")
    try expect(try fixture.database.deliberationCitations(messageID: message.id).first?.citationStatus == .current, "A current deliberation citation was reported as stale")

    var rejectedChangedQuote = false
    do {
        let invalidMessage = DeliberationMessage(
            sessionID: scaffold.session.id, perspective: .theoretical, phase: .revision,
            content: "Invalid source use.", sequence: 7, modelGenerated: true
        )
        try fixture.database.saveDeliberationMessage(invalidMessage, citations: [DeliberationCitation(
            messageID: invalidMessage.id, label: "S1", literatureID: paper.id,
            sourcePassageID: "\(paper.id.uuidString):1", page: 1, quotedPassage: "Invented wording"
        )])
    } catch { rejectedChangedQuote = true }
    try expect(rejectedChangedQuote, "A deliberation message accepted an invented quotation")
    try fixture.database.indexPDFPages(literatureID: paper.id, pages: ["The passage changed after deliberation."])
    try expect(try fixture.database.deliberationCitations(messageID: message.id).first?.citationStatus == .passageChanged, "A changed deliberation source was not detected")
    let files = try ResearchExporter.files(for: fixture.database.exportBundle())
    try expect(files["deliberation-sessions.csv"] != nil && files["deliberation-messages.csv"] != nil && files["deliberation-citations.csv"] != nil, "Portable export omitted deliberation provenance")
}

func checkWritingEvidenceAndCitationReviewWorkflow() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }
    let project = ResearchProject(title: "Writing project")
    try fixture.database.saveProject(project)
    let question = ResearchQuestion(projectID: project.id, question: "What does the evidence support?")
    try fixture.database.saveQuestion(question)
    let paper = LiteratureItem(title: "Writing source", citationKey: "Writer2026")
    try fixture.database.upsertLiterature(paper)
    try fixture.database.indexPDFPages(literatureID: paper.id, pages: ["The bounded finding applies to the recorded population."])
    let claim = ResearchClaim(
        claimText: "The bounded finding applies to the recorded population.", category: .empiricalFinding,
        literatureID: paper.id, sourcePassageID: "\(paper.id.uuidString):1", page: 1,
        quotedSourceText: "The bounded finding applies to the recorded population.",
        extractionMethod: .manualSelection, verification: .verified
    )
    try fixture.database.saveClaim(claim)
    let document = WritingDocument(
        projectID: project.id, questionID: question.id, title: "Evidence-led literature review",
        purpose: .literatureReview
    )
    try fixture.database.saveWritingDocument(document)
    let section = WritingSection(
        documentID: document.id, title: "Bounded result", body: "The bounded finding applies to the recorded population.", position: 1
    )
    try fixture.database.saveWritingSection(section)
    let link = WritingEvidenceLink(
        sectionID: section.id, targetType: .claim, targetID: claim.id.uuidString,
        citationKey: paper.citationKey, rationale: "Exact verified claim and passage."
    )
    try fixture.database.saveWritingEvidenceLink(link)
    let localReviews = LocalCitationSupportAuditor.makeReviews(section: section, links: [link])
    try expect(localReviews.count == 1 && localReviews.first?.assessment == .requiresHumanReview, "The local citation auditor overstated citation correctness")
    for review in localReviews { try fixture.database.saveCitationSupportReview(review) }
    let causalSection = WritingSection(
        documentID: document.id, title: "Causal overstatement",
        body: "The intervention causes the bounded outcome across every population.", position: 2
    )
    let cautiousSource = CitationSupportSourceSnapshot(
        evidenceLinkID: link.id,
        text: "The intervention was associated with the outcome only in the recorded population.",
        verification: .verified
    )
    let scopeReviews = LocalCitationSupportAuditor.makeReviews(section: causalSection, links: [link], sources: [cautiousSource])
    try expect(
        scopeReviews.first?.assessment == .partiallySupported &&
        scopeReviews.first?.evidenceLinkID == link.id &&
        scopeReviews.first?.concern.contains("causal language") == true &&
        scopeReviews.first?.concern.contains("qualifying language") == true,
        "The local citation auditor did not surface causal or qualification mismatch risks"
    )
    try expect(try fixture.database.search("bounded result").contains { $0.entityType == "writing-section" }, "Writing sections were not searchable")

    var rejectedAIReviewWithoutProvenance = false
    do {
        try fixture.database.saveCitationSupportReview(CitationSupportReview(
            sectionID: section.id, statement: "Model review without provenance",
            assessment: .appearsSupported, origin: .aiSuggested
        ))
    } catch { rejectedAIReviewWithoutProvenance = true }
    try expect(rejectedAIReviewWithoutProvenance, "An AI citation-support review was stored without model and prompt provenance")

    let files = try ResearchExporter.files(for: fixture.database.exportBundle())
    try expect(files["writing-documents.csv"] != nil && files["writing-sections.csv"] != nil && files["writing-evidence-links.csv"] != nil && files["citation-support-reviews.csv"] != nil, "Portable export omitted writing or citation-review records")
    try fixture.database.deleteWritingDocument(id: document.id)
    try expect(try fixture.database.writingSections().isEmpty && fixture.database.writingEvidenceLinks().isEmpty, "Deleting a writing workspace left dependent records")
    try expect(try fixture.database.claims().count == 1, "Deleting a writing workspace removed source claims")
}

func checkCollectiveExperimentReproducibilityAndSafety() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }

    var experiment = CollectiveExperiment(
        title: "Structured disagreement pilot",
        researchPurpose: "Compare independent and revised confidence judgments.",
        taskInstructions: "Assess the bounded claim, exchange objections, then revise confidence.",
        interactionMode: .structuredDisagreement
    )
    try fixture.database.saveCollectiveExperiment(experiment)
    try expect(
        try fixture.database.collectiveExperiments().first?.validationNote.contains("not validated") == true,
        "The collective-lab validation limitation was not preserved"
    )

    var invalidSettings = CollectiveExperiment(title: "Invalid settings", taskInstructions: "Test validation.")
    invalidSettings.modelSettingsJSON = "[1, 2, 3]"
    var rejectedInvalidSettings = false
    do { try fixture.database.saveCollectiveExperiment(invalidSettings) } catch { rejectedInvalidSettings = true }
    try expect(rejectedInvalidSettings, "Collective-lab model settings accepted a non-object JSON value")

    let firstAgent = CollectiveAgent(
        experimentID: experiment.id, label: "Agent A", role: "Empirical advocate",
        informationAvailable: "Passage S1 only", position: 1
    )
    let secondAgent = CollectiveAgent(
        experimentID: experiment.id, label: "Agent B", role: "Methodological critic",
        informationAvailable: "Task instructions only", position: 2
    )
    try fixture.database.saveCollectiveAgent(firstAgent)
    try fixture.database.saveCollectiveAgent(secondAgent)
    try expect(try fixture.database.collectiveAgents(experimentID: experiment.id).count == 2, "Collective-lab roles were not preserved")

    var rejectedUnconfiguredModelTurn = false
    do {
        try fixture.database.saveCollectiveTurn(CollectiveTurn(
            experimentID: experiment.id, agentID: firstAgent.id, round: 1, sequence: 1,
            kind: .initialJudgment, promptText: "Assess the claim.", responseText: "Initial answer.",
            confidence: 0.6, modelGenerated: true
        ))
    } catch { rejectedUnconfiguredModelTurn = true }
    try expect(rejectedUnconfiguredModelTurn, "A turn was labelled model-generated without provider and model provenance")

    experiment.provider = "OpenAI"
    experiment.model = "gpt-test"
    experiment.modelSettingsJSON = #"{"temperature":0,"seed":42}"#
    experiment.promptVersion = "collective-lab-pilot-v2"
    experiment.status = .running
    try fixture.database.saveCollectiveExperiment(experiment)

    let source = LiteratureItem(title: "Collective judgment source")
    try fixture.database.upsertLiterature(source)
    try fixture.database.indexPDFPages(literatureID: source.id, pages: ["Structured disagreement improved calibration in the bounded task."])
    let turn = CollectiveTurn(
        experimentID: experiment.id, agentID: firstAgent.id, round: 1, sequence: 1,
        kind: .initialJudgment, informationAvailable: "Passage S1 only",
        promptText: "Assess the result using only S1.", responseText: "The result is bounded to the recorded task [S1].",
        confidence: 0.75, modelGenerated: true
    )
    let citation = CollectiveTurnCitation(
        turnID: turn.id, label: "S1", literatureID: source.id,
        sourcePassageID: "\(source.id.uuidString):1", page: 1,
        quotedPassage: "Structured disagreement improved calibration in the bounded task."
    )
    try fixture.database.saveCollectiveTurn(turn, citations: [citation])
    let storedTurn = try fixture.database.collectiveTurns(experimentID: experiment.id).first
    try expect(storedTurn?.confidence == 0.75 && storedTurn?.modelGenerated == true, "Collective-lab confidence or authorship provenance was not preserved")
    try expect(try fixture.database.collectiveTurnCitations(turnID: turn.id).first?.citationStatus == .current, "A current collective-lab citation was reported as stale")

    let otherExperiment = CollectiveExperiment(title: "Other experiment", taskInstructions: "Keep roles isolated.")
    try fixture.database.saveCollectiveExperiment(otherExperiment)
    let foreignAgent = CollectiveAgent(experimentID: otherExperiment.id, label: "Foreign role", position: 1)
    try fixture.database.saveCollectiveAgent(foreignAgent)
    var rejectedForeignAgent = false
    do {
        try fixture.database.saveCollectiveTurn(CollectiveTurn(
            experimentID: experiment.id, agentID: foreignAgent.id, round: 1, sequence: 2,
            kind: .deliberation, responseText: "Wrong experiment."
        ))
    } catch { rejectedForeignAgent = true }
    try expect(rejectedForeignAgent, "A collective-lab turn accepted a role from another experiment")

    var rejectedInventedCitation = false
    do {
        let inventedTurn = CollectiveTurn(
            experimentID: experiment.id, agentID: secondAgent.id, round: 1, sequence: 2,
            kind: .deliberation, responseText: "Invented citation."
        )
        try fixture.database.saveCollectiveTurn(inventedTurn, citations: [CollectiveTurnCitation(
            turnID: inventedTurn.id, label: "S1", literatureID: source.id,
            sourcePassageID: "\(source.id.uuidString):1", page: 1, quotedPassage: "Invented wording"
        )])
    } catch { rejectedInventedCitation = true }
    try expect(rejectedInventedCitation, "A collective-lab turn accepted an invented quotation")

    let observation = CollectiveTurn(
        experimentID: experiment.id, round: 2, sequence: 2, kind: .researcherObservation,
        responseText: "The second role did not receive passage S1.", modelGenerated: false
    )
    try fixture.database.saveCollectiveTurn(observation)
    try fixture.database.indexPDFPages(literatureID: source.id, pages: ["The indexed passage changed after the experiment."])
    try expect(try fixture.database.collectiveTurnCitations(turnID: turn.id).first?.citationStatus == .passageChanged, "A changed collective-lab source passage was not detected")

    let files = try ResearchExporter.files(for: fixture.database.exportBundle())
    try expect(
        files["collective-experiments.csv"] != nil && files["collective-agents.csv"] != nil &&
        files["collective-turns.csv"] != nil && files["collective-turn-citations.csv"] != nil,
        "Portable export omitted collective-lab provenance"
    )
    let markdown = String(data: files["research-atlas.md"] ?? Data(), encoding: .utf8) ?? ""
    try expect(markdown.contains("not validated measures of human collective intelligence"), "The collective-lab export omitted its experimental limitation")

    try fixture.database.deleteCollectiveExperiment(id: experiment.id)
    try expect(try fixture.database.collectiveAgents(experimentID: experiment.id).isEmpty, "Deleting a collective experiment left dependent roles")
    try expect(try fixture.database.collectiveTurns(experimentID: experiment.id).isEmpty, "Deleting a collective experiment left dependent turns")
    try expect(try fixture.database.collectiveTurnCitations(turnID: turn.id).isEmpty, "Deleting a collective experiment left dependent citations")
    try expect(try fixture.database.literatureItems().contains { $0.id == source.id }, "Deleting a collective experiment removed a source paper")
}

func checkGroundedCriticalAIContractsAndTargets() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }

    let paper = LiteratureItem(title: "Critical reasoning source")
    try fixture.database.upsertLiterature(paper)
    let sourceText = "The observed outcome depended on task structure and the accuracy of the supplied advice."
    try fixture.database.indexPDFPages(literatureID: paper.id, pages: [sourceText])
    let passage = RetrievedPassage(
        retrievalSetID: UUID(), sourcePassageID: "\(paper.id.uuidString):1", literatureID: paper.id,
        page: 1, passageText: sourceText, extractionMethod: "PDF text extraction",
        sourceIndexedAt: Date(), rank: 1
    )
    let argument = ResearchArgument(proposition: "AI advice improves collective judgment.", qualification: "Only under specified task conditions.")
    let analysisID = UUID()
    let package = try GroundedDeliberationBuilder.package(
        analysisID: analysisID, argument: argument, evidence: [], passages: [passage],
        literature: [paper], model: "gpt-test", maximumOutputTokens: 2400
    )
    try expect(package.citations.map(\.label) == ["S1"] && package.request.input.contains(argument.proposition), "The deliberation package omitted its source label or argument context")

    var collectiveExperiment = CollectiveExperiment(
        title: "Bounded role test", researchPurpose: "Test calibrated role contributions.",
        taskInstructions: "Assess the conditional claim.", interactionMode: .independent
    )
    let collectiveAgent = CollectiveAgent(
        experimentID: collectiveExperiment.id, label: "Methodological critic",
        role: "Identify design boundaries", informationAvailable: "Approved source passages only", position: 1
    )
    let hiddenPrior = CollectiveTurn(
        experimentID: collectiveExperiment.id, round: 1, sequence: 1, kind: .initialJudgment,
        responseText: "SECRET PRIOR JUDGMENT"
    )
    let independentPackage = try GroundedCollectiveTurnBuilder.package(
        analysisID: UUID(), experiment: collectiveExperiment, agent: collectiveAgent,
        round: 1, kind: .initialJudgment, additionalInstruction: "Preserve qualifications.",
        priorTurns: [hiddenPrior], passages: [passage], literature: [paper],
        model: "gpt-test", maximumOutputTokens: 1200
    )
    try expect(
        independentPackage.request.input.contains("Methodological critic") &&
        independentPackage.request.input.contains("Hidden by the independent-assessment design") &&
        !independentPackage.request.input.contains("SECRET PRIOR JUDGMENT") &&
        independentPackage.citations.map(\.label) == ["S1"],
        "The collective-turn builder leaked an independent prior turn or omitted role/source context"
    )
    collectiveExperiment.interactionMode = .structuredDisagreement
    let disagreementPackage = try GroundedCollectiveTurnBuilder.package(
        analysisID: UUID(), experiment: collectiveExperiment, agent: collectiveAgent,
        round: 2, kind: .deliberation, additionalInstruction: "Challenge the earlier inference.",
        priorTurns: [hiddenPrior], passages: [passage], literature: [paper],
        model: "gpt-test", maximumOutputTokens: 1200
    )
    try expect(disagreementPackage.request.input.contains("SECRET PRIOR JUDGMENT"), "A deliberative collective turn omitted the recorded prior-turn context")
    let validCollective = GroundedCollectiveTurnOutput(
        insufficientEvidence: false, insufficiencyReason: "",
        response: "The claim remains conditional on task structure [S1].",
        confidence: 0.72, uncertainty: "Only one supplied passage.", citations: ["S1"]
    )
    let validCollectiveJSON = String(data: try JSONEncoder().encode(validCollective), encoding: .utf8)!
    _ = try GroundedCollectiveTurnBuilder.decodeAndValidate(validCollectiveJSON, allowedCitationLabels: ["S1"])
    var invalidCollective = validCollective
    invalidCollective.citations = ["S99"]
    var rejectedCollectiveCitation = false
    do {
        _ = try GroundedCollectiveTurnBuilder.decodeAndValidate(
            String(data: try JSONEncoder().encode(invalidCollective), encoding: .utf8)!,
            allowedCitationLabels: ["S1"]
        )
    } catch { rejectedCollectiveCitation = true }
    try expect(rejectedCollectiveCitation, "A collective model turn accepted an unavailable citation label")

    func contribution(_ text: String, labels: [String] = ["S1"]) -> GroundedDeliberationContribution {
        GroundedDeliberationContribution(content: text, citations: labels, uncertainty: "Bounded by the supplied passage.")
    }
    let roles: [GroundedDeliberationRole] = [
        .init(perspective: .theoretical, initialAssessment: contribution("The construct needs definition."), crossExamination: contribution("The causal framing is stronger than the passage."), revisedAssessment: contribution("A bounded association is supportable.")),
        .init(perspective: .methodological, initialAssessment: contribution("Task structure is a boundary."), crossExamination: contribution("Accuracy may moderate the outcome."), revisedAssessment: contribution("The design details remain necessary.")),
        .init(perspective: .evidence, initialAssessment: contribution("The passage reports a conditional outcome."), crossExamination: contribution("The claim omits those conditions."), revisedAssessment: contribution("The qualification partially resolves this.")),
        .init(perspective: .alternative, initialAssessment: contribution("Advice accuracy offers an alternative explanation."), crossExamination: contribution("Task structure could also drive the result."), revisedAssessment: contribution("Both remain plausible."))
    ]
    let validDeliberation = GroundedDeliberationOutput(
        insufficientEvidence: false, insufficiencyReason: "", roles: roles,
        synthesis: contribution("The roles agree only that the current claim requires explicit conditions.")
    )
    let validDeliberationJSON = String(data: try JSONEncoder().encode(validDeliberation), encoding: .utf8)!
    _ = try GroundedDeliberationBuilder.decodeAndValidate(validDeliberationJSON, allowedCitationLabels: ["S1"])

    var duplicateRoles = validDeliberation
    duplicateRoles.roles[3].perspective = .theoretical
    var rejectedDuplicateRole = false
    do {
        _ = try GroundedDeliberationBuilder.decodeAndValidate(
            String(data: try JSONEncoder().encode(duplicateRoles), encoding: .utf8)!,
            allowedCitationLabels: ["S1"]
        )
    } catch { rejectedDuplicateRole = true }
    try expect(rejectedDuplicateRole, "A model deliberation accepted a duplicate role and omitted a required perspective")

    var inventedLabel = validDeliberation
    inventedLabel.roles[0].initialAssessment.citations = ["S9"]
    var rejectedInventedLabel = false
    do {
        _ = try GroundedDeliberationBuilder.decodeAndValidate(
            String(data: try JSONEncoder().encode(inventedLabel), encoding: .utf8)!,
            allowedCitationLabels: ["S1"]
        )
    } catch { rejectedInventedLabel = true }
    try expect(rejectedInventedLabel, "A model deliberation accepted an unavailable citation label")

    let biasOutput = GroundedBiasAuditOutput(
        insufficientEvidence: false, insufficiencyReason: "",
        concerns: [GroundedBiasConcern(
            kind: .overgeneralisation, potentialProblem: "The proposition may omit recorded conditions.",
            whyItMatters: "The task and advice accuracy changed the observed outcome.",
            alternativeInterpretations: "The effect may be conditional rather than general.",
            investigationQuestions: ["Which task structures preserve the effect?"],
            uncertainty: "One supplied passage.", citations: ["S1"]
        )]
    )
    _ = try GroundedBiasAuditBuilder.decodeAndValidate(
        String(data: try JSONEncoder().encode(biasOutput), encoding: .utf8)!, allowedCitationLabels: ["S1"]
    )
    var uncitedBias = biasOutput
    uncitedBias.concerns[0].citations = []
    var rejectedUncitedBias = false
    do {
        _ = try GroundedBiasAuditBuilder.decodeAndValidate(
            String(data: try JSONEncoder().encode(uncitedBias), encoding: .utf8)!, allowedCitationLabels: ["S1"]
        )
    } catch { rejectedUncitedBias = true }
    try expect(rejectedUncitedBias, "A model bias concern was accepted without a source label")

    let contradictionOutput = GroundedContradictionReviewOutput(
        insufficientEvidence: false, insufficiencyReason: "", suggestedStatus: .contextualDifference,
        assessment: "The apparent conflict is plausibly conditional on task structure.",
        possibleExplanations: ["Advice accuracy differs."], contextualDifferences: ["Task structure differs."],
        unresolvedQuestions: ["Were outcomes operationalised identically?"], citations: ["S1"]
    )
    _ = try GroundedContradictionReviewBuilder.decodeAndValidate(
        String(data: try JSONEncoder().encode(contradictionOutput), encoding: .utf8)!, allowedCitationLabels: ["S1"]
    )
    var invalidContradiction = contradictionOutput
    invalidContradiction.citations = ["S404"]
    var rejectedContradictionLabel = false
    do {
        _ = try GroundedContradictionReviewBuilder.decodeAndValidate(
            String(data: try JSONEncoder().encode(invalidContradiction), encoding: .utf8)!, allowedCitationLabels: ["S1"]
        )
    } catch { rejectedContradictionLabel = true }
    try expect(rejectedContradictionLabel, "A contradiction review accepted an unavailable source label")

    let targetID = UUID()
    let analysis = AIAnalysis(
        id: analysisID, kind: .contradictionReview, provider: "Test provider", model: "gpt-test",
        promptVersion: GroundedContradictionReviewBuilder.promptVersion,
        targetType: .contradictionCase, targetID: targetID, userQuery: "Investigate the apparent conflict.",
        responseText: contradictionOutput.assessment, structuredResponseJSON: String(data: try JSONEncoder().encode(contradictionOutput), encoding: .utf8)!,
        status: .completed, transmittedPassageCount: 1, transmittedCharacterCount: package.characterCount
    )
    let storedCitation = AIAnalysisCitation(
        analysisID: analysis.id, label: "S1", sourcePassageID: passage.sourcePassageID,
        literatureID: paper.id, page: 1, quotedPassage: sourceText
    )
    try fixture.database.saveAIAnalysis(analysis, citations: [storedCitation])
    let stored = try fixture.database.aiAnalyses().first
    try expect(stored?.targetType == .contradictionCase && stored?.targetID == targetID, "AI analysis target provenance was not preserved")
    let files = try ResearchExporter.files(for: fixture.database.exportBundle())
    let aiCSV = String(data: files["ai-analyses.csv"] ?? Data(), encoding: .utf8) ?? ""
    try expect(aiCSV.contains("target_type") && aiCSV.contains(targetID.uuidString), "Portable AI analysis export omitted target provenance")
}

func checkGroundedResearcherNoteSnapshots() throws {
    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }

    let originalText = "A working interpretation proposes that calibrated dissent may reduce conformity when advice confidence is visible. This is a researcher hypothesis, not a published finding."
    let note = ObsidianNote(
        path: "/fixtures/calibrated-dissent.md", title: "Calibrated dissent hypothesis",
        content: originalText, tags: ["working-theory"], modifiedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    try fixture.database.upsertObsidianNote(note)

    let set = RetrievalSet(name: "Dissent notes", query: "calibrated dissent")
    let paperResults = try fixture.database.createRetrievalSet(set)
    try expect(paperResults.isEmpty, "A note-only retrieval unexpectedly returned a paper passage")
    let noteResults = try fixture.database.retrievedNoteSnippets(retrievalSetID: set.id)
    try expect(noteResults.count == 1, "A matching Obsidian note was not snapshotted into the retrieval set")
    guard let snapshot = noteResults.first else { throw CheckFailure(description: "Missing note snapshot") }
    try expect(snapshot.noteID == note.id && snapshot.snippetText == originalText, "The exact note excerpt or identity was not preserved")
    try expect(snapshot.citationStatus == .current, "A newly captured note excerpt was not current")

    let filteredSet = RetrievalSet(name: "Filtered papers", query: "calibrated dissent", yearFrom: 2020)
    _ = try fixture.database.createRetrievalSet(filteredSet)
    try expect(try fixture.database.retrievedNoteSnippets(retrievalSetID: filteredSet.id).isEmpty, "Researcher notes bypassed a publication-year filter")

    let analysisID = UUID()
    let package = try GroundedAnswerBuilder.package(
        analysisID: analysisID, query: "What hypothesis is recorded?", passages: [],
        noteSnippets: [snapshot], literature: [], model: "gpt-test", maximumOutputTokens: 800
    )
    try expect(package.citations.isEmpty && package.noteCitations.map(\.label) == ["N1"], "Note-only grounding did not use a separate N-series citation")
    try expect(package.request.instructions.contains("must never be represented as published evidence"), "The note-grounding prompt omitted the source-class safety rule")

    let answer = GroundedAnswer(
        answer: "The researcher records a hypothesis that calibrated dissent may reduce conformity.",
        insufficientEvidence: false, insufficiencyReason: "",
        claims: [.init(text: "This is a researcher hypothesis.", citations: ["N1"], interpretation: true)]
    )
    let answerJSON = String(data: try JSONEncoder().encode(answer), encoding: .utf8)!
    _ = try GroundedAnswerBuilder.decodeAndValidate(answerJSON, allowedCitationLabels: ["N1"])
    var rejectedPaperLabel = false
    do {
        _ = try GroundedAnswerBuilder.decodeAndValidate(answerJSON, allowedCitationLabels: ["S1"])
    } catch { rejectedPaperLabel = true }
    try expect(rejectedPaperLabel, "A note citation was silently accepted as a paper citation")

    let analysis = AIAnalysis(
        id: analysisID, kind: .literatureAnswer, provider: "Test provider", model: "gpt-test",
        promptVersion: GroundedAnswerBuilder.promptVersion, retrievalSetID: set.id,
        userQuery: "What hypothesis is recorded?", responseText: answer.answer,
        structuredResponseJSON: answerJSON, status: .completed, transmittedPassageCount: 1,
        transmittedCharacterCount: package.characterCount
    )
    try fixture.database.saveAIAnalysis(analysis, citations: [], noteCitations: package.noteCitations)
    let storedCitations = try fixture.database.aiAnalysisNoteCitations(analysisID: analysis.id)
    try expect(storedCitations.count == 1 && storedCitations.first?.citationStatus == .current, "AI note-citation provenance did not round trip")

    var revisedNote = note
    revisedNote.content = "The earlier calibrated-dissent hypothesis was withdrawn pending further reading."
    revisedNote.modifiedAt = Date(timeIntervalSince1970: 1_800_000_100)
    try fixture.database.upsertObsidianNote(revisedNote)
    let staleRetrieval = try fixture.database.retrievedNoteSnippets(retrievalSetID: set.id)
    let staleCitation = try fixture.database.aiAnalysisNoteCitations(analysisID: analysis.id)
    try expect(staleRetrieval.first?.citationStatus == .passageChanged, "A changed note excerpt was not marked stale in its retrieval set")
    try expect(staleCitation.first?.citationStatus == .passageChanged, "A changed note excerpt was not marked stale in the saved AI analysis")
    var acceptedStaleNote = false
    do {
        _ = try GroundedAnswerBuilder.package(
            analysisID: UUID(), query: "Use the stale note", passages: [], noteSnippets: staleRetrieval,
            literature: [], model: "gpt-test", maximumOutputTokens: 400
        )
        acceptedStaleNote = true
    } catch { }
    try expect(!acceptedStaleNote, "A stale researcher-note excerpt remained eligible for transmission")

    let bundle = try fixture.database.exportBundle()
    try expect(bundle.formatVersion == 9 && bundle.retrievedNoteSnippets.count == 1 && bundle.aiAnalysisNoteCitations.count == 1, "Portable export omitted note-grounding provenance")
    let files = try ResearchExporter.files(for: bundle)
    let retrievalCSV = String(data: files["retrieved-note-snippets.csv"] ?? Data(), encoding: .utf8) ?? ""
    let analysisCSV = String(data: files["ai-analysis-note-citations.csv"] ?? Data(), encoding: .utf8) ?? ""
    let markdown = String(data: files["research-atlas.md"] ?? Data(), encoding: .utf8) ?? ""
    try expect(retrievalCSV.contains(note.id.uuidString) && retrievalCSV.contains(RetrievalCitationStatus.passageChanged.rawValue), "Note retrieval CSV omitted identity or live staleness")
    try expect(analysisCSV.contains("N1") && analysisCSV.contains(note.title), "AI note-citation CSV omitted its label or title")
    try expect(markdown.contains("Researcher-note snapshots (context, not published evidence)"), "Markdown export did not distinguish notes from published sources")
}

func checkDirectZoteroIdentityRouting() throws {
    try expect(
        ZoteroAPIRouting.itemPath(libraryID: "user:0", itemKey: "ABCD1234") == "users/0/items/ABCD1234",
        "A user-library item did not map to its exact local-API route"
    )
    try expect(
        ZoteroAPIRouting.itemPath(libraryID: "group:42", itemKey: "WXYZ9876") == "groups/42/items/WXYZ9876",
        "A group-library item did not map to its exact local-API route"
    )
    try expect(
        ZoteroAPIRouting.itemSelectionURL(libraryID: "user:0", itemKey: "ABCD1234")?.absoluteString == "zotero://select/library/items/ABCD1234",
        "A user-library item did not map to a direct Zotero desktop selection URL"
    )
    try expect(
        ZoteroAPIRouting.itemSelectionURL(libraryID: "group:42", itemKey: "WXYZ9876")?.absoluteString == "zotero://select/groups/42/items/WXYZ9876",
        "A group-library item did not map to a direct Zotero desktop selection URL"
    )
    try expect(
        ZoteroAPIRouting.itemSelectionURL(libraryID: "web-user:123456", itemKey: "ABCD1234")?.absoluteString == "zotero://select/library/items/ABCD1234",
        "A Web API personal-library item did not retain its direct desktop selection URL"
    )
    try expect(
        ZoteroAPIRouting.webItemPath(libraryID: "user:0", itemKey: "ABCD1234", userID: "123456") == "users/123456/items/ABCD1234",
        "A personal item did not map to the configured account's exact Web API route"
    )
    try expect(
        ZoteroAPIRouting.webItemPath(libraryID: "group:42", itemKey: "WXYZ9876", userID: "123456") == "groups/42/items/WXYZ9876",
        "A group item did not preserve its group identity in the Web API route"
    )
    let request = ZoteroAPIRouting.readRequest(
        url: URL(string: "http://localhost:23119/api/users/0/items/ABCD1234")!,
        expectedServerID: "server-identity"
    )
    try expect(request.value(forHTTPHeaderField: "Zotero-API-Version") == "3", "Zotero API v3 was not requested explicitly")
    try expect(request.value(forHTTPHeaderField: "Zotero-Server-ID") == "server-identity", "The documented Zotero server-identity precondition header was not used")
    try expect(request.value(forHTTPHeaderField: "Zotero-Expected-Server-ID") == nil, "The obsolete non-standard Zotero server header was still present")
    let webRequest = ZoteroAPIRouting.webReadRequest(
        url: URL(string: "https://api.zotero.org/users/123456/items/ABCD1234")!,
        apiKey: "test-read-key"
    )
    try expect(webRequest.value(forHTTPHeaderField: "Zotero-API-Version") == "3", "The Web API request did not pin API v3")
    try expect(webRequest.value(forHTTPHeaderField: "Zotero-API-Key") == "test-read-key", "The Web API key was not sent in Zotero's recommended header")
    try expect(webRequest.url?.query == nil, "The Zotero Web API key leaked into the URL query")

    let fixture = try DatabaseFixture()
    defer { fixture.cleanup() }
    let collection = ZoteroCollection(serverID: "server-identity", libraryID: "user:0", key: "COLL0001", name: "Methods")
    let original = LiteratureItem(
        zoteroKey: "ABCD1234", zoteroServerID: "server-identity", zoteroLibraryID: "user:0",
        zoteroLibraryName: "My Library", zoteroVersion: 1, title: "Original Zotero title", source: .zotero
    )
    try fixture.database.applyZoteroSync(ZoteroSnapshot(
        items: [original], collections: [collection], itemCollectionKeys: ["ABCD1234": ["COLL0001"]],
        serverID: "server-identity", libraryVersion: 10
    ))
    var refreshed = original
    refreshed.title = "Exact-key API title"
    refreshed.zoteroVersion = 2
    try fixture.database.applyZoteroItemRefresh(ZoteroItemRefresh(
        item: refreshed, collectionKeys: ["COLL0001"],
        connection: ZoteroConnectionInfo(
            endpoint: "http://localhost:23119/api/", serverID: "server-identity",
            apiVersion: "3", schemaVersion: "99"
        ),
        apiPath: "users/0/items/ABCD1234"
    ))
    let stored = try fixture.database.literatureItems()
    try expect(stored.count == 1 && stored.first?.title == refreshed.title && stored.first?.zoteroVersion == 2, "An exact-key Zotero refresh duplicated or failed to update its item")
    try expect(try fixture.database.literatureCollectionMemberships().count == 1, "An exact-key Zotero refresh lost a valid collection membership")
    try expect(try fixture.database.zoteroCheckpoint()?.libraryVersion == 10, "A single-item verification incorrectly advanced the library checkpoint")

    let webPaper = LiteratureItem(
        zoteroKey: "CLOUD123", zoteroServerID: "zotero.org:user:123456",
        zoteroLibraryID: "web-user:123456", zoteroLibraryName: "My Library — Zotero Web",
        zoteroVersion: 7, title: "Web API paper", source: .zotero
    )
    let webCollection = ZoteroCollection(
        serverID: "zotero.org:user:123456", libraryID: "web-user:123456",
        key: "WEBCOLL1", name: "Cloud metadata"
    )
    try fixture.database.applyZoteroRefresh(ZoteroRefresh(
        serverID: "zotero.org:user:123456",
        snapshots: [ZoteroSnapshot(
            items: [webPaper], collections: [webCollection],
            itemCollectionKeys: ["CLOUD123": ["WEBCOLL1"]],
            serverID: "zotero.org:user:123456", libraryID: "web-user:123456",
            libraryKind: .user, libraryName: "My Library — Zotero Web",
            libraryVersion: 77
        )],
        accessibleLibraryIDs: ["web-user:123456"]
    ))
    let webStored = try fixture.database.literatureItems().first { $0.zoteroKey == "CLOUD123" }
    try expect(webStored?.zoteroServerID == "zotero.org:user:123456", "A Web API library sync lost its account-scoped identity")
    try expect(try fixture.database.zoteroLibraries().contains { $0.libraryID == "web-user:123456" && $0.libraryVersion == 77 }, "A Web API library checkpoint was not persisted")
}

func checkQuestionLiteratureCoverageAudit() throws {
    let first = LiteratureItem(
        title: "Early experiment", year: 2020, tags: ["Collective intelligence", "Advice"]
    )
    let second = LiteratureItem(
        title: "Later experiment", year: 2024, tags: ["collective intelligence"],
        sourceAvailability: .libraryUnavailable
    )
    let third = LiteratureItem(title: "Undated observation")
    let complete = LiteratureComparisonProfile(
        literatureID: first.id,
        researchQuestion: "Does calibrated advice improve group accuracy?",
        theoreticalFramework: "Social influence",
        studyDesign: "Randomised experiment",
        sample: "120 online groups",
        independentVariables: "Advice calibration",
        dependentVariables: "Group accuracy",
        operationalDefinitions: "Calibration error",
        mainFindings: "Calibrated advice improved accuracy.",
        limitations: "Single task domain"
    )
    let partial = LiteratureComparisonProfile(
        literatureID: second.id,
        studyDesign: "randomised experiment",
        mainFindings: "Effects varied by group composition."
    )
    let unrelated = LiteratureComparisonProfile(
        literatureID: UUID(), studyDesign: "Survey", mainFindings: "Must not leak into the linked set."
    )

    let report = LiteratureCoverageAnalyzer.analyze(
        literature: [third, second, first],
        comparisonProfiles: [unrelated, partial, complete]
    )
    try expect(report.linkedCount == 3 && report.availableCount == 2, "Coverage audit did not preserve the linked-set or availability boundary")
    try expect(report.knownYearCount == 2 && report.earliestYear == 2020 && report.latestYear == 2024, "Coverage audit year range is incorrect")
    try expect(report.profiledCount == 2 && report.fullyProfiledCount == 1, "Coverage audit profile completion is incorrect")
    try expect(report.designDistribution == [LiteratureCoverageCategory(label: "Randomised experiment", count: 2)], "Coverage categories were not normalised without losing their display label")
    try expect(report.topicDistribution.first == LiteratureCoverageCategory(label: "Collective intelligence", count: 2), "Coverage audit did not count linked-paper topics")
    let findings = report.fields.first { $0.field == .mainFindings }
    let limitations = report.fields.first { $0.field == .limitations }
    try expect(findings?.recordedCount == 2 && limitations?.recordedCount == 1, "Comparison-field coverage counts are incorrect")
    try expect(report.papers.first?.title == "Early experiment" && report.papers.last?.title == "Undated observation", "Coverage paper order is not deterministic")
    try expect(report.attentionNotes.contains { $0.contains("not evidence of a wider methodological gap") }, "Single-design coverage was not bounded against gap overclaiming")
    try expect(report.scopeStatement.contains("does not measure the wider literature"), "Coverage audit omitted its library-only interpretation boundary")
}

let checks: [(String, () throws -> Void)] = [
    ("database workflow and provenance", checkResearchWorkflow),
    ("Zotero duplicate prevention", checkZoteroDeduplication),
    ("metadata, PDF, and note search", checkFullTextSearch),
    ("Obsidian metadata parsing", checkObsidianParsing),
    ("Obsidian recursive discovery", checkObsidianDiscovery),
    ("local research-folder PDF discovery", checkLocalResearchFolderDiscovery),
    ("explicit note matching and review preservation", checkExplicitNoteMatchingAndReview),
    ("manual and opt-in title note links", checkManualAndOptionalTitleNoteLinks),
    ("argument history, portable export, and database backup", checkArgumentHistoryExportAndBackup),
    ("incremental Zotero state and source partitioning", checkZoteroIncrementalStateAndSourcePartitioning),
    ("Zotero group libraries and collection provenance", checkZoteroGroupLibrariesAndCollections),
    ("schema-4 migration provenance preservation", checkVersionFourMigrationPreservesEvidence),
    ("validated database restore and recovery copy", checkValidatedDatabaseRestoreAndRecoveryCopy),
    ("missing PDF diagnosis and provenance-safe repair", checkMissingPDFDiagnosisAndRepair),
    ("evidence geometry editing and deletion", checkEvidenceGeometryEditingAndDeletion),
    ("grounded retrieval and citation failures", checkGroundedRetrievalAndCitationFailures),
    ("comparison and knowledge-graph foundation", checkComparisonAndKnowledgeGraphFoundation),
    ("indexing job recovery", checkIndexingJobRecovery),
    ("structured claims and revision provenance", checkStructuredClaimsAndRevisionProvenance),
    ("research-question, idea, and history workflows", checkQuestionIdeaAndHistoryWorkflows),
    ("context-sensitive contradiction review", checkContextualContradictionReview),
    ("AI provider configuration and secret boundary", checkAIProviderConfigurationAndSecretBoundary),
    ("direct Claude, Gemini, OpenAI, Ollama, and LM Studio HTTP contracts", checkDirectAIProviderHTTPContracts),
    ("grounded AI answer contract and citation rejection", checkGroundedAnswerContractAndCitationRejection),
    ("AI analysis provenance, review, and citation staleness", checkAIAnalysisProvenanceReviewAndStaleness),
    ("bias-audit questions and review decisions", checkBiasAuditQuestionsAndReviewDecisions),
    ("deliberation records and citation integrity", checkDeliberationRecordAndCitationIntegrity),
    ("writing evidence and citation-review workflow", checkWritingEvidenceAndCitationReviewWorkflow),
    ("collective experiment reproducibility and safety", checkCollectiveExperimentReproducibilityAndSafety),
    ("grounded critical-AI contracts and target provenance", checkGroundedCriticalAIContractsAndTargets),
    ("grounded researcher-note snapshots and safety boundaries", checkGroundedResearcherNoteSnapshots),
    ("direct Zotero identity, API routing, and exact-item refresh", checkDirectZoteroIdentityRouting),
    ("question-linked literature coverage boundaries", checkQuestionLiteratureCoverageAudit)
]

do {
    for (name, check) in checks {
        try check()
        print("PASS: \(name)")
    }
    print("All \(checks.count) Research Atlas checks passed.")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}

private extension JSONDecoder {
    static var configuredForResearchAtlas: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
