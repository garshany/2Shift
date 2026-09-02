import TwoShiftCore

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

let converter = LayoutConverter()

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    guard actual == expected else {
        throw CheckFailure(description: "\(message): expected \(expected), got \(actual)")
    }
}

try expectEqual(converter.converted("ghbdtn"), "привет", "english mistype")
try expectEqual(converter.converted("Ghbdtn"), "Привет", "capitalized english mistype")
try expectEqual(converter.converted("GHBDTN"), "ПРИВЕТ", "uppercase english mistype")
try expectEqual(converter.converted("руддщ"), "hello", "russian mistype")
try expectEqual(converter.converted("Руддщ"), "Hello", "capitalized russian mistype")
try expectEqual(converter.converted("Ghbdtn^ vbh& Rfr ltkf? Lf!"), "Привет, мир. Как дела? Да!", "macOS Russian punctuation keys")
try expectEqual(converter.converted("Руддщб цщкдвю Црн? Нуы!"), "Hello, world. Why? Yes!", "reverse macOS Russian punctuation keys")
try expectEqual(converter.converted("^&@#%*"), ",.\"№:;", "punctuation-only english side")
try expectEqual(converter.converted("№"), "#", "punctuation-only russian side")
try expectEqual(converter.converted("123 😊"), "123 😊", "unsupported characters")
try expectEqual(converter.detectedDirection(for: "hello мир"), .englishToRussian, "mixed latin majority direction")
try expectEqual(converter.detectedDirection(for: "hi привет"), .russianToEnglish, "mixed cyrillic majority direction")
try expectEqual(converter.detectedDirection(for: "^&"), .englishToRussian, "punctuation-only english direction")

let defaultShortcut = ShortcutSpec.defaultShortcut
try expectEqual(defaultShortcut.keyCode, 49, "default shortcut key is Space")
try expectEqual(defaultShortcut.displayString, "⇧⌘Space", "default shortcut display")
try expectEqual(defaultShortcut.matches(keyCode: 49, activeModifiers: [.command, .shift]), true, "default shortcut matches exact modifiers")
try expectEqual(defaultShortcut.matches(keyCode: 49, activeModifiers: [.command, .shift, .option]), false, "extra modifier must not match")
try expectEqual(defaultShortcut.matches(keyCode: 49, activeModifiers: [.command]), false, "missing modifier must not match")
try expectEqual(defaultShortcut.matches(keyCode: 48, activeModifiers: [.command, .shift]), false, "different key must not match")

try expectEqual(ShortcutSpec(keyCode: 97, modifiers: []).isSafeGlobalShortcut, true, "bare function key is a safe shortcut")
try expectEqual(ShortcutSpec(keyCode: 0, modifiers: [.shift]).isSafeGlobalShortcut, false, "shift+letter is not a safe shortcut")
try expectEqual(ShortcutSpec(keyCode: 0, modifiers: [.control]).isSafeGlobalShortcut, true, "control+letter is a safe shortcut")

try expectEqual(ShortcutSpec.sanitized(keyCode: 49, modifiersRawValue: Int(ShortcutModifiers([.command, .shift]).rawValue)), defaultShortcut, "sanitized round-trip of default shortcut")
try expectEqual(ShortcutSpec.sanitized(keyCode: 999, modifiersRawValue: 3), nil, "out-of-range key code is rejected")
try expectEqual(ShortcutSpec.sanitized(keyCode: -1, modifiersRawValue: 3), nil, "negative key code is rejected")
try expectEqual(ShortcutSpec.sanitized(keyCode: 0, modifiersRawValue: 0), nil, "typing key without modifiers is rejected")
try expectEqual(ShortcutSpec.sanitized(keyCode: 49, modifiersRawValue: Int(UInt8.max) + 5), nil, "overflowing modifier bits are rejected")

try expectEqual(ShortcutSpec(keyCode: 3, modifiers: [.control, .option, .shift, .command]).displayString, "⌃⌥⇧⌘F", "modifier symbol order")
try expectEqual(ShortcutSpec.keyName(for: 111), "F12", "function key name")
try expectEqual(ShortcutSpec.keyName(for: 90), "key 90", "unknown key fallback name")

let russian = InputSourceCandidate(identifier: "com.apple.keylayout.Russian", languages: ["ru"], isASCIICapable: false)
let russianPC = InputSourceCandidate(identifier: "com.apple.keylayout.RussianWin", languages: ["ru"], isASCIICapable: false)
let abc = InputSourceCandidate(identifier: "com.apple.keylayout.ABC", languages: ["en"], isASCIICapable: true)
let dvorak = InputSourceCandidate(identifier: "com.apple.keylayout.Dvorak", languages: ["en-US"], isASCIICapable: true)
let german = InputSourceCandidate(identifier: "com.apple.keylayout.German", languages: ["de"], isASCIICapable: true)
let installed = [dvorak, russianPC, russian, abc, german]

try expectEqual(InputSourceMatcher.baseLanguage("en-US"), "en", "base language strips region")
try expectEqual(InputSourceMatcher.resultLanguage(for: .englishToRussian), "ru", "en->ru result is russian")
try expectEqual(InputSourceMatcher.resultLanguage(for: .russianToEnglish), "en", "ru->en result is english")
try expectEqual(dvorak.primaryLanguage, "en", "primary language of a regional tag")
try expectEqual(german.supports(language: "ru"), false, "german does not support russian")

try expectEqual(InputSourceMatcher.source(for: "ru", in: installed, current: abc), russian, "standard russian layout wins over alternatives")
try expectEqual(InputSourceMatcher.source(for: "en", in: installed, current: russian), abc, "standard ABC layout wins over dvorak")
try expectEqual(InputSourceMatcher.source(for: "en", in: [dvorak, german], current: german), dvorak, "falls back to the only english layout")
try expectEqual(InputSourceMatcher.source(for: "ru", in: installed, current: russian), nil, "already active language is not re-selected")
try expectEqual(InputSourceMatcher.source(for: "ru", in: [abc, german], current: abc), nil, "missing language yields no target")

try expectEqual(InputSourceMatcher.toggleTarget(in: installed, current: russian), abc, "toggle from russian goes to english")
try expectEqual(InputSourceMatcher.toggleTarget(in: installed, current: abc), russian, "toggle from english goes to russian")
try expectEqual(InputSourceMatcher.toggleTarget(in: [abc, german], current: abc), german, "without russian the toggle cycles to the next source")
try expectEqual(InputSourceMatcher.toggleTarget(in: [abc, german], current: german), abc, "cycling wraps around")
try expectEqual(InputSourceMatcher.toggleTarget(in: [abc], current: abc), nil, "single source has nothing to toggle to")
try expectEqual(InputSourceMatcher.toggleTarget(in: installed, current: nil), russian, "unknown current source falls back to russian")

print("TwoShiftCoreCheck passed")
