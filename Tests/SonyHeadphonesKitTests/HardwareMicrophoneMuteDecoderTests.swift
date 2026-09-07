import Testing
@testable import SonyHeadphonesKit

struct HardwareMicrophoneMuteDecoderTests {
    private let mutedPayload: [UInt8] = [
        0xc9, 0x01, 0x0f,
        0x6b, 0x65, 0x79, 0x43, 0x75, 0x73, 0x74, 0x6f,
        0x6d, 0x42, 0x74, 0x6e, 0x54, 0x77, 0x6f,
        0x00, 0x00
    ]

    private let unmutedPayload: [UInt8] = [
        0xc9, 0x00, 0x0f,
        0x6b, 0x65, 0x79, 0x43, 0x75, 0x73, 0x74, 0x6f,
        0x6d, 0x42, 0x74, 0x6e, 0x54, 0x77, 0x6f,
        0x00, 0x00
    ]

    @Test func decodesCapturedMutedPayload() {
        #expect(decodedMuteState(from: mutedPayload) == true)
    }

    @Test func decodesCapturedUnmutedPayload() {
        #expect(decodedMuteState(from: unmutedPayload) == false)
    }

    @Test func ignoresDifferentEventName() {
        var payload = mutedPayload
        payload.replaceSubrange(15...17, with: [0x4f, 0x6e, 0x65]) // "keyCustomBtnOne"
        #expect(decodedMuteState(from: payload) == nil)
    }

    @Test func ignoresDifferentOpcode() {
        var payload = mutedPayload
        payload[0] = 0xc8
        #expect(decodedMuteState(from: payload) == nil)
    }

    @Test func ignoresInvalidStateByte() {
        var payload = mutedPayload
        payload[1] = 0x02
        #expect(decodedMuteState(from: payload) == nil)
    }

    @Test func ignoresTooShortPayload() {
        #expect(decodedMuteState(from: [0xc9, 0x01]) == nil)
    }

    @Test func ignoresInconsistentDeclaredNameLength() {
        var payload = Array(mutedPayload.prefix(12))
        payload[2] = 0x0f
        #expect(decodedMuteState(from: payload) == nil)
    }

    @Test func allowsFutureTrailingBytes() {
        #expect(decodedMuteState(from: mutedPayload + [0xaa, 0xbb]) == true)
    }

    private func decodedMuteState(from payload: [UInt8]) -> Bool? {
        guard case .hardwareMicrophoneMute(let muted) = SonyEventDecoder.decode(
            payload: payload,
            messageType: .command1
        ) else {
            return nil
        }
        return muted
    }
}
