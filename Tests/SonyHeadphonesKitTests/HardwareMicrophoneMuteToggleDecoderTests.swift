import Testing
@testable import SonyHeadphonesKit

struct HardwareMicrophoneMuteToggleDecoderTests {
    private let capturedTogglePayload: [UInt8] = [
        0xc9, 0x01, 0x0f,
        0x6b, 0x65, 0x79, 0x43, 0x75, 0x73, 0x74, 0x6f,
        0x6d, 0x42, 0x74, 0x6e, 0x54, 0x77, 0x6f,
        0x00, 0x00
    ]

    @Test func decodesCapturedTogglePayload() {
        #expect(isHardwareMicrophoneMuteToggle(capturedTogglePayload))
    }

    @Test func ignoresCommand2Payload() {
        #expect(!isHardwareMicrophoneMuteToggle(capturedTogglePayload, messageType: .command2))
    }

    @Test func ignoresDifferentEventName() {
        var payload = capturedTogglePayload
        payload.replaceSubrange(15...17, with: [0x4f, 0x6e, 0x65]) // "keyCustomBtnOne"
        #expect(!isHardwareMicrophoneMuteToggle(payload))
    }

    @Test func ignoresDifferentOpcode() {
        var payload = capturedTogglePayload
        payload[0] = 0xc8
        #expect(!isHardwareMicrophoneMuteToggle(payload))
    }

    @Test func ignoresUnknownFixedFieldValue() {
        var payload = capturedTogglePayload
        payload[1] = 0x02
        #expect(!isHardwareMicrophoneMuteToggle(payload))
    }

    @Test func ignoresTooShortPayload() {
        #expect(!isHardwareMicrophoneMuteToggle([0xc9, 0x01]))
    }

    @Test func ignoresInconsistentDeclaredNameLength() {
        var payload = Array(capturedTogglePayload.prefix(12))
        payload[2] = 0x0f
        #expect(!isHardwareMicrophoneMuteToggle(payload))
    }

    @Test func ignoresMalformedASCIIName() {
        var payload = capturedTogglePayload
        payload[3] = 0xff
        #expect(!isHardwareMicrophoneMuteToggle(payload))
    }

    @Test func allowsFutureTrailingBytes() {
        #expect(isHardwareMicrophoneMuteToggle(capturedTogglePayload + [0xaa, 0xbb]))
    }

    private func isHardwareMicrophoneMuteToggle(
        _ payload: [UInt8],
        messageType: SonyMessageType = .command1
    ) -> Bool {
        guard case .hardwareMicrophoneMuteToggle = SonyEventDecoder.decode(
            payload: payload,
            messageType: messageType
        ) else {
            return false
        }
        return true
    }
}

struct HardwareMicrophoneMuteStateTransitionTests {
    @Test func firstToggleInfersMuted() {
        #expect(HardwareMicrophoneMuteStateTransition.next(after: nil) == true)
    }

    @Test func secondToggleInfersUnmuted() {
        #expect(HardwareMicrophoneMuteStateTransition.next(after: true) == false)
    }

    @Test func subsequentToggleInfersMutedAgain() {
        #expect(HardwareMicrophoneMuteStateTransition.next(after: false) == true)
    }
}
