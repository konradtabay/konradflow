import Foundation

enum LLMAPITransport {
    private static let sharedSessionLock = NSLock()
    private static var sharedSession: URLSession?
    private static var warmedHosts = Set<String>()

    private static func makeSharedSession(timeout: TimeInterval = 60) -> URLSession {
        sharedSessionLock.lock()
        defer { sharedSessionLock.unlock() }

        if let sharedSession {
            return sharedSession
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        sharedSession = session
        return session
    }

    private static func timeout(for request: URLRequest) -> TimeInterval {
        let requestTimeout = request.timeoutInterval
        guard requestTimeout.isFinite, requestTimeout > 0 else {
            return 60
        }
        return requestTimeout
    }

    static func warmConnections(baseURL: String, apiKey: String) {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let host = url.host else {
            return
        }

        sharedSessionLock.lock()
        let alreadyWarmed = warmedHosts.contains(host)
        if !alreadyWarmed {
            warmedHosts.insert(host)
        }
        sharedSessionLock.unlock()
        guard !alreadyWarmed else { return }

        var request = URLRequest(url: url.appendingPathComponent("models"))
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        Task {
            _ = try? await makeSharedSession(timeout: 5).data(for: request)
        }
    }

    static func data(
        for request: URLRequest
    ) async throws -> (Data, URLResponse) {
        try await makeSharedSession(timeout: timeout(for: request)).data(for: request)
    }

    static func upload(
        for request: URLRequest,
        from bodyData: Data
    ) async throws -> (Data, URLResponse) {
        try await makeSharedSession(timeout: timeout(for: request)).upload(for: request, from: bodyData)
    }
}
