import Foundation

/// Decodes the unsolicited custom-button event emitted when the WH-1000XM6 hardware
/// microphone button is double-pressed. The packet reports only the button press; it
/// does not report or guarantee a microphone mute-state change.
enum HardwareMicrophoneMuteButtonPressDecoder {
    private static let eventName = "keyCustomBtnTwo"

    static func decode(
        _ payload: [UInt8],
        messageType: SonyMessageType
    ) -> HeadphonesEvent? {
        guard messageType == .command1,
              payload.count >= 3,
              payload[0] == Opcode.customButtonEvent else {
            return nil
        }

        // This field was 0x01 in every captured button press. Its meaning is unknown.
        guard payload[1] == 0x01 else { return nil }

        let nameLength = Int(payload[2])
        let nameStart = 3
        let nameEnd = nameStart + nameLength
        guard nameEnd <= payload.count,
              let name = String(bytes: payload[nameStart..<nameEnd], encoding: .ascii),
              name == eventName else {
            return nil
        }

        return .hardwareMicrophoneMuteButtonPressed
    }
}
