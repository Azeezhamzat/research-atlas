import Foundation

enum OllamaRuntimeStatus: Equatable, Sendable {
    case stopped
    case starting
    case loading(model: String)
    case ready(model: String, managedByResearchAtlas: Bool)
    case generating(model: String)
    case unavailable(String)

    var title: String {
        switch self {
        case .stopped: "Stopped"
        case .starting: "Starting local engine"
        case .loading(let model): "Loading \(model)"
        case .ready(let model, _): "Ready · \(model)"
        case .generating(let model): "Generating · \(model)"
        case .unavailable: "Unavailable"
        }
    }

    var detail: String {
        switch self {
        case .stopped:
            "Research Atlas will start its bundled local engine when a request is approved."
        case .starting:
            "Starting the loopback-only inference engine on 127.0.0.1."
        case .loading(let model):
            "Loading \(model) into unified memory. The first request can take longer."
        case .ready(_, let managed):
            managed
                ? "Research Atlas started this engine and will stop it after the configured idle period."
                : "Research Atlas connected to an engine that was already running and will not stop it."
        case .generating:
            "The approved request is running locally on this Mac."
        case .unavailable(let message):
            message
        }
    }

    var systemImage: String {
        switch self {
        case .stopped: "power"
        case .starting, .loading: "arrow.triangle.2.circlepath"
        case .ready: "checkmark.circle.fill"
        case .generating: "brain.head.profile"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }
}

enum OllamaRuntimeError: Error, LocalizedError {
    case executableMissing
    case launch(String)
    case startupTimeout
    case modelUnavailable(String)
    case response(String)

    var errorDescription: String? {
        switch self {
        case .executableMissing:
            "Research Atlas could not find its bundled local AI engine. Rebuild the app while the Ollama command-line runtime is available."
        case .launch(let message):
            "The local AI engine could not start: \(message)"
        case .startupTimeout:
            "The local AI engine did not become ready on 127.0.0.1:11434."
        case .modelUnavailable(let model):
            "The local model \(model) is not installed in the Ollama model store."
        case .response(let message):
            "The local AI engine returned an invalid readiness response: \(message)"
        }
    }
}

@MainActor
final class OllamaRuntimeController {
    typealias StatusHandler = @MainActor @Sendable (OllamaRuntimeStatus, Bool) -> Void

    private let baseURL = URL(string: "http://127.0.0.1:11434")!
    private let statusHandler: StatusHandler
    private let session: URLSession
    private var managedProcess: Process?
    private var idleTask: Task<Void, Never>?
    private var activeRequests = 0

    init(statusHandler: @escaping StatusHandler) {
        self.statusHandler = statusHandler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        self.session = URLSession(
            configuration: configuration,
            delegate: OllamaRuntimeRedirectBlocker.shared,
            delegateQueue: nil
        )
    }

    func acquire(model: String, idleMinutes: Int) async throws {
        idleTask?.cancel()
        idleTask = nil
        activeRequests += 1
        do {
            if !(await isReachable()) {
                try startManagedEngine()
                try await waitUntilReady()
            }
            try await verifyModel(model)
            setStatus(.loading(model: model))
            try await preload(model: model, idleMinutes: idleMinutes)
            setStatus(.ready(model: model, managedByResearchAtlas: managedProcess != nil))
        } catch {
            activeRequests = max(0, activeRequests - 1)
            setStatus(.unavailable(error.localizedDescription))
            scheduleIdleShutdown(after: idleMinutes)
            throw error
        }
    }

    func markGenerating(model: String) {
        setStatus(.generating(model: model))
    }

    func release(model: String, idleMinutes: Int) {
        activeRequests = max(0, activeRequests - 1)
        setStatus(.ready(model: model, managedByResearchAtlas: managedProcess != nil))
        scheduleIdleShutdown(after: idleMinutes)
    }

    func stopManagedEngine() {
        idleTask?.cancel()
        idleTask = nil
        activeRequests = 0
        guard let process = managedProcess else { return }
        if process.isRunning { process.terminate() }
        managedProcess = nil
        setStatus(.stopped)
    }

    func shutdown() {
        stopManagedEngine()
        session.invalidateAndCancel()
    }

    private func startManagedEngine() throws {
        if let process = managedProcess {
            if process.isRunning { return }
            managedProcess = nil
        }
        guard let executable = localExecutableURL() else { throw OllamaRuntimeError.executableMissing }
        setStatus(.starting)
        let process = Process()
        process.executableURL = executable
        process.arguments = ["serve"]
        var environment = ProcessInfo.processInfo.environment
        environment["OLLAMA_HOST"] = "127.0.0.1:11434"
        environment["OLLAMA_ORIGINS"] = ""
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() }
        catch { throw OllamaRuntimeError.launch(error.localizedDescription) }
        managedProcess = process
    }

    private func waitUntilReady() async throws {
        for _ in 0..<80 {
            if await isReachable() { return }
            try await Task.sleep(for: .milliseconds(250))
        }
        stopManagedEngine()
        throw OllamaRuntimeError.startupTimeout
    }

    private func isReachable() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 2
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }

    private func verifyModel(_ model: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/show"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OllamaRuntimeError.response("No HTTP status was returned.")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 { throw OllamaRuntimeError.modelUnavailable(model) }
            let message = Self.errorMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw OllamaRuntimeError.response(message)
        }
    }

    private func preload(model: String, idleMinutes: Int) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "prompt": "",
            "stream": false,
            "keep_alive": "\(max(1, idleMinutes))m"
        ])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = Self.errorMessage(from: data) ?? "The model could not be loaded."
            throw OllamaRuntimeError.response(message)
        }
    }

    private func scheduleIdleShutdown(after minutes: Int) {
        idleTask?.cancel()
        idleTask = nil
        guard activeRequests == 0, managedProcess != nil else { return }
        let delay = max(1, minutes)
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay * 60))
            guard !Task.isCancelled else { return }
            self?.stopManagedEngine()
        }
    }

    private func localExecutableURL() -> URL? {
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("Runtime/ollama"))
        }
        candidates += [
            URL(filePath: "/opt/homebrew/bin/ollama"),
            URL(filePath: "/usr/local/bin/ollama"),
            URL(filePath: "/Applications/Ollama.app/Contents/Resources/ollama")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func setStatus(_ status: OllamaRuntimeStatus) {
        statusHandler(status, managedProcess != nil)
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["error"] as? String
    }
}

private final class OllamaRuntimeRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = OllamaRuntimeRedirectBlocker()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
