import CoreAudio
import Foundation

/// Pure selection helpers shared by the production activity monitor and the
/// opt-in mute-signal diagnostic probe.
public enum XM6MuteSignalProbeSupport {
    public static let launchArgument = "--mute-signal-probe"

    public static func isEnabled(arguments: [String]) -> Bool {
        arguments.contains(launchArgument)
    }

    public static func isXM6(
        name: String,
        uid: String,
        modelUID: String,
        manufacturer: String
    ) -> Bool {
        let identities = [name, uid, modelUID].map(normalized)
        if identities.contains(where: { $0.contains("wh1000xm6") }) { return true }
        return normalized(manufacturer).contains("sony")
            && identities.contains(where: { $0.contains("1000xm6") })
    }

    /// CoreAudio controls may be exposed on the main element, individual input
    /// channels, or both. Keep the order deterministic for logs and listeners.
    public static func inputMuteElements(
        inputChannelCount: UInt32
    ) -> [AudioObjectPropertyElement] {
        guard inputChannelCount > 0 else { return [kAudioObjectPropertyElementMain] }
        var elements = [kAudioObjectPropertyElementMain]
        for channel in 1...inputChannelCount {
            elements.append(channel)
        }
        return elements
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
