import CryptoKit
import Foundation
import PDFKit

public struct PDFIndexResult: Sendable {
    public let pages: [String]
    public let hasMachineReadableText: Bool

    public init(pages: [String], hasMachineReadableText: Bool) {
        self.pages = pages
        self.hasMachineReadableText = hasMachineReadableText
    }
}

public enum PDFIndexingError: Error, LocalizedError {
    case unreadable
    case changedDuringRelink

    public var errorDescription: String? {
        switch self {
        case .unreadable: "The PDF could not be opened by PDFKit."
        case .changedDuringRelink: "The selected PDF changed after it was previewed. Choose it again before repairing the link."
        }
    }
}

public enum PDFIndexer {
    public static func extractText(from url: URL) throws -> PDFIndexResult {
        guard let document = PDFDocument(url: url) else { throw PDFIndexingError.unreadable }
        var pages: [String] = []
        pages.reserveCapacity(document.pageCount)
        var nonWhitespaceCharacters = 0
        for pageNumber in 0..<document.pageCount {
            let text = document.page(at: pageNumber)?.string ?? ""
            pages.append(text)
            nonWhitespaceCharacters += text.filter { !$0.isWhitespace }.count
        }
        return PDFIndexResult(pages: pages, hasMachineReadableText: nonWhitespaceCharacters > 20)
    }
}

public enum PDFFileInspector {
    public static func availability(for path: String?) -> PDFFileAvailability {
        guard let path else { return .notLinked }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: path) else { return .missing }
        return .available
    }

    public static func availability(for item: LiteratureItem) -> PDFFileAvailability {
        let base = availability(for: item.pdfPath)
        guard base == .available, let path = item.pdfPath,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return base }
        if let expectedSize = item.pdfByteCount,
           let currentSize = (attributes[.size] as? NSNumber)?.int64Value,
           expectedSize != currentSize {
            return .changed
        }
        if let verifiedAt = item.pdfLastVerifiedAt,
           let modifiedAt = attributes[.modificationDate] as? Date,
           modifiedAt.timeIntervalSince(verifiedAt) > 1 {
            return .changed
        }
        return .available
    }

    public static func fingerprint(at url: URL) throws -> PDFFileFingerprint {
        guard availability(for: url.path) == .available else { throw PDFIndexingError.unreadable }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return PDFFileFingerprint(byteCount: byteCount, sha256: digest)
    }
}
