import SwiftUI
import Carbon.HIToolbox

// MARK: - Hardcoded Config
let defaultTimerMinutes: Int = 5

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
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock (belt-and-suspenders with Info.plist LSUIElement)
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupGlobalHotKey()

        // Show window on first launch
        showNoteWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        iconTimer?.invalidate()
        iconTimer = nil

        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    // MARK: - Status Item
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon()

        if let button = statusItem.button {
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }
    }

    @objc func statusItemClicked() {
        guard let event = NSApp.currentEvent else {
            toggleNoteWindow()
            return
        }
        let isRightClick = event.type == .rightMouseUp
            || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
        if isRightClick {
            showStatusMenu()
        } else {
            toggleNoteWindow()
        }
    }

    func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Five Minute Note", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Clear the menu so left-click goes back to toggle behavior
        statusItem.menu = nil
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
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
            // Static "5" icon
            button.image = drawFiveIcon()

            // No active note or past the pie animation window — stop ticking
            if !state.hasActiveNote {
                stopIconTimer()
            }
        }
    }

    func drawFiveIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let font = NSFont.systemFont(ofSize: 14, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black,
            ]
            let str = NSAttributedString(string: "5", attributes: attrs)
            let textSize = str.size()
            let x = (rect.width - textSize.width) / 2
            let y = (rect.height - textSize.height) / 2
            str.draw(at: NSPoint(x: x, y: y))
            return true
        }
        image.isTemplate = true
        return image
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

    // MARK: - Global Hot Key (Carbon RegisterEventHotKey — no Accessibility permission needed)
    func setupGlobalHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus in
                guard let event = event, let userData = userData else {
                    return OSStatus(eventNotHandledErr)
                }
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard err == noErr else { return OSStatus(eventNotHandledErr) }

                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    delegate.toggleNoteWindow()
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        guard status == noErr else { return }

        // Register Cmd+Shift+Space
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x464D4E45), // "FMNE"
            id: 1
        )
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
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
