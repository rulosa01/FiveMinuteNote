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
    }

    func applicationWillTerminate(_ notification: Notification) {
        iconTimer?.invalidate()
        iconTimer = nil

        unregisterHotKey()
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
            button.sendAction(on: [.leftMouseUp])
            button.target = self
        }
    }

    @objc func statusItemClicked() {
        showStatusMenu()
    }

    func showStatusMenu() {
        let menu = NSMenu()
        let prefs = PreferencesManager.shared

        // Show/Hide note
        let isVisible = noteWindow?.isVisible == true
        let showItem = NSMenuItem(title: isVisible ? "Hide Note" : "Show Note", action: #selector(toggleNoteWindowAction), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        // Hotkey section
        let hotkeyLabel = NSMenuItem(title: "Hotkey: \(prefs.hotkeyDisplayString())", action: nil, keyEquivalent: "")
        hotkeyLabel.isEnabled = false
        menu.addItem(hotkeyLabel)

        let changeHotkey = NSMenuItem(title: "Change Hotkey…", action: #selector(showHotkeyRecorder), keyEquivalent: "")
        changeHotkey.target = self
        menu.addItem(changeHotkey)

        menu.addItem(NSMenuItem.separator())

        // Color section
        let colorItem = NSMenuItem(title: "Window Color…", action: #selector(showColorPicker), keyEquivalent: "")
        colorItem.target = self
        menu.addItem(colorItem)

        let resetItem = NSMenuItem(title: "Reset Color", action: #selector(resetWindowColor), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Five Minute Note", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func toggleNoteWindowAction() {
        toggleNoteWindow()
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
        registerHotKey()
    }

    @discardableResult
    private func registerHotKey() -> OSStatus {
        let prefs = PreferencesManager.shared
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x464D4E45), // "FMNE"
            id: 1
        )
        return RegisterEventHotKey(
            prefs.hotkeyKeyCode,
            prefs.hotkeyModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func unregisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    // MARK: - Hotkey Recorder
    @objc func showHotkeyRecorder() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Record Hotkey"
        panel.level = .floating
        panel.center()

        let label = NSTextField(labelWithString: "Press your desired key combination…")
        label.font = .systemFont(ofSize: 14)
        label.alignment = .center
        label.frame = NSRect(x: 20, y: 45, width: 260, height: 30)

        let sublabel = NSTextField(labelWithString: "Must include \u{2318}, \u{2303}, or \u{2325}")
        sublabel.font = .systemFont(ofSize: 11)
        sublabel.textColor = .secondaryLabelColor
        sublabel.alignment = .center
        sublabel.frame = NSRect(x: 20, y: 20, width: 260, height: 20)

        panel.contentView?.addSubview(label)
        panel.contentView?.addSubview(sublabel)

        var monitor: Any?
        var closeObserver: NSObjectProtocol?

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasRequired = modifiers.contains(.command)
                || modifiers.contains(.control)
                || modifiers.contains(.option)

            guard hasRequired else {
                NSSound.beep()
                return nil
            }

            let prefs = PreferencesManager.shared
            let previousKeyCode = prefs.hotkeyKeyCode
            let previousModifiers = prefs.hotkeyModifiers

            let carbonMods = PreferencesManager.carbonModifiers(from: modifiers)
            let newKeyCode = UInt32(event.keyCode)

            // Skip if unchanged
            if newKeyCode == previousKeyCode && carbonMods == previousModifiers {
                if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
                if let obs = closeObserver { NotificationCenter.default.removeObserver(obs); closeObserver = nil }
                panel.close()
                return nil
            }

            prefs.hotkeyKeyCode = newKeyCode
            prefs.hotkeyModifiers = carbonMods

            self.unregisterHotKey()
            let status = self.registerHotKey()

            if status != noErr {
                // Revert on failure
                prefs.hotkeyKeyCode = previousKeyCode
                prefs.hotkeyModifiers = previousModifiers
                self.registerHotKey()

                let alert = NSAlert()
                alert.messageText = "Could not register hotkey"
                alert.informativeText = "This key combination may be in use by another application."
                alert.runModal()
            }

            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            if let obs = closeObserver { NotificationCenter.default.removeObserver(obs); closeObserver = nil }
            panel.close()
            return nil
        }

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { _ in
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            if let obs = closeObserver { NotificationCenter.default.removeObserver(obs); closeObserver = nil }
        }

        activateApp()
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - Window Color
    @objc func showColorPicker() {
        let colorPanel = NSColorPanel.shared
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(colorDidChange(_:)))
        colorPanel.color = PreferencesManager.shared.windowColor
        activateApp()
        colorPanel.makeKeyAndOrderFront(nil)

        // Position near the menubar icon
        if let buttonFrame = statusItem.button?.window?.frame {
            let x = buttonFrame.midX - colorPanel.frame.width / 2
            let y = buttonFrame.minY - colorPanel.frame.height - 4
            colorPanel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    @objc func colorDidChange(_ sender: NSColorPanel) {
        let color = sender.color
        PreferencesManager.shared.windowColor = color
        noteWindow?.backgroundColor = color
    }

    @objc func resetWindowColor() {
        PreferencesManager.shared.resetWindowColor()
        noteWindow?.backgroundColor = .windowBackgroundColor
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
        .environmentObject(PreferencesManager.shared)

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
        window.backgroundColor = PreferencesManager.shared.windowColor

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
