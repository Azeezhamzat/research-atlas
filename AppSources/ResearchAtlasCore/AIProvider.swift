import Foundation

public enum AIProviderError: Error, LocalizedError, Equatable {
    case disabled
    case invalidEndpoint
    case missingCredential
    case transport(String)
    case httpStatus(Int, String)
    case refused(String)
    case incomplete(String)
    case invalidResponse(String)
    case unsupportedCitation(String)
    case insufficientGrounding(String)

    public var errorDescription: String? {
        switch self {
        case .disabled: "AI transmission is disabled in Research Atlas settings."
        case .invalidEndpoint: "The configured AI endpoint is not an approved provider URL. Hosted providers require HTTPS; local providers are restricted to their fixed loopback endpoints."
        case .missingCredential: "No API credential is stored for the configured provider."
        case .transport(let message): "The AI request failed before a response was received: \(message)"
        case .httpStatus(let status, let message): "The AI provider returned HTTP \(status): \(message)"
        case .refused(let message): "The AI provider refused this request: \(message)"
        case .incomplete(let message): "The AI provider returned an incomplete response: \(message)"
        case .invalidResponse(let message): "The AI provider returned an invalid response: \(message)"
        case .unsupportedCitation(let label): "The AI response cited an unavailable source label: \(label)."
        case .insufficientGrounding(let message): "The AI response was not sufficiently grounded: \(message)"
        }
    }
}

public struct AIProviderRequest: Sendable {
    public var model: String
    public var instructions: String
    public var input: String
    public var responseSchemaName: String
    public var responseSchema: [String: JSONValue]
    public var maximumOutputTokens: Int

    public init(
        model: String, instructions: String, input: String, responseSchemaName: String,
        responseSchema: [String: JSONValue], maximumOutputTokens: Int
    ) {
        self.model = model
        self.instructions = instructions
        self.input = input
        self.responseSchemaName = responseSchemaName
        self.responseSchema = responseSchema
        self.maximumOutputTokens = maximumOutputTokens
    }
}

public struct AIProviderResponse: Equatable, Sendable {
    public var providerResponseID: String?
    public var outputText: String
    public var inputTokens: Int?
    public var outputTokens: Int?

    public init(providerResponseID: String? = nil, outputText: String, inputTokens: Int? = nil, outputTokens: Int? = nil) {
        self.providerResponseID = providerResponseID
        self.outputText = outputText
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public protocol AIProvider: Sendable {
    var identifier: String { get }
    func generate(_ request: AIProviderRequest) async throws -> AIProviderResponse
}

public indirect enum JSONValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    fileprivate var foundationValue: Any {
        switch self {
        case .string(let value): value
        case .number(let value): value
        case .bool(let value): value
        case .object(let value): value.mapValues(\.foundationValue)
        case .array(let value): value.map(\.foundationValue)
        case .null: NSNull()
        }
    }
}

public enum AIProviderHTTPCodec {
    public static func makeRequest(
        provider: AIProviderKind,
        endpoint: URL,
        apiKey: String,
        request: AIProviderRequest,
        reasoningEffort: AIReasoningEffort = .medium,
        localRuntimeIdleMinutes: Int = 10
    ) throws -> URLRequest {
        guard provider != .disabled else { throw AIProviderError.disabled }
        guard endpointIsAllowed(provider: provider, endpoint: endpoint) else { throw AIProviderError.invalidEndpoint }
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider.requiresCredential, trimmedKey.isEmpty { throw AIProviderError.missingCredential }
        guard !request.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProviderError.invalidResponse("No model identifier was configured.")
        }
        if provider != .compatibleEndpoint {
            guard normalized(endpoint.absoluteString) == normalized(provider.defaultEndpoint) else {
                throw AIProviderError.invalidEndpoint
            }
        }

        let targetURL: URL
        let body: [String: Any]
        switch provider {
        case .disabled:
            throw AIProviderError.disabled
        case .openAI, .compatibleEndpoint:
            targetURL = endpoint
            body = [
                "model": request.model,
                "instructions": request.instructions,
                "input": request.input,
                "max_output_tokens": request.maximumOutputTokens,
                "store": false,
                "text": [
                    "format": [
                        "type": "json_schema",
                        "name": request.responseSchemaName,
                        "strict": true,
                        "schema": request.responseSchema.mapValues(\.foundationValue)
                    ]
                ]
            ]
        case .anthropic:
            targetURL = endpoint
            body = [
                "model": request.model,
                "max_tokens": request.maximumOutputTokens,
                "system": request.instructions,
                "messages": [["role": "user", "content": request.input]],
                "output_config": [
                    "format": [
                        "type": "json_schema",
                        "schema": request.responseSchema.mapValues(\.foundationValue)
                    ]
                ]
            ]
        case .googleGemini:
            let model = request.model.hasPrefix("models/") ? String(request.model.dropFirst(7)) : request.model
            guard !model.isEmpty, !model.contains("/"), !model.contains("?") else {
                throw AIProviderError.invalidResponse("The Gemini model identifier is not valid.")
            }
            targetURL = endpoint
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent("\(model):generateContent", isDirectory: false)
            body = [
                "system_instruction": ["parts": [["text": request.instructions]]],
                "contents": [["role": "user", "parts": [["text": request.input]]]],
                "generationConfig": [
                    "maxOutputTokens": request.maximumOutputTokens,
                    "responseMimeType": "application/json",
                    "responseJsonSchema": request.responseSchema.mapValues(\.foundationValue)
                ]
            ]
        case .ollamaLocal:
            targetURL = endpoint
            body = [
                "model": request.model,
                "messages": [
                    ["role": "system", "content": request.instructions],
                    ["role": "user", "content": request.input]
                ],
                "stream": false,
                "think": reasoningEffort.rawValue,
                "format": request.responseSchema.mapValues(\.foundationValue),
                "keep_alive": "\(max(1, localRuntimeIdleMinutes))m",
                "options": [
                    "temperature": 0,
                    "num_predict": request.maximumOutputTokens
                ]
            ]
        case .lmStudioLocal:
            targetURL = endpoint
            body = [
                "model": request.model,
                "messages": [
                    ["role": "system", "content": request.instructions],
                    ["role": "user", "content": request.input]
                ],
                "stream": false,
                "temperature": 0,
                "max_tokens": request.maximumOutputTokens,
                "response_format": [
                    "type": "json_schema",
                    "json_schema": [
                        "name": request.responseSchemaName,
                        "strict": true,
                        "schema": request.responseSchema.mapValues(\.foundationValue)
                    ]
                ]
            ]
        }

        let data: Data
        do { data = try JSONSerialization.data(withJSONObject: body) }
        catch { throw AIProviderError.invalidResponse("Could not encode the structured request.") }

        var urlRequest = URLRequest(url: targetURL)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = data
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch provider {
        case .disabled:
            break
        case .openAI, .compatibleEndpoint:
            urlRequest.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            urlRequest.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
            urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .googleGemini:
            urlRequest.setValue(trimmedKey, forHTTPHeaderField: "x-goog-api-key")
        case .ollamaLocal, .lmStudioLocal:
            break
        }
        return urlRequest
    }

    public static func decodeResponse(provider: AIProviderKind, data: Data) throws -> AIProviderResponse {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.invalidResponse("The response body was not a JSON object.")
        }
        if let error = root["error"] as? [String: Any], let message = error["message"] as? String {
            throw AIProviderError.invalidResponse(message)
        }
        switch provider {
        case .disabled:
            throw AIProviderError.disabled
        case .openAI, .compatibleEndpoint:
            return try decodeOpenAIResponse(root)
        case .anthropic:
            return try decodeAnthropicResponse(root)
        case .googleGemini:
            return try decodeGeminiResponse(root)
        case .ollamaLocal:
            return try decodeOllamaResponse(root)
        case .lmStudioLocal:
            return try decodeLMStudioResponse(root)
        }
    }

    public static func providerErrorMessage(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = root["error"] as? [String: Any] { return error["message"] as? String }
        return root["error"] as? String
    }

    private static func decodeOpenAIResponse(_ root: [String: Any]) throws -> AIProviderResponse {
        if let status = root["status"] as? String, status == "incomplete" {
            let detail = (root["incomplete_details"] as? [String: Any])?["reason"] as? String ?? "Unknown reason"
            throw AIProviderError.incomplete(detail)
        }
        var textParts: [String] = []
        var refusal: String?
        for item in root["output"] as? [[String: Any]] ?? [] {
            guard item["type"] as? String == "message" else { continue }
            for content in item["content"] as? [[String: Any]] ?? [] {
                switch content["type"] as? String {
                case "output_text": if let text = content["text"] as? String { textParts.append(text) }
                case "refusal": refusal = content["refusal"] as? String ?? "No refusal detail was returned."
                default: continue
                }
            }
        }
        if let refusal { throw AIProviderError.refused(refusal) }
        guard !textParts.isEmpty else { throw AIProviderError.invalidResponse("No output text was returned.") }
        let usage = root["usage"] as? [String: Any]
        return AIProviderResponse(
            providerResponseID: root["id"] as? String,
            outputText: textParts.joined(separator: "\n"),
            inputTokens: usage?["input_tokens"] as? Int,
            outputTokens: usage?["output_tokens"] as? Int
        )
    }

    private static func decodeAnthropicResponse(_ root: [String: Any]) throws -> AIProviderResponse {
        if let refusal = root["stop_details"] as? [String: Any], refusal["type"] as? String == "refusal" {
            throw AIProviderError.refused(refusal["explanation"] as? String ?? "Claude refused this request.")
        }
        if root["stop_reason"] as? String == "max_tokens" {
            throw AIProviderError.incomplete("Claude reached the configured output-token limit.")
        }
        let textParts = (root["content"] as? [[String: Any]] ?? []).compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }
        guard !textParts.isEmpty else { throw AIProviderError.invalidResponse("Claude returned no text content.") }
        let usage = root["usage"] as? [String: Any]
        return AIProviderResponse(
            providerResponseID: root["id"] as? String,
            outputText: textParts.joined(separator: "\n"),
            inputTokens: usage?["input_tokens"] as? Int,
            outputTokens: usage?["output_tokens"] as? Int
        )
    }

    private static func decodeGeminiResponse(_ root: [String: Any]) throws -> AIProviderResponse {
        if let feedback = root["promptFeedback"] as? [String: Any], let reason = feedback["blockReason"] as? String {
            throw AIProviderError.refused("Gemini blocked the prompt: \(reason).")
        }
        guard let candidate = (root["candidates"] as? [[String: Any]])?.first else {
            throw AIProviderError.invalidResponse("Gemini returned no response candidate.")
        }
        let finishReason = candidate["finishReason"] as? String
        if finishReason == "MAX_TOKENS" {
            throw AIProviderError.incomplete("Gemini reached the configured output-token limit.")
        }
        if let finishReason, ["SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT"].contains(finishReason) {
            throw AIProviderError.refused("Gemini stopped the response: \(finishReason).")
        }
        let content = candidate["content"] as? [String: Any]
        let textParts = (content?["parts"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }
        guard !textParts.isEmpty else { throw AIProviderError.invalidResponse("Gemini returned no text content.") }
        let usage = root["usageMetadata"] as? [String: Any]
        return AIProviderResponse(
            providerResponseID: root["responseId"] as? String,
            outputText: textParts.joined(separator: "\n"),
            inputTokens: usage?["promptTokenCount"] as? Int,
            outputTokens: usage?["candidatesTokenCount"] as? Int
        )
    }

    private static func decodeOllamaResponse(_ root: [String: Any]) throws -> AIProviderResponse {
        if let error = root["error"] as? String { throw AIProviderError.invalidResponse(error) }
        guard root["done"] as? Bool == true else {
            throw AIProviderError.incomplete("Ollama did not mark the non-streaming response complete.")
        }
        if root["done_reason"] as? String == "length" {
            throw AIProviderError.incomplete("Ollama reached the configured output-token limit.")
        }
        let message = root["message"] as? [String: Any]
        guard let text = message?["content"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProviderError.invalidResponse("Ollama returned no message content.")
        }
        return AIProviderResponse(
            providerResponseID: root["created_at"] as? String,
            outputText: text,
            inputTokens: root["prompt_eval_count"] as? Int,
            outputTokens: root["eval_count"] as? Int
        )
    }

    private static func decodeLMStudioResponse(_ root: [String: Any]) throws -> AIProviderResponse {
        guard let choice = (root["choices"] as? [[String: Any]])?.first else {
            throw AIProviderError.invalidResponse("LM Studio returned no response choice.")
        }
        if choice["finish_reason"] as? String == "length" {
            throw AIProviderError.incomplete("LM Studio reached the configured output-token limit.")
        }
        guard let message = choice["message"] as? [String: Any] else {
            throw AIProviderError.invalidResponse("LM Studio returned no assistant message.")
        }
        if let refusal = message["refusal"] as? String,
           !refusal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AIProviderError.refused(refusal)
        }

        let content = (message["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text: String
        if !content.isEmpty {
            text = content
        } else {
            // Some reasoning models served by LM Studio place their schema-constrained final
            // answer in `reasoning_content`. Accept it only when the complete value is valid
            // JSON, so free-form hidden reasoning is never surfaced as an application result.
            let reasoning = (message["reasoning_content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let data = reasoning.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: data)) != nil else {
                throw AIProviderError.invalidResponse("LM Studio returned no schema-valid message content.")
            }
            text = reasoning
        }
        let usage = root["usage"] as? [String: Any]
        return AIProviderResponse(
            providerResponseID: root["id"] as? String,
            outputText: text,
            inputTokens: usage?["prompt_tokens"] as? Int,
            outputTokens: usage?["completion_tokens"] as? Int
        )
    }

    private static func endpointIsAllowed(provider: AIProviderKind, endpoint: URL) -> Bool {
        if provider.isLocal {
            return normalized(endpoint.absoluteString) == normalized(provider.defaultEndpoint)
        }
        return endpoint.scheme?.lowercased() == "https"
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

public actor ConfiguredHTTPAIProvider: AIProvider {
    public let identifier: String
    private let provider: AIProviderKind
    private let endpoint: URL
    private let apiKey: String
    private let reasoningEffort: AIReasoningEffort
    private let localRuntimeIdleMinutes: Int
    private let session: URLSession

    public init(
        provider: AIProviderKind,
        endpoint: URL,
        apiKey: String,
        reasoningEffort: AIReasoningEffort = .medium,
        localRuntimeIdleMinutes: Int = 10,
        session: URLSession = .shared
    ) throws {
        guard provider != .disabled else { throw AIProviderError.disabled }
        let scheme = endpoint.scheme?.lowercased()
        guard (provider.isLocal && scheme == "http") || (!provider.isLocal && scheme == "https") else {
            throw AIProviderError.invalidEndpoint
        }
        if provider.requiresCredential,
           apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AIProviderError.missingCredential
        }
        self.provider = provider
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.reasoningEffort = reasoningEffort
        self.localRuntimeIdleMinutes = max(1, localRuntimeIdleMinutes)
        self.identifier = provider.rawValue
        self.session = session
    }

    public func generate(_ request: AIProviderRequest) async throws -> AIProviderResponse {
        let urlRequest = try AIProviderHTTPCodec.makeRequest(
            provider: provider, endpoint: endpoint, apiKey: apiKey, request: request,
            reasoningEffort: reasoningEffort, localRuntimeIdleMinutes: localRuntimeIdleMinutes
        )

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(
                for: urlRequest,
                delegate: AIProviderRedirectBlocker.shared
            )
        }
        catch { throw AIProviderError.transport(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw AIProviderError.invalidResponse("No HTTP response metadata was returned.") }
        guard (200..<300).contains(http.statusCode) else {
            let message = AIProviderHTTPCodec.providerErrorMessage(from: responseData) ?? "No provider error detail was returned."
            throw AIProviderError.httpStatus(http.statusCode, message)
        }
        return try AIProviderHTTPCodec.decodeResponse(provider: provider, data: responseData)
    }
}

public typealias OpenAIResponsesProvider = ConfiguredHTTPAIProvider

private final class AIProviderRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = AIProviderRedirectBlocker()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // A destination is part of the researcher's approved preview. Following even a
        // same-host redirect would make the actual request target differ from that record.
        completionHandler(nil)
    }
}

public struct GroundedPromptPackage: Sendable {
    public var request: AIProviderRequest
    public var citations: [AIAnalysisCitation]
    public var noteCitations: [AIAnalysisNoteCitation]
    public var characterCount: Int

    public init(
        request: AIProviderRequest,
        citations: [AIAnalysisCitation],
        noteCitations: [AIAnalysisNoteCitation] = [],
        characterCount: Int
    ) {
        self.request = request
        self.citations = citations
        self.noteCitations = noteCitations
        self.characterCount = characterCount
    }
}

public enum GroundedAnswerBuilder {
    public static let promptVersion = "grounded-literature-answer-v1"

    public static func package(
        analysisID: UUID,
        query: String,
        passages: [RetrievedPassage],
        noteSnippets: [RetrievedNoteSnippet] = [],
        literature: [LiteratureItem],
        model: String,
        maximumOutputTokens: Int
    ) throws -> GroundedPromptPackage {
        let usable = passages.filter { $0.citationStatus == .current }
        let usableNotes = noteSnippets.filter { $0.citationStatus == .current }
        guard !usable.isEmpty || !usableNotes.isEmpty else {
            throw AIProviderError.insufficientGrounding("No current paper passages or note excerpts are available. Refresh or replace stale retrieval evidence before transmission.")
        }
        let literatureByID = Dictionary(uniqueKeysWithValues: literature.map { ($0.id, $0) })
        var sourceBlocks: [String] = []
        var citations: [AIAnalysisCitation] = []
        var noteCitations: [AIAnalysisNoteCitation] = []
        for (offset, passage) in usable.enumerated() {
            let label = "S\(offset + 1)"
            let title = literatureByID[passage.literatureID]?.title ?? "Unavailable title"
            sourceBlocks.append("[\(label)] \(title), page \(passage.page)\n\(passage.passageText)")
            citations.append(AIAnalysisCitation(
                analysisID: analysisID, label: label, sourcePassageID: passage.sourcePassageID,
                literatureID: passage.literatureID, page: passage.page, quotedPassage: passage.passageText,
                sourceDocumentHash: passage.sourceDocumentHash, citationStatus: passage.citationStatus
            ))
        }
        for (offset, note) in usableNotes.enumerated() {
            let label = "N\(offset + 1)"
            sourceBlocks.append("[\(label)] Researcher note: \(note.noteTitle)\n\(note.snippetText)")
            noteCitations.append(AIAnalysisNoteCitation(
                analysisID: analysisID, label: label, noteID: note.noteID,
                notePath: note.notePath, noteTitle: note.noteTitle,
                quotedSnippet: note.snippetText, sourceModifiedAt: note.sourceModifiedAt,
                citationStatus: note.citationStatus
            ))
        }
        let input = """
            RESEARCH QUESTION
            \(query)

            RETRIEVED SOURCE PASSAGES
            \(sourceBlocks.joined(separator: "\n\n"))
            """
        let instructions = """
            Answer only from the supplied Research Atlas sources. [S#] labels are paper passages; [N#] labels are the researcher's Obsidian note excerpts and must never be represented as published evidence. Never introduce a paper, author, result, page, quotation, or methodological fact that is not present. Treat the supplied labels as the complete set of allowed citations. Put every substantive statement into the claims array with one or more allowed citation labels. Mark interpretation true when the statement is synthesis or inference rather than a direct report. If the sources do not support an answer, set insufficient_evidence true, explain what is missing, keep claims empty, and do not guess. Preserve qualifications and distinguish quotations, paraphrases, and researcher notes.
            """
        let schema: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object([
                "answer": .object(["type": .string("string")]),
                "insufficient_evidence": .object(["type": .string("boolean")]),
                "insufficiency_reason": .object(["type": .string("string")]),
                "claims": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "text": .object(["type": .string("string")]),
                            "citations": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                            "interpretation": .object(["type": .string("boolean")])
                        ]),
                        "required": .array([.string("text"), .string("citations"), .string("interpretation")]),
                        "additionalProperties": .bool(false)
                    ])
                ])
            ]),
            "required": .array([.string("answer"), .string("insufficient_evidence"), .string("insufficiency_reason"), .string("claims")]),
            "additionalProperties": .bool(false)
        ]
        return GroundedPromptPackage(
            request: AIProviderRequest(
                model: model, instructions: instructions, input: input,
                responseSchemaName: "grounded_research_answer", responseSchema: schema,
                maximumOutputTokens: maximumOutputTokens
            ),
            citations: citations,
            noteCitations: noteCitations,
            characterCount: input.count
        )
    }

    public static func decodeAndValidate(_ data: String, allowedCitationLabels: Set<String>) throws -> GroundedAnswer {
        let answer: GroundedAnswer
        do { answer = try JSONDecoder().decode(GroundedAnswer.self, from: Data(data.utf8)) }
        catch { throw AIProviderError.invalidResponse("Structured answer decoding failed: \(error.localizedDescription)") }
        if answer.insufficientEvidence {
            guard answer.claims.isEmpty else {
                throw AIProviderError.insufficientGrounding("The response marked evidence insufficient but still returned substantive claims.")
            }
            guard !answer.insufficiencyReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIProviderError.insufficientGrounding("The response did not explain why evidence was insufficient.")
            }
            return answer
        }
        guard !answer.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !answer.claims.isEmpty else {
            throw AIProviderError.insufficientGrounding("A supported answer requires an answer and at least one citation-bearing claim.")
        }
        for claim in answer.claims {
            guard !claim.citations.isEmpty else {
                throw AIProviderError.insufficientGrounding("A substantive claim had no citation.")
            }
            for label in claim.citations where !allowedCitationLabels.contains(label) {
                throw AIProviderError.unsupportedCitation(label)
            }
        }
        return answer
    }
}

private enum GroundedCriticalSourceBuilder {
    static func packageMaterial(
        analysisID: UUID,
        context: String,
        passages: [RetrievedPassage],
        noteSnippets: [RetrievedNoteSnippet] = [],
        literature: [LiteratureItem]
    ) throws -> (input: String, citations: [AIAnalysisCitation], noteCitations: [AIAnalysisNoteCitation]) {
        let usable = passages.filter { $0.citationStatus == .current }
        let usableNotes = noteSnippets.filter { $0.citationStatus == .current }
        guard !usable.isEmpty || !usableNotes.isEmpty else {
            throw AIProviderError.insufficientGrounding("No current paper passages or note excerpts are available. Refresh or replace stale retrieval evidence before transmission.")
        }
        let literatureByID = Dictionary(uniqueKeysWithValues: literature.map { ($0.id, $0) })
        var blocks: [String] = []
        var citations: [AIAnalysisCitation] = []
        var noteCitations: [AIAnalysisNoteCitation] = []
        for (offset, passage) in usable.enumerated() {
            let label = "S\(offset + 1)"
            let title = literatureByID[passage.literatureID]?.title ?? "Unavailable title"
            blocks.append("[\(label)] \(title), page \(passage.page)\n\(passage.passageText)")
            citations.append(AIAnalysisCitation(
                analysisID: analysisID, label: label, sourcePassageID: passage.sourcePassageID,
                literatureID: passage.literatureID, page: passage.page, quotedPassage: passage.passageText,
                sourceDocumentHash: passage.sourceDocumentHash, citationStatus: passage.citationStatus
            ))
        }
        for (offset, note) in usableNotes.enumerated() {
            let label = "N\(offset + 1)"
            blocks.append("[\(label)] Researcher note: \(note.noteTitle)\n\(note.snippetText)")
            noteCitations.append(AIAnalysisNoteCitation(
                analysisID: analysisID, label: label, noteID: note.noteID,
                notePath: note.notePath, noteTitle: note.noteTitle,
                quotedSnippet: note.snippetText, sourceModifiedAt: note.sourceModifiedAt,
                citationStatus: note.citationStatus
            ))
        }
        return (
            "RESEARCH CONTEXT\n\(context)\n\nRETRIEVED SOURCE PASSAGES\n\(blocks.joined(separator: "\n\n"))",
            citations,
            noteCitations
        )
    }

    static func validate(labels: [String], allowed: Set<String>, field: String) throws {
        guard !labels.isEmpty else { throw AIProviderError.insufficientGrounding("\(field) had no source citation.") }
        for label in labels where !allowed.contains(label) { throw AIProviderError.unsupportedCitation(label) }
    }

    static func contributionSchema() -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "content": .object(["type": .string("string")]),
                "citations": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "uncertainty": .object(["type": .string("string")])
            ]),
            "required": .array([.string("content"), .string("citations"), .string("uncertainty")]),
            "additionalProperties": .bool(false)
        ])
    }
}

public enum GroundedDeliberationBuilder {
    public static let promptVersion = "grounded-argument-room-v1"

    public static func package(
        analysisID: UUID,
        argument: ResearchArgument,
        evidence: [EvidenceRelationship],
        passages: [RetrievedPassage],
        noteSnippets: [RetrievedNoteSnippet] = [],
        literature: [LiteratureItem],
        model: String,
        maximumOutputTokens: Int
    ) throws -> GroundedPromptPackage {
        let recordedEvidence = evidence.enumerated().map { index, item in
            "E\(index + 1): \(item.relation.rawValue) — \(item.summary) [human verification: \(item.verification.rawValue)]"
        }.joined(separator: "\n")
        let context = """
            PROPOSITION
            \(argument.proposition)

            RECORDED QUALIFICATION
            \(argument.qualification.isEmpty ? "None recorded" : argument.qualification)

            APPLICATION EVIDENCE RELATIONSHIPS
            \(recordedEvidence.isEmpty ? "None recorded" : recordedEvidence)
            """
        let material = try GroundedCriticalSourceBuilder.packageMaterial(
            analysisID: analysisID, context: context, passages: passages,
            noteSnippets: noteSnippets, literature: literature
        )
        let roleValues: [JSONValue] = [
            DeliberationPerspective.theoretical, .methodological, .evidence, .alternative
        ].map { .string($0.rawValue) }
        let contribution = GroundedCriticalSourceBuilder.contributionSchema()
        let roleSchema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "perspective": .object(["type": .string("string"), "enum": .array(roleValues)]),
                "initial_assessment": contribution,
                "cross_examination": contribution,
                "revised_assessment": contribution
            ]),
            "required": .array([.string("perspective"), .string("initial_assessment"), .string("cross_examination"), .string("revised_assessment")]),
            "additionalProperties": .bool(false)
        ])
        let schema: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object([
                "insufficient_evidence": .object(["type": .string("boolean")]),
                "insufficiency_reason": .object(["type": .string("string")]),
                "roles": .object(["type": .string("array"), "items": roleSchema]),
                "synthesis": contribution
            ]),
            "required": .array([.string("insufficient_evidence"), .string("insufficiency_reason"), .string("roles"), .string("synthesis")]),
            "additionalProperties": .bool(false)
        ]
        let instructions = """
            Simulate four critical roles using the same model: Theoretical Critic, Methodological Critic, Evidence Reviewer, and Alternative Explanation Reviewer. These are not independent experts. Each role must first assess the proposition, then challenge assumptions or another perspective, then revise its assessment. End with a Synthesis Perspective that maps agreements, disagreements, unresolved questions, and what evidence would change the assessment; do not manufacture consensus. Use only supplied sources for literature-dependent statements. [S#] labels are paper passages; [N#] labels are researcher-note excerpts and are not published evidence. Every contribution must cite one or more allowed labels, distinguish source reports from interpretation, preserve qualifications, and state uncertainty. Return exactly one of each required role. If the evidence cannot support a responsible deliberation, set insufficient_evidence true, explain why, return no roles, and return an empty synthesis contribution.
            """
        return GroundedPromptPackage(
            request: AIProviderRequest(
                model: model, instructions: instructions, input: material.input,
                responseSchemaName: "grounded_argument_room", responseSchema: schema,
                maximumOutputTokens: maximumOutputTokens
            ),
            citations: material.citations,
            noteCitations: material.noteCitations,
            characterCount: material.input.count
        )
    }

    public static func decodeAndValidate(_ data: String, allowedCitationLabels: Set<String>) throws -> GroundedDeliberationOutput {
        let output: GroundedDeliberationOutput
        do { output = try JSONDecoder().decode(GroundedDeliberationOutput.self, from: Data(data.utf8)) }
        catch { throw AIProviderError.invalidResponse("Structured deliberation decoding failed: \(error.localizedDescription)") }
        if output.insufficientEvidence {
            guard output.roles.isEmpty, !output.insufficiencyReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIProviderError.insufficientGrounding("An insufficient-evidence deliberation must contain no roles and explain the missing evidence.")
            }
            return output
        }
        let required: Set<DeliberationPerspective> = [.theoretical, .methodological, .evidence, .alternative]
        guard output.roles.count == required.count, Set(output.roles.map(\.perspective)) == required else {
            throw AIProviderError.invalidResponse("The deliberation did not return exactly one of each required critical role.")
        }
        for role in output.roles {
            for (phase, contribution) in [
                ("\(role.perspective.rawValue) initial assessment", role.initialAssessment),
                ("\(role.perspective.rawValue) cross-examination", role.crossExamination),
                ("\(role.perspective.rawValue) revised assessment", role.revisedAssessment)
            ] {
                guard !contribution.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw AIProviderError.invalidResponse("\(phase) was empty.")
                }
                try GroundedCriticalSourceBuilder.validate(labels: contribution.citations, allowed: allowedCitationLabels, field: phase)
            }
        }
        guard !output.synthesis.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProviderError.invalidResponse("The synthesis was empty.")
        }
        try GroundedCriticalSourceBuilder.validate(labels: output.synthesis.citations, allowed: allowedCitationLabels, field: "Synthesis")
        return output
    }
}

public enum GroundedCollectiveTurnBuilder {
    public static let promptVersion = "grounded-collective-turn-v1"

    public static func package(
        analysisID: UUID,
        experiment: CollectiveExperiment,
        agent: CollectiveAgent,
        round: Int,
        kind: CollectiveTurnKind,
        additionalInstruction: String,
        priorTurns: [CollectiveTurn],
        passages: [RetrievedPassage],
        literature: [LiteratureItem],
        model: String,
        maximumOutputTokens: Int
    ) throws -> GroundedPromptPackage {
        let priorContext: String
        if experiment.interactionMode == .independent {
            priorContext = "Hidden by the independent-assessment design. Do not infer other roles' judgments."
        } else if priorTurns.isEmpty {
            priorContext = "No earlier turns are recorded."
        } else {
            priorContext = priorTurns.map { turn in
                let confidence = turn.confidence.map { String(format: "%.2f", $0) } ?? "not recorded"
                return "Turn \(turn.sequence), round \(turn.round), \(turn.kind.rawValue), confidence \(confidence):\n\(turn.responseText)"
            }.joined(separator: "\n\n")
        }
        let context = """
            EXPERIMENT
            Title: \(experiment.title)
            Research purpose: \(experiment.researchPurpose.isEmpty ? "Not recorded" : experiment.researchPurpose)
            Interaction mode: \(experiment.interactionMode.rawValue)
            Task: \(experiment.taskInstructions)

            CURRENT SIMULATED ROLE
            Label: \(agent.label)
            Assigned role: \(agent.role.isEmpty ? "No specialist role recorded" : agent.role)
            Information condition: \(agent.informationAvailable.isEmpty ? "Use only the task and supplied source passages" : agent.informationAvailable)
            Requested turn: round \(round), \(kind.rawValue)
            Additional researcher instruction: \(additionalInstruction.isEmpty ? "None" : additionalInstruction)

            PRIOR RECORDED TURNS AVAILABLE TO THIS ROLE
            \(priorContext)
            """
        let material = try GroundedCriticalSourceBuilder.packageMaterial(
            analysisID: analysisID, context: context, passages: passages, literature: literature
        )
        let schema: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object([
                "insufficient_evidence": .object(["type": .string("boolean")]),
                "insufficiency_reason": .object(["type": .string("string")]),
                "response": .object(["type": .string("string")]),
                "confidence": .object(["type": .string("number"), "minimum": .number(0), "maximum": .number(1)]),
                "uncertainty": .object(["type": .string("string")]),
                "citations": .object(["type": .string("array"), "items": .object(["type": .string("string")])])
            ]),
            "required": .array([
                .string("insufficient_evidence"), .string("insufficiency_reason"), .string("response"),
                .string("confidence"), .string("uncertainty"), .string("citations")
            ]),
            "additionalProperties": .bool(false)
        ]
        let instructions = """
            Produce one bounded contribution for the explicitly named simulated role. All roles in this experiment use the same configured model: do not claim independent expertise, consciousness, consensus, or validation of collective intelligence. Follow the role and information condition without inventing hidden evidence. Use only supplied [S#] passages for literature-dependent claims, preserve source qualifications, distinguish source reports from interpretation, and cite every substantive contribution with one or more allowed labels. State uncertainty and give calibrated confidence from 0 to 1. If the passages cannot support a responsible contribution, set insufficient_evidence true, explain what is missing, return an empty response and citations, and use confidence 0. Otherwise set insufficient_evidence false and leave insufficiency_reason empty.
            """
        return GroundedPromptPackage(
            request: AIProviderRequest(
                model: model, instructions: instructions, input: material.input,
                responseSchemaName: "grounded_collective_turn", responseSchema: schema,
                maximumOutputTokens: maximumOutputTokens
            ),
            citations: material.citations,
            characterCount: material.input.count
        )
    }

    public static func decodeAndValidate(
        _ data: String,
        allowedCitationLabels: Set<String>
    ) throws -> GroundedCollectiveTurnOutput {
        let output: GroundedCollectiveTurnOutput
        do { output = try JSONDecoder().decode(GroundedCollectiveTurnOutput.self, from: Data(data.utf8)) }
        catch { throw AIProviderError.invalidResponse("Structured collective-turn decoding failed: \(error.localizedDescription)") }
        guard (0...1).contains(output.confidence) else {
            throw AIProviderError.invalidResponse("Collective-turn confidence was outside 0 to 1.")
        }
        guard !output.uncertainty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProviderError.invalidResponse("The collective turn did not state its uncertainty.")
        }
        if output.insufficientEvidence {
            guard output.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  output.citations.isEmpty,
                  output.confidence == 0,
                  !output.insufficiencyReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIProviderError.insufficientGrounding("An insufficient-evidence collective turn must explain the gap, return no answer or citations, and use zero confidence.")
            }
            return output
        }
        guard output.insufficiencyReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !output.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProviderError.invalidResponse("A completed collective turn requires a response and no insufficiency reason.")
        }
        try GroundedCriticalSourceBuilder.validate(
            labels: output.citations, allowed: allowedCitationLabels, field: "Collective-lab response"
        )
        return output
    }
}

public enum GroundedBiasAuditBuilder {
    public static let promptVersion = "grounded-bias-audit-v1"

    public static func package(
        analysisID: UUID,
        argument: ResearchArgument,
        evidence: [EvidenceRelationship],
        passages: [RetrievedPassage],
        noteSnippets: [RetrievedNoteSnippet] = [],
        literature: [LiteratureItem],
        model: String,
        maximumOutputTokens: Int
    ) throws -> GroundedPromptPackage {
        let recordedEvidence = evidence.enumerated().map { index, item in
            "E\(index + 1): \(item.relation.rawValue) — \(item.summary) [human verification: \(item.verification.rawValue)]"
        }.joined(separator: "\n")
        let context = """
            ARGUMENT TO CRITICALLY EXAMINE
            \(argument.proposition)

            RECORDED QUALIFICATION
            \(argument.qualification.isEmpty ? "None recorded" : argument.qualification)

            APPLICATION EVIDENCE RELATIONSHIPS
            \(recordedEvidence.isEmpty ? "None recorded" : recordedEvidence)
            """
        let material = try GroundedCriticalSourceBuilder.packageMaterial(
            analysisID: analysisID, context: context, passages: passages,
            noteSnippets: noteSnippets, literature: literature
        )
        let concernSchema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "kind": .object(["type": .string("string"), "enum": .array(BiasConcernKind.allCases.map { .string($0.rawValue) })]),
                "potential_problem": .object(["type": .string("string")]),
                "why_it_matters": .object(["type": .string("string")]),
                "alternative_interpretations": .object(["type": .string("string")]),
                "investigation_questions": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "uncertainty": .object(["type": .string("string")]),
                "citations": .object(["type": .string("array"), "items": .object(["type": .string("string")])])
            ]),
            "required": .array([.string("kind"), .string("potential_problem"), .string("why_it_matters"), .string("alternative_interpretations"), .string("investigation_questions"), .string("uncertainty"), .string("citations")]),
            "additionalProperties": .bool(false)
        ])
        let schema: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object([
                "insufficient_evidence": .object(["type": .string("boolean")]),
                "insufficiency_reason": .object(["type": .string("string")]),
                "concerns": .object(["type": .string("array"), "items": concernSchema])
            ]),
            "required": .array([.string("insufficient_evidence"), .string("insufficiency_reason"), .string("concerns")]),
            "additionalProperties": .bool(false)
        ]
        let instructions = """
            Critically examine the recorded argument and evidence without diagnosing the researcher's psychology or motives. Identify only specific, source-linked reasoning patterns that warrant investigation. Consider evidence quality and relevance, preserve qualifications, and offer plausible alternative interpretations. [S#] labels are paper passages; [N#] labels are researcher-note excerpts and are not published evidence. Every concern must cite one or more allowed labels and include uncertainty plus concrete questions for the researcher. Treat all output as reviewable suggestions, never verified findings. If the supplied sources are insufficient, set insufficient_evidence true, explain what is missing, and return no concerns.
            """
        return GroundedPromptPackage(
            request: AIProviderRequest(
                model: model, instructions: instructions, input: material.input,
                responseSchemaName: "grounded_bias_audit", responseSchema: schema,
                maximumOutputTokens: maximumOutputTokens
            ),
            citations: material.citations,
            noteCitations: material.noteCitations,
            characterCount: material.input.count
        )
    }

    public static func decodeAndValidate(_ data: String, allowedCitationLabels: Set<String>) throws -> GroundedBiasAuditOutput {
        let output: GroundedBiasAuditOutput
        do { output = try JSONDecoder().decode(GroundedBiasAuditOutput.self, from: Data(data.utf8)) }
        catch { throw AIProviderError.invalidResponse("Structured bias-audit decoding failed: \(error.localizedDescription)") }
        if output.insufficientEvidence {
            guard output.concerns.isEmpty, !output.insufficiencyReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIProviderError.insufficientGrounding("An insufficient-evidence bias audit must contain no concerns and explain the missing evidence.")
            }
            return output
        }
        guard !output.concerns.isEmpty else { throw AIProviderError.insufficientGrounding("The bias audit returned no reviewable concerns.") }
        for concern in output.concerns {
            guard !concern.potentialProblem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !concern.whyItMatters.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !concern.investigationQuestions.isEmpty else {
                throw AIProviderError.invalidResponse("A bias-audit concern was incomplete.")
            }
            try GroundedCriticalSourceBuilder.validate(labels: concern.citations, allowed: allowedCitationLabels, field: concern.kind.rawValue)
        }
        return output
    }
}

public enum GroundedContradictionReviewBuilder {
    public static let promptVersion = "grounded-contradiction-review-v1"

    public static func package(
        analysisID: UUID,
        contradiction: ContradictionCase,
        sources: [ContradictionSource],
        comparisonProfiles: [LiteratureComparisonProfile],
        passages: [RetrievedPassage],
        noteSnippets: [RetrievedNoteSnippet] = [],
        literature: [LiteratureItem],
        model: String,
        maximumOutputTokens: Int
    ) throws -> GroundedPromptPackage {
        let profiles = Dictionary(uniqueKeysWithValues: comparisonProfiles.map { ($0.literatureID, $0) })
        let papers = Dictionary(uniqueKeysWithValues: literature.map { ($0.id, $0) })
        let sourceContext = sources.enumerated().map { index, source in
            let profile = profiles[source.literatureID]
            return """
                C\(index + 1): \(papers[source.literatureID]?.title ?? "Unavailable source")
                Recorded role/finding: \(source.role) — \(source.finding)
                Recorded contextual difference: \(source.contextualDifference)
                Design/sample: \([profile?.studyDesign, profile?.sample].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "; "))
                Definitions/variables: \([profile?.operationalDefinitions, profile?.independentVariables, profile?.dependentVariables].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "; "))
                Limitations: \(profile?.limitations ?? "")
                Human verification: \(source.verification.rawValue)
                """
        }.joined(separator: "\n\n")
        let context = """
            APPARENT CONFLICT
            \(contradiction.title)

            RESEARCHER'S COMPARISON RATIONALE
            \(contradiction.summary)

            RECORDED COMPARISON SOURCES
            \(sourceContext.isEmpty ? "None recorded" : sourceContext)
            """
        let material = try GroundedCriticalSourceBuilder.packageMaterial(
            analysisID: analysisID, context: context, passages: passages,
            noteSnippets: noteSnippets, literature: literature
        )
        let schema: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object([
                "insufficient_evidence": .object(["type": .string("boolean")]),
                "insufficiency_reason": .object(["type": .string("string")]),
                "suggested_status": .object(["type": .string("string"), "enum": .array(ContradictionCaseStatus.allCases.map { .string($0.rawValue) })]),
                "assessment": .object(["type": .string("string")]),
                "possible_explanations": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "contextual_differences": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "unresolved_questions": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "citations": .object(["type": .string("array"), "items": .object(["type": .string("string")])])
            ]),
            "required": .array([.string("insufficient_evidence"), .string("insufficiency_reason"), .string("suggested_status"), .string("assessment"), .string("possible_explanations"), .string("contextual_differences"), .string("unresolved_questions"), .string("citations")]),
            "additionalProperties": .bool(false)
        ]
        let instructions = """
            Investigate whether the apparent conflict is a genuine contradiction or may arise from design, population, task, intervention quality, measurement, operational definition, analysis, or context. Use only the supplied sources for literature-dependent statements. [S#] labels are paper passages; [N#] labels are researcher-note excerpts and are not published evidence. Cite every assessment with allowed labels. Preserve ambiguity, identify missing details, and do not silently change the researcher's contradiction record. The suggested status is a reviewable model suggestion only. If the evidence is insufficient, set insufficient_evidence true, explain what is missing, leave the assessment and arrays empty, use Open as the suggested status, and return no citations.
            """
        return GroundedPromptPackage(
            request: AIProviderRequest(
                model: model, instructions: instructions, input: material.input,
                responseSchemaName: "grounded_contradiction_review", responseSchema: schema,
                maximumOutputTokens: maximumOutputTokens
            ),
            citations: material.citations,
            noteCitations: material.noteCitations,
            characterCount: material.input.count
        )
    }

    public static func decodeAndValidate(_ data: String, allowedCitationLabels: Set<String>) throws -> GroundedContradictionReviewOutput {
        let output: GroundedContradictionReviewOutput
        do { output = try JSONDecoder().decode(GroundedContradictionReviewOutput.self, from: Data(data.utf8)) }
        catch { throw AIProviderError.invalidResponse("Structured contradiction-review decoding failed: \(error.localizedDescription)") }
        if output.insufficientEvidence {
            guard output.citations.isEmpty, !output.insufficiencyReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIProviderError.insufficientGrounding("An insufficient-evidence contradiction review must contain no citations and explain the missing evidence.")
            }
            return output
        }
        guard !output.assessment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !output.unresolvedQuestions.isEmpty else {
            throw AIProviderError.invalidResponse("The contradiction review did not include an assessment and unresolved questions.")
        }
        try GroundedCriticalSourceBuilder.validate(labels: output.citations, allowed: allowedCitationLabels, field: "Contradiction assessment")
        return output
    }
}
