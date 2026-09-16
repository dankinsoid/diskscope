import Foundation
import Testing

/// Decoding a keystroke from the byte stream a terminal delivers.
///
/// The logic lives in the CLI target, so this mirrors it against the rule it
/// has to satisfy: one keypress must yield exactly one key, whatever alphabet
/// it was typed in.
@Suite("UTF-8 key decoding")
struct KeyDecodingTests {

    /// Number of bytes a UTF-8 sequence occupies, from its leading byte.
    private func sequenceLength(_ first: UInt8) -> Int {
        switch first {
        case 0x00 ... 0x7F: 1
        case 0xC0 ... 0xDF: 2
        case 0xE0 ... 0xEF: 3
        case 0xF0 ... 0xF7: 4
        default: 1
        }
    }

    /// Splits a byte stream the way the terminal reader does.
    private func decode(_ text: String) -> [Character] {
        var bytes = Array(text.utf8)[...]
        var characters: [Character] = []

        while let first = bytes.first {
            bytes = bytes.dropFirst()
            var sequence = [first]
            let expected = sequenceLength(first)

            while sequence.count < expected, let next = bytes.first,
                  next & 0b1100_0000 == 0b1000_0000 {
                sequence.append(next)
                bytes = bytes.dropFirst()
            }
            if let character = String(bytes: sequence, encoding: .utf8)?.first {
                characters.append(character)
            }
        }
        return characters
    }

    @Test("one keypress yields one key, in any alphabet", arguments: [
        "build", "Документы", "café", "日本語", "naïve",
    ])
    func decodesOneKeyPerCharacter(_ text: String) {
        #expect(decode(text) == Array(text))
    }

    @Test("a Cyrillic letter is one key, not two")
    func cyrillicIsSingleKey() {
        // Read a byte at a time, "б" becomes 0xD0 0xB1 — two keystrokes, either
        // of which could land on a command such as quit.
        #expect("б".utf8.count == 2)
        #expect(decode("б") == ["б"])
        #expect(decode("привет").count == 6)
    }

    @Test("emoji outside the basic planes survive")
    func decodesFourByteSequences() {
        #expect("📁".utf8.count == 4)
        #expect(decode("📁") == ["📁"])
    }

    @Test("mixed scripts keep their order")
    func decodesMixedText() {
        #expect(decode("a—б") == ["a", "—", "б"])
    }
}
