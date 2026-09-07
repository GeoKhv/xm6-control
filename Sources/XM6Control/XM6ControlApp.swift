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
        } label: {
            Image(systemName: "headphones.circle.fill")
        }
        .menuBarExtraStyle(.window)

        // Floating desktop widget, opened from the main window or the menu bar panel.
        Window("XM6 Widget", id: "desktop-widget") {
            DesktopWidgetView()
                .environmentObject(controller)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
    }
}
