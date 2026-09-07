import AppKit
import Combine
import SwiftUI
import XM6ControlCore
import SonyHeadphonesKit

/// Coordinates CoreAudio session truth with Sony's button-press event, owns the
/// inferred mute state, and presents the existing non-interactive overlay window.
@MainActor
final class HardwareMicrophoneMuteIndicatorController: ObservableObject {
    private static let preferenceKey = "showHardwareMicMuteIndicator"
    private static let indicatorSize = CGSize(width: 18, height: 18)

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.preferenceKey)
            updatePresentationForPreference()
        }
    }

    private let microphoneActivityMonitor: any XM6MicrophoneActivityProviding
    private let diagnosticHandler: (String) -> Void
    private var sessionState: XM6MicrophoneSessionState = .inactive
    private var isXM6InputActive = false
    private var connectionState: ConnectionState = .disconnected
    private var panel: MicrophoneMuteIndicatorPanel?
    private var hideTask: Task<Void, Never>?
    private var presentationGeneration = 0
    private var cancellables: Set<AnyCancellable> = []

    init(
        headphonesController: HeadphonesController,
        microphoneActivityMonitor: any XM6MicrophoneActivityProviding
    ) {
        isEnabled = UserDefaults.standard.bool(forKey: Self.preferenceKey)
        self.microphoneActivityMonitor = microphoneActivityMonitor
        diagnosticHandler = { [weak headphonesController] message in
            headphonesController?.logDiagnostic(message)
        }

        headphonesController.hardwareMicrophoneMuteButtonPressedPublisher
            .sink { [weak self] in
                guard let self else { return }
                self.handleButtonPress()
            }
            .store(in: &cancellables)

        headphonesController.$connectionState
            .sink { [weak self] connectionState in
                guard let self else { return }
                self.connectionState = connectionState
                self.synchronizeInputSession()
            }
            .store(in: &cancellables)

        microphoneActivityMonitor.inputActivityPublisher
            .sink { [weak self] active in
                guard let self else { return }
                self.isXM6InputActive = active
                self.synchronizeInputSession()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.repositionIfVisible()
            }
            .store(in: &cancellables)

        microphoneActivityMonitor.start()
    }

    private func updatePresentationForPreference() {
        guard isEnabled, connectionState == .connected else {
            cancelPendingPresentation()
            hideImmediately()
            return
        }

        if sessionState == .activeMuted {
            cancelPendingPresentation()
            show(color: .systemRed)
        } else {
            cancelPendingPresentation()
            hideImmediately()
        }
    }

    private func synchronizeInputSession() {
        let shouldBeActive = isXM6InputActive && connectionState == .connected
        if shouldBeActive, sessionState == .inactive {
            apply(.inputBecameActive)
        } else if !shouldBeActive, sessionState != .inactive {
            apply(.inputBecameInactive)
        }
    }

    private func handleButtonPress() {
        let wasInactive = sessionState == .inactive
        let transition = apply(.buttonPressed)
        if wasInactive {
            diagnosticHandler("Mic button pressed: ignored (input inactive)")
        } else if transition.state == .activeMuted {
            diagnosticHandler("Mic button pressed: inferred muted")
        } else if transition.state == .activeUnmuted {
            diagnosticHandler("Mic button pressed: inferred unmuted")
        }
    }

    @discardableResult
    private func apply(
        _ event: XM6MicrophoneSessionEvent
    ) -> XM6MicrophoneSessionTransition {
        let previousState = sessionState
        let transition = XM6MicrophoneSessionStateMachine.transition(
            from: previousState,
            event: event
        )
        sessionState = transition.state

        if event == .inputBecameInactive, previousState != .inactive {
            diagnosticHandler("CoreAudio: input session ended, clearing mute state")
        }

        present(transition.indicatorAction)
        return transition
    }

    private func present(_ action: XM6MicrophoneIndicatorAction) {
        switch action {
        case .none:
            return
        case .hide:
            cancelPendingPresentation()
            hideImmediately()
        case .showMuted:
            guard isEnabled, connectionState == .connected else { return }
            cancelPendingPresentation()
            show(color: .systemRed)
        case .showUnmuted:
            guard isEnabled, connectionState == .connected else { return }
            cancelPendingPresentation()
            show(color: .systemGreen)
            scheduleGreenHide(generation: presentationGeneration)
        }
    }

    private func cancelPendingPresentation() {
        presentationGeneration += 1
        hideTask?.cancel()
        hideTask = nil
    }

    private func show(color: NSColor) {
        let panel = panel ?? makePanel()
        self.panel = panel
        updateContent(of: panel, color: color)
        position(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    private func scheduleGreenHide(generation: Int) {
        hideTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return
            }
            guard let self, !Task.isCancelled,
                  generation == self.presentationGeneration else { return }
            self.fadeOut(generation: generation)
        }
    }

    private func fadeOut(generation: Int) {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                guard let self, let panel,
                      generation == self.presentationGeneration else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        }
    }

    private func hideImmediately() {
        panel?.orderOut(nil)
        panel?.alphaValue = 1
    }

    private func repositionIfVisible() {
        guard let panel, panel.isVisible else { return }
        position(panel)
    }

    private func makePanel() -> MicrophoneMuteIndicatorPanel {
        let panel = MicrophoneMuteIndicatorPanel(
            contentRect: NSRect(origin: .zero, size: Self.indicatorSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .none
        return panel
    }

    private func updateContent(of panel: NSPanel, color: NSColor) {
        panel.contentView = NSHostingView(
            rootView: HardwareMicrophoneMuteIndicatorView(color: Color(nsColor: color))
        )
    }

    private func position(_ panel: NSPanel) {
        guard let screen = targetScreen() else {
            panel.orderOut(nil)
            return
        }

        let origin: CGPoint
        if isNotched(screen),
           let rightAuxiliaryArea = screen.auxiliaryTopRightArea,
           !rightAuxiliaryArea.isEmpty {
            origin = CGPoint(
                x: min(rightAuxiliaryArea.minX + 4, rightAuxiliaryArea.maxX - Self.indicatorSize.width),
                y: rightAuxiliaryArea.midY - Self.indicatorSize.height / 2
            )
        } else if isNotched(screen),
                  let leftAuxiliaryArea = screen.auxiliaryTopLeftArea,
                  !leftAuxiliaryArea.isEmpty {
            origin = CGPoint(
                x: max(leftAuxiliaryArea.maxX - Self.indicatorSize.width - 4, leftAuxiliaryArea.minX),
                y: leftAuxiliaryArea.midY - Self.indicatorSize.height / 2
            )
        } else {
            let topAreaHeight = max(NSStatusBar.system.thickness, screen.frame.maxY - screen.visibleFrame.maxY)
            origin = CGPoint(
                x: screen.frame.midX - Self.indicatorSize.width / 2,
                y: screen.frame.maxY - topAreaHeight / 2 - Self.indicatorSize.height / 2
            )
        }
        panel.setFrameOrigin(origin)
    }

    private func targetScreen() -> NSScreen? {
        let notchedScreens = NSScreen.screens
            .filter(isNotched)
            .sorted {
                ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY)
            }
        return notchedScreens.first ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func isNotched(_ screen: NSScreen) -> Bool {
        let hasLeftAuxiliaryArea = screen.auxiliaryTopLeftArea?.isEmpty == false
        let hasRightAuxiliaryArea = screen.auxiliaryTopRightArea?.isEmpty == false
        return screen.safeAreaInsets.top > 0 && (hasLeftAuxiliaryArea || hasRightAuxiliaryArea)
    }
}

private final class MicrophoneMuteIndicatorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct HardwareMicrophoneMuteIndicatorView: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.45), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
            .frame(width: 9, height: 9)
            .frame(width: 18, height: 18)
    }
}
