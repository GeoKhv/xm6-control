import Testing
@testable import XM6ControlCore

struct XM6MicrophoneIndicatorPresentationTests {
    @Test func locationDefaultsToNearNotch() {
        #expect(XM6MicrophoneIndicatorLocation.defaultValue == .nearNotch)
    }

    @Test func locationsHaveStablePersistenceValues() {
        #expect(XM6MicrophoneIndicatorLocation(rawValue: "nearNotch") == .nearNotch)
        #expect(XM6MicrophoneIndicatorLocation(rawValue: "menuBarIcon") == .menuBarIcon)
        #expect(XM6MicrophoneIndicatorLocation(rawValue: "unknown") == nil)
    }

    @Test func presentationActionsDriveOneSharedAppearance() {
        var appearance: XM6MicrophoneIndicatorAppearance = .hidden
        appearance = apply(.showMuted, to: appearance)
        #expect(appearance == .muted)

        appearance = apply(.showUnmuted, to: appearance)
        #expect(appearance == .unmuted)

        appearance = apply(.showUnknown, to: appearance)
        #expect(appearance == .unknown)

        appearance = apply(.hide, to: appearance)
        #expect(appearance == .hidden)
    }

    @Test func noPresentationActionPreservesCurrentAppearance() {
        #expect(apply(.none, to: .muted) == .muted)
        #expect(apply(.none, to: .unmuted) == .unmuted)
        #expect(apply(.none, to: .unknown) == .unknown)
    }

    private func apply(
        _ action: XM6MicrophoneIndicatorAction,
        to appearance: XM6MicrophoneIndicatorAppearance
    ) -> XM6MicrophoneIndicatorAppearance {
        XM6MicrophoneIndicatorPresentationStateMachine.transition(
            from: appearance,
            action: action
        )
    }
}
