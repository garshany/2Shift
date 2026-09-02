@preconcurrency import AppKit
import Carbon
import TwoShiftCore

/// Switches the system keyboard layout via Text Input Sources (TIS).
///
/// TIS is documented as main-thread only, hence `@MainActor`. The enabled
/// source list is re-read on every call: the user can enable or disable
/// layouts in System Settings at any time, and the call happens only on an
/// explicit trigger (a few milliseconds, not a hot path).
@MainActor
final class InputSourceSwitcher {
    enum SwitchResult: Equatable {
        case switched(identifier: String)
        /// Requested language already active, or no other source to move to.
        case alreadyActive
        /// No enabled input source speaks the requested language.
        case noMatchingSource
        /// TISSelectInputSource refused the source.
        case failed(status: Int)
    }

    /// Selects the layout the converted text is written in.
    @discardableResult
    func selectLayout(for direction: ConversionDirection) -> SwitchResult {
        let language = InputSourceMatcher.resultLanguage(for: direction)
        let sources = enabledSources()
        guard
            let target = InputSourceMatcher.source(
                for: language,
                in: sources.map(\.candidate),
                current: currentCandidate()
            )
        else {
            return sources.contains(where: { $0.candidate.supports(language: language) })
                ? .alreadyActive
                : .noMatchingSource
        }
        return select(identifier: target.identifier, in: sources)
    }

    /// Toggles between the enabled EN and RU layouts (used when there was
    /// nothing to convert, so no direction is known).
    @discardableResult
    func toggleLayout() -> SwitchResult {
        let sources = enabledSources()
        guard
            let target = InputSourceMatcher.toggleTarget(
                in: sources.map(\.candidate),
                current: currentCandidate()
            )
        else {
            return sources.count > 1 ? .alreadyActive : .noMatchingSource
        }
        return select(identifier: target.identifier, in: sources)
    }

    // MARK: - TIS bridging

    private struct Source {
        let candidate: InputSourceCandidate
        let inputSource: TISInputSource
    }

    private func select(identifier: String, in sources: [Source]) -> SwitchResult {
        guard let source = sources.first(where: { $0.candidate.identifier == identifier }) else {
            return .noMatchingSource
        }

        let status = TISSelectInputSource(source.inputSource)
        guard status == noErr else {
            return .failed(status: Int(status))
        }
        return .switched(identifier: identifier)
    }

    private func enabledSources() -> [Source] {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsEnableCapable: kCFBooleanTrue as Any
        ]

        guard
            let list = TISCreateInputSourceList(filter as CFDictionary, false)?
                .takeRetainedValue() as? [TISInputSource]
        else {
            return []
        }

        return list.compactMap { inputSource in
            guard
                isSelectable(inputSource),
                let candidate = makeCandidate(from: inputSource)
            else {
                return nil
            }
            return Source(candidate: candidate, inputSource: inputSource)
        }
    }

    private func currentCandidate() -> InputSourceCandidate? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return makeCandidate(from: current)
    }

    private func makeCandidate(from inputSource: TISInputSource) -> InputSourceCandidate? {
        guard let identifier = stringProperty(inputSource, kTISPropertyInputSourceID) else {
            return nil
        }

        let languages = arrayProperty(inputSource, kTISPropertyInputSourceLanguages) as? [String] ?? []
        return InputSourceCandidate(
            identifier: identifier,
            languages: languages,
            isASCIICapable: boolProperty(inputSource, kTISPropertyInputSourceIsASCIICapable)
        )
    }

    private func isSelectable(_ inputSource: TISInputSource) -> Bool {
        boolProperty(inputSource, kTISPropertyInputSourceIsSelectCapable)
    }

    private func stringProperty(_ inputSource: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(inputSource, key) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private func arrayProperty(_ inputSource: TISInputSource, _ key: CFString) -> [Any]? {
        guard let pointer = TISGetInputSourceProperty(inputSource, key) else {
            return nil
        }
        return Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [Any]
    }

    private func boolProperty(_ inputSource: TISInputSource, _ key: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(inputSource, key) else {
            return false
        }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }
}
