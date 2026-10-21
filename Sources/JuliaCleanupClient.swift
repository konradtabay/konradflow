import Darwin
import Foundation
import os.log

private let juliaClientLog = OSLog(subsystem: "com.konradtabay.konradflow", category: "JuliaCleanup")

struct JuliaCleanupDecision {
    let index: Int
    let probabilities: [Double]
    let topProbability: Double

    static let abstain = JuliaCleanupDecision(index: -1, probabilities: [], topProbability: 0)
}

final class JuliaCleanupClient {
    static let shared = JuliaCleanupClient()

    private let queue = DispatchQueue(label: "com.konradtabay.konradflow.julia.client")
    private var process: Process?
    private var isModelReady = false
    private var restartScheduled = false
    private let requestTimeout: TimeInterval = 5

    private init() {}

    var isReady: Bool {
        queue.sync { isModelReady && process?.isRunning == true }
    }

    func startIfNeeded() {
        queue.async {
            self.launchHelperLocked()
        }
    }

    func choose(transcript: String, options: [String]) async -> JuliaCleanupDecision {
        guard options.count >= 2 else { return .abstain }

        return await withCheckedContinuation { continuation in
            queue.async {
                guard self.isModelReady, self.process?.isRunning == true else {
                    continuation.resume(returning: .abstain)
                    return
                }

                let socketPath = Self.socketPath()
                let request: [String: Any] = [
                    "state": transcript,
                    "question": "Which sentence is the cleaned dictation?",
                    "options": options,
                ]

                do {
                    let responseData = try self.sendRequest(request, socketPath: socketPath)
                    guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
                        continuation.resume(returning: .abstain)
                        return
                    }
                    if json["error"] != nil {
                        continuation.resume(returning: .abstain)
                        return
                    }
                    let index = json["index"] as? Int ?? -1
                    let probs = (json["probabilities"] as? [Double]) ?? (json["probabilities"] as? [NSNumber])?.map(\.doubleValue) ?? []
                    let top = probs.max() ?? 0
                    guard index >= 0, index < options.count else {
                        continuation.resume(returning: .abstain)
                        return
                    }
                    continuation.resume(returning: JuliaCleanupDecision(index: index, probabilities: probs, topProbability: top))
                } catch {
                    os_log(.error, log: juliaClientLog, "Julia request failed: %{public}@", error.localizedDescription)
                    continuation.resume(returning: .abstain)
                }
            }
        }
    }

    private func launchHelperLocked() {
        guard process == nil || process?.isRunning != true else { return }

        let scriptURL = Self.helperScriptURL()
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            os_log(.error, log: juliaClientLog, "helper script missing at %{public}@", scriptURL.path)
            return
        }

        let proc = Process()
        proc.executableURL = Self.helperPythonExecutable()
        proc.arguments = [scriptURL.path]
        proc.environment = Self.helperEnvironment()
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        proc.terminationHandler = { [weak self] _ in
            self?.queue.async {
                self?.isModelReady = false
                self?.process = nil
                self?.scheduleRestartLocked()
            }
        }

        do {
            try proc.run()
            process = proc
            waitForSocketReady(path: Self.socketPath())
            isModelReady = true
            os_log(.info, log: juliaClientLog, "Julia helper started")
        } catch {
            os_log(.error, log: juliaClientLog, "failed to start helper: %{public}@", error.localizedDescription)
        }
    }

    private func scheduleRestartLocked() {
        guard !restartScheduled else { return }
        restartScheduled = true
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.queue.async {
                self?.restartScheduled = false
                self?.launchHelperLocked()
            }
        }
    }

    private func waitForSocketReady(path: String, timeout: TimeInterval = 120) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: path) {
                return
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    private func sendRequest(_ request: [String: Any], socketPath: String) throws -> Data {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(.EIO)
        }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathData = socketPath.utf8CString
        guard pathData.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            throw POSIXError(.ENAMETOOLONG)
        }
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            pathData.withUnsafeBufferPointer { buffer in
                memcpy(ptr, buffer.baseAddress, buffer.count)
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw POSIXError(.ECONNREFUSED)
        }

        let payload = try JSONSerialization.data(withJSONObject: request)
        var line = payload
        line.append(0x0A)
        _ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }

        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        let deadline = Date().addingTimeInterval(requestTimeout)
        while Date() < deadline {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            received.append(contentsOf: buffer.prefix(count))
            if received.contains(0x0A) {
                if let newlineIndex = received.firstIndex(of: 0x0A) {
                    return received.prefix(upTo: newlineIndex)
                }
            }
        }
        throw POSIXError(.ETIMEDOUT)
    }

    private static func socketPath() -> String {
        let appName = AppName.displayName
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(appName, isDirectory: true)
        return base?.appendingPathComponent("julia-cleanup.sock").path
            ?? NSTemporaryDirectory() + "konradflow-julia-cleanup.sock"
    }

    private static func helperScriptURL() -> URL {
        if let bundled = Bundle.main.url(forResource: "julia_cleanup_helper", withExtension: "py", subdirectory: "Scripts") {
            return bundled
        }
        let sourceRelative = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts/julia_cleanup_helper.py")
        if FileManager.default.fileExists(atPath: sourceRelative.path) {
            return sourceRelative
        }
        return Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts/julia_cleanup_helper.py")
    }

    private static func helperPythonExecutable() -> URL {
        if let override = ProcessInfo.processInfo.environment["JULIA_PYTHON"],
           FileManager.default.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        let venvPython = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Julia-1-venv/bin/python")
        if FileManager.default.isExecutableFile(atPath: venvPython.path) {
            return venvPython
        }
        return URL(fileURLWithPath: "/usr/bin/python3")
    }

    private static func helperEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["JULIA_SOCKET_PATH"] = socketPath()
        if env["JULIA_MODEL_PATH"] == nil {
            let defaultModel = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Julia-1")
            if FileManager.default.fileExists(atPath: defaultModel.path) {
                env["JULIA_MODEL_PATH"] = defaultModel.path
            }
        }
        return env
    }
}
