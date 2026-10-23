import Foundation

public struct BiasAuditDraft: Sendable {
    public var audit: BiasAudit
    public var concerns: [BiasConcern]

    public init(audit: BiasAudit, concerns: [BiasConcern]) {
        self.audit = audit
        self.concerns = concerns
    }
}

public enum LocalBiasAuditor {
    public static func makeDraft(
        argument: ResearchArgument,
        evidence: [EvidenceRelationship],
        literature: [LiteratureItem],
        comparisonProfiles: [LiteratureComparisonProfile]
    ) -> BiasAuditDraft {
        let now = Date()
        let audit = BiasAudit(
            argumentID: argument.id,
            title: "Critical review: \(argument.proposition)",
            scopeNote: "Locally generated investigation prompts derived from the argument and its recorded evidence. These are not findings that the researcher is biased.",
            origin: .localSuggestion,
            createdAt: now
        )
        let supporting = evidence.filter { $0.relation == .supports }
        let countervailing = evidence.filter {
            $0.relation == .challenges || $0.relation == .qualifies || $0.relation == .alternative
        }
        let literatureIDs = Set(evidence.map(\.literatureID))
        let profilesByID = Dictionary(uniqueKeysWithValues: comparisonProfiles.map { ($0.literatureID, $0) })
        var concerns: [BiasConcern] = []

        func concern(
            _ kind: BiasConcernKind, _ problem: String, _ why: String,
            alternatives: String = "", questions: [String], evidenceIDs: [UUID] = []
        ) -> BiasConcern {
            BiasConcern(
                auditID: audit.id, kind: kind, potentialProblem: problem, whyItMatters: why,
                alternativeInterpretations: alternatives, investigationQuestions: questions,
                evidenceRelationshipIDs: evidenceIDs, uncertainty: "Rule-based prompt; requires human evaluation against the cited sources.",
                origin: .localSuggestion, createdAt: now, modifiedAt: now
            )
        }

        if evidence.isEmpty {
            concerns.append(concern(
                .evidenceScope,
                "The argument currently has no recorded evidence relationships.",
                "Without source-linked evidence, the scope and limits of the proposition cannot be checked inside Research Atlas.",
                questions: ["Which exact passages would support, qualify, or challenge this proposition?", "What evidence would change your current interpretation?"]
            ))
        } else {
            if !supporting.isEmpty && countervailing.isEmpty {
                concerns.append(concern(
                    .selectiveEvidence,
                    "The recorded evidence is supportive or extending, with no challenging, qualifying, contradictory, or alternative-explanation relationship.",
                    "This may reflect the current state of data entry rather than the literature, but it leaves the argument untested against counterevidence.",
                    alternatives: "Relevant counterevidence may exist outside the current library or may not yet have been linked.",
                    questions: ["Which finding would most strongly challenge this proposition?", "Have qualification and null-result passages been searched for explicitly?"],
                    evidenceIDs: supporting.map(\.id)
                ))
            }
            let unverified = evidence.filter { $0.verification != .verified }
            if !unverified.isEmpty {
                concerns.append(concern(
                    .evidenceScope,
                    "\(unverified.count) of \(evidence.count) linked evidence records remain unverified or rejected.",
                    "A proposition may appear better supported than it is if review status is not considered.",
                    questions: ["Which unverified relationship should be checked against its original passage first?", "Should any rejected relationship be removed from the working interpretation?"],
                    evidenceIDs: unverified.map(\.id)
                ))
            }
            if literatureIDs.count <= 1 {
                let title = literature.first { literatureIDs.contains($0.id) }?.title ?? "the only linked source"
                concerns.append(concern(
                    .sourceConcentration,
                    "All recorded evidence comes from \(title).",
                    "A single source cannot show how the proposition travels across authors, contexts, methods, or populations.",
                    alternatives: "A tightly bounded argument may legitimately rely on one study, if that boundary is explicit.",
                    questions: ["Is the proposition intentionally limited to this source's context?", "Which independent source would provide the most informative comparison?"],
                    evidenceIDs: evidence.map(\.id)
                ))
            }
        }

        if argument.qualification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            concerns.append(concern(
                .overgeneralisation,
                "No boundary conditions or methodological qualification have been recorded for the proposition.",
                "Population, task, intervention, measure, and study-design boundaries may materially change what the evidence supports.",
                questions: ["For which population, task, and form of intervention is the proposition intended to hold?", "Which conditions would make the proposition false or inapplicable?"],
                evidenceIDs: evidence.map(\.id)
            ))
        }

        let recordedDesigns = literatureIDs.compactMap { profilesByID[$0]?.studyDesign.nilIfEmpty }
        if Set(recordedDesigns.map { $0.lowercased() }).count > 1 {
            concerns.append(concern(
                .designMismatch,
                "The linked sources have different recorded study designs: \(recordedDesigns.joined(separator: "; ")).",
                "Findings from different designs may estimate different quantities and support different kinds of inference.",
                questions: ["Are outcomes, manipulations, samples, and comparison conditions sufficiently similar?", "Should each design support a narrower subclaim instead of one pooled proposition?"],
                evidenceIDs: evidence.map(\.id)
            ))
        }

        let causalTerms = ["cause", "causes", "caused", "lead to", "leads to", "reinforce", "drives", "results in"]
        let propositionUsesCausalLanguage = causalTerms.contains { argument.proposition.lowercased().contains($0) }
        let hasExperimentalDesign = recordedDesigns.contains {
            let value = $0.lowercased()
            return value.contains("experiment") || value.contains("random") || value.contains("intervention")
        }
        if propositionUsesCausalLanguage && !hasExperimentalDesign {
            concerns.append(concern(
                .correlationCausation,
                "The proposition uses causal language, but no linked comparison profile currently records an experimental, randomised, or intervention design.",
                "The database may simply lack method details; nevertheless, causal wording warrants checking the actual identification strategy.",
                alternatives: "The relationship may be associational, conditional, mediated, or explained by a third factor.",
                questions: ["Which design feature supports a causal interpretation?", "Would associational wording better match the current evidence?"],
                evidenceIDs: evidence.map(\.id)
            ))
        }

        if !evidence.isEmpty && !evidence.contains(where: { $0.relation == .alternative }) {
            concerns.append(concern(
                .alternativeExplanation,
                "No linked evidence relationship is currently classified as an alternative explanation.",
                "The same observation may be compatible with several mechanisms even when the empirical finding is reliable.",
                questions: ["What competing mechanism could generate the same observed pattern?", "Which source or design could discriminate between the preferred and alternative explanations?"],
                evidenceIDs: evidence.map(\.id)
            ))
        }

        return BiasAuditDraft(audit: audit, concerns: concerns)
    }
}

public struct DeliberationScaffold: Sendable {
    public var session: DeliberationSession
    public var messages: [DeliberationMessage]

    public init(session: DeliberationSession, messages: [DeliberationMessage]) {
        self.session = session
        self.messages = messages
    }
}

public enum LocalDeliberationScaffoldBuilder {
    public static func make(argument: ResearchArgument, evidence: [EvidenceRelationship]) -> DeliberationScaffold {
        let session = DeliberationSession(
            argumentID: argument.id,
            title: "Deliberation: \(argument.proposition)",
            provider: "Local structured prompts", model: "No model invoked",
            promptVersion: "local-deliberation-scaffold-v1",
            disclosure: "These are locally generated review prompts, not expert assessments. If model-generated perspectives are later added, they remain simulated roles produced by the configured model, not independent experts.",
            status: .inProgress
        )
        let evidenceSummary = evidence.isEmpty
            ? "No evidence relationships are currently linked."
            : "\(evidence.count) evidence relationships are linked: " + Dictionary(grouping: evidence, by: \.relation).map { "\($0.key.rawValue) \($0.value.count)" }.sorted().joined(separator: ", ") + "."
        let prompts: [(DeliberationPerspective, String)] = [
            (.theoretical, "Which concepts and causal mechanisms does the proposition assume? Identify competing frameworks and terms that need precise definition."),
            (.methodological, "Which designs, measures, populations, and validity constraints determine whether the linked studies can evaluate this proposition?"),
            (.evidence, "Inspect the exact linked passages. Which parts directly support the proposition, which only provide context, and which remain unverified? \(evidenceSummary)"),
            (.alternative, "What plausible mechanisms or boundary conditions could explain the same observations without the proposition being generally true?"),
            (.synthesis, "After the critical perspectives are answered, record only the conclusions supported across the inspected sources and preserve unresolved disagreements.")
        ]
        let messages = prompts.enumerated().map { index, prompt in
            DeliberationMessage(
                sessionID: session.id, perspective: prompt.0, phase: prompt.0 == .synthesis ? .synthesis : .initial,
                content: prompt.1, sequence: index + 1, modelGenerated: false
            )
        }
        return DeliberationScaffold(session: session, messages: messages)
    }
}

public struct CitationSupportSourceSnapshot: Hashable, Sendable {
    public var evidenceLinkID: UUID
    public var text: String
    public var verification: VerificationState

    public init(evidenceLinkID: UUID, text: String, verification: VerificationState) {
        self.evidenceLinkID = evidenceLinkID
        self.text = text
        self.verification = verification
    }
}

public enum LocalCitationSupportAuditor {
    public static func makeReviews(
        section: WritingSection,
        links: [WritingEvidenceLink],
        sources: [CitationSupportSourceSnapshot] = []
    ) -> [CitationSupportReview] {
        let statements = section.body
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 30 }
        guard !statements.isEmpty else { return [] }
        return statements.map { statement in
            if links.isEmpty {
                return CitationSupportReview(
                    sectionID: section.id, statement: statement,
                    assessment: .unsupported,
                    concern: "No evidence link is attached to this section. This does not prove the statement is false, but its support cannot be inspected here.",
                    origin: .localSuggestion
                )
            }
            guard let best = sources.max(by: { overlap(statement, $0.text) < overlap(statement, $1.text) }) else {
                return CitationSupportReview(
                    sectionID: section.id, statement: statement,
                    assessment: .requiresHumanReview,
                    concern: "Evidence is attached, but no inspectable source text could be resolved for a statement-level comparison.",
                    origin: .localSuggestion,
                    reviewNotes: "Link an exact claim or passage, then compare the statement with the original source."
                )
            }

            let score = overlap(statement, best.text)
            let statementTerms = normalisedTerms(statement)
            let sourceTerms = normalisedTerms(best.text)
            let causalTerms: Set<String> = ["cause", "causes", "caused", "causal", "leads", "produces", "results", "because"]
            let broadTerms: Set<String> = ["all", "always", "never", "proves", "universally", "inevitably", "every"]
            let qualificationTerms: Set<String> = ["may", "might", "conditional", "depends", "limited", "only", "however", "context", "association", "associated"]
            var concerns: [String] = []
            if score < 0.12 {
                concerns.append("The closest linked source shares little substantive terminology with this statement; it may address a different claim.")
            }
            if !statementTerms.isDisjoint(with: causalTerms), sourceTerms.isDisjoint(with: causalTerms) {
                concerns.append("The statement uses causal language, while the linked source text does not explicitly do so.")
            }
            if !statementTerms.isDisjoint(with: broadTerms), sourceTerms.isDisjoint(with: broadTerms) {
                concerns.append("The statement uses broad or universal wording that is not present in the linked source text.")
            }
            if !sourceTerms.isDisjoint(with: qualificationTerms), statementTerms.isDisjoint(with: qualificationTerms) {
                concerns.append("The source text contains qualifying language that may be missing from the statement.")
            }
            if best.verification != .verified {
                concerns.append("The closest linked evidence is \(best.verification.rawValue.lowercased()) and requires source review.")
            }
            let assessment: CitationSupportAssessment = concerns.isEmpty ? .requiresHumanReview : .partiallySupported
            let message = concerns.isEmpty
                ? "No obvious scope or causal-language mismatch was found in the closest linked text, but this local comparison cannot establish citation correctness."
                : concerns.joined(separator: " ")
            return CitationSupportReview(
                sectionID: section.id, statement: statement, evidenceLinkID: best.evidenceLinkID,
                assessment: assessment, concern: message, origin: .localSuggestion,
                reviewNotes: "Inspect the exact source and its study context before recording a human judgment. Lexical overlap is not conceptual equivalence."
            )
        }
    }

    private static func overlap(_ statement: String, _ source: String) -> Double {
        let statementTerms = normalisedTerms(statement)
        guard !statementTerms.isEmpty else { return 0 }
        return Double(statementTerms.intersection(normalisedTerms(source)).count) / Double(statementTerms.count)
    }

    private static func normalisedTerms(_ text: String) -> Set<String> {
        let stopWords: Set<String> = [
            "about", "after", "also", "among", "and", "are", "been", "before", "being", "between",
            "both", "but", "can", "could", "does", "from", "had", "has", "have", "into", "its", "more", "not",
            "other", "our", "than", "that", "the", "their", "there", "these", "they", "this", "those",
            "through", "under", "using", "was", "were", "which", "while", "with", "would"
        ]
        let words = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(words.filter { $0.count >= 3 && !stopWords.contains($0) })
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
