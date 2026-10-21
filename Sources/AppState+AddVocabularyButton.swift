import AppKit

// MARK: - Add Vocabulary Button Extension

@MainActor
extension AppState {
    /// Pastes a word (or words) from the macOS pasteboard into the user's custom vocabulary.
    /// Returns the pasted text if successful, or nil otherwise.
    @discardableResult
    func pasteWordToVocabulary() -> String? {
        guard let pastedString = NSPasteboard.general.string(forType: .string),
              !pastedString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let wordsToAdd = pastedString
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return addTermsToCustomVocabulary(wordsToAdd)
    }

    @discardableResult
    func addTermsToCustomVocabulary(_ wordsToAdd: [String]) -> String? {
        let cleanedWords = wordsToAdd
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleanedWords.isEmpty else { return nil }

        let currentWordsList = self.customVocabulary
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let currentWordsSet = Set(currentWordsList.map { $0.lowercased() })
        let newUniqueWords = cleanedWords.filter { !currentWordsSet.contains($0.lowercased()) }

        guard !newUniqueWords.isEmpty else { return nil }

        let newWordsString = newUniqueWords.joined(separator: ", ")
        var currentVocab = self.customVocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentVocab.isEmpty {
            if !currentVocab.hasSuffix(",") {
                currentVocab += ","
            }
            currentVocab += "\n\(newWordsString)"
        } else {
            currentVocab = newWordsString
        }

        self.customVocabulary = currentVocab
        return newWordsString
    }
}

