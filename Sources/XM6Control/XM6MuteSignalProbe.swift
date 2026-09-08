import AVFAudio
import CoreAudio
import Foundation
import XM6ControlCore

/// Passive, opt-in diagnostics for public macOS headset mute signals.
///
/// This component never opens an audio device, reads samples, writes a mute
/// property, or creates an HFP gateway. It is intentionally independent of the
/// production microphone-mute state and overlay.
@MainActor
final class XM6MuteSignalProbe {
    private struct DeviceDescription {
        let id: AudioDeviceID
        let name: String
        let uid: String
        let inputChannels: UInt32
        let outputChannels: UInt32
    }

    private final class ListenerRegistration {
        let objectID: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
        private var isRemoved = false

        init(
            objectID: AudioObjectID,
            address: AudioObjectPropertyAddress,
            block: @escaping AudioObjectPropertyListenerBlock
        ) {
            self.objectID = objectID
            self.address = address
            self.block = block
        }

        func remove() {
            guard !isRemoved else { return }
            isRemoved = true
            var address = address
            AudioObjectRemovePropertyListenerBlock(objectID, &address, .main, block)
        }

        deinit {
            remove()
        }
    }

    private let diagnosticHandler: (String) -> Void
    private var notificationObserver: NSObjectProtocol?
    private var systemListeners: [ListenerRegistration] = []
    private var deviceListeners: [ListenerRegistration] = []
    private var started = false

    init(diagnosticHandler: @escaping (String) -> Void) {
        self.diagnosticHandler = diagnosticHandler
    }

    func start() {
        guard !started else { return }
        started = true
        log("started")
        startAVAudioApplicationProbe()
        startCoreAudioProbe()

        // The public IOBluetoothHandsFree classes only expose callbacks on a
        // client-created HFP object. Creating one would register/own a service-level
        // RFCOMM connection and could interfere with macOS's existing HFP session.
        log("Passive HFP observation not available through the public API without owning the connection")
    }

    func stop() {
        guard started else { return }
        started = false
        removeListeners(&deviceListeners)
        removeListeners(&systemListeners)
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
            self.notificationObserver = nil
        }
        if #available(macOS 14.0, *) {
            try? AVAudioApplication.shared.setInputMuteStateChangeHandler(nil)
        }
        log("stopped")
    }

    private func startAVAudioApplicationProbe() {
        guard #available(macOS 14.0, *) else {
            log("AVAudioApplication unavailable (requires macOS 14 or newer)")
            return
        }

        let application = AVAudioApplication.shared
        log("AVAudioApplication available (macOS 14+)")
        log("AVAudioApplication initial mute=\(application.isInputMuted)")

        notificationObserver = NotificationCenter.default.addObserver(
            forName: AVAudioApplication.inputMuteStateChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak application] notification in
            let reportedValue = (notification.userInfo?[AVAudioApplication.muteStateKey] as? NSNumber)?.boolValue
            let muted = reportedValue ?? application?.isInputMuted
            Task { @MainActor in
                if let muted {
                    self?.log("AVAudioApplication notification -> muted=\(muted)")
                } else {
                    self?.log("AVAudioApplication notification -> mute value unavailable")
                }
            }
        }

        do {
            try application.setInputMuteStateChangeHandler { [weak self] inputShouldBeMuted in
                Task { @MainActor in
                    self?.log("AVAudioApplication callback -> muted=\(inputShouldBeMuted)")
                }
                // Probe-only: report that this non-audio app did not apply muting.
                // Returning false avoids claiming that samples were changed.
                return false
            }
            log("AVAudioApplication input mute change handler installed (observation only)")
        } catch {
            log("AVAudioApplication input mute change handler unavailable: \(error.localizedDescription)")
        }
    }

    private func startCoreAudioProbe() {
        addListener(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address: propertyAddress(kAudioHardwarePropertyDevices),
            into: &systemListeners
        ) { [weak self] in
            self?.rebuildCoreAudioDeviceListeners()
        }
        rebuildCoreAudioDeviceListeners()
    }

    private func rebuildCoreAudioDeviceListeners() {
        guard started else { return }
        removeListeners(&deviceListeners)

        let devices = readXM6InputDevices()
        guard !devices.isEmpty else {
            log("CoreAudio no input-capable WH-1000XM6 device found")
            return
        }

        for device in devices {
            log(
                "CoreAudio XM6 device \"\(device.name)\" uid=\(device.uid) "
                    + "inputChannels=\(device.inputChannels) outputChannels=\(device.outputChannels)"
            )
            installMuteListeners(for: device)
        }
    }

    private func installMuteListeners(for device: DeviceDescription) {
        var availableElements: [AudioObjectPropertyElement] = []
        let candidates = XM6MuteSignalProbeSupport.inputMuteElements(
            inputChannelCount: device.inputChannels
        )

        for element in candidates {
            let address = propertyAddress(
                kAudioDevicePropertyMute,
                scope: kAudioObjectPropertyScopeInput,
                element: element
            )
            guard hasProperty(objectID: device.id, address: address) else { continue }
            availableElements.append(element)

            let elementDescription = describe(element: element)
            if let value = readUInt32(objectID: device.id, address: address) {
                log(
                    "CoreAudio input mute property available uid=\(device.uid) "
                        + "element=\(elementDescription) initial=\(value != 0)"
                )
            } else {
                log(
                    "CoreAudio input mute property available uid=\(device.uid) "
                        + "element=\(elementDescription) initial=unreadable"
                )
            }

            addListener(
                objectID: device.id,
                address: address,
                into: &deviceListeners
            ) { [weak self] in
                guard let self else { return }
                if let value = self.readUInt32(objectID: device.id, address: address) {
                    self.log(
                        "CoreAudio input mute changed uid=\(device.uid) "
                            + "element=\(elementDescription) -> \(value != 0)"
                    )
                } else {
                    self.log(
                        "CoreAudio input mute changed uid=\(device.uid) "
                            + "element=\(elementDescription) -> unreadable"
                    )
                }
            }
        }

        if availableElements.isEmpty {
            let checked = candidates.map(describe(element:)).joined(separator: ",")
            log("CoreAudio input mute property unavailable uid=\(device.uid) checkedElements=\(checked)")
        }
    }

    private func readXM6InputDevices() -> [DeviceDescription] {
        let deviceIDs = readObjectIDs(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address: propertyAddress(kAudioHardwarePropertyDevices)
        ) ?? []

        return deviceIDs.compactMap { deviceID in
            let name = readString(
                objectID: deviceID,
                address: propertyAddress(kAudioObjectPropertyName)
            ) ?? "?"
            let uid = readString(
                objectID: deviceID,
                address: propertyAddress(kAudioDevicePropertyDeviceUID)
            ) ?? "?"
            let modelUID = readString(
                objectID: deviceID,
                address: propertyAddress(kAudioDevicePropertyModelUID)
            ) ?? ""
            let manufacturer = readString(
                objectID: deviceID,
                address: propertyAddress(kAudioObjectPropertyManufacturer)
            ) ?? ""
            let inputChannels = channelCount(
                deviceID: deviceID,
                scope: kAudioObjectPropertyScopeInput
            )

            guard inputChannels > 0,
                  XM6MuteSignalProbeSupport.isXM6(
                    name: name,
                    uid: uid,
                    modelUID: modelUID,
                    manufacturer: manufacturer
                  ) else {
                return nil
            }

            return DeviceDescription(
                id: deviceID,
                name: name,
                uid: uid,
                inputChannels: inputChannels,
                outputChannels: channelCount(
                    deviceID: deviceID,
                    scope: kAudioObjectPropertyScopeOutput
                )
            )
        }.sorted {
            ($0.name, $0.uid, $0.id) < ($1.name, $1.uid, $1.id)
        }
    }

    private func channelCount(
        deviceID: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) -> UInt32 {
        var address = propertyAddress(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
              dataSize >= MemoryLayout<AudioBufferList>.size else {
            return 0
        }

        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }

        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            rawBuffer
        ) == noErr else {
            return 0
        }

        return UnsafeMutableAudioBufferListPointer(
            rawBuffer.assumingMemoryBound(to: AudioBufferList.self)
        ).reduce(0) { $0 + $1.mNumberChannels }
    }

    private func readObjectIDs(
        objectID: AudioObjectID,
        address requestedAddress: AudioObjectPropertyAddress
    ) -> [AudioObjectID]? {
        var address = requestedAddress
        guard AudioObjectHasProperty(objectID, &address) else { return nil }

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize) == noErr,
              dataSize % UInt32(MemoryLayout<AudioObjectID>.stride) == 0 else {
            return nil
        }
        guard dataSize > 0 else { return [] }

        var values = [AudioObjectID](
            repeating: kAudioObjectUnknown,
            count: Int(dataSize) / MemoryLayout<AudioObjectID>.stride
        )
        let status = values.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &dataSize,
                buffer.baseAddress!
            )
        }
        return status == noErr ? values : nil
    }

    private func readUInt32(
        objectID: AudioObjectID,
        address requestedAddress: AudioObjectPropertyAddress
    ) -> UInt32? {
        var address = requestedAddress
        guard AudioObjectHasProperty(objectID, &address) else { return nil }
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )
        return status == noErr ? value : nil
    }

    private func readString(
        objectID: AudioObjectID,
        address requestedAddress: AudioObjectPropertyAddress
    ) -> String? {
        var address = requestedAddress
        guard AudioObjectHasProperty(objectID, &address) else { return nil }
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private func addListener(
        objectID: AudioObjectID,
        address requestedAddress: AudioObjectPropertyAddress,
        into registrations: inout [ListenerRegistration],
        onChange: @escaping () -> Void
    ) {
        var address = requestedAddress
        guard AudioObjectHasProperty(objectID, &address) else { return }
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            onChange()
        }
        let status = AudioObjectAddPropertyListenerBlock(objectID, &address, .main, block)
        guard status == noErr else {
            log(
                "CoreAudio listener registration failed selector=\(fourCharacterCode(address.mSelector)) "
                    + "scope=\(fourCharacterCode(address.mScope)) element=\(address.mElement) status=\(status)"
            )
            return
        }
        registrations.append(
            ListenerRegistration(objectID: objectID, address: address, block: block)
        )
    }

    private func removeListeners(_ registrations: inout [ListenerRegistration]) {
        let oldRegistrations = registrations
        registrations.removeAll()
        oldRegistrations.forEach { $0.remove() }
    }

    private func hasProperty(
        objectID: AudioObjectID,
        address requestedAddress: AudioObjectPropertyAddress
    ) -> Bool {
        var address = requestedAddress
        return AudioObjectHasProperty(objectID, &address)
    }

    private func propertyAddress(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
    }

    private func describe(element: AudioObjectPropertyElement) -> String {
        element == kAudioObjectPropertyElementMain ? "main" : String(element)
    }

    private func fourCharacterCode(_ value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? String(value)
    }

    private func log(_ message: String) {
        diagnosticHandler("MuteProbe: \(message)")
    }
}
