import Testing
@testable import XM6ControlCore

struct XM6MicrophoneSessionStateMachineTests {
    @Test func buttonWhileInactiveIsIgnored() {
        let result = apply(.buttonPressed, to: .inactive)
        #expect(result.state == .inactive)
        #expect(result.indicatorAction == .none)
    }

    @Test func activeInputStartsWithSilentUnmutedBaseline() {
        let result = apply(.inputBecameActive, to: .inactive)
        #expect(result.state == .activeUnmuted)
        #expect(result.indicatorAction == .none)
    }

    @Test func buttonWhileUnmutedInfersMuted() {
        let result = apply(.buttonPressed, to: .activeUnmuted)
        #expect(result.state == .activeMuted)
        #expect(result.indicatorAction == .showMuted)
    }

    @Test func buttonWhileMutedInfersUnmuted() {
        let result = apply(.buttonPressed, to: .activeMuted)
        #expect(result.state == .activeUnmuted)
        #expect(result.indicatorAction == .showUnmuted)
    }

    @Test func endingMutedSessionClearsStateAndIndicator() {
        let result = apply(.inputBecameInactive, to: .activeMuted)
        #expect(result.state == .inactive)
        #expect(result.indicatorAction == .hide)
    }

    @Test func endingUnmutedSessionClearsStateAndIndicator() {
        let result = apply(.inputBecameInactive, to: .activeUnmuted)
        #expect(result.state == .inactive)
        #expect(result.indicatorAction == .hide)
    }

    @Test func outsideCallPressesDoNotChangeNextSessionBaseline() {
        var state: XM6MicrophoneSessionState = .inactive
        state = apply(.buttonPressed, to: state).state
        state = apply(.buttonPressed, to: state).state
        let result = apply(.inputBecameActive, to: state)

        #expect(result.state == .activeUnmuted)
        #expect(result.indicatorAction == .none)
    }

    @Test func endedMutedSessionDoesNotLeakIntoNextSession() {
        var state: XM6MicrophoneSessionState = .activeUnmuted
        state = apply(.buttonPressed, to: state).state
        #expect(state == .activeMuted)

        let ended = apply(.inputBecameInactive, to: state)
        #expect(ended.state == .inactive)
        #expect(ended.indicatorAction == .hide)

        state = apply(.buttonPressed, to: ended.state).state
        let restarted = apply(.inputBecameActive, to: state)
        #expect(restarted.state == .activeUnmuted)
        #expect(restarted.indicatorAction == .none)
    }

    @Test func disconnectWhileMutedClearsStateBeforeReconnectSession() {
        var state: XM6MicrophoneSessionState = .activeUnmuted
        state = apply(.buttonPressed, to: state).state
        #expect(state == .activeMuted)

        let disconnected = apply(.inputBecameInactive, to: state)
        #expect(disconnected.state == .inactive)
        #expect(disconnected.indicatorAction == .hide)

        let reconnectedSession = apply(.inputBecameActive, to: disconnected.state)
        #expect(reconnectedSession.state == .activeUnmuted)
        #expect(reconnectedSession.indicatorAction == .none)
    }

    private func apply(
        _ event: XM6MicrophoneSessionEvent,
        to state: XM6MicrophoneSessionState
    ) -> XM6MicrophoneSessionTransition {
        XM6MicrophoneSessionStateMachine.transition(from: state, event: event)
    }
}
