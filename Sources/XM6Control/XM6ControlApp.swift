import AppKit
import SwiftUI
import XM6ControlCore
import SonyHeadphonesKit

@main
struct XM6ControlApp: App {
    @StateObject private var controller: HeadphonesController
    @StateObject private var microphoneMuteIndicator: HardwareMicrophoneMuteIndicatorController

    init() {
        let controller = HeadphonesController()
        let microphoneActivityMonitor = XM6MicrophoneActivityMonitor { [weak controller] message in
            controller?.logDiagnostic(message)
        }
        _controller = StateObject(wrappedValue: controller)
        _microphoneMuteIndicator = StateObject(
            wrappedValue: HardwareMicrophoneMuteIndicatorController(
                headphonesController: controller,
                microphoneActivityMonitor: microphoneActivityMonitor
            )
        )
        ProbeMode.runIfRequested()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(controller)
                .environmentObject(microphoneMuteIndicator)
                .frame(minWidth: 380, idealWidth: 420, minHeight: 560, idealHeight: 680)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        // Menu bar controls: always one click away, even with the main window closed.
        // Icon-only label: the title+systemImage form reserves layout space for the
        // (invisible) title text, leaving an odd gap next to the icon.
        MenuBarExtra {
            CompactControlsView()
                .environmentObject(controller)
                .environmentObject(microphoneMuteIndicator)
        } label: {
            MenuBarHeadphonesIcon(indicator: microphoneMuteIndicator)
        }
        .menuBarExtraStyle(.window)

        // Floating desktop widget, opened from the main window or the menu bar panel.
        Window("XM6 Widget", id: "desktop-widget") {
            DesktopWidgetView()
                .environmentObject(controller)
                .environmentObject(microphoneMuteIndicator)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
    }
}

private struct MenuBarHeadphonesIcon: View {
    @ObservedObject var indicator: HardwareMicrophoneMuteIndicatorController
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    var body: some View {
        if indicator.menuBarAppearance == .hidden {
            Image(systemName: "headphones.circle.fill")
        } else {
            Image(nsImage: activeIconImage)
                .renderingMode(.original)
        }
    }

    /// MenuBarExtra templates its final label, including child overlays. Rendering the
    /// complete active icon as one original image is what preserves the badge color.
    private var activeIconImage: NSImage {
        let color: NSColor
        switch indicator.menuBarAppearance {
        case .hidden: color = .clear
        case .muted: color = .systemRed
        case .unmuted: color = .systemGreen
        case .unknown: color = .systemGray
        }

        let artwork = ZStack(alignment: .bottomTrailing) {
            Image(systemName: "headphones.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
            if indicator.menuBarAppearance == .unknown {
                ZStack {
                    Circle().fill(Color(nsColor: color))
                    Text("?")
                        .font(.system(size: 5, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 7, height: 7)
            } else {
                Circle()
                    .fill(Color(nsColor: color))
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.95), lineWidth: 1)
                    }
                    .frame(width: 7, height: 7)
            }
        }
        .frame(width: 16, height: 16)

        let renderer = ImageRenderer(content: artwork)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 16, height: 16))
        image.isTemplate = false
        return image
    }
}
