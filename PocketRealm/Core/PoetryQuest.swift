import Foundation

/// A small spoken quest: Nibbi supplies A/B starters, the player completes each couplet.
struct PoetryQuest: Codable, Equatable {
    private(set) var lines: [String] = []
    var complete: Bool { lines.count == 2 }
    var pair: Int { min(lines.count, 1) }
    var target: String { pair == 0 ? "night" : "day" }
    var starter: String { pair == 0 ? Self.first : Self.third }
    static let first = "I tucked a sugar star into the night."
    static let third = "I saved a little cookie for the day."
    var hint: String { pair == 0 ? "Try ending with light, bright, or white." : "Try ending with play, stay, or away." }
    var context: String {
        if complete { return "Poem complete. Sugar-star Poet badge earned. \(Self.first) \(lines[0]) \(Self.third) \(lines[1])" }
        return "Current pair_index: \(pair). Nibbi's starter: \(starter) Player must supply a new line rhyming with \(target). \(hint) Accepted player lines: \(lines.joined(separator: " / "))"
    }
    var opening: String {
        complete ? "Our poem is finished. Want to read it together?" :
        "Let's make a little poem. I'll give you a line, and you give me one that rhymes. \(starter) What comes next?"
    }
    static func words(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    }
    /// Never accepts a model-invented line, a duplicate tool call, or the wrong couplet.
    mutating func submit(_ line: String, pairIndex: Int, heard: String) -> String {
        guard !complete else { return "Already complete. Do not award again. " + context }
        guard pairIndex == pair else { return "That pair is not the current turn. " + context }
        let words = Self.words(line)
        guard words.count >= 3, line.count <= 240 else { return "Try a short line of at least three words. " + hint }
        guard Self.words(heard).joined(separator: " ").contains(words.joined(separator: " ")) else {
            return "I didn't catch that exact line. Ask the player to say it again. No progress awarded."
        }
        guard let ending = words.last, ending != target else { return "Use a different ending word that rhymes with \(target). " + hint }
        let rhymes = pair == 0 ? RhymeWords.night : RhymeWords.day
        guard rhymes.contains(ending) else {
            return "I couldn't match that ending to \(target). No progress lost. " + hint
        }
        lines.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
        return complete ? "Accepted. Poem complete; Sugar-star Poet badge earned. " + context : "Accepted. First couplet complete. Now read the next starter and ask for the B line. " + context
    }
}
