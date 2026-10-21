import Foundation

enum EnglishConjugation {
    /// Closed alternates for local conjugation swaps (same tense family only).
    static let alternateGroups: [[String]] = [
        ["was", "were"],
        ["am", "is", "are"],
        ["go", "goes", "going", "went"],
        ["do", "does"],
        ["don't", "doesn't"],
        ["i", "me"],
    ]

    static func alternates(for word: String) -> [String]? {
        let lower = word.lowercased()
        for group in alternateGroups {
            if group.contains(lower) {
                return group
            }
        }
        return nil
    }

    static func isSubjunctiveWere(beforeIndex: Int, tokens: [String]) -> Bool {
        guard beforeIndex >= 2 else { return false }
        let prev = tokens[beforeIndex - 1].lowercased()
        let prev2 = tokens[beforeIndex - 2].lowercased()
        return prev == "i" && prev2 == "if"
    }

    static func nearestSubject(beforeIndex: Int, tokens: [String]) -> String? {
        let subjects = ["i", "you", "he", "she", "it", "we", "they", "who", "whoever"]
        for index in stride(from: beforeIndex - 1, through: 0, by: -1) {
            let token = tokens[index].lowercased()
            if subjects.contains(token) {
                return token
            }
        }
        return nil
    }

    static func preferredAlternate(
        current: String,
        subject: String?,
        at index: Int,
        tokens: [String]
    ) -> String? {
        let lower = current.lowercased()
        guard let group = alternates(for: lower) else { return nil }
        if lower == "were", isSubjunctiveWere(beforeIndex: index, tokens: tokens) {
            return nil
        }

        switch lower {
        case "was", "were":
            switch subject {
            case "we", "they":
                return lower == "was" ? "were" : nil
            case "i", "he", "she", "it":
                return lower == "were" ? "was" : nil
            default:
                return lower == "was" ? "were" : "was"
            }
        case "am", "is", "are":
            switch subject {
            case "i":
                return lower == "is" || lower == "are" ? "am" : nil
            case "he", "she", "it":
                return lower == "am" || lower == "are" ? "is" : nil
            case "we", "they", "you":
                return lower == "am" || lower == "is" ? "are" : nil
            default:
                return nil
            }
        case "go", "goes":
            switch subject {
            case "he", "she", "it":
                return lower == "go" ? "goes" : nil
            default:
                return lower == "goes" ? "go" : nil
            }
        case "do", "does":
            switch subject {
            case "he", "she", "it":
                return lower == "do" ? "does" : nil
            default:
                return lower == "does" ? "do" : nil
            }
        case "don't", "doesn't":
            switch subject {
            case "he", "she", "it":
                return lower == "don't" ? "doesn't" : nil
            default:
                return lower == "doesn't" ? "don't" : nil
            }
        case "i", "me":
            return lower == "i" ? "me" : "I"
        default:
            return group.first(where: { $0.lowercased() != lower })
        }
    }
}
