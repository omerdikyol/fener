import AppKit

/// Built-in system actions. Destructive ones ask for confirmation first.
/// Restart, shut down and log out go through System Events, and empty trash through Finder,
/// so macOS asks once for Automation permission (fener controlling System Events / Finder).
struct SystemAction {
    let name: String
    let subtitle: String
    let icon: String          // SF Symbol
    let confirm: Bool
    let run: () -> Void

    static let all: [SystemAction] = [
        SystemAction(name: "Lock Screen", subtitle: "system", icon: "lock", confirm: false, run: lock),
        SystemAction(name: "Sleep", subtitle: "system", icon: "moon", confirm: false) { pmset("sleepnow") },
        SystemAction(name: "Sleep Display", subtitle: "system", icon: "display", confirm: false) { pmset("displaysleepnow") },
        SystemAction(name: "Restart", subtitle: "system", icon: "arrow.clockwise", confirm: true) {
            osa("tell application \"System Events\" to restart")
        },
        SystemAction(name: "Shut Down", subtitle: "system", icon: "power", confirm: true) {
            osa("tell application \"System Events\" to shut down")
        },
        SystemAction(name: "Log Out", subtitle: "system", icon: "rectangle.portrait.and.arrow.right", confirm: true) {
            osa("tell application \"System Events\" to log out")
        },
        SystemAction(name: "Empty Trash", subtitle: "system", icon: "trash", confirm: true) {
            osa("tell application \"Finder\" to empty trash")
        },
    ]

    private static func pmset(_ arg: String) { Shell.run("/usr/bin/pmset", [arg]) }
    private static func osa(_ script: String) { Shell.run("/usr/bin/osascript", ["-e", script]) }

    /// Locks right away through the private login framework (what the menu-bar Lock Screen
    /// item uses); if that symbol is ever missing, falls back to sleeping the display, which
    /// locks when "require password immediately" is on.
    private static func lock() {
        typealias Fn = @convention(c) () -> Void
        if let h = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let sym = dlsym(h, "SACLockScreenImmediate") {
            unsafeBitCast(sym, to: Fn.self)()
        } else {
            pmset("displaysleepnow")
        }
    }
}
