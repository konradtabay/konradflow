import Foundation

enum LatencyBenchmarkTests {
    static func runAll() {
        testShortcutReleaseSchedulerSkipsPollWhenAlreadyReleased()
        testShortcutReleaseSchedulerPollsWhileKeysHeld()
        testRealtimeWebSocketURLDerivation()
        testLatencyBenchmarkStats()
        testTranscriptionResponseFormat()
        print("LatencyBenchmarkTests passed")
    }

    private static func testShortcutReleaseSchedulerSkipsPollWhenAlreadyReleased() {
        let step = ShortcutReleaseScheduler.step(
            hasPressedShortcutInputs: false,
            attempt: 0,
            shortcutAlreadyReleased: true
        )
        expect(!step.shouldPoll, "Expected no polling when shortcut already released")
        expect(step.pasteDelay == ShortcutReleaseScheduler.pasteDelayAfterRelease, "Expected tuned paste delay")
    }

    private static func testShortcutReleaseSchedulerPollsWhileKeysHeld() {
        let step = ShortcutReleaseScheduler.step(
            hasPressedShortcutInputs: true,
            attempt: 0,
            shortcutAlreadyReleased: false
        )
        expect(step.shouldPoll, "Expected polling while shortcut inputs remain pressed")
        expect(step.pasteDelay == 0, "Expected zero paste delay while polling")
    }

    private static func testRealtimeWebSocketURLDerivation() {
        let url = RealtimeTranscriptionService.deriveWebSocketURL(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-realtime-whisper",
            language: "en"
        )
        expect(url?.scheme == "wss", "Expected wss scheme")
        expect(url?.path == "/v1/realtime", "Expected /v1/realtime path")
        expect(url?.query?.contains("intent=transcription") == true, "Expected transcription intent query")
    }

    private static func testLatencyBenchmarkStats() {
        let summary = LatencyBenchmarkStats.summarize(values: [10, 20, 30, 40, 50])
        expect(summary["p50"] == 30, "Expected p50 of 30")
        expect(summary["count"] == 5, "Expected count of 5")
    }

    private static func testTranscriptionResponseFormat() {
        expect(
            TranscriptionService.responseFormat(forModel: "whisper-large-v3") == "verbose_json",
            "Whisper models should use verbose_json"
        )
        expect(
            TranscriptionService.responseFormat(forModel: "gpt-4o-transcribe") == "json",
            "Non-whisper models should use json"
        )
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            fatalError(message)
        }
    }
}
