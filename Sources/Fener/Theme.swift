import AppKit

/// Colors and metrics for the panel. The defaults are Tokyo Night; theme files override any of them.
struct Theme: Equatable {
    var background = NSColor(hex: 0x1a1b26)
    var backgroundOpacity: CGFloat = 0.95
    var border = NSColor(hex: 0xc0caf5)
    var borderWidth: CGFloat = 2
    var text = NSColor(hex: 0xc0caf5)
    var muted = NSColor(hex: 0x565f89)
    var accent = NSColor(hex: 0x7aa2f7)
    var selection = NSColor(hex: 0x24283b)

    var fontFamily = "JetBrainsMono Nerd Font"
    var fontSize: CGFloat = 15
    var width: CGFloat = 480
    var padding: CGFloat = 18
    var cornerRadius: CGFloat = 0
    var selectionRadius: CGFloat = 4
    var rowHeight: CGFloat = 40
    var iconSize: CGFloat = 20
    var visibleRows = 9

    func font(_ size: CGFloat, weight: Int = 5) -> NSFont {
        NSFontManager.shared.font(withFamily: fontFamily, traits: [], weight: weight, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: weight > 5 ? .semibold : .regular)
    }

}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}
