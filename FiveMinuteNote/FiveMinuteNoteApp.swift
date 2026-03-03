import SwiftUI
import Carbon.HIToolbox

// MARK: - Hardcoded Config
let defaultTimerMinutes: Int = 5
// Hotkey: Cmd+Shift+Space
let hotkeyModifiers: CGEventFlags = [.maskCommand, .maskShift]
let hotkeyKeyCode: Int64 = Int64(kVK_Space)

@main
struct FiveMinuteNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var noteWindow: NotePanel?
    var noteState = NoteState.shared
    private var iconTimer: Timer?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var accessibilityPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock (belt-and-suspenders with Info.plist LSUIElement)
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        requestAccessibilityAndSetupHotKey()

        // Show window on first launch
        showNoteWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // #7: Clean up all resources
        iconTimer?.invalidate()
        iconTimer = nil
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Status Item
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon()

        if let button = statusItem.button {
            button.action = #selector(statusItemClicked)
            button.target = self
        }
    }

    @objc func statusItemClicked() {
        toggleNoteWindow()
    }

    // #4: Only start icon timer when note is active, stop when not needed
    func startIconTimerIfNeeded() {
        guard iconTimer == nil else { return }
        iconTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateStatusIcon()
        }
    }

    func stopIconTimer() {
        iconTimer?.invalidate()
        iconTimer = nil
    }

    func updateStatusIcon() {
        guard let button = statusItem.button else { return }

        let state = noteState
        let remaining = state.timeRemaining

        if state.hasActiveNote && remaining <= 60 && remaining > 0 {
            // Draw pie/arc icon
            let fraction = remaining / 60.0
            let image = drawPieIcon(fraction: fraction)
            button.image = image
        } else {
            // Static hourglass icon
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Five Minute Note")
            button.image = image?.withSymbolConfiguration(config)

            // No active note or past the pie animation window — stop ticking
            if !state.hasActiveNote {
                stopIconTimer()
            }
        }
    }

    // #12: Draw with solid black, let isTemplate handle appearance adaptation
    func drawPieIcon(fraction: Double) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 7.0

            // Draw filled arc representing remaining time
            let startAngle: CGFloat = 90 // 12 o'clock
            let endAngle: CGFloat = startAngle - CGFloat(fraction * 360)

            let path = NSBezierPath()
            path.move(to: center)
            path.appendArc(withCenter: center, radius: radius,
                          startAngle: startAngle, endAngle: endAngle, clockwise: true)
            path.close()

            NSColor.black.setFill()
            path.fill()

            // Draw thin circle outline
            let outline = NSBezierPath(ovalIn: NSRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            ))
            NSColor.black.withAlphaComponent(0.3).setStroke()
            outline.lineWidth = 0.75
            outline.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Global Hot Key (CGEvent tap with Accessibility prompt)
    func requestAccessibilityAndSetupHotKey() {
        // Prompt for Accessibility permission if not yet granted
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if trusted {
            setupGlobalHotKey()
        } else {
            // Poll until permission is granted
            accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    self?.accessibilityPollTimer = nil
                    self?.setupGlobalHotKey()
                }
            }
        }
    }

    func setupGlobalHotKey() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                // #1: Use passUnretained for pass-through to avoid CGEvent leak
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                return delegate.handleGlobalKeyEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap")
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // #1: passUnretained for all pass-through returns
    func handleGlobalKeyEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if it gets disabled by the system
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Check for Cmd+Shift+Space
        let hasCmd = flags.contains(.maskCommand)
        let hasShift = flags.contains(.maskShift)
        let hasCtrl = flags.contains(.maskControl)
        let hasOpt = flags.contains(.maskAlternate)

        if keyCode == hotkeyKeyCode && hasCmd && hasShift && !hasCtrl && !hasOpt {
            DispatchQueue.main.async { [weak self] in
                self?.toggleNoteWindow()
            }
            return nil // Consume the event
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Window Management
    func toggleNoteWindow() {
        if let window = noteWindow, window.isVisible {
            hideNoteWindow()
        } else {
            showNoteWindow()
        }
    }

    // #13: Helper for activate that handles deprecation
    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func showNoteWindow() {
        if let window = noteWindow {
            window.makeKeyAndOrderFront(nil)
            activateApp()
            if !noteState.hasActiveNote {
                noteState.startNewNote()
                startIconTimerIfNeeded()
            }
            return
        }

        // Create new window
        // #18: Pass hideNoteWindow as the Escape handler
        let contentView = NoteContentView(
            onClose: { [weak self] in self?.hideNoteWindow() },
            onNoteDied: { [weak self] in self?.onNoteDied() }
        )
        .environmentObject(noteState)

        let window = NotePanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // #18: Route Escape through hideNoteWindow
        window.onEscape = { [weak self] in
            self?.hideNoteWindow()
        }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.backgroundColor = .windowBackgroundColor

        // Center on screen initially
        window.center()

        window.makeKeyAndOrderFront(nil)
        activateApp()

        self.noteWindow = window

        // Start a new note if there isn't an active one
        if !noteState.hasActiveNote {
            noteState.startNewNote()
            startIconTimerIfNeeded()
        }
    }

    func hideNoteWindow() {
        noteWindow?.orderOut(nil)
    }

    func onNoteDied() {
        noteWindow?.orderOut(nil)
        noteState.clearNote()
        // #16: Clear the undo buffer so Cmd+Z can't recover destroyed text
        if let textView = (noteWindow?.contentView as? NSHostingView<AnyView>)?.subviews
            .compactMap({ $0 as? NSScrollView }).first?.documentView as? NSTextView {
            textView.undoManager?.removeAllActions()
        }
        // Also clear via the text view in the window's view hierarchy
        clearUndoBuffer()
        updateStatusIcon()
        stopIconTimer()
    }

    // #16: Walk the view hierarchy to find and clear the NSTextView's undo manager
    private func clearUndoBuffer() {
        guard let contentView = noteWindow?.contentView else { return }
        func findTextView(in view: NSView) -> NSTextView? {
            if let tv = view as? NSTextView { return tv }
            for subview in view.subviews {
                if let tv = findTextView(in: subview) { return tv }
            }
            return nil
        }
        findTextView(in: contentView)?.undoManager?.removeAllActions()
    }
}

// MARK: - Custom NSPanel for key handling
class NotePanel: NSPanel {
    // #18: Closure so Escape routes through the proper hideNoteWindow path
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape key
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}
