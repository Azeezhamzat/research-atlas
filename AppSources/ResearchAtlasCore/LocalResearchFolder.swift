import Foundation

public enum LocalResearchFolderError: Error, LocalizedError {
    case notDirectory
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .notDirectory: "The selected research library is not a folder."
        case .unreadable: "Research Atlas could not read the selected research folder."
        }
    }
}

public enum LocalResearchFolderScanner {
    /// Finds readable PDFs without following symbolic links, entering hidden folders, or
    /// descending into application packages. The source folder and its files are never changed.
    public static func discoverPDFs(at root: URL) throws -> [URL] {
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey])
        guard values.isDirectory == true else { throw LocalResearchFolderError.notDirectory }
        guard values.isReadable != false else { throw LocalResearchFolderError.unreadable }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isReadableKey, .isSymbolicLinkKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            throw LocalResearchFolderError.unreadable
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame,
                  let resourceValues = try? url.resourceValues(forKeys: keys),
                  resourceValues.isRegularFile == true,
                  resourceValues.isReadable != false,
                  resourceValues.isSymbolicLink != true else { continue }
            urls.append(url)
        }
        return urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
