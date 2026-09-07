/// App-layer state inferred from CoreAudio input activity and Sony's button event.
/// Sony never reports an absolute microphone mute state.
public enum XM6MicrophoneSessionState: Equatable, Sendable {
    case inactive
    case activeUnmuted
    case activeMuted
}

public enum XM6MicrophoneSessionEvent: Equatable, Sendable {
    case inputBecameActive
    case inputBecameInactive
    case buttonPressed
}

/// Presentation commands are explicit because entering a session establishes an
/// unmuted baseline but must not display the transient green indicator.
public enum XM6MicrophoneIndicatorAction: Equatable, Sendable {
    case none
    case showMuted
    case showUnmuted
    case hide
}

public struct XM6MicrophoneSessionTransition: Equatable, Sendable {
    public let state: XM6MicrophoneSessionState
    public let indicatorAction: XM6MicrophoneIndicatorAction

    public init(
        state: XM6MicrophoneSessionState,
        indicatorAction: XM6MicrophoneIndicatorAction
    ) {
        self.state = state
        self.indicatorAction = indicatorAction
    }
}

/// A small deterministic reducer so the microphone-session behavior can be tested
/// without Bluetooth or CoreAudio hardware.
public enum XM6MicrophoneSessionStateMachine {
    public static func transition(
        from state: XM6MicrophoneSessionState,
        event: XM6MicrophoneSessionEvent
    ) -> XM6MicrophoneSessionTransition {
        switch (state, event) {
        case (.inactive, .inputBecameActive):
            return XM6MicrophoneSessionTransition(
                state: .activeUnmuted,
                indicatorAction: .none
            )

        case (.activeUnmuted, .buttonPressed):
            return XM6MicrophoneSessionTransition(
                state: .activeMuted,
                indicatorAction: .showMuted
            )

        case (.activeMuted, .buttonPressed):
            return XM6MicrophoneSessionTransition(
                state: .activeUnmuted,
                indicatorAction: .showUnmuted
            )

        case (.activeUnmuted, .inputBecameInactive),
             (.activeMuted, .inputBecameInactive):
            return XM6MicrophoneSessionTransition(
                state: .inactive,
                indicatorAction: .hide
            )

        default:
            return XM6MicrophoneSessionTransition(
                state: state,
                indicatorAction: .none
            )
        }
    }
}
