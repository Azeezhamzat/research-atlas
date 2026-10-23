import Foundation

public enum ZoteroError: Error, LocalizedError {
    case unavailable
    case disabled
    case serverChanged
    case libraryChangedDuringSync
    case unexpectedResponse(Int)
    case itemNotFound(String)
    case unauthorized
    case userIDMismatch(expected: String, actual: String)
    case libraryAccessDenied
    case responseFormat(endpoint: String, field: String)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Zotero is not responding at its local API. Open Zotero and try again."
        case .disabled: "Zotero's local API is disabled. In Zotero, enable Settings → Advanced → Allow other applications on this computer to communicate with Zotero."
        case .serverChanged: "Zotero switched profiles during the refresh. No checkpoint was saved; try again."
        case .libraryChangedDuringSync: "A Zotero library kept changing during the refresh. No checkpoint was saved; try again when the current Zotero changes have settled."
        case .unexpectedResponse(let code): "Zotero returned HTTP \(code)."
        case .itemNotFound(let key): "Zotero no longer contains item \(key) in the recorded library. The Research Atlas record was left unchanged."
        case .unauthorized: "Zotero rejected the Web API key. Create a dedicated read-only key in your Zotero account settings and try again."
        case .userIDMismatch(let expected, let actual): "The API key belongs to Zotero user ID \(actual), not the entered user ID \(expected). Nothing was imported."
        case .libraryAccessDenied: "The Zotero API key does not have read access to the requested library."
        case .responseFormat(let endpoint, let field):
            "Zotero returned an unsupported \(endpoint) response at \(field). No partial import was committed."
        case .invalidData: "Zotero returned data that Research Atlas could not understand."
        }
    }
}

public struct ZoteroConnectionInfo: Hashable, Sendable {
    public var endpoint: String
    public var serverID: String
    public var apiVersion: String?
    public var schemaVersion: String?
    public var checkedAt: Date

    public init(endpoint: String, serverID: String, apiVersion: String?, schemaVersion: String?, checkedAt: Date = Date()) {
        self.endpoint = endpoint
        self.serverID = serverID
        self.apiVersion = apiVersion
        self.schemaVersion = schemaVersion
        self.checkedAt = checkedAt
    }
}

public struct ZoteroItemRefresh: Sendable {
    public var item: LiteratureItem
    public var collectionKeys: [String]
    public var connection: ZoteroConnectionInfo
    public var apiPath: String

    public init(item: LiteratureItem, collectionKeys: [String], connection: ZoteroConnectionInfo, apiPath: String) {
        self.item = item
        self.collectionKeys = collectionKeys
        self.connection = connection
        self.apiPath = apiPath
    }
}

public struct ZoteroWebIdentity: Hashable, Sendable {
    public var userID: String
    public var username: String
    public var canReadUserLibrary: Bool
    public var canReadAllGroups: Bool

    public init(userID: String, username: String, canReadUserLibrary: Bool, canReadAllGroups: Bool) {
        self.userID = userID
        self.username = username
        self.canReadUserLibrary = canReadUserLibrary
        self.canReadAllGroups = canReadAllGroups
    }
}

/// Centralizes stable Zotero identities and request headers so UI links, API reads, and tests use the same routing rules.
public enum ZoteroAPIRouting {
    public static func apiPrefix(libraryID: String) -> String? {
        if libraryID == "user:0" { return "users/0" }
        if libraryID.hasPrefix("group:"), !libraryID.dropFirst("group:".count).isEmpty {
            return "groups/\(libraryID.dropFirst("group:".count))"
        }
        return nil
    }

    public static func itemPath(libraryID: String, itemKey: String) -> String? {
        guard let prefix = apiPrefix(libraryID: libraryID), !itemKey.isEmpty else { return nil }
        return "\(prefix)/items/\(itemKey)"
    }

    public static func itemSelectionURL(libraryID: String, itemKey: String) -> URL? {
        guard !itemKey.isEmpty else { return nil }
        if libraryID == "user:0" || libraryID.hasPrefix("web-user:") {
            return URL(string: "zotero://select/library/items/\(itemKey)")
        }
        if libraryID.hasPrefix("group:"), !libraryID.dropFirst("group:".count).isEmpty {
            return URL(string: "zotero://select/groups/\(libraryID.dropFirst("group:".count))/items/\(itemKey)")
        }
        return nil
    }

    public static func webItemPath(libraryID: String, itemKey: String, userID: String) -> String? {
        guard !itemKey.isEmpty, !userID.isEmpty else { return nil }
        if libraryID.hasPrefix("group:"), !libraryID.dropFirst("group:".count).isEmpty {
            return "groups/\(libraryID.dropFirst("group:".count))/items/\(itemKey)"
        }
        return "users/\(userID)/items/\(itemKey)"
    }

    public static func readRequest(url: URL, expectedServerID: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("3", forHTTPHeaderField: "Zotero-API-Version")
        if let expectedServerID {
            // Zotero's local API uses the same header name for the value returned by a prior response.
            request.setValue(expectedServerID, forHTTPHeaderField: "Zotero-Server-ID")
        }
        return request
    }

    public static func webReadRequest(url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("3", forHTTPHeaderField: "Zotero-API-Version")
        request.setValue(apiKey, forHTTPHeaderField: "Zotero-API-Key")
        return request
    }
}

public enum ZoteroSyncMode: String, Sendable {
    case full
    case incremental
}

public struct ZoteroSnapshot: Sendable {
    public let items: [LiteratureItem]
    public let collections: [ZoteroCollection]
    public let itemCollectionKeys: [String: [String]]
    public let deletedItemKeys: [String]
    public let deletedCollectionKeys: [String]
    public let serverID: String?
    public let libraryID: String
    public let libraryKind: ZoteroLibraryKind
    public let libraryName: String
    public let libraryMetadataVersion: Int?
    public let libraryVersion: Int?
    public let mode: ZoteroSyncMode

    public init(
        items: [LiteratureItem],
        collections: [ZoteroCollection] = [],
        itemCollectionKeys: [String: [String]] = [:],
        deletedItemKeys: [String] = [],
        deletedCollectionKeys: [String] = [],
        serverID: String?,
        libraryID: String = "user:0",
        libraryKind: ZoteroLibraryKind = .user,
        libraryName: String = "My Library",
        libraryMetadataVersion: Int? = nil,
        libraryVersion: Int?,
        mode: ZoteroSyncMode = .full
    ) {
        self.items = items
        self.collections = collections
        self.itemCollectionKeys = itemCollectionKeys
        self.deletedItemKeys = deletedItemKeys
        self.deletedCollectionKeys = deletedCollectionKeys
        self.serverID = serverID
        self.libraryID = libraryID
        self.libraryKind = libraryKind
        self.libraryName = libraryName
        self.libraryMetadataVersion = libraryMetadataVersion
        self.libraryVersion = libraryVersion
        self.mode = mode
    }
}

public struct ZoteroRefresh: Sendable {
    public let serverID: String
    public let snapshots: [ZoteroSnapshot]
    public let accessibleLibraryIDs: Set<String>
    public let connection: ZoteroConnectionInfo?

    public init(
        serverID: String, snapshots: [ZoteroSnapshot], accessibleLibraryIDs: Set<String>,
        connection: ZoteroConnectionInfo? = nil
    ) {
        self.serverID = serverID
        self.snapshots = snapshots
        self.accessibleLibraryIDs = accessibleLibraryIDs
        self.connection = connection
    }
}

private struct ZoteroLibraryDescriptor: Sendable {
    let libraryID: String
    let kind: ZoteroLibraryKind
    let name: String
    let metadataVersion: Int?
    let apiPrefix: String
}

public actor ZoteroLocalClient {
    private let session: URLSession
    private let baseURL: URL

    public init(baseURL: URL = URL(string: "http://localhost:23119/api/")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func fetchLibraries(checkpoints: [ZoteroLibraryCheckpoint] = []) async throws -> ZoteroRefresh {
        let root = try await request(relativePath: "")
        let connection = try connectionInfo(from: root.response)
        let serverID = connection.serverID

        var descriptors = [ZoteroLibraryDescriptor(
            libraryID: "user:0",
            kind: .user,
            name: "My Library",
            metadataVersion: nil,
            apiPrefix: "users/0"
        )]
        descriptors += try await fetchGroupDescriptors(expectedServerID: serverID)

        var snapshots: [ZoteroSnapshot] = []
        for descriptor in descriptors {
            let checkpoint = checkpoints.first {
                $0.serverID == serverID && $0.libraryID == descriptor.libraryID
            }
            snapshots.append(try await fetchLibrary(
                descriptor: descriptor,
                checkpoint: checkpoint,
                serverID: serverID
            ))
        }
        return ZoteroRefresh(
            serverID: serverID,
            snapshots: snapshots,
            accessibleLibraryIDs: Set(descriptors.map(\.libraryID)),
            connection: connection
        )
    }

    public func probe() async throws -> ZoteroConnectionInfo {
        let root = try await request(relativePath: "")
        return try connectionInfo(from: root.response)
    }

    public func refreshItem(_ item: LiteratureItem) async throws -> ZoteroItemRefresh {
        guard item.source == .zotero,
              let expectedServerID = item.zoteroServerID,
              let libraryID = item.zoteroLibraryID,
              let itemKey = item.zoteroKey,
              let apiPrefix = ZoteroAPIRouting.apiPrefix(libraryID: libraryID),
              let apiPath = ZoteroAPIRouting.itemPath(libraryID: libraryID, itemKey: itemKey) else {
            throw ZoteroError.invalidData
        }
        let root = try await request(relativePath: "")
        let connection = try connectionInfo(from: root.response)
        guard connection.serverID == expectedServerID else { throw ZoteroError.serverChanged }

        let descriptor = ZoteroLibraryDescriptor(
            libraryID: libraryID,
            kind: libraryID.hasPrefix("group:") ? .group : .user,
            name: item.zoteroLibraryName ?? (libraryID.hasPrefix("group:") ? "Zotero group" : "My Library"),
            metadataVersion: nil,
            apiPrefix: apiPrefix
        )
        guard let envelope = try await fetchItemEnvelope(
            key: itemKey, prefix: apiPrefix, expectedServerID: expectedServerID
        ) else { throw ZoteroError.itemNotFound(itemKey) }
        let childrenPayload = try await request(
            url: itemChildrenURL(prefix: apiPrefix, itemKey: itemKey),
            expectedServerID: expectedServerID
        )
        guard let children = try? JSONDecoder().decode([ZoteroEnvelope].self, from: childrenPayload.data) else {
            throw ZoteroError.invalidData
        }
        let transformed = await literature(
            from: [envelope] + children, descriptor: descriptor, serverID: expectedServerID
        )
        guard var refreshed = transformed.items.first(where: { $0.zoteroKey == itemKey }) else {
            throw ZoteroError.invalidData
        }
        refreshed.id = item.id
        return ZoteroItemRefresh(
            item: refreshed,
            collectionKeys: transformed.collectionKeys[itemKey] ?? [],
            connection: connection,
            apiPath: apiPath
        )
    }

    public func fetchLibrary(checkpoint: ZoteroCheckpoint? = nil) async throws -> ZoteroSnapshot {
        let root = try await request(relativePath: "")
        let serverID = root.response.value(forHTTPHeaderField: "Zotero-Server-ID")?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let descriptor = ZoteroLibraryDescriptor(
            libraryID: "user:0",
            kind: .user,
            name: "My Library",
            metadataVersion: nil,
            apiPrefix: "users/0"
        )
        if let checkpoint, let serverID, checkpoint.serverID == serverID {
            return try await fetchIncremental(descriptor: descriptor, since: checkpoint.libraryVersion, serverID: serverID)
        }
        return try await fetchFull(descriptor: descriptor, serverID: serverID)
    }

    private func fetchGroupDescriptors(expectedServerID: String) async throws -> [ZoteroLibraryDescriptor] {
        var components = URLComponents(url: baseURL.appendingPathComponent("users/0/groups"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "include", value: "data")
        ]
        let payload = try await request(url: components.url!, expectedServerID: expectedServerID)
        guard let groups = try? JSONDecoder().decode([ZoteroGroupEnvelope].self, from: payload.data) else {
            throw ZoteroError.invalidData
        }
        return groups.compactMap { group in
            guard let numericID = group.id ?? group.data?.id else { return nil }
            let name = group.data?.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Group \(numericID)"
            return ZoteroLibraryDescriptor(
                libraryID: "group:\(numericID)",
                kind: .group,
                name: name,
                metadataVersion: group.version ?? group.data?.version,
                apiPrefix: "groups/\(numericID)"
            )
        }
    }

    private func fetchLibrary(
        descriptor: ZoteroLibraryDescriptor,
        checkpoint: ZoteroLibraryCheckpoint?,
        serverID: String
    ) async throws -> ZoteroSnapshot {
        if let checkpoint {
            return try await fetchIncremental(descriptor: descriptor, since: checkpoint.libraryVersion, serverID: serverID)
        }
        return try await fetchFull(descriptor: descriptor, serverID: serverID)
    }

    private func fetchFull(descriptor: ZoteroLibraryDescriptor, serverID: String?) async throws -> ZoteroSnapshot {
        for _ in 0..<3 {
            let itemPayload = try await request(url: itemsURL(prefix: descriptor.apiPrefix, since: nil), expectedServerID: serverID)
            let collectionPayload = try await request(url: collectionsURL(prefix: descriptor.apiPrefix, since: nil), expectedServerID: serverID)
            guard let itemVersion = responseVersion(itemPayload.response),
                  let collectionVersion = responseVersion(collectionPayload.response) else {
                throw ZoteroError.invalidData
            }
            guard itemVersion == collectionVersion else { continue }
            guard let envelopes = try? JSONDecoder().decode([ZoteroEnvelope].self, from: itemPayload.data),
                  let collectionEnvelopes = try? JSONDecoder().decode([ZoteroCollectionEnvelope].self, from: collectionPayload.data) else {
                throw ZoteroError.invalidData
            }
            let transformed = await literature(from: envelopes, descriptor: descriptor, serverID: serverID)
            return ZoteroSnapshot(
                items: transformed.items,
                collections: collections(from: collectionEnvelopes, descriptor: descriptor, serverID: serverID),
                itemCollectionKeys: transformed.collectionKeys,
                serverID: serverID,
                libraryID: descriptor.libraryID,
                libraryKind: descriptor.kind,
                libraryName: descriptor.name,
                libraryMetadataVersion: descriptor.metadataVersion,
                libraryVersion: itemVersion,
                mode: .full
            )
        }
        throw ZoteroError.libraryChangedDuringSync
    }

    private func fetchIncremental(
        descriptor: ZoteroLibraryDescriptor,
        since version: Int,
        serverID: String
    ) async throws -> ZoteroSnapshot {
        for _ in 0..<3 {
            let changedItems = try await request(url: itemsURL(prefix: descriptor.apiPrefix, since: version), expectedServerID: serverID)
            let changedCollections = try await request(url: collectionsURL(prefix: descriptor.apiPrefix, since: version), expectedServerID: serverID)
            let deleted = try await request(url: deletedURL(prefix: descriptor.apiPrefix, since: version), expectedServerID: serverID)
            guard let itemVersion = responseVersion(changedItems.response),
                  let collectionVersion = responseVersion(changedCollections.response),
                  let deletedVersion = responseVersion(deleted.response) else {
                throw ZoteroError.invalidData
            }
            guard itemVersion == collectionVersion, itemVersion == deletedVersion else { continue }
            guard var envelopes = try? JSONDecoder().decode([ZoteroEnvelope].self, from: changedItems.data),
                  let collectionEnvelopes = try? JSONDecoder().decode([ZoteroCollectionEnvelope].self, from: changedCollections.data),
                  let deletions = try? JSONDecoder().decode(ZoteroDeletions.self, from: deleted.data) else {
                throw ZoteroError.invalidData
            }

            let includedKeys = Set(envelopes.map(\.key))
            let missingParents = Set(envelopes.compactMap { envelope -> String? in
                guard envelope.data.itemType == "attachment",
                      envelope.data.contentType?.lowercased() == "application/pdf",
                      let parent = envelope.data.parentItem,
                      !includedKeys.contains(parent) else { return nil }
                return parent
            })
            for parent in missingParents {
                if let envelope = try await fetchItemEnvelope(
                    key: parent,
                    prefix: descriptor.apiPrefix,
                    expectedServerID: serverID
                ) {
                    envelopes.append(envelope)
                }
            }

            let transformed = await literature(from: envelopes, descriptor: descriptor, serverID: serverID)
            return ZoteroSnapshot(
                items: transformed.items,
                collections: collections(from: collectionEnvelopes, descriptor: descriptor, serverID: serverID),
                itemCollectionKeys: transformed.collectionKeys,
                deletedItemKeys: deletions.items,
                deletedCollectionKeys: deletions.collections ?? [],
                serverID: serverID,
                libraryID: descriptor.libraryID,
                libraryKind: descriptor.kind,
                libraryName: descriptor.name,
                libraryMetadataVersion: descriptor.metadataVersion,
                libraryVersion: itemVersion,
                mode: .incremental
            )
        }
        throw ZoteroError.libraryChangedDuringSync
    }

    private func literature(
        from envelopes: [ZoteroEnvelope],
        descriptor: ZoteroLibraryDescriptor,
        serverID: String?
    ) async -> (items: [LiteratureItem], collectionKeys: [String: [String]]) {
        let attachments = envelopes.filter {
            $0.data.itemType == "attachment" && $0.data.contentType?.lowercased() == "application/pdf" && $0.data.parentItem != nil
        }
        var attachmentByParent: [String: ZoteroEnvelope] = [:]
        for attachment in attachments {
            attachmentByParent[attachment.data.parentItem!] = attachment
        }

        let attachmentPaths: [String: String] = await withTaskGroup(of: (String, String?).self) { group in
            for attachment in attachments {
                group.addTask {
                    (
                        attachment.key,
                        try? await self.attachmentFilePath(
                            key: attachment.key,
                            prefix: descriptor.apiPrefix,
                            expectedServerID: serverID
                        )
                    )
                }
            }
            var paths: [String: String] = [:]
            for await (key, path) in group {
                if let path { paths[key] = path }
            }
            return paths
        }

        var collectionKeys: [String: [String]] = [:]
        let items = envelopes.compactMap { envelope -> LiteratureItem? in
            guard !["attachment", "note", "annotation"].contains(envelope.data.itemType) else { return nil }
            let creators = envelope.data.creators?.map { creator in
                creator.name ?? [creator.firstName, creator.lastName].compactMap { $0 }.joined(separator: " ")
            }.filter { !$0.isEmpty }.joined(separator: "; ") ?? ""
            let attachment = attachmentByParent[envelope.key]
            collectionKeys[envelope.key] = envelope.data.collections ?? []
            return LiteratureItem(
                zoteroKey: envelope.key,
                zoteroAttachmentKey: attachment?.key,
                zoteroServerID: serverID,
                zoteroLibraryID: descriptor.libraryID,
                zoteroLibraryName: descriptor.name,
                zoteroVersion: envelope.version,
                title: envelope.data.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled Zotero item",
                authors: creators,
                year: envelope.data.date.flatMap(firstFourDigitYear),
                abstract: envelope.data.abstractNote ?? "",
                doi: envelope.data.doi?.nilIfEmpty,
                citationKey: citationKey(for: envelope.data),
                tags: (envelope.data.tags ?? []).map(\.tag).filter { !$0.isEmpty }.sorted(),
                itemType: envelope.data.itemType,
                source: .zotero,
                pdfPath: attachment.flatMap { attachmentPaths[$0.key] },
                externalURL: envelope.links?.alternate?.href,
                sourceAvailability: .available,
                modifiedAt: ISO8601DateFormatter().date(from: envelope.data.dateModified ?? "") ?? Date()
            )
        }
        return (items, collectionKeys)
    }

    private func collections(
        from envelopes: [ZoteroCollectionEnvelope],
        descriptor: ZoteroLibraryDescriptor,
        serverID: String?
    ) -> [ZoteroCollection] {
        guard let serverID else { return [] }
        return envelopes.map {
            ZoteroCollection(
                serverID: serverID,
                libraryID: descriptor.libraryID,
                key: $0.key,
                name: $0.data.name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled collection",
                parentKey: $0.data.parentCollection?.nilIfEmpty,
                version: $0.version
            )
        }
    }

    private func fetchItemEnvelope(key: String, prefix: String, expectedServerID: String) async throws -> ZoteroEnvelope? {
        do {
            var components = URLComponents(url: baseURL.appendingPathComponent("\(prefix)/items/\(key)"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "include", value: "data")
            ]
            let payload = try await request(url: components.url!, expectedServerID: expectedServerID)
            return try? JSONDecoder().decode(ZoteroEnvelope.self, from: payload.data)
        } catch ZoteroError.unexpectedResponse(let status) where status == 404 {
            return nil
        }
    }

    private func attachmentFilePath(key: String, prefix: String, expectedServerID: String?) async throws -> String? {
        let response = try await request(relativePath: "\(prefix)/items/\(key)/file/view/url", expectedServerID: expectedServerID)
        let value = String(data: response.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, let url = URL(string: value), url.isFileURL else { return nil }
        return url.path
    }

    private func itemsURL(prefix: String, since: Int?) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("\(prefix)/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "include", value: "data")
        ]
        if let since { components.queryItems?.append(URLQueryItem(name: "since", value: String(since))) }
        return components.url!
    }

    private func collectionsURL(prefix: String, since: Int?) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("\(prefix)/collections"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "include", value: "data")
        ]
        if let since { components.queryItems?.append(URLQueryItem(name: "since", value: String(since))) }
        return components.url!
    }

    private func deletedURL(prefix: String, since: Int) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("\(prefix)/deleted"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "since", value: String(since))]
        return components.url!
    }

    private func itemChildrenURL(prefix: String, itemKey: String) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("\(prefix)/items/\(itemKey)/children"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "include", value: "data")
        ]
        return components.url!
    }

    private func responseVersion(_ response: HTTPURLResponse) -> Int? {
        Int(response.value(forHTTPHeaderField: "Last-Modified-Version") ?? "")
    }

    private func request(relativePath: String, expectedServerID: String? = nil) async throws -> (data: Data, response: HTTPURLResponse) {
        try await request(url: baseURL.appendingPathComponent(relativePath), expectedServerID: expectedServerID)
    }

    private func request(url: URL, expectedServerID: String? = nil) async throws -> (data: Data, response: HTTPURLResponse) {
        let request = ZoteroAPIRouting.readRequest(url: url, expectedServerID: expectedServerID)
        let data: Data
        let rawResponse: URLResponse
        do {
            (data, rawResponse) = try await session.data(for: request)
        } catch {
            throw ZoteroError.unavailable
        }
        guard let response = rawResponse as? HTTPURLResponse else { throw ZoteroError.unavailable }
        switch response.statusCode {
        case 200..<300: return (data, response)
        case 403: throw ZoteroError.disabled
        case 412: throw ZoteroError.serverChanged
        default: throw ZoteroError.unexpectedResponse(response.statusCode)
        }
    }

    private func connectionInfo(from response: HTTPURLResponse) throws -> ZoteroConnectionInfo {
        guard let serverID = response.value(forHTTPHeaderField: "Zotero-Server-ID")?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            throw ZoteroError.invalidData
        }
        return ZoteroConnectionInfo(
            endpoint: baseURL.absoluteString,
            serverID: serverID,
            apiVersion: response.value(forHTTPHeaderField: "Zotero-API-Version")?
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            schemaVersion: response.value(forHTTPHeaderField: "Zotero-Schema-Version")?
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

    private func firstFourDigitYear(in value: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(\d{4})\b"#),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return Int(value[range])
    }

    private func citationKey(for item: ZoteroItemData) -> String? {
        if let direct = item.citationKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty { return direct }
        guard let extra = item.extra,
              let regex = try? NSRegularExpression(pattern: #"(?im)^citation key:\s*([^\s]+)\s*$"#),
              let match = regex.firstMatch(in: extra, range: NSRange(extra.startIndex..<extra.endIndex, in: extra)),
              let range = Range(match.range(at: 1), in: extra) else { return nil }
        return String(extra[range])
    }
}

/// Account-level read path. It never writes, downloads attachment files, or replaces the local
/// API: it verifies the user's Zotero ID/key, imports accessible library metadata and collections,
/// and can refresh one record by its exact stable key.
public actor ZoteroWebClient {
    private let session: URLSession
    private let baseURL: URL

    public init(baseURL: URL = URL(string: "https://api.zotero.org/")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func fetchLibraries(
        userID: String, apiKey: String, checkpoints: [ZoteroLibraryCheckpoint] = []
    ) async throws -> ZoteroRefresh {
        let identity = try await validate(userID: userID, apiKey: apiKey)
        let serverID = "zotero.org:user:\(identity.userID)"
        var descriptors = [ZoteroLibraryDescriptor(
            libraryID: "web-user:\(identity.userID)", kind: .user,
            name: "My Library — Zotero Web", metadataVersion: nil,
            apiPrefix: "users/\(identity.userID)"
        )]
        descriptors += try await fetchWebGroupDescriptors(userID: identity.userID, apiKey: apiKey)
        var snapshots: [ZoteroSnapshot] = []
        for descriptor in descriptors {
            let checkpoint = checkpoints.first {
                $0.serverID == serverID && $0.libraryID == descriptor.libraryID
            }
            snapshots.append(try await fetchWebLibrary(
                descriptor: descriptor, checkpoint: checkpoint,
                serverID: serverID, apiKey: apiKey
            ))
        }
        return ZoteroRefresh(
            serverID: serverID,
            snapshots: snapshots,
            accessibleLibraryIDs: Set(descriptors.map(\.libraryID)),
            connection: ZoteroConnectionInfo(
                endpoint: baseURL.absoluteString, serverID: serverID,
                apiVersion: "3", schemaVersion: nil
            )
        )
    }

    public func validate(userID: String, apiKey: String) async throws -> ZoteroWebIdentity {
        let expectedID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expectedID.isEmpty, expectedID.allSatisfy(\.isNumber), !key.isEmpty else {
            throw ZoteroError.invalidData
        }
        let payload = try await request(relativePath: "keys/current", apiKey: key)
        guard let info = try? JSONDecoder().decode(ZoteroKeyInformation.self, from: payload.data) else {
            throw ZoteroError.invalidData
        }
        let actualID = String(info.userID)
        guard actualID == expectedID else {
            throw ZoteroError.userIDMismatch(expected: expectedID, actual: actualID)
        }
        let identity = ZoteroWebIdentity(
            userID: actualID,
            username: info.username,
            canReadUserLibrary: info.access.user.library,
            canReadAllGroups: info.access.groups?.all?.library ?? false
        )
        guard identity.canReadUserLibrary else { throw ZoteroError.libraryAccessDenied }
        return identity
    }

    public func refreshItem(
        _ item: LiteratureItem, userID: String, apiKey: String
    ) async throws -> ZoteroItemRefresh {
        guard item.source == .zotero,
              let itemKey = item.zoteroKey,
              let libraryID = item.zoteroLibraryID,
              let serverID = item.zoteroServerID,
              let path = ZoteroAPIRouting.webItemPath(
                libraryID: libraryID, itemKey: itemKey,
                userID: userID.trimmingCharacters(in: .whitespacesAndNewlines)
              ) else { throw ZoteroError.invalidData }
        _ = try await validate(userID: userID, apiKey: apiKey)
        let parentPayload = try await request(relativePath: path, apiKey: apiKey)
        guard let parent = try? JSONDecoder().decode(ZoteroEnvelope.self, from: parentPayload.data) else {
            throw ZoteroError.invalidData
        }
        let childrenPayload = try await request(relativePath: "\(path)/children", apiKey: apiKey)
        guard let children = try? JSONDecoder().decode([ZoteroEnvelope].self, from: childrenPayload.data) else {
            throw ZoteroError.invalidData
        }
        let refreshed = transformedItem(parent: parent, children: children, preserving: item)
        return ZoteroItemRefresh(
            item: refreshed,
            collectionKeys: parent.data.collections ?? [],
            connection: ZoteroConnectionInfo(
                endpoint: baseURL.absoluteString,
                serverID: serverID,
                apiVersion: parentPayload.response.value(forHTTPHeaderField: "Zotero-API-Version"),
                schemaVersion: parentPayload.response.value(forHTTPHeaderField: "Zotero-Schema-Version")
            ),
            apiPath: path
        )
    }

    private func fetchWebGroupDescriptors(userID: String, apiKey: String) async throws -> [ZoteroLibraryDescriptor] {
        let result: ([ZoteroGroupEnvelope], Int?) = try await paged(
            relativePath: "users/\(userID)/groups", queryItems: [], apiKey: apiKey
        )
        return result.0.compactMap { group in
            guard let numericID = group.id ?? group.data?.id else { return nil }
            return ZoteroLibraryDescriptor(
                libraryID: "group:\(numericID)", kind: .group,
                name: group.data?.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Group \(numericID)",
                metadataVersion: group.version ?? group.data?.version,
                apiPrefix: "groups/\(numericID)"
            )
        }
    }

    private func fetchWebLibrary(
        descriptor: ZoteroLibraryDescriptor, checkpoint: ZoteroLibraryCheckpoint?,
        serverID: String, apiKey: String
    ) async throws -> ZoteroSnapshot {
        for _ in 0..<3 {
            let since = checkpoint.map { URLQueryItem(name: "since", value: String($0.libraryVersion)) }
            let itemResult: ([ZoteroEnvelope], Int?) = try await paged(
                relativePath: "\(descriptor.apiPrefix)/items",
                queryItems: since.map { [$0] } ?? [], apiKey: apiKey
            )
            let collectionResult: ([ZoteroCollectionEnvelope], Int?) = try await paged(
                relativePath: "\(descriptor.apiPrefix)/collections",
                queryItems: since.map { [$0] } ?? [], apiKey: apiKey
            )
            guard let itemVersion = itemResult.1,
                  let collectionVersion = collectionResult.1,
                  itemVersion == collectionVersion else { continue }

            var envelopes = itemResult.0
            var deletedItems: [String] = []
            var deletedCollections: [String] = []
            if let checkpoint {
                var deletedComponents = URLComponents(
                    url: baseURL.appendingPathComponent("\(descriptor.apiPrefix)/deleted"),
                    resolvingAgainstBaseURL: false
                )!
                deletedComponents.queryItems = [URLQueryItem(name: "since", value: String(checkpoint.libraryVersion))]
                let deletedPayload = try await request(url: deletedComponents.url!, apiKey: apiKey)
                guard responseVersion(deletedPayload.response) == itemVersion,
                      let deletions = try? JSONDecoder().decode(ZoteroDeletions.self, from: deletedPayload.data) else {
                    continue
                }
                deletedItems = deletions.items
                deletedCollections = deletions.collections ?? []

                let includedKeys = Set(envelopes.map(\.key))
                let missingParents = Set(envelopes.compactMap { envelope -> String? in
                    guard envelope.data.itemType == "attachment",
                          envelope.data.contentType?.lowercased() == "application/pdf",
                          let parent = envelope.data.parentItem,
                          !includedKeys.contains(parent) else { return nil }
                    return parent
                })
                for parent in missingParents {
                    let payload = try await request(
                        relativePath: "\(descriptor.apiPrefix)/items/\(parent)", apiKey: apiKey
                    )
                    if let envelope = try? JSONDecoder().decode(ZoteroEnvelope.self, from: payload.data) {
                        envelopes.append(envelope)
                    }
                }
            }

            let transformed = webLiterature(
                from: envelopes, descriptor: descriptor, serverID: serverID
            )
            return ZoteroSnapshot(
                items: transformed.items,
                collections: webCollections(
                    from: collectionResult.0, descriptor: descriptor, serverID: serverID
                ),
                itemCollectionKeys: transformed.collectionKeys,
                deletedItemKeys: deletedItems,
                deletedCollectionKeys: deletedCollections,
                serverID: serverID,
                libraryID: descriptor.libraryID,
                libraryKind: descriptor.kind,
                libraryName: descriptor.name,
                libraryMetadataVersion: descriptor.metadataVersion,
                libraryVersion: itemVersion,
                mode: checkpoint == nil ? .full : .incremental
            )
        }
        throw ZoteroError.libraryChangedDuringSync
    }

    private func webLiterature(
        from envelopes: [ZoteroEnvelope], descriptor: ZoteroLibraryDescriptor, serverID: String
    ) -> (items: [LiteratureItem], collectionKeys: [String: [String]]) {
        let attachments = envelopes.filter {
            $0.data.itemType == "attachment"
                && $0.data.contentType?.lowercased() == "application/pdf"
                && $0.data.parentItem != nil
        }
        var attachmentByParent: [String: ZoteroEnvelope] = [:]
        for attachment in attachments { attachmentByParent[attachment.data.parentItem!] = attachment }
        var collectionKeys: [String: [String]] = [:]
        let items = envelopes.compactMap { envelope -> LiteratureItem? in
            guard !["attachment", "note", "annotation"].contains(envelope.data.itemType) else { return nil }
            let creators = envelope.data.creators?.map { creator in
                creator.name ?? [creator.firstName, creator.lastName].compactMap { $0 }.joined(separator: " ")
            }.filter { !$0.isEmpty }.joined(separator: "; ") ?? ""
            collectionKeys[envelope.key] = envelope.data.collections ?? []
            return LiteratureItem(
                zoteroKey: envelope.key,
                zoteroAttachmentKey: attachmentByParent[envelope.key]?.key,
                zoteroServerID: serverID,
                zoteroLibraryID: descriptor.libraryID,
                zoteroLibraryName: descriptor.name,
                zoteroVersion: envelope.version,
                title: envelope.data.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled Zotero item",
                authors: creators,
                year: envelope.data.date.flatMap(firstFourDigitYear),
                abstract: envelope.data.abstractNote ?? "",
                doi: envelope.data.doi?.nilIfEmpty,
                citationKey: citationKey(for: envelope.data),
                tags: (envelope.data.tags ?? []).map(\.tag).filter { !$0.isEmpty }.sorted(),
                itemType: envelope.data.itemType,
                source: .zotero,
                externalURL: envelope.links?.alternate?.href,
                sourceAvailability: .available,
                modifiedAt: ISO8601DateFormatter().date(from: envelope.data.dateModified ?? "") ?? Date()
            )
        }
        return (items, collectionKeys)
    }

    private func webCollections(
        from envelopes: [ZoteroCollectionEnvelope], descriptor: ZoteroLibraryDescriptor, serverID: String
    ) -> [ZoteroCollection] {
        envelopes.map {
            ZoteroCollection(
                serverID: serverID, libraryID: descriptor.libraryID,
                key: $0.key,
                name: $0.data.name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled collection",
                parentKey: $0.data.parentCollection?.nilIfEmpty,
                version: $0.version
            )
        }
    }

    private func paged<T: Decodable>(
        relativePath: String, queryItems: [URLQueryItem], apiKey: String
    ) async throws -> ([T], Int?) {
        var results: [T] = []
        var start = 0
        var version: Int?
        while true {
            var components = URLComponents(
                url: baseURL.appendingPathComponent(relativePath), resolvingAgainstBaseURL: false
            )!
            components.queryItems = queryItems + [
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "include", value: "data"),
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "start", value: String(start))
            ]
            let payload = try await request(url: components.url!, apiKey: apiKey)
            let page: [T]
            do {
                page = try JSONDecoder().decode([T].self, from: payload.data)
            } catch {
                throw ZoteroError.responseFormat(
                    endpoint: relativePath.split(separator: "/").last.map(String.init) ?? "API",
                    field: decodingLocation(error)
                )
            }
            let pageVersion = responseVersion(payload.response)
            if let version, let pageVersion, version != pageVersion {
                throw ZoteroError.libraryChangedDuringSync
            }
            version = version ?? pageVersion
            results += page
            let total = Int(payload.response.value(forHTTPHeaderField: "Total-Results") ?? "")
            start += page.count
            if page.isEmpty || page.count < 100 || (total != nil && start >= total!) { break }
        }
        return (results, version)
    }

    private func responseVersion(_ response: HTTPURLResponse) -> Int? {
        Int(response.value(forHTTPHeaderField: "Last-Modified-Version") ?? "")
    }

    private func decodingLocation(_ error: Error) -> String {
        let context: DecodingError.Context?
        switch error {
        case DecodingError.typeMismatch(_, let value): context = value
        case DecodingError.valueNotFound(_, let value): context = value
        case DecodingError.keyNotFound(_, let value): context = value
        case DecodingError.dataCorrupted(let value): context = value
        default: context = nil
        }
        guard let context else { return "the response body" }
        let path = context.codingPath.map { key in
            key.intValue.map { "[\($0)]" } ?? key.stringValue
        }.joined(separator: ".")
        let safePath = path.isEmpty ? "the response body" : path
        return "\(safePath) (\(context.debugDescription))"
    }

    private func transformedItem(
        parent: ZoteroEnvelope, children: [ZoteroEnvelope], preserving original: LiteratureItem
    ) -> LiteratureItem {
        let creators = parent.data.creators?.map { creator in
            creator.name ?? [creator.firstName, creator.lastName].compactMap { $0 }.joined(separator: " ")
        }.filter { !$0.isEmpty }.joined(separator: "; ") ?? ""
        let pdfAttachment = children.first {
            $0.data.itemType == "attachment" && $0.data.contentType?.lowercased() == "application/pdf"
        }
        return LiteratureItem(
            id: original.id,
            zoteroKey: parent.key,
            zoteroAttachmentKey: pdfAttachment?.key ?? original.zoteroAttachmentKey,
            zoteroServerID: original.zoteroServerID,
            zoteroLibraryID: original.zoteroLibraryID,
            zoteroLibraryName: original.zoteroLibraryName,
            zoteroVersion: parent.version,
            title: parent.data.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled Zotero item",
            authors: creators,
            year: parent.data.date.flatMap(firstFourDigitYear),
            abstract: parent.data.abstractNote ?? "",
            doi: parent.data.doi?.nilIfEmpty,
            citationKey: citationKey(for: parent.data),
            tags: (parent.data.tags ?? []).map(\.tag).filter { !$0.isEmpty }.sorted(),
            itemType: parent.data.itemType,
            source: .zotero,
            pdfPath: original.pdfPath,
            pdfByteCount: original.pdfByteCount,
            pdfContentHash: original.pdfContentHash,
            pdfLastVerifiedAt: original.pdfLastVerifiedAt,
            externalURL: parent.links?.alternate?.href ?? original.externalURL,
            sourceAvailability: .available,
            modifiedAt: ISO8601DateFormatter().date(from: parent.data.dateModified ?? "") ?? Date()
        )
    }

    private func request(relativePath: String, apiKey: String) async throws -> (data: Data, response: HTTPURLResponse) {
        let url = baseURL.appendingPathComponent(relativePath)
        return try await request(url: url, apiKey: apiKey)
    }

    private func request(url: URL, apiKey: String) async throws -> (data: Data, response: HTTPURLResponse) {
        let request = ZoteroAPIRouting.webReadRequest(url: url, apiKey: apiKey)
        let data: Data
        let rawResponse: URLResponse
        do {
            (data, rawResponse) = try await session.data(for: request)
        } catch {
            throw ZoteroError.unavailable
        }
        guard let response = rawResponse as? HTTPURLResponse else { throw ZoteroError.unavailable }
        switch response.statusCode {
        case 200..<300: return (data, response)
        case 401, 403: throw ZoteroError.unauthorized
        case 404: throw ZoteroError.itemNotFound(url.lastPathComponent)
        default: throw ZoteroError.unexpectedResponse(response.statusCode)
        }
    }

    private func firstFourDigitYear(in value: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(\d{4})\b"#),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return Int(value[range])
    }

    private func citationKey(for item: ZoteroItemData) -> String? {
        if let direct = item.citationKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty { return direct }
        guard let extra = item.extra,
              let regex = try? NSRegularExpression(pattern: #"(?im)^citation key:\s*([^\s]+)\s*$"#),
              let match = regex.firstMatch(in: extra, range: NSRange(extra.startIndex..<extra.endIndex, in: extra)),
              let range = Range(match.range(at: 1), in: extra) else { return nil }
        return String(extra[range])
    }
}

private struct ZoteroKeyInformation: Decodable {
    let userID: Int
    let username: String
    let access: Access

    struct Access: Decodable {
        let user: UserAccess
        let groups: GroupAccess?
    }

    struct UserAccess: Decodable { let library: Bool }
    struct GroupAccess: Decodable {
        let all: GroupLibraryAccess?

        private enum CodingKeys: String, CodingKey { case all }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            all = try? container.decode(GroupLibraryAccess.self, forKey: .all)
        }
    }
    struct GroupLibraryAccess: Decodable { let library: Bool }
}

private struct ZoteroEnvelope: Decodable, Sendable {
    let key: String
    let version: Int?
    let data: ZoteroItemData
    let links: ZoteroLinks?
}

private struct ZoteroCollectionEnvelope: Decodable, Sendable {
    let key: String
    let version: Int?
    let data: ZoteroCollectionData
}

private struct ZoteroCollectionData: Decodable, Sendable {
    let name: String
    let parentCollection: String?

    private enum CodingKeys: String, CodingKey { case name, parentCollection }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        // Zotero represents a top-level collection as JSON `false`, while a child collection
        // receives its parent's item-key string. Treat false/null/missing as no parent.
        parentCollection = try? container.decode(String.self, forKey: .parentCollection)
    }
}

private struct ZoteroGroupEnvelope: Decodable, Sendable {
    let id: Int?
    let version: Int?
    let data: ZoteroGroupData?
}

private struct ZoteroGroupData: Decodable, Sendable {
    let id: Int?
    let version: Int?
    let name: String?
}

private struct ZoteroDeletions: Decodable, Sendable {
    let collections: [String]?
    let items: [String]
}

private struct ZoteroItemData: Decodable, Sendable {
    let itemType: String
    let title: String?
    let creators: [ZoteroCreator]?
    let date: String?
    let doi: String?
    let abstractNote: String?
    let contentType: String?
    let parentItem: String?
    let dateModified: String?
    let citationKey: String?
    let extra: String?
    let tags: [ZoteroTag]?
    let collections: [String]?

    enum CodingKeys: String, CodingKey {
        case itemType, title, creators, date, abstractNote, contentType, parentItem, dateModified, citationKey, extra, tags, collections
        case doi = "DOI"
    }
}

private struct ZoteroTag: Decodable, Sendable {
    let tag: String
}

private struct ZoteroCreator: Decodable, Sendable {
    let firstName: String?
    let lastName: String?
    let name: String?
}

private struct ZoteroLinks: Decodable, Sendable {
    let alternate: ZoteroLink?
}

private struct ZoteroLink: Decodable, Sendable {
    let href: String
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
