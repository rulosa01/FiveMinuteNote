import SwiftUI
import Carbon.HIToolbox

class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    // MARK: - UserDefaults Keys
    private enum Keys {
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let windowColorData = "windowColorData"
    }

    // MARK: - Hotkey
    var hotkeyKeyCode: UInt32 {
        get {
            if UserDefaults.standard.object(forKey: Keys.hotkeyKeyCode) != nil {
                return UInt32(UserDefaults.standard.integer(forKey: Keys.hotkeyKeyCode))
            }
            return UInt32(kVK_Space)
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: Keys.hotkeyKeyCode) }
    }

    var hotkeyModifiers: UInt32 {
        get {
            if UserDefaults.standard.object(forKey: Keys.hotkeyModifiers) != nil {
                return UInt32(UserDefaults.standard.integer(forKey: Keys.hotkeyModifiers))
            }
            return UInt32(cmdKey | shiftKey)
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: Keys.hotkeyModifiers) }
    }

    // MARK: - Window Color
    @Published var windowColor: NSColor {
        didSet { saveWindowColor() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Keys.windowColorData),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            self.windowColor = color
        } else {
            self.windowColor = .windowBackgroundColor
        }
    }

    private func saveWindowColor() {
        if let data = try? NSKeyedArchiver.archivedData(
            withRootObject: windowColor, requiringSecureCoding: true
        ) {
            UserDefaults.standard.set(data, forKey: Keys.windowColorData)
        }
    }

    func resetWindowColor() {
        windowColor = .windowBackgroundColor
        UserDefaults.standard.removeObject(forKey: Keys.windowColorData)
    }

    // MARK: - Hotkey Display
    func hotkeyDisplayString() -> String {
        var parts: [String] = []
        let mods = hotkeyModifiers
        if mods & UInt32(controlKey) != 0 { parts.append("\u{2303}") }  // ⌃
        if mods & UInt32(optionKey) != 0 { parts.append("\u{2325}") }   // ⌥
        if mods & UInt32(shiftKey) != 0 { parts.append("\u{21E7}") }    // ⇧
        if mods & UInt32(cmdKey) != 0 { parts.append("\u{2318}") }      // ⌘
        parts.append(Self.keyCodeToString(hotkeyKeyCode))
        return parts.joined()
    }

    static func keyCodeToString(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Fwd Del"
        case kVK_Escape: return "Esc"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_LeftArrow: return "\u{2190}"   // ←
        case kVK_RightArrow: return "\u{2192}"  // →
        case kVK_UpArrow: return "\u{2191}"     // ↑
        case kVK_DownArrow: return "\u{2193}"   // ↓
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        default:
            // Use keyboard layout to translate key code to character
            guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
                  let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
                return "Key\(keyCode)"
            }
            let layoutData = unsafeBitCast(layoutPtr, to: CFData.self) as Data
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            layoutData.withUnsafeBytes { rawBuf in
                let ptr = rawBuf.bindMemory(to: UCKeyboardLayout.self).baseAddress!
                UCKeyTranslate(ptr, UInt16(keyCode), UInt16(kUCKeyActionDisplay),
                               0, UInt32(LMGetKbdType()),
                               UInt32(kUCKeyTranslateNoDeadKeysBit),
                               &deadKeyState, 4, &length, &chars)
            }
            if length > 0 {
                return String(utf16CodeUnits: chars, count: length).uppercased()
            }
            return "Key\(keyCode)"
        }
    }

    // MARK: - Modifier Conversion
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }
}
