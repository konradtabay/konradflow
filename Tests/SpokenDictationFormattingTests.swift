import Foundation

enum SpokenDictationFormattingTests {
    static func runAll() {
        var failures = 0
        failures += expect("thanks line best", "thanks\nbest")
        failures += expect("the bottom line is we should wait", "the bottom line is we should wait")
        failures += expect("wait in line please", "wait in line please")
        failures += expect("a line of code", "a line of code")
        failures += expect("new line hello", "\nhello")
        failures += expect("bracket hello bracket", "(hello)")
        failures += expect("bracket hello world", "(hello world)")
        failures += expect("open square bracket i close square bracket", "[i]")
        failures += expect("array bracket one bracket", "array [one]")
        failures += expect("json bracket name bracket", "json {name}")
        failures += expect("call bracket foo bracket then done", "call (foo) then done")
        let twice = SpokenDictationFormatting.apply(SpokenDictationFormatting.apply("thanks line best"))
        if twice != "thanks\nbest" {
            print("FAIL idempotent: \(twice.debugDescription)")
            failures += 1
        }
        if failures > 0 {
            print("SpokenDictationFormattingTests: \(failures) failure(s)")
            exit(1)
        }
        print("SpokenDictationFormattingTests passed")
    }

    private static func expect(_ input: String, _ expected: String) -> Int {
        let actual = SpokenDictationFormatting.apply(input)
        if actual == expected {
            return 0
        }
        print("FAIL \(input.debugDescription)")
        print("  expected \(expected.debugDescription)")
        print("  actual   \(actual.debugDescription)")
        return 1
    }
}
