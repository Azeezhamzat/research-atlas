import Foundation
import SQLite3

public enum DatabaseError: Error, LocalizedError {
    case open(String)
    case prepare(String)
    case execute(String)
    case invalidData(String)
    case incompatibleBackup(String)
    case restore(String)

    public var errorDescription: String? {
        switch self {
        case .open(let message): "Could not open the research database: \(message)"
        case .prepare(let message): "Could not prepare a database operation: \(message)"
        case .execute(let message): "Database operation failed: \(message)"
        case .invalidData(let message): "The database contains invalid data: \(message)"
        case .incompatibleBackup(let message): "This backup cannot be restored: \(message)"
        case .restore(let message): "The database restore failed: \(message)"
        }
    }
}

private enum SQLValue {
    case text(String)
    case int(Int64)
    case double(Double)
    case null
}

public final class AtlasDatabase: @unchecked Sendable {
    public static let currentSchemaVersion = 16
    public let url: URL
    private var connection: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let dateFormatter = ISO8601DateFormatter()

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &connection, flags, nil) == SQLITE_OK else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
            if let connection { sqlite3_close(connection) }
            throw DatabaseError.open(message)
        }
        sqlite3_busy_timeout(connection, 5_000)
        try migrate()
    }

    deinit {
        if let connection { sqlite3_close(connection) }
    }

    public static func defaultURL() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return root.appendingPathComponent("Research Atlas", isDirectory: true)
            .appendingPathComponent("research-atlas.sqlite3")
    }

    private func migrate() throws {
        try synchronized {
            try execute("PRAGMA foreign_keys = ON")
            try execute("PRAGMA journal_mode = WAL")
            try execute("""
                CREATE TABLE IF NOT EXISTS schema_migrations (
                    version INTEGER PRIMARY KEY,
                    applied_at TEXT NOT NULL
                )
                """)
            let version = try scalarInt("SELECT COALESCE(MAX(version), 0) FROM schema_migrations")
            if version < 1 {
                try execute("BEGIN IMMEDIATE")
                do {
                    try execute("""
                        CREATE TABLE literature_items (
                            id TEXT PRIMARY KEY,
                            zotero_key TEXT UNIQUE,
                            title TEXT NOT NULL,
                            authors TEXT NOT NULL DEFAULT '',
                            publication_year INTEGER,
                            abstract_text TEXT NOT NULL DEFAULT '',
                            doi TEXT,
                            item_type TEXT NOT NULL,
                            source TEXT NOT NULL,
                            pdf_path TEXT,
                            external_url TEXT,
                            created_at TEXT NOT NULL,
                            modified_at TEXT NOT NULL
                        )
                        """)
                    try execute("""
                        CREATE TABLE obsidian_notes (
                            id TEXT PRIMARY KEY,
                            path TEXT NOT NULL UNIQUE,
                            title TEXT NOT NULL,
                            content TEXT NOT NULL,
                            tags_json TEXT NOT NULL,
                            wikilinks_json TEXT NOT NULL,
                            citation_keys_json TEXT NOT NULL,
                            dois_json TEXT NOT NULL,
                            modified_at TEXT NOT NULL
                        )
                        """)
                    try execute("""
                        CREATE TABLE research_projects (
                            id TEXT PRIMARY KEY,
                            title TEXT NOT NULL,
                            summary TEXT NOT NULL DEFAULT '',
                            created_at TEXT NOT NULL,
                            modified_at TEXT NOT NULL
                        )
                        """)
                    try execute("""
                        CREATE TABLE research_questions (
                            id TEXT PRIMARY KEY,
                            project_id TEXT NOT NULL REFERENCES research_projects(id) ON DELETE CASCADE,
                            question TEXT NOT NULL,
                            notes TEXT NOT NULL DEFAULT '',
                            status TEXT NOT NULL,
                            created_at TEXT NOT NULL,
                            modified_at TEXT NOT NULL
                        )
                        """)
                    try execute("""
                        CREATE TABLE research_arguments (
                            id TEXT PRIMARY KEY,
                            question_id TEXT REFERENCES research_questions(id) ON DELETE SET NULL,
                            proposition TEXT NOT NULL,
                            qualification TEXT NOT NULL DEFAULT '',
                            status TEXT NOT NULL,
                            created_at TEXT NOT NULL,
                            modified_at TEXT NOT NULL
                        )
                        """)
                    try execute("""
                        CREATE TABLE evidence_relationships (
                            id TEXT PRIMARY KEY,
                            argument_id TEXT NOT NULL REFERENCES research_arguments(id) ON DELETE CASCADE,
                            literature_id TEXT NOT NULL REFERENCES literature_items(id) ON DELETE CASCADE,
                            relation TEXT NOT NULL,
                            summary TEXT NOT NULL,
                            page INTEGER,
                            quoted_passage TEXT NOT NULL DEFAULT '',
                            verification TEXT NOT NULL,
                            created_at TEXT NOT NULL
                        )
                        """)
                    try execute("""
                        CREATE VIRTUAL TABLE search_index USING fts5(
                            entity_id UNINDEXED,
                            entity_type UNINDEXED,
                            title,
                            body,
                            tokenize='unicode61 remove_diacritics 2'
                        )
                        """)
                    try execute(
                        "INSERT INTO schema_migrations(version, applied_at) VALUES(1, ?)",
                        [.text(dateFormatter.string(from: Date()))]
                    )
                    try execute("COMMIT")
                } catch {
                    try? execute("ROLLBACK")
                    throw error
                }
            }
            if version < 2 {
                try execute("BEGIN IMMEDIATE")
                do {
                    try execute("""
                        CREATE TABLE IF NOT EXISTS source_passages (
                            id TEXT PRIMARY KEY,
                            literature_id TEXT NOT NULL REFERENCES literature_items(id) ON DELETE CASCADE,
                            page INTEGER NOT NULL,
                            passage_text TEXT NOT NULL,
                            extraction_method TEXT NOT NULL,
                            indexed_at TEXT NOT NULL,
                            UNIQUE(literature_id, page)
                        )
                        """)
                    try execute("INSERT INTO schema_migrations(version, applied_at) VALUES(2, ?)", [.text(dateFormatter.string(from: Date()))])
                    try execute("COMMIT")
                } catch {
                    try? execute("ROLLBACK")
                    throw error
                }
            }
            if version < 3 {
                try execute("BEGIN IMMEDIATE")
                do {
                    try execute("ALTER TABLE literature_items ADD COLUMN citation_key TEXT")
                    try execute("ALTER TABLE literature_items ADD COLUMN tags_json TEXT NOT NULL DEFAULT '[]'")
                    try execute("""
                        CREATE TABLE note_links (
                            id TEXT PRIMARY KEY,
                            note_id TEXT NOT NULL REFERENCES obsidian_notes(id) ON DELETE CASCADE,
                            literature_id TEXT NOT NULL REFERENCES literature_items(id) ON DELETE CASCADE,
                            match_method TEXT NOT NULL,
                            matched_identifier TEXT NOT NULL,
                            review_state TEXT NOT NULL,
                            created_at TEXT NOT NULL,
                            modified_at TEXT NOT NULL,
                            UNIQUE(note_id, literature_id)
                        )
                        """)
                    try execute("CREATE INDEX note_links_literature_idx ON note_links(literature_id, review_state)")
                    try execute("INSERT INTO schema_migrations(version, applied_at) VALUES(3, ?)", [.text(dateFormatter.string(from: Date()))])
                    try execute("COMMIT")
                } catch {
                    try? execute("ROLLBACK")
                    throw error
                }
            }
            if version < 4 {
                try execute("BEGIN IMMEDIATE")
                do {
                    try execute("""
                        CREATE TABLE argument_versions (
                            id TEXT PRIMARY KEY,
                            argument_id TEXT NOT NULL REFERENCES research_arguments(id) ON DELETE CASCADE,
                            question_id TEXT REFERENCES research_questions(id) ON DELETE SET NULL,
                            proposition TEXT NOT NULL,
                            qualification TEXT NOT NULL DEFAULT '',
                            status TEXT NOT NULL,
                            change_note TEXT NOT NULL DEFAULT '',
                            created_at TEXT NOT NULL
                        )
                        """)
                    try execute("CREATE INDEX argument_versions_argument_idx ON argument_versions(argument_id, created_at DESC)")
                    try execute("INSERT INTO schema_migrations(version, applied_at) VALUES(4, ?)", [.text(dateFormatter.string(from: Date()))])
                    try execute("COMMIT")
                } catch {
                    try? execute("ROLLBACK")
                    throw error
                }
            }
            if version < 5 {
                // Removing the old global UNIQUE(zotero_key) constraint requires a
                // table rebuild. Foreign keys are disabled only for this migration
                // and checked before normal operation resumes.
                try execute("PRAGMA foreign_keys = OFF")
                do {
                    try execute("BEGIN IMMEDIATE")
                    try execute("""
                        CREATE TABLE literature_items_v5 (
                            id TEXT PRIMARY KEY,
                            zotero_key TEXT,
                            zotero_attachment_key TEXT,
                            zotero_server_id TEXT,
                            zotero_version INTEGER,
                            title TEXT NOT NULL,
                            authors TEXT NOT NULL DEFAULT '',
                            publication_year INTEGER,
                            abstract_text TEXT NOT NULL DEFAULT '',
                            doi TEXT,
                            citation_key TEXT,
                            tags_json TEXT NOT NULL DEFAULT '[]',
                            item_type TEXT NOT NULL,
                            source TEXT NOT NULL,
                            source_availability TEXT NOT NULL DEFAULT 'Available',
                            pdf_path TEXT,
                            external_url TEXT,
                            created_at TEXT NOT NULL,
                            modified_at TEXT NOT NULL,
                            UNIQUE(zotero_server_id, zotero_key)
                        )
                        """)
                    try execute("""
                        INSERT INTO literature_items_v5(
                            id,zotero_key,title,authors,publication_year,abstract_text,doi,citation_key,
                            tags_json,item_type,source,pdf_path,external_url,created_at,modified_at
                        )
                        SELECT id,zotero_key,title,authors,publication_year,abstract_text,doi,citation_key,
                               tags_json,item_type,source,pdf_path,external_url,created_at,modified_at
                        FROM literature_items
                        """)
                    try execute("DROP TABLE literature_items")
                    try execute("ALTER TABLE literature_items_v5 RENAME TO literature_items")
                    try execute("CREATE INDEX literature_zotero_key_idx ON literature_items(zotero_key)")
                    try execute("CREATE INDEX literature_source_status_idx ON literature_items(source, source_availability)")
                    try execute("""
                        CREATE TABLE integration_state (
                            key TEXT PRIMARY KEY,
                            value TEXT NOT NULL,
                            updated_at TEXT NOT NULL
                        )
                        """)
                    try execute("INSERT INTO schema_migrations(version, applied_at) VALUES(5, ?)", [.text(dateFormatter.string(from: Date()))])
                    try execute("COMMIT")
                    try execute("PRAGMA foreign_keys = ON")
                    let violations = try query("PRAGMA foreign_key_check") { $0.text(0) }
                    guard violations.isEmpty else {
                        throw DatabaseError.invalidData("Schema migration 5 found broken foreign-key references.")
                    }
                } catch {
                    try? execute("ROLLBACK")
                    try? execute("PRAGMA foreign_keys = ON")
                    throw error
                }
            }
            if version < 6 {
                try execute("BEGIN IMMEDIATE")
                do {
                    try execute("ALTER TABLE literature_items ADD COLUMN pdf_byte_count INTEGER")
                    try execute("ALTER TABLE literature_items ADD COLUMN pdf_sha256 TEXT")
                    try execute("ALTER TABLE literature_items ADD COLUMN pdf_last_verified_at TEXT")
                    try execute("INSERT INTO schema_migrations(version, applied_at) VALUES(6, ?)", [.text(dateFormatter.string(from: Date()))])
                    try execute("COMMIT")
                } catch {
                    try? execute("ROLLBACK")
                    throw error
                }
            }
            if version < 7 {
                let legacyCheckpoint: ZoteroCheckpoint? = try query(
                    "SELECT value FROM integration_state WHERE key='zotero_checkpoint'",
                    map: { row in
                        try? JSONDecoder().decode(ZoteroCheckpoint.self, from: Data(row.text(0).utf8))
                    }
                ).first ?? nil
                try execute("PRAGMA foreign_keys = OFF")
                do {
                    try execute("BEGIN IMMEDIATE")
                    try execute("""
                        CREATE TABLE literature_items_v7 (
                            id TEXT PRIMARY KEY,
                            zotero_key TEXT,
                            zotero_attachment_key TEXT,
                            zotero_server_id TEXT,
                            zotero_library_id TEXT,
                            zotero_version INTEGER,
                            title TEXT NOT NULL,
                            authors TEXT NOT NULL DEFAULT '',
                            publication_year INTEGER,
                            abstract_text TEXT NOT NULL DEFAULT '',
                            doi TEXT,
                            citation_key TEXT,
                            tags_json TEXT NOT NULL DEFAULT '[]',
                            item_type TEXT NOT NULL,
                            source TEXT NOT NULL,
                            source_availability TEXT NOT NULL DEFAULT 'Available',
                            pdf_path TEXT,
                            pdf_byte_count INTEGER,
                            pdf_sha256 TEXT,
                            pdf_last_verified_at TEXT,
                            external_url TEXT,
                            created_at TEXT NOT NULL,
                            modified_at TEXT NOT NULL,
                            UNIQUE(zotero_server_id, zotero_library_id, zotero_key)
                        )
                        """)
                    try execute("""
                        INSERT INTO literature_items_v7(
                            id,zotero_key,zotero_attachment_key,zotero_server_id,zotero_library_id,zotero_version,
                            title,authors,publication_year,abstract_text,doi,citation_key,tags_json,item_type,source,
                            source_availability,pdf_path,pdf_byte_count,pdf_sha256,pdf_last_verified_at,external_url,
                            created_at,modified_at
                        )
                        SELECT id,zotero_key,zotero_attachment_key,zotero_server_id,
                               CASE WHEN source='Zotero' THEN 'user:0' ELSE NULL END,zotero_version,
                               title,authors,publication_year,abstract_text,doi,citation_key,tags_json,item_type,source,
                               source_availability,pdf_path,pdf_byte_count,pdf_sha256,pdf_last_verified_at,external_url,
                               created_at,modified_at
                        FROM literature_items
                        """)
                    try execute("DROP TABLE literature_items")
                    try execute("ALTER TABLE literature_items_v7 RENAME TO literature_items")
                    try execute("CREATE INDEX literature_zotero_key_idx ON literature_items(zotero_key)")
                    try execute("CREATE INDEX literature_source_status_idx ON literature_items(source, source_availability)")
                    try execute("CREATE INDEX literature_zotero_library_idx ON literature_items(zotero_server_id, zotero_library_id)")
                    try execute("""
                        CREATE TABLE zotero_libraries (
                            server_id TEXT NOT NULL,
                            library_id TEXT NOT NULL,
                            kind TEXT NOT NULL,
                            name TEXT NOT NULL,
                            metadata_version INTEGER,
                            library_version INTEGER,
                            availability TEXT NOT NULL,
                            last_synced_at TEXT,
                            PRIMARY KEY(server_id, library_id)
                        )
                        """)
                    try execute("""
                        INSERT OR IGNORE INTO zotero_libraries(
                            server_id,library_id,kind,name,library_version,availability,last_synced_at
                        )
                        SELECT DISTINCT zotero_server_id,'user:0','User','My Library',NULL,'Available',NULL
                        FROM literature_items
                        WHERE source='Zotero' AND zotero_server_id IS NOT NULL
                        """)
                    if let legacyCheckpoint {
                        try execute("""
                            INSERT INTO zotero_libraries(
                                server_id,library_id,kind,name,library_version,availability,last_synced_at
                            ) VALUES(?,'user:0','User','My Library',?,'Available',?)
                            ON CONFLICT(server_id,library_id) DO UPDATE SET
                                library_version=excluded.library_version,
                                availability=excluded.availability,
                                last_synced_at=excluded.last_synced_at
                            """, [
                                .text(legacyCheckpoint.serverID), .int(Int64(legacyCheckpoint.libraryVersion)),
                                .text(dateFormatter.string(from: Date()))
                            ])
                    }
                    try execute("""
                        CREATE TABLE zotero_collections (
                            server_id TEXT NOT NULL,
                            library_id TEXT NOT NULL,
                            collection_key TEXT NOT NULL,
                            name TEXT NOT NULL,
                            parent_collection_key TEXT,
                            zotero_version INTEGER,
                            PRIMARY KEY(server_id, library_id, collection_key),
                            FOREIGN KEY(server_id, library_id) REFERENCES zotero_libraries(server_id, library_id) ON DELETE CASCADE
                        )
                        """)
                    try execute("CREATE INDEX zotero_collections_parent_idx ON zotero_collections(server_id,library_id,parent_collection_key)")
                    try execute("""
                        CREATE TABLE literature_collection_memberships (
                            literature_id TEXT NOT NULL REFERENCES literature_items(id) ON DELETE CASCADE,
                            server_id TEXT NOT NULL,
                            library_id TEXT NOT NULL,
                            collection_key TEXT NOT NULL,
                            PRIMARY KEY(literature_id, server_id, library_id, collection_key),
                            FOREIGN KEY(server_id, library_id, collection_key)
                                REFERENCES zotero_collections(server_id, library_id, collection_key) ON DELETE CASCADE
                        )
                        """)
                    try execute("CREATE INDEX literature_collection_lookup_idx ON literature_collection_memberships(server_id,library_id,collection_key)")
                    try execute("INSERT INTO schema_migrations(version, applied_at) VALUES(7, ?)", [.text(dateFormatter.string(from: Date()))])
                    try execute("COMMIT")
                    try execute("PRAGMA foreign_keys = ON")
                    let violations = try query("PRAGMA foreign_key_check") { $0.text(0) }
                    guard violations.isEmpty else {
                        throw DatabaseError.invalidData("Schema migration 7 found broken foreign-key references.")
                    }
                } catch {
                    try? execute("ROLLBACK")
                    try? execute("PRAGMA foreign_keys = ON")
                    throw error
                }
            }
            if version < 8 {
                try execute("BEGIN IMMEDIATE")
                do {
                    try execute("ALTER TABLE evidence_relationships ADD COLUMN selection_geometry_json TEXT NOT NULL DEFAULT '[]'")
                    try execute("ALTER TABLE evidence_relationships ADD COLUMN selection_document_hash TEXT")
                    try execute("INSERT INTO schema_migrations(version, applied_at) VALUES(8, ?)", [.text(dateFormatter.string(from: Date()))])
                    try execute("COMMIT")
                } catch {
                    try? execute("ROLLBACK")
                    throw error
                }
            }
            if version < 9 {
                try execute("BEGIN IMMEDIATE")
                do {
                    try execute("""
                        CREATE TABLE literature_comparison_profiles (
                            literature_id TEXT PRIMARY KEY REFERENCES literature_items(id) ON DELETE CASCADE,
                            research_question TEXT NOT NULL DEFAULT '',
                            theoretical_framework TEXT NOT NULL DEFAULT '',
                            study_design TEXT NOT NULL DEFAULT '',
                            sample TEXT NOT NULL DEFAULT '',
                            independent_variables TEXT NOT NULL DEFAULT '',
                            dependent_variables TEXT NOT NULL DEFAULT '',
                            operational_definitions TEXT NOT NULL DEFAULT '',
                            main_findings TEXT NOT NULL DEFAULT '',
                            limitations TEXT NOT NULL DEFAULT '',
                            user_notes TEXT NOT NULL DEFAULT '',
                            modified_at TEXT NOT NULL
                        )
                        """)
                    try execute("""
                        CREATE TABLE retrieval_sets (
                            id TEXT PRIMARY KEY,
                            name TEXT NOT NULL,
                            query_text TEXT NOT NULL,
                            zotero_library_filter_id TEXT,
                            zotero_collection_filter_id TEXT,
                            year_from INTEGER,
                            year_to INTEGER,
                            created_at TEXT NOT NULL
                        )
                        """)
                    try execute("""
                        CREATE TABLE retrieval_set_passages (
                            retrieval_set_id TEXT NOT NULL REFERENCES retrieval_sets(id) ON DELETE CASCADE,
                            source_passage_id TEXT NOT NULL,
                            literature_id TEXT NOT NULL REFERENCES literature_items(id) ON DELETE CASCADE,
                            page INTEGER NOT NULL,
                            passage_text TEXT NOT NULL,
                            extraction_method TEXT NOT NULL,
                            source_indexed_at TEXT NOT NULL,
                            source_document_hash TEXT,
                            relevance_rank REAL NOT NULL,
                            added_at TEXT NOT NULL,
                            PRIMARY KEY(retrieval_set_id, source_passage_id)
                        )
                        """)
                    try execute("CREATE INDEX retrieval_passage_literature_idx ON retrieval_set_passages(literature_id,page)")
                    try execute("""
                        CREATE TABLE research_concepts (
                            id TEXT PRIMARY KEY,
                            name TEXT NOT NULL,
                            definition TEXT NOT NULL DEFAULT '',
                            notes TEXT NOT NULL DEFAULT '',
                            verification TEXT NOT NULL,
                            origin TEXT NOT NULL,
                            created_at TEXT NOT NULL,
                            modified_at TEXT NOT NULL
                        )
                        """)
                    try execute("""
                        CREATE TABLE knowledge_relationships (
                            id TEXT PRIMARY KEY,
                            source_type TEXT NOT NULL,
                            source_id TEXT NOT NULL,
                            target_type TEXT NOT NULL,
                            target_id TEXT NOT NULL,
                            relationship_type TEXT NOT NULL,
                            evidence_relationship_id TEXT REFERENCES evidence_relationships(id) ON DELETE SET NULL,
                            source_passage_id TEXT,
                            verification TEXT NOT NULL,
                            origin TEXT NOT NULL,
                            notes TEXT NOT NULL DEFAULT '',
                            created_at TEXT NOT NULL,
                            modified_at TEXT NOT NULL,
                            CHECK(source_type<>target_type OR source_id<>target_id)
                        )
                        """)
                    try execute("CREATE INDEX knowledge_relationship_source_idx ON knowledge_relationships(source_type,source_id)")
                    try execute("CREATE INDEX knowledge_relationship_target_idx ON knowledge_relationships(target_type,target_id)")
                    try execute("""
                        CREATE TABLE indexing_jobs (
                            id TEXT PRIMARY KEY,
                            kind TEXT NOT NULL,
                            source_name TEXT NOT NULL,
                            status TEXT NOT NULL,
                            completed_units INTEGER NOT NULL DEFAULT 0,
                            total_units INTEGER,
                            failure_message TEXT,
                            created_at TEXT NOT NULL,
                            updated_at TEXT NOT NULL
                        )
                        """)
                    try execute("INSERT INTO schema_migrations(version, applied_at) VALUES(9, ?)", [.text(dateFormatter.string(from: Date()))])
                    try execute("COMMIT")
                } catch {
                    try? execute("ROLLBACK")
                    throw error
                }
            }
            if version < 10 {
                try execute("BEGIN IMMEDIATE")
                do {
                    try execute("ALTER TABLE research_questions ADD COLUMN parent_question_id TEXT")
                    try execute("ALTER TABLE research_questions ADD COLUMN objectives TEXT NOT NULL DEFAULT ''")
                    try execute("ALTER TABLE research_questions ADD COLUMN theoretical_interests TEXT NOT NULL DEFAULT ''")
                    try execute("ALTER TABLE research_questions ADD COLUMN conceptual_definitions TEXT NOT NULL DEFAULT ''")
                    try execute("ALTER TABLE research_questions ADD COLUMN unresolved_disagreements TEXT NOT NULL DEFAULT ''")
                    try execute("ALTER TABLE research_questions ADD COLUMN potential_hypotheses TEXT NOT NULL DEFAULT ''")
                    try execute("ALTER TABLE research_questions ADD COLUMN methodological_considerations TEXT NOT NULL DEFAULT ''")
                    try execute("""
                        CREATE TABLE question_versions (
                            id TEXT PRIMARY KEY,
                            question_id TEXT NOT NULL REFERENCES research_questions(id) ON DELETE CASCADE,
                            parent_question_id TEXT,
                            question_text TEXT NOT NULL,
                            notes TEXT NOT NULL,
                            status TEXT NOT NULL,
                            objectives TEXT NOT NULL,
                            theoretical_interests TEXT NOT NULL,
                            conceptual_definitions TEXT NOT NULL,
                            unresolved_disagreements TEXT NOT NULL,
                            potential_hypotheses TEXT NOT NULL,
                            methodological_considerations TEXT NOT NULL,
                            change_note TEXT NOT NULL,
                            created_at TEXT NOT NULL
                        )
                        """)
                    try execute("CREATE INDEX question_versions_question_idx ON question_versions(question_id,created_at)")
                    try execute("""
                        CREATE TABLE question_literature_associations (
                            question_id TEXT NOT NULL REFERENCES research_questions(id) ON DELETE CASCADE,
                            literature_id TEXT NOT NULL REFERENCES literature_items(id) ON DELETE CASCADE,
                            notes TEXT NOT NULL DEFAULT '',
                            created_at TEXT NOT NULL,
                            PRIMARY KEY(question_id,literature_id)
                        )
                        """)
                    try execute("""
                        CREATE TABLE question_concept_associations (
                            question_id TEXT NOT NULL REFERENCES research_questions(id) ON DELETE CASCADE,
                            concept_id TEXT NOT NULL REFERENCES research_concepts(id) ON DELETE CASCADE,
                            notes TEXT NOT NULL DEFAULT '',
                            created_at TEXT NOT NULL,
                            PRIMARY KEY(question_id,concept_id)
                        )
                        """)
                    try execute("""
                        CREATE TABLE research_claims (
                            id TEXT PRIMARY KEY,
                            claim_text TEXT NOT NULL,
                            category TEXT NOT NULL,
                            literature_id TEXT REFERENCES literature_items(id) ON DELETE SET NULL,
                            source_passage_id TEXT,
                            page INTEGER,
                            quoted_source_text TEXT NOT NULL DEFAULT '',
                            author_terminology TEXT NOT NULL DEFAULT '',
                            methodological_context TEXT NOT NULL DEFAULT '',
                            evidence_type TEXT NOT NULL DEFAULT '',
                            related_constructs_json TEXT NOT NULL DEFAULT '[]',
                            study_context TEXT NOT NULL DEFAULT '',
                            extraction_method TEXT NOT NULL,
                            model_identifier TEXT,
                            prompt_version TEXT,
                            verification TEXT NOT NULL,
                            user_notes TEXT NOT NULL DEFAULT '',
                            created_at TEXT NOT NULL,
                            modified_at TEXT NOT NULL
                        )
                        """)
                    try execute("CREATE INDEX research_claims_literature_idx ON research_claims(literature_id,page)")
                    try execute("""
                        CREATE TABLE claim_versions (
                            id TEXT PRIMARY KEY,
                            claim_id TEXT NOT NULL REFERENCES research_claims(id) ON DELETE CASCADE,
                            claim_text TEXT NOT NULL,
                            category TEXT NOT NULL,
                            author_terminology TEXT NOT NULL,
                            methodological_context TEXT NOT NULL,
                            evidence_type TEXT NOT NULL,
                            related_constructs_json TEXT NOT NULL,
                            study_context TEXT NOT NULL,
                            verification TEXT NOT NULL,
                            user_notes TEXT NOT NULL,
                            change_note TEXT NOT NULL,
                            created_at TEXT NOT NULL
                        )
                        """)
                    try execute("CREATE INDEX claim_versions_claim_idx ON claim_versions(claim_id,created_at)")
                    try execute("""
                        CREATE TABLE research_ideas (
                            id TEXT PRIMARY KEY,
                            project_id TEXT REFERENCES research_projects(id) ON DELETE SET NULL,
                            question_id TEXT REFERENCES research_questions(id) ON DELETE SET NULL,
                            title TEXT NOT NULL,
                            body TEXT NOT NULL DEFAULT '',
                            status TEXT NOT NULL,
                            assumptions TEXT NOT NULL DEFAULT '',
                            alternative_explanations TEXT NOT NULL DEFAULT '',
                            evidence_needed TEXT NOT NULL DEFAULT '',
                            investigation_notes TEXT NOT NULL DEFAULT '',
                            created_at TEXT NOT NULL,
                            modified_at TEXT NOT NULL
                        )
                        """)
                    try execute("""
                        CREATE TABLE idea_versions (
                            id TEXT PRIMARY KEY,
                            idea_id TEXT NOT NULL REFERENCES research_ideas(id) ON DELETE CASCADE,
                            title TEXT NOT NULL,
                            body TEXT NOT NULL,
                            status TEXT NOT NULL,
                            assumptions TEXT NOT NULL,
                            alternative_explanations TEXT NOT NULL,
                            evidence_needed TEXT NOT NULL,
                            investigation_notes TEXT NOT NULL,
                            change_note TEXT NOT NULL,
                            created_at TEXT NOT NULL
                        )
                        """)
                    try execute("CREATE INDEX idea_versions_idea_idx ON idea_versions(idea_id,created_at)")
                    try execute("""
                        CREATE TABLE idea_links (
                            id TEXT PRIMARY KEY,
                            idea_id TEXT NOT NULL REFERENCES research_ideas(id) ON DELETE CASCADE,
                            target_type TEXT NOT NULL,
                            target_id TEXT NOT NULL,
                            notes TEXT NOT NULL DEFAULT '',
                            created_at TEXT NOT NULL,
                            UNIQUE(idea_id,target_type,target_id)
                        )
                        """)
                    try execute("""
                        CREATE TABLE contradiction_cases (
                            id TEXT PRIMARY KEY,
                            question_id TEXT REFERENCES research_questions(id) ON DELETE SET NULL,
                            title TEXT NOT NULL,
                            summary TEXT NOT NULL DEFAULT '',
                            status TEXT NOT NULL,
                            resolution_notes TEXT NOT NULL DEFAULT '',
                            created_at TEXT NOT NULL,
                            modified_at TEXT NOT NULL
                        )
                        """)
                    try execute("""
                        CREATE TABLE contradiction_sources (
                            id TEXT PRIMARY KEY,
                            case_id TEXT NOT NULL REFERENCES contradiction_cases(id) ON DELETE CASCADE,
                            literature_id TEXT NOT NULL REFERENCES literature_items(id) ON DELETE CASCADE,
                            source_passage_id TEXT,
                            role TEXT NOT NULL,
                            finding TEXT NOT NULL DEFAULT '',
                            contextual_difference TEXT NOT NULL DEFAULT '',
                            verification TEXT NOT NULL,
                            created_at TEXT NOT NULL
                        )
                        """)
                    try execute("CREATE INDEX contradiction_sources_case_idx ON contradiction_sources(case_id)")
                    try execute("""
                        CREATE TABLE history_events (
                            id TEXT PRIMARY KEY,
                            entity_type TEXT NOT NULL,
                            entity_id TEXT NOT NULL,
                            event_type TEXT NOT NULL,
                            title TEXT NOT NULL,
                            detail TEXT NOT NULL DEFAULT '',
                            recorded_at TEXT NOT NULL
                        )
                        """)
                    try execute("CREATE INDEX history_events_time_idx ON history_events(recorded_at DESC)")
                    try execute("CREATE INDEX history_events_entity_idx ON history_events(entity_type,entity_id)")
                    try execute("INSERT INTO schema_migrations(version, applied_at) VALUES(10, ?)", [.text(dateFormatter.string(from: Date()))])
                    try execute("COMMIT")
                } catch {
                    try? execute("ROLLBACK")
                    throw error
                }
            }
            if version < 11 {
                try execute("BEGIN IMMEDIATE")
                do {
                    try execute("""
                        CREATE TABLE ai_provider_configuration (
                            singleton_id INTEGER PRIMARY KEY CHECK(singleton_id=1),
                            provider TEXT NOT NULL,
                            endpoint TEXT NOT NULL,
                            model TEXT NOT NULL,
                            external_transmission_enabled INTEGER NOT NULL,
                            maximum_passages INTEGER NOT NULL,
                            maximum_output_tokens INTEGER NOT NULL,
                            modified_at TEXT NOT NULL
                        )
                        """)
                    try execute("""
                        CREATE TABLE ai_analyses (
                            id TEXT PRIMARY KEY,
                            kind TEXT NOT NULL,
                            provider TEXT NOT NULL,
                            model TEXT NOT NULL,
                            prompt_version TEXT NOT NULL,
                            retrieval_set_id TEXT REFERENCES retrieval_sets(id) ON DELETE SET NULL,
                            user_query TEXT NOT NULL,
                            response_text TEXT NOT NULL DEFAULT '',
                            structured_response_json TEXT NOT NULL DEFAULT '',
                            status TEXT NOT NULL,
                            transmitted_passage_count INTEGER NOT NULL DEFAULT 0,
                            transmitted_character_count INTEGER NOT NULL DEFAULT 0,
                            input_tokens INTEGER,
                            output_tokens INTEGER,
                            error_message TEXT,
                            created_at TEXT NOT NULL,
                            completed_at TEXT
                        )
                        """)
                    try execute("CREATE INDEX ai_analyses_created_idx ON ai_analyses(created_at DESC)")
                    try execute("""
                        CREATE TABLE ai_analysis_citations (
                            id TEXT PRIMARY KEY,
                            analysis_id TEXT NOT NULL REFERENCES ai_analyses(id) ON DELETE CASCADE,
                            citation_label TEXT NOT NULL,
                            source_passage_id TEXT NOT NULL,
                            literature_id TEXT NOT NULL REFERENCES literature_items(id) ON DELETE CASCADE,
                            page INTEGER NOT NULL,
                            quoted_passage TEXT NOT NULL,
                            source_document_hash TEXT,
                            citation_status TEXT NOT NULL,
                            UNIQUE(analysis_id,citation_label)
                        )
                        """)
                    try execute("""
                        CREATE TABLE analysis_reviews (
                            id TEXT PRIMARY KEY,
                            analysis_id TEXT NOT NULL UNIQUE REFERENCES ai_analyses(id) ON DELETE CASCADE,
                            decision TEXT NOT NULL,
                            notes TEXT NOT NULL DEFAULT '',
                            reviewed_at TEXT NOT NULL
                        )
                        """)
                    try execute("INSERT INTO schema_migrations(version, applied_at) VALUES(11, ?)", [.text(dateFormatter.string(from: Date()))])
                    try execute("COMMIT")
                } catch {
                    try? execute("ROLLBACK")
                    throw error
                }
            }
            if version < 12 {
                try execute("BEGIN IMMEDIATE")
                do {
                    try execute("""
                        CREATE TABLE bias_audits (
                            id TEXT PRIMARY KEY,
                            argument_id TEXT NOT NULL REFERENCES research_arguments(id) ON DELETE CASCADE,
                            title TEXT NOT NULL,
                            scope_note TEXT NOT NULL DEFAULT '',
                            origin TEXT NOT NULL,
                            analysis_id TEXT REFERENCES ai_analyses(id) ON DELETE SET NULL,
                            created_at TEXT NOT NULL
                        )
                        """)
                    try execute("""
                        CREATE TABLE bias_concerns (
                            id TEXT PRIMARY KEY,
                            audit_id TEXT NOT NULL REFERENCES bias_audits(id) ON DELETE CASCADE,
                            kind TEXT NOT NULL,
                            potential_problem TEXT NOT NULL,
                            why_it_matters TEXT NOT NULL DEFAULT '',
                            alternative_interpretations TEXT NOT NULL DEFAULT '',
                            investigation_questions_json TEXT NOT NULL DEFAULT '[]',
                            uncertainty TEXT NOT NULL,
                            origin TEXT NOT NULL,
                            disposition TEXT NOT NULL,
                            review_notes TEXT NOT NULL DEFAULT '',
                            created_at TEXT NOT NULL,
                            modified_at TEXT NOT NULL
                        )
                        """)
                    try execute("""
                        CREATE TABLE bias_concern_evidence (
                            concern_id TEXT NOT NULL REFERENCES bias_concerns(id) ON DELETE CASCADE,
                            evidence_relationship_id TEXT NOT NULL REFERENCES evidence_relationships(id) ON DELETE CASCADE,
                            PRIMARY KEY(concern_id,evidence_relationship_id)
                        )
                        """)
                    try execute("CREATE INDEX bias_audits_argument_idx ON bias_audits(argument_id,created_at DESC)")
                    try execute("CREATE INDEX bias_concerns_audit_idx ON bias_concerns(audit_id,created_at)")
                    try execute("""
                        CREATE TABLE deliberation_sessions (
                            id TEXT PRIMARY KEY,
                            argument_id TEXT NOT NULL REFERENCES research_arguments(id) ON DELETE CASCADE,
                            title TEXT NOT NULL,
                            provider TEXT NOT NULL,
                            model TEXT NOT NULL,
                            prompt_version TEXT NOT NULL,
                            disclosure TEXT NOT NULL,
                            status TEXT NOT NULL,
                            created_at TEXT NOT NULL,
                            completed_at TEXT
                        )
                        """)
                    try execute("""
                        CREATE TABLE deliberation_messages (
                            id TEXT PRIMARY KEY,
                            session_id TEXT NOT NULL REFERENCES deliberation_sessions(id) ON DELETE CASCADE,
                            perspective TEXT NOT NULL,
                            phase TEXT NOT NULL,
                            content TEXT NOT NULL,
                            sequence INTEGER NOT NULL,
                            model_generated INTEGER NOT NULL,
                            created_at TEXT NOT NULL,
                            UNIQUE(session_id,sequence)
                        )
                        """)
                    try execute("""
                        CREATE TABLE deliberation_citations (
                            id TEXT PRIMARY KEY,
                            message_id TEXT NOT NULL REFERENCES deliberation_messages(id) ON DELETE CASCADE,
                            citation_label TEXT NOT NULL,
                            literature_id TEXT NOT NULL REFERENCES literature_items(id) ON DELETE CASCADE,
                            source_passage_id TEXT NOT NULL,
                            page INTEGER NOT NULL,
                            quoted_passage TEXT NOT NULL,
                            source_document_hash TEXT,
                            citation_status TEXT NOT NULL,
                            UNIQUE(message_id,citation_label)
                        )
                        """)
                    try execute("CREATE INDEX deliberation_sessions_argument_idx ON deliberation_sessions(argument_id,created_at DESC)")
                    try execute("CREATE INDEX deliberation_messages_session_idx ON deliberation_messages(session_id,sequence)")
                    try execute("""
                        CREATE TABLE writing_documents (
                            id TEXT PRIMARY KEY,
                            project_id TEXT REFERENCES research_projects(id) ON DELETE SET NULL,
                            question_id TEXT REFERENCES research_questions(id) ON DELETE SET NULL,
                            title TEXT NOT NULL,
                            purpose TEXT NOT NULL,
                            status TEXT NOT NULL,
                            notes TEXT NOT NULL DEFAULT '',
                            created_at TEXT NOT NULL,
                            modified_at TEXT NOT NULL
                        )
                        """)
                    try execute("""
                        CREATE TABLE writing_sections (
                            id TEXT PRIMARY KEY,
                            document_id TEXT NOT NULL REFERENCES writing_documents(id) ON DELETE CASCADE,
                            title TEXT NOT NULL,
                            body TEXT NOT NULL DEFAULT '',
                            position INTEGER NOT NULL,
                            notes TEXT NOT NULL DEFAULT '',
                            created_at TEXT NOT NULL,
                            modified_at TEXT NOT NULL,
                            UNIQUE(document_id,position)
                        )
                        """)
                    try execute("""
                        CREATE TABLE writing_evidence_links (
                            id TEXT PRIMARY KEY,
                            section_id TEXT NOT NULL REFERENCES writing_sections(id) ON DELETE CASCADE,
                            target_type TEXT NOT NULL,
                            target_id TEXT NOT NULL,
                            citation_key TEXT,
                            rationale TEXT NOT NULL DEFAULT '',
                            created_at TEXT NOT NULL,
                            UNIQUE(section_id,target_type,target_id)
                        )
                        """)
                    try execute("""
                        CREATE TABLE citation_support_reviews (
                            id TEXT PRIMARY KEY,
                            section_id TEXT NOT NULL REFERENCES writing_sections(id) ON DELETE CASCADE,
                            statement TEXT NOT NULL,
                            evidence_link_id TEXT REFERENCES writing_evidence_links(id) ON DELETE SET NULL,
                            assessment TEXT NOT NULL,
                            concern TEXT NOT NULL DEFAULT '',
                            origin TEXT NOT NULL,
                            model_identifier TEXT,
                            prompt_version TEXT,
                            review_notes TEXT NOT NULL DEFAULT '',
                            created_at TEXT NOT NULL,
                            modified_at TEXT NOT NULL
                        )
                        """)
                    try execute("CREATE INDEX writing_sections_document_idx ON writing_sections(document_id,position)")
                    try execute("CREATE INDEX writing_links_section_idx ON writing_evidence_links(section_id)")
                    try execute("CREATE INDEX citation_reviews_section_idx ON citation_support_reviews(section_id,modified_at DESC)")
                    try execute("INSERT INTO schema_migrations(version, applied_at) VALUES(12, ?)", [.text(dateFormatter.string(from: Date()))])
                    try execute("COMMIT")
                } catch {
                    try? execute("ROLLBACK")
                    throw error
                }
            }
            if version < 13 {
                try execute("BEGIN IMMEDIATE")
                do {
                    try execute("""
                        CREATE TABLE collective_experiments (
                            id TEXT PRIMARY KEY,
                            title TEXT NOT NULL,
                            research_purpose TEXT NOT NULL DEFAULT '',
                            task_instructions TEXT NOT NULL DEFAULT '',
                            interaction_mode TEXT NOT NULL,
                            provider TEXT NOT NULL,
                            model TEXT NOT NULL,
                            model_settings_json TEXT NOT NULL DEFAULT '{}',
                            prompt_version TEXT NOT NULL,
                            status TEXT NOT NULL,
                            validation_note TEXT NOT NULL,
                            created_at TEXT NOT NULL,
                            completed_at TEXT
                        )
                        """)
                    try execute("""
                        CREATE TABLE collective_agents (
                            id TEXT PRIMARY KEY,
                            experiment_id TEXT NOT NULL REFERENCES collective_experiments(id) ON DELETE CASCADE,
                            label TEXT NOT NULL,
                            role TEXT NOT NULL DEFAULT '',
                            information_available TEXT NOT NULL DEFAULT '',
                            position INTEGER NOT NULL,
                            created_at TEXT NOT NULL,
                            UNIQUE(experiment_id,position)
                        )
                        """)
                    try execute("""
                        CREATE TABLE collective_turns (
                            id TEXT PRIMARY KEY,
                            experiment_id TEXT NOT NULL REFERENCES collective_experiments(id) ON DELETE CASCADE,
                            agent_id TEXT REFERENCES collective_agents(id) ON DELETE SET NULL,
                            round_number INTEGER NOT NULL,
                            sequence INTEGER NOT NULL,
                            kind TEXT NOT NULL,
                            information_available TEXT NOT NULL DEFAULT '',
                            prompt_text TEXT NOT NULL DEFAULT '',
                            response_text TEXT NOT NULL,
                            confidence REAL,
                            model_generated INTEGER NOT NULL,
                            error_message TEXT,
                            created_at TEXT NOT NULL,
                            UNIQUE(experiment_id,sequence)
                        )
                        """)
                    try execute("""
                        CREATE TABLE collective_turn_citations (
                            id TEXT PRIMARY KEY,
                            turn_id TEXT NOT NULL REFERENCES collective_turns(id) ON DELETE CASCADE,
                            citation_label TEXT NOT NULL,
                            literature_id TEXT NOT NULL REFERENCES literature_items(id) ON DELETE CASCADE,
                            source_passage_id TEXT NOT NULL,
                            page INTEGER NOT NULL,
                            quoted_passage TEXT NOT NULL,
                            source_document_hash TEXT,
                            citation_status TEXT NOT NULL,
                            UNIQUE(turn_id,citation_label)
                        )
                        """)
                    try execute("CREATE INDEX collective_agents_experiment_idx ON collective_agents(experiment_id,position)")
                    try execute("CREATE INDEX collective_turns_experiment_idx ON collective_turns(experiment_id,sequence)")
                    try execute("INSERT INTO schema_migrations(version, applied_at) VALUES(13, ?)", [.text(dateFormatter.string(from: Date()))])
                    try execute("COMMIT")
                } catch {
                    try? execute("ROLLBACK")
                    throw error
                }
            }
            if version < 14 {
                try execute("BEGIN IMMEDIATE")
                do {
                    try execute("ALTER TABLE ai_analyses ADD COLUMN target_type TEXT")
                    try execute("ALTER TABLE ai_analyses ADD COLUMN target_id TEXT")
                    try execute("CREATE INDEX ai_analyses_target_idx ON ai_analyses(target_type,target_id,created_at DESC)")
                    try execute("INSERT INTO schema_migrations(version, applied_at) VALUES(14, ?)", [.text(dateFormatter.string(from: Date()))])
                    try execute("COMMIT")
                } catch {
                    try? execute("ROLLBACK")
                    throw error
                }
            }
            if version < 15 {
                try execute("BEGIN IMMEDIATE")
                do {
                    try execute("""
                        CREATE TABLE retrieval_set_note_snippets (
                            retrieval_set_id TEXT NOT NULL REFERENCES retrieval_sets(id) ON DELETE CASCADE,
                            note_id TEXT NOT NULL,
                            note_path TEXT NOT NULL,
                            note_title TEXT NOT NULL,
                            snippet_text TEXT NOT NULL,
                            source_modified_at TEXT NOT NULL,
                            relevance_rank REAL NOT NULL,
                            added_at TEXT NOT NULL,
                            PRIMARY KEY(retrieval_set_id,note_id)
                        )
                        """)
                    try execute("CREATE INDEX retrieval_note_snippets_note_idx ON retrieval_set_note_snippets(note_id)")
                    try execute("""
                        CREATE TABLE ai_analysis_note_citations (
                            id TEXT PRIMARY KEY,
                            analysis_id TEXT NOT NULL REFERENCES ai_analyses(id) ON DELETE CASCADE,
                            citation_label TEXT NOT NULL,
                            note_id TEXT NOT NULL,
                            note_path TEXT NOT NULL,
                            note_title TEXT NOT NULL,
                            quoted_snippet TEXT NOT NULL,
                            source_modified_at TEXT NOT NULL,
                            citation_status TEXT NOT NULL,
                            UNIQUE(analysis_id,citation_label)
                        )
                        """)
                    try execute("CREATE INDEX ai_note_citations_note_idx ON ai_analysis_note_citations(note_id)")
                    try execute("INSERT INTO schema_migrations(version, applied_at) VALUES(15, ?)", [.text(dateFormatter.string(from: Date()))])
                    try execute("COMMIT")
                } catch {
                    try? execute("ROLLBACK")
                    throw error
                }
            }
            if version < 16 {
                try execute("BEGIN IMMEDIATE")
                do {
                    try execute("ALTER TABLE ai_provider_configuration ADD COLUMN reasoning_effort TEXT NOT NULL DEFAULT 'medium'")
                    try execute("ALTER TABLE ai_provider_configuration ADD COLUMN local_runtime_idle_minutes INTEGER NOT NULL DEFAULT 10")
                    try execute("INSERT INTO schema_migrations(version, applied_at) VALUES(16, ?)", [.text(dateFormatter.string(from: Date()))])
                    try execute("COMMIT")
                } catch {
                    try? execute("ROLLBACK")
                    throw error
                }
            }
        }
    }

    public func upsertLiterature(_ item: LiteratureItem) throws {
        try synchronized {
            var record = item
            if record.source == .zotero, record.zoteroKey != nil, record.zoteroLibraryID == nil {
                record.zoteroLibraryID = "user:0"
            }
            let existingID: UUID? = if let key = record.zoteroKey {
                if let serverID = record.zoteroServerID, let libraryID = record.zoteroLibraryID {
                    try query(
                        "SELECT id FROM literature_items WHERE zotero_key=? AND zotero_server_id=? AND zotero_library_id=?",
                        [.text(key), .text(serverID), .text(libraryID)]
                    ) { UUID(uuidString: $0.text(0)) }.first ?? nil
                } else if let serverID = record.zoteroServerID {
                    try query(
                        "SELECT id FROM literature_items WHERE zotero_key=? AND zotero_server_id=? AND zotero_library_id IS NULL",
                        [.text(key), .text(serverID)]
                    ) { UUID(uuidString: $0.text(0)) }.first ?? nil
                } else {
                    try query(
                        "SELECT id FROM literature_items WHERE zotero_key=? AND zotero_server_id IS NULL",
                        [.text(key)]
                    ) { UUID(uuidString: $0.text(0)) }.first ?? nil
                }
            } else {
                nil
            }
            if let existingID { record.id = existingID }
            let now = dateFormatter.string(from: Date())
            try execute("""
                INSERT INTO literature_items(
                    id, zotero_key, zotero_attachment_key, zotero_server_id, zotero_library_id, zotero_version,
                    title, authors, publication_year, abstract_text, doi, citation_key, tags_json,
                    item_type, source, source_availability, pdf_path, pdf_byte_count, pdf_sha256,
                    pdf_last_verified_at, external_url, created_at, modified_at
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    zotero_key=excluded.zotero_key,
                    zotero_attachment_key=COALESCE(excluded.zotero_attachment_key, literature_items.zotero_attachment_key),
                    zotero_server_id=excluded.zotero_server_id,
                    zotero_library_id=excluded.zotero_library_id,
                    zotero_version=excluded.zotero_version,
                    title=excluded.title,
                    authors=excluded.authors,
                    publication_year=excluded.publication_year,
                    abstract_text=excluded.abstract_text,
                    doi=excluded.doi,
                    citation_key=excluded.citation_key,
                    tags_json=excluded.tags_json,
                    item_type=excluded.item_type,
                    source=excluded.source,
                    source_availability=excluded.source_availability,
                    pdf_path=COALESCE(excluded.pdf_path, literature_items.pdf_path),
                    pdf_byte_count=COALESCE(excluded.pdf_byte_count, literature_items.pdf_byte_count),
                    pdf_sha256=COALESCE(excluded.pdf_sha256, literature_items.pdf_sha256),
                    pdf_last_verified_at=COALESCE(excluded.pdf_last_verified_at, literature_items.pdf_last_verified_at),
                    external_url=COALESCE(excluded.external_url, literature_items.external_url),
                    modified_at=excluded.modified_at
                """, [
                    .text(record.id.uuidString), optionalText(record.zoteroKey), optionalText(record.zoteroAttachmentKey),
                    optionalText(record.zoteroServerID), optionalText(record.zoteroLibraryID), optionalInt(record.zoteroVersion), .text(record.title),
                    .text(record.authors), optionalInt(record.year), .text(record.abstract), optionalText(record.doi),
                    optionalText(record.citationKey), .text(json(record.tags)), .text(record.itemType), .text(record.source.rawValue),
                    .text(record.sourceAvailability.rawValue), optionalText(record.pdfPath), optionalInt64(record.pdfByteCount),
                    optionalText(record.pdfContentHash), optionalText(record.pdfLastVerifiedAt.map { dateFormatter.string(from: $0) }),
                    optionalText(record.externalURL), .text(now), .text(dateFormatter.string(from: record.modifiedAt))
                ])
            try replaceSearchIndex(
                entityID: record.id.uuidString,
                type: "literature",
                title: record.title,
                body: [record.authors, record.abstract, record.doi ?? "", record.citationKey ?? "", record.tags.joined(separator: " ")].joined(separator: "\n")
            )
        }
    }

    /// Stores one paper and its extracted pages as a single durable unit. Folder refreshes
    /// intentionally commit one PDF at a time so cancellation retains completed work, while
    /// a failure cannot leave updated metadata paired with an older page index.
    public func upsertLiterature(_ item: LiteratureItem, indexingPDFPages pages: [String]) throws {
        try synchronized {
            try execute("BEGIN IMMEDIATE")
            do {
                try upsertLiterature(item)
                try replacePDFPageIndex(literatureID: item.id, pages: pages)
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    public func literatureItems(matching queryText: String = "") throws -> [LiteratureItem] {
        try synchronized {
            let wildcard = "%\(queryText)%"
            let sql: String
            let values: [SQLValue]
            if queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sql = """
                    SELECT i.id,i.zotero_key,i.zotero_attachment_key,i.zotero_server_id,i.zotero_library_id,
                           l.name,i.zotero_version,i.title,i.authors,i.publication_year,i.abstract_text,i.doi,
                           i.citation_key,i.tags_json,i.item_type,i.source,i.source_availability,i.pdf_path,
                           i.pdf_byte_count,i.pdf_sha256,i.pdf_last_verified_at,i.external_url,i.modified_at
                    FROM literature_items i
                    LEFT JOIN zotero_libraries l ON l.server_id=i.zotero_server_id AND l.library_id=i.zotero_library_id
                    ORDER BY i.title COLLATE NOCASE
                    """
                values = []
            } else {
                sql = """
                    SELECT i.id,i.zotero_key,i.zotero_attachment_key,i.zotero_server_id,i.zotero_library_id,
                           l.name,i.zotero_version,i.title,i.authors,i.publication_year,i.abstract_text,i.doi,
                           i.citation_key,i.tags_json,i.item_type,i.source,i.source_availability,i.pdf_path,
                           i.pdf_byte_count,i.pdf_sha256,i.pdf_last_verified_at,i.external_url,i.modified_at
                    FROM literature_items i
                    LEFT JOIN zotero_libraries l ON l.server_id=i.zotero_server_id AND l.library_id=i.zotero_library_id
                    WHERE i.title LIKE ? OR i.authors LIKE ? OR i.abstract_text LIKE ? OR i.doi LIKE ? OR i.citation_key LIKE ? OR i.tags_json LIKE ?
                    ORDER BY i.title COLLATE NOCASE
                    """
                values = [.text(wildcard), .text(wildcard), .text(wildcard), .text(wildcard), .text(wildcard), .text(wildcard)]
            }
            return try query(sql, values) { row in
                LiteratureItem(
                    id: try row.uuid(0),
                    zoteroKey: row.optionalText(1),
                    zoteroAttachmentKey: row.optionalText(2),
                    zoteroServerID: row.optionalText(3),
                    zoteroLibraryID: row.optionalText(4),
                    zoteroLibraryName: row.optionalText(5),
                    zoteroVersion: row.optionalInt(6),
                    title: row.text(7),
                    authors: row.text(8),
                    year: row.optionalInt(9),
                    abstract: row.text(10),
                    doi: row.optionalText(11),
                    citationKey: row.optionalText(12),
                    tags: self.stringArray(row.text(13)),
                    itemType: row.text(14),
                    source: SourceKind(rawValue: row.text(15)) ?? .manual,
                    pdfPath: row.optionalText(17),
                    pdfByteCount: row.optionalInt64(18),
                    pdfContentHash: row.optionalText(19),
                    pdfLastVerifiedAt: row.optionalText(20).map(self.date),
                    externalURL: row.optionalText(21),
                    sourceAvailability: SourceAvailability(rawValue: row.text(16)) ?? .available,
                    modifiedAt: self.date(row.text(22))
                )
            }
        }
    }

    public func zoteroCheckpoint() throws -> ZoteroCheckpoint? {
        try synchronized {
            try query("""
                SELECT server_id,library_version FROM zotero_libraries
                WHERE library_id='user:0' AND library_version IS NOT NULL AND availability=?
                ORDER BY last_synced_at DESC LIMIT 1
                """, [.text(ZoteroLibraryAvailability.available.rawValue)]) { row in
                    ZoteroCheckpoint(serverID: row.text(0), libraryVersion: row.int(1))
                }.first
        }
    }

    public func zoteroCheckpoints() throws -> [ZoteroLibraryCheckpoint] {
        try synchronized {
            try query("""
                SELECT server_id,library_id,library_version FROM zotero_libraries
                WHERE library_version IS NOT NULL AND availability=?
                """, [.text(ZoteroLibraryAvailability.available.rawValue)]) { row in
                    ZoteroLibraryCheckpoint(serverID: row.text(0), libraryID: row.text(1), libraryVersion: row.int(2))
                }
        }
    }

    public func zoteroLibraries() throws -> [ZoteroLibrary] {
        try synchronized {
            try query("""
                SELECT server_id,library_id,kind,name,metadata_version,library_version,availability,last_synced_at
                FROM zotero_libraries
                ORDER BY availability<>?, kind, name COLLATE NOCASE
                """, [.text(ZoteroLibraryAvailability.available.rawValue)]) { row in
                    ZoteroLibrary(
                        serverID: row.text(0),
                        libraryID: row.text(1),
                        kind: ZoteroLibraryKind(rawValue: row.text(2)) ?? .user,
                        name: row.text(3),
                        metadataVersion: row.optionalInt(4),
                        libraryVersion: row.optionalInt(5),
                        availability: ZoteroLibraryAvailability(rawValue: row.text(6)) ?? .unavailable,
                        lastSyncedAt: row.optionalText(7).map(self.date)
                    )
                }
        }
    }

    public func zoteroCollections() throws -> [ZoteroCollection] {
        try synchronized {
            try query("""
                SELECT server_id,library_id,collection_key,name,parent_collection_key,zotero_version
                FROM zotero_collections ORDER BY name COLLATE NOCASE
                """) { row in
                    ZoteroCollection(
                        serverID: row.text(0), libraryID: row.text(1), key: row.text(2), name: row.text(3),
                        parentKey: row.optionalText(4), version: row.optionalInt(5)
                    )
                }
        }
    }

    public func literatureCollectionMemberships() throws -> [LiteratureCollectionMembership] {
        try synchronized {
            try query("""
                SELECT literature_id,server_id,library_id,collection_key
                FROM literature_collection_memberships
                """) { row in
                    LiteratureCollectionMembership(
                        literatureID: try row.uuid(0),
                        collectionID: "\(row.text(1))|\(row.text(2))|\(row.text(3))"
                    )
                }
        }
    }

    public func applyZoteroSync(_ snapshot: ZoteroSnapshot) throws {
        guard let serverID = snapshot.serverID else {
            throw DatabaseError.invalidData("Zotero did not provide a server identity for this refresh.")
        }
        try applyZoteroRefresh(ZoteroRefresh(
            serverID: serverID,
            snapshots: [snapshot],
            accessibleLibraryIDs: [snapshot.libraryID]
        ))
    }

    public func applyZoteroRefresh(_ refresh: ZoteroRefresh) throws {
        try synchronized {
            try execute("BEGIN IMMEDIATE")
            do {
                try execute("""
                    UPDATE zotero_libraries SET availability=?
                    WHERE server_id<>?
                    """, [.text(ZoteroLibraryAvailability.differentServer.rawValue), .text(refresh.serverID)])
                try execute("""
                    UPDATE literature_items SET source_availability=?
                    WHERE source=? AND zotero_server_id IS NOT NULL AND zotero_server_id<>?
                    """, [
                        .text(SourceAvailability.differentLibrary.rawValue),
                        .text(SourceKind.zotero.rawValue),
                        .text(refresh.serverID)
                    ])

                let storedLibraryIDs = try query(
                    "SELECT library_id FROM zotero_libraries WHERE server_id=?",
                    [.text(refresh.serverID)]
                ) { $0.text(0) }
                for libraryID in storedLibraryIDs where !refresh.accessibleLibraryIDs.contains(libraryID) {
                    try execute("""
                        UPDATE zotero_libraries SET availability=? WHERE server_id=? AND library_id=?
                        """, [
                            .text(ZoteroLibraryAvailability.unavailable.rawValue),
                            .text(refresh.serverID), .text(libraryID)
                        ])
                    try execute("""
                        UPDATE literature_items
                        SET source_availability=?
                        WHERE source=? AND zotero_server_id=? AND zotero_library_id=?
                        """, [
                            .text(SourceAvailability.libraryUnavailable.rawValue),
                            .text(SourceKind.zotero.rawValue), .text(refresh.serverID), .text(libraryID)
                        ])
                }

                for snapshot in refresh.snapshots {
                    guard snapshot.serverID == refresh.serverID else {
                        throw DatabaseError.invalidData("A Zotero refresh mixed records from different server identities.")
                    }
                    try applyZoteroSnapshot(snapshot)
                }
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    /// Applies one exact-key local-API response without advancing a library checkpoint or
    /// changing the availability of any other Zotero library or item.
    public func applyZoteroItemRefresh(_ refresh: ZoteroItemRefresh) throws {
        guard let serverID = refresh.item.zoteroServerID,
              let libraryID = refresh.item.zoteroLibraryID,
              let itemKey = refresh.item.zoteroKey,
              serverID == refresh.connection.serverID else {
            throw DatabaseError.invalidData("The exact Zotero item response did not match its recorded server and library identity.")
        }
        try synchronized {
            try execute("BEGIN IMMEDIATE")
            do {
                try upsertLiterature(refresh.item)
                let refreshedIDs: [String] = try query("""
                    SELECT id FROM literature_items
                    WHERE zotero_server_id=? AND zotero_library_id=? AND zotero_key=?
                    """, [.text(serverID), .text(libraryID), .text(itemKey)]) { $0.text(0) }
                guard let literatureID = refreshedIDs.first else {
                    throw DatabaseError.invalidData("The refreshed Zotero item could not be read back by its exact identity.")
                }
                try execute(
                    "DELETE FROM literature_collection_memberships WHERE literature_id=?",
                    [.text(literatureID)]
                )
                for collectionKey in refresh.collectionKeys {
                    let exists = try query("""
                        SELECT COUNT(*) FROM zotero_collections
                        WHERE server_id=? AND library_id=? AND collection_key=?
                        """, [.text(serverID), .text(libraryID), .text(collectionKey)]) { $0.int(0) }.first ?? 0
                    if exists == 1 {
                        try execute("""
                            INSERT INTO literature_collection_memberships(literature_id,server_id,library_id,collection_key)
                            VALUES(?,?,?,?)
                            """, [.text(literatureID), .text(serverID), .text(libraryID), .text(collectionKey)])
                    }
                }
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    private func applyZoteroSnapshot(_ snapshot: ZoteroSnapshot) throws {
        guard let serverID = snapshot.serverID else {
            throw DatabaseError.invalidData("Zotero did not provide a server identity for this library.")
        }
        let syncedAt = dateFormatter.string(from: Date())
        try execute("""
            INSERT INTO zotero_libraries(
                server_id,library_id,kind,name,metadata_version,library_version,availability,last_synced_at
            ) VALUES(?,?,?,?,?,?,?,?)
            ON CONFLICT(server_id,library_id) DO UPDATE SET
                kind=excluded.kind,name=excluded.name,metadata_version=excluded.metadata_version,
                library_version=excluded.library_version,availability=excluded.availability,last_synced_at=excluded.last_synced_at
            """, [
                .text(serverID), .text(snapshot.libraryID), .text(snapshot.libraryKind.rawValue), .text(snapshot.libraryName),
                optionalInt(snapshot.libraryMetadataVersion), optionalInt(snapshot.libraryVersion),
                .text(ZoteroLibraryAvailability.available.rawValue), .text(syncedAt)
            ])

        for collection in snapshot.collections {
            guard collection.serverID == serverID, collection.libraryID == snapshot.libraryID else {
                throw DatabaseError.invalidData("A Zotero collection was associated with the wrong library.")
            }
            try execute("""
                INSERT INTO zotero_collections(server_id,library_id,collection_key,name,parent_collection_key,zotero_version)
                VALUES(?,?,?,?,?,?)
                ON CONFLICT(server_id,library_id,collection_key) DO UPDATE SET
                    name=excluded.name,parent_collection_key=excluded.parent_collection_key,zotero_version=excluded.zotero_version
                """, [
                    .text(serverID), .text(snapshot.libraryID), .text(collection.key), .text(collection.name),
                    optionalText(collection.parentKey), optionalInt(collection.version)
                ])
        }

        for key in snapshot.deletedCollectionKeys {
            try execute(
                "DELETE FROM zotero_collections WHERE server_id=? AND library_id=? AND collection_key=?",
                [.text(serverID), .text(snapshot.libraryID), .text(key)]
            )
        }
        if snapshot.mode == .full {
            let receivedCollectionKeys = Set(snapshot.collections.map(\.key))
            let storedCollectionKeys = try query(
                "SELECT collection_key FROM zotero_collections WHERE server_id=? AND library_id=?",
                [.text(serverID), .text(snapshot.libraryID)]
            ) { $0.text(0) }
            for key in storedCollectionKeys where !receivedCollectionKeys.contains(key) {
                try execute(
                    "DELETE FROM zotero_collections WHERE server_id=? AND library_id=? AND collection_key=?",
                    [.text(serverID), .text(snapshot.libraryID), .text(key)]
                )
            }
        }

        for incoming in snapshot.items {
            var item = incoming
            item.zoteroServerID = serverID
            item.zoteroLibraryID = snapshot.libraryID
            item.zoteroLibraryName = snapshot.libraryName
            item.sourceAvailability = .available
            try upsertLiterature(item)
            guard let itemKey = item.zoteroKey else { continue }

            let literatureID = try query("""
                SELECT id FROM literature_items
                WHERE zotero_server_id=? AND zotero_library_id=? AND zotero_key=?
                """, [.text(serverID), .text(snapshot.libraryID), .text(itemKey)]) { $0.text(0) }.first
            guard let literatureID else {
                throw DatabaseError.invalidData("A synced Zotero item could not be read back from the database.")
            }
            try execute(
                "DELETE FROM literature_collection_memberships WHERE literature_id=?",
                [.text(literatureID)]
            )
            for collectionKey in snapshot.itemCollectionKeys[itemKey] ?? [] {
                try execute("""
                    INSERT INTO literature_collection_memberships(literature_id,server_id,library_id,collection_key)
                    VALUES(?,?,?,?)
                    """, [.text(literatureID), .text(serverID), .text(snapshot.libraryID), .text(collectionKey)])
            }

            if snapshot.mode == .full, item.zoteroAttachmentKey == nil {
                try execute("""
                    UPDATE literature_items SET zotero_attachment_key=NULL,pdf_path=NULL,
                        pdf_byte_count=NULL,pdf_sha256=NULL,pdf_last_verified_at=NULL
                    WHERE zotero_server_id=? AND zotero_library_id=? AND zotero_key=?
                    """, [.text(serverID), .text(snapshot.libraryID), .text(itemKey)])
            }
        }

        for key in snapshot.deletedItemKeys {
            try execute("""
                UPDATE literature_items SET source_availability=?
                WHERE zotero_server_id=? AND zotero_library_id=? AND zotero_key=?
                """, [
                    .text(SourceAvailability.deletedInSource.rawValue),
                    .text(serverID), .text(snapshot.libraryID), .text(key)
                ])
            try execute("""
                DELETE FROM literature_collection_memberships
                WHERE literature_id IN (
                    SELECT id FROM literature_items
                    WHERE zotero_server_id=? AND zotero_library_id=? AND zotero_key=?
                )
                """, [.text(serverID), .text(snapshot.libraryID), .text(key)])
            try execute("""
                UPDATE literature_items SET zotero_attachment_key=NULL,pdf_path=NULL,
                    pdf_byte_count=NULL,pdf_sha256=NULL,pdf_last_verified_at=NULL
                WHERE zotero_server_id=? AND zotero_library_id=? AND zotero_attachment_key=?
                """, [.text(serverID), .text(snapshot.libraryID), .text(key)])
        }

        if snapshot.mode == .full {
            let receivedKeys = Set(snapshot.items.compactMap(\.zoteroKey))
            let storedKeys = try query("""
                SELECT zotero_key FROM literature_items
                WHERE source=? AND zotero_server_id=? AND zotero_library_id=? AND zotero_key IS NOT NULL
                """, [.text(SourceKind.zotero.rawValue), .text(serverID), .text(snapshot.libraryID)]) { $0.text(0) }
            for key in storedKeys where !receivedKeys.contains(key) {
                try execute("""
                    UPDATE literature_items SET source_availability=?
                    WHERE zotero_server_id=? AND zotero_library_id=? AND zotero_key=?
                    """, [
                        .text(SourceAvailability.deletedInSource.rawValue),
                        .text(serverID), .text(snapshot.libraryID), .text(key)
                    ])
                try execute("""
                    DELETE FROM literature_collection_memberships
                    WHERE literature_id IN (
                        SELECT id FROM literature_items
                        WHERE zotero_server_id=? AND zotero_library_id=? AND zotero_key=?
                    )
                    """, [.text(serverID), .text(snapshot.libraryID), .text(key)])
            }
        }

        if snapshot.libraryID == "user:0", let libraryVersion = snapshot.libraryVersion {
            let checkpoint = ZoteroCheckpoint(serverID: serverID, libraryVersion: libraryVersion)
            let data = try JSONEncoder().encode(checkpoint)
            guard let value = String(data: data, encoding: .utf8) else {
                throw DatabaseError.invalidData("Could not encode the Zotero checkpoint.")
            }
            try execute("""
                INSERT INTO integration_state(key,value,updated_at) VALUES('zotero_checkpoint',?,?)
                ON CONFLICT(key) DO UPDATE SET value=excluded.value,updated_at=excluded.updated_at
                """, [.text(value), .text(syncedAt)])
        }
    }

    public func upsertObsidianNote(_ note: ObsidianNote) throws {
        try synchronized {
            let existingID = try query("SELECT id FROM obsidian_notes WHERE path = ?", [.text(note.path)]) { row in
                UUID(uuidString: row.text(0))
            }.first ?? nil
            var record = note
            if let existingID { record.id = existingID }
            try execute("""
                INSERT INTO obsidian_notes(id,path,title,content,tags_json,wikilinks_json,citation_keys_json,dois_json,modified_at)
                VALUES(?,?,?,?,?,?,?,?,?)
                ON CONFLICT(path) DO UPDATE SET
                    title=excluded.title,
                    content=excluded.content,
                    tags_json=excluded.tags_json,
                    wikilinks_json=excluded.wikilinks_json,
                    citation_keys_json=excluded.citation_keys_json,
                    dois_json=excluded.dois_json,
                    modified_at=excluded.modified_at
                """, [
                    .text(record.id.uuidString), .text(record.path), .text(record.title), .text(record.content),
                    .text(json(record.tags)), .text(json(record.wikilinks)), .text(json(record.citationKeys)),
                    .text(json(record.dois)), .text(dateFormatter.string(from: record.modifiedAt))
                ])
            try replaceSearchIndex(entityID: record.id.uuidString, type: "note", title: record.title, body: record.content)
        }
    }

    public func obsidianNotes() throws -> [ObsidianNote] {
        try synchronized {
            try query("SELECT id,path,title,content,tags_json,wikilinks_json,citation_keys_json,dois_json,modified_at FROM obsidian_notes ORDER BY title COLLATE NOCASE") { row in
                ObsidianNote(
                    id: try row.uuid(0), path: row.text(1), title: row.text(2), content: row.text(3),
                    tags: self.stringArray(row.text(4)), wikilinks: self.stringArray(row.text(5)),
                    citationKeys: self.stringArray(row.text(6)), dois: self.stringArray(row.text(7)),
                    modifiedAt: self.date(row.text(8))
                )
            }
        }
    }

    public func saveNoteLinkSuggestion(_ link: PaperNoteLink) throws {
        try synchronized {
            try execute("""
                INSERT INTO note_links(id,note_id,literature_id,match_method,matched_identifier,review_state,created_at,modified_at)
                VALUES(?,?,?,?,?,?,?,?)
                ON CONFLICT(note_id,literature_id) DO NOTHING
                """, [.text(link.id.uuidString), .text(link.noteID.uuidString), .text(link.literatureID.uuidString),
                       .text(link.method.rawValue), .text(link.matchedIdentifier), .text(link.state.rawValue),
                       .text(dateFormatter.string(from: link.createdAt)), .text(dateFormatter.string(from: link.modifiedAt))])
        }
    }

    public func saveNoteLink(_ link: PaperNoteLink) throws {
        try synchronized {
            try execute("""
                INSERT INTO note_links(id,note_id,literature_id,match_method,matched_identifier,review_state,created_at,modified_at)
                VALUES(?,?,?,?,?,?,?,?)
                ON CONFLICT(note_id,literature_id) DO UPDATE SET
                    match_method=excluded.match_method,
                    matched_identifier=excluded.matched_identifier,
                    review_state=excluded.review_state,
                    modified_at=excluded.modified_at
                """, [.text(link.id.uuidString), .text(link.noteID.uuidString), .text(link.literatureID.uuidString),
                       .text(link.method.rawValue), .text(link.matchedIdentifier), .text(link.state.rawValue),
                       .text(dateFormatter.string(from: link.createdAt)), .text(dateFormatter.string(from: link.modifiedAt))])
        }
    }

    public func noteLinks(literatureID: UUID? = nil) throws -> [PaperNoteLink] {
        try synchronized {
            let sql = literatureID == nil
                ? "SELECT id,note_id,literature_id,match_method,matched_identifier,review_state,created_at,modified_at FROM note_links ORDER BY modified_at DESC"
                : "SELECT id,note_id,literature_id,match_method,matched_identifier,review_state,created_at,modified_at FROM note_links WHERE literature_id=? ORDER BY modified_at DESC"
            let values: [SQLValue] = literatureID.map { [.text($0.uuidString)] } ?? []
            return try query(sql, values) { row in
                PaperNoteLink(
                    id: try row.uuid(0), noteID: try row.uuid(1), literatureID: try row.uuid(2),
                    method: NoteMatchMethod(rawValue: row.text(3)) ?? .manual,
                    matchedIdentifier: row.text(4), state: LinkReviewState(rawValue: row.text(5)) ?? .suggested,
                    createdAt: self.date(row.text(6)), modifiedAt: self.date(row.text(7))
                )
            }
        }
    }

    public func deleteNoteLink(id: UUID) throws {
        try synchronized {
            try execute("DELETE FROM note_links WHERE id=?", [.text(id.uuidString)])
        }
    }

    public func saveProject(_ project: ResearchProject) throws {
        try synchronized {
            let existed = (try query("SELECT COUNT(*) FROM research_projects WHERE id=?", [.text(project.id.uuidString)]) { $0.int(0) }.first ?? 0) == 1
            try execute("""
                INSERT INTO research_projects(id,title,summary,created_at,modified_at) VALUES(?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET title=excluded.title,summary=excluded.summary,modified_at=excluded.modified_at
                """, [.text(project.id.uuidString), .text(project.title), .text(project.summary),
                       .text(dateFormatter.string(from: project.createdAt)), .text(dateFormatter.string(from: project.modifiedAt))])
            try replaceSearchIndex(entityID: project.id.uuidString, type: "project", title: project.title, body: project.summary)
            try insertHistoryEvent(HistoryEvent(
                entityType: "project", entityID: project.id.uuidString,
                eventType: existed ? "updated" : "created", title: project.title, detail: project.summary,
                recordedAt: project.modifiedAt
            ))
        }
    }

    public func projects() throws -> [ResearchProject] {
        try synchronized {
            try query("SELECT id,title,summary,created_at,modified_at FROM research_projects ORDER BY modified_at DESC") { row in
                ResearchProject(id: try row.uuid(0), title: row.text(1), summary: row.text(2), createdAt: self.date(row.text(3)), modifiedAt: self.date(row.text(4)))
            }
        }
    }

    public func saveQuestion(_ question: ResearchQuestion, changeNote: String? = nil) throws {
        try synchronized {
            let existing = try questionRecord(id: question.id)
            let changed = existing.map { $0 != question } ?? true
            guard changed else { return }
            try execute("BEGIN IMMEDIATE")
            do {
                if let existing {
                    let count = try query("SELECT COUNT(*) FROM question_versions WHERE question_id=?", [.text(question.id.uuidString)]) { $0.int(0) }.first ?? 0
                    if count == 0 { try insertQuestionVersion(version(from: existing, changeNote: "Baseline captured before first tracked edit")) }
                }
                try execute("""
                    INSERT INTO research_questions(
                        id,project_id,parent_question_id,question,notes,status,objectives,theoretical_interests,
                        conceptual_definitions,unresolved_disagreements,potential_hypotheses,
                        methodological_considerations,created_at,modified_at
                    ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET project_id=excluded.project_id,parent_question_id=excluded.parent_question_id,
                        question=excluded.question,notes=excluded.notes,status=excluded.status,objectives=excluded.objectives,
                        theoretical_interests=excluded.theoretical_interests,conceptual_definitions=excluded.conceptual_definitions,
                        unresolved_disagreements=excluded.unresolved_disagreements,potential_hypotheses=excluded.potential_hypotheses,
                        methodological_considerations=excluded.methodological_considerations,modified_at=excluded.modified_at
                    """, [
                        .text(question.id.uuidString), .text(question.projectID.uuidString), optionalText(question.parentQuestionID?.uuidString),
                        .text(question.question), .text(question.notes), .text(question.status), .text(question.objectives),
                        .text(question.theoreticalInterests), .text(question.conceptualDefinitions),
                        .text(question.unresolvedDisagreements), .text(question.potentialHypotheses),
                        .text(question.methodologicalConsiderations), .text(dateFormatter.string(from: question.createdAt)),
                        .text(dateFormatter.string(from: question.modifiedAt))
                    ])
                let note = changeNote?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? (existing == nil ? "Created" : "Updated")
                try insertQuestionVersion(version(from: question, changeNote: note))
                try replaceSearchIndex(
                    entityID: question.id.uuidString, type: "question", title: question.question,
                    body: [question.notes, question.objectives, question.theoreticalInterests, question.conceptualDefinitions,
                           question.unresolvedDisagreements, question.potentialHypotheses, question.methodologicalConsiderations].joined(separator: "\n")
                )
                try insertHistoryEvent(HistoryEvent(
                    entityType: "question", entityID: question.id.uuidString,
                    eventType: existing == nil ? "created" : "revised", title: question.question, detail: note,
                    recordedAt: question.modifiedAt
                ))
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    public func questions(projectID: UUID? = nil) throws -> [ResearchQuestion] {
        try synchronized {
            let sql = projectID == nil
                ? "SELECT id,project_id,parent_question_id,question,notes,status,objectives,theoretical_interests,conceptual_definitions,unresolved_disagreements,potential_hypotheses,methodological_considerations,created_at,modified_at FROM research_questions ORDER BY modified_at DESC"
                : "SELECT id,project_id,parent_question_id,question,notes,status,objectives,theoretical_interests,conceptual_definitions,unresolved_disagreements,potential_hypotheses,methodological_considerations,created_at,modified_at FROM research_questions WHERE project_id=? ORDER BY modified_at DESC"
            let values: [SQLValue] = projectID.map { [.text($0.uuidString)] } ?? []
            return try query(sql, values) { row in
                ResearchQuestion(
                    id: try row.uuid(0), projectID: try row.uuid(1), parentQuestionID: row.optionalText(2).flatMap(UUID.init(uuidString:)),
                    question: row.text(3), notes: row.text(4), status: row.text(5), objectives: row.text(6),
                    theoreticalInterests: row.text(7), conceptualDefinitions: row.text(8), unresolvedDisagreements: row.text(9),
                    potentialHypotheses: row.text(10), methodologicalConsiderations: row.text(11),
                    createdAt: self.date(row.text(12)), modifiedAt: self.date(row.text(13))
                )
            }
        }
    }

    public func questionVersions(questionID: UUID? = nil) throws -> [ResearchQuestionVersion] {
        try synchronized {
            var sql = """
                SELECT id,question_id,parent_question_id,question_text,notes,status,objectives,theoretical_interests,
                       conceptual_definitions,unresolved_disagreements,potential_hypotheses,
                       methodological_considerations,change_note,created_at
                FROM question_versions
                """
            var values: [SQLValue] = []
            if let questionID { sql += " WHERE question_id=?"; values = [.text(questionID.uuidString)] }
            sql += " ORDER BY created_at DESC"
            return try query(sql, values) { row in
                ResearchQuestionVersion(
                    id: try row.uuid(0), questionID: try row.uuid(1), parentQuestionID: row.optionalText(2).flatMap(UUID.init(uuidString:)),
                    question: row.text(3), notes: row.text(4), status: row.text(5), objectives: row.text(6),
                    theoreticalInterests: row.text(7), conceptualDefinitions: row.text(8), unresolvedDisagreements: row.text(9),
                    potentialHypotheses: row.text(10), methodologicalConsiderations: row.text(11),
                    changeNote: row.text(12), createdAt: self.date(row.text(13))
                )
            }
        }
    }

    public func saveQuestionLiteratureAssociation(_ association: QuestionLiteratureAssociation) throws {
        try synchronized {
            try execute("""
                INSERT INTO question_literature_associations(question_id,literature_id,notes,created_at)
                VALUES(?,?,?,?)
                ON CONFLICT(question_id,literature_id) DO UPDATE SET notes=excluded.notes
                """, [
                    .text(association.questionID.uuidString), .text(association.literatureID.uuidString), .text(association.notes),
                    .text(dateFormatter.string(from: association.createdAt))
                ])
        }
    }

    public func questionLiteratureAssociations() throws -> [QuestionLiteratureAssociation] {
        try synchronized {
            try query("SELECT question_id,literature_id,notes,created_at FROM question_literature_associations ORDER BY created_at DESC") { row in
                QuestionLiteratureAssociation(questionID: try row.uuid(0), literatureID: try row.uuid(1), notes: row.text(2), createdAt: self.date(row.text(3)))
            }
        }
    }

    public func deleteQuestionLiteratureAssociation(questionID: UUID, literatureID: UUID) throws {
        try synchronized {
            try execute("DELETE FROM question_literature_associations WHERE question_id=? AND literature_id=?", [.text(questionID.uuidString), .text(literatureID.uuidString)])
        }
    }

    public func saveQuestionConceptAssociation(_ association: QuestionConceptAssociation) throws {
        try synchronized {
            try execute("""
                INSERT INTO question_concept_associations(question_id,concept_id,notes,created_at)
                VALUES(?,?,?,?)
                ON CONFLICT(question_id,concept_id) DO UPDATE SET notes=excluded.notes
                """, [
                    .text(association.questionID.uuidString), .text(association.conceptID.uuidString), .text(association.notes),
                    .text(dateFormatter.string(from: association.createdAt))
                ])
        }
    }

    public func questionConceptAssociations() throws -> [QuestionConceptAssociation] {
        try synchronized {
            try query("SELECT question_id,concept_id,notes,created_at FROM question_concept_associations ORDER BY created_at DESC") { row in
                QuestionConceptAssociation(questionID: try row.uuid(0), conceptID: try row.uuid(1), notes: row.text(2), createdAt: self.date(row.text(3)))
            }
        }
    }

    public func deleteQuestionConceptAssociation(questionID: UUID, conceptID: UUID) throws {
        try synchronized {
            try execute("DELETE FROM question_concept_associations WHERE question_id=? AND concept_id=?", [.text(questionID.uuidString), .text(conceptID.uuidString)])
        }
    }

    public func saveArgument(_ argument: ResearchArgument, changeNote: String? = nil) throws {
        try synchronized {
            let existing = try query("SELECT id,question_id,proposition,qualification,status,created_at,modified_at FROM research_arguments WHERE id=?", [.text(argument.id.uuidString)]) { row in
                ResearchArgument(id: try row.uuid(0), questionID: row.optionalText(1).flatMap(UUID.init(uuidString:)), proposition: row.text(2), qualification: row.text(3), status: row.text(4), createdAt: self.date(row.text(5)), modifiedAt: self.date(row.text(6)))
            }.first
            let changed = existing.map {
                $0.questionID != argument.questionID || $0.proposition != argument.proposition || $0.qualification != argument.qualification || $0.status != argument.status
            } ?? true
            guard changed else { return }

            try execute("BEGIN IMMEDIATE")
            do {
                if let existing {
                    let versionCount = try query("SELECT COUNT(*) FROM argument_versions WHERE argument_id=?", [.text(argument.id.uuidString)]) { $0.int(0) }.first ?? 0
                    if versionCount == 0 {
                        try insertArgumentVersion(ArgumentVersion(
                            argumentID: existing.id,
                            questionID: existing.questionID,
                            proposition: existing.proposition,
                            qualification: existing.qualification,
                            status: existing.status,
                            changeNote: "Baseline captured before first tracked edit"
                        ))
                    }
                }
                try execute("""
                    INSERT INTO research_arguments(id,question_id,proposition,qualification,status,created_at,modified_at) VALUES(?,?,?,?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET question_id=excluded.question_id,proposition=excluded.proposition,qualification=excluded.qualification,status=excluded.status,modified_at=excluded.modified_at
                    """, [.text(argument.id.uuidString), optionalText(argument.questionID?.uuidString), .text(argument.proposition), .text(argument.qualification),
                           .text(argument.status), .text(dateFormatter.string(from: argument.createdAt)), .text(dateFormatter.string(from: argument.modifiedAt))])
                try insertArgumentVersion(ArgumentVersion(
                    argumentID: argument.id,
                    questionID: argument.questionID,
                    proposition: argument.proposition,
                    qualification: argument.qualification,
                    status: argument.status,
                    changeNote: changeNote?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? (existing == nil ? "Created" : "Updated"),
                    createdAt: argument.modifiedAt
                ))
                try replaceSearchIndex(entityID: argument.id.uuidString, type: "argument", title: argument.proposition, body: argument.qualification)
                try insertHistoryEvent(HistoryEvent(
                    entityType: "argument", entityID: argument.id.uuidString,
                    eventType: existing == nil ? "created" : "revised", title: argument.proposition,
                    detail: changeNote?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? (existing == nil ? "Created" : "Updated"),
                    recordedAt: argument.modifiedAt
                ))
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    public func arguments() throws -> [ResearchArgument] {
        try synchronized {
            try query("SELECT id,question_id,proposition,qualification,status,created_at,modified_at FROM research_arguments ORDER BY modified_at DESC") { row in
                ResearchArgument(id: try row.uuid(0), questionID: row.optionalText(1).flatMap(UUID.init(uuidString:)), proposition: row.text(2), qualification: row.text(3), status: row.text(4), createdAt: self.date(row.text(5)), modifiedAt: self.date(row.text(6)))
            }
        }
    }

    public func argumentVersions(argumentID: UUID? = nil) throws -> [ArgumentVersion] {
        try synchronized {
            let sql = argumentID == nil
                ? "SELECT id,argument_id,question_id,proposition,qualification,status,change_note,created_at FROM argument_versions ORDER BY created_at DESC"
                : "SELECT id,argument_id,question_id,proposition,qualification,status,change_note,created_at FROM argument_versions WHERE argument_id=? ORDER BY created_at DESC"
            let values: [SQLValue] = argumentID.map { [.text($0.uuidString)] } ?? []
            return try query(sql, values) { row in
                ArgumentVersion(
                    id: try row.uuid(0), argumentID: try row.uuid(1), questionID: row.optionalText(2).flatMap(UUID.init(uuidString:)),
                    proposition: row.text(3), qualification: row.text(4), status: row.text(5), changeNote: row.text(6), createdAt: self.date(row.text(7))
                )
            }
        }
    }

    public func saveEvidence(_ evidence: EvidenceRelationship) throws {
        try synchronized {
            let existed = (try query("SELECT COUNT(*) FROM evidence_relationships WHERE id=?", [.text(evidence.id.uuidString)]) { $0.int(0) }.first ?? 0) == 1
            try execute("""
                INSERT INTO evidence_relationships(
                    id,argument_id,literature_id,relation,summary,page,quoted_passage,verification,
                    selection_geometry_json,selection_document_hash,created_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET
                    relation=excluded.relation,summary=excluded.summary,page=excluded.page,
                    quoted_passage=excluded.quoted_passage,verification=excluded.verification,
                    selection_geometry_json=excluded.selection_geometry_json,
                    selection_document_hash=excluded.selection_document_hash
                """, [.text(evidence.id.uuidString), .text(evidence.argumentID.uuidString), .text(evidence.literatureID.uuidString),
                       .text(evidence.relation.rawValue), .text(evidence.summary), optionalInt(evidence.page), .text(evidence.quotedPassage),
                       .text(evidence.verification.rawValue), .text(encodeJSON(evidence.selectionRegions)),
                       optionalText(evidence.selectionDocumentHash), .text(dateFormatter.string(from: evidence.createdAt))])
            try insertHistoryEvent(HistoryEvent(
                entityType: "evidence", entityID: evidence.id.uuidString,
                eventType: existed ? "updated" : "created", title: evidence.summary,
                detail: "\(evidence.relation.rawValue) · \(evidence.verification.rawValue)", recordedAt: Date()
            ))
        }
    }

    public func deleteEvidence(id: UUID) throws {
        try synchronized {
            try execute("DELETE FROM evidence_relationships WHERE id=?", [.text(id.uuidString)])
        }
    }

    public func indexPDFPages(literatureID: UUID, pages: [String]) throws {
        try synchronized {
            try execute("BEGIN IMMEDIATE")
            do {
                try replacePDFPageIndex(literatureID: literatureID, pages: pages)
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    public func relinkPDF(
        literatureID: UUID,
        url: URL,
        fingerprint: PDFFileFingerprint,
        pages: [String],
        preserveZoteroAttachmentKey: Bool = true
    ) throws {
        try synchronized {
            try execute("BEGIN IMMEDIATE")
            do {
                try execute("""
                    UPDATE literature_items
                    SET pdf_path=?,pdf_byte_count=?,pdf_sha256=?,pdf_last_verified_at=?,
                        zotero_attachment_key=CASE WHEN ?=1 THEN zotero_attachment_key ELSE NULL END
                    WHERE id=?
                    """, [
                        .text(url.path), .int(fingerprint.byteCount), .text(fingerprint.sha256),
                        .text(dateFormatter.string(from: Date())), .int(preserveZoteroAttachmentKey ? 1 : 0),
                        .text(literatureID.uuidString)
                    ])
                guard sqlite3_changes(connection) == 1 else {
                    throw DatabaseError.invalidData("The paper selected for PDF repair no longer exists.")
                }
                try replacePDFPageIndex(literatureID: literatureID, pages: pages)
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    public func evidence(argumentID: UUID) throws -> [EvidenceRelationship] {
        try synchronized {
            try query("SELECT id,argument_id,literature_id,relation,summary,page,quoted_passage,verification,selection_geometry_json,selection_document_hash,created_at FROM evidence_relationships WHERE argument_id=? ORDER BY created_at DESC", [.text(argumentID.uuidString)]) { row in
                EvidenceRelationship(id: try row.uuid(0), argumentID: try row.uuid(1), literatureID: try row.uuid(2), relation: EvidenceRelation(rawValue: row.text(3)) ?? .context,
                                     summary: row.text(4), page: row.optionalInt(5), quotedPassage: row.text(6), verification: VerificationState(rawValue: row.text(7)) ?? .unverified,
                                     selectionRegions: self.decodeJSON([PDFSelectionRegion].self, from: row.text(8)) ?? [],
                                     selectionDocumentHash: row.optionalText(9), createdAt: self.date(row.text(10)))
            }
        }
    }

    public func allEvidence() throws -> [EvidenceRelationship] {
        try synchronized {
            try query("SELECT id,argument_id,literature_id,relation,summary,page,quoted_passage,verification,selection_geometry_json,selection_document_hash,created_at FROM evidence_relationships ORDER BY created_at DESC") { row in
                EvidenceRelationship(id: try row.uuid(0), argumentID: try row.uuid(1), literatureID: try row.uuid(2), relation: EvidenceRelation(rawValue: row.text(3)) ?? .context,
                                     summary: row.text(4), page: row.optionalInt(5), quotedPassage: row.text(6), verification: VerificationState(rawValue: row.text(7)) ?? .unverified,
                                     selectionRegions: self.decodeJSON([PDFSelectionRegion].self, from: row.text(8)) ?? [],
                                     selectionDocumentHash: row.optionalText(9), createdAt: self.date(row.text(10)))
            }
        }
    }

    public func saveClaim(_ claim: ResearchClaim, changeNote: String? = nil) throws {
        try synchronized {
            let trimmedText = claim.claimText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { throw DatabaseError.invalidData("Claim text is required.") }
            if claim.extractionMethod == .aiCandidate {
                guard claim.modelIdentifier?.nilIfEmpty != nil, claim.promptVersion?.nilIfEmpty != nil else {
                    throw DatabaseError.invalidData("AI claim candidates require a model identifier and prompt version.")
                }
            }
            if let passageID = claim.sourcePassageID {
                let source = try query("SELECT literature_id,page,passage_text FROM source_passages WHERE id=?", [.text(passageID)]) {
                    (try $0.uuid(0), $0.int(1), $0.text(2))
                }.first
                guard let source else { throw DatabaseError.invalidData("The selected claim source passage is no longer indexed.") }
                if let literatureID = claim.literatureID, literatureID != source.0 {
                    throw DatabaseError.invalidData("The claim's paper and source passage do not match.")
                }
                if let page = claim.page, page != source.1 {
                    throw DatabaseError.invalidData("The claim's page does not match its indexed source passage.")
                }
            }
            let existing = try claimRecord(id: claim.id)
            let changed = existing.map { $0 != claim } ?? true
            guard changed else { return }
            try execute("BEGIN IMMEDIATE")
            do {
                if let existing {
                    let count = try query("SELECT COUNT(*) FROM claim_versions WHERE claim_id=?", [.text(claim.id.uuidString)]) { $0.int(0) }.first ?? 0
                    if count == 0 { try insertClaimVersion(version(from: existing, changeNote: "Baseline captured before first tracked edit")) }
                }
                try execute("""
                    INSERT INTO research_claims(
                        id,claim_text,category,literature_id,source_passage_id,page,quoted_source_text,
                        author_terminology,methodological_context,evidence_type,related_constructs_json,
                        study_context,extraction_method,model_identifier,prompt_version,verification,user_notes,
                        created_at,modified_at
                    ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET claim_text=excluded.claim_text,category=excluded.category,
                        literature_id=excluded.literature_id,source_passage_id=excluded.source_passage_id,page=excluded.page,
                        quoted_source_text=excluded.quoted_source_text,author_terminology=excluded.author_terminology,
                        methodological_context=excluded.methodological_context,evidence_type=excluded.evidence_type,
                        related_constructs_json=excluded.related_constructs_json,study_context=excluded.study_context,
                        extraction_method=excluded.extraction_method,model_identifier=excluded.model_identifier,
                        prompt_version=excluded.prompt_version,verification=excluded.verification,
                        user_notes=excluded.user_notes,modified_at=excluded.modified_at
                    """, [
                        .text(claim.id.uuidString), .text(trimmedText), .text(claim.category.rawValue),
                        optionalText(claim.literatureID?.uuidString), optionalText(claim.sourcePassageID), optionalInt(claim.page),
                        .text(claim.quotedSourceText), .text(claim.authorTerminology), .text(claim.methodologicalContext),
                        .text(claim.evidenceType), .text(json(claim.relatedConstructs)), .text(claim.studyContext),
                        .text(claim.extractionMethod.rawValue), optionalText(claim.modelIdentifier), optionalText(claim.promptVersion),
                        .text(claim.verification.rawValue), .text(claim.userNotes),
                        .text(dateFormatter.string(from: claim.createdAt)), .text(dateFormatter.string(from: claim.modifiedAt))
                    ])
                let note = changeNote?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? (existing == nil ? "Created" : "Updated")
                try insertClaimVersion(version(from: claim, changeNote: note))
                try replaceSearchIndex(
                    entityID: claim.id.uuidString, type: "claim", title: claim.claimText,
                    body: [claim.quotedSourceText, claim.authorTerminology, claim.methodologicalContext,
                           claim.evidenceType, claim.relatedConstructs.joined(separator: " "), claim.studyContext,
                           claim.userNotes].joined(separator: "\n")
                )
                try insertHistoryEvent(HistoryEvent(
                    entityType: "claim", entityID: claim.id.uuidString,
                    eventType: existing == nil ? "created" : "revised", title: claim.claimText, detail: note,
                    recordedAt: claim.modifiedAt
                ))
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    public func claims() throws -> [ResearchClaim] {
        try synchronized {
            try query("""
                SELECT id,claim_text,category,literature_id,source_passage_id,page,quoted_source_text,
                       author_terminology,methodological_context,evidence_type,related_constructs_json,
                       study_context,extraction_method,model_identifier,prompt_version,verification,user_notes,
                       created_at,modified_at
                FROM research_claims ORDER BY modified_at DESC
                """) { try self.claim(from: $0) }
        }
    }

    public func claimVersions(claimID: UUID? = nil) throws -> [ClaimVersion] {
        try synchronized {
            var sql = """
                SELECT id,claim_id,claim_text,category,author_terminology,methodological_context,evidence_type,
                       related_constructs_json,study_context,verification,user_notes,change_note,created_at
                FROM claim_versions
                """
            var values: [SQLValue] = []
            if let claimID { sql += " WHERE claim_id=?"; values = [.text(claimID.uuidString)] }
            sql += " ORDER BY created_at DESC"
            return try query(sql, values) { row in
                ClaimVersion(
                    id: try row.uuid(0), claimID: try row.uuid(1), claimText: row.text(2),
                    category: ClaimCategory(rawValue: row.text(3)) ?? .personalInterpretation,
                    authorTerminology: row.text(4), methodologicalContext: row.text(5), evidenceType: row.text(6),
                    relatedConstructs: self.stringArray(row.text(7)), studyContext: row.text(8),
                    verification: VerificationState(rawValue: row.text(9)) ?? .unverified,
                    userNotes: row.text(10), changeNote: row.text(11), createdAt: self.date(row.text(12))
                )
            }
        }
    }

    public func deleteClaim(id: UUID) throws {
        try synchronized {
            try execute("BEGIN IMMEDIATE")
            do {
                try execute("DELETE FROM knowledge_relationships WHERE (source_type=? AND source_id=?) OR (target_type=? AND target_id=?)", [
                    .text(KnowledgeNodeType.claim.rawValue), .text(id.uuidString),
                    .text(KnowledgeNodeType.claim.rawValue), .text(id.uuidString)
                ])
                try execute("DELETE FROM research_claims WHERE id=?", [.text(id.uuidString)])
                try execute("DELETE FROM search_index WHERE entity_id=? AND entity_type='claim'", [.text(id.uuidString)])
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    public func saveComparisonProfile(_ profile: LiteratureComparisonProfile) throws {
        try synchronized {
            try execute("""
                INSERT INTO literature_comparison_profiles(
                    literature_id,research_question,theoretical_framework,study_design,sample,
                    independent_variables,dependent_variables,operational_definitions,main_findings,
                    limitations,user_notes,modified_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(literature_id) DO UPDATE SET
                    research_question=excluded.research_question,
                    theoretical_framework=excluded.theoretical_framework,
                    study_design=excluded.study_design,sample=excluded.sample,
                    independent_variables=excluded.independent_variables,
                    dependent_variables=excluded.dependent_variables,
                    operational_definitions=excluded.operational_definitions,
                    main_findings=excluded.main_findings,limitations=excluded.limitations,
                    user_notes=excluded.user_notes,modified_at=excluded.modified_at
                """, [
                    .text(profile.literatureID.uuidString), .text(profile.researchQuestion),
                    .text(profile.theoreticalFramework), .text(profile.studyDesign), .text(profile.sample),
                    .text(profile.independentVariables), .text(profile.dependentVariables),
                    .text(profile.operationalDefinitions), .text(profile.mainFindings),
                    .text(profile.limitations), .text(profile.userNotes),
                    .text(dateFormatter.string(from: profile.modifiedAt))
                ])
            try replaceSearchIndex(
                entityID: profile.literatureID.uuidString,
                type: "comparison",
                title: "Literature comparison profile",
                body: [profile.researchQuestion, profile.theoreticalFramework, profile.studyDesign, profile.sample,
                       profile.independentVariables, profile.dependentVariables, profile.operationalDefinitions,
                       profile.mainFindings, profile.limitations, profile.userNotes].joined(separator: "\n")
            )
        }
    }

    public func comparisonProfiles() throws -> [LiteratureComparisonProfile] {
        try synchronized {
            try query("""
                SELECT literature_id,research_question,theoretical_framework,study_design,sample,
                       independent_variables,dependent_variables,operational_definitions,main_findings,
                       limitations,user_notes,modified_at
                FROM literature_comparison_profiles ORDER BY modified_at DESC
                """) { row in
                LiteratureComparisonProfile(
                    literatureID: try row.uuid(0), researchQuestion: row.text(1),
                    theoreticalFramework: row.text(2), studyDesign: row.text(3), sample: row.text(4),
                    independentVariables: row.text(5), dependentVariables: row.text(6),
                    operationalDefinitions: row.text(7), mainFindings: row.text(8),
                    limitations: row.text(9), userNotes: row.text(10), modifiedAt: self.date(row.text(11))
                )
            }
        }
    }

    @discardableResult
    public func createRetrievalSet(_ set: RetrievalSet, limit: Int = 40) throws -> [RetrievedPassage] {
        let queryText = set.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !queryText.isEmpty else { throw DatabaseError.invalidData("A retrieval query is required.") }
        if let from = set.yearFrom, let to = set.yearTo, from > to {
            throw DatabaseError.invalidData("The starting publication year must not be after the ending year.")
        }
        return try synchronized {
            let matches = try matchingSourcePassages(for: set, limit: max(1, min(limit, 200)))
            let noteMatches = try matchingNoteSnippets(for: set, limit: max(1, min(limit / 2, 80)))
            try execute("BEGIN IMMEDIATE")
            do {
                try execute("""
                    INSERT INTO retrieval_sets(
                        id,name,query_text,zotero_library_filter_id,zotero_collection_filter_id,year_from,year_to,created_at
                    ) VALUES(?,?,?,?,?,?,?,?)
                    """, [
                        .text(set.id.uuidString), .text(set.name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? queryText),
                        .text(queryText), optionalText(set.zoteroLibraryFilterID), optionalText(set.zoteroCollectionFilterID),
                        optionalInt(set.yearFrom), optionalInt(set.yearTo), .text(dateFormatter.string(from: set.createdAt))
                    ])
                for passage in matches {
                    try execute("""
                        INSERT INTO retrieval_set_passages(
                            retrieval_set_id,source_passage_id,literature_id,page,passage_text,extraction_method,
                            source_indexed_at,source_document_hash,relevance_rank,added_at
                        ) VALUES(?,?,?,?,?,?,?,?,?,?)
                        """, [
                            .text(set.id.uuidString), .text(passage.sourcePassageID), .text(passage.literatureID.uuidString),
                            .int(Int64(passage.page)), .text(passage.passageText), .text(passage.extractionMethod),
                            .text(dateFormatter.string(from: passage.sourceIndexedAt)), optionalText(passage.sourceDocumentHash),
                            .double(passage.rank), .text(dateFormatter.string(from: passage.addedAt))
                        ])
                }
                for note in noteMatches {
                    try execute("""
                        INSERT INTO retrieval_set_note_snippets(
                            retrieval_set_id,note_id,note_path,note_title,snippet_text,
                            source_modified_at,relevance_rank,added_at
                        ) VALUES(?,?,?,?,?,?,?,?)
                        """, [
                            .text(set.id.uuidString), .text(note.noteID.uuidString), .text(note.notePath),
                            .text(note.noteTitle), .text(note.snippetText),
                            .text(dateFormatter.string(from: note.sourceModifiedAt)), .double(note.rank),
                            .text(dateFormatter.string(from: note.addedAt))
                        ])
                }
                try execute("COMMIT")
                return matches
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    public func retrievalSets() throws -> [RetrievalSet] {
        try synchronized {
            try query("""
                SELECT id,name,query_text,zotero_library_filter_id,zotero_collection_filter_id,year_from,year_to,created_at
                FROM retrieval_sets ORDER BY created_at DESC
                """) { row in
                RetrievalSet(
                    id: try row.uuid(0), name: row.text(1), query: row.text(2),
                    zoteroLibraryFilterID: row.optionalText(3), zoteroCollectionFilterID: row.optionalText(4),
                    yearFrom: row.optionalInt(5), yearTo: row.optionalInt(6), createdAt: self.date(row.text(7))
                )
            }
        }
    }

    public func retrievedPassages(retrievalSetID: UUID? = nil) throws -> [RetrievedPassage] {
        try synchronized {
            var sql = """
                SELECT r.retrieval_set_id,r.source_passage_id,r.literature_id,r.page,r.passage_text,
                       r.extraction_method,r.source_indexed_at,r.source_document_hash,r.relevance_rank,r.added_at,
                       p.id,p.passage_text,l.pdf_sha256
                FROM retrieval_set_passages r
                LEFT JOIN source_passages p ON p.id=r.source_passage_id
                LEFT JOIN literature_items l ON l.id=r.literature_id
                """
            var values: [SQLValue] = []
            if let retrievalSetID {
                sql += " WHERE r.retrieval_set_id=?"
                values = [.text(retrievalSetID.uuidString)]
            }
            sql += " ORDER BY r.relevance_rank ASC,r.page ASC"
            return try query(sql, values) { row in
                let status: RetrievalCitationStatus
                if row.optionalText(10) == nil {
                    status = .sourceMissing
                } else if let storedHash = row.optionalText(7), storedHash != row.optionalText(12) {
                    status = .documentChanged
                } else if row.text(4) != row.text(11) {
                    status = .passageChanged
                } else {
                    status = .current
                }
                return RetrievedPassage(
                    retrievalSetID: try row.uuid(0), sourcePassageID: row.text(1), literatureID: try row.uuid(2),
                    page: row.int(3), passageText: row.text(4), extractionMethod: row.text(5),
                    sourceIndexedAt: self.date(row.text(6)), sourceDocumentHash: row.optionalText(7),
                    rank: row.double(8), citationStatus: status, addedAt: self.date(row.text(9))
                )
            }
        }
    }

    public func retrievedNoteSnippets(retrievalSetID: UUID? = nil) throws -> [RetrievedNoteSnippet] {
        try synchronized {
            var sql = """
                SELECT r.retrieval_set_id,r.note_id,r.note_path,r.note_title,r.snippet_text,
                       r.source_modified_at,r.relevance_rank,r.added_at,n.id,n.content,n.modified_at
                FROM retrieval_set_note_snippets r
                LEFT JOIN obsidian_notes n ON n.id=r.note_id
                """
            var values: [SQLValue] = []
            if let retrievalSetID {
                sql += " WHERE r.retrieval_set_id=?"
                values = [.text(retrievalSetID.uuidString)]
            }
            sql += " ORDER BY r.relevance_rank ASC,r.note_title COLLATE NOCASE"
            return try query(sql, values) { row in
                let status: RetrievalCitationStatus
                if row.optionalText(8) == nil { status = .sourceMissing }
                else if !row.text(9).contains(row.text(4)) { status = .passageChanged }
                else { status = .current }
                return RetrievedNoteSnippet(
                    retrievalSetID: try row.uuid(0), noteID: try row.uuid(1), notePath: row.text(2),
                    noteTitle: row.text(3), snippetText: row.text(4), sourceModifiedAt: self.date(row.text(5)),
                    rank: row.double(6), citationStatus: status, addedAt: self.date(row.text(7))
                )
            }
        }
    }

    public func deleteRetrievalSet(id: UUID) throws {
        try synchronized { try execute("DELETE FROM retrieval_sets WHERE id=?", [.text(id.uuidString)]) }
    }

    public func saveConcept(_ concept: ResearchConcept) throws {
        try synchronized {
            try execute("""
                INSERT INTO research_concepts(id,name,definition,notes,verification,origin,created_at,modified_at)
                VALUES(?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET name=excluded.name,definition=excluded.definition,
                    notes=excluded.notes,verification=excluded.verification,origin=excluded.origin,
                    modified_at=excluded.modified_at
                """, [
                    .text(concept.id.uuidString), .text(concept.name), .text(concept.definition), .text(concept.notes),
                    .text(concept.verification.rawValue), .text(concept.origin.rawValue),
                    .text(dateFormatter.string(from: concept.createdAt)), .text(dateFormatter.string(from: concept.modifiedAt))
                ])
            try replaceSearchIndex(entityID: concept.id.uuidString, type: "concept", title: concept.name, body: "\(concept.definition)\n\(concept.notes)")
        }
    }

    public func concepts() throws -> [ResearchConcept] {
        try synchronized {
            try query("SELECT id,name,definition,notes,verification,origin,created_at,modified_at FROM research_concepts ORDER BY name COLLATE NOCASE") { row in
                ResearchConcept(
                    id: try row.uuid(0), name: row.text(1), definition: row.text(2), notes: row.text(3),
                    verification: VerificationState(rawValue: row.text(4)) ?? .unverified,
                    origin: RecordOrigin(rawValue: row.text(5)) ?? .user,
                    createdAt: self.date(row.text(6)), modifiedAt: self.date(row.text(7))
                )
            }
        }
    }

    public func deleteConcept(id: UUID) throws {
        try synchronized {
            try execute("BEGIN IMMEDIATE")
            do {
                try execute("DELETE FROM knowledge_relationships WHERE (source_type=? AND source_id=?) OR (target_type=? AND target_id=?)", [
                    .text(KnowledgeNodeType.concept.rawValue), .text(id.uuidString),
                    .text(KnowledgeNodeType.concept.rawValue), .text(id.uuidString)
                ])
                try execute("DELETE FROM research_concepts WHERE id=?", [.text(id.uuidString)])
                try execute("DELETE FROM search_index WHERE entity_id=? AND entity_type='concept'", [.text(id.uuidString)])
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    public func saveKnowledgeRelationship(_ relationship: KnowledgeRelationship) throws {
        try synchronized {
            guard relationship.sourceType != relationship.targetType || relationship.sourceID != relationship.targetID else {
                throw DatabaseError.invalidData("A knowledge relationship cannot point a node to itself.")
            }
            guard try knowledgeNodeExists(type: relationship.sourceType, id: relationship.sourceID),
                  try knowledgeNodeExists(type: relationship.targetType, id: relationship.targetID) else {
                throw DatabaseError.invalidData("One of the selected knowledge nodes no longer exists.")
            }
            if let passageID = relationship.sourcePassageID {
                let passageCount = try query("SELECT COUNT(*) FROM source_passages WHERE id=?", [.text(passageID)]) { $0.int(0) }.first ?? 0
                guard passageCount == 1 else {
                    throw DatabaseError.invalidData("The selected source passage is no longer indexed.")
                }
            }
            let rationale = relationship.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            guard relationship.evidenceRelationshipID != nil || relationship.sourcePassageID != nil || !rationale.isEmpty else {
                throw DatabaseError.invalidData("Add an evidence link, source passage, or rationale for this relationship.")
            }
            let existed = (try query("SELECT COUNT(*) FROM knowledge_relationships WHERE id=?", [.text(relationship.id.uuidString)]) { $0.int(0) }.first ?? 0) == 1
            try execute("""
                INSERT INTO knowledge_relationships(
                    id,source_type,source_id,target_type,target_id,relationship_type,
                    evidence_relationship_id,source_passage_id,verification,origin,notes,created_at,modified_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET source_type=excluded.source_type,source_id=excluded.source_id,
                    target_type=excluded.target_type,target_id=excluded.target_id,
                    relationship_type=excluded.relationship_type,evidence_relationship_id=excluded.evidence_relationship_id,
                    source_passage_id=excluded.source_passage_id,verification=excluded.verification,
                    origin=excluded.origin,notes=excluded.notes,modified_at=excluded.modified_at
                """, [
                    .text(relationship.id.uuidString), .text(relationship.sourceType.rawValue), .text(relationship.sourceID),
                    .text(relationship.targetType.rawValue), .text(relationship.targetID), .text(relationship.relationship.rawValue),
                    optionalText(relationship.evidenceRelationshipID?.uuidString), optionalText(relationship.sourcePassageID),
                    .text(relationship.verification.rawValue), .text(relationship.origin.rawValue), .text(rationale),
                    .text(dateFormatter.string(from: relationship.createdAt)), .text(dateFormatter.string(from: relationship.modifiedAt))
                ])
            try insertHistoryEvent(HistoryEvent(
                entityType: "knowledge_relationship", entityID: relationship.id.uuidString,
                eventType: existed ? "updated" : "created", title: relationship.relationship.rawValue,
                detail: rationale, recordedAt: relationship.modifiedAt
            ))
        }
    }

    public func knowledgeRelationships() throws -> [KnowledgeRelationship] {
        try synchronized {
            try query("""
                SELECT id,source_type,source_id,target_type,target_id,relationship_type,
                       evidence_relationship_id,source_passage_id,verification,origin,notes,created_at,modified_at
                FROM knowledge_relationships ORDER BY modified_at DESC
                """) { row in
                KnowledgeRelationship(
                    id: try row.uuid(0), sourceType: KnowledgeNodeType(rawValue: row.text(1)) ?? .paper,
                    sourceID: row.text(2), targetType: KnowledgeNodeType(rawValue: row.text(3)) ?? .paper,
                    targetID: row.text(4), relationship: KnowledgeRelationshipType(rawValue: row.text(5)) ?? .relatesTo,
                    evidenceRelationshipID: row.optionalText(6).flatMap(UUID.init(uuidString:)), sourcePassageID: row.optionalText(7),
                    verification: VerificationState(rawValue: row.text(8)) ?? .unverified,
                    origin: RecordOrigin(rawValue: row.text(9)) ?? .user, notes: row.text(10),
                    createdAt: self.date(row.text(11)), modifiedAt: self.date(row.text(12))
                )
            }
        }
    }

    public func deleteKnowledgeRelationship(id: UUID) throws {
        try synchronized { try execute("DELETE FROM knowledge_relationships WHERE id=?", [.text(id.uuidString)]) }
    }

    public func saveIdea(_ idea: ResearchIdea, changeNote: String? = nil) throws {
        try synchronized {
            guard !idea.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DatabaseError.invalidData("An idea title is required.")
            }
            let existing = try ideaRecord(id: idea.id)
            let changed = existing.map { $0 != idea } ?? true
            guard changed else { return }
            try execute("BEGIN IMMEDIATE")
            do {
                if let existing {
                    let count = try query("SELECT COUNT(*) FROM idea_versions WHERE idea_id=?", [.text(idea.id.uuidString)]) { $0.int(0) }.first ?? 0
                    if count == 0 { try insertIdeaVersion(version(from: existing, changeNote: "Baseline captured before first tracked edit")) }
                }
                try execute("""
                    INSERT INTO research_ideas(
                        id,project_id,question_id,title,body,status,assumptions,alternative_explanations,
                        evidence_needed,investigation_notes,created_at,modified_at
                    ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET project_id=excluded.project_id,question_id=excluded.question_id,
                        title=excluded.title,body=excluded.body,status=excluded.status,assumptions=excluded.assumptions,
                        alternative_explanations=excluded.alternative_explanations,evidence_needed=excluded.evidence_needed,
                        investigation_notes=excluded.investigation_notes,modified_at=excluded.modified_at
                    """, [
                        .text(idea.id.uuidString), optionalText(idea.projectID?.uuidString), optionalText(idea.questionID?.uuidString),
                        .text(idea.title), .text(idea.body), .text(idea.status.rawValue), .text(idea.assumptions),
                        .text(idea.alternativeExplanations), .text(idea.evidenceNeeded), .text(idea.investigationNotes),
                        .text(dateFormatter.string(from: idea.createdAt)), .text(dateFormatter.string(from: idea.modifiedAt))
                    ])
                let note = changeNote?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? (existing == nil ? "Created" : "Updated")
                try insertIdeaVersion(version(from: idea, changeNote: note))
                try replaceSearchIndex(
                    entityID: idea.id.uuidString, type: "idea", title: idea.title,
                    body: [idea.body, idea.assumptions, idea.alternativeExplanations, idea.evidenceNeeded, idea.investigationNotes].joined(separator: "\n")
                )
                try insertHistoryEvent(HistoryEvent(
                    entityType: "idea", entityID: idea.id.uuidString,
                    eventType: existing == nil ? "created" : "revised", title: idea.title, detail: note,
                    recordedAt: idea.modifiedAt
                ))
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    public func ideas() throws -> [ResearchIdea] {
        try synchronized {
            try query("""
                SELECT id,project_id,question_id,title,body,status,assumptions,alternative_explanations,
                       evidence_needed,investigation_notes,created_at,modified_at
                FROM research_ideas ORDER BY modified_at DESC
                """) { row in
                ResearchIdea(
                    id: try row.uuid(0), projectID: row.optionalText(1).flatMap(UUID.init(uuidString:)),
                    questionID: row.optionalText(2).flatMap(UUID.init(uuidString:)), title: row.text(3), body: row.text(4),
                    status: ResearchIdeaStatus(rawValue: row.text(5)) ?? .initialObservation,
                    assumptions: row.text(6), alternativeExplanations: row.text(7), evidenceNeeded: row.text(8),
                    investigationNotes: row.text(9), createdAt: self.date(row.text(10)), modifiedAt: self.date(row.text(11))
                )
            }
        }
    }

    public func ideaVersions(ideaID: UUID? = nil) throws -> [IdeaVersion] {
        try synchronized {
            var sql = """
                SELECT id,idea_id,title,body,status,assumptions,alternative_explanations,evidence_needed,
                       investigation_notes,change_note,created_at FROM idea_versions
                """
            var values: [SQLValue] = []
            if let ideaID { sql += " WHERE idea_id=?"; values = [.text(ideaID.uuidString)] }
            sql += " ORDER BY created_at DESC"
            return try query(sql, values) { row in
                IdeaVersion(
                    id: try row.uuid(0), ideaID: try row.uuid(1), title: row.text(2), body: row.text(3),
                    status: ResearchIdeaStatus(rawValue: row.text(4)) ?? .initialObservation,
                    assumptions: row.text(5), alternativeExplanations: row.text(6), evidenceNeeded: row.text(7),
                    investigationNotes: row.text(8), changeNote: row.text(9), createdAt: self.date(row.text(10))
                )
            }
        }
    }

    public func saveIdeaLink(_ link: ResearchIdeaLink) throws {
        try synchronized {
            guard try ideaLinkTargetExists(type: link.targetType, id: link.targetID) else {
                throw DatabaseError.invalidData("The selected idea link target no longer exists.")
            }
            try execute("""
                INSERT INTO idea_links(id,idea_id,target_type,target_id,notes,created_at) VALUES(?,?,?,?,?,?)
                ON CONFLICT(idea_id,target_type,target_id) DO UPDATE SET notes=excluded.notes
                """, [
                    .text(link.id.uuidString), .text(link.ideaID.uuidString), .text(link.targetType.rawValue),
                    .text(link.targetID), .text(link.notes), .text(dateFormatter.string(from: link.createdAt))
                ])
        }
    }

    public func ideaLinks() throws -> [ResearchIdeaLink] {
        try synchronized {
            try query("SELECT id,idea_id,target_type,target_id,notes,created_at FROM idea_links ORDER BY created_at DESC") { row in
                ResearchIdeaLink(
                    id: try row.uuid(0), ideaID: try row.uuid(1), targetType: IdeaLinkTargetType(rawValue: row.text(2)) ?? .literature,
                    targetID: row.text(3), notes: row.text(4), createdAt: self.date(row.text(5))
                )
            }
        }
    }

    public func deleteIdeaLink(id: UUID) throws {
        try synchronized { try execute("DELETE FROM idea_links WHERE id=?", [.text(id.uuidString)]) }
    }

    public func deleteIdea(id: UUID) throws {
        try synchronized {
            try execute("BEGIN IMMEDIATE")
            do {
                try execute("DELETE FROM knowledge_relationships WHERE (source_type=? AND source_id=?) OR (target_type=? AND target_id=?)", [
                    .text(KnowledgeNodeType.idea.rawValue), .text(id.uuidString),
                    .text(KnowledgeNodeType.idea.rawValue), .text(id.uuidString)
                ])
                try execute("DELETE FROM research_ideas WHERE id=?", [.text(id.uuidString)])
                try execute("DELETE FROM search_index WHERE entity_id=? AND entity_type='idea'", [.text(id.uuidString)])
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    public func saveContradictionCase(_ contradiction: ContradictionCase) throws {
        try synchronized {
            try execute("""
                INSERT INTO contradiction_cases(id,question_id,title,summary,status,resolution_notes,created_at,modified_at)
                VALUES(?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET question_id=excluded.question_id,title=excluded.title,
                    summary=excluded.summary,status=excluded.status,resolution_notes=excluded.resolution_notes,
                    modified_at=excluded.modified_at
                """, [
                    .text(contradiction.id.uuidString), optionalText(contradiction.questionID?.uuidString),
                    .text(contradiction.title), .text(contradiction.summary), .text(contradiction.status.rawValue),
                    .text(contradiction.resolutionNotes), .text(dateFormatter.string(from: contradiction.createdAt)),
                    .text(dateFormatter.string(from: contradiction.modifiedAt))
                ])
            try replaceSearchIndex(entityID: contradiction.id.uuidString, type: "contradiction", title: contradiction.title, body: "\(contradiction.summary)\n\(contradiction.resolutionNotes)")
            try insertHistoryEvent(HistoryEvent(
                entityType: "contradiction", entityID: contradiction.id.uuidString,
                eventType: "reviewed", title: contradiction.title, detail: contradiction.status.rawValue,
                recordedAt: contradiction.modifiedAt
            ))
        }
    }

    public func contradictionCases() throws -> [ContradictionCase] {
        try synchronized {
            try query("SELECT id,question_id,title,summary,status,resolution_notes,created_at,modified_at FROM contradiction_cases ORDER BY modified_at DESC") { row in
                ContradictionCase(
                    id: try row.uuid(0), questionID: row.optionalText(1).flatMap(UUID.init(uuidString:)),
                    title: row.text(2), summary: row.text(3), status: ContradictionCaseStatus(rawValue: row.text(4)) ?? .open,
                    resolutionNotes: row.text(5), createdAt: self.date(row.text(6)), modifiedAt: self.date(row.text(7))
                )
            }
        }
    }

    public func saveContradictionSource(_ source: ContradictionSource) throws {
        try synchronized {
            if let passageID = source.sourcePassageID {
                let passageLiteratureID = try query("SELECT literature_id FROM source_passages WHERE id=?", [.text(passageID)]) { try $0.uuid(0) }.first
                guard let passageLiteratureID else {
                    throw DatabaseError.invalidData("The selected contradiction source passage is no longer indexed.")
                }
                guard passageLiteratureID == source.literatureID else {
                    throw DatabaseError.invalidData("The contradiction source passage belongs to a different paper.")
                }
            }
            try execute("""
                INSERT INTO contradiction_sources(id,case_id,literature_id,source_passage_id,role,finding,contextual_difference,verification,created_at)
                VALUES(?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET literature_id=excluded.literature_id,source_passage_id=excluded.source_passage_id,
                    role=excluded.role,finding=excluded.finding,contextual_difference=excluded.contextual_difference,
                    verification=excluded.verification
                """, [
                    .text(source.id.uuidString), .text(source.caseID.uuidString), .text(source.literatureID.uuidString),
                    optionalText(source.sourcePassageID), .text(source.role), .text(source.finding),
                    .text(source.contextualDifference), .text(source.verification.rawValue),
                    .text(dateFormatter.string(from: source.createdAt))
                ])
        }
    }

    public func contradictionSources(caseID: UUID? = nil) throws -> [ContradictionSource] {
        try synchronized {
            var sql = "SELECT id,case_id,literature_id,source_passage_id,role,finding,contextual_difference,verification,created_at FROM contradiction_sources"
            var values: [SQLValue] = []
            if let caseID { sql += " WHERE case_id=?"; values = [.text(caseID.uuidString)] }
            sql += " ORDER BY created_at"
            return try query(sql, values) { row in
                ContradictionSource(
                    id: try row.uuid(0), caseID: try row.uuid(1), literatureID: try row.uuid(2),
                    sourcePassageID: row.optionalText(3), role: row.text(4), finding: row.text(5),
                    contextualDifference: row.text(6), verification: VerificationState(rawValue: row.text(7)) ?? .unverified,
                    createdAt: self.date(row.text(8))
                )
            }
        }
    }

    public func deleteContradictionSource(id: UUID) throws {
        try synchronized { try execute("DELETE FROM contradiction_sources WHERE id=?", [.text(id.uuidString)]) }
    }

    public func deleteContradictionCase(id: UUID) throws {
        try synchronized {
            try execute("DELETE FROM contradiction_cases WHERE id=?", [.text(id.uuidString)])
            try execute("DELETE FROM search_index WHERE entity_id=? AND entity_type='contradiction'", [.text(id.uuidString)])
        }
    }

    public func historyEvents(limit: Int = 500) throws -> [HistoryEvent] {
        try synchronized {
            try query("SELECT id,entity_type,entity_id,event_type,title,detail,recorded_at FROM history_events ORDER BY recorded_at DESC LIMIT ?", [.int(Int64(limit))]) { row in
                HistoryEvent(
                    id: try row.uuid(0), entityType: row.text(1), entityID: row.text(2), eventType: row.text(3),
                    title: row.text(4), detail: row.text(5), recordedAt: self.date(row.text(6))
                )
            }
        }
    }

    public func aiProviderConfiguration() throws -> AIProviderConfiguration {
        try synchronized {
            try query("""
                SELECT provider,endpoint,model,external_transmission_enabled,maximum_passages,
                       maximum_output_tokens,reasoning_effort,local_runtime_idle_minutes,modified_at
                FROM ai_provider_configuration WHERE singleton_id=1
                """) { row in
                AIProviderConfiguration(
                    provider: AIProviderKind(rawValue: row.text(0)) ?? .disabled,
                    endpoint: row.text(1), model: row.text(2), externalTransmissionEnabled: row.int(3) == 1,
                    maximumPassages: row.int(4), maximumOutputTokens: row.int(5),
                    reasoningEffort: AIReasoningEffort(rawValue: row.text(6)) ?? .medium,
                    localRuntimeIdleMinutes: row.int(7), modifiedAt: self.date(row.text(8))
                )
            }.first ?? AIProviderConfiguration()
        }
    }

    public func saveAIProviderConfiguration(_ configuration: AIProviderConfiguration) throws {
        guard (1...40).contains(configuration.maximumPassages),
              (128...16_000).contains(configuration.maximumOutputTokens),
              (1...120).contains(configuration.localRuntimeIdleMinutes) else {
            throw DatabaseError.invalidData("AI passage, output-token, or local-engine idle limits are outside the supported range.")
        }
        if configuration.provider != .disabled {
            guard let endpoint = URL(string: configuration.endpoint) else {
                throw DatabaseError.invalidData("The AI provider endpoint is not a valid URL.")
            }
            let configured = endpoint.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let official = configuration.provider.defaultEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if configuration.provider.isLocal {
                guard configured == official else {
                    throw DatabaseError.invalidData("Local AI providers are restricted to their fixed loopback endpoints.")
                }
            } else {
                guard endpoint.scheme?.lowercased() == "https" else {
                    throw DatabaseError.invalidData("Hosted AI provider endpoints must use HTTPS.")
                }
                if configuration.provider != .compatibleEndpoint, configured != official {
                    throw DatabaseError.invalidData("Direct provider credentials may only be sent to that provider's official API endpoint.")
                }
            }
            guard !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DatabaseError.invalidData("An AI model identifier is required.")
            }
        }
        try synchronized {
            try execute("""
                INSERT INTO ai_provider_configuration(
                    singleton_id,provider,endpoint,model,external_transmission_enabled,
                    maximum_passages,maximum_output_tokens,reasoning_effort,
                    local_runtime_idle_minutes,modified_at
                ) VALUES(1,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(singleton_id) DO UPDATE SET provider=excluded.provider,endpoint=excluded.endpoint,
                    model=excluded.model,external_transmission_enabled=excluded.external_transmission_enabled,
                    maximum_passages=excluded.maximum_passages,maximum_output_tokens=excluded.maximum_output_tokens,
                    reasoning_effort=excluded.reasoning_effort,
                    local_runtime_idle_minutes=excluded.local_runtime_idle_minutes,
                    modified_at=excluded.modified_at
                """, [
                    .text(configuration.provider.rawValue), .text(configuration.endpoint), .text(configuration.model),
                    .int(configuration.externalTransmissionEnabled ? 1 : 0), .int(Int64(configuration.maximumPassages)),
                    .int(Int64(configuration.maximumOutputTokens)), .text(configuration.reasoningEffort.rawValue),
                    .int(Int64(configuration.localRuntimeIdleMinutes)),
                    .text(dateFormatter.string(from: configuration.modifiedAt))
                ])
        }
    }

    public func saveAIAnalysis(
        _ analysis: AIAnalysis,
        citations: [AIAnalysisCitation],
        noteCitations: [AIAnalysisNoteCitation] = []
    ) throws {
        guard citations.allSatisfy({ $0.analysisID == analysis.id }) else {
            throw DatabaseError.invalidData("An AI citation was attached to the wrong analysis.")
        }
        guard noteCitations.allSatisfy({ $0.analysisID == analysis.id }) else {
            throw DatabaseError.invalidData("An AI note citation was attached to the wrong analysis.")
        }
        try synchronized {
            try execute("BEGIN IMMEDIATE")
            do {
                try execute("""
                    INSERT INTO ai_analyses(
                        id,kind,provider,model,prompt_version,retrieval_set_id,target_type,target_id,user_query,response_text,
                        structured_response_json,status,transmitted_passage_count,transmitted_character_count,
                        input_tokens,output_tokens,error_message,created_at,completed_at
                    ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET response_text=excluded.response_text,
                        structured_response_json=excluded.structured_response_json,status=excluded.status,
                        target_type=excluded.target_type,target_id=excluded.target_id,
                        transmitted_passage_count=excluded.transmitted_passage_count,
                        transmitted_character_count=excluded.transmitted_character_count,
                        input_tokens=excluded.input_tokens,output_tokens=excluded.output_tokens,
                        error_message=excluded.error_message,completed_at=excluded.completed_at
                    """, [
                        .text(analysis.id.uuidString), .text(analysis.kind.rawValue), .text(analysis.provider),
                        .text(analysis.model), .text(analysis.promptVersion), optionalText(analysis.retrievalSetID?.uuidString),
                        optionalText(analysis.targetType?.rawValue), optionalText(analysis.targetID?.uuidString),
                        .text(analysis.userQuery), .text(analysis.responseText), .text(analysis.structuredResponseJSON),
                        .text(analysis.status.rawValue), .int(Int64(analysis.transmittedPassageCount)),
                        .int(Int64(analysis.transmittedCharacterCount)), optionalInt(analysis.inputTokens),
                        optionalInt(analysis.outputTokens), optionalText(analysis.errorMessage),
                        .text(dateFormatter.string(from: analysis.createdAt)),
                        optionalText(analysis.completedAt.map { dateFormatter.string(from: $0) })
                    ])
                try execute("DELETE FROM ai_analysis_citations WHERE analysis_id=?", [.text(analysis.id.uuidString)])
                for citation in citations {
                    try execute("""
                        INSERT INTO ai_analysis_citations(
                            id,analysis_id,citation_label,source_passage_id,literature_id,page,quoted_passage,
                            source_document_hash,citation_status
                        ) VALUES(?,?,?,?,?,?,?,?,?)
                        """, [
                            .text(citation.id.uuidString), .text(citation.analysisID.uuidString), .text(citation.label),
                            .text(citation.sourcePassageID), .text(citation.literatureID.uuidString), .int(Int64(citation.page)),
                            .text(citation.quotedPassage), optionalText(citation.sourceDocumentHash),
                            .text(citation.citationStatus.rawValue)
                        ])
                }
                try execute("DELETE FROM ai_analysis_note_citations WHERE analysis_id=?", [.text(analysis.id.uuidString)])
                for citation in noteCitations {
                    try execute("""
                        INSERT INTO ai_analysis_note_citations(
                            id,analysis_id,citation_label,note_id,note_path,note_title,quoted_snippet,
                            source_modified_at,citation_status
                        ) VALUES(?,?,?,?,?,?,?,?,?)
                        """, [
                            .text(citation.id.uuidString), .text(citation.analysisID.uuidString), .text(citation.label),
                            .text(citation.noteID.uuidString), .text(citation.notePath), .text(citation.noteTitle),
                            .text(citation.quotedSnippet), .text(dateFormatter.string(from: citation.sourceModifiedAt)),
                            .text(citation.citationStatus.rawValue)
                        ])
                }
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    public func aiAnalyses() throws -> [AIAnalysis] {
        try synchronized {
            try query("""
                SELECT id,kind,provider,model,prompt_version,retrieval_set_id,target_type,target_id,user_query,response_text,
                       structured_response_json,status,transmitted_passage_count,transmitted_character_count,
                       input_tokens,output_tokens,error_message,created_at,completed_at
                FROM ai_analyses ORDER BY created_at DESC
                """) { row in
                AIAnalysis(
                    id: try row.uuid(0), kind: AIAnalysisKind(rawValue: row.text(1)) ?? .literatureAnswer,
                    provider: row.text(2), model: row.text(3), promptVersion: row.text(4),
                    retrievalSetID: row.optionalText(5).flatMap(UUID.init(uuidString:)),
                    targetType: row.optionalText(6).flatMap(AIAnalysisTargetType.init(rawValue:)),
                    targetID: row.optionalText(7).flatMap(UUID.init(uuidString:)), userQuery: row.text(8),
                    responseText: row.text(9), structuredResponseJSON: row.text(10),
                    status: AIAnalysisStatus(rawValue: row.text(11)) ?? .failed,
                    transmittedPassageCount: row.int(12), transmittedCharacterCount: row.int(13),
                    inputTokens: row.optionalInt(14), outputTokens: row.optionalInt(15), errorMessage: row.optionalText(16),
                    createdAt: self.date(row.text(17)), completedAt: row.optionalText(18).map(self.date)
                )
            }
        }
    }

    public func aiAnalysisCitations(analysisID: UUID? = nil) throws -> [AIAnalysisCitation] {
        try synchronized {
            var sql = """
                SELECT c.id,c.analysis_id,c.citation_label,c.source_passage_id,c.literature_id,c.page,
                       c.quoted_passage,c.source_document_hash,c.citation_status,p.id,p.passage_text,l.pdf_sha256
                FROM ai_analysis_citations c
                LEFT JOIN source_passages p ON p.id=c.source_passage_id
                LEFT JOIN literature_items l ON l.id=c.literature_id
                """
            var values: [SQLValue] = []
            if let analysisID { sql += " WHERE c.analysis_id=?"; values = [.text(analysisID.uuidString)] }
            sql += " ORDER BY c.analysis_id,c.citation_label"
            return try query(sql, values) { row in
                let status: RetrievalCitationStatus
                if row.optionalText(9) == nil { status = .sourceMissing }
                else if let hash = row.optionalText(7), hash != row.optionalText(11) { status = .documentChanged }
                else if row.text(6) != row.text(10) { status = .passageChanged }
                else { status = RetrievalCitationStatus(rawValue: row.text(8)) ?? .current }
                return AIAnalysisCitation(
                    id: try row.uuid(0), analysisID: try row.uuid(1), label: row.text(2), sourcePassageID: row.text(3),
                    literatureID: try row.uuid(4), page: row.int(5), quotedPassage: row.text(6),
                    sourceDocumentHash: row.optionalText(7), citationStatus: status
                )
            }
        }
    }

    public func aiAnalysisNoteCitations(analysisID: UUID? = nil) throws -> [AIAnalysisNoteCitation] {
        try synchronized {
            var sql = """
                SELECT c.id,c.analysis_id,c.citation_label,c.note_id,c.note_path,c.note_title,
                       c.quoted_snippet,c.source_modified_at,c.citation_status,n.id,n.content,n.modified_at
                FROM ai_analysis_note_citations c
                LEFT JOIN obsidian_notes n ON n.id=c.note_id
                """
            var values: [SQLValue] = []
            if let analysisID { sql += " WHERE c.analysis_id=?"; values = [.text(analysisID.uuidString)] }
            sql += " ORDER BY c.analysis_id,c.citation_label"
            return try query(sql, values) { row in
                let status: RetrievalCitationStatus
                if row.optionalText(9) == nil { status = .sourceMissing }
                else if !row.text(10).contains(row.text(6)) { status = .passageChanged }
                else { status = RetrievalCitationStatus(rawValue: row.text(8)) ?? .current }
                return AIAnalysisNoteCitation(
                    id: try row.uuid(0), analysisID: try row.uuid(1), label: row.text(2),
                    noteID: try row.uuid(3), notePath: row.text(4), noteTitle: row.text(5),
                    quotedSnippet: row.text(6), sourceModifiedAt: self.date(row.text(7)), citationStatus: status
                )
            }
        }
    }

    public func saveAnalysisReview(_ review: AnalysisReview) throws {
        try synchronized {
            try execute("""
                INSERT INTO analysis_reviews(id,analysis_id,decision,notes,reviewed_at) VALUES(?,?,?,?,?)
                ON CONFLICT(analysis_id) DO UPDATE SET decision=excluded.decision,notes=excluded.notes,reviewed_at=excluded.reviewed_at
                """, [
                    .text(review.id.uuidString), .text(review.analysisID.uuidString), .text(review.decision.rawValue),
                    .text(review.notes), .text(dateFormatter.string(from: review.reviewedAt))
                ])
        }
    }

    public func analysisReviews() throws -> [AnalysisReview] {
        try synchronized {
            try query("SELECT id,analysis_id,decision,notes,reviewed_at FROM analysis_reviews ORDER BY reviewed_at DESC") { row in
                AnalysisReview(
                    id: try row.uuid(0), analysisID: try row.uuid(1),
                    decision: AnalysisReviewDecision(rawValue: row.text(2)) ?? .pending,
                    notes: row.text(3), reviewedAt: self.date(row.text(4))
                )
            }
        }
    }

    public func saveBiasAudit(_ audit: BiasAudit) throws {
        try synchronized {
            try execute("""
                INSERT INTO bias_audits(id,argument_id,title,scope_note,origin,analysis_id,created_at)
                VALUES(?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET title=excluded.title,scope_note=excluded.scope_note,
                    origin=excluded.origin,analysis_id=excluded.analysis_id
                """, [
                    .text(audit.id.uuidString), .text(audit.argumentID.uuidString), .text(audit.title),
                    .text(audit.scopeNote), .text(audit.origin.rawValue), optionalText(audit.analysisID?.uuidString),
                    .text(dateFormatter.string(from: audit.createdAt))
                ])
            try insertHistoryEvent(HistoryEvent(
                entityType: "bias-audit", entityID: audit.id.uuidString, eventType: "created",
                title: audit.title, detail: audit.scopeNote, recordedAt: audit.createdAt
            ))
        }
    }

    public func biasAudits(argumentID: UUID? = nil) throws -> [BiasAudit] {
        try synchronized {
            var sql = "SELECT id,argument_id,title,scope_note,origin,analysis_id,created_at FROM bias_audits"
            var values: [SQLValue] = []
            if let argumentID { sql += " WHERE argument_id=?"; values = [.text(argumentID.uuidString)] }
            sql += " ORDER BY created_at DESC"
            return try query(sql, values) { row in
                BiasAudit(
                    id: try row.uuid(0), argumentID: try row.uuid(1), title: row.text(2), scopeNote: row.text(3),
                    origin: RecordOrigin(rawValue: row.text(4)) ?? .user,
                    analysisID: row.optionalText(5).flatMap(UUID.init(uuidString:)), createdAt: self.date(row.text(6))
                )
            }
        }
    }

    public func saveBiasConcern(_ concern: BiasConcern) throws {
        try synchronized {
            let auditArgumentIDs = try query(
                "SELECT argument_id FROM bias_audits WHERE id=?",
                [.text(concern.auditID.uuidString)],
                map: { UUID(uuidString: $0.text(0)) }
            )
            guard let argumentID = auditArgumentIDs.first ?? nil else {
                throw DatabaseError.invalidData("The bias audit no longer exists.")
            }
            for evidenceID in concern.evidenceRelationshipIDs {
                let matches = try query(
                    "SELECT COUNT(*) FROM evidence_relationships WHERE id=? AND argument_id=?",
                    [.text(evidenceID.uuidString), .text(argumentID.uuidString)]
                ) { $0.int(0) }.first ?? 0
                guard matches == 1 else { throw DatabaseError.invalidData("A bias concern referenced evidence from a different argument.") }
            }
            try execute("BEGIN IMMEDIATE")
            do {
                try execute("""
                    INSERT INTO bias_concerns(
                        id,audit_id,kind,potential_problem,why_it_matters,alternative_interpretations,
                        investigation_questions_json,uncertainty,origin,disposition,review_notes,created_at,modified_at
                    ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET kind=excluded.kind,potential_problem=excluded.potential_problem,
                        why_it_matters=excluded.why_it_matters,alternative_interpretations=excluded.alternative_interpretations,
                        investigation_questions_json=excluded.investigation_questions_json,uncertainty=excluded.uncertainty,
                        disposition=excluded.disposition,review_notes=excluded.review_notes,modified_at=excluded.modified_at
                    """, [
                        .text(concern.id.uuidString), .text(concern.auditID.uuidString), .text(concern.kind.rawValue),
                        .text(concern.potentialProblem), .text(concern.whyItMatters), .text(concern.alternativeInterpretations),
                        .text(json(concern.investigationQuestions)), .text(concern.uncertainty), .text(concern.origin.rawValue),
                        .text(concern.disposition.rawValue), .text(concern.reviewNotes),
                        .text(dateFormatter.string(from: concern.createdAt)), .text(dateFormatter.string(from: concern.modifiedAt))
                    ])
                try execute("DELETE FROM bias_concern_evidence WHERE concern_id=?", [.text(concern.id.uuidString)])
                for evidenceID in concern.evidenceRelationshipIDs {
                    try execute(
                        "INSERT INTO bias_concern_evidence(concern_id,evidence_relationship_id) VALUES(?,?)",
                        [.text(concern.id.uuidString), .text(evidenceID.uuidString)]
                    )
                }
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    public func biasConcerns(auditID: UUID? = nil) throws -> [BiasConcern] {
        try synchronized {
            var sql = """
                SELECT id,audit_id,kind,potential_problem,why_it_matters,alternative_interpretations,
                       investigation_questions_json,uncertainty,origin,disposition,review_notes,created_at,modified_at
                FROM bias_concerns
                """
            var values: [SQLValue] = []
            if let auditID { sql += " WHERE audit_id=?"; values = [.text(auditID.uuidString)] }
            sql += " ORDER BY created_at"
            let records = try query(sql, values) { row in
                BiasConcern(
                    id: try row.uuid(0), auditID: try row.uuid(1),
                    kind: BiasConcernKind(rawValue: row.text(2)) ?? .evidenceScope,
                    potentialProblem: row.text(3), whyItMatters: row.text(4), alternativeInterpretations: row.text(5),
                    investigationQuestions: self.stringArray(row.text(6)), uncertainty: row.text(7),
                    origin: RecordOrigin(rawValue: row.text(8)) ?? .user,
                    disposition: ReviewDisposition(rawValue: row.text(9)) ?? .pending, reviewNotes: row.text(10),
                    createdAt: self.date(row.text(11)), modifiedAt: self.date(row.text(12))
                )
            }
            return try records.map { record in
                var updated = record
                updated.evidenceRelationshipIDs = try query(
                    "SELECT evidence_relationship_id FROM bias_concern_evidence WHERE concern_id=? ORDER BY evidence_relationship_id",
                    [.text(record.id.uuidString)]
                ) { try $0.uuid(0) }
                return updated
            }
        }
    }

    public func deleteBiasAudit(id: UUID) throws {
        try synchronized { try execute("DELETE FROM bias_audits WHERE id=?", [.text(id.uuidString)]) }
    }

    public func saveDeliberationSession(_ session: DeliberationSession) throws {
        try synchronized {
            try execute("""
                INSERT INTO deliberation_sessions(
                    id,argument_id,title,provider,model,prompt_version,disclosure,status,created_at,completed_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET title=excluded.title,provider=excluded.provider,model=excluded.model,
                    prompt_version=excluded.prompt_version,disclosure=excluded.disclosure,status=excluded.status,
                    completed_at=excluded.completed_at
                """, [
                    .text(session.id.uuidString), .text(session.argumentID.uuidString), .text(session.title),
                    .text(session.provider), .text(session.model), .text(session.promptVersion), .text(session.disclosure),
                    .text(session.status.rawValue), .text(dateFormatter.string(from: session.createdAt)),
                    optionalText(session.completedAt.map { dateFormatter.string(from: $0) })
                ])
        }
    }

    public func deliberationSessions(argumentID: UUID? = nil) throws -> [DeliberationSession] {
        try synchronized {
            var sql = "SELECT id,argument_id,title,provider,model,prompt_version,disclosure,status,created_at,completed_at FROM deliberation_sessions"
            var values: [SQLValue] = []
            if let argumentID { sql += " WHERE argument_id=?"; values = [.text(argumentID.uuidString)] }
            sql += " ORDER BY created_at DESC"
            return try query(sql, values) { row in
                DeliberationSession(
                    id: try row.uuid(0), argumentID: try row.uuid(1), title: row.text(2), provider: row.text(3),
                    model: row.text(4), promptVersion: row.text(5), disclosure: row.text(6),
                    status: DeliberationStatus(rawValue: row.text(7)) ?? .failed,
                    createdAt: self.date(row.text(8)), completedAt: row.optionalText(9).map(self.date)
                )
            }
        }
    }

    public func saveDeliberationMessage(_ message: DeliberationMessage, citations: [DeliberationCitation] = []) throws {
        guard citations.allSatisfy({ $0.messageID == message.id }) else {
            throw DatabaseError.invalidData("A deliberation citation was attached to the wrong message.")
        }
        if message.modelGenerated && message.perspective == .user {
            throw DatabaseError.invalidData("A researcher response cannot be marked as model-generated.")
        }
        try synchronized {
            for citation in citations {
                let passage = try query(
                    "SELECT literature_id,passage_text FROM source_passages WHERE id=?",
                    [.text(citation.sourcePassageID)]
                ) { ($0.text(0), $0.text(1)) }.first
                guard passage?.0 == citation.literatureID.uuidString, passage?.1 == citation.quotedPassage else {
                    throw DatabaseError.invalidData("A deliberation citation did not match its exact indexed source passage.")
                }
            }
            try execute("BEGIN IMMEDIATE")
            do {
                try execute("""
                    INSERT INTO deliberation_messages(id,session_id,perspective,phase,content,sequence,model_generated,created_at)
                    VALUES(?,?,?,?,?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET perspective=excluded.perspective,phase=excluded.phase,
                        content=excluded.content,sequence=excluded.sequence,model_generated=excluded.model_generated
                    """, [
                        .text(message.id.uuidString), .text(message.sessionID.uuidString), .text(message.perspective.rawValue),
                        .text(message.phase.rawValue), .text(message.content), .int(Int64(message.sequence)),
                        .int(message.modelGenerated ? 1 : 0), .text(dateFormatter.string(from: message.createdAt))
                    ])
                try execute("DELETE FROM deliberation_citations WHERE message_id=?", [.text(message.id.uuidString)])
                for citation in citations {
                    try execute("""
                        INSERT INTO deliberation_citations(
                            id,message_id,citation_label,literature_id,source_passage_id,page,quoted_passage,
                            source_document_hash,citation_status
                        ) VALUES(?,?,?,?,?,?,?,?,?)
                        """, [
                            .text(citation.id.uuidString), .text(citation.messageID.uuidString), .text(citation.label),
                            .text(citation.literatureID.uuidString), .text(citation.sourcePassageID), .int(Int64(citation.page)),
                            .text(citation.quotedPassage), optionalText(citation.sourceDocumentHash),
                            .text(citation.citationStatus.rawValue)
                        ])
                }
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    public func deliberationMessages(sessionID: UUID? = nil) throws -> [DeliberationMessage] {
        try synchronized {
            var sql = "SELECT id,session_id,perspective,phase,content,sequence,model_generated,created_at FROM deliberation_messages"
            var values: [SQLValue] = []
            if let sessionID { sql += " WHERE session_id=?"; values = [.text(sessionID.uuidString)] }
            sql += " ORDER BY session_id,sequence"
            return try query(sql, values) { row in
                DeliberationMessage(
                    id: try row.uuid(0), sessionID: try row.uuid(1),
                    perspective: DeliberationPerspective(rawValue: row.text(2)) ?? .user,
                    phase: DeliberationPhase(rawValue: row.text(3)) ?? .initial,
                    content: row.text(4), sequence: row.int(5), modelGenerated: row.int(6) == 1,
                    createdAt: self.date(row.text(7))
                )
            }
        }
    }

    public func deliberationCitations(messageID: UUID? = nil) throws -> [DeliberationCitation] {
        try synchronized {
            var sql = """
                SELECT c.id,c.message_id,c.citation_label,c.literature_id,c.source_passage_id,c.page,
                       c.quoted_passage,c.source_document_hash,c.citation_status,p.id,p.passage_text,l.pdf_sha256
                FROM deliberation_citations c
                LEFT JOIN source_passages p ON p.id=c.source_passage_id
                LEFT JOIN literature_items l ON l.id=c.literature_id
                """
            var values: [SQLValue] = []
            if let messageID { sql += " WHERE c.message_id=?"; values = [.text(messageID.uuidString)] }
            sql += " ORDER BY c.message_id,c.citation_label"
            return try query(sql, values) { row in
                let status: RetrievalCitationStatus
                if row.optionalText(9) == nil { status = .sourceMissing }
                else if let hash = row.optionalText(7), hash != row.optionalText(11) { status = .documentChanged }
                else if row.text(6) != row.text(10) { status = .passageChanged }
                else { status = RetrievalCitationStatus(rawValue: row.text(8)) ?? .current }
                return DeliberationCitation(
                    id: try row.uuid(0), messageID: try row.uuid(1), label: row.text(2),
                    literatureID: try row.uuid(3), sourcePassageID: row.text(4), page: row.int(5),
                    quotedPassage: row.text(6), sourceDocumentHash: row.optionalText(7), citationStatus: status
                )
            }
        }
    }

    public func deleteDeliberationSession(id: UUID) throws {
        try synchronized { try execute("DELETE FROM deliberation_sessions WHERE id=?", [.text(id.uuidString)]) }
    }

    public func saveWritingDocument(_ document: WritingDocument) throws {
        try synchronized {
            if let questionID = document.questionID, let projectID = document.projectID {
                let belongs = try query(
                    "SELECT COUNT(*) FROM research_questions WHERE id=? AND project_id=?",
                    [.text(questionID.uuidString), .text(projectID.uuidString)]
                ) { $0.int(0) }.first ?? 0
                guard belongs == 1 else { throw DatabaseError.invalidData("The writing workspace question does not belong to its selected project.") }
            }
            let existed = (try query("SELECT COUNT(*) FROM writing_documents WHERE id=?", [.text(document.id.uuidString)]) { $0.int(0) }.first ?? 0) == 1
            try execute("""
                INSERT INTO writing_documents(id,project_id,question_id,title,purpose,status,notes,created_at,modified_at)
                VALUES(?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET project_id=excluded.project_id,question_id=excluded.question_id,
                    title=excluded.title,purpose=excluded.purpose,status=excluded.status,notes=excluded.notes,
                    modified_at=excluded.modified_at
                """, [
                    .text(document.id.uuidString), optionalText(document.projectID?.uuidString), optionalText(document.questionID?.uuidString),
                    .text(document.title), .text(document.purpose.rawValue), .text(document.status), .text(document.notes),
                    .text(dateFormatter.string(from: document.createdAt)), .text(dateFormatter.string(from: document.modifiedAt))
                ])
            try replaceSearchIndex(entityID: document.id.uuidString, type: "writing", title: document.title, body: document.notes)
            try insertHistoryEvent(HistoryEvent(
                entityType: "writing", entityID: document.id.uuidString, eventType: existed ? "updated" : "created",
                title: document.title, detail: "\(document.purpose.rawValue) · \(document.status)", recordedAt: document.modifiedAt
            ))
        }
    }

    public func writingDocuments() throws -> [WritingDocument] {
        try synchronized {
            try query("SELECT id,project_id,question_id,title,purpose,status,notes,created_at,modified_at FROM writing_documents ORDER BY modified_at DESC") { row in
                WritingDocument(
                    id: try row.uuid(0), projectID: row.optionalText(1).flatMap(UUID.init(uuidString:)),
                    questionID: row.optionalText(2).flatMap(UUID.init(uuidString:)), title: row.text(3),
                    purpose: WritingPurpose(rawValue: row.text(4)) ?? .researchNote, status: row.text(5), notes: row.text(6),
                    createdAt: self.date(row.text(7)), modifiedAt: self.date(row.text(8))
                )
            }
        }
    }

    public func deleteWritingDocument(id: UUID) throws {
        try synchronized {
            let sectionIDs = try query("SELECT id FROM writing_sections WHERE document_id=?", [.text(id.uuidString)]) { $0.text(0) }
            for sectionID in sectionIDs { try execute("DELETE FROM search_index WHERE entity_id=? AND entity_type='writing-section'", [.text(sectionID)]) }
            try execute("DELETE FROM search_index WHERE entity_id=? AND entity_type='writing'", [.text(id.uuidString)])
            try execute("DELETE FROM writing_documents WHERE id=?", [.text(id.uuidString)])
        }
    }

    public func saveWritingSection(_ section: WritingSection) throws {
        try synchronized {
            try execute("""
                INSERT INTO writing_sections(id,document_id,title,body,position,notes,created_at,modified_at)
                VALUES(?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET title=excluded.title,body=excluded.body,position=excluded.position,
                    notes=excluded.notes,modified_at=excluded.modified_at
                """, [
                    .text(section.id.uuidString), .text(section.documentID.uuidString), .text(section.title), .text(section.body),
                    .int(Int64(section.position)), .text(section.notes), .text(dateFormatter.string(from: section.createdAt)),
                    .text(dateFormatter.string(from: section.modifiedAt))
                ])
            try replaceSearchIndex(entityID: section.id.uuidString, type: "writing-section", title: section.title, body: "\(section.body)\n\(section.notes)")
        }
    }

    public func writingSections(documentID: UUID? = nil) throws -> [WritingSection] {
        try synchronized {
            var sql = "SELECT id,document_id,title,body,position,notes,created_at,modified_at FROM writing_sections"
            var values: [SQLValue] = []
            if let documentID { sql += " WHERE document_id=?"; values = [.text(documentID.uuidString)] }
            sql += " ORDER BY document_id,position"
            return try query(sql, values) { row in
                WritingSection(
                    id: try row.uuid(0), documentID: try row.uuid(1), title: row.text(2), body: row.text(3),
                    position: row.int(4), notes: row.text(5), createdAt: self.date(row.text(6)), modifiedAt: self.date(row.text(7))
                )
            }
        }
    }

    public func deleteWritingSection(id: UUID) throws {
        try synchronized {
            try execute("DELETE FROM search_index WHERE entity_id=? AND entity_type='writing-section'", [.text(id.uuidString)])
            try execute("DELETE FROM writing_sections WHERE id=?", [.text(id.uuidString)])
        }
    }

    public func saveWritingEvidenceLink(_ link: WritingEvidenceLink) throws {
        try synchronized {
            guard try writingTargetExists(type: link.targetType, id: link.targetID) else {
                throw DatabaseError.invalidData("The writing evidence target no longer exists.")
            }
            try execute("""
                INSERT INTO writing_evidence_links(id,section_id,target_type,target_id,citation_key,rationale,created_at)
                VALUES(?,?,?,?,?,?,?)
                ON CONFLICT(section_id,target_type,target_id) DO UPDATE SET citation_key=excluded.citation_key,rationale=excluded.rationale
                """, [
                    .text(link.id.uuidString), .text(link.sectionID.uuidString), .text(link.targetType.rawValue),
                    .text(link.targetID), optionalText(link.citationKey), .text(link.rationale),
                    .text(dateFormatter.string(from: link.createdAt))
                ])
        }
    }

    public func writingEvidenceLinks(sectionID: UUID? = nil) throws -> [WritingEvidenceLink] {
        try synchronized {
            var sql = "SELECT id,section_id,target_type,target_id,citation_key,rationale,created_at FROM writing_evidence_links"
            var values: [SQLValue] = []
            if let sectionID { sql += " WHERE section_id=?"; values = [.text(sectionID.uuidString)] }
            sql += " ORDER BY created_at"
            return try query(sql, values) { row in
                WritingEvidenceLink(
                    id: try row.uuid(0), sectionID: try row.uuid(1),
                    targetType: WritingEvidenceTargetType(rawValue: row.text(2)) ?? .claim,
                    targetID: row.text(3), citationKey: row.optionalText(4), rationale: row.text(5),
                    createdAt: self.date(row.text(6))
                )
            }
        }
    }

    public func deleteWritingEvidenceLink(id: UUID) throws {
        try synchronized { try execute("DELETE FROM writing_evidence_links WHERE id=?", [.text(id.uuidString)]) }
    }

    public func saveCitationSupportReview(_ review: CitationSupportReview) throws {
        if review.origin == .aiSuggested {
            guard review.modelIdentifier?.nilIfEmpty != nil, review.promptVersion?.nilIfEmpty != nil else {
                throw DatabaseError.invalidData("An AI citation review requires model and prompt provenance.")
            }
        }
        try synchronized {
            try execute("""
                INSERT INTO citation_support_reviews(
                    id,section_id,statement,evidence_link_id,assessment,concern,origin,model_identifier,
                    prompt_version,review_notes,created_at,modified_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET statement=excluded.statement,evidence_link_id=excluded.evidence_link_id,
                    assessment=excluded.assessment,concern=excluded.concern,review_notes=excluded.review_notes,
                    modified_at=excluded.modified_at
                """, [
                    .text(review.id.uuidString), .text(review.sectionID.uuidString), .text(review.statement),
                    optionalText(review.evidenceLinkID?.uuidString), .text(review.assessment.rawValue), .text(review.concern),
                    .text(review.origin.rawValue), optionalText(review.modelIdentifier), optionalText(review.promptVersion),
                    .text(review.reviewNotes), .text(dateFormatter.string(from: review.createdAt)),
                    .text(dateFormatter.string(from: review.modifiedAt))
                ])
        }
    }

    public func citationSupportReviews(sectionID: UUID? = nil) throws -> [CitationSupportReview] {
        try synchronized {
            var sql = """
                SELECT id,section_id,statement,evidence_link_id,assessment,concern,origin,model_identifier,
                       prompt_version,review_notes,created_at,modified_at FROM citation_support_reviews
                """
            var values: [SQLValue] = []
            if let sectionID { sql += " WHERE section_id=?"; values = [.text(sectionID.uuidString)] }
            sql += " ORDER BY modified_at DESC"
            return try query(sql, values) { row in
                CitationSupportReview(
                    id: try row.uuid(0), sectionID: try row.uuid(1), statement: row.text(2),
                    evidenceLinkID: row.optionalText(3).flatMap(UUID.init(uuidString:)),
                    assessment: CitationSupportAssessment(rawValue: row.text(4)) ?? .pending,
                    concern: row.text(5), origin: RecordOrigin(rawValue: row.text(6)) ?? .user,
                    modelIdentifier: row.optionalText(7), promptVersion: row.optionalText(8), reviewNotes: row.text(9),
                    createdAt: self.date(row.text(10)), modifiedAt: self.date(row.text(11))
                )
            }
        }
    }

    public func deleteCitationSupportReview(id: UUID) throws {
        try synchronized { try execute("DELETE FROM citation_support_reviews WHERE id=?", [.text(id.uuidString)]) }
    }

    public func saveCollectiveExperiment(_ experiment: CollectiveExperiment) throws {
        guard let settingsData = experiment.modelSettingsJSON.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: settingsData)) is [String: Any] else {
            throw DatabaseError.invalidData("Collective-lab model settings must be a JSON object.")
        }
        try synchronized {
            try execute("""
                INSERT INTO collective_experiments(
                    id,title,research_purpose,task_instructions,interaction_mode,provider,model,
                    model_settings_json,prompt_version,status,validation_note,created_at,completed_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET title=excluded.title,research_purpose=excluded.research_purpose,
                    task_instructions=excluded.task_instructions,interaction_mode=excluded.interaction_mode,
                    provider=excluded.provider,model=excluded.model,model_settings_json=excluded.model_settings_json,
                    prompt_version=excluded.prompt_version,status=excluded.status,validation_note=excluded.validation_note,
                    completed_at=excluded.completed_at
                """, [
                    .text(experiment.id.uuidString), .text(experiment.title), .text(experiment.researchPurpose),
                    .text(experiment.taskInstructions), .text(experiment.interactionMode.rawValue), .text(experiment.provider),
                    .text(experiment.model), .text(experiment.modelSettingsJSON), .text(experiment.promptVersion),
                    .text(experiment.status.rawValue), .text(experiment.validationNote),
                    .text(dateFormatter.string(from: experiment.createdAt)),
                    optionalText(experiment.completedAt.map { dateFormatter.string(from: $0) })
                ])
        }
    }

    public func collectiveExperiments() throws -> [CollectiveExperiment] {
        try synchronized {
            try query("""
                SELECT id,title,research_purpose,task_instructions,interaction_mode,provider,model,
                       model_settings_json,prompt_version,status,validation_note,created_at,completed_at
                FROM collective_experiments ORDER BY created_at DESC
                """) { row in
                CollectiveExperiment(
                    id: try row.uuid(0), title: row.text(1), researchPurpose: row.text(2), taskInstructions: row.text(3),
                    interactionMode: CollectiveInteractionMode(rawValue: row.text(4)) ?? .independent,
                    provider: row.text(5), model: row.text(6), modelSettingsJSON: row.text(7), promptVersion: row.text(8),
                    status: CollectiveExperimentStatus(rawValue: row.text(9)) ?? .interrupted,
                    validationNote: row.text(10), createdAt: self.date(row.text(11)),
                    completedAt: row.optionalText(12).map(self.date)
                )
            }
        }
    }

    public func saveCollectiveAgent(_ agent: CollectiveAgent) throws {
        try synchronized {
            try execute("""
                INSERT INTO collective_agents(id,experiment_id,label,role,information_available,position,created_at)
                VALUES(?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET label=excluded.label,role=excluded.role,
                    information_available=excluded.information_available,position=excluded.position
                """, [
                    .text(agent.id.uuidString), .text(agent.experimentID.uuidString), .text(agent.label),
                    .text(agent.role), .text(agent.informationAvailable), .int(Int64(agent.position)),
                    .text(dateFormatter.string(from: agent.createdAt))
                ])
        }
    }

    public func collectiveAgents(experimentID: UUID? = nil) throws -> [CollectiveAgent] {
        try synchronized {
            var sql = "SELECT id,experiment_id,label,role,information_available,position,created_at FROM collective_agents"
            var values: [SQLValue] = []
            if let experimentID { sql += " WHERE experiment_id=?"; values = [.text(experimentID.uuidString)] }
            sql += " ORDER BY experiment_id,position"
            return try query(sql, values) { row in
                CollectiveAgent(
                    id: try row.uuid(0), experimentID: try row.uuid(1), label: row.text(2), role: row.text(3),
                    informationAvailable: row.text(4), position: row.int(5), createdAt: self.date(row.text(6))
                )
            }
        }
    }

    public func deleteCollectiveAgent(id: UUID) throws {
        try synchronized { try execute("DELETE FROM collective_agents WHERE id=?", [.text(id.uuidString)]) }
    }

    public func saveCollectiveTurn(_ turn: CollectiveTurn, citations: [CollectiveTurnCitation] = []) throws {
        guard citations.allSatisfy({ $0.turnID == turn.id }) else {
            throw DatabaseError.invalidData("A collective-lab citation was attached to the wrong turn.")
        }
        if let confidence = turn.confidence, !(0...1).contains(confidence) {
            throw DatabaseError.invalidData("Collective-lab confidence must be between 0 and 1.")
        }
        try synchronized {
            if let agentID = turn.agentID {
                let belongs = try query(
                    "SELECT COUNT(*) FROM collective_agents WHERE id=? AND experiment_id=?",
                    [.text(agentID.uuidString), .text(turn.experimentID.uuidString)]
                ) { $0.int(0) }.first ?? 0
                guard belongs == 1 else { throw DatabaseError.invalidData("The selected agent belongs to a different experiment.") }
            }
            if turn.modelGenerated {
                let configured = try query(
                    "SELECT provider,model FROM collective_experiments WHERE id=?",
                    [.text(turn.experimentID.uuidString)]
                ) { ($0.text(0), $0.text(1)) }.first
                guard let configured, configured.0 != "Not configured", configured.1 != "Not configured" else {
                    throw DatabaseError.invalidData("A model-generated turn requires recorded provider and model identifiers.")
                }
            }
            for citation in citations {
                let passage = try query(
                    "SELECT literature_id,passage_text FROM source_passages WHERE id=?",
                    [.text(citation.sourcePassageID)]
                ) { ($0.text(0), $0.text(1)) }.first
                guard passage?.0 == citation.literatureID.uuidString, passage?.1 == citation.quotedPassage else {
                    throw DatabaseError.invalidData("A collective-lab citation did not match its exact indexed source passage.")
                }
            }
            try execute("BEGIN IMMEDIATE")
            do {
                try execute("""
                    INSERT INTO collective_turns(
                        id,experiment_id,agent_id,round_number,sequence,kind,information_available,
                        prompt_text,response_text,confidence,model_generated,error_message,created_at
                    ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET agent_id=excluded.agent_id,round_number=excluded.round_number,
                        sequence=excluded.sequence,kind=excluded.kind,information_available=excluded.information_available,
                        prompt_text=excluded.prompt_text,response_text=excluded.response_text,confidence=excluded.confidence,
                        model_generated=excluded.model_generated,error_message=excluded.error_message
                    """, [
                        .text(turn.id.uuidString), .text(turn.experimentID.uuidString), optionalText(turn.agentID?.uuidString),
                        .int(Int64(turn.round)), .int(Int64(turn.sequence)), .text(turn.kind.rawValue),
                        .text(turn.informationAvailable), .text(turn.promptText), .text(turn.responseText),
                        turn.confidence.map(SQLValue.double) ?? .null, .int(turn.modelGenerated ? 1 : 0),
                        optionalText(turn.errorMessage), .text(dateFormatter.string(from: turn.createdAt))
                    ])
                try execute("DELETE FROM collective_turn_citations WHERE turn_id=?", [.text(turn.id.uuidString)])
                for citation in citations {
                    try execute("""
                        INSERT INTO collective_turn_citations(
                            id,turn_id,citation_label,literature_id,source_passage_id,page,quoted_passage,
                            source_document_hash,citation_status
                        ) VALUES(?,?,?,?,?,?,?,?,?)
                        """, [
                            .text(citation.id.uuidString), .text(citation.turnID.uuidString), .text(citation.label),
                            .text(citation.literatureID.uuidString), .text(citation.sourcePassageID), .int(Int64(citation.page)),
                            .text(citation.quotedPassage), optionalText(citation.sourceDocumentHash), .text(citation.citationStatus.rawValue)
                        ])
                }
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    public func collectiveTurns(experimentID: UUID? = nil) throws -> [CollectiveTurn] {
        try synchronized {
            var sql = """
                SELECT id,experiment_id,agent_id,round_number,sequence,kind,information_available,
                       prompt_text,response_text,confidence,model_generated,error_message,created_at
                FROM collective_turns
                """
            var values: [SQLValue] = []
            if let experimentID { sql += " WHERE experiment_id=?"; values = [.text(experimentID.uuidString)] }
            sql += " ORDER BY experiment_id,sequence"
            return try query(sql, values) { row in
                CollectiveTurn(
                    id: try row.uuid(0), experimentID: try row.uuid(1),
                    agentID: row.optionalText(2).flatMap(UUID.init(uuidString:)), round: row.int(3), sequence: row.int(4),
                    kind: CollectiveTurnKind(rawValue: row.text(5)) ?? .interruption,
                    informationAvailable: row.text(6), promptText: row.text(7), responseText: row.text(8),
                    confidence: row.optionalDouble(9), modelGenerated: row.int(10) == 1,
                    errorMessage: row.optionalText(11), createdAt: self.date(row.text(12))
                )
            }
        }
    }

    public func collectiveTurnCitations(turnID: UUID? = nil) throws -> [CollectiveTurnCitation] {
        try synchronized {
            var sql = """
                SELECT c.id,c.turn_id,c.citation_label,c.literature_id,c.source_passage_id,c.page,
                       c.quoted_passage,c.source_document_hash,c.citation_status,p.id,p.passage_text,l.pdf_sha256
                FROM collective_turn_citations c
                LEFT JOIN source_passages p ON p.id=c.source_passage_id
                LEFT JOIN literature_items l ON l.id=c.literature_id
                """
            var values: [SQLValue] = []
            if let turnID { sql += " WHERE c.turn_id=?"; values = [.text(turnID.uuidString)] }
            sql += " ORDER BY c.turn_id,c.citation_label"
            return try query(sql, values) { row in
                let status: RetrievalCitationStatus
                if row.optionalText(9) == nil { status = .sourceMissing }
                else if let hash = row.optionalText(7), hash != row.optionalText(11) { status = .documentChanged }
                else if row.text(6) != row.text(10) { status = .passageChanged }
                else { status = RetrievalCitationStatus(rawValue: row.text(8)) ?? .current }
                return CollectiveTurnCitation(
                    id: try row.uuid(0), turnID: try row.uuid(1), label: row.text(2), literatureID: try row.uuid(3),
                    sourcePassageID: row.text(4), page: row.int(5), quotedPassage: row.text(6),
                    sourceDocumentHash: row.optionalText(7), citationStatus: status
                )
            }
        }
    }

    public func deleteCollectiveTurn(id: UUID) throws {
        try synchronized { try execute("DELETE FROM collective_turns WHERE id=?", [.text(id.uuidString)]) }
    }

    public func deleteCollectiveExperiment(id: UUID) throws {
        try synchronized { try execute("DELETE FROM collective_experiments WHERE id=?", [.text(id.uuidString)]) }
    }

    public func saveIndexingJob(_ job: IndexingJob) throws {
        try synchronized {
            try execute("""
                INSERT INTO indexing_jobs(id,kind,source_name,status,completed_units,total_units,failure_message,created_at,updated_at)
                VALUES(?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET status=excluded.status,completed_units=excluded.completed_units,
                    total_units=excluded.total_units,failure_message=excluded.failure_message,updated_at=excluded.updated_at
                """, [
                    .text(job.id.uuidString), .text(job.kind.rawValue), .text(job.sourceName), .text(job.status.rawValue),
                    .int(Int64(job.completedUnits)), optionalInt(job.totalUnits), optionalText(job.failureMessage),
                    .text(dateFormatter.string(from: job.createdAt)), .text(dateFormatter.string(from: job.updatedAt))
                ])
        }
    }

    public func indexingJobs(limit: Int = 50) throws -> [IndexingJob] {
        try synchronized {
            try query("""
                SELECT id,kind,source_name,status,completed_units,total_units,failure_message,created_at,updated_at
                FROM indexing_jobs ORDER BY updated_at DESC LIMIT ?
                """, [.int(Int64(limit))]) { row in
                IndexingJob(
                    id: try row.uuid(0), kind: IndexingJobKind(rawValue: row.text(1)) ?? .pdf,
                    sourceName: row.text(2), status: IndexingJobStatus(rawValue: row.text(3)) ?? .failed,
                    completedUnits: row.int(4), totalUnits: row.optionalInt(5), failureMessage: row.optionalText(6),
                    createdAt: self.date(row.text(7)), updatedAt: self.date(row.text(8))
                )
            }
        }
    }

    public func markInterruptedIndexingJobs() throws {
        try synchronized {
            try execute("""
                UPDATE indexing_jobs
                SET status=?,failure_message=?,updated_at=?
                WHERE status IN (?,?)
                """, [
                    .text(IndexingJobStatus.failed.rawValue),
                    .text("The application closed before this indexing job completed. No completion was assumed."),
                    .text(dateFormatter.string(from: Date())),
                    .text(IndexingJobStatus.queued.rawValue), .text(IndexingJobStatus.running.rawValue)
                ])
        }
    }

    public func exportBundle() throws -> ResearchExportBundle {
        try synchronized {
            ResearchExportBundle(
                literature: try literatureItems(),
                notes: try obsidianNotes(),
                noteLinks: try noteLinks(),
                projects: try projects(),
                questions: try questions(),
                arguments: try arguments(),
                argumentVersions: try argumentVersions(),
                evidence: try allEvidence(),
                zoteroLibraries: try zoteroLibraries(),
                zoteroCollections: try zoteroCollections(),
                literatureCollectionMemberships: try literatureCollectionMemberships(),
                comparisonProfiles: try comparisonProfiles(),
                retrievalSets: try retrievalSets(),
                retrievedPassages: try retrievedPassages(),
                retrievedNoteSnippets: try retrievedNoteSnippets(),
                concepts: try concepts(),
                knowledgeRelationships: try knowledgeRelationships(),
                indexingJobs: try indexingJobs(),
                questionVersions: try questionVersions(),
                questionLiteratureAssociations: try questionLiteratureAssociations(),
                questionConceptAssociations: try questionConceptAssociations(),
                claims: try claims(),
                claimVersions: try claimVersions(),
                ideas: try ideas(),
                ideaVersions: try ideaVersions(),
                ideaLinks: try ideaLinks(),
                contradictionCases: try contradictionCases(),
                contradictionSources: try contradictionSources(),
                historyEvents: try historyEvents(),
                aiProviderConfiguration: try aiProviderConfiguration(),
                aiAnalyses: try aiAnalyses(),
                aiAnalysisCitations: try aiAnalysisCitations(),
                aiAnalysisNoteCitations: try aiAnalysisNoteCitations(),
                analysisReviews: try analysisReviews(),
                biasAudits: try biasAudits(),
                biasConcerns: try biasConcerns(),
                deliberationSessions: try deliberationSessions(),
                deliberationMessages: try deliberationMessages(),
                deliberationCitations: try deliberationCitations(),
                writingDocuments: try writingDocuments(),
                writingSections: try writingSections(),
                writingEvidenceLinks: try writingEvidenceLinks(),
                citationSupportReviews: try citationSupportReviews(),
                collectiveExperiments: try collectiveExperiments(),
                collectiveAgents: try collectiveAgents(),
                collectiveTurns: try collectiveTurns(),
                collectiveTurnCitations: try collectiveTurnCitations()
            )
        }
    }

    public func backup(to destinationURL: URL) throws {
        guard destinationURL.standardizedFileURL != url.standardizedFileURL else {
            throw DatabaseError.invalidData("The backup destination must be different from the live database.")
        }
        try synchronized {
            var destination: OpaquePointer?
            guard sqlite3_open_v2(destinationURL.path, &destination, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
                  let destination else {
                let message = destination.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open backup destination"
                if let destination { sqlite3_close(destination) }
                throw DatabaseError.open(message)
            }
            defer { sqlite3_close(destination) }
            guard let backup = sqlite3_backup_init(destination, "main", connection, "main") else {
                throw DatabaseError.execute(String(cString: sqlite3_errmsg(destination)))
            }
            let result = sqlite3_backup_step(backup, -1)
            let finishResult = sqlite3_backup_finish(backup)
            guard result == SQLITE_DONE, finishResult == SQLITE_OK else {
                throw DatabaseError.execute(String(cString: sqlite3_errmsg(destination)))
            }
        }
    }

    public func previewRestore(from sourceURL: URL) throws -> DatabaseRestorePreview {
        guard sourceURL.standardizedFileURL != url.standardizedFileURL else {
            throw DatabaseError.incompatibleBackup("Choose a backup file, not the live Research Atlas database.")
        }
        return try Self.inspectBackup(at: sourceURL)
    }

    @discardableResult
    public func restore(from sourceURL: URL) throws -> URL {
        _ = try previewRestore(from: sourceURL)
        return try synchronized {
            let recoveryDirectory = url.deletingLastPathComponent().appendingPathComponent("Recovery Backups", isDirectory: true)
            try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
            let suffix = UUID().uuidString.prefix(8)
            let recoveryURL = recoveryDirectory.appendingPathComponent("Pre-restore \(formatter.string(from: Date())) \(suffix).sqlite3")
            try backup(to: recoveryURL)

            do {
                try replaceLiveDatabase(from: sourceURL)
                try migrate()
                try rebuildSearchIndex()
                try validateLiveDatabase()
                return recoveryURL
            } catch {
                let restoreFailure = error
                do {
                    try replaceLiveDatabase(from: recoveryURL)
                    try migrate()
                    try rebuildSearchIndex()
                    try validateLiveDatabase()
                } catch {
                    throw DatabaseError.restore(
                        "The selected backup failed, and automatic rollback also failed. Your pre-restore recovery copy remains at \(recoveryURL.path). Rollback error: \(error.localizedDescription)"
                    )
                }
                throw DatabaseError.restore("\(restoreFailure.localizedDescription) The previous workspace was recovered automatically.")
            }
        }
    }

    public func search(_ text: String, limit: Int = 100) throws -> [SearchResult] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }
        return try synchronized {
            let expression = ftsExpression(cleaned)
            guard !expression.isEmpty else { return [] }
            return try query("""
                SELECT entity_id,entity_type,title,snippet(search_index,3,'‹','›',' … ',18)
                FROM search_index WHERE search_index MATCH ? ORDER BY rank LIMIT ?
                """, [.text(expression), .int(Int64(limit))]) { row in
                    SearchResult(entityID: row.text(0), entityType: row.text(1), title: row.text(2), snippet: row.text(3))
                }
        }
    }

    public func sourcePassage(id: String) throws -> RetrievedPassage? {
        try synchronized {
            try query("""
                SELECT p.id,p.literature_id,p.page,p.passage_text,p.extraction_method,p.indexed_at,l.pdf_sha256
                FROM source_passages p
                JOIN literature_items l ON l.id=p.literature_id
                WHERE p.id=? LIMIT 1
                """, [.text(id)]) { row in
                    RetrievedPassage(
                        retrievalSetID: UUID(), sourcePassageID: row.text(0), literatureID: try row.uuid(1),
                        page: row.int(2), passageText: row.text(3), extractionMethod: row.text(4),
                        sourceIndexedAt: self.date(row.text(5)), sourceDocumentHash: row.optionalText(6),
                        rank: 0, citationStatus: .current
                    )
                }.first
        }
    }

    public func metrics() throws -> HomeMetrics {
        try synchronized {
            HomeMetrics(
                literatureCount: try scalarInt("SELECT COUNT(*) FROM literature_items"),
                noteCount: try scalarInt("SELECT COUNT(*) FROM obsidian_notes"),
                questionCount: try scalarInt("SELECT COUNT(*) FROM research_questions"),
                argumentCount: try scalarInt("SELECT COUNT(*) FROM research_arguments")
            )
        }
    }

    public func rebuildSearchIndex() throws {
        try synchronized {
            try execute("DELETE FROM search_index")
            for item in try literatureItems() { try replaceSearchIndex(entityID: item.id.uuidString, type: "literature", title: item.title, body: [item.authors, item.abstract, item.doi ?? "", item.citationKey ?? "", item.tags.joined(separator: " ")].joined(separator: "\n")) }
            for note in try obsidianNotes() { try replaceSearchIndex(entityID: note.id.uuidString, type: "note", title: note.title, body: note.content) }
            for project in try projects() { try replaceSearchIndex(entityID: project.id.uuidString, type: "project", title: project.title, body: project.summary) }
            for question in try questions() {
                try replaceSearchIndex(
                    entityID: question.id.uuidString, type: "question", title: question.question,
                    body: [question.notes, question.objectives, question.theoreticalInterests, question.conceptualDefinitions,
                           question.unresolvedDisagreements, question.potentialHypotheses, question.methodologicalConsiderations].joined(separator: "\n")
                )
            }
            for argument in try arguments() { try replaceSearchIndex(entityID: argument.id.uuidString, type: "argument", title: argument.proposition, body: argument.qualification) }
            for profile in try comparisonProfiles() {
                try replaceSearchIndex(
                    entityID: profile.literatureID.uuidString, type: "comparison", title: "Literature comparison profile",
                    body: [profile.researchQuestion, profile.theoreticalFramework, profile.studyDesign, profile.sample,
                           profile.independentVariables, profile.dependentVariables, profile.operationalDefinitions,
                           profile.mainFindings, profile.limitations, profile.userNotes].joined(separator: "\n")
                )
            }
            for concept in try concepts() {
                try replaceSearchIndex(entityID: concept.id.uuidString, type: "concept", title: concept.name, body: "\(concept.definition)\n\(concept.notes)")
            }
            for claim in try claims() {
                try replaceSearchIndex(
                    entityID: claim.id.uuidString, type: "claim", title: claim.claimText,
                    body: [claim.quotedSourceText, claim.authorTerminology, claim.methodologicalContext,
                           claim.evidenceType, claim.relatedConstructs.joined(separator: " "), claim.studyContext,
                           claim.userNotes].joined(separator: "\n")
                )
            }
            for idea in try ideas() {
                try replaceSearchIndex(
                    entityID: idea.id.uuidString, type: "idea", title: idea.title,
                    body: [idea.body, idea.assumptions, idea.alternativeExplanations, idea.evidenceNeeded, idea.investigationNotes].joined(separator: "\n")
                )
            }
            for contradiction in try contradictionCases() {
                try replaceSearchIndex(entityID: contradiction.id.uuidString, type: "contradiction", title: contradiction.title, body: "\(contradiction.summary)\n\(contradiction.resolutionNotes)")
            }
            for document in try writingDocuments() {
                try replaceSearchIndex(entityID: document.id.uuidString, type: "writing", title: document.title, body: document.notes)
            }
            for section in try writingSections() {
                try replaceSearchIndex(entityID: section.id.uuidString, type: "writing-section", title: section.title, body: "\(section.body)\n\(section.notes)")
            }
        }
    }

    private static func inspectBackup(at sourceURL: URL) throws -> DatabaseRestorePreview {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw DatabaseError.incompatibleBackup("The selected file no longer exists.")
        }
        var source: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_URI
        guard sqlite3_open_v2(immutableSQLiteURI(for: sourceURL), &source, flags, nil) == SQLITE_OK, let source else {
            let message = source.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite could not open the file"
            if let source { sqlite3_close(source) }
            throw DatabaseError.incompatibleBackup(message)
        }
        defer { sqlite3_close(source) }
        sqlite3_busy_timeout(source, 5_000)

        let integrity = try strings("PRAGMA integrity_check", from: source)
        guard integrity == ["ok"] else {
            throw DatabaseError.incompatibleBackup("SQLite integrity checking reported: \(integrity.joined(separator: "; "))")
        }
        let tables = Set(try strings("SELECT name FROM sqlite_master WHERE type IN ('table','view')", from: source))
        let required = Set([
            "schema_migrations", "literature_items", "obsidian_notes", "research_projects",
            "research_questions", "research_arguments", "evidence_relationships", "search_index"
        ])
        let missing = required.subtracting(tables).sorted()
        guard missing.isEmpty else {
            throw DatabaseError.incompatibleBackup("Required Research Atlas tables are missing: \(missing.joined(separator: ", ")).")
        }
        let version = try integer("SELECT COALESCE(MAX(version),0) FROM schema_migrations", from: source)
        guard version >= 1 else {
            throw DatabaseError.incompatibleBackup("No recognized schema version was found.")
        }
        guard version <= currentSchemaVersion else {
            throw DatabaseError.incompatibleBackup("Schema \(version) is newer than this app supports (schema \(currentSchemaVersion)).")
        }
        let foreignKeyProblems = try strings("PRAGMA foreign_key_check", from: source)
        guard foreignKeyProblems.isEmpty else {
            throw DatabaseError.incompatibleBackup("Foreign-key checking reported: \(foreignKeyProblems.joined(separator: "; "))")
        }

        return DatabaseRestorePreview(
            url: sourceURL,
            schemaVersion: version,
            literatureCount: try integer("SELECT COUNT(*) FROM literature_items", from: source),
            noteCount: try integer("SELECT COUNT(*) FROM obsidian_notes", from: source),
            projectCount: try integer("SELECT COUNT(*) FROM research_projects", from: source),
            questionCount: try integer("SELECT COUNT(*) FROM research_questions", from: source),
            argumentCount: try integer("SELECT COUNT(*) FROM research_arguments", from: source),
            evidenceCount: try integer("SELECT COUNT(*) FROM evidence_relationships", from: source)
        )
    }

    private func replaceLiveDatabase(from sourceURL: URL) throws {
        var source: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_URI
        guard sqlite3_open_v2(Self.immutableSQLiteURI(for: sourceURL), &source, flags, nil) == SQLITE_OK, let source else {
            let message = source.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open restore source"
            if let source { sqlite3_close(source) }
            throw DatabaseError.open(message)
        }
        defer { sqlite3_close(source) }
        sqlite3_busy_timeout(source, 5_000)
        guard let operation = sqlite3_backup_init(connection, "main", source, "main") else {
            throw DatabaseError.execute(errorMessage)
        }
        let stepResult = sqlite3_backup_step(operation, -1)
        let finishResult = sqlite3_backup_finish(operation)
        guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
            throw DatabaseError.execute(errorMessage)
        }
    }

    private func validateLiveDatabase() throws {
        let integrity = try query("PRAGMA integrity_check") { $0.text(0) }
        guard integrity == ["ok"] else {
            throw DatabaseError.invalidData("Integrity checking reported: \(integrity.joined(separator: "; "))")
        }
        let foreignKeyProblems = try query("PRAGMA foreign_key_check") { "\($0.text(0)) row \($0.int(1))" }
        guard foreignKeyProblems.isEmpty else {
            throw DatabaseError.invalidData("Foreign-key checking reported: \(foreignKeyProblems.joined(separator: "; "))")
        }
    }

    private static func strings(_ sql: String, from connection: OpaquePointer) throws -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DatabaseError.incompatibleBackup(String(cString: sqlite3_errmsg(connection)))
        }
        defer { sqlite3_finalize(statement) }
        var values: [String] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return values }
            guard result == SQLITE_ROW else {
                throw DatabaseError.incompatibleBackup(String(cString: sqlite3_errmsg(connection)))
            }
            values.append(sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "")
        }
    }

    private static func integer(_ sql: String, from connection: OpaquePointer) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DatabaseError.incompatibleBackup(String(cString: sqlite3_errmsg(connection)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw DatabaseError.incompatibleBackup(String(cString: sqlite3_errmsg(connection)))
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private static func immutableSQLiteURI(for url: URL) -> String {
        url.absoluteString + (url.query == nil ? "?immutable=1" : "&immutable=1")
    }

    private func questionRecord(id: UUID) throws -> ResearchQuestion? {
        try query("""
            SELECT id,project_id,parent_question_id,question,notes,status,objectives,theoretical_interests,
                   conceptual_definitions,unresolved_disagreements,potential_hypotheses,
                   methodological_considerations,created_at,modified_at
            FROM research_questions WHERE id=?
            """, [.text(id.uuidString)]) { row in
            ResearchQuestion(
                id: try row.uuid(0), projectID: try row.uuid(1), parentQuestionID: row.optionalText(2).flatMap(UUID.init(uuidString:)),
                question: row.text(3), notes: row.text(4), status: row.text(5), objectives: row.text(6),
                theoreticalInterests: row.text(7), conceptualDefinitions: row.text(8), unresolvedDisagreements: row.text(9),
                potentialHypotheses: row.text(10), methodologicalConsiderations: row.text(11),
                createdAt: self.date(row.text(12)), modifiedAt: self.date(row.text(13))
            )
        }.first
    }

    private func version(from question: ResearchQuestion, changeNote: String) -> ResearchQuestionVersion {
        ResearchQuestionVersion(
            questionID: question.id, parentQuestionID: question.parentQuestionID,
            question: question.question, notes: question.notes, status: question.status, objectives: question.objectives,
            theoreticalInterests: question.theoreticalInterests, conceptualDefinitions: question.conceptualDefinitions,
            unresolvedDisagreements: question.unresolvedDisagreements, potentialHypotheses: question.potentialHypotheses,
            methodologicalConsiderations: question.methodologicalConsiderations, changeNote: changeNote,
            createdAt: question.modifiedAt
        )
    }

    private func insertQuestionVersion(_ version: ResearchQuestionVersion) throws {
        try execute("""
            INSERT INTO question_versions(
                id,question_id,parent_question_id,question_text,notes,status,objectives,theoretical_interests,
                conceptual_definitions,unresolved_disagreements,potential_hypotheses,
                methodological_considerations,change_note,created_at
            ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, [
                .text(version.id.uuidString), .text(version.questionID.uuidString), optionalText(version.parentQuestionID?.uuidString),
                .text(version.question), .text(version.notes), .text(version.status), .text(version.objectives),
                .text(version.theoreticalInterests), .text(version.conceptualDefinitions),
                .text(version.unresolvedDisagreements), .text(version.potentialHypotheses),
                .text(version.methodologicalConsiderations), .text(version.changeNote),
                .text(dateFormatter.string(from: version.createdAt))
            ])
    }

    private func claim(from row: SQLiteRow) throws -> ResearchClaim {
        ResearchClaim(
            id: try row.uuid(0), claimText: row.text(1), category: ClaimCategory(rawValue: row.text(2)) ?? .personalInterpretation,
            literatureID: row.optionalText(3).flatMap(UUID.init(uuidString:)), sourcePassageID: row.optionalText(4),
            page: row.optionalInt(5), quotedSourceText: row.text(6), authorTerminology: row.text(7),
            methodologicalContext: row.text(8), evidenceType: row.text(9), relatedConstructs: stringArray(row.text(10)),
            studyContext: row.text(11), extractionMethod: ClaimExtractionMethod(rawValue: row.text(12)) ?? .manual,
            modelIdentifier: row.optionalText(13), promptVersion: row.optionalText(14),
            verification: VerificationState(rawValue: row.text(15)) ?? .unverified, userNotes: row.text(16),
            createdAt: date(row.text(17)), modifiedAt: date(row.text(18))
        )
    }

    private func claimRecord(id: UUID) throws -> ResearchClaim? {
        try query("""
            SELECT id,claim_text,category,literature_id,source_passage_id,page,quoted_source_text,
                   author_terminology,methodological_context,evidence_type,related_constructs_json,
                   study_context,extraction_method,model_identifier,prompt_version,verification,user_notes,
                   created_at,modified_at FROM research_claims WHERE id=?
            """, [.text(id.uuidString)]) { try self.claim(from: $0) }.first
    }

    private func version(from claim: ResearchClaim, changeNote: String) -> ClaimVersion {
        ClaimVersion(
            claimID: claim.id, claimText: claim.claimText, category: claim.category,
            authorTerminology: claim.authorTerminology, methodologicalContext: claim.methodologicalContext,
            evidenceType: claim.evidenceType, relatedConstructs: claim.relatedConstructs, studyContext: claim.studyContext,
            verification: claim.verification, userNotes: claim.userNotes, changeNote: changeNote,
            createdAt: claim.modifiedAt
        )
    }

    private func insertClaimVersion(_ version: ClaimVersion) throws {
        try execute("""
            INSERT INTO claim_versions(
                id,claim_id,claim_text,category,author_terminology,methodological_context,evidence_type,
                related_constructs_json,study_context,verification,user_notes,change_note,created_at
            ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, [
                .text(version.id.uuidString), .text(version.claimID.uuidString), .text(version.claimText),
                .text(version.category.rawValue), .text(version.authorTerminology), .text(version.methodologicalContext),
                .text(version.evidenceType), .text(json(version.relatedConstructs)), .text(version.studyContext),
                .text(version.verification.rawValue), .text(version.userNotes), .text(version.changeNote),
                .text(dateFormatter.string(from: version.createdAt))
            ])
    }

    private func ideaRecord(id: UUID) throws -> ResearchIdea? {
        try query("""
            SELECT id,project_id,question_id,title,body,status,assumptions,alternative_explanations,
                   evidence_needed,investigation_notes,created_at,modified_at
            FROM research_ideas WHERE id=?
            """, [.text(id.uuidString)]) { row in
            ResearchIdea(
                id: try row.uuid(0), projectID: row.optionalText(1).flatMap(UUID.init(uuidString:)),
                questionID: row.optionalText(2).flatMap(UUID.init(uuidString:)), title: row.text(3), body: row.text(4),
                status: ResearchIdeaStatus(rawValue: row.text(5)) ?? .initialObservation,
                assumptions: row.text(6), alternativeExplanations: row.text(7), evidenceNeeded: row.text(8),
                investigationNotes: row.text(9), createdAt: self.date(row.text(10)), modifiedAt: self.date(row.text(11))
            )
        }.first
    }

    private func version(from idea: ResearchIdea, changeNote: String) -> IdeaVersion {
        IdeaVersion(
            ideaID: idea.id, title: idea.title, body: idea.body, status: idea.status,
            assumptions: idea.assumptions, alternativeExplanations: idea.alternativeExplanations,
            evidenceNeeded: idea.evidenceNeeded, investigationNotes: idea.investigationNotes,
            changeNote: changeNote, createdAt: idea.modifiedAt
        )
    }

    private func insertIdeaVersion(_ version: IdeaVersion) throws {
        try execute("""
            INSERT INTO idea_versions(
                id,idea_id,title,body,status,assumptions,alternative_explanations,evidence_needed,
                investigation_notes,change_note,created_at
            ) VALUES(?,?,?,?,?,?,?,?,?,?,?)
            """, [
                .text(version.id.uuidString), .text(version.ideaID.uuidString), .text(version.title),
                .text(version.body), .text(version.status.rawValue), .text(version.assumptions),
                .text(version.alternativeExplanations), .text(version.evidenceNeeded),
                .text(version.investigationNotes), .text(version.changeNote),
                .text(dateFormatter.string(from: version.createdAt))
            ])
    }

    private func insertHistoryEvent(_ event: HistoryEvent) throws {
        try execute("INSERT INTO history_events(id,entity_type,entity_id,event_type,title,detail,recorded_at) VALUES(?,?,?,?,?,?,?)", [
            .text(event.id.uuidString), .text(event.entityType), .text(event.entityID), .text(event.eventType),
            .text(event.title), .text(event.detail), .text(dateFormatter.string(from: event.recordedAt))
        ])
    }

    private func ideaLinkTargetExists(type: IdeaLinkTargetType, id: String) throws -> Bool {
        let table: String
        switch type {
        case .literature: table = "literature_items"
        case .passage: table = "source_passages"
        case .note: table = "obsidian_notes"
        case .concept: table = "research_concepts"
        case .argument: table = "research_arguments"
        }
        return (try query("SELECT COUNT(*) FROM \(table) WHERE id=?", [.text(id)]) { $0.int(0) }.first ?? 0) == 1
    }

    private func writingTargetExists(type: WritingEvidenceTargetType, id: String) throws -> Bool {
        let table: String
        switch type {
        case .claim: table = "research_claims"
        case .argumentEvidence: table = "evidence_relationships"
        case .literature: table = "literature_items"
        case .argument: table = "research_arguments"
        }
        return (try query("SELECT COUNT(*) FROM \(table) WHERE id=?", [.text(id)]) { $0.int(0) }.first ?? 0) == 1
    }

    private func matchingSourcePassages(for set: RetrievalSet, limit: Int) throws -> [RetrievedPassage] {
        let expression = ftsExpression(set.query)
        guard !expression.isEmpty else { return [] }
        var sql = """
            SELECT p.id,p.literature_id,p.page,p.passage_text,p.extraction_method,p.indexed_at,
                   l.pdf_sha256,bm25(search_index)
            FROM search_index
            JOIN source_passages p ON p.id=search_index.entity_id AND search_index.entity_type='passage'
            JOIN literature_items l ON l.id=p.literature_id
            WHERE search_index MATCH ?
            """
        var values: [SQLValue] = [.text(expression)]
        if let libraryFilter = set.zoteroLibraryFilterID {
            let parts = libraryFilter.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { throw DatabaseError.invalidData("The saved Zotero library filter is invalid.") }
            sql += " AND l.zotero_server_id=? AND l.zotero_library_id=?"
            values += [.text(parts[0]), .text(parts[1])]
        }
        if let collectionFilter = set.zoteroCollectionFilterID {
            let parts = collectionFilter.split(separator: "|", maxSplits: 2).map(String.init)
            guard parts.count == 3 else { throw DatabaseError.invalidData("The saved Zotero collection filter is invalid.") }
            sql += """
                AND EXISTS(
                    SELECT 1 FROM literature_collection_memberships m
                    WHERE m.literature_id=l.id AND m.server_id=? AND m.library_id=? AND m.collection_key=?
                )
                """
            values += [.text(parts[0]), .text(parts[1]), .text(parts[2])]
        }
        if let yearFrom = set.yearFrom {
            sql += " AND l.publication_year>=?"
            values.append(.int(Int64(yearFrom)))
        }
        if let yearTo = set.yearTo {
            sql += " AND l.publication_year<=?"
            values.append(.int(Int64(yearTo)))
        }
        sql += " ORDER BY bm25(search_index) ASC,p.page ASC LIMIT ?"
        values.append(.int(Int64(limit)))
        let addedAt = Date()
        return try query(sql, values) { row in
            RetrievedPassage(
                retrievalSetID: set.id, sourcePassageID: row.text(0), literatureID: try row.uuid(1),
                page: row.int(2), passageText: row.text(3), extractionMethod: row.text(4),
                sourceIndexedAt: self.date(row.text(5)), sourceDocumentHash: row.optionalText(6),
                rank: row.double(7), citationStatus: .current, addedAt: addedAt
            )
        }
    }

    private func matchingNoteSnippets(for set: RetrievalSet, limit: Int) throws -> [RetrievedNoteSnippet] {
        guard set.zoteroLibraryFilterID == nil, set.zoteroCollectionFilterID == nil,
              set.yearFrom == nil, set.yearTo == nil else { return [] }
        let expression = ftsExpression(set.query)
        guard !expression.isEmpty else { return [] }
        let addedAt = Date()
        return try query("""
            SELECT n.id,n.path,n.title,n.content,n.modified_at,bm25(search_index)
            FROM search_index
            JOIN obsidian_notes n ON n.id=search_index.entity_id AND search_index.entity_type='note'
            WHERE search_index MATCH ?
            ORDER BY bm25(search_index) ASC,n.title COLLATE NOCASE
            LIMIT ?
            """, [.text(expression), .int(Int64(limit))]) { row in
                let content = row.text(3)
                return RetrievedNoteSnippet(
                    retrievalSetID: set.id, noteID: try row.uuid(0), notePath: row.text(1),
                    noteTitle: row.text(2), snippetText: self.noteSnippet(content: content, query: set.query),
                    sourceModifiedAt: self.date(row.text(4)), rank: row.double(5),
                    citationStatus: .current, addedAt: addedAt
                )
            }
    }

    private func noteSnippet(content: String, query: String) -> String {
        let terms = query.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 2 }
        let source = content as NSString
        let lower = content.lowercased() as NSString
        let match = terms.lazy.map { lower.range(of: $0.lowercased()) }.first { $0.location != NSNotFound }
        let location = match?.location ?? 0
        let start = max(0, location - 240)
        let length = min(source.length - start, 900)
        guard length > 0 else { return "" }
        return source.substring(with: NSRange(location: start, length: length))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func knowledgeNodeExists(type: KnowledgeNodeType, id: String) throws -> Bool {
        let table: String
        switch type {
        case .paper: table = "literature_items"
        case .concept: table = "research_concepts"
        case .argument: table = "research_arguments"
        case .researchQuestion: table = "research_questions"
        case .note: table = "obsidian_notes"
        case .claim: table = "research_claims"
        case .idea: table = "research_ideas"
        }
        return (try query("SELECT COUNT(*) FROM \(table) WHERE id=?", [.text(id)]) { $0.int(0) }.first ?? 0) == 1
    }

    private func ftsExpression(_ text: String) -> String {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return "" }
        var clauses: [String] = []
        var buffer = ""
        var insidePhrase = false

        func escaped(_ value: String) -> String {
            value.replacingOccurrences(of: "\"", with: "\"\"")
        }
        func tokens(_ value: String) -> [String] {
            value.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        }
        func appendTerms(_ value: String) {
            for term in tokens(value) {
                clauses.append("\"\(escaped(term))\"*")
            }
        }
        func appendPhrase(_ value: String) {
            let phrase = tokens(value).joined(separator: " ")
            guard !phrase.isEmpty else { return }
            clauses.append("\"\(escaped(phrase))\"")
        }

        for character in source {
            if character == "\"" || character == "“" || character == "”" {
                if insidePhrase {
                    appendPhrase(buffer)
                } else {
                    appendTerms(buffer)
                }
                buffer = ""
                insidePhrase.toggle()
            } else {
                buffer.append(character)
            }
        }
        // A remaining buffer is ordinary text. If the user is still typing an unmatched quote,
        // treating that buffer as prefix terms avoids sending an incomplete FTS expression.
        appendTerms(buffer)
        return clauses.joined(separator: " AND ")
    }

    private func replaceSearchIndex(entityID: String, type: String, title: String, body: String) throws {
        try execute("DELETE FROM search_index WHERE entity_id=? AND entity_type=?", [.text(entityID), .text(type)])
        try execute("INSERT INTO search_index(entity_id,entity_type,title,body) VALUES(?,?,?,?)", [.text(entityID), .text(type), .text(title), .text(body)])
    }

    private func replacePDFPageIndex(literatureID: UUID, pages: [String]) throws {
        let oldPassages = try query("SELECT id FROM source_passages WHERE literature_id=?", [.text(literatureID.uuidString)]) { $0.text(0) }
        for id in oldPassages {
            try execute("DELETE FROM search_index WHERE entity_id=? AND entity_type='passage'", [.text(id)])
        }
        try execute("DELETE FROM source_passages WHERE literature_id=?", [.text(literatureID.uuidString)])
        let timestamp = dateFormatter.string(from: Date())
        for (offset, text) in pages.enumerated() where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let page = offset + 1
            let id = "\(literatureID.uuidString):\(page)"
            try execute("INSERT INTO source_passages(id,literature_id,page,passage_text,extraction_method,indexed_at) VALUES(?,?,?,?,?,?)", [
                .text(id), .text(literatureID.uuidString), .int(Int64(page)), .text(text), .text("PDFKit"), .text(timestamp)
            ])
            try replaceSearchIndex(entityID: id, type: "passage", title: "PDF page \(page)", body: text)
        }
    }

    private func insertArgumentVersion(_ version: ArgumentVersion) throws {
        try execute("""
            INSERT INTO argument_versions(id,argument_id,question_id,proposition,qualification,status,change_note,created_at)
            VALUES(?,?,?,?,?,?,?,?)
            """, [.text(version.id.uuidString), .text(version.argumentID.uuidString), optionalText(version.questionID?.uuidString),
                   .text(version.proposition), .text(version.qualification), .text(version.status), .text(version.changeNote),
                   .text(dateFormatter.string(from: version.createdAt))])
    }

    @discardableResult
    private func synchronized<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func execute(_ sql: String, _ values: [SQLValue] = []) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else { throw DatabaseError.execute(errorMessage) }
    }

    private func query<T>(_ sql: String, _ values: [SQLValue] = [], map: (SQLiteRow) throws -> T) throws -> [T] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var results: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw DatabaseError.execute(errorMessage) }
            results.append(try map(SQLiteRow(statement: statement)))
        }
        return results
    }

    private func scalarInt(_ sql: String) throws -> Int {
        let values = try query(sql) { row in row.int(0) }
        return values.first ?? 0
    }

    private func prepare(_ sql: String, _ values: [SQLValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DatabaseError.prepare(errorMessage)
        }
        do {
            for (offset, value) in values.enumerated() { try bind(value, to: statement, at: Int32(offset + 1)) }
            return statement
        } catch {
            sqlite3_finalize(statement)
            throw error
        }
    }

    private func bind(_ value: SQLValue, to statement: OpaquePointer, at index: Int32) throws {
        let result: Int32
        switch value {
        case .text(let text): result = sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT)
        case .int(let number): result = sqlite3_bind_int64(statement, index, number)
        case .double(let number): result = sqlite3_bind_double(statement, index, number)
        case .null: result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else { throw DatabaseError.execute(errorMessage) }
    }

    private var errorMessage: String { connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error" }
    private func optionalText(_ value: String?) -> SQLValue { value.map(SQLValue.text) ?? .null }
    private func optionalInt(_ value: Int?) -> SQLValue { value.map { .int(Int64($0)) } ?? .null }
    private func optionalInt64(_ value: Int64?) -> SQLValue { value.map(SQLValue.int) ?? .null }
    private func date(_ text: String) -> Date { dateFormatter.date(from: text) ?? .distantPast }
    private func json(_ values: [String]) -> String { (try? String(data: JSONEncoder().encode(values), encoding: .utf8)) ?? "[]" }
    private func stringArray(_ value: String) -> [String] { (try? JSONDecoder().decode([String].self, from: Data(value.utf8))) ?? [] }
    private func encodeJSON<T: Encodable>(_ value: T) -> String {
        (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? "[]"
    }
    private func decodeJSON<T: Decodable>(_ type: T.Type, from value: String) -> T? {
        try? JSONDecoder().decode(type, from: Data(value.utf8))
    }
}

private struct SQLiteRow {
    let statement: OpaquePointer

    func text(_ column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    func optionalText(_ column: Int32) -> String? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : text(column)
    }

    func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(statement, column)) }
    func optionalInt(_ column: Int32) -> Int? { sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : int(column) }
    func optionalInt64(_ column: Int32) -> Int64? { sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, column) }
    func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
    func optionalDouble(_ column: Int32) -> Double? { sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : double(column) }
    func uuid(_ column: Int32) throws -> UUID {
        guard let id = UUID(uuidString: text(column)) else { throw DatabaseError.invalidData("Invalid UUID in column \(column)") }
        return id
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
