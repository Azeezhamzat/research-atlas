import Foundation

public enum LiteratureComparisonField: String, CaseIterable, Codable, Sendable {
    case researchQuestion = "Research question"
    case theoreticalFramework = "Theoretical framework"
    case studyDesign = "Study design"
    case sample = "Sample or population"
    case independentVariables = "Independent variables"
    case dependentVariables = "Dependent variables"
    case operationalDefinitions = "Operational definitions"
    case mainFindings = "Main findings"
    case limitations = "Limitations"
}

public struct LiteratureCoverageFieldSummary: Identifiable, Hashable, Codable, Sendable {
    public var id: String { field.rawValue }
    public let field: LiteratureComparisonField
    public let recordedCount: Int
    public let linkedCount: Int
    public let missingLiteratureIDs: [UUID]

    public var fraction: Double {
        linkedCount == 0 ? 0 : Double(recordedCount) / Double(linkedCount)
    }

    public init(
        field: LiteratureComparisonField,
        recordedCount: Int,
        linkedCount: Int,
        missingLiteratureIDs: [UUID]
    ) {
        self.field = field
        self.recordedCount = recordedCount
        self.linkedCount = linkedCount
        self.missingLiteratureIDs = missingLiteratureIDs
    }
}

public struct LiteratureCoverageCategory: Identifiable, Hashable, Codable, Sendable {
    public var id: String { label.lowercased() }
    public let label: String
    public let count: Int

    public init(label: String, count: Int) {
        self.label = label
        self.count = count
    }
}

public struct LiteratureCoveragePaper: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let title: String
    public let year: Int?
    public let sourceAvailability: SourceAvailability
    public let recordedComparisonFieldCount: Int
    public let comparisonFieldCount: Int

    public var completionFraction: Double {
        comparisonFieldCount == 0 ? 0 : Double(recordedComparisonFieldCount) / Double(comparisonFieldCount)
    }

    public init(
        id: UUID,
        title: String,
        year: Int?,
        sourceAvailability: SourceAvailability,
        recordedComparisonFieldCount: Int,
        comparisonFieldCount: Int
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.sourceAvailability = sourceAvailability
        self.recordedComparisonFieldCount = recordedComparisonFieldCount
        self.comparisonFieldCount = comparisonFieldCount
    }
}

public struct LiteratureCoverageReport: Hashable, Codable, Sendable {
    public let linkedCount: Int
    public let availableCount: Int
    public let knownYearCount: Int
    public let earliestYear: Int?
    public let latestYear: Int?
    public let profiledCount: Int
    public let fullyProfiledCount: Int
    public let yearDistribution: [LiteratureCoverageCategory]
    public let topicDistribution: [LiteratureCoverageCategory]
    public let frameworkDistribution: [LiteratureCoverageCategory]
    public let designDistribution: [LiteratureCoverageCategory]
    public let fields: [LiteratureCoverageFieldSummary]
    public let papers: [LiteratureCoveragePaper]
    public let attentionNotes: [String]

    public var scopeStatement: String {
        "This audit describes only the papers linked to this question and the metadata recorded in Research Atlas. It does not measure the wider literature or establish a research gap."
    }

    public init(
        linkedCount: Int,
        availableCount: Int,
        knownYearCount: Int,
        earliestYear: Int?,
        latestYear: Int?,
        profiledCount: Int,
        fullyProfiledCount: Int,
        yearDistribution: [LiteratureCoverageCategory],
        topicDistribution: [LiteratureCoverageCategory],
        frameworkDistribution: [LiteratureCoverageCategory],
        designDistribution: [LiteratureCoverageCategory],
        fields: [LiteratureCoverageFieldSummary],
        papers: [LiteratureCoveragePaper],
        attentionNotes: [String]
    ) {
        self.linkedCount = linkedCount
        self.availableCount = availableCount
        self.knownYearCount = knownYearCount
        self.earliestYear = earliestYear
        self.latestYear = latestYear
        self.profiledCount = profiledCount
        self.fullyProfiledCount = fullyProfiledCount
        self.yearDistribution = yearDistribution
        self.topicDistribution = topicDistribution
        self.frameworkDistribution = frameworkDistribution
        self.designDistribution = designDistribution
        self.fields = fields
        self.papers = papers
        self.attentionNotes = attentionNotes
    }
}

public enum LiteratureCoverageAnalyzer {
    public static func analyze(
        literature: [LiteratureItem],
        comparisonProfiles: [LiteratureComparisonProfile]
    ) -> LiteratureCoverageReport {
        let linked = literature.sorted {
            if $0.year != $1.year { return ($0.year ?? Int.max) < ($1.year ?? Int.max) }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        let linkedIDs = Set(linked.map(\.id))
        let profiles = comparisonProfiles.filter { linkedIDs.contains($0.literatureID) }
        let profilesByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.literatureID, $0) })
        let comparisonFieldCount = LiteratureComparisonField.allCases.count

        let fields = LiteratureComparisonField.allCases.map { field in
            let missingIDs = linked.compactMap { paper -> UUID? in
                guard let profile = profilesByID[paper.id], value(for: field, in: profile).isRecorded else {
                    return paper.id
                }
                return nil
            }
            return LiteratureCoverageFieldSummary(
                field: field,
                recordedCount: linked.count - missingIDs.count,
                linkedCount: linked.count,
                missingLiteratureIDs: missingIDs
            )
        }

        let paperSummaries = linked.map { paper in
            let recordedCount = profilesByID[paper.id].map { profile in
                LiteratureComparisonField.allCases.filter { value(for: $0, in: profile).isRecorded }.count
            } ?? 0
            return LiteratureCoveragePaper(
                id: paper.id,
                title: paper.title,
                year: paper.year,
                sourceAvailability: paper.sourceAvailability,
                recordedComparisonFieldCount: recordedCount,
                comparisonFieldCount: comparisonFieldCount
            )
        }

        let years = linked.compactMap(\.year)
        let yearDistribution = categories(years.map(String.init), limit: nil) {
            guard let left = Int($0.label), let right = Int($1.label) else { return $0.label < $1.label }
            return left < right
        }
        let topicDistribution = categories(linked.flatMap(\.tags), limit: 8)
        let frameworkDistribution = categories(profiles.map(\.theoreticalFramework), limit: 8)
        let designDistribution = categories(profiles.map(\.studyDesign), limit: 8)
        let availableCount = linked.filter { $0.sourceAvailability == .available }.count
        let fullyProfiledCount = paperSummaries.filter { $0.recordedComparisonFieldCount == comparisonFieldCount }.count

        var notes: [String] = []
        if linked.isEmpty {
            notes.append("Link papers to this question before interpreting its coverage.")
        } else {
            let missingYears = linked.count - years.count
            if missingYears > 0 {
                notes.append("Publication year is missing for \(missingYears) linked paper\(missingYears == 1 ? "" : "s").")
            }
            let missingProfiles = linked.count - profiles.count
            if missingProfiles > 0 {
                notes.append("\(missingProfiles) linked paper\(missingProfiles == 1 ? " has" : "s have") no comparison profile yet.")
            }
            if availableCount < linked.count {
                let unavailable = linked.count - availableCount
                notes.append("\(unavailable) linked source record\(unavailable == 1 ? " is" : "s are") not currently available.")
            }
            for importantField in [LiteratureComparisonField.studyDesign, .sample, .mainFindings, .limitations] {
                guard let summary = fields.first(where: { $0.field == importantField }), summary.recordedCount < linked.count else { continue }
                notes.append("\(importantField.rawValue) is unrecorded for \(linked.count - summary.recordedCount) linked paper\(linked.count - summary.recordedCount == 1 ? "" : "s").")
            }
            if designDistribution.count == 1, let design = designDistribution.first, profiles.count > 1 {
                notes.append("All recorded profiles currently use the study-design label “\(design.label)”. This describes the linked set only; it is not evidence of a wider methodological gap.")
            }
        }

        return LiteratureCoverageReport(
            linkedCount: linked.count,
            availableCount: availableCount,
            knownYearCount: years.count,
            earliestYear: years.min(),
            latestYear: years.max(),
            profiledCount: profiles.count,
            fullyProfiledCount: fullyProfiledCount,
            yearDistribution: yearDistribution,
            topicDistribution: topicDistribution,
            frameworkDistribution: frameworkDistribution,
            designDistribution: designDistribution,
            fields: fields,
            papers: paperSummaries,
            attentionNotes: notes
        )
    }

    private static func value(
        for field: LiteratureComparisonField,
        in profile: LiteratureComparisonProfile
    ) -> String {
        switch field {
        case .researchQuestion: profile.researchQuestion
        case .theoreticalFramework: profile.theoreticalFramework
        case .studyDesign: profile.studyDesign
        case .sample: profile.sample
        case .independentVariables: profile.independentVariables
        case .dependentVariables: profile.dependentVariables
        case .operationalDefinitions: profile.operationalDefinitions
        case .mainFindings: profile.mainFindings
        case .limitations: profile.limitations
        }
    }

    private static func categories(
        _ values: [String],
        limit: Int?,
        sortedBy: ((LiteratureCoverageCategory, LiteratureCoverageCategory) -> Bool)? = nil
    ) -> [LiteratureCoverageCategory] {
        var originals: [String: String] = [:]
        var counts: [String: Int] = [:]
        for rawValue in values {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let key = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if let existing = originals[key] {
                let valueStartsUppercase = value.first.map { String($0) == String($0).uppercased() } ?? false
                let existingStartsUppercase = existing.first.map { String($0) == String($0).uppercased() } ?? false
                if valueStartsUppercase != existingStartsUppercase {
                    if valueStartsUppercase { originals[key] = value }
                } else if value.localizedStandardCompare(existing) == .orderedAscending {
                    originals[key] = value
                }
            } else {
                originals[key] = value
            }
            counts[key, default: 0] += 1
        }
        var result = counts.map { key, count in
            LiteratureCoverageCategory(label: originals[key] ?? key, count: count)
        }
        if let sortedBy {
            result.sort(by: sortedBy)
        } else {
            result.sort {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
            }
        }
        if let limit { return Array(result.prefix(limit)) }
        return result
    }
}

private extension String {
    var isRecorded: Bool {
        !trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
