import AppKit
import CoreAudio
import SQLite3

// MARK: System Settings panes

/// Opens a pane with x-apple.systempreferences:<extension id>. Names are English; ids are
/// the panes' extension bundle ids on macOS 14+ (a test checks they still exist).
enum SettingsPanes {
    static let all: [(name: String, id: String, icon: String)] = [
        ("Wi-Fi", "com.apple.wifi-settings-extension", "nf-md-wifi"),
        ("Bluetooth", "com.apple.BluetoothSettings", "nf-md-bluetooth"),
        ("Network", "com.apple.Network-Settings.extension", "nf-md-lan"),
        ("VPN", "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension", "nf-md-vpn"),
        ("Battery", "com.apple.Battery-Settings.extension", "nf-md-battery"),
        ("General: About", "com.apple.SystemProfiler.AboutExtension", "nf-md-information_outline"),
        ("General: Software Update", "com.apple.Software-Update-Settings.extension", "nf-md-update"),
        ("General: Storage", "com.apple.settings.Storage", "nf-md-harddisk"),
        ("General: AirDrop & Handoff", "com.apple.AirDrop-Handoff-Settings.extension", "nf-md-share_variant"),
        ("General: Login Items", "com.apple.LoginItems-Settings.extension", "nf-md-login"),
        ("General: Language & Region", "com.apple.Localization-Settings.extension", "nf-md-translate"),
        ("General: Date & Time", "com.apple.Date-Time-Settings.extension", "nf-md-clock_outline"),
        ("General: Sharing", "com.apple.Sharing-Settings.extension", "nf-md-share"),
        ("General: Time Machine", "com.apple.Time-Machine-Settings.extension", "nf-md-backup_restore"),
        ("General: Transfer or Reset", "com.apple.Transfer-Reset-Settings.extension", "nf-md-restore"),
        ("General: Startup Disk", "com.apple.Startup-Disk-Settings.extension", "nf-md-harddisk"),
        ("Accessibility", "com.apple.Accessibility-Settings.extension", "nf-md-human"),
        ("Appearance", "com.apple.Appearance-Settings.extension", "nf-md-theme_light_dark"),
        ("Control Center / Menu Bar", "com.apple.ControlCenter-Settings.extension", "nf-md-dock_top"),
        ("Siri", "com.apple.Siri-Settings.extension", "nf-md-microphone_variant"),
        ("Spotlight", "com.apple.Spotlight-Settings.extension", "nf-md-magnify"),
        ("Privacy & Security", "com.apple.settings.PrivacySecurity.extension", "nf-md-shield_lock"),
        ("Desktop & Dock", "com.apple.Desktop-Settings.extension", "nf-md-dock_bottom"),
        ("Displays", "com.apple.Displays-Settings.extension", "nf-md-monitor"),
        ("Wallpaper", "com.apple.Wallpaper-Settings.extension", "nf-md-image"),
        ("Notifications", "com.apple.Notifications-Settings.extension", "nf-md-bell"),
        ("Sound", "com.apple.Sound-Settings.extension", "nf-md-volume_high"),
        ("Focus", "com.apple.Focus-Settings.extension", "nf-md-moon_waning_crescent"),
        ("Screen Time", "com.apple.Screen-Time-Settings.extension", "nf-md-timer_sand"),
        ("Lock Screen", "com.apple.Lock-Screen-Settings.extension", "nf-md-lock"),
        ("Touch ID & Password", "com.apple.Touch-ID-Settings.extension", "nf-md-fingerprint"),
        ("Users & Groups", "com.apple.Users-Groups-Settings.extension", "nf-md-account_group"),
        ("Internet Accounts", "com.apple.Internet-Accounts-Settings.extension", "nf-md-at"),
        ("Keyboard", "com.apple.Keyboard-Settings.extension", "nf-md-keyboard"),
        ("Mouse", "com.apple.Mouse-Settings.extension", "nf-md-mouse"),
        ("Trackpad", "com.apple.Trackpad-Settings.extension", "nf-md-gesture_tap"),
        ("Printers & Scanners", "com.apple.Print-Scan-Settings.extension", "nf-md-printer"),
        ("Game Controllers", "com.apple.Game-Controller-Settings.extension", "nf-md-gamepad_variant"),
    ]

    static func open(_ id: String) {
        if let u = URL(string: "x-apple.systempreferences:" + id) { NSWorkspace.shared.open(u) }
    }
}

// MARK: Audio devices

/// Default input/output switching through Core Audio (no permission needed).
enum Audio {
    struct Device { let id: AudioDeviceID; let name: String; let input: Bool; let output: Bool; let transport: UInt32 }

    private static func address(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func devices() -> [Device] {
        var addr = address(kAudioHardwarePropertyDevices), size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var nameAddr = address(kAudioObjectPropertyName)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard withUnsafeMutablePointer(to: &name, { AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, $0) }) == noErr,
                  let n = name?.takeRetainedValue() as String? else { return nil }
            func hasStreams(_ scope: AudioObjectPropertyScope) -> Bool {
                var a = address(kAudioDevicePropertyStreams, scope), s: UInt32 = 0
                return AudioObjectGetPropertyDataSize(id, &a, 0, nil, &s) == noErr && s > 0
            }
            var tAddr = address(kAudioDevicePropertyTransportType), transport: UInt32 = 0, tSize = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(id, &tAddr, 0, nil, &tSize, &transport)
            return Device(id: id, name: n, input: hasStreams(kAudioObjectPropertyScopeInput),
                          output: hasStreams(kAudioObjectPropertyScopeOutput), transport: transport)
        }
    }

    static func defaultDevice(input: Bool) -> AudioDeviceID {
        var addr = address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var id: AudioDeviceID = 0, size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    /// Output also moves system sounds (alerts) to the same device.
    static func setDefault(_ id: AudioDeviceID, input: Bool) {
        var dev = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size), system = AudioObjectID(kAudioObjectSystemObject)
        let selectors = input ? [kAudioHardwarePropertyDefaultInputDevice]
            : [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice]
        for sel in selectors {
            var addr = address(sel)
            AudioObjectSetPropertyData(system, &addr, 0, nil, size, &dev)
        }
    }

    static func icon(_ d: Device, input: Bool) -> String {
        if input { return "nf-md-microphone" }
        switch d.transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "nf-md-headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "nf-md-monitor_speaker"
        case kAudioDeviceTransportTypeAirPlay: return "nf-md-cast_audio"
        default: return "nf-md-speaker"
        }
    }
}

// MARK: Helium bookmarks and VS Code recents

enum Bookmarks {
    struct Bookmark { let name: String; let url: String; let folder: String }

    /// Chromium "Bookmarks" JSON from every Helium profile.
    static func helium() -> [Bookmark] {
        let base = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/net.imput.helium")
        let profiles = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
        return profiles.flatMap { p -> [Bookmark] in
            guard let d = try? Data(contentsOf: base.appendingPathComponent(p).appendingPathComponent("Bookmarks")) else { return [] }
            return parse(d)
        }
    }

    static func parse(_ data: Data) -> [Bookmark] {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = j["roots"] as? [String: Any] else { return [] }
        var out: [Bookmark] = []
        func walk(_ node: [String: Any], _ folder: String) {
            if node["type"] as? String == "url", let u = node["url"] as? String {
                out.append(Bookmark(name: node["name"] as? String ?? u, url: u, folder: folder))
            }
            let name = node["name"] as? String ?? ""
            for c in node["children"] as? [[String: Any]] ?? [] { walk(c, node["type"] as? String == "folder" ? name : folder) }
        }
        for case let r as [String: Any] in roots.values { walk(r, "") }
        return out
    }
}

enum VSCodeRecents {
    /// The recently-opened list from VS Code's state database, opened read-only. Newer
    /// versions store it as "recently.opened", older ones as "history.recentlyOpenedPathsList".
    static func load() -> [URL] {
        let db = NSHomeDirectory() + "/Library/Application Support/Code/User/globalStorage/state.vscdb"
        var h: OpaquePointer?
        // A plain path: the "file:" URI form would need the space in "Application Support" escaped.
        guard sqlite3_open_v2(db, &h, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(h); return [] }
        defer { sqlite3_close(h) }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(h, "SELECT value FROM ItemTable WHERE key IN ('recently.opened', 'history.recentlyOpenedPathsList') ORDER BY key = 'recently.opened' DESC LIMIT 1", -1, &st, nil) == SQLITE_OK
        else { return [] }
        defer { sqlite3_finalize(st) }
        guard sqlite3_step(st) == SQLITE_ROW, let c = sqlite3_column_text(st, 0) else { return [] }
        return parse(Data(String(cString: c).utf8))
    }

    static func parse(_ data: Data) -> [URL] {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = j["entries"] as? [[String: Any]] else { return [] }
        return entries.compactMap { e in
            let s = e["folderUri"] as? String ?? (e["workspace"] as? [String: Any])?["configPath"] as? String ?? e["fileUri"] as? String
            guard let s, let u = URL(string: s) else { return nil }
            // Local entries must still exist; remote ones (vscode-remote://ssh-remote+host/…) are kept.
            return !u.isFileURL || FileManager.default.fileExists(atPath: u.path) ? u : nil
        }
    }
}

// MARK: Generators

enum Generators {
    static let lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."

    /// Uses the system's cryptographically secure generator.
    static func password(length: Int, symbols: Bool) -> String {
        let letters = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"   // no l, I, O, 0, 1
        let pool = Array(letters + (symbols ? "!@#$%^&*-_=+?" : ""))
        var rng = SystemRandomNumberGenerator()
        return String((0..<max(4, min(length, 256))).map { _ in pool.randomElement(using: &rng)! })
    }

    static func pin(_ n: Int) -> String {
        var rng = SystemRandomNumberGenerator()
        return String((0..<max(4, min(n, 32))).map { _ in Character(String(Int.random(in: 0...9, using: &rng))) })
    }
}

// MARK: Processes

enum Processes {
    struct Proc { let pid: Int32; let cpu: Double; let memMB: Int; let name: String }

    /// This user's processes, most CPU first (`ps`; other users' processes cannot be signalled anyway).
    static func list() -> [Proc] {
        guard let out = Shell.capture("/bin/ps", ["-U", "\(getuid())", "-o", "pid=,pcpu=,rss=,comm="], timeout: 3) else { return [] }
        return parse(out)
    }

    static func parse(_ out: String) -> [Proc] {
        out.split(separator: "\n").compactMap { line in
            let f = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard f.count == 4, let pid = Int32(f[0]), let cpu = Double(f[1]), let rss = Int(f[2]) else { return nil }
            return Proc(pid: pid, cpu: cpu, memMB: rss / 1024, name: (String(f[3]) as NSString).lastPathComponent)
        }.sorted { $0.cpu > $1.cpu }
    }

    /// PIDs listening on a TCP port.
    static func listening(port: Int) -> Set<Int32> {
        guard let out = Shell.capture("/usr/sbin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"], timeout: 3) else { return [] }
        return Set(out.split(separator: "\n").compactMap { Int32($0) })
    }
}
