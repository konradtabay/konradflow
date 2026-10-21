import Foundation

enum PasteLightCandidateBuilderTests {
    static func runAll() {
        var failures = 0
        failures += testThursdaySelfCorrection()
        failures += testWasWereSwap()
        if failures > 0 {
            print("PasteLightCandidateBuilderTests: \(failures) failure(s)")
            exit(1)
        }
        print("PasteLightCandidateBuilderTests passed")
    }

    private static func testThursdaySelfCorrection() -> Int {
        let raw = "Let's meet Thursday, no actually Wednesday after lunch"
        let candidates = PasteLightCandidateBuilder.buildCandidates(rawTranscript: raw, vocabulary: "")
        let expected = "Let's meet Wednesday after lunch"
        if candidates.contains(where: { normalize($0) == normalize(expected) }) {
            return 0
        }
        print("FAIL Thursday: expected \(expected) in \(candidates)")
        return 1
    }

    private static func testWasWereSwap() -> Int {
        let raw = "they was happy"
        let candidates = PasteLightCandidateBuilder.buildCandidates(rawTranscript: raw, vocabulary: "")
        let expected = "they were happy"
        if candidates.contains(where: { normalize($0) == normalize(expected) }) {
            return 0
        }
        print("FAIL was/were: expected \(expected) in \(candidates)")
        print("candidates: \(candidates)")
        return 1
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
