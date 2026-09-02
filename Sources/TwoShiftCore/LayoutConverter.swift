import Foundation

public enum ConversionDirection: Sendable, Equatable {
    case englishToRussian
    case russianToEnglish
}

public struct LayoutConverter: Sendable {
    private let englishToRussian: [Character: Character]
    private let russianToEnglish: [Character: Character]
    private let latinScoreCharacters: Set<Character>
    private let cyrillicScoreCharacters: Set<Character>

    public init() {
        let pairs: [(Character, Character)] = [
            ("`", "ё"), ("~", "Ё"),
            ("q", "й"), ("w", "ц"), ("e", "у"), ("r", "к"), ("t", "е"),
            ("y", "н"), ("u", "г"), ("i", "ш"), ("o", "щ"), ("p", "з"),
            ("[", "х"), ("]", "ъ"),
            ("a", "ф"), ("s", "ы"), ("d", "в"), ("f", "а"), ("g", "п"),
            ("h", "р"), ("j", "о"), ("k", "л"), ("l", "д"), (";", "ж"),
            ("'", "э"),
            ("z", "я"), ("x", "ч"), ("c", "с"), ("v", "м"), ("b", "и"),
            ("n", "т"), ("m", "ь"), (",", "б"), (".", "ю"),
            ("Q", "Й"), ("W", "Ц"), ("E", "У"), ("R", "К"), ("T", "Е"),
            ("Y", "Н"), ("U", "Г"), ("I", "Ш"), ("O", "Щ"), ("P", "З"),
            ("{", "Х"), ("}", "Ъ"),
            ("A", "Ф"), ("S", "Ы"), ("D", "В"), ("F", "А"), ("G", "П"),
            ("H", "Р"), ("J", "О"), ("K", "Л"), ("L", "Д"), (":", "Ж"),
            ("\"", "Э"),
            ("Z", "Я"), ("X", "Ч"), ("C", "С"), ("V", "М"), ("B", "И"),
            ("N", "Т"), ("M", "Ь"), ("<", "Б"), (">", "Ю"),
            ("!", "!"), ("@", "\""), ("#", "№"), ("$", "%"), ("%", ":"),
            ("^", ","), ("&", "."), ("*", ";"), ("(", "("), (")", ")"),
            ("_", "_"), ("+", "+"), ("/", "/"), ("?", "?")
        ]

        var enRu: [Character: Character] = [:]
        var ruEn: [Character: Character] = [:]
        for (english, russian) in pairs {
            enRu[english] = russian
            ruEn[russian] = english
        }

        self.englishToRussian = enRu
        self.russianToEnglish = ruEn
        self.latinScoreCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ@#$%^&*")
        self.cyrillicScoreCharacters = Set("абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ№")
    }

    public func converted(_ text: String, direction explicitDirection: ConversionDirection? = nil) -> String {
        guard let direction = explicitDirection ?? detectedDirection(for: text) else {
            return text
        }

        let mapping = direction == .englishToRussian ? englishToRussian : russianToEnglish
        return String(text.map { mapping[$0] ?? $0 })
    }

    public func detectedDirection(for text: String) -> ConversionDirection? {
        var latinScore = 0
        var cyrillicScore = 0

        for character in text {
            if latinScoreCharacters.contains(character) {
                latinScore += 1
            } else if cyrillicScoreCharacters.contains(character) {
                cyrillicScore += 1
            }
        }

        if latinScore == 0 && cyrillicScore == 0 {
            return nil
        }

        return latinScore >= cyrillicScore ? .englishToRussian : .russianToEnglish
    }
}
