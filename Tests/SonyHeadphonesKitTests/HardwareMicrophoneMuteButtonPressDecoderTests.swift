import Testing
@testable import SonyHeadphonesKit

struct HardwareMicrophoneMuteButtonPressDecoderTests {
    private let capturedButtonPressPayload: [UInt8] = [
        0xc9, 0x01, 0x0f,
        0x6b, 0x65, 0x79, 0x43, 0x75, 0x73, 0x74, 0x6f,
        0x6d, 0x42, 0x74, 0x6e, 0x54, 0x77, 0x6f,
        0x00, 0x00
    ]

    @Test func decodesCapturedButtonPressPayload() {
        #expect(isHardwareMicrophoneMuteButtonPress(capturedButtonPressPayload))
    }

    @Test func ignoresCommand2Payload() {
        #expect(!isHardwareMicrophoneMuteButtonPress(capturedButtonPressPayload, messageType: .command2))
    }

    @Test func ignoresDifferentEventName() {
        var payload = capturedButtonPressPayload
        payload.replaceSubrange(15...17, with: [0x4f, 0x6e, 0x65]) // "keyCustomBtnOne"
        #expect(!isHardwareMicrophoneMuteButtonPress(payload))
    }

    @Test func ignoresDifferentOpcode() {
        var payload = capturedButtonPressPayload
        payload[0] = 0xc8
        #expect(!isHardwareMicrophoneMuteButtonPress(payload))
    }

    @Test func ignoresUnknownFixedFieldValue() {
        var payload = capturedButtonPressPayload
        payload[1] = 0x02
        #expect(!isHardwareMicrophoneMuteButtonPress(payload))
    }

    @Test func ignoresTooShortPayload() {
        #expect(!isHardwareMicrophoneMuteButtonPress([0xc9, 0x01]))
    }

    @Test func ignoresInconsistentDeclaredNameLength() {
        var payload = Array(capturedButtonPressPayload.prefix(12))
        payload[2] = 0x0f
        #expect(!isHardwareMicrophoneMuteButtonPress(payload))
    }

    @Test func ignoresMalformedASCIIName() {
        var payload = capturedButtonPressPayload
        payload[3] = 0xff
        #expect(!isHardwareMicrophoneMuteButtonPress(payload))
    }

    @Test func allowsFutureTrailingBytes() {
        #expect(isHardwareMicrophoneMuteButtonPress(capturedButtonPressPayload + [0xaa, 0xbb]))
    }

    private func isHardwareMicrophoneMuteButtonPress(
        _ payload: [UInt8],
        messageType: SonyMessageType = .command1
    ) -> Bool {
        guard case .hardwareMicrophoneMuteButtonPressed = SonyEventDecoder.decode(
            payload: payload,
            messageType: messageType
        ) else {
            return false
        }
        return true
    }
}
