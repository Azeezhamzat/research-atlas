import Foundation

public struct ObsidianImportResult: Sendable {
    public let notes: [ObsidianNote]
    public let failures: [String]

    public init(notes: [ObsidianNote], failures: [String]) {
        self.notes = notes
        self.failures = failures
    }
}

public enum ObsidianIntegration {
    public static func discoverNotes(in vaultURL: URL) -> ObsidianImportResult {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return ObsidianImportResult(notes: [], failures: ["The selected folder could not be read."])
        }

        var notes: [ObsidianNote] = []
        var failures: [String] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "md" {
            do {
                let values = try fileURL.resourceValues(forKeys: Set(keys))
                guard values.isRegularFile == true else { continue }
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                notes.append(parse(content: content, url: fileURL, modifiedAt: values.contentModificationDate ?? Date()))
            } catch {
                failures.append("\(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return ObsidianImportResult(notes: notes, failures: failures)
    }

    public static func parse(content: String, url: URL, modifiedAt: Date = Date()) -> ObsidianNote {
        let title = firstMatch(in: content, pattern: #"(?m)^#\s+(.+)$"#)
            ?? frontmatterValue(named: "title", in: content)
            ?? url.deletingPathExtension().lastPathComponent
        let tags = Set(
            matches(in: content, pattern: #"(?<![\p{L}\p{N}_])#([\p{L}\p{N}_/-]+)"#)
            + frontmatterList(named: "tags", in: content)
        )
        let wikilinks = Set(matches(in: content, pattern: #"\[\[([^\]|#]+)(?:[#|][^\]]*)?\]\]"#))
        let citationKeys = Set(matches(in: content, pattern: #"(?<![\p{L}\p{N}_])@([A-Za-z][A-Za-z0-9_:-]{2,})"#))
        let dois = Set(matches(in: content, pattern: #"(?i)\b(10\.\d{4,9}/[-._;()/:A-Z0-9]+)"#).map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:)]}"))
        })
        return ObsidianNote(
            path: url.path,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            content: content,
            tags: tags.sorted(),
            wikilinks: wikilinks.sorted(),
            citationKeys: citationKeys.sorted(),
            dois: dois.sorted(),
            modifiedAt: modifiedAt
        )
    }

    private static func frontmatterValue(named key: String, in content: String) -> String? {
        guard content.hasPrefix("---\n"), let end = content.range(of: "\n---", range: content.index(content.startIndex, offsetBy: 4)..<content.endIndex) else { return nil }
        let block = String(content[content.index(content.startIndex, offsetBy: 4)..<end.lowerBound])
        return firstMatch(in: block, pattern: "(?m)^\(NSRegularExpression.escapedPattern(for: key))\\s*:\\s*[\"']?([^\\n\"']+)")
    }

    private static func frontmatterList(named key: String, in content: String) -> [String] {
        guard let value = frontmatterValue(named: key, in: content) else { return [] }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'"))) }
            .filter { !$0.isEmpty }
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        matches(in: text, pattern: pattern).first
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern), !text.isEmpty else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let swiftRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[swiftRange])
        }
    }
}
