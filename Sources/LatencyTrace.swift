import Foundation
import os.log

private let latencyLog = OSLog(subsystem: "com.konradtabay.konradflow", category: "Latency")

enum LatencyStage: String, Codable, CaseIterable {
    case holdActivated
    case startRecordingEntered
    case beginRecording
    case firstBuffer
    case holdDeactivated
    case wavReady
    case sttDone
    case contextReady
    case candidatesBuilt
    case juliaDone
    case ppDone
    case pastePosted
}

struct LatencyTraceConfig: Codable {
    let transcriptionModel: String
    let postProcessingModel: String
    let realtimeStreamingEnabled: Bool
    let preserveExactWording: Bool
    let fastDictationContextEnabled: Bool
    let fastPostProcessingEnabled: Bool
    let pasteLightEnabled: Bool
}

struct LatencyTraceRecord: Codable {
    let traceID: String
    let config: LatencyTraceConfig
    let timestamps: [String: Double]
    let completedAt: Double

    var tStartMs: Double? {
        guard let hold = timestamps[LatencyStage.holdActivated.rawValue],
              let first = timestamps[LatencyStage.firstBuffer.rawValue] else {
            return nil
        }
        return (first - hold) * 1000
    }

    var tPasteMs: Double? {
        guard let release = timestamps[LatencyStage.holdDeactivated.rawValue],
              let paste = timestamps[LatencyStage.pastePosted.rawValue] else {
            return nil
        }
        return (paste - release) * 1000
    }

    func spanMs(from start: LatencyStage, to end: LatencyStage) -> Double? {
        guard let startTime = timestamps[start.rawValue],
              let endTime = timestamps[end.rawValue] else {
            return nil
        }
        return (endTime - startTime) * 1000
    }
}

final class LatencyTraceRecorder {
    static let shared = LatencyTraceRecorder()

    private let lock = NSLock()
    private var activeTraceID: String?
    private var timestamps: [LatencyStage: CFAbsoluteTime] = [:]
    private var config: LatencyTraceConfig?

    private init() {}

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeTraceID != nil
    }

    func beginSession(config: LatencyTraceConfig) {
        lock.lock()
        activeTraceID = UUID().uuidString
        timestamps = [.holdActivated: CFAbsoluteTimeGetCurrent()]
        self.config = config
        lock.unlock()
    }

    func mark(_ stage: LatencyStage) {
        lock.lock()
        guard activeTraceID != nil else {
            lock.unlock()
            return
        }
        if timestamps[stage] == nil {
            timestamps[stage] = CFAbsoluteTimeGetCurrent()
        }
        lock.unlock()
    }

    func finishAndExport() {
        lock.lock()
        guard let traceID = activeTraceID, let config else {
            activeTraceID = nil
            timestamps = [:]
            self.config = nil
            lock.unlock()
            return
        }

        let exportedTimestamps = Dictionary(
            uniqueKeysWithValues: timestamps.map { ($0.key.rawValue, $0.value) }
        )
        let record = LatencyTraceRecord(
            traceID: traceID,
            config: config,
            timestamps: exportedTimestamps,
            completedAt: CFAbsoluteTimeGetCurrent()
        )
        activeTraceID = nil
        timestamps = [:]
        self.config = nil
        lock.unlock()

        export(record)
    }

    func reset() {
        lock.lock()
        activeTraceID = nil
        timestamps = [:]
        config = nil
        lock.unlock()
    }

    func finishIfActive() {
        lock.lock()
        let hasActive = activeTraceID != nil
        lock.unlock()
        if hasActive {
            finishAndExport()
        }
    }

    private func export(_ record: LatencyTraceRecord) {
        guard let data = try? JSONEncoder().encode(record),
              let jsonLine = String(data: data, encoding: .utf8) else {
            return
        }

        os_log(.info, log: latencyLog, "latency_trace %{public}@", jsonLine)

        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "KonradFlow"
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent(appName, isDirectory: true)

        guard let supportDirectory else { return }

        do {
            try FileManager.default.createDirectory(
                at: supportDirectory,
                withIntermediateDirectories: true
            )
            let traceFile = supportDirectory.appendingPathComponent("latency-traces.jsonl")
            let line = jsonLine + "\n"
            if FileManager.default.fileExists(atPath: traceFile.path) {
                let handle = try FileHandle(forWritingTo: traceFile)
                defer { try? handle.close() }
                try handle.seekToEnd()
                if let lineData = line.data(using: .utf8) {
                    try handle.write(contentsOf: lineData)
                }
            } else {
                try line.write(to: traceFile, atomically: true, encoding: .utf8)
            }
        } catch {
            os_log(.error, log: latencyLog, "failed to write latency trace: %{public}@", error.localizedDescription)
        }
    }
}

enum ShortcutReleaseScheduler {
    static let pollInterval: TimeInterval = 0.01
    static let maxAttempts = 24
    static let pasteDelayAfterRelease: TimeInterval = 0.012

    struct Step {
        let shouldPoll: Bool
        let pasteDelay: TimeInterval
    }

    /// Returns whether to keep polling and the delay before running the paste action.
    static func step(
        hasPressedShortcutInputs: Bool,
        attempt: Int,
        shortcutAlreadyReleased: Bool
    ) -> Step {
        if shortcutAlreadyReleased && !hasPressedShortcutInputs {
            return Step(shouldPoll: false, pasteDelay: pasteDelayAfterRelease)
        }
        if hasPressedShortcutInputs && attempt < maxAttempts {
            return Step(shouldPoll: true, pasteDelay: 0)
        }
        return Step(shouldPoll: false, pasteDelay: pasteDelayAfterRelease)
    }
}

enum LatencyBenchmarkStats {
    static func percentile(_ values: [Double], _ percentile: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = Int(ceil(percentile * Double(sorted.count))) - 1
        let index = min(max(rank, 0), sorted.count - 1)
        return sorted[index]
    }

    static func summarize(values: [Double]) -> [String: Double] {
        var summary: [String: Double] = ["count": Double(values.count)]
        if let p50 = percentile(values, 0.50) { summary["p50"] = p50 }
        if let p95 = percentile(values, 0.95) { summary["p95"] = p95 }
        if let p99 = percentile(values, 0.99) { summary["p99"] = p99 }
        return summary
    }
}
