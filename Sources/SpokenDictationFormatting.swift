import Foundation

/// Turns spoken formatting commands into characters.
///
/// "line" becomes a line break when it is used as a command, and stays a word
/// in phrases like "the bottom line" or "a line of". "bracket" opens a pair
/// and closes it around the following words, using (), [], or {} from the
/// words around it.
enum SpokenDictationFormatting {
    static func apply(_ text: String) -> String {
        let withPhrases = replacePhrases(in: text)
        let withBrackets = replaceBracketCommands(in: withPhrases)
        let withLines = replaceLineCommands(in: withBrackets)
        return cleanupSpacing(withLines)
    }

    // MARK: - Phrases

    private static let phrases: [(pattern: String, replacement: String)] = [
        (#"\bnew\s+line\b"#, "\n"),
        (#"\bnext\s+line\b"#, "\n"),
        (#"\bline\s+break\b"#, "\n"),
        (#"\bopen\s+square\s+bracket\b"#, "["),
        (#"\bleft\s+square\s+bracket\b"#, "["),
        (#"\bclose\s+square\s+bracket\b"#, "]"),
        (#"\bright\s+square\s+bracket\b"#, "]"),
        (#"\bopen\s+curly\s+bracket\b"#, "{"),
        (#"\bleft\s+curly\s+bracket\b"#, "{"),
        (#"\bclose\s+curly\s+bracket\b"#, "}"),
        (#"\bright\s+curly\s+bracket\b"#, "}"),
        (#"\bopen\s+bracket\b"#, "("),
        (#"\bleft\s+bracket\b"#, "("),
        (#"\bclose\s+bracket\b"#, ")"),
        (#"\bright\s+bracket\b"#, ")"),
    ]

    private static func replacePhrases(in text: String) -> String {
        var result = text
        for phrase in phrases {
            guard let expression = try? NSRegularExpression(
                pattern: phrase.pattern,
                options: [.caseInsensitive]
            ) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: phrase.replacement
            )
        }
        return result
    }

    // MARK: - Bracket

    private struct Piece {
        var text: String
        var isWord: Bool
    }

    private static func replaceBracketCommands(in text: String) -> String {
        var pieces = pieces(of: text)
        var index = 0
        while index < pieces.count {
            guard pieces[index].isWord, pieces[index].text.lowercased() == "bracket" else {
                index += 1
                continue
            }

            let pair = bracketPair(lookingBackFrom: index, pieces: pieces)
            if let closer = nextBracketIndex(after: index, pieces: pieces) {
                pieces[index].text = pair.open
                pieces[index].isWord = false
                pieces[closer].text = pair.close
                pieces[closer].isWord = false
                index = closer + 1
                continue
            }

            let end = followingPhraseEnd(after: index, pieces: pieces)
            pieces[index].text = pair.open
            pieces[index].isWord = false
            pieces.insert(Piece(text: pair.close, isWord: false), at: end)
            index = end + 1
        }
        return pieces.map(\.text).joined()
    }

    private static func nextBracketIndex(after start: Int, pieces: [Piece]) -> Int? {
        var index = start + 1
        while index < pieces.count {
            let piece = pieces[index]
            if piece.text.contains("\n") || isSentenceEnd(piece) {
                return nil
            }
            if piece.isWord, piece.text.lowercased() == "bracket" {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func followingPhraseEnd(after start: Int, pieces: [Piece]) -> Int {
        var index = start + 1
        var sawWord = false
        while index < pieces.count {
            let piece = pieces[index]
            if piece.text.contains("\n") || isSentenceEnd(piece) {
                return index
            }
            if piece.isWord {
                sawWord = true
            }
            index += 1
        }
        if !sawWord {
            return start + 1
        }
        return pieces.count
    }

    private static func bracketPair(lookingBackFrom index: Int, pieces: [Piece]) -> (open: String, close: String) {
        var words: [String] = []
        var cursor = index - 1
        while cursor >= 0, words.count < 6 {
            let piece = pieces[cursor]
            if piece.text.contains("\n") || isSentenceEnd(piece) {
                break
            }
            if piece.isWord {
                words.append(piece.text.lowercased())
            }
            cursor -= 1
        }

        if words.contains(where: { ["square", "array", "index", "indexes", "indices"].contains($0) }) {
            return ("[", "]")
        }
        if words.contains(where: { ["curly", "brace", "braces", "json", "object", "dict", "dictionary"].contains($0) }) {
            return ("{", "}")
        }
        return ("(", ")")
    }

    private static func isSentenceEnd(_ piece: Piece) -> Bool {
        piece.text == "." || piece.text == "?" || piece.text == "!"
    }

    // MARK: - Line

    private static let lineKeptAfter: Set<String> = [
        "a", "an", "the", "this", "that", "these", "those",
        "my", "your", "our", "their", "his", "her", "its",
        "one", "first", "last", "next", "every", "each",
        "finish", "bottom", "top", "straight", "assembly", "product", "production",
        "phone", "party", "subject", "punch", "base", "front", "back", "side",
        "waiting", "long", "short", "fine", "horizontal", "vertical", "dotted", "solid",
        "single", "double", "same", "whole", "main", "starting", "goal",
        "by", "in", "on", "off", "out", "of", "per", "along",
        "command", "story", "plot", "pickup", "pipe", "power", "property",
        "border", "above", "below", "under", "over",
    ]

    private static let lineKeptBefore: Set<String> = [
        "of", "up", "item", "items", "number", "numbers", "manager", "cook",
        "drawing", "segment", "segments", "art", "dance", "judge",
    ]

    private static func replaceLineCommands(in text: String) -> String {
        var pieces = pieces(of: text)
        for index in pieces.indices {
            guard pieces[index].isWord, pieces[index].text.lowercased() == "line" else { continue }
            if let previous = previousWord(before: index, pieces: pieces), lineKeptAfter.contains(previous) {
                continue
            }
            if let next = nextWord(after: index, pieces: pieces), lineKeptBefore.contains(next) {
                continue
            }
            pieces[index].text = "\n"
            pieces[index].isWord = false
        }
        return pieces.map(\.text).joined()
    }

    private static func previousWord(before index: Int, pieces: [Piece]) -> String? {
        var cursor = index - 1
        while cursor >= 0 {
            if pieces[cursor].text.contains("\n") { return nil }
            if pieces[cursor].isWord { return pieces[cursor].text.lowercased() }
            cursor -= 1
        }
        return nil
    }

    private static func nextWord(after index: Int, pieces: [Piece]) -> String? {
        var cursor = index + 1
        while cursor < pieces.count {
            if pieces[cursor].text.contains("\n") { return nil }
            if pieces[cursor].isWord { return pieces[cursor].text.lowercased() }
            cursor += 1
        }
        return nil
    }

    // MARK: - Spacing

    private static func pieces(of text: String) -> [Piece] {
        var pieces: [Piece] = []
        var word = ""

        func flushWord() {
            guard !word.isEmpty else { return }
            pieces.append(Piece(text: word, isWord: true))
            word = ""
        }

        for character in text {
            if character.isLetter || character == "'" || character == "’" {
                word.append(character)
            } else {
                flushWord()
                if var last = pieces.last, !last.isWord, last.text.allSatisfy(\.isWhitespace), character.isWhitespace {
                    last.text.append(character)
                    pieces[pieces.count - 1] = last
                } else {
                    pieces.append(Piece(text: String(character), isWord: false))
                }
            }
        }
        flushWord()
        return pieces
    }

    private static func cleanupSpacing(_ text: String) -> String {
        var result = text
        let patterns: [(String, String)] = [
            (#"\(\s+"#, "("),
            (#"\s+\)"#, ")"),
            (#"\[\s+"#, "["),
            (#"\s+\]"#, "]"),
            (#"\{\s+"#, "{"),
            (#"\s+\}"#, "}"),
            (#"[ \t]*\n[ \t]*"#, "\n"),
            (#"[ \t]{2,}"#, " "),
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern.0) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = expression.stringByReplacingMatches(in: result, range: range, withTemplate: pattern.1)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
