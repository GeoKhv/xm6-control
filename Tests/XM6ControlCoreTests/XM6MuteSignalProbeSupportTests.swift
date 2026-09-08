import CoreAudio
import Testing
@testable import XM6ControlCore

struct XM6MuteSignalProbeSupportTests {
    @Test func probeIsEnabledOnlyByExactLaunchArgument() {
        #expect(
            XM6MuteSignalProbeSupport.isEnabled(
                arguments: ["XM6Control", "--mute-signal-probe"]
            )
        )
        #expect(
            !XM6MuteSignalProbeSupport.isEnabled(
                arguments: ["XM6Control", "--mute-signal-probe=true"]
            )
        )
        #expect(!XM6MuteSignalProbeSupport.isEnabled(arguments: ["XM6Control"]))
    }

    @Test func xm6IdentityMatchingNormalizesPunctuationAndCase() {
        #expect(
            XM6MuteSignalProbeSupport.isXM6(
                name: "WH-1000XM6",
                uid: "ignored",
                modelUID: "",
                manufacturer: ""
            )
        )
        #expect(
            XM6MuteSignalProbeSupport.isXM6(
                name: "Headset",
                uid: "1000-XM6-input",
                modelUID: "",
                manufacturer: "Sony Corporation"
            )
        )
        #expect(
            !XM6MuteSignalProbeSupport.isXM6(
                name: "WH-1000XM5",
                uid: "1000xm5",
                modelUID: "",
                manufacturer: "Sony"
            )
        )
    }

    @Test func inputMuteElementsIncludeMainThenEveryInputChannel() {
        #expect(
            XM6MuteSignalProbeSupport.inputMuteElements(inputChannelCount: 0)
                == [kAudioObjectPropertyElementMain]
        )
        #expect(
            XM6MuteSignalProbeSupport.inputMuteElements(inputChannelCount: 2)
                == [kAudioObjectPropertyElementMain, 1, 2]
        )
    }
}
