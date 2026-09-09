import SwiftUI
import SonyHeadphonesKit
import XM6ControlCore

struct DashboardView: View {
    @EnvironmentObject private var controller: HeadphonesController
    @EnvironmentObject private var microphoneMuteIndicator: HardwareMicrophoneMuteIndicatorController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HeaderView()
                NoiseControlCard()
                ListeningModeCard()
                EqualizerCard()
                SpeakToChatCard()
                WearDetectionCard()
                ConnectionCard()

                HStack(spacing: 10) {
                    Button {
                        openWindow(id: "desktop-widget")
                    } label: {
                        Label("Widget", systemImage: "macwindow.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        controller.refreshState()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        controller.disconnect()
                    } label: {
                        Text("Disconnect")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)

                Text(footerText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(
                        "Show hardware mic mute indicator",
                        isOn: $microphoneMuteIndicator.isEnabled
                    )
                    Picker("Indicator location", selection: $microphoneMuteIndicator.location) {
                        Text("Near notch").tag(XM6MicrophoneIndicatorLocation.nearNotch)
                        Text("Menu bar icon").tag(XM6MicrophoneIndicatorLocation.menuBarIcon)
                    }
                    .disabled(!microphoneMuteIndicator.isEnabled)
                    if microphoneMuteIndicator.isEnabled,
                       microphoneMuteIndicator.isMicrophoneStateUnknown {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Microphone state unknown")
                            Text("Start a new microphone session to resync.")
                        }
                        .foregroundStyle(.secondary)
                    }
                    Toggle("Debug logging (protocol.log)", isOn: $controller.protocolLoggingEnabled)
                }
                .toggleStyle(.checkbox)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }

    private var footerText: String {
        switch controller.protocolVersion {
        case .v2: return "Connected \u{2022} Sony protocol v2"
        case .v1: return "Connected \u{2022} Sony protocol v1 (some features may be limited)"
        case .unknown: return "Connected \u{2022} protocol version not identified"
        }
    }
}
