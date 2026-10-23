import Foundation

public enum ResearchExporter {
    public static func files(for bundle: ResearchExportBundle) throws -> [String: Data] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601

        return [
            "research-atlas.json": try encoder.encode(bundle),
            "research-atlas.md": Data(markdown(for: bundle).utf8),
            "literature.csv": Data(literatureCSV(bundle.literature).utf8),
            "zotero-libraries.csv": Data(zoteroLibrariesCSV(bundle.zoteroLibraries).utf8),
            "zotero-collections.csv": Data(zoteroCollectionsCSV(bundle.zoteroCollections).utf8),
            "literature-collections.csv": Data(literatureCollectionsCSV(bundle.literatureCollectionMemberships).utf8),
            "evidence.csv": Data(evidenceCSV(bundle.evidence).utf8),
            "note-links.csv": Data(noteLinksCSV(bundle.noteLinks).utf8),
            "argument-history.csv": Data(argumentHistoryCSV(bundle.argumentVersions).utf8),
            "literature-comparison.csv": Data(comparisonCSV(bundle.comparisonProfiles).utf8),
            "retrieval-sets.csv": Data(retrievalSetsCSV(bundle.retrievalSets).utf8),
            "retrieved-passages.csv": Data(retrievedPassagesCSV(bundle.retrievedPassages).utf8),
            "retrieved-note-snippets.csv": Data(retrievedNoteSnippetsCSV(bundle.retrievedNoteSnippets).utf8),
            "concepts.csv": Data(conceptsCSV(bundle.concepts).utf8),
            "knowledge-relationships.csv": Data(knowledgeRelationshipsCSV(bundle.knowledgeRelationships).utf8),
            "indexing-jobs.csv": Data(indexingJobsCSV(bundle.indexingJobs).utf8),
            "question-history.csv": Data(questionHistoryCSV(bundle.questionVersions).utf8),
            "question-literature.csv": Data(questionLiteratureCSV(bundle.questionLiteratureAssociations).utf8),
            "question-concepts.csv": Data(questionConceptsCSV(bundle.questionConceptAssociations).utf8),
            "claims.csv": Data(claimsCSV(bundle.claims).utf8),
            "claim-history.csv": Data(claimHistoryCSV(bundle.claimVersions).utf8),
            "ideas.csv": Data(ideasCSV(bundle.ideas).utf8),
            "idea-history.csv": Data(ideaHistoryCSV(bundle.ideaVersions).utf8),
            "idea-links.csv": Data(ideaLinksCSV(bundle.ideaLinks).utf8),
            "contradiction-cases.csv": Data(contradictionCasesCSV(bundle.contradictionCases).utf8),
            "contradiction-sources.csv": Data(contradictionSourcesCSV(bundle.contradictionSources).utf8),
            "intellectual-history.csv": Data(historyEventsCSV(bundle.historyEvents).utf8),
            "ai-provider-configuration.csv": Data(aiProviderConfigurationCSV(bundle.aiProviderConfiguration).utf8),
            "ai-analyses.csv": Data(aiAnalysesCSV(bundle.aiAnalyses).utf8),
            "ai-analysis-citations.csv": Data(aiAnalysisCitationsCSV(bundle.aiAnalysisCitations).utf8),
            "ai-analysis-note-citations.csv": Data(aiAnalysisNoteCitationsCSV(bundle.aiAnalysisNoteCitations).utf8),
            "ai-analysis-reviews.csv": Data(analysisReviewsCSV(bundle.analysisReviews).utf8),
            "bias-audits.csv": Data(biasAuditsCSV(bundle.biasAudits).utf8),
            "bias-concerns.csv": Data(biasConcernsCSV(bundle.biasConcerns).utf8),
            "deliberation-sessions.csv": Data(deliberationSessionsCSV(bundle.deliberationSessions).utf8),
            "deliberation-messages.csv": Data(deliberationMessagesCSV(bundle.deliberationMessages).utf8),
            "deliberation-citations.csv": Data(deliberationCitationsCSV(bundle.deliberationCitations).utf8),
            "writing-documents.csv": Data(writingDocumentsCSV(bundle.writingDocuments).utf8),
            "writing-sections.csv": Data(writingSectionsCSV(bundle.writingSections).utf8),
            "writing-evidence-links.csv": Data(writingEvidenceLinksCSV(bundle.writingEvidenceLinks).utf8),
            "citation-support-reviews.csv": Data(citationSupportReviewsCSV(bundle.citationSupportReviews).utf8),
            "collective-experiments.csv": Data(collectiveExperimentsCSV(bundle.collectiveExperiments).utf8),
            "collective-agents.csv": Data(collectiveAgentsCSV(bundle.collectiveAgents).utf8),
            "collective-turns.csv": Data(collectiveTurnsCSV(bundle.collectiveTurns).utf8),
            "collective-turn-citations.csv": Data(collectiveTurnCitationsCSV(bundle.collectiveTurnCitations).utf8)
        ]
    }

    public static func markdown(for bundle: ResearchExportBundle) -> String {
        let literatureByID = Dictionary(uniqueKeysWithValues: bundle.literature.map { ($0.id, $0) })
        let questionsByID = Dictionary(uniqueKeysWithValues: bundle.questions.map { ($0.id, $0) })
        var lines: [String] = [
            "# Research Atlas Export",
            "",
            "Exported: \(timestamp(bundle.exportedAt))",
            "",
            "> This export separates source metadata, user-authored arguments, evidence links, and recorded versions. Verification states are preserved.",
            ""
        ]

        lines += ["## Research Projects", ""]
        if bundle.projects.isEmpty { lines += ["_No research projects._", ""] }
        for project in bundle.projects {
            lines += ["### \(project.title)", "", project.summary, ""]
            let questions = bundle.questions.filter { $0.projectID == project.id }
            for question in questions {
                lines += ["- **\(question.status):** \(question.question)"]
                if !question.notes.isEmpty { lines += ["  - \(question.notes)"] }
            }
            lines.append("")
        }

        lines += ["## Arguments", ""]
        if bundle.arguments.isEmpty { lines += ["_No arguments._", ""] }
        for argument in bundle.arguments {
            lines += ["### \(argument.proposition)", "", "Status: **\(argument.status)**"]
            if let questionID = argument.questionID, let question = questionsByID[questionID] {
                lines += ["Research question: \(question.question)"]
            }
            if !argument.qualification.isEmpty { lines += ["", "Qualification: \(argument.qualification)"] }
            lines += ["", "#### Evidence", ""]
            let evidence = bundle.evidence.filter { $0.argumentID == argument.id }
            if evidence.isEmpty { lines.append("_No linked evidence._") }
            for relationship in evidence {
                let source = literatureByID[relationship.literatureID]?.title ?? "Unavailable source"
                let page = relationship.page.map { ", p. \($0)" } ?? ""
                lines += ["- **\(relationship.relation.rawValue)** — \(source)\(page) [\(relationship.verification.rawValue)]", "  - \(relationship.summary)"]
                if !relationship.quotedPassage.isEmpty { lines += ["  - > \(singleLine(relationship.quotedPassage))"] }
            }
            lines += ["", "#### Recorded history", ""]
            let versions = bundle.argumentVersions.filter { $0.argumentID == argument.id }.sorted { $0.createdAt < $1.createdAt }
            if versions.isEmpty { lines.append("_No recorded versions._") }
            for version in versions {
                lines += ["- \(timestamp(version.createdAt)) — **\(version.changeNote)**: \(version.proposition)"]
            }
            lines.append("")
        }

        lines += ["## Literature", ""]
        if bundle.literature.isEmpty { lines += ["_No literature items._", ""] }
        for item in bundle.literature {
            let year = item.year.map(String.init) ?? "n.d."
            lines += ["- **\(item.title)** — \(item.authors) (\(year))"]
            if item.sourceAvailability != .available { lines += ["  - Source status: \(item.sourceAvailability.rawValue)"] }
            if let libraryName = item.zoteroLibraryName { lines += ["  - Zotero library: \(libraryName)"] }
            if let doi = item.doi { lines += ["  - DOI: \(doi)"] }
            if let key = item.citationKey { lines += ["  - Citation key: `\(key)`"] }
        }
        lines.append("")

        lines += ["## Saved Retrieval Sets", ""]
        if bundle.retrievalSets.isEmpty { lines += ["_No saved retrieval sets._", ""] }
        for set in bundle.retrievalSets {
            lines += ["### \(set.name)", "", "Query: `\(set.query)`", ""]
            let passages = bundle.retrievedPassages.filter { $0.retrievalSetID == set.id }
            let noteSnippets = bundle.retrievedNoteSnippets.filter { $0.retrievalSetID == set.id }
            if passages.isEmpty && noteSnippets.isEmpty { lines.append("_No matching source snapshots were retrieved._") }
            if !passages.isEmpty { lines.append("Published-source passages:") }
            for passage in passages {
                let source = literatureByID[passage.literatureID]?.title ?? "Unavailable source"
                lines += ["- **\(source), p. \(passage.page)** [\(passage.citationStatus.rawValue)]", "  - > \(singleLine(passage.passageText))"]
            }
            if !noteSnippets.isEmpty {
                lines += ["", "Researcher-note excerpts (context, not published evidence):"]
                for snippet in noteSnippets {
                    lines += ["- **\(snippet.noteTitle)** [\(snippet.citationStatus.rawValue)]", "  - > \(singleLine(snippet.snippetText))"]
                }
            }
            lines.append("")
        }

        lines += ["## Knowledge Relationships", ""]
        if bundle.knowledgeRelationships.isEmpty { lines += ["_No knowledge relationships._", ""] }
        for relationship in bundle.knowledgeRelationships {
            lines.append("- \(relationship.sourceType.rawValue) `\(relationship.sourceID)` **\(relationship.relationship.rawValue)** \(relationship.targetType.rawValue) `\(relationship.targetID)` [\(relationship.verification.rawValue); \(relationship.origin.rawValue)]")
            if !relationship.notes.isEmpty { lines.append("  - \(relationship.notes)") }
        }
        lines.append("")

        lines += ["## Structured Claims", ""]
        if bundle.claims.isEmpty { lines += ["_No structured claims._", ""] }
        for claim in bundle.claims {
            lines += ["### \(claim.claimText)", "", "Category: **\(claim.category.rawValue)** · Verification: **\(claim.verification.rawValue)**"]
            if let literatureID = claim.literatureID {
                let source = literatureByID[literatureID]?.title ?? "Unavailable source"
                lines.append("Source: \(source)\(claim.page.map { ", p. \($0)" } ?? "")")
            }
            if !claim.quotedSourceText.isEmpty { lines += ["", "> \(singleLine(claim.quotedSourceText))"] }
            lines.append("")
        }

        lines += ["## Research Ideas", ""]
        if bundle.ideas.isEmpty { lines += ["_No research ideas._", ""] }
        for idea in bundle.ideas {
            lines += ["### \(idea.title)", "", "Status: **\(idea.status.rawValue)**", "", idea.body, ""]
            if !idea.assumptions.isEmpty { lines += ["- Assumptions: \(idea.assumptions)"] }
            if !idea.alternativeExplanations.isEmpty { lines += ["- Alternative explanations: \(idea.alternativeExplanations)"] }
            if !idea.evidenceNeeded.isEmpty { lines += ["- Evidence needed: \(idea.evidenceNeeded)"] }
            lines.append("")
        }

        lines += ["## Contradiction Reviews", ""]
        if bundle.contradictionCases.isEmpty { lines += ["_No contradiction reviews._", ""] }
        for item in bundle.contradictionCases {
            lines += ["### \(item.title)", "", "Assessment: **\(item.status.rawValue)**", "", item.summary]
            if !item.resolutionNotes.isEmpty { lines += ["", "Current resolution: \(item.resolutionNotes)"] }
            lines.append("")
        }

        lines += ["## Model-generated Analyses", "", "> These records are model-generated suggestions, not verified findings. Provider, model, prompt contract, source snapshots, citation status, and human review are preserved.", ""]
        if bundle.aiAnalyses.isEmpty { lines += ["_No model-generated analyses._", ""] }
        let citationsByAnalysis = Dictionary(grouping: bundle.aiAnalysisCitations, by: \.analysisID)
        let noteCitationsByAnalysis = Dictionary(grouping: bundle.aiAnalysisNoteCitations, by: \.analysisID)
        let reviewsByAnalysis = Dictionary(uniqueKeysWithValues: bundle.analysisReviews.map { ($0.analysisID, $0) })
        for analysis in bundle.aiAnalyses {
            lines += ["### \(analysis.userQuery)", "", "Kind: **\(analysis.kind.rawValue)** · Status: **\(analysis.status.rawValue)** · Model: `\(analysis.model)` · Prompt: `\(analysis.promptVersion)`"]
            if let targetType = analysis.targetType, let targetID = analysis.targetID {
                lines += ["", "Target: **\(targetType.rawValue)** `\(targetID.uuidString)`"]
            }
            if !analysis.responseText.isEmpty { lines += ["", analysis.responseText] }
            if let error = analysis.errorMessage { lines += ["", "Failure: \(error)"] }
            let citations = citationsByAnalysis[analysis.id] ?? []
            let noteCitations = noteCitationsByAnalysis[analysis.id] ?? []
            if !citations.isEmpty {
                lines += ["", "Published-source snapshots:"]
                for citation in citations {
                    let source = literatureByID[citation.literatureID]?.title ?? "Unavailable source"
                    lines += ["- [\(citation.label)] **\(source), p. \(citation.page)** [\(citation.citationStatus.rawValue)]", "  - > \(singleLine(citation.quotedPassage))"]
                }
            }
            if !noteCitations.isEmpty {
                lines += ["", "Researcher-note snapshots (context, not published evidence):"]
                for citation in noteCitations {
                    lines += ["- [\(citation.label)] **\(citation.noteTitle)** [\(citation.citationStatus.rawValue)]", "  - > \(singleLine(citation.quotedSnippet))"]
                }
            }
            if let review = reviewsByAnalysis[analysis.id] {
                lines += ["", "Human review: **\(review.decision.rawValue)**\(review.notes.isEmpty ? "" : " — \(review.notes)")"]
            } else {
                lines += ["", "Human review: **Pending review**"]
            }
            lines.append("")
        }

        lines += ["## Research Bias Audits", "", "> Concerns are critical questions for human investigation, not diagnoses of psychological bias.", ""]
        if bundle.biasAudits.isEmpty { lines += ["_No bias audits._", ""] }
        let concernsByAudit = Dictionary(grouping: bundle.biasConcerns, by: \.auditID)
        for audit in bundle.biasAudits {
            lines += ["### \(audit.title)", "", audit.scopeNote, ""]
            for concern in concernsByAudit[audit.id] ?? [] {
                lines += ["- **\(concern.kind.rawValue)** [\(concern.disposition.rawValue)] — \(concern.potentialProblem)"]
                if !concern.whyItMatters.isEmpty { lines.append("  - Why it may matter: \(concern.whyItMatters)") }
                if !concern.alternativeInterpretations.isEmpty { lines.append("  - Alternatives: \(concern.alternativeInterpretations)") }
                for question in concern.investigationQuestions { lines.append("  - Question: \(question)") }
            }
            lines.append("")
        }

        lines += ["## Argument Room Deliberations", "", "> Generated roles are simulated perspectives, not independent experts or independent evidence.", ""]
        if bundle.deliberationSessions.isEmpty { lines += ["_No deliberation sessions._", ""] }
        let messagesBySession = Dictionary(grouping: bundle.deliberationMessages, by: \.sessionID)
        let citationsByMessage = Dictionary(grouping: bundle.deliberationCitations, by: \.messageID)
        for session in bundle.deliberationSessions {
            lines += ["### \(session.title)", "", "Status: **\(session.status.rawValue)** · Model: `\(session.model)`", "", session.disclosure, ""]
            for message in messagesBySession[session.id] ?? [] {
                lines += ["#### \(message.perspective.rawValue) — \(message.phase.rawValue)", "", message.content, ""]
                let labels = (citationsByMessage[message.id] ?? []).map { "[\($0.label)] p. \($0.page) [\($0.citationStatus.rawValue)]" }
                if !labels.isEmpty { lines += ["Sources: " + labels.joined(separator: "; "), ""] }
            }
        }

        lines += ["## Research Writing", ""]
        if bundle.writingDocuments.isEmpty { lines += ["_No writing workspaces._", ""] }
        let sectionsByDocument = Dictionary(grouping: bundle.writingSections, by: \.documentID)
        for document in bundle.writingDocuments {
            lines += ["### \(document.title)", "", "Purpose: **\(document.purpose.rawValue)** · Status: **\(document.status)**", "", document.notes, ""]
            for section in (sectionsByDocument[document.id] ?? []).sorted(by: { $0.position < $1.position }) {
                lines += ["#### \(section.title)", "", section.body, ""]
            }
        }

        lines += ["## Collective Intelligence Laboratory", "", "> These are exploratory simulation records, not validated measures of human collective intelligence.", ""]
        if bundle.collectiveExperiments.isEmpty { lines += ["_No collective-intelligence experiments._", ""] }
        let agentsByExperiment = Dictionary(grouping: bundle.collectiveAgents, by: \.experimentID)
        let turnsByExperiment = Dictionary(grouping: bundle.collectiveTurns, by: \.experimentID)
        for experiment in bundle.collectiveExperiments {
            lines += ["### \(experiment.title)", "", "Mode: **\(experiment.interactionMode.rawValue)** · Status: **\(experiment.status.rawValue)**", "", experiment.validationNote, ""]
            if !experiment.researchPurpose.isEmpty { lines += ["Purpose: \(experiment.researchPurpose)", ""] }
            if !experiment.taskInstructions.isEmpty { lines += ["Task: \(experiment.taskInstructions)", ""] }
            let agents = agentsByExperiment[experiment.id] ?? []
            if !agents.isEmpty { lines += ["Agents: " + agents.sorted(by: { $0.position < $1.position }).map { "\($0.label) (\($0.role))" }.joined(separator: "; "), ""] }
            for turn in turnsByExperiment[experiment.id] ?? [] {
                let agent = turn.agentID.flatMap { id in agents.first { $0.id == id }?.label } ?? "Researcher/system"
                lines += ["- Round \(turn.round), \(agent), **\(turn.kind.rawValue)**\(turn.confidence.map { " · confidence \($0)" } ?? ""): \(singleLine(turn.responseText))"]
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func literatureCSV(_ items: [LiteratureItem]) -> String {
        var rows = [["id", "title", "authors", "year", "doi", "citation_key", "tags", "source", "source_availability", "zotero_server_id", "zotero_library_id", "zotero_library_name", "zotero_key", "zotero_version", "pdf_path", "pdf_byte_count", "pdf_sha256", "pdf_last_verified_at"]]
        rows += items.map {
            [$0.id.uuidString, $0.title, $0.authors, $0.year.map(String.init) ?? "", $0.doi ?? "", $0.citationKey ?? "",
             $0.tags.joined(separator: "; "), $0.source.rawValue, $0.sourceAvailability.rawValue, $0.zoteroServerID ?? "",
             $0.zoteroLibraryID ?? "", $0.zoteroLibraryName ?? "", $0.zoteroKey ?? "", $0.zoteroVersion.map(String.init) ?? "", $0.pdfPath ?? "", $0.pdfByteCount.map(String.init) ?? "",
             $0.pdfContentHash ?? "", $0.pdfLastVerifiedAt.map(timestamp) ?? ""]
        }
        return csv(rows)
    }

    private static func zoteroLibrariesCSV(_ libraries: [ZoteroLibrary]) -> String {
        var rows = [["server_id", "library_id", "kind", "name", "metadata_version", "library_version", "availability", "last_synced_at"]]
        rows += libraries.map {
            [$0.serverID, $0.libraryID, $0.kind.rawValue, $0.name, $0.metadataVersion.map(String.init) ?? "",
             $0.libraryVersion.map(String.init) ?? "", $0.availability.rawValue, $0.lastSyncedAt.map(timestamp) ?? ""]
        }
        return csv(rows)
    }

    private static func zoteroCollectionsCSV(_ collections: [ZoteroCollection]) -> String {
        var rows = [["server_id", "library_id", "collection_key", "name", "parent_collection_key", "zotero_version"]]
        rows += collections.map {
            [$0.serverID, $0.libraryID, $0.key, $0.name, $0.parentKey ?? "", $0.version.map(String.init) ?? ""]
        }
        return csv(rows)
    }

    private static func literatureCollectionsCSV(_ memberships: [LiteratureCollectionMembership]) -> String {
        var rows = [["literature_id", "collection_id"]]
        rows += memberships.map { [$0.literatureID.uuidString, $0.collectionID] }
        return csv(rows)
    }

    private static func evidenceCSV(_ items: [EvidenceRelationship]) -> String {
        var rows = [["id", "argument_id", "literature_id", "relationship", "summary", "page", "quoted_passage", "verification", "selection_geometry_json", "selection_document_hash", "created_at"]]
        rows += items.map {
            [$0.id.uuidString, $0.argumentID.uuidString, $0.literatureID.uuidString, $0.relation.rawValue,
             $0.summary, $0.page.map(String.init) ?? "", $0.quotedPassage, $0.verification.rawValue,
             jsonString($0.selectionRegions), $0.selectionDocumentHash ?? "", timestamp($0.createdAt)]
        }
        return csv(rows)
    }

    private static func noteLinksCSV(_ items: [PaperNoteLink]) -> String {
        var rows = [["id", "note_id", "literature_id", "match_method", "matched_identifier", "review_state", "modified_at"]]
        rows += items.map { [$0.id.uuidString, $0.noteID.uuidString, $0.literatureID.uuidString, $0.method.rawValue, $0.matchedIdentifier, $0.state.rawValue, timestamp($0.modifiedAt)] }
        return csv(rows)
    }

    private static func argumentHistoryCSV(_ items: [ArgumentVersion]) -> String {
        var rows = [["id", "argument_id", "question_id", "proposition", "qualification", "status", "change_note", "created_at"]]
        rows += items.map { [$0.id.uuidString, $0.argumentID.uuidString, $0.questionID?.uuidString ?? "", $0.proposition, $0.qualification, $0.status, $0.changeNote, timestamp($0.createdAt)] }
        return csv(rows)
    }

    private static func comparisonCSV(_ items: [LiteratureComparisonProfile]) -> String {
        var rows = [["literature_id", "research_question", "theoretical_framework", "study_design", "sample", "independent_variables", "dependent_variables", "operational_definitions", "main_findings", "limitations", "user_notes", "modified_at"]]
        rows += items.map {
            [$0.literatureID.uuidString, $0.researchQuestion, $0.theoreticalFramework, $0.studyDesign, $0.sample,
             $0.independentVariables, $0.dependentVariables, $0.operationalDefinitions, $0.mainFindings,
             $0.limitations, $0.userNotes, timestamp($0.modifiedAt)]
        }
        return csv(rows)
    }

    private static func retrievalSetsCSV(_ items: [RetrievalSet]) -> String {
        var rows = [["id", "name", "query", "zotero_library_filter_id", "zotero_collection_filter_id", "year_from", "year_to", "created_at"]]
        rows += items.map {
            [$0.id.uuidString, $0.name, $0.query, $0.zoteroLibraryFilterID ?? "", $0.zoteroCollectionFilterID ?? "",
             $0.yearFrom.map(String.init) ?? "", $0.yearTo.map(String.init) ?? "", timestamp($0.createdAt)]
        }
        return csv(rows)
    }

    private static func retrievedPassagesCSV(_ items: [RetrievedPassage]) -> String {
        var rows = [["retrieval_set_id", "source_passage_id", "literature_id", "page", "passage_text", "extraction_method", "source_indexed_at", "source_document_hash", "relevance_rank", "citation_status", "added_at"]]
        rows += items.map {
            [$0.retrievalSetID.uuidString, $0.sourcePassageID, $0.literatureID.uuidString, String($0.page),
             $0.passageText, $0.extractionMethod, timestamp($0.sourceIndexedAt), $0.sourceDocumentHash ?? "",
             String($0.rank), $0.citationStatus.rawValue, timestamp($0.addedAt)]
        }
        return csv(rows)
    }

    private static func retrievedNoteSnippetsCSV(_ items: [RetrievedNoteSnippet]) -> String {
        var rows = [["retrieval_set_id", "note_id", "note_path", "note_title", "snippet_text", "source_modified_at", "relevance_rank", "citation_status", "added_at"]]
        rows += items.map {
            [$0.retrievalSetID.uuidString, $0.noteID.uuidString, $0.notePath, $0.noteTitle,
             $0.snippetText, timestamp($0.sourceModifiedAt), String($0.rank),
             $0.citationStatus.rawValue, timestamp($0.addedAt)]
        }
        return csv(rows)
    }

    private static func conceptsCSV(_ items: [ResearchConcept]) -> String {
        var rows = [["id", "name", "definition", "notes", "verification", "origin", "created_at", "modified_at"]]
        rows += items.map {
            [$0.id.uuidString, $0.name, $0.definition, $0.notes, $0.verification.rawValue, $0.origin.rawValue,
             timestamp($0.createdAt), timestamp($0.modifiedAt)]
        }
        return csv(rows)
    }

    private static func knowledgeRelationshipsCSV(_ items: [KnowledgeRelationship]) -> String {
        var rows = [["id", "source_type", "source_id", "target_type", "target_id", "relationship", "evidence_relationship_id", "source_passage_id", "verification", "origin", "notes", "created_at", "modified_at"]]
        rows += items.map {
            [$0.id.uuidString, $0.sourceType.rawValue, $0.sourceID, $0.targetType.rawValue, $0.targetID,
             $0.relationship.rawValue, $0.evidenceRelationshipID?.uuidString ?? "", $0.sourcePassageID ?? "",
             $0.verification.rawValue, $0.origin.rawValue, $0.notes, timestamp($0.createdAt), timestamp($0.modifiedAt)]
        }
        return csv(rows)
    }

    private static func indexingJobsCSV(_ items: [IndexingJob]) -> String {
        var rows = [["id", "kind", "source_name", "status", "completed_units", "total_units", "failure_message", "created_at", "updated_at"]]
        rows += items.map {
            [$0.id.uuidString, $0.kind.rawValue, $0.sourceName, $0.status.rawValue, String($0.completedUnits),
             $0.totalUnits.map(String.init) ?? "", $0.failureMessage ?? "", timestamp($0.createdAt), timestamp($0.updatedAt)]
        }
        return csv(rows)
    }

    private static func questionHistoryCSV(_ items: [ResearchQuestionVersion]) -> String {
        var rows = [["id", "question_id", "parent_question_id", "question", "notes", "status", "objectives", "theoretical_interests", "conceptual_definitions", "unresolved_disagreements", "potential_hypotheses", "methodological_considerations", "change_note", "created_at"]]
        rows += items.map {
            [$0.id.uuidString, $0.questionID.uuidString, $0.parentQuestionID?.uuidString ?? "", $0.question, $0.notes,
             $0.status, $0.objectives, $0.theoreticalInterests, $0.conceptualDefinitions, $0.unresolvedDisagreements,
             $0.potentialHypotheses, $0.methodologicalConsiderations, $0.changeNote, timestamp($0.createdAt)]
        }
        return csv(rows)
    }

    private static func questionLiteratureCSV(_ items: [QuestionLiteratureAssociation]) -> String {
        var rows = [["question_id", "literature_id", "notes", "created_at"]]
        rows += items.map { [$0.questionID.uuidString, $0.literatureID.uuidString, $0.notes, timestamp($0.createdAt)] }
        return csv(rows)
    }

    private static func questionConceptsCSV(_ items: [QuestionConceptAssociation]) -> String {
        var rows = [["question_id", "concept_id", "notes", "created_at"]]
        rows += items.map { [$0.questionID.uuidString, $0.conceptID.uuidString, $0.notes, timestamp($0.createdAt)] }
        return csv(rows)
    }

    private static func claimsCSV(_ items: [ResearchClaim]) -> String {
        var rows = [["id", "claim_text", "category", "literature_id", "source_passage_id", "page", "quoted_source_text", "author_terminology", "methodological_context", "evidence_type", "related_constructs", "study_context", "extraction_method", "model_identifier", "prompt_version", "verification", "user_notes", "created_at", "modified_at"]]
        rows += items.map {
            [$0.id.uuidString, $0.claimText, $0.category.rawValue, $0.literatureID?.uuidString ?? "", $0.sourcePassageID ?? "",
             $0.page.map(String.init) ?? "", $0.quotedSourceText, $0.authorTerminology, $0.methodologicalContext,
             $0.evidenceType, $0.relatedConstructs.joined(separator: "; "), $0.studyContext, $0.extractionMethod.rawValue,
             $0.modelIdentifier ?? "", $0.promptVersion ?? "", $0.verification.rawValue, $0.userNotes,
             timestamp($0.createdAt), timestamp($0.modifiedAt)]
        }
        return csv(rows)
    }

    private static func claimHistoryCSV(_ items: [ClaimVersion]) -> String {
        var rows = [["id", "claim_id", "claim_text", "category", "author_terminology", "methodological_context", "evidence_type", "related_constructs", "study_context", "verification", "user_notes", "change_note", "created_at"]]
        rows += items.map {
            [$0.id.uuidString, $0.claimID.uuidString, $0.claimText, $0.category.rawValue, $0.authorTerminology,
             $0.methodologicalContext, $0.evidenceType, $0.relatedConstructs.joined(separator: "; "), $0.studyContext,
             $0.verification.rawValue, $0.userNotes, $0.changeNote, timestamp($0.createdAt)]
        }
        return csv(rows)
    }

    private static func ideasCSV(_ items: [ResearchIdea]) -> String {
        var rows = [["id", "project_id", "question_id", "title", "body", "status", "assumptions", "alternative_explanations", "evidence_needed", "investigation_notes", "created_at", "modified_at"]]
        rows += items.map {
            [$0.id.uuidString, $0.projectID?.uuidString ?? "", $0.questionID?.uuidString ?? "", $0.title, $0.body,
             $0.status.rawValue, $0.assumptions, $0.alternativeExplanations, $0.evidenceNeeded, $0.investigationNotes,
             timestamp($0.createdAt), timestamp($0.modifiedAt)]
        }
        return csv(rows)
    }

    private static func ideaHistoryCSV(_ items: [IdeaVersion]) -> String {
        var rows = [["id", "idea_id", "title", "body", "status", "assumptions", "alternative_explanations", "evidence_needed", "investigation_notes", "change_note", "created_at"]]
        rows += items.map {
            [$0.id.uuidString, $0.ideaID.uuidString, $0.title, $0.body, $0.status.rawValue, $0.assumptions,
             $0.alternativeExplanations, $0.evidenceNeeded, $0.investigationNotes, $0.changeNote, timestamp($0.createdAt)]
        }
        return csv(rows)
    }

    private static func ideaLinksCSV(_ items: [ResearchIdeaLink]) -> String {
        var rows = [["id", "idea_id", "target_type", "target_id", "notes", "created_at"]]
        rows += items.map { [$0.id.uuidString, $0.ideaID.uuidString, $0.targetType.rawValue, $0.targetID, $0.notes, timestamp($0.createdAt)] }
        return csv(rows)
    }

    private static func contradictionCasesCSV(_ items: [ContradictionCase]) -> String {
        var rows = [["id", "question_id", "title", "summary", "status", "resolution_notes", "created_at", "modified_at"]]
        rows += items.map { [$0.id.uuidString, $0.questionID?.uuidString ?? "", $0.title, $0.summary, $0.status.rawValue, $0.resolutionNotes, timestamp($0.createdAt), timestamp($0.modifiedAt)] }
        return csv(rows)
    }

    private static func contradictionSourcesCSV(_ items: [ContradictionSource]) -> String {
        var rows = [["id", "case_id", "literature_id", "source_passage_id", "role", "finding", "contextual_difference", "verification", "created_at"]]
        rows += items.map { [$0.id.uuidString, $0.caseID.uuidString, $0.literatureID.uuidString, $0.sourcePassageID ?? "", $0.role, $0.finding, $0.contextualDifference, $0.verification.rawValue, timestamp($0.createdAt)] }
        return csv(rows)
    }

    private static func historyEventsCSV(_ items: [HistoryEvent]) -> String {
        var rows = [["id", "entity_type", "entity_id", "event_type", "title", "detail", "recorded_at"]]
        rows += items.map { [$0.id.uuidString, $0.entityType, $0.entityID, $0.eventType, $0.title, $0.detail, timestamp($0.recordedAt)] }
        return csv(rows)
    }

    private static func aiProviderConfigurationCSV(_ configuration: AIProviderConfiguration?) -> String {
        var rows = [["provider", "endpoint", "model", "external_transmission_enabled", "maximum_passages", "maximum_output_tokens", "reasoning_effort", "local_runtime_idle_minutes", "modified_at", "credential_exported"]]
        if let configuration {
            rows.append([
                configuration.provider.rawValue, configuration.endpoint, configuration.model,
                String(configuration.externalTransmissionEnabled), String(configuration.maximumPassages),
                String(configuration.maximumOutputTokens), configuration.reasoningEffort.rawValue,
                String(configuration.localRuntimeIdleMinutes), timestamp(configuration.modifiedAt), "false"
            ])
        }
        return csv(rows)
    }

    private static func aiAnalysesCSV(_ items: [AIAnalysis]) -> String {
        var rows = [["id", "kind", "provider", "model", "prompt_version", "retrieval_set_id", "target_type", "target_id", "user_query", "response_text", "structured_response_json", "status", "transmitted_passage_count", "transmitted_character_count", "input_tokens", "output_tokens", "error_message", "created_at", "completed_at"]]
        rows += items.map {
            [$0.id.uuidString, $0.kind.rawValue, $0.provider, $0.model, $0.promptVersion,
             $0.retrievalSetID?.uuidString ?? "", $0.targetType?.rawValue ?? "", $0.targetID?.uuidString ?? "",
             $0.userQuery, $0.responseText, $0.structuredResponseJSON,
             $0.status.rawValue, String($0.transmittedPassageCount), String($0.transmittedCharacterCount),
             $0.inputTokens.map(String.init) ?? "", $0.outputTokens.map(String.init) ?? "", $0.errorMessage ?? "",
             timestamp($0.createdAt), $0.completedAt.map(timestamp) ?? ""]
        }
        return csv(rows)
    }

    private static func aiAnalysisCitationsCSV(_ items: [AIAnalysisCitation]) -> String {
        var rows = [["id", "analysis_id", "label", "source_passage_id", "literature_id", "page", "quoted_passage", "source_document_hash", "citation_status"]]
        rows += items.map {
            [$0.id.uuidString, $0.analysisID.uuidString, $0.label, $0.sourcePassageID, $0.literatureID.uuidString,
             String($0.page), $0.quotedPassage, $0.sourceDocumentHash ?? "", $0.citationStatus.rawValue]
        }
        return csv(rows)
    }

    private static func aiAnalysisNoteCitationsCSV(_ items: [AIAnalysisNoteCitation]) -> String {
        var rows = [["id", "analysis_id", "label", "note_id", "note_path", "note_title", "quoted_snippet", "source_modified_at", "citation_status"]]
        rows += items.map {
            [$0.id.uuidString, $0.analysisID.uuidString, $0.label, $0.noteID.uuidString,
             $0.notePath, $0.noteTitle, $0.quotedSnippet, timestamp($0.sourceModifiedAt),
             $0.citationStatus.rawValue]
        }
        return csv(rows)
    }

    private static func analysisReviewsCSV(_ items: [AnalysisReview]) -> String {
        var rows = [["id", "analysis_id", "decision", "notes", "reviewed_at"]]
        rows += items.map { [$0.id.uuidString, $0.analysisID.uuidString, $0.decision.rawValue, $0.notes, timestamp($0.reviewedAt)] }
        return csv(rows)
    }

    private static func biasAuditsCSV(_ items: [BiasAudit]) -> String {
        var rows = [["id", "argument_id", "title", "scope_note", "origin", "analysis_id", "created_at"]]
        rows += items.map { [$0.id.uuidString, $0.argumentID.uuidString, $0.title, $0.scopeNote, $0.origin.rawValue, $0.analysisID?.uuidString ?? "", timestamp($0.createdAt)] }
        return csv(rows)
    }

    private static func biasConcernsCSV(_ items: [BiasConcern]) -> String {
        var rows = [["id", "audit_id", "kind", "potential_problem", "why_it_matters", "alternative_interpretations", "investigation_questions", "evidence_relationship_ids", "uncertainty", "origin", "disposition", "review_notes", "created_at", "modified_at"]]
        rows += items.map {
            [$0.id.uuidString, $0.auditID.uuidString, $0.kind.rawValue, $0.potentialProblem, $0.whyItMatters,
             $0.alternativeInterpretations, $0.investigationQuestions.joined(separator: " | "),
             $0.evidenceRelationshipIDs.map(\.uuidString).joined(separator: "; "), $0.uncertainty,
             $0.origin.rawValue, $0.disposition.rawValue, $0.reviewNotes, timestamp($0.createdAt), timestamp($0.modifiedAt)]
        }
        return csv(rows)
    }

    private static func deliberationSessionsCSV(_ items: [DeliberationSession]) -> String {
        var rows = [["id", "argument_id", "title", "provider", "model", "prompt_version", "disclosure", "status", "created_at", "completed_at"]]
        rows += items.map {
            [$0.id.uuidString, $0.argumentID.uuidString, $0.title, $0.provider, $0.model, $0.promptVersion,
             $0.disclosure, $0.status.rawValue, timestamp($0.createdAt), $0.completedAt.map(timestamp) ?? ""]
        }
        return csv(rows)
    }

    private static func deliberationMessagesCSV(_ items: [DeliberationMessage]) -> String {
        var rows = [["id", "session_id", "perspective", "phase", "content", "sequence", "model_generated", "created_at"]]
        rows += items.map {
            [$0.id.uuidString, $0.sessionID.uuidString, $0.perspective.rawValue, $0.phase.rawValue, $0.content,
             String($0.sequence), String($0.modelGenerated), timestamp($0.createdAt)]
        }
        return csv(rows)
    }

    private static func deliberationCitationsCSV(_ items: [DeliberationCitation]) -> String {
        var rows = [["id", "message_id", "label", "literature_id", "source_passage_id", "page", "quoted_passage", "source_document_hash", "citation_status"]]
        rows += items.map {
            [$0.id.uuidString, $0.messageID.uuidString, $0.label, $0.literatureID.uuidString, $0.sourcePassageID,
             String($0.page), $0.quotedPassage, $0.sourceDocumentHash ?? "", $0.citationStatus.rawValue]
        }
        return csv(rows)
    }

    private static func writingDocumentsCSV(_ items: [WritingDocument]) -> String {
        var rows = [["id", "project_id", "question_id", "title", "purpose", "status", "notes", "created_at", "modified_at"]]
        rows += items.map {
            [$0.id.uuidString, $0.projectID?.uuidString ?? "", $0.questionID?.uuidString ?? "", $0.title,
             $0.purpose.rawValue, $0.status, $0.notes, timestamp($0.createdAt), timestamp($0.modifiedAt)]
        }
        return csv(rows)
    }

    private static func writingSectionsCSV(_ items: [WritingSection]) -> String {
        var rows = [["id", "document_id", "title", "body", "position", "notes", "created_at", "modified_at"]]
        rows += items.map {
            [$0.id.uuidString, $0.documentID.uuidString, $0.title, $0.body, String($0.position), $0.notes,
             timestamp($0.createdAt), timestamp($0.modifiedAt)]
        }
        return csv(rows)
    }

    private static func writingEvidenceLinksCSV(_ items: [WritingEvidenceLink]) -> String {
        var rows = [["id", "section_id", "target_type", "target_id", "citation_key", "rationale", "created_at"]]
        rows += items.map {
            [$0.id.uuidString, $0.sectionID.uuidString, $0.targetType.rawValue, $0.targetID,
             $0.citationKey ?? "", $0.rationale, timestamp($0.createdAt)]
        }
        return csv(rows)
    }

    private static func citationSupportReviewsCSV(_ items: [CitationSupportReview]) -> String {
        var rows = [["id", "section_id", "statement", "evidence_link_id", "assessment", "concern", "origin", "model_identifier", "prompt_version", "review_notes", "created_at", "modified_at"]]
        rows += items.map {
            [$0.id.uuidString, $0.sectionID.uuidString, $0.statement, $0.evidenceLinkID?.uuidString ?? "",
             $0.assessment.rawValue, $0.concern, $0.origin.rawValue, $0.modelIdentifier ?? "",
             $0.promptVersion ?? "", $0.reviewNotes, timestamp($0.createdAt), timestamp($0.modifiedAt)]
        }
        return csv(rows)
    }

    private static func collectiveExperimentsCSV(_ items: [CollectiveExperiment]) -> String {
        var rows = [["id", "title", "research_purpose", "task_instructions", "interaction_mode", "provider", "model", "model_settings_json", "prompt_version", "status", "validation_note", "created_at", "completed_at"]]
        rows += items.map {
            [$0.id.uuidString, $0.title, $0.researchPurpose, $0.taskInstructions, $0.interactionMode.rawValue,
             $0.provider, $0.model, $0.modelSettingsJSON, $0.promptVersion, $0.status.rawValue,
             $0.validationNote, timestamp($0.createdAt), $0.completedAt.map(timestamp) ?? ""]
        }
        return csv(rows)
    }

    private static func collectiveAgentsCSV(_ items: [CollectiveAgent]) -> String {
        var rows = [["id", "experiment_id", "label", "role", "information_available", "position", "created_at"]]
        rows += items.map {
            [$0.id.uuidString, $0.experimentID.uuidString, $0.label, $0.role, $0.informationAvailable,
             String($0.position), timestamp($0.createdAt)]
        }
        return csv(rows)
    }

    private static func collectiveTurnsCSV(_ items: [CollectiveTurn]) -> String {
        var rows = [["id", "experiment_id", "agent_id", "round", "sequence", "kind", "information_available", "prompt_text", "response_text", "confidence", "model_generated", "error_message", "created_at"]]
        rows += items.map { item -> [String] in
            [item.id.uuidString, item.experimentID.uuidString, item.agentID?.uuidString ?? "", "\(item.round)",
             "\(item.sequence)", item.kind.rawValue, item.informationAvailable, item.promptText, item.responseText,
             item.confidence.map { String($0) } ?? "", String(item.modelGenerated), item.errorMessage ?? "", timestamp(item.createdAt)]
        }
        return csv(rows)
    }

    private static func collectiveTurnCitationsCSV(_ items: [CollectiveTurnCitation]) -> String {
        var rows = [["id", "turn_id", "label", "literature_id", "source_passage_id", "page", "quoted_passage", "source_document_hash", "citation_status"]]
        rows += items.map {
            [$0.id.uuidString, $0.turnID.uuidString, $0.label, $0.literatureID.uuidString, $0.sourcePassageID,
             String($0.page), $0.quotedPassage, $0.sourceDocumentHash ?? "", $0.citationStatus.rawValue]
        }
        return csv(rows)
    }

    private static func csv(_ rows: [[String]]) -> String {
        rows.map { $0.map(escapeCSV).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    private static func escapeCSV(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func jsonString<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func singleLine(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
