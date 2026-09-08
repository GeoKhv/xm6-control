import Foundation
import IOKit
import IOKit.hid
import XM6ControlCore

/// Passive, opt-in diagnostics for public macOS HID events from WH-1000XM6.
///
/// The manager is used only to discover devices. It is intentionally not opened,
/// because an unfiltered IOHIDManager would open unrelated keyboards and mice.
/// Only devices whose public metadata contains an XM6 identity marker are opened,
/// always with non-seizing options, and receive input callbacks.
final class XM6HIDMuteProbe {
    fileprivate final class DeviceRegistration {
        weak var owner: XM6HIDMuteProbe?
        let device: IOHIDDevice
        let key: UInt
        let metadata: XM6HIDProbeSupport.DeviceMetadata
        let identifier: String
        let reportBuffer: UnsafeMutablePointer<UInt8>
        let reportBufferSize: Int
        var isOpen = true

        init(
            owner: XM6HIDMuteProbe,
            device: IOHIDDevice,
            key: UInt,
            metadata: XM6HIDProbeSupport.DeviceMetadata,
            reportBufferSize: Int
        ) {
            self.owner = owner
            self.device = device
            self.key = key
            self.metadata = metadata
            identifier = XM6HIDProbeSupport.deviceIdentifier(metadata)
            self.reportBufferSize = reportBufferSize
            reportBuffer = .allocate(capacity: reportBufferSize)
            reportBuffer.initialize(repeating: 0, count: reportBufferSize)
        }

        func stop() {
            guard isOpen else { return }
            isOpen = false
            IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
            IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, reportBufferSize, nil, nil)
            IOHIDDeviceRegisterRemovalCallback(device, nil, nil)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            reportBuffer.deinitialize(count: reportBufferSize)
            reportBuffer.deallocate()
        }

        deinit {
            stop()
        }
    }

    private let diagnosticHandler: (String) -> Void
    private var manager: IOHIDManager?
    private var registrations: [UInt: DeviceRegistration] = [:]
    private var started = false

    init(diagnosticHandler: @escaping (String) -> Void) {
        self.diagnosticHandler = diagnosticHandler
    }

    func start() {
        guard !started else { return }
        started = true
        log("started")

        let manager = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        self.manager = manager

        // No matching dictionary means enumeration of public metadata only. No
        // manager-level input callback is ever installed.
        IOHIDManagerSetDeviceMatching(manager, nil)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(
            manager,
            xm6HIDManagerDeviceMatched,
            context
        )
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )
        log("manager discovery scheduled (manager not opened; candidate devices open individually)")

        let devices = copyDevices(from: manager)
        for device in devices {
            consider(device)
        }

        if registrations.isEmpty {
            log("no WH-1000XM6 HID candidate found")
            logBluetoothMetadataOnce(devices)
        }
    }

    func stop() {
        guard started else { return }
        started = false

        let oldRegistrations = Array(registrations.values)
        registrations.removeAll()
        oldRegistrations.forEach { $0.stop() }

        if let manager {
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.defaultMode.rawValue
            )
            self.manager = nil
        }
        log("stopped")
    }

    fileprivate func managerMatched(_ device: IOHIDDevice, result: IOReturn) {
        guard started else { return }
        guard result == kIOReturnSuccess else {
            log("device discovery callback result=\(describe(result))")
            return
        }
        consider(device)
    }

    fileprivate func receivedValue(
        registration: DeviceRegistration,
        result: IOReturn,
        value: IOHIDValue
    ) {
        guard started, registrations[registration.key] === registration else { return }
        guard result == kIOReturnSuccess else {
            log("value device=\(registration.identifier) result=\(describe(result))")
            return
        }

        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let integerValue = IOHIDValueGetIntegerValue(value)
        let reportID = IOHIDElementGetReportID(element)
        let elementType = IOHIDElementGetType(element)
        log(
            "value device=\(registration.identifier) "
                + "usagePage=\(hex(usagePage, width: 2)) usage=\(hex(usage, width: 4)) "
                + "value=\(integerValue) reportID=\(reportID) elementType=\(elementType.rawValue)"
        )
    }

    fileprivate func receivedReport(
        registration: DeviceRegistration,
        result: IOReturn,
        type: IOHIDReportType,
        reportID: UInt32,
        reportedLength: Int,
        bytes: [UInt8]
    ) {
        guard started, registrations[registration.key] === registration else { return }
        guard result == kIOReturnSuccess else {
            log("report device=\(registration.identifier) result=\(describe(result))")
            return
        }

        let typeName = type == kIOHIDReportTypeInput ? "input" : "\(type.rawValue)"
        log(
            "report device=\(registration.identifier) reportType=\(typeName) "
                + "reportID=\(reportID) length=\(reportedLength) "
                + "bytes=\(XM6HIDProbeSupport.formatReport(bytes))"
                + (reportedLength > bytes.count
                    ? " [callback buffer limited to \(bytes.count) bytes]"
                    : "")
        )
    }

    fileprivate func removed(_ registration: DeviceRegistration, result: IOReturn) {
        guard registrations[registration.key] === registration else { return }
        log("device removed \(registration.identifier) result=\(describe(result))")
        registrations.removeValue(forKey: registration.key)
        registration.stop()
    }

    private func consider(_ device: IOHIDDevice) {
        let key = deviceKey(device)
        guard registrations[key] == nil else { return }

        let metadata = readMetadata(device)
        guard XM6HIDProbeSupport.isCandidate(metadata) else { return }

        logCandidate(metadata)
        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        log("open device=\(XM6HIDProbeSupport.deviceIdentifier(metadata)) result=\(describe(openResult))")
        guard openResult == kIOReturnSuccess else {
            if openResult == kIOReturnNotPermitted || openResult == kIOReturnNotPrivileged {
                log("passive access denied; no permission or TCC workaround attempted")
            }
            return
        }

        let reportedSize = integerProperty(device, kIOHIDMaxInputReportSizeKey as CFString)
        let bufferSize = XM6HIDProbeSupport.reportBufferSize(reportedSize: reportedSize)
        let registration = DeviceRegistration(
            owner: self,
            device: device,
            key: key,
            metadata: metadata,
            reportBufferSize: bufferSize
        )
        registrations[key] = registration

        let context = Unmanaged.passUnretained(registration).toOpaque()
        IOHIDDeviceRegisterRemovalCallback(device, xm6HIDDeviceRemoved, context)
        IOHIDDeviceRegisterInputValueCallback(device, xm6HIDInputValue, context)
        IOHIDDeviceRegisterInputReportCallback(
            device,
            registration.reportBuffer,
            registration.reportBufferSize,
            xm6HIDInputReport,
            context
        )
        let sizeSource = reportedSize.map(String.init) ?? "unavailable; fallback=1024"
        log(
            "callbacks installed device=\(registration.identifier) "
                + "maxInputReportSize=\(sizeSource) bufferSize=\(bufferSize)"
        )
        logRelevantElements(device, identifier: registration.identifier)
    }

    private func readMetadata(_ device: IOHIDDevice) -> XM6HIDProbeSupport.DeviceMetadata {
        var registryID: UInt64 = 0
        let service = IOHIDDeviceGetService(device)
        let registryResult = service == IO_OBJECT_NULL
            ? kIOReturnNoDevice
            : IORegistryEntryGetRegistryEntryID(service, &registryID)

        return .init(
            product: stringProperty(device, kIOHIDProductKey as CFString),
            manufacturer: stringProperty(device, kIOHIDManufacturerKey as CFString),
            transport: stringProperty(device, kIOHIDTransportKey as CFString),
            vendorID: integerProperty(device, kIOHIDVendorIDKey as CFString),
            productID: integerProperty(device, kIOHIDProductIDKey as CFString),
            serialNumber: stringProperty(device, kIOHIDSerialNumberKey as CFString),
            primaryUsagePage: integerProperty(device, kIOHIDPrimaryUsagePageKey as CFString),
            primaryUsage: integerProperty(device, kIOHIDPrimaryUsageKey as CFString),
            locationID: integerProperty(device, kIOHIDLocationIDKey as CFString),
            uniqueID: propertyDescription(device, kIOHIDUniqueIDKey as CFString),
            registryID: registryResult == kIOReturnSuccess ? registryID : nil
        )
    }

    private func logCandidate(_ metadata: XM6HIDProbeSupport.DeviceMetadata) {
        log(
            "candidate device product=\(quoted(metadata.product)) "
                + "manufacturer=\(quoted(metadata.manufacturer)) "
                + "transport=\(quoted(metadata.transport)) "
                + "vendorID=\(optionalHex(metadata.vendorID, width: 4)) "
                + "productID=\(optionalHex(metadata.productID, width: 4)) "
                + "usagePage=\(optionalHex(metadata.primaryUsagePage, width: 2)) "
                + "usage=\(optionalHex(metadata.primaryUsage, width: 4)) "
                + "serial=\(quoted(metadata.serialNumber)) "
                + "locationID=\(optionalHex(metadata.locationID, width: 8)) "
                + "uniqueID=\(quoted(metadata.uniqueID)) "
                + "registryID=\(metadata.registryID.map { hex($0) } ?? "unavailable")"
        )
    }

    private func logBluetoothMetadataOnce(_ devices: [IOHIDDevice]) {
        let metadata = devices.map(readMetadata).filter(XM6HIDProbeSupport.isBluetooth)
        guard !metadata.isEmpty else {
            log("Bluetooth HID metadata: none found")
            return
        }
        for item in metadata {
            // Deliberately omit serial, location, unique, and registry identifiers
            // from this fallback list. No callbacks are installed on these devices.
            log(
                "Bluetooth HID metadata product=\(quoted(item.product)) "
                    + "manufacturer=\(quoted(item.manufacturer)) "
                    + "transport=\(quoted(item.transport)) "
                    + "vendorID=\(optionalHex(item.vendorID, width: 4)) "
                    + "productID=\(optionalHex(item.productID, width: 4)) "
                    + "usagePage=\(optionalHex(item.primaryUsagePage, width: 2)) "
                    + "usage=\(optionalHex(item.primaryUsage, width: 4))"
            )
        }
    }

    private func logRelevantElements(_ device: IOHIDDevice, identifier: String) {
        guard let elements = IOHIDDeviceCopyMatchingElements(
            device,
            nil,
            IOOptionBits(kIOHIDOptionsTypeNone)
        ) else {
            log("elements device=\(identifier) unavailable")
            return
        }

        let relevantPages: Set<UInt32> = [
            UInt32(kHIDPage_Button),
            UInt32(kHIDPage_Telephony),
            UInt32(kHIDPage_Consumer)
        ]
        let maximumElements = 128
        var relevantCount = 0
        var loggedCount = 0

        for index in 0..<CFArrayGetCount(elements) {
            let element = unsafeBitCast(
                CFArrayGetValueAtIndex(elements, index),
                to: IOHIDElement.self
            )
            let usagePage = IOHIDElementGetUsagePage(element)
            guard relevantPages.contains(usagePage)
                    || usagePage >= UInt32(kHIDPage_VendorDefinedStart) else {
                continue
            }
            relevantCount += 1
            guard loggedCount < maximumElements else { continue }
            loggedCount += 1
            log(
                "element device=\(identifier) usagePage=\(hex(usagePage, width: 2)) "
                    + "usage=\(hex(IOHIDElementGetUsage(element), width: 4)) "
                    + "reportID=\(IOHIDElementGetReportID(element)) "
                    + "elementType=\(IOHIDElementGetType(element).rawValue)"
            )
        }

        if relevantCount == 0 {
            log("elements device=\(identifier) no relevant consumer/telephony/button/vendor-defined elements")
        } else if relevantCount > maximumElements {
            log("elements device=\(identifier) truncated \(relevantCount - maximumElements) entries")
        }
    }

    private func copyDevices(from manager: IOHIDManager) -> [IOHIDDevice] {
        guard let set = IOHIDManagerCopyDevices(manager) else { return [] }
        let count = CFSetGetCount(set)
        guard count > 0 else { return [] }
        var rawValues = [UnsafeRawPointer?](repeating: nil, count: count)
        CFSetGetValues(set, &rawValues)
        return rawValues.compactMap { pointer in
            pointer.map { unsafeBitCast($0, to: IOHIDDevice.self) }
        }
    }

    private func stringProperty(_ device: IOHIDDevice, _ key: CFString) -> String? {
        IOHIDDeviceGetProperty(device, key) as? String
    }

    private func integerProperty(_ device: IOHIDDevice, _ key: CFString) -> Int? {
        (IOHIDDeviceGetProperty(device, key) as? NSNumber)?.intValue
    }

    private func propertyDescription(_ device: IOHIDDevice, _ key: CFString) -> String? {
        guard let value = IOHIDDeviceGetProperty(device, key) else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return String(describing: value)
    }

    private func deviceKey(_ device: IOHIDDevice) -> UInt {
        UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
    }

    private func describe(_ result: IOReturn) -> String {
        let status = String(format: "0x%08x", UInt32(bitPattern: result))
        guard let message = mach_error_string(result) else { return status }
        return "\(status) (\(String(cString: message)))"
    }

    private func quoted(_ value: String?) -> String {
        XM6HIDProbeSupport.quoted(value ?? "unavailable")
    }

    private func optionalHex(_ value: Int?, width: Int) -> String {
        value.map { hex($0, width: width) } ?? "unavailable"
    }

    private func hex<T: BinaryInteger>(_ value: T, width: Int = 0) -> String {
        String(format: "0x%0*llx", width, UInt64(value))
    }

    private func log(_ message: String) {
        diagnosticHandler("MuteHIDProbe: \(message)")
    }
}

private func xm6HIDManagerDeviceMatched(
    _ context: UnsafeMutableRawPointer?,
    _ result: IOReturn,
    _ sender: UnsafeMutableRawPointer?,
    _ device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<XM6HIDMuteProbe>.fromOpaque(context).takeUnretainedValue()
        .managerMatched(device, result: result)
}

private func xm6HIDDeviceRemoved(
    _ context: UnsafeMutableRawPointer?,
    _ result: IOReturn,
    _ sender: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let registration = Unmanaged<XM6HIDMuteProbe.DeviceRegistration>
        .fromOpaque(context).takeUnretainedValue()
    registration.owner?.removed(registration, result: result)
}

private func xm6HIDInputValue(
    _ context: UnsafeMutableRawPointer?,
    _ result: IOReturn,
    _ sender: UnsafeMutableRawPointer?,
    _ value: IOHIDValue
) {
    guard let context else { return }
    let registration = Unmanaged<XM6HIDMuteProbe.DeviceRegistration>
        .fromOpaque(context).takeUnretainedValue()
    registration.owner?.receivedValue(registration: registration, result: result, value: value)
}

private func xm6HIDInputReport(
    _ context: UnsafeMutableRawPointer?,
    _ result: IOReturn,
    _ sender: UnsafeMutableRawPointer?,
    _ type: IOHIDReportType,
    _ reportID: UInt32,
    _ report: UnsafeMutablePointer<UInt8>,
    _ reportLength: CFIndex
) {
    guard let context else { return }
    let registration = Unmanaged<XM6HIDMuteProbe.DeviceRegistration>
        .fromOpaque(context).takeUnretainedValue()
    // Copy only the bytes delivered by IOKit before returning from the callback.
    let reportedLength = max(0, reportLength)
    let safeLength = min(reportedLength, registration.reportBufferSize)
    let bytes = Array(UnsafeBufferPointer(start: report, count: safeLength))
    registration.owner?.receivedReport(
        registration: registration,
        result: result,
        type: type,
        reportID: reportID,
        reportedLength: reportedLength,
        bytes: bytes
    )
}
