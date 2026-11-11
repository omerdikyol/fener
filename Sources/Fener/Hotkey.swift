import AppKit
import Carbon.HIToolbox

/// fener's own shortcut for showing and hiding the panel (config.toml `shortcut`), registered
/// with RegisterEventHotKey: a system hotkey that needs no Input Monitoring or Accessibility
/// permission. Written as "ctrl+opt+cmd+space"; key names follow the US layout's key positions
/// (like Karabiner), so a shortcut stays on the same physical key when the input source changes.
enum Hotkey {
    struct Combo: Equatable {
        var key: UInt32
        var mods: NSEvent.ModifierFlags
    }

    static let names: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "space": kVK_Space, "return": kVK_Return, "tab": kVK_Tab, "delete": kVK_Delete, "escape": kVK_Escape,
        "comma": kVK_ANSI_Comma, "period": kVK_ANSI_Period, "slash": kVK_ANSI_Slash, "semicolon": kVK_ANSI_Semicolon,
        "quote": kVK_ANSI_Quote, "minus": kVK_ANSI_Minus, "equal": kVK_ANSI_Equal, "grave": kVK_ANSI_Grave,
        "backslash": kVK_ANSI_Backslash, "bracketleft": kVK_ANSI_LeftBracket, "bracketright": kVK_ANSI_RightBracket,
        "section": kVK_ISO_Section,
        "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7,
        "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12, "f13": kVK_F13,
        "f14": kVK_F14, "f15": kVK_F15, "f16": kVK_F16, "f17": kVK_F17, "f18": kVK_F18, "f19": kVK_F19, "f20": kVK_F20,
    ]
    private static let modNames: [(String, NSEvent.ModifierFlags)] = [("ctrl", .control), ("opt", .option), ("shift", .shift), ("cmd", .command)]
    static let relevant: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    /// "ctrl+opt+cmd+space", "cmd+shift+k", "hyper+space" (ctrl+opt+cmd), "key50" for unnamed keys.
    static func parse(_ s: String) -> Combo? {
        var mods: NSEvent.ModifierFlags = []
        var key: UInt32?
        for part in s.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "ctrl", "control": mods.insert(.control)
            case "opt", "option", "alt": mods.insert(.option)
            case "shift": mods.insert(.shift)
            case "cmd", "command": mods.insert(.command)
            case "hyper": mods.formUnion([.control, .option, .command])
            default:
                guard key == nil else { return nil }
                if let k = names[part] { key = UInt32(k) }
                else if part.hasPrefix("key"), let n = UInt32(part.dropFirst(3)), n < 128 { key = n }
                else { return nil }
            }
        }
        return key.map { Combo(key: $0, mods: mods) }
    }

    static func string(_ c: Combo) -> String {
        let key = names.first { UInt32($0.value) == c.key }?.key ?? "key\(c.key)"
        return (modNames.filter { c.mods.contains($0.1) }.map(\.0) + [key]).joined(separator: "+")
    }

    static func combo(_ e: NSEvent) -> Combo { Combo(key: UInt32(e.keyCode), mods: e.modifierFlags.intersection(relevant)) }

    static func isFunctionKey(_ key: UInt32) -> Bool { names.contains { $0.key.hasPrefix("f") && $0.key.count > 1 && UInt32($0.value) == key } }

    /// Why this cannot be the shortcut, or nil. Without Command or Control a key types text
    /// (Option and Option+Shift type characters on many layouts, Turkish among them).
    static func problem(_ c: Combo) -> String? {
        if c.mods.isDisjoint(with: [.command, .control]) && !isFunctionKey(c.key) {
            return "a shortcut needs Command or Control (Option and Shift alone type characters)"
        }
        return nil
    }

    /// "⌃⌥⌘ Space", with the key as the current layout prints it ("Ç" on a Turkish keyboard).
    static func label(_ c: Combo) -> String {
        let mods = [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { c.mods.contains($0.0) }.map(\.1).joined()
        let special: [Int: String] = [kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete",
                                      kVK_Escape: "Esc", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓"]
        let key = special[Int(c.key)]
            ?? names.first { $0.key.hasPrefix("f") && $0.key.count > 1 && UInt32($0.value) == c.key }?.key.uppercased()
            ?? character(c.key) ?? string(Combo(key: c.key, mods: []))
        return mods + " " + key
    }

    /// The character a key types on the current layout, uppercased.
    private static func character(_ key: UInt32) -> String? {
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var dead: UInt32 = 0, length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { buf in
            UCKeyTranslate(buf.bindMemory(to: UCKeyboardLayout.self).baseAddress!, UInt16(key), UInt16(kUCKeyActionDisplay), 0,
                           UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s.uppercased(with: Locale.current)
    }

    // MARK: registration

    private static var ref: EventHotKeyRef?
    private static var handler: EventHandlerRef?
    private static var action: () -> Void = {}
    private static var registered: String?
    /// Why the configured shortcut is not active, or nil.
    private(set) static var error: String?

    /// Registers `shortcut` ("" = none) to run `action`; does nothing when it is unchanged.
    static func set(_ shortcut: String, action: @escaping () -> Void) {
        self.action = action
        guard shortcut != registered else { return }
        registered = shortcut
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
        error = nil
        guard !shortcut.isEmpty else { return }
        guard let c = parse(shortcut) else { error = "config.toml: shortcut \"\(shortcut)\" is not a key combination"; return }
        if let p = problem(c) { error = "config.toml: shortcut \(label(c)): \(p)"; return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in Hotkey.action(); return noErr }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: 0x666E_6572, id: 1)   // "fner"
        let status = RegisterEventHotKey(c.key, carbonMods(c.mods), id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            Log.info("shortcut: \(shortcut)")
        } else {
            error = "shortcut \(label(c)) could not be registered (\(status)); another app may use it"
        }
    }

    private static func carbonMods(_ m: NSEvent.ModifierFlags) -> UInt32 {
        var r = 0
        if m.contains(.command) { r |= cmdKey }
        if m.contains(.control) { r |= controlKey }
        if m.contains(.option) { r |= optionKey }
        if m.contains(.shift) { r |= shiftKey }
        return UInt32(r)
    }
}
