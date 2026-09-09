public enum XM6MicrophoneIndicatorLocation: String, CaseIterable, Equatable, Sendable {
    case nearNotch
    case menuBarIcon

    public static let defaultValue: Self = .nearNotch
}

public enum XM6MicrophoneIndicatorAppearance: Equatable, Sendable {
    case hidden
    case muted
    case unmuted
}

/// Keeps presentation state independent from the inferred microphone state. Both
/// renderers consume this single value; neither owns a second mute state machine.
public enum XM6MicrophoneIndicatorPresentationStateMachine {
    public static func transition(
        from appearance: XM6MicrophoneIndicatorAppearance,
        action: XM6MicrophoneIndicatorAction
    ) -> XM6MicrophoneIndicatorAppearance {
        switch action {
        case .none:
            return appearance
        case .hide:
            return .hidden
        case .showMuted:
            return .muted
        case .showUnmuted:
            return .unmuted
        }
    }
}
