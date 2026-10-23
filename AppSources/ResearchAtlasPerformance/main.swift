import Foundation
import ResearchAtlasCore

private struct Options {
    var paperCount = 3_000
    var pagesPerPaper = 12
    var iterations = 40
    var outputPath: String?

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            guard index + 1 < arguments.count else {
                throw BenchmarkError.invalidArguments("Missing value for \(flag).")
            }
            let value = arguments[index + 1]
            switch flag {
            case "--papers":
                guard let parsed = Int(value), parsed > 0 else {
                    throw BenchmarkError.invalidArguments("--papers must be a positive integer.")
                }
                paperCount = parsed
            case "--pages-per-paper":
                guard let parsed = Int(value), parsed > 0 else {
                    throw BenchmarkError.invalidArguments("--pages-per-paper must be a positive integer.")
                }
                pagesPerPaper = parsed
            case "--iterations":
                guard let parsed = Int(value), parsed >= 5 else {
                    throw BenchmarkError.invalidArguments("--iterations must be at least 5.")
                }
                iterations = parsed
            case "--output":
                outputPath = value
            default:
                throw BenchmarkError.invalidArguments("Unknown option \(flag).")
            }
            index += 2
        }
    }
}

private enum BenchmarkError: Error, LocalizedError {
    case invalidArguments(String)
    case validation(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message), .validation(let message): message
        }
    }
}

private struct TimingSummary: Codable {
    let operation: String
    let samples: Int
    let minimumMilliseconds: Double
    let medianMilliseconds: Double
    let p95Milliseconds: Double
    let maximumMilliseconds: Double
}

private struct EnvironmentSummary: Codable {
    let operatingSystem: String
    let processorCount: Int
    let activeProcessorCount: Int
    let physicalMemoryBytes: UInt64
}

private struct PerformanceReport: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let dataset: String
    let paperCount: Int
    let passageCount: Int
    let databaseBytes: Int64
    let ingestionSeconds: Double
    let rebuildSeconds: Double
    let measurements: [TimingSummary]
    let correctnessChecks: [String]
    let environment: EnvironmentSummary
}

private let topics = [
    "calibration", "diversity", "herding", "replication", "causality", "uncertainty"
]

private let benchmarkQueries = [
    "calibration evidence",
    "diversity evidence",
    "herding evidence",
    "replication evidence",
    "causality evidence",
    "uncertainty evidence"
]

private func elapsedMilliseconds<T>(_ body: () throws -> T) rethrows -> (T, Double) {
    let start = DispatchTime.now().uptimeNanoseconds
    let value = try body()
    let end = DispatchTime.now().uptimeNanoseconds
    return (value, Double(end - start) / 1_000_000)
}

private func percentile(_ sortedValues: [Double], _ percentile: Double) -> Double {
    guard !sortedValues.isEmpty else { return 0 }
    let rawIndex = percentile * Double(sortedValues.count - 1)
    let lower = Int(rawIndex.rounded(.down))
    let upper = Int(rawIndex.rounded(.up))
    if lower == upper { return sortedValues[lower] }
    let fraction = rawIndex - Double(lower)
    return sortedValues[lower] + ((sortedValues[upper] - sortedValues[lower]) * fraction)
}

private func summary(_ operation: String, values: [Double]) -> TimingSummary {
    let sorted = values.sorted()
    return TimingSummary(
        operation: operation,
        samples: sorted.count,
        minimumMilliseconds: sorted.first ?? 0,
        medianMilliseconds: percentile(sorted, 0.5),
        p95Milliseconds: percentile(sorted, 0.95),
        maximumMilliseconds: sorted.last ?? 0
    )
}

private func syntheticPages(paperIndex: Int, count: Int) -> [String] {
    let primary = topics[paperIndex % topics.count]
    let comparison = topics[(paperIndex + 1) % topics.count]
    return (1...count).map { page in
        """
        Synthetic benchmark passage \(paperIndex)-\(page). The study reports \(primary) evidence in a controlled research setting. It compares \(primary) with \(comparison), records uncertainty explicitly, and preserves the page-level source boundary. Unique marker atlas\(paperIndex)-\(page).
        """
    }
}

private func seed(database: AtlasDatabase, options: Options) throws {
    for index in 0..<options.paperCount {
        let topic = topics[index % topics.count]
        let comparison = topics[(index + 1) % topics.count]
        let item = LiteratureItem(
            title: "Synthetic \(topic.capitalized) Study \(String(format: "%05d", index))",
            authors: "Benchmark Author \(index % 200)",
            year: 1990 + (index % 36),
            abstract: "A synthetic evaluation of \(topic) evidence compared with \(comparison).",
            doi: "10.9999/research-atlas.\(index)",
            citationKey: "AtlasSynthetic\(index)",
            tags: [topic, comparison, "synthetic-benchmark"],
            source: .manual
        )
        try database.upsertLiterature(
            item,
            indexingPDFPages: syntheticPages(paperIndex: index, count: options.pagesPerPaper)
        )
        if (index + 1).isMultiple(of: 250) || index + 1 == options.paperCount {
            print("Seeded \(index + 1)/\(options.paperCount) synthetic papers", terminator: "\r")
            fflush(stdout)
        }
    }
    print("")
}

private func validateSearchResults(_ results: [SearchResult], query: String) throws {
    guard !results.isEmpty else {
        throw BenchmarkError.validation("Search returned no result for '\(query)'.")
    }
    let firstTerm = query.split(separator: " ").first.map(String.init) ?? query
    guard results.contains(where: {
        $0.title.localizedCaseInsensitiveContains(firstTerm) ||
        $0.snippet.localizedCaseInsensitiveContains(firstTerm)
    }) else {
        throw BenchmarkError.validation("Search results did not preserve the expected term '\(firstTerm)'.")
    }
}

private func run() throws {
    let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ResearchAtlasPerformance-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let databaseURL = root.appendingPathComponent("performance.sqlite3")
    let database = try AtlasDatabase(url: databaseURL)
    let (_, ingestionMilliseconds) = try elapsedMilliseconds {
        try seed(database: database, options: options)
    }

    var correctness = [String]()
    let metrics = try database.metrics()
    guard metrics.literatureCount == options.paperCount else {
        throw BenchmarkError.validation("Expected \(options.paperCount) papers; database reported \(metrics.literatureCount).")
    }
    correctness.append("All synthetic literature records were persisted.")

    for query in benchmarkQueries {
        try validateSearchResults(try database.search(query, limit: 100), query: query)
    }
    correctness.append("Every benchmark query returned a labelled FTS result.")

    var searchTimes = [Double]()
    var retrievalTimes = [Double]()
    var filteredLibraryTimes = [Double]()
    var allMetadataTimes = [Double]()

    for iteration in 0..<options.iterations {
        let query = benchmarkQueries[iteration % benchmarkQueries.count]
        let (searchResults, searchMilliseconds) = try elapsedMilliseconds {
            try database.search(query, limit: 100)
        }
        try validateSearchResults(searchResults, query: query)
        searchTimes.append(searchMilliseconds)

        let (filteredItems, filteredMilliseconds) = try elapsedMilliseconds {
            try database.literatureItems(matching: query.split(separator: " ").first.map(String.init) ?? query)
        }
        guard !filteredItems.isEmpty else {
            throw BenchmarkError.validation("Filtered library lookup returned no result for '\(query)'.")
        }
        filteredLibraryTimes.append(filteredMilliseconds)

        let (allItems, allMetadataMilliseconds) = try elapsedMilliseconds {
            try database.literatureItems()
        }
        guard allItems.count == options.paperCount else {
            throw BenchmarkError.validation("Full metadata load returned \(allItems.count) records.")
        }
        allMetadataTimes.append(allMetadataMilliseconds)

        let retrievalSet = RetrievalSet(name: "Performance \(iteration)", query: query)
        let (retrieved, retrievalMilliseconds) = try elapsedMilliseconds {
            try database.createRetrievalSet(retrievalSet, limit: 40)
        }
        guard !retrieved.isEmpty, retrieved.allSatisfy({ $0.citationStatus == .current }) else {
            throw BenchmarkError.validation("Grounded retrieval failed for '\(query)'.")
        }
        let stored = try database.retrievedPassages(retrievalSetID: retrievalSet.id)
        guard stored.count == retrieved.count, stored.allSatisfy({ $0.citationStatus == .current }) else {
            throw BenchmarkError.validation("Stored retrieval snapshots were missing or stale.")
        }
        try database.deleteRetrievalSet(id: retrievalSet.id)
        retrievalTimes.append(retrievalMilliseconds)
    }
    correctness.append("Grounded retrieval returned only current, persisted source snapshots.")
    correctness.append("Full and filtered library loads retained the expected record count.")

    let (_, rebuildMilliseconds) = try elapsedMilliseconds {
        try database.rebuildSearchIndex()
    }
    try validateSearchResults(try database.search(benchmarkQueries[0], limit: 100), query: benchmarkQueries[0])
    correctness.append("A complete FTS rebuild preserved searchable passage provenance.")

    let attributes = try FileManager.default.attributesOfItem(atPath: databaseURL.path)
    let databaseBytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    let process = ProcessInfo.processInfo
    let measurements = [
        summary("Global FTS search", values: searchTimes),
        summary("Grounded retrieval set creation", values: retrievalTimes),
        summary("Filtered literature load", values: filteredLibraryTimes),
        summary("Complete literature metadata load", values: allMetadataTimes)
    ]
    let report = PerformanceReport(
        schemaVersion: 1,
        generatedAt: Date(),
        dataset: "Deterministic synthetic corpus; no personal files or database content",
        paperCount: options.paperCount,
        passageCount: options.paperCount * options.pagesPerPaper,
        databaseBytes: databaseBytes,
        ingestionSeconds: ingestionMilliseconds / 1_000,
        rebuildSeconds: rebuildMilliseconds / 1_000,
        measurements: measurements,
        correctnessChecks: correctness,
        environment: EnvironmentSummary(
            operatingSystem: process.operatingSystemVersionString,
            processorCount: process.processorCount,
            activeProcessorCount: process.activeProcessorCount,
            physicalMemoryBytes: process.physicalMemory
        )
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(report)
    if let outputPath = options.outputPath {
        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: outputURL, options: .atomic)
        print("Report: \(outputURL.path)")
    }

    print("Synthetic corpus: \(report.paperCount) papers / \(report.passageCount) passages")
    print(String(format: "Ingestion: %.2f s · FTS rebuild: %.2f s · Database: %.1f MB", report.ingestionSeconds, report.rebuildSeconds, Double(report.databaseBytes) / 1_048_576))
    for measurement in measurements {
        print(String(format: "%@: median %.2f ms · p95 %.2f ms · max %.2f ms", measurement.operation, measurement.medianMilliseconds, measurement.p95Milliseconds, measurement.maximumMilliseconds))
    }
    print("All \(correctness.count) performance correctness checks passed.")
}

do {
    try run()
} catch {
    fputs("PERFORMANCE PROFILE FAILED: \(error.localizedDescription)\n", stderr)
    exit(1)
}
