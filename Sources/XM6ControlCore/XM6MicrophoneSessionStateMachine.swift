/// App-layer state inferred from CoreAudio input activity and Sony's button event.
/// Sony never reports an absolute microphone mute state.
public enum XM6MicrophoneSessionState: Equatable, Sendable {
    case inactive
    case activeUnmuted
    case activeMuted
    case activeUnknown
}

public enum XM6MicrophoneSessionEvent: Equatable, Sendable {
    case inputActivityObserved(Bool)
    case controlConnectionChanged(isConnected: Bool)
    case buttonPressed
}

/// Presentation commands are explicit because entering a session establishes an
/// unmuted baseline but must not display the transient green indicator.
public enum XM6MicrophoneIndicatorAction: Equatable, Sendable {
    case none
    case showMuted
    case showUnmuted
    case showUnknown
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
public struct XM6MicrophoneSessionStateMachine: Sendable {
    public private(set) var state: XM6MicrophoneSessionState = .inactive

    /// `nil` means CoreAudio discovery has not completed. This deliberately keeps
    /// the monitor's placeholder `false` separate from observed inactivity.
    private var observedInputActivity: Bool?
    private var isControlConnected = false

    public init() {}

    public mutating func handle(
        _ event: XM6MicrophoneSessionEvent
    ) -> XM6MicrophoneSessionTransition {
        let transition: XM6MicrophoneSessionTransition

        switch event {
        case .inputActivityObserved(false):
            observedInputActivity = false
            transition = state == .inactive
                ? unchanged()
                : result(.inactive, .hide)

        case .inputActivityObserved(true):
            let previousObservation = observedInputActivity
            observedInputActivity = true

            if previousObservation == true {
                // A repeated active report is not evidence of a fresh session.
                transition = unchanged()
            } else if previousObservation == false, isControlConnected {
                // We saw the preceding inactive state and the complete new start.
                transition = result(.activeUnmuted, .none)
            } else {
                // The app started mid-session, or the session began without the
                // control channel needed to observe every Sony button press.
                transition = result(.activeUnknown, .showUnknown)
            }

        case .controlConnectionChanged(let connected):
            let wasConnected = isControlConnected
            isControlConnected = connected

            if wasConnected, !connected, observedInputActivity == true {
                // Button events can be lost until RFCOMM returns. Do not turn this
                // into a synthetic input-session boundary.
                transition = result(.activeUnknown, .showUnknown)
            } else if !wasConnected, connected,
                      observedInputActivity == true,
                      state == .activeUnknown || state == .inactive {
                // Restoring only RFCOMM cannot recreate an absolute mute baseline.
                transition = result(.activeUnknown, .showUnknown)
            } else {
                transition = unchanged()
            }

        case .buttonPressed:
            switch state {
            case .activeUnmuted:
                transition = result(.activeMuted, .showMuted)
            case .activeMuted:
                transition = result(.activeUnmuted, .showUnmuted)
            case .inactive, .activeUnknown:
                // Sony reports a press, not the resulting absolute mute state.
                transition = unchanged()
            }
        }

        state = transition.state
        return transition
    }

    private func unchanged() -> XM6MicrophoneSessionTransition {
        result(state, .none)
    }

    private func result(
        _ state: XM6MicrophoneSessionState,
        _ action: XM6MicrophoneIndicatorAction
    ) -> XM6MicrophoneSessionTransition {
        XM6MicrophoneSessionTransition(state: state, indicatorAction: action)
    }
}
