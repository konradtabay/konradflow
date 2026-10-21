import Foundation

final class VocabularyLearningMonitor {
    static let shared = VocabularyLearningMonitor()

    private var pollTimer: Timer?
    private var endTask: Task<Void, Never>?
    private var pastedTokens: Set<String> = []
    private var lastObservedFieldValue: String?
    private var learnedThisSession: Set<String> = []
    private var contextService: AppContextService?
    private var onLearn: ((String) -> Void)?
    private var onSubstantiveFieldRewrite: (() -> Void)?

    private let pollInterval: TimeInterval = 0.35
    private let sessionDuration: TimeInterval = 20
    private let maxTermsPerSession = 3

    private init() {}

    func beginSession(
        pastedText: String,
        contextService: AppContextService,
        onSubstantiveFieldRewrite: (() -> Void)? = nil,
        onLearn: @escaping (String) -> Void
    ) {
        endSession()

        let trimmed = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        self.contextService = contextService
        self.onLearn = onLearn
        self.onSubstantiveFieldRewrite = onSubstantiveFieldRewrite
        pastedTokens = Set(Self.tokenize(trimmed).map { $0.lowercased() })
        lastObservedFieldValue = trimmed
        learnedThisSession = []

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.poll()
            }
        }

        endTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(sessionDuration * 1_000_000_000))
            await MainActor.run {
                self.endSession()
            }
        }
    }

    func endSession() {
        pollTimer?.invalidate()
        pollTimer = nil
        endTask?.cancel()
        endTask = nil
        contextService = nil
        onLearn = nil
        onSubstantiveFieldRewrite = nil
        pastedTokens = []
        lastObservedFieldValue = nil
        learnedThisSession = []
    }

    private func poll() {
        guard let contextService, learnedThisSession.count < maxTermsPerSession else { return }

        let snapshot = contextService.collectSelectionSnapshot()
        if let selectedText = snapshot.selectedText {
            evaluateSelection(selectedText)
        }

        if let fieldValue = contextService.focusedFieldText() {
            evaluateFieldEdit(fieldValue)
        }
    }

    private func evaluateSelection(_ selectedText: String) {
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let terms = Self.tokenize(trimmed)
        guard terms.count == 1, let term = terms.first else { return }
        learn(term)
    }

    private func evaluateFieldEdit(_ fieldValue: String) {
        guard fieldValue != lastObservedFieldValue else { return }
        lastObservedFieldValue = fieldValue

        let editedTokens = Self.tokenize(fieldValue)
        guard !editedTokens.isEmpty else { return }

        let editedTokenSet = Set(editedTokens.map { $0.lowercased() })
        let overlap = pastedTokens.intersection(editedTokenSet)
        guard !pastedTokens.isEmpty else { return }
        guard Double(overlap.count) >= Double(pastedTokens.count) * 0.6 else { return }

        var newTerms: [String] = []
        for term in editedTokens where !pastedTokens.contains(term.lowercased()) {
            newTerms.append(term)
            learn(term)
            if learnedThisSession.count >= maxTermsPerSession { break }
        }

        if newTerms.count > 1 {
            onSubstantiveFieldRewrite?()
        } else if newTerms.count == 1, editedTokens.count > pastedTokens.count + 1 {
            onSubstantiveFieldRewrite?()
        }
    }

    private func learn(_ term: String) {
        guard Self.isValidVocabularyTerm(term) else { return }

        let normalized = term.lowercased()
        guard !pastedTokens.contains(normalized) else { return }
        guard !learnedThisSession.contains(normalized) else { return }

        learnedThisSession.insert(normalized)
        onLearn?(term)
    }

    private static func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func isValidVocabularyTerm(_ term: String) -> Bool {
        guard term.count >= 2, term.count <= 48 else { return false }
        return term.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }
}
