import AppKit

/// Building blocks for row actions (Cmd+K). An action is an Item, so it can have an icon,
/// a confirmation or a submenu like any row.
enum Act {
    static func make(_ title: String, _ icon: String, _ run: @escaping () -> Void) -> Item {
        Item(id: "action:" + title, title: title, icon: sf(icon), run: run)
    }

    static func copy(_ title: String, _ text: String) -> Item {
        make(title, "nf-md-content_copy") { Clipboard.copyText(text) }
    }

    /// Show in Finder, Quick Look, Copy Path, Copy File.
    static func file(_ path: String) -> [Item] {
        let url = URL(fileURLWithPath: path)
        return [
            make("Show in Finder", "nf-md-folder_search") { NSWorkspace.shared.activateFileViewerSelecting([url]) },
            make("Quick Look", "nf-md-eye") { Shell.run("/usr/bin/qlmanage", ["-p", path]) },
            copy("Copy Path", path),
            make("Copy File", "nf-md-file_document_multiple") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([url as NSURL])
            },
        ]
    }

    /// "Open in <terminal>" for a folder ([apps] terminal). Ghostty needs its own flag.
    static func terminal(_ dir: String) -> Item {
        let app = config.terminalApp
        return make("Open in \(app)", "nf-md-console_line") {
            if app.lowercased() == "ghostty" { Shell.run("/usr/bin/open", ["-na", "Ghostty", "--args", "--working-directory=" + dir]) }
            else { Shell.run("/usr/bin/open", ["-a", app, dir]) }
        }
    }

    /// "Edit" in the configured editor ([apps] editor).
    static func edit(_ title: String, _ path: String) -> Item {
        make(title, "nf-md-pencil") { Editors.current.open(path) }
    }

    static func url(_ s: String) -> [Item] {
        [copy("Copy URL", s)]
    }

    /// Show in Finder, Copy Path, then Quit and Force Quit while the app runs.
    static func app(_ path: String) -> [Item] {
        var out = [file(path)[0], copy("Copy Path", path)]
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path == path }) {
            out.append(make("Quit", "nf-md-close_circle") { running.terminate() })
            out.append(make("Force Quit", "nf-md-alert") { running.forceTerminate() })
        }
        return out
    }
}
