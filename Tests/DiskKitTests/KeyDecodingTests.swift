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

/// Escape is both a key and the first byte of every arrow key and mouse report.
@Suite("Escape sequences")
struct EscapeSequenceTests {

    /// Bytes a terminal sends for the keys the browser understands.
    @Test("arrow keys and mouse reports begin with the same byte as Escape")
    func sequencesShareTheirFirstByte() {
        let escape: [UInt8] = [0x1B]
        let arrowDown: [UInt8] = Array("\u{1B}[B".utf8)
        let wheelDown: [UInt8] = Array("\u{1B}[<65;20;10M".utf8)

        #expect(escape.first == arrowDown.first)
        #expect(escape.first == wheelDown.first)

        // Nothing in the stream says which one it is, so telling them apart
        // means waiting briefly and seeing whether more arrives.
        #expect(escape.count == 1)
        #expect(arrowDown.count > 1)
    }

    @Test("a mouse report ends at its final letter")
    func mouseReportIsSelfDelimiting() {
        let report = Array("\u{1B}[<65;20;10M".utf8)

        // Everything up to M or m belongs to the report; leaving the rest in
        // the stream turns one scroll into a burst of stray keys.
        #expect(report.last == UInt8(ascii: "M"))
        #expect(report.dropLast().allSatisfy { $0 != UInt8(ascii: "M") })
    }

    @Test("a CSI sequence ends in the range 0x40...0x7E", arguments: [
        "\u{1B}[A", "\u{1B}[B", "\u{1B}[5~", "\u{1B}[<65;20;10M", "\u{1B}[200~",
    ])
    func sequencesEndInTheFinalByteRange(_ sequence: String) {
        let final = Array(sequence.utf8).last!
        #expect((0x40 ... 0x7E).contains(final))
    }
}
