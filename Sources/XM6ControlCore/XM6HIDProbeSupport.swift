import Foundation

/// Pure helpers for the opt-in, passive WH-1000XM6 HID diagnostic probe.
public enum XM6HIDProbeSupport {
    public static let launchArgument = "--hid-mute-probe"

    public struct DeviceMetadata: Equatable, Sendable {
        public var product: String?
        public var manufacturer: String?
        public var transport: String?
        public var vendorID: Int?
        public var productID: Int?
        public var serialNumber: String?
        public var primaryUsagePage: Int?
        public var primaryUsage: Int?
        public var locationID: Int?
        public var uniqueID: String?
        public var registryID: UInt64?

        public init(
            product: String? = nil,
            manufacturer: String? = nil,
            transport: String? = nil,
            vendorID: Int? = nil,
            productID: Int? = nil,
            serialNumber: String? = nil,
            primaryUsagePage: Int? = nil,
            primaryUsage: Int? = nil,
            locationID: Int? = nil,
            uniqueID: String? = nil,
            registryID: UInt64? = nil
        ) {
            self.product = product
            self.manufacturer = manufacturer
            self.transport = transport
            self.vendorID = vendorID
            self.productID = productID
            self.serialNumber = serialNumber
            self.primaryUsagePage = primaryUsagePage
            self.primaryUsage = primaryUsage
            self.locationID = locationID
            self.uniqueID = uniqueID
            self.registryID = registryID
        }
    }

    public static func isEnabled(arguments: [String]) -> Bool {
        arguments.contains(launchArgument)
    }

    /// An XM6 marker is required before callbacks are installed. Sony vendor or
    /// Bluetooth metadata alone is deliberately insufficient, because that could
    /// subscribe the probe to an unrelated controller, keyboard, or mouse.
    public static func isCandidate(_ metadata: DeviceMetadata) -> Bool {
        [
            metadata.product,
            metadata.manufacturer,
            metadata.serialNumber,
            metadata.uniqueID
        ]
        .compactMap { $0 }
        .map(normalizedIdentity)
        .contains { $0.contains("wh1000xm6") || $0.contains("1000xm6") }
    }

    public static func isBluetooth(_ metadata: DeviceMetadata) -> Bool {
        guard let transport = metadata.transport else { return false }
        return normalizedIdentity(transport).contains("bluetooth")
    }

    public static func deviceIdentifier(_ metadata: DeviceMetadata) -> String {
        var parts = [quoted(metadata.product ?? "unknown")]
        if let vendorID = metadata.vendorID, let productID = metadata.productID {
            parts.append(String(format: "vid=0x%04x", vendorID))
            parts.append(String(format: "pid=0x%04x", productID))
        }
        if let locationID = metadata.locationID {
            parts.append(String(format: "location=0x%x", locationID))
        }
        if let registryID = metadata.registryID {
            parts.append(String(format: "registry=0x%llx", registryID))
        } else if let uniqueID = metadata.uniqueID {
            parts.append("unique=\(quoted(uniqueID))")
        }
        return parts.joined(separator: " ")
    }

    public static func formatReport(_ bytes: [UInt8], maximumBytes: Int = 128) -> String {
        let safeMaximum = max(0, maximumBytes)
        let prefix = bytes.prefix(safeMaximum).map { String(format: "%02x", $0) }
            .joined(separator: " ")
        guard bytes.count > safeMaximum else { return prefix }
        return "\(prefix) [truncated \(bytes.count - safeMaximum) bytes]"
    }

    public static func reportBufferSize(
        reportedSize: Int?,
        fallback: Int = 1_024,
        maximum: Int = 16_384
    ) -> Int {
        let safeMaximum = max(1, maximum)
        let requested = (reportedSize ?? fallback)
        return min(max(1, requested), safeMaximum)
    }

    public static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    private static func normalizedIdentity(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
