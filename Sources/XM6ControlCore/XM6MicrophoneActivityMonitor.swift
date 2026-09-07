import Combine
import CoreAudio
import Foundation

/// The narrow boundary consumed by app coordination. Tests can provide a fake and
/// exercise session behavior without touching CoreAudio or real headphones.
@MainActor
public protocol XM6MicrophoneActivityProviding: AnyObject {
    var isInputActive: Bool { get }
    var inputActivityPublisher: AnyPublisher<Bool, Never> { get }
    func start()
    func stop()
}

/// Observes public CoreAudio HAL metadata only. It never creates an IOProc, opens an
/// input unit, or reads audio samples, so it does not request microphone permission.
///
/// The primary path correlates a process whose `isRunningInput` property is true with
/// that process's input-scoped device list. On older HALs that do not expose process
/// objects, the only fallback accepted is `DeviceIsRunningSomewhere` on a CoreAudio
/// input-only XM6 endpoint; a duplex device is deliberately treated as unsupported to
/// avoid mistaking playback for microphone activity.
@MainActor
public final class XM6MicrophoneActivityMonitor: ObservableObject, XM6MicrophoneActivityProviding {
    @Published public private(set) var isInputActive = false

    public var inputActivityPublisher: AnyPublisher<Bool, Never> {
        $isInputActive.eraseToAnyPublisher()
    }

    private struct DeviceDescription: Equatable {
        let id: AudioDeviceID
        let name: String
        let uid: String
        let inputChannels: UInt32
        let outputChannels: UInt32

        var isInputOnly: Bool {
            inputChannels > 0 && outputChannels == 0
        }
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
    private var systemListeners: [ListenerRegistration] = []
    private var processListeners: [ListenerRegistration] = []
    private var fallbackDeviceListeners: [ListenerRegistration] = []
    private var xm6InputDevices: [DeviceDescription] = []
    private var started = false
    private var hasReportedActivity = false
    private var lastTopologyDiagnostic: String?

    public init(diagnosticHandler: @escaping (String) -> Void = { _ in }) {
        self.diagnosticHandler = diagnosticHandler
    }

    public func start() {
        guard !started else { return }
        started = true
        installSystemListeners()
        rebuildTopology()
    }

    public func stop() {
        guard started else { return }
        started = false
        removeListeners(&fallbackDeviceListeners)
        removeListeners(&processListeners)
        removeListeners(&systemListeners)
        xm6InputDevices = []
        setActivity(false)
    }

    private var supportsProcessObservation: Bool {
        hasProperty(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address: propertyAddress(kAudioHardwarePropertyProcessObjectList)
        )
    }

    private func installSystemListeners() {
        addListener(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address: propertyAddress(kAudioHardwarePropertyDevices),
            into: &systemListeners
        ) { [weak self] in
            self?.rebuildTopology()
        }

        let processListAddress = propertyAddress(kAudioHardwarePropertyProcessObjectList)
        if hasProperty(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address: processListAddress
        ) {
            addListener(
                objectID: AudioObjectID(kAudioObjectSystemObject),
                address: processListAddress,
                into: &systemListeners
            ) { [weak self] in
                self?.rebuildProcessListenersAndRefresh()
            }
        }
    }

    private func rebuildTopology() {
        guard started else { return }
        xm6InputDevices = readXM6InputDevices()

        let deviceSummary: String
        if xm6InputDevices.isEmpty {
            deviceSummary = "no input-capable WH-1000XM6 device found"
        } else {
            deviceSummary = xm6InputDevices.map {
                "\($0.name) [uid=\($0.uid), input=\($0.inputChannels), output=\($0.outputChannels)]"
            }.joined(separator: ", ")
        }

        if supportsProcessObservation {
            logTopologyOnce("CoreAudio: process input monitoring; \(deviceSummary)")
            removeListeners(&fallbackDeviceListeners)
            rebuildProcessListenersAndRefresh()
        } else {
            removeListeners(&processListeners)
            rebuildFallbackListenersAndRefresh(deviceSummary: deviceSummary)
        }
    }

    private func rebuildProcessListenersAndRefresh() {
        guard started, supportsProcessObservation else { return }
        removeListeners(&processListeners)

        let processIDs = readObjectIDs(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address: propertyAddress(kAudioHardwarePropertyProcessObjectList)
        ) ?? []

        for processID in processIDs {
            addListener(
                objectID: processID,
                address: propertyAddress(kAudioProcessPropertyIsRunningInput),
                into: &processListeners
            ) { [weak self] in
                self?.refreshActivity()
            }
            addListener(
                objectID: processID,
                address: propertyAddress(
                    kAudioProcessPropertyDevices,
                    scope: kAudioObjectPropertyScopeInput
                ),
                into: &processListeners
            ) { [weak self] in
                self?.refreshActivity()
            }
        }

        refreshActivity()
    }

    private func rebuildFallbackListenersAndRefresh(deviceSummary: String) {
        removeListeners(&fallbackDeviceListeners)
        let eligibleDevices = xm6InputDevices.filter(\.isInputOnly)

        if eligibleDevices.isEmpty {
            let reason = xm6InputDevices.isEmpty
                ? deviceSummary
                : "XM6 endpoint is duplex; refusing DeviceIsRunningSomewhere fallback"
            logTopologyOnce("CoreAudio: process input properties unavailable; \(reason)")
            setActivity(false)
            return
        }

        logTopologyOnce("CoreAudio: input-only endpoint fallback; \(deviceSummary)")
        for device in eligibleDevices {
            addListener(
                objectID: device.id,
                address: propertyAddress(kAudioDevicePropertyDeviceIsRunningSomewhere),
                into: &fallbackDeviceListeners
            ) { [weak self] in
                self?.refreshActivity()
            }
        }
        refreshActivity()
    }

    private func refreshActivity() {
        guard started else { return }
        let active: Bool
        if supportsProcessObservation {
            active = isAnyProcessUsingXM6Input()
        } else {
            active = xm6InputDevices
                .filter(\.isInputOnly)
                .contains { device in
                    readUInt32(
                        objectID: device.id,
                        address: propertyAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
                    ) == 1
                }
        }
        setActivity(active)
    }

    private func isAnyProcessUsingXM6Input() -> Bool {
        let xm6DeviceIDs = Set(xm6InputDevices.map(\.id))
        guard !xm6DeviceIDs.isEmpty else { return false }

        let processIDs = readObjectIDs(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address: propertyAddress(kAudioHardwarePropertyProcessObjectList)
        ) ?? []

        return processIDs.contains { processID in
            guard readUInt32(
                objectID: processID,
                address: propertyAddress(kAudioProcessPropertyIsRunningInput)
            ) == 1 else {
                return false
            }

            let inputDevices = readObjectIDs(
                objectID: processID,
                address: propertyAddress(
                    kAudioProcessPropertyDevices,
                    scope: kAudioObjectPropertyScopeInput
                )
            ) ?? []
            return inputDevices.contains(where: xm6DeviceIDs.contains)
        }
    }

    private func setActivity(_ active: Bool) {
        guard !hasReportedActivity || isInputActive != active else { return }
        hasReportedActivity = true
        isInputActive = active
        diagnosticHandler("CoreAudio: XM6 input \(active ? "active" : "inactive")")
    }

    private func logTopologyOnce(_ message: String) {
        guard lastTopologyDiagnostic != message else { return }
        lastTopologyDiagnostic = message
        diagnosticHandler(message)
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
            let inputChannels = channelCount(deviceID: deviceID, scope: kAudioObjectPropertyScopeInput)
            guard inputChannels > 0,
                  isXM6(name: name, uid: uid, modelUID: modelUID, manufacturer: manufacturer) else {
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

    private func isXM6(
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

    private func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
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

        let audioBufferList = rawBuffer.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(audioBufferList)
            .reduce(0) { $0 + $1.mNumberChannels }
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
        guard AudioObjectAddPropertyListenerBlock(objectID, &address, .main, block) == noErr else {
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
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
