import Foundation
import os.log

private let pasteLightLog = OSLog(subsystem: "com.konradtabay.konradflow", category: "PasteLight")

/// Tracks streaming partial transcripts during Fn hold and refreshes rule-built candidates.
final class PasteLightHoldCoordinator {
    static let stablePartialInterval: TimeInterval = 0.3

    private(set) var latestPartial: String = ""
    private(set) var lastStablePartial: String = ""
    private(set) var latestCandidates: [String] = []
    private(set) var stableCandidateCount: Int = 0

    private var lastPartialChangeTime: CFAbsoluteTime?
    private var lastPartialText: String = ""
    private var vocabulary: String = ""
    private var cachedDecisionSource: String = ""
    private var cachedDecisionChosen: String = ""
    private var cachedDecisionProbability: Double = -1

    func reset(vocabulary: String) {
        self.vocabulary = vocabulary
        latestPartial = ""
        lastStablePartial = ""
        latestCandidates = []
        stableCandidateCount = 0
        lastPartialChangeTime = nil
        lastPartialText = ""
        cachedDecisionSource = ""
        cachedDecisionChosen = ""
        cachedDecisionProbability = -1
    }

    func cachedDecision(for source: String) -> (chosen: String, probability: Double)? {
        guard source == cachedDecisionSource, cachedDecisionProbability >= 0 else { return nil }
        return (cachedDecisionChosen, cachedDecisionProbability)
    }

    func storeDecision(source: String, chosen: String, probability: Double) {
        cachedDecisionSource = source
        cachedDecisionChosen = chosen
        cachedDecisionProbability = probability
    }

    func handlePartialUpdate(_ partial: String) {
        let trimmed = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        latestPartial = trimmed
        let now = CFAbsoluteTimeGetCurrent()

        if trimmed != lastPartialText {
            lastPartialText = trimmed
            lastPartialChangeTime = now
            return
        }

        guard !trimmed.isEmpty,
              let lastChange = lastPartialChangeTime,
              now - lastChange >= Self.stablePartialInterval else {
            return
        }

        lastStablePartial = trimmed
        let built = PasteLightCandidateBuilder.buildCandidates(
            rawTranscript: trimmed,
            vocabulary: vocabulary
        )
        latestCandidates = built
        stableCandidateCount = built.count
        os_log(.info, log: pasteLightLog, "stable partial (%d candidates): %{public}@", built.count, trimmed)
    }

    func logFinalComparison(finalTranscript: String) {
        let final = finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !final.isEmpty, final != lastStablePartial else { return }
        os_log(.info, log: pasteLightLog, "final transcript diverged from last stable partial")
    }
}
