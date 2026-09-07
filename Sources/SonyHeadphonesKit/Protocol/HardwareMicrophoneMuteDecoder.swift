import Foundation

/// Decodes the unsolicited custom-button event emitted when the WH-1000XM6 hardware
/// microphone mute state changes.
enum HardwareMicrophoneMuteDecoder {
    private static let eventName = "keyCustomBtnTwo"

    static func decode(_ payload: [UInt8]) -> Bool? {
        guard payload.count >= 3, payload[0] == Opcode.customButtonEvent else {
            return nil
        }
        guard let muted = boolFromByte(payload[1]) else { return nil }

        let nameLength = Int(payload[2])
        let nameStart = 3
        let nameEnd = nameStart + nameLength
        guard nameEnd <= payload.count,
              let name = String(bytes: payload[nameStart..<nameEnd], encoding: .ascii),
              name == eventName else {
            return nil
        }

        return muted
    }
}
