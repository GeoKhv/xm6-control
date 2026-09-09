import Testing
@testable import XM6ControlCore

struct XM6MicrophoneSessionStateMachineTests {
    @Test func launchWhileInputIsAlreadyActiveStartsUnknown() {
        var machine = connectedMachineWithoutInputObservation()
        let result = machine.handle(.inputActivityObserved(true))

        #expect(result.state == .activeUnknown)
        #expect(result.indicatorAction == .showUnknown)
    }

    @Test func placeholderInactiveBeforeDiscoveryDoesNotCreateBaseline() {
        var machine = XM6MicrophoneSessionStateMachine()
        _ = machine.handle(.controlConnectionChanged(isConnected: false))
        _ = machine.handle(.controlConnectionChanged(isConnected: true))
        let result = machine.handle(.inputActivityObserved(true))

        #expect(result.state == .activeUnknown)
        #expect(result.indicatorAction == .showUnknown)
    }

    @Test func activeObservationBeforeInitialControlConnectionRemainsUnknown() {
        var machine = XM6MicrophoneSessionStateMachine()
        let observed = machine.handle(.inputActivityObserved(true))
        let connected = machine.handle(.controlConnectionChanged(isConnected: true))

        #expect(observed.state == .activeUnknown)
        #expect(connected.state == .activeUnknown)
        #expect(connected.indicatorAction == .showUnknown)
    }

    @Test func buttonWhileUnknownKeepsUnknown() {
        var machine = unknownMachine()
        let result = machine.handle(.buttonPressed)

        #expect(result.state == .activeUnknown)
        #expect(result.indicatorAction == .none)
    }

    @Test func repeatedActiveObservationsDoNotClearUnknown() {
        var machine = unknownMachine()
        let result = machine.handle(.inputActivityObserved(true))

        #expect(result.state == .activeUnknown)
        #expect(result.indicatorAction == .none)
    }

    @Test func inactiveThenNewActiveSessionEstablishesUnmutedBaseline() {
        var machine = unknownMachine()
        let ended = machine.handle(.inputActivityObserved(false))
        let restarted = machine.handle(.inputActivityObserved(true))

        #expect(ended.state == .inactive)
        #expect(ended.indicatorAction == .hide)
        #expect(restarted.state == .activeUnmuted)
        #expect(restarted.indicatorAction == .none)
    }

    @Test func controlLossDuringActiveInputMakesStateUnknown() {
        var machine = knownUnmutedMachine()
        let result = machine.handle(.controlConnectionChanged(isConnected: false))

        #expect(result.state == .activeUnknown)
        #expect(result.indicatorAction == .showUnknown)
    }

    @Test func restoringOnlyControlConnectionDoesNotRestoreBaseline() {
        var machine = knownUnmutedMachine()
        _ = machine.handle(.controlConnectionChanged(isConnected: false))
        let result = machine.handle(.controlConnectionChanged(isConnected: true))

        #expect(result.state == .activeUnknown)
        #expect(result.indicatorAction == .showUnknown)
    }

    @Test func observedPowerCycleAllowsNextConnectedSessionBaseline() {
        var machine = knownUnmutedMachine()
        _ = machine.handle(.buttonPressed)
        #expect(machine.state == .activeMuted)

        _ = machine.handle(.controlConnectionChanged(isConnected: false))
        let ended = machine.handle(.inputActivityObserved(false))
        _ = machine.handle(.controlConnectionChanged(isConnected: true))
        let restarted = machine.handle(.inputActivityObserved(true))

        #expect(ended.state == .inactive)
        #expect(ended.indicatorAction == .hide)
        #expect(restarted.state == .activeUnmuted)
        #expect(restarted.indicatorAction == .none)
    }

    @Test func sessionStartingWithoutControlRemainsUnknownAfterReconnect() {
        var machine = XM6MicrophoneSessionStateMachine()
        _ = machine.handle(.inputActivityObserved(false))
        let started = machine.handle(.inputActivityObserved(true))
        let restored = machine.handle(.controlConnectionChanged(isConnected: true))

        #expect(started.state == .activeUnknown)
        #expect(restored.state == .activeUnknown)
        #expect(restored.indicatorAction == .showUnknown)
    }

    @Test func normalMuteAndUnmuteBehaviorIsPreserved() {
        var machine = knownUnmutedMachine()
        let muted = machine.handle(.buttonPressed)
        let unmuted = machine.handle(.buttonPressed)

        #expect(muted.state == .activeMuted)
        #expect(muted.indicatorAction == .showMuted)
        #expect(unmuted.state == .activeUnmuted)
        #expect(unmuted.indicatorAction == .showUnmuted)
    }

    @Test func pressesOutsideInputDoNotChangeNextSessionBaseline() {
        var machine = XM6MicrophoneSessionStateMachine()
        _ = machine.handle(.controlConnectionChanged(isConnected: true))
        _ = machine.handle(.inputActivityObserved(false))
        _ = machine.handle(.buttonPressed)
        _ = machine.handle(.buttonPressed)
        let result = machine.handle(.inputActivityObserved(true))

        #expect(result.state == .activeUnmuted)
        #expect(result.indicatorAction == .none)
    }

    private func connectedMachineWithoutInputObservation() -> XM6MicrophoneSessionStateMachine {
        var machine = XM6MicrophoneSessionStateMachine()
        _ = machine.handle(.controlConnectionChanged(isConnected: true))
        return machine
    }

    private func unknownMachine() -> XM6MicrophoneSessionStateMachine {
        var machine = connectedMachineWithoutInputObservation()
        _ = machine.handle(.inputActivityObserved(true))
        return machine
    }

    private func knownUnmutedMachine() -> XM6MicrophoneSessionStateMachine {
        var machine = connectedMachineWithoutInputObservation()
        _ = machine.handle(.inputActivityObserved(false))
        _ = machine.handle(.inputActivityObserved(true))
        return machine
    }
}
