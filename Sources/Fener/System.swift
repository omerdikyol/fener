import AppKit

/// Built-in system actions. Destructive ones ask for confirmation first.
/// Restart, shut down and log out go through System Events, and empty trash through Finder,
/// so macOS asks once for Automation permission (fener controlling System Events / Finder).
struct SystemAction {
    let name: String
    let subtitle: String
    let icon: String          // see Icons: a Nerd Font name such as nf-md-lock
    let confirm: Bool
    let run: () -> Void

    static let all: [SystemAction] = [
        SystemAction(name: "Lock Screen", subtitle: "system", icon: "nf-md-lock", confirm: false, run: lock),
        SystemAction(name: "Sleep", subtitle: "system", icon: "nf-md-power_sleep", confirm: false) { pmset("sleepnow") },
        SystemAction(name: "Sleep Display", subtitle: "system", icon: "nf-md-monitor_off", confirm: false) { pmset("displaysleepnow") },
        SystemAction(name: "Screensaver", subtitle: "system", icon: "nf-md-monitor_star", confirm: false) {
            Shell.run("/usr/bin/open", ["-a", "ScreenSaverEngine"])
        },
        SystemAction(name: "Restart", subtitle: "system", icon: "nf-md-restart", confirm: true) {
            osa("tell application \"System Events\" to restart")
        },
        SystemAction(name: "Shut Down", subtitle: "system", icon: "nf-md-power", confirm: true) {
            osa("tell application \"System Events\" to shut down")
        },
        SystemAction(name: "Log Out", subtitle: "system", icon: "nf-md-logout", confirm: true) {
            osa("tell application \"System Events\" to log out")
        },
        SystemAction(name: "Empty Trash", subtitle: "system", icon: "nf-md-delete", confirm: true) {
            osa("tell application \"Finder\" to empty trash")
        },
        SystemAction(name: "Toggle Hidden Files", subtitle: "Finder", icon: "nf-md-eye", confirm: false) {
            Shell.sh("[ \"$(defaults read com.apple.finder AppleShowAllFiles 2>/dev/null)\" = 1 ] && v=false || v=true; "
                     + "defaults write com.apple.finder AppleShowAllFiles -bool $v && killall Finder")
        },
        SystemAction(name: "Eject All Disks", subtitle: "external drives and disk images", icon: "nf-md-eject", confirm: false) {
            Shell.sh("for d in $(diskutil list external | awk '/^\\/dev\\//{print $1}'); do diskutil eject \"$d\"; done")
        },
        SystemAction(name: "Quit fener", subtitle: "until the next login, or open fener.app", icon: "nf-md-close_circle_outline", confirm: false) {
            DispatchQueue.main.async { NSApp.terminate(nil) }
        },
        SystemAction(name: "Restart Finder", subtitle: "Finder", icon: "nf-md-restart", confirm: false) { Shell.sh("killall Finder") },
        SystemAction(name: "Restart Dock", subtitle: "Dock", icon: "nf-md-restart", confirm: false) { Shell.sh("killall Dock") },
        SystemAction(name: "Hide Other Apps", subtitle: "system", icon: "nf-md-eye_off", confirm: false) {
            NSApp.hideOtherApplications(nil)
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
