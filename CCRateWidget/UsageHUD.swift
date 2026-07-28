import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A floating panel summoned by a global hotkey (⌥⌘U) that fades itself out.
///
/// Carbon's RegisterEventHotKey is used rather than NSEvent.addGlobalMonitorForEvents
/// because the latter requires Accessibility permission — a system prompt and a trip to
/// System Settings, for a read-only glance at your own usage. Carbon needs no permission
/// and still works on macOS 14+, deprecation notices notwithstanding.
@MainActor
final class UsageHUD {
    static let shared = UsageHUD()

    private var panel: NSPanel?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var hideWorkItem: DispatchWorkItem?
    private var escMonitor: Any?

    /// Seconds on screen before fading out. Long enough to read three numbers.
    private let visibleDuration: TimeInterval = 3.0

    private init() {}

    // MARK: - Hotkey registration

    func registerHotKeyIfEnabled() {
        guard SettingsStore.shared.hotkeyEnabled else { return }
        registerHotKey()
    }

    func registerHotKey() {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in UsageHUD.shared.toggle() }
            return noErr
        }, 1, &eventType, nil, &handlerRef)

        // ⌥⌘U — U for usage; ⌥⌘ avoids the crowded ⌃⌘ and ⇧⌘ spaces.
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x43525721), id: 1)   // 'CRW!'
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_U),
                                         UInt32(optionKey | cmdKey),
                                         id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRef = ref
        } else {
            NSLog("[UsageHUD] hotkey registration failed: \(status)")
        }
    }

    func unregisterHotKey() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    // MARK: - Presentation

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        AggregationCoordinator.shared.runOnce()   // freshen while it fades in

        let content = UsagePopover(
            onDismiss: { [weak self] in self?.hide() },
            cornerRadius: 14          // the panel is transparent; the content is the shape
        )

        let hosting = NSHostingController(rootView: content)
        hosting.view.appearance = NSApp.effectiveAppearance
        let p = panel ?? makePanel()
        p.contentViewController = hosting
        p.setContentSize(hosting.view.fittingSize)
        centerOnActiveScreen(p)

        p.alphaValue = 0
        p.orderFrontRegardless()
        // The panel is transparent, so its shadow is derived from the rendered content.
        // Without invalidating, a reused panel keeps the previous frame's shadow shape.
        p.invalidateShadow()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            p.animator().alphaValue = 1
        }
        panel = p

        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.hide(); return nil }   // Esc
            return event
        }

        scheduleAutoHide()
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = nil

        guard let p = panel, p.isVisible else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            p.animator().alphaValue = 0
        } completionHandler: {
            p.orderOut(nil)
        }
    }

    /// Auto-dismiss, but not while the pointer is over the panel — grabbing for it as it
    /// vanishes is the most annoying failure mode a transient HUD has.
    private func scheduleAutoHide() {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let p = self.panel else { return }
            let mouseInside = p.frame.contains(NSEvent.mouseLocation)
            if mouseInside {
                self.scheduleAutoHide()      // wait for them to move away
            } else {
                self.hide()
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + visibleDuration, execute: work)
    }

    // MARK: - Panel

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero,
                        styleMask: [.nonactivatingPanel, .fullSizeContentView],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        // Show over full-screen spaces — the case where reaching for the menu bar is
        // exactly what you can't do.
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return p
    }

    private func centerOnActiveScreen(_ p: NSPanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = p.frame.size
        // Slightly above centre: centred panels sit lower than the eye expects.
        let origin = NSPoint(x: visible.midX - size.width / 2,
                             y: visible.midY - size.height / 2 + visible.height * 0.08)
        p.setFrameOrigin(origin)
    }
}
