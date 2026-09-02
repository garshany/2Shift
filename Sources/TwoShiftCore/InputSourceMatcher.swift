import Foundation

/// AppKit/Carbon-free description of an enabled keyboard input source.
/// The app layer builds these from Text Input Sources (TIS) so that the
/// picking rules stay pure and checkable in TwoShiftCoreCheck.
public struct InputSourceCandidate: Sendable, Equatable {
    public let identifier: String
    public let languages: [String]
    public let isASCIICapable: Bool

    public init(identifier: String, languages: [String], isASCIICapable: Bool) {
        self.identifier = identifier
        self.languages = languages
        self.isASCIICapable = isASCIICapable
    }

    /// Language tag of the source's primary language, without a region suffix
    /// ("ru-RU" -> "ru").
    public var primaryLanguage: String? {
        languages.first.map(InputSourceMatcher.baseLanguage)
    }

    public func supports(language: String) -> Bool {
        languages.contains { InputSourceMatcher.baseLanguage($0) == language }
    }
}

public enum InputSourceMatcher {
    public static let englishLanguage = "en"
    public static let russianLanguage = "ru"

    /// Identifiers preferred when several enabled sources speak the same
    /// language (e.g. "Russian" over "Russian - Phonetic").
    private static let preferredIdentifiers: Set<String> = [
        "com.apple.keylayout.Russian",
        "com.apple.keylayout.ABC",
        "com.apple.keylayout.US"
    ]

    public static func baseLanguage(_ tag: String) -> String {
        guard let separator = tag.firstIndex(where: { $0 == "-" || $0 == "_" }) else {
            return tag.lowercased()
        }
        return String(tag[tag.startIndex..<separator]).lowercased()
    }

    /// Language the text ends up in after a conversion in this direction.
    public static func resultLanguage(for direction: ConversionDirection) -> String {
        direction == .englishToRussian ? russianLanguage : englishLanguage
    }

    /// Best enabled source for `language`, or nil when none is installed.
    /// `current` is returned as nil (nothing to switch to).
    public static func source(
        for language: String,
        in candidates: [InputSourceCandidate],
        current: InputSourceCandidate?
    ) -> InputSourceCandidate? {
        guard let match = bestMatch(for: baseLanguage(language), in: candidates) else {
            return nil
        }
        return match.identifier == current?.identifier ? nil : match
    }

    /// Target for a plain layout toggle: the other of EN/RU when the current
    /// source is one of them, otherwise the next enabled source in order.
    public static func toggleTarget(
        in candidates: [InputSourceCandidate],
        current: InputSourceCandidate?
    ) -> InputSourceCandidate? {
        let wantedLanguage = current?.primaryLanguage == russianLanguage ? englishLanguage : russianLanguage
        if let match = bestMatch(for: wantedLanguage, in: candidates), match.identifier != current?.identifier {
            return match
        }

        guard candidates.count > 1 else {
            return nil
        }
        guard
            let current,
            let index = candidates.firstIndex(where: { $0.identifier == current.identifier })
        else {
            return candidates.first
        }
        return candidates[(index + 1) % candidates.count]
    }

    private static func bestMatch(for language: String, in candidates: [InputSourceCandidate]) -> InputSourceCandidate? {
        let primary = candidates.filter { $0.primaryLanguage == language }
        let pool = primary.isEmpty ? candidates.filter { $0.supports(language: language) } : primary
        guard !pool.isEmpty else {
            return nil
        }

        if let preferred = pool.first(where: { preferredIdentifiers.contains($0.identifier) }) {
            return preferred
        }
        if language == englishLanguage, let ascii = pool.first(where: { $0.isASCIICapable }) {
            return ascii
        }
        return pool.first
    }
}
