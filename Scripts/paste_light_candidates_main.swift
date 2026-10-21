import Foundation

@main
enum PasteLightCandidatesCLI {
    static func main() {
        let input = readLine(strippingNewline: true) ?? ""
        let vocabulary = ProcessInfo.processInfo.environment["PASTE_LIGHT_VOCABULARY"] ?? ""
        let candidates = PasteLightCandidateBuilder.buildCandidates(
            rawTranscript: input,
            vocabulary: vocabulary
        )
        let payload: [String: Any] = ["candidates": candidates]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            fputs("{\"candidates\":[]}\n", stderr)
            exit(1)
        }
        print(json)
    }
}
