import Testing
@testable import XM6ControlCore

struct XM6HIDProbeSupportTests {
    @Test func probeIsEnabledOnlyByExactLaunchArgument() {
        #expect(
            XM6HIDProbeSupport.isEnabled(
                arguments: ["XM6Control", "--hid-mute-probe"]
            )
        )
        #expect(
            !XM6HIDProbeSupport.isEnabled(
                arguments: ["XM6Control", "--hid-mute-probe=true"]
            )
        )
    }

    @Test func candidateIdentityNormalizesKnownXM6Forms() {
        #expect(
            XM6HIDProbeSupport.isCandidate(
                .init(product: "WH-1000XM6", manufacturer: "Sony Corporation")
            )
        )
        #expect(
            XM6HIDProbeSupport.isCandidate(
                .init(product: "Headset", serialNumber: "wh_1000-xm6")
            )
        )
        #expect(
            !XM6HIDProbeSupport.isCandidate(
                .init(
                    product: "Wireless Controller",
                    manufacturer: "Sony",
                    transport: "Bluetooth",
                    vendorID: 0x054c
                )
            )
        )
        #expect(
            !XM6HIDProbeSupport.isCandidate(
                .init(product: "WH-1000XM5", manufacturer: "Sony")
            )
        )
    }

    @Test func bluetoothMetadataMatchingIsCaseAndPunctuationInsensitive() {
        #expect(XM6HIDProbeSupport.isBluetooth(.init(transport: "Bluetooth Low Energy")))
        #expect(XM6HIDProbeSupport.isBluetooth(.init(transport: "bluetooth-le")))
        #expect(!XM6HIDProbeSupport.isBluetooth(.init(transport: "USB")))
    }

    @Test func reportFormattingIsBoundedAndMarksTruncation() {
        #expect(
            XM6HIDProbeSupport.formatReport([0x00, 0xab, 0xff])
                == "00 ab ff"
        )
        #expect(
            XM6HIDProbeSupport.formatReport([0x00, 0xab, 0xff], maximumBytes: 2)
                == "00 ab [truncated 1 bytes]"
        )
    }

    @Test func reportBufferSizeUsesFallbackAndSafetyCap() {
        #expect(XM6HIDProbeSupport.reportBufferSize(reportedSize: 64) == 64)
        #expect(XM6HIDProbeSupport.reportBufferSize(reportedSize: nil) == 1_024)
        #expect(XM6HIDProbeSupport.reportBufferSize(reportedSize: 100_000) == 16_384)
        #expect(XM6HIDProbeSupport.reportBufferSize(reportedSize: 0) == 1)
    }

    @Test func quotedMetadataCannotInjectExtraLogLines() {
        #expect(XM6HIDProbeSupport.quoted("XM6\nFake: event") == "\"XM6\\nFake: event\"")
    }
}
