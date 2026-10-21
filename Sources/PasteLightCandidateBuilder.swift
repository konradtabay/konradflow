import Foundation

struct PasteLightCandidateBuilder {
    static let maxCandidates = 20

    static func buildCandidates(rawTranscript: String, vocabulary: String) -> [String] {
        let raw = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }

        let spokenTokens = tokenize(raw)
        let spokenSet = Set(spokenTokens.map { $0.lowercased() })
        let vocabTerms = parseVocabulary(vocabulary)

        var ranked: [String] = []
        var seen = Set<String>()

        func appendUnique(_ candidate: String) {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return }
            guard isLexicallyAllowed(
                candidate: trimmed,
                spokenSet: spokenSet,
                spokenTokens: spokenTokens,
                vocabTerms: vocabTerms
            ) else { return }
            ranked.append(trimmed)
        }

        appendUnique(raw)

        let afterFillers = removeFillers(from: raw)
        appendUnique(afterFillers)

        let afterSelfCorrection = applySelfCorrection(to: raw)
        appendUnique(afterSelfCorrection)
        appendUnique(removeFillers(from: afterSelfCorrection))

        for conjugated in conjugationVariants(of: afterSelfCorrection.isEmpty ? raw : afterSelfCorrection) {
            appendUnique(conjugated)
            appendUnique(removeFillers(from: conjugated))
        }

        for punctuated in punctuationVariants(of: afterSelfCorrection.isEmpty ? afterFillers : afterSelfCorrection) {
            appendUnique(punctuated)
        }

        for vocabApplied in vocabularyVariants(
            of: afterSelfCorrection.isEmpty ? afterFillers : afterSelfCorrection,
            spokenTokens: spokenTokens,
            vocabTerms: vocabTerms
        ) {
            appendUnique(vocabApplied)
        }

        return Array(ranked.prefix(maxCandidates))
    }

    // MARK: - Fillers

    private static func removeFillers(from text: String) -> String {
        var tokens = tokenize(text)
        guard !tokens.isEmpty else { return text }

        var output: [String] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            let lower = token.lowercased()

            if lower == "um" || lower == "uh" {
                index += 1
                continue
            }

            if lower == "like", isDiscourseFillerLike(at: index, tokens: tokens) {
                index += 1
                continue
            }

            if index + 1 < tokens.count,
               tokens[index + 1].lowercased() == lower {
                output.append(token)
                index += 2
                continue
            }

            output.append(token)
            index += 1
        }

        return joinTokens(output, original: text)
    }

    private static func isDiscourseFillerLike(at index: Int, tokens: [String]) -> Bool {
        let lower = tokens[index].lowercased()
        guard lower == "like" else { return false }
        if index > 0 {
            let prev = tokens[index - 1].lowercased()
            if prev == "i" { return false }
            if prev == "would" { return false }
            if prev == "looks" || prev == "feels" || prev == "something" { return false }
        }
        return true
    }

    // MARK: - Self-correction

    private static let selfCorrectionMarkers = [
        "no actually",
        "sorry",
        "wait",
        "nu stai",
        "de fapt",
        "no perdón",
        "no perdon",
    ]

    static func applySelfCorrection(to text: String) -> String {
        for marker in selfCorrectionMarkers {
            if let range = text.range(of: marker, options: .caseInsensitive) {
                return joinCorrection(original: text, markerRange: range)
            }
        }

        if let perdónRange = text.range(of: "perdón", options: .caseInsensitive)
            ?? text.range(of: "perdon", options: .caseInsensitive) {
            let before = String(text[..<perdónRange.lowerBound])
            if before.contains(",") {
                return joinCorrection(original: text, markerRange: perdónRange)
            }
        }

        return text
    }

    private static func joinCorrection(
        original: String,
        markerRange: Range<String.Index>
    ) -> String {
        let prefix = String(original[..<markerRange.lowerBound])
        let suffix = String(original[markerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        var kept = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        while kept.hasSuffix(",") {
            kept = kept.dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var keptTokens = tokenize(kept)
        if !keptTokens.isEmpty {
            keptTokens.removeLast()
        }
        kept = joinTokens(keptTokens, original: original)

        return [kept, suffix].filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: - Conjugation

    private static func conjugationVariants(of text: String) -> [String] {
        var tokens = tokenize(text)
        guard !tokens.isEmpty else { return [] }

        var sites: [(Int, String)] = []
        for index in tokens.indices {
            let token = tokens[index]
            guard EnglishConjugation.alternates(for: token) != nil else { continue }
            if EnglishConjugation.isSubjunctiveWere(beforeIndex: index, tokens: tokens) { continue }
            let subject = EnglishConjugation.nearestSubject(beforeIndex: index, tokens: tokens)
            if let swap = EnglishConjugation.preferredAlternate(
                current: token,
                subject: subject,
                at: index,
                tokens: tokens
            ) {
                sites.append((index, swap))
            }
        }

        guard !sites.isEmpty else { return [] }

        var results: [String] = []
        for (index, swap) in sites.prefix(4) {
            var copy = tokens
            copy[index] = preserveCase(template: swap, from: copy[index])
            results.append(joinTokens(copy, original: text))
        }

        if sites.count >= 2 {
            var copy = tokens
            for (index, swap) in sites.prefix(2) {
                copy[index] = preserveCase(template: swap, from: copy[index])
            }
            results.append(joinTokens(copy, original: text))
        }

        return results
    }

    // MARK: - Punctuation

    private static func punctuationVariants(of text: String) -> [String] {
        var variants: [String] = []
        let capitalized = capitalizeSentences(in: text)
        variants.append(capitalized)
        variants.append(ensureTerminalPunctuation(capitalized))

        if !capitalized.contains(",") {
            let withComma = insertClauseComma(in: capitalized)
            if let withComma {
                variants.append(withComma)
                variants.append(ensureTerminalPunctuation(withComma))
            }
        }

        return variants
    }

    private static func capitalizeSentences(in text: String) -> String {
        var result = ""
        var capitalizeNext = true
        for character in text {
            if capitalizeNext, character.isLetter {
                result.append(String(character).uppercased())
                capitalizeNext = false
            } else {
                result.append(character)
                if character == "." || character == "!" || character == "?" {
                    capitalizeNext = true
                }
            }
        }
        if result.isEmpty, let first = text.first {
            return String(first).uppercased() + text.dropFirst()
        }
        return result.isEmpty ? text : result
    }

    private static func ensureTerminalPunctuation(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.last == "." || trimmed.last == "!" || trimmed.last == "?" {
            return trimmed
        }
        return trimmed + "."
    }

    private static func insertClauseComma(in text: String) -> String? {
        let markers = [" because ", " but ", " and then ", " so "]
        let lower = text.lowercased()
        for marker in markers {
            if let range = lower.range(of: marker) {
                let offset = text.distance(from: text.startIndex, to: range.lowerBound)
                let index = text.index(text.startIndex, offsetBy: offset + marker.count - 1)
                var copy = text
                copy.insert(",", at: index)
                return copy
            }
        }
        return nil
    }

    // MARK: - Vocabulary

    private static func parseVocabulary(_ vocabulary: String) -> [String] {
        vocabulary
            .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",")))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func vocabularyVariants(
        of text: String,
        spokenTokens: [String],
        vocabTerms: [String]
    ) -> [String] {
        guard !vocabTerms.isEmpty else { return [] }
        var tokens = tokenize(text)
        var results: [String] = []

        for (index, token) in tokens.enumerated() {
            guard let match = closestVocabularyMatch(for: token, terms: vocabTerms, spokenTokens: spokenTokens) else {
                continue
            }
            var copy = tokens
            copy[index] = match
            results.append(joinTokens(copy, original: text))
        }

        return results
    }

    private static func closestVocabularyMatch(
        for token: String,
        terms: [String],
        spokenTokens: [String]
    ) -> String? {
        let lower = token.lowercased()
        var best: (term: String, distance: Int)?
        for term in terms {
            let termLower = term.lowercased()
            if termLower == lower { continue }
            let distance = levenshtein(lower, termLower)
            let maxLen = max(lower.count, termLower.count)
            guard maxLen > 0 else { continue }
            if distance <= 2 && distance * 100 <= maxLen * 35 {
                if best == nil || distance < best!.distance {
                    best = (term, distance)
                }
            }
        }
        return best?.term
    }

    // MARK: - Lexical guard

    private static func isLexicallyAllowed(
        candidate: String,
        spokenSet: Set<String>,
        spokenTokens: [String],
        vocabTerms: [String]
    ) -> Bool {
        let candidateTokens = tokenize(candidate)
        let allowedAlternates = Set(
            spokenTokens.flatMap { EnglishConjugation.alternates(for: $0) ?? [] }.map { $0.lowercased() }
        )
        let vocabLower = Set(vocabTerms.map { $0.lowercased() })

        for token in candidateTokens {
            let lower = token.lowercased()
            if spokenSet.contains(lower) { continue }
            if allowedAlternates.contains(lower) { continue }
            if vocabLower.contains(lower) { continue }
            return false
        }
        return true
    }

    // MARK: - Token helpers

    private static func tokenize(_ text: String) -> [String] {
        let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'"))
        return text.components(separatedBy: wordCharacters.inverted)
            .filter { !$0.isEmpty }
    }

    private static func joinTokens(_ tokens: [String], original: String) -> String {
        guard !tokens.isEmpty else { return original }
        var result = tokens[0]
        for index in 1..<tokens.count {
            let prev = tokens[index - 1]
            let next = tokens[index]
            let needsSpace = !(prev.last == "," || prev.last == "." || next.first == ",")
            result += (needsSpace ? " " : "") + next
        }
        return result
    }

    private static func preserveCase(template: String, from original: String) -> String {
        if original == original.uppercased() {
            return template.uppercased()
        }
        if let first = original.first, first.isUppercase {
            return template.prefix(1).uppercased() + template.dropFirst()
        }
        return template
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current.append(min(
                    current[j - 1] + 1,
                    previous[j] + 1,
                    previous[j - 1] + cost
                ))
            }
            previous = current
        }
        return previous[b.count]
    }
}
