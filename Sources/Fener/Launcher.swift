import AppKit
import QuartzCore

struct Item {
    var id = ""            // stable identity (e.g. app path); unchanged ids skip a redraw
    var title: String
    var subtitle = ""      // dim text after the title, for windows/files; apps leave it empty
    var accessory = ""     // right-aligned hint, e.g. "›" for submenus
    var icon: NSImage?
    var run: () -> Void = {}
    var score = 0          // used to merge results from several sources
    var submenu: (() -> Mode)? = nil  // set: Return opens this mode instead of running
}

/// What the panel is searching: the root (apps, windows, menus) or one menu.
struct Mode {
    var prompt: String
    var search: (String) -> [Item]
}

/// Borderless panel that can take keyboard focus without activating the app (like Spotlight),
/// so the previously focused app keeps its activation state and no activation request is needed.
final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class Launcher: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    let theme: Theme
    let panel: LauncherPanel
    private let field = NSTextField()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let fade = CAGradientLayer()
    private let fieldEditor = NSTextView()
    private let root: Mode
    private var stack: [Mode]
    private var items: [Item] = []
    private var hiding = false
    private var topY: CGFloat = 0
    private var mode: Mode { stack[stack.count - 1] }
    var onShow: () -> Void = {}

    // Vertical metrics: padding, search line, gap, list, padding.
    private var pad: CGFloat { theme.padding }
    private let searchH: CGFloat = 24, gap: CGFloat = 10
    private var chromeH: CGFloat { pad + searchH + gap + pad }

    init(theme: Theme, root: Mode) {
        self.theme = theme
        self.root = root
        self.stack = [root]
        panel = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: theme.width, height: 200),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.delegate = self
        panel.appearance = NSAppearance(named: .darkAqua)

        let root = NSView(frame: NSRect(x: 0, y: 0, width: theme.width, height: 200))
        root.wantsLayer = true
        panel.contentView = root

        // Blur behind, then a near-opaque tint with the border on top.
        let blur = NSVisualEffectView(frame: root.bounds)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        if theme.cornerRadius > 0 { blur.maskImage = Self.roundedMask(radius: theme.cornerRadius) }
        root.addSubview(blur)

        let skin = NSView(frame: root.bounds)
        skin.wantsLayer = true
        skin.layer?.backgroundColor = theme.background.withAlphaComponent(theme.backgroundOpacity).cgColor
        skin.layer?.borderColor = theme.border.cgColor
        skin.layer?.borderWidth = theme.borderWidth
        skin.layer?.cornerRadius = theme.cornerRadius
        skin.autoresizingMask = [.width, .height]
        root.addSubview(skin)

        // Search line: no box, no icon; the placeholder doubles as the mode prompt ("Apps…").
        let inner = theme.width - 2 * pad
        field.frame = NSRect(x: pad + 2, y: 200 - pad - searchH, width: inner - 4, height: searchH)
        field.autoresizingMask = [.minYMargin]
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = theme.font(theme.fontSize)
        field.textColor = theme.text
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        setPlaceholder()
        root.addSubview(field)

        fieldEditor.isFieldEditor = true
        fieldEditor.insertionPointColor = theme.accent
        fieldEditor.selectedTextAttributes = [.backgroundColor: theme.accent.withAlphaComponent(0.35)]

        // List.
        let col = NSTableColumn(identifier: .init("c"))
        col.width = inner
        table.addTableColumn(col)
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = theme.rowHeight
        table.intercellSpacing = .zero
        table.style = .plain
        table.focusRingType = .none
        table.refusesFirstResponder = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        scroll.frame = NSRect(x: pad, y: pad, width: inner, height: 200 - chromeH)
        scroll.autoresizingMask = [.height]
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.wantsLayer = true
        // Bottom fade that hints "more below" when the list overflows.
        // The scroll view's layer is flipped: y = 1 is the bottom edge.
        fade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        root.addSubview(scroll)

        filter()
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.panel.isKeyWindow else { return e }
            return self.handleKey(e) ? nil : e
        }
    }

    // MARK: show / hide

    var isVisible: Bool { panel.isVisible && !hiding }

    func toggle() { isVisible ? hide() : show() }

    /// Orders the panel in once while fully transparent so the first real show skips
    /// creating the window server backing and the first layout pass.
    func prewarm() {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        CATransaction.flush()
        panel.orderOut(nil)
    }

    /// Opens the panel at the root mode, or directly in `mode` (e.g. `fener show themes`).
    func show(_ mode: Mode? = nil) {
        hiding = false
        stack = [root] + (mode.map { [$0] } ?? [])
        setPlaceholder()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main!
        let vf = screen.visibleFrame
        // Top edge fixed so the panel grows downward as results change; centered at its tallest.
        let maxH = chromeH + theme.rowHeight * (CGFloat(theme.visibleRows) + 0.5)
        topY = (vf.midY + maxH / 2).rounded()
        panel.setFrameOrigin(NSPoint(x: (vf.midX - theme.width / 2).rounded(), y: topY - panel.frame.height))
        if !field.stringValue.isEmpty { field.stringValue = "" }
        filter()
        onShow()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        animate(scaleFrom: 0.97, to: 1, alphaTo: 1, duration: 0.12) {}
    }

    func hide() {
        guard panel.isVisible, !hiding else { return }
        hiding = true
        animate(scaleFrom: 1, to: 0.98, alphaTo: 0, duration: 0.08) { [weak self] in
            guard let self, self.hiding else { return }
            self.panel.orderOut(nil)
            self.hiding = false
        }
    }

    private func animate(scaleFrom: CGFloat, to: CGFloat, alphaTo: CGFloat, duration: TimeInterval, done: @escaping () -> Void) {
        guard let layer = panel.contentView?.layer else { return }
        let b = layer.bounds
        func scaled(_ k: CGFloat) -> CATransform3D {  // scale about the center; view layers anchor at (0,0)
            var t = CATransform3DMakeTranslation(b.midX, b.midY, 0)
            t = CATransform3DScale(t, k, k, 1)
            return CATransform3DTranslate(t, -b.midX, -b.midY, 0)
        }
        let anim = CABasicAnimation(keyPath: "transform")
        anim.fromValue = scaled(scaleFrom)
        anim.toValue = scaled(to)
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        layer.add(anim, forKey: "scale")
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = alphaTo
        }, completionHandler: done)
    }

    func windowDidResignKey(_ notification: Notification) { hide() }

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        client as? NSTextField === field ? fieldEditor : nil
    }

    // MARK: keys and mouse

    private func handleKey(_ e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = e.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (e.keyCode, mods) {
        case (53, []): hide()                                  // escape
        case (51, []) where field.stringValue.isEmpty && stack.count > 1: pop()  // backspace on empty: back
        case (125, []): move(1)                                // down
        case (126, []): move(-1)                               // up
        case (36, []), (76, []): run(table.selectedRow)        // return, keypad enter
        default:
            if mods == .control, key == "n" || key == "j" { move(1) }
            else if mods == .control, key == "p" || key == "k" { move(-1) }
            else if mods == .command, let n = Int(key), (1...9).contains(n) { run(n - 1) }
            else { return false }
        }
        return true
    }

    @objc private func clicked() { run(table.clickedRow) }

    private func move(_ d: Int) {
        guard !items.isEmpty else { return }
        let r = (table.selectedRow + d + items.count) % items.count
        select(r)
    }

    private func select(_ r: Int) {
        let old = table.selectedRow
        table.selectRowIndexes([r], byExtendingSelection: false)
        table.scrollRowToVisible(r)
        // Selected title is drawn in the accent color; refresh the two affected cells.
        table.reloadData(forRowIndexes: IndexSet([old, r].filter { $0 >= 0 }), columnIndexes: [0])
    }

    private func run(_ row: Int) {
        guard items.indices.contains(row) else { return }
        let item = items[row]
        if let sub = item.submenu { push(sub()); return }
        hide()
        item.run()
    }

    // MARK: data

    func controlTextDidChange(_ obj: Notification) { filter() }

    func setQuery(_ q: String) { field.stringValue = q; filter() }

    func push(_ m: Mode) {
        stack.append(m)
        field.stringValue = ""
        setPlaceholder()
        filter()
    }

    private func pop() {
        guard stack.count > 1 else { return }
        stack.removeLast()
        setPlaceholder()
        filter()
    }

    /// Re-runs the current search after a source changed, keeping the selected row if it is still there.
    func refilter() {
        guard isVisible else { return }
        let keep = items.indices.contains(table.selectedRow) ? items[table.selectedRow].id : nil
        filter()
        if let keep, let r = items.firstIndex(where: { $0.id == keep }), r != table.selectedRow { select(r) }
    }

    private func filter() {
        let new = mode.search(field.stringValue)
        let key = { (i: Item) in i.id + "\u{1}" + i.title + "\u{1}" + i.subtitle }
        let same = !new.isEmpty && new.map(key) == items.map(key) && !new.contains { $0.id.isEmpty }
        items = new
        if same {
            if table.selectedRow != 0 { select(0) } else { table.scrollRowToVisible(0) }
            return  // rows already drawn; skipping reload saves ~10 ms on show
        }
        table.reloadData()
        if !items.isEmpty { select(0) }
        resize()
    }

    /// Height follows the result count (up to visibleRows + a half row that fades out).
    private func resize() {
        let rows = min(CGFloat(items.count), CGFloat(theme.visibleRows) + 0.5)
        let h = (chromeH - (items.isEmpty ? gap : 0) + rows * theme.rowHeight).rounded()
        var f = panel.frame
        if panel.isVisible || topY > 0 { f.origin.y = topY - h }
        f.size.height = h
        panel.setFrame(f, display: panel.isVisible)
        // Explicit frames: autoresizing loses track once the list height reaches zero.
        field.frame.origin.y = h - pad - searchH
        scroll.frame = NSRect(x: pad, y: pad, width: theme.width - 2 * pad, height: rows * theme.rowHeight)
        let overflow = CGFloat(items.count) > CGFloat(theme.visibleRows)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        fade.frame = scroll.bounds
        fade.locations = [0, NSNumber(value: Double(1 - min(1, theme.rowHeight / max(scroll.bounds.height, 1)))), 1]
        scroll.layer?.mask = overflow ? fade : nil
        CATransaction.commit()
    }

    private func setPlaceholder() {
        field.placeholderAttributedString = NSAttributedString(
            string: mode.prompt, attributes: [.foregroundColor: theme.muted, .font: theme.font(theme.fontSize)])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        RowView(color: theme.selection, radius: theme.selectionRadius)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: .init("cell"), owner: nil) as? Cell) ?? Cell(theme: theme)
        cell.set(items[row], selected: row == tableView.selectedRow)
        return cell
    }

    // MARK: helpers

    private static func roundedMask(radius r: CGFloat) -> NSImage {
        let edge = 2 * r + 1
        let img = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        img.resizingMode = .stretch
        return img
    }
}

private final class RowView: NSTableRowView {
    let color: NSColor, radius: CGFloat
    init(color: NSColor, radius: CGFloat) { self.color = color; self.radius = radius; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override func drawSelection(in dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: radius, yRadius: radius).fill()
    }
    override var isEmphasized: Bool { get { true } set {} }
}

private final class Cell: NSView {
    private let theme: Theme
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let accessory = NSTextField(labelWithString: "")

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        identifier = .init("cell")
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.lineBreakMode = .byTruncatingTail
        accessory.font = theme.font(theme.fontSize - 1)
        accessory.textColor = theme.muted
        accessory.alignment = .right
        for v in [icon, title, accessory] { addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(_ item: Item, selected: Bool) {
        icon.image = item.icon
        let s = NSMutableAttributedString(string: item.title, attributes: [
            .font: theme.font(theme.fontSize), .foregroundColor: selected ? theme.accent : theme.text])
        if !item.subtitle.isEmpty {
            s.append(NSAttributedString(string: "  " + item.subtitle, attributes: [
                .font: theme.font(theme.fontSize - 2), .foregroundColor: theme.muted]))
        }
        title.attributedStringValue = s
        accessory.stringValue = item.accessory
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height, w = bounds.width, i = theme.iconSize
        icon.frame = NSRect(x: 14, y: ((h - i) / 2).rounded(), width: i, height: i)
        let x = 14 + i + 12
        title.frame = NSRect(x: x, y: ((h - 18) / 2).rounded(), width: w - x - 36, height: 18)
        accessory.frame = NSRect(x: w - 32, y: ((h - 18) / 2).rounded(), width: 20, height: 18)
    }
}
