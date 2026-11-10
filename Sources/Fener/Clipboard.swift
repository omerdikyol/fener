import AppKit
import CryptoKit

/// Clipboard history. Polls NSPasteboard.changeCount every 0.5 s and keeps the last
/// `maxItems` text, file and image items in ~/Library/Caches/fener/clipboard (owner-only).
/// Never stores items marked concealed or transient (password managers, nspasteboard.org).
/// Nothing leaves this Mac.
final class Clipboard {
    struct Clip: Codable {
        enum Kind: String, Codable { case text, files, image }
        var id: String
        var kind: Kind
        var text: String           // the text, or file paths one per line; empty for images
        var image: String?         // PNG file name inside the images folder
        var width = 0, height = 0
        var hash: String
        var date: Date
    }

    static let skipTypes: Set = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"]
    static func shouldRecord(types: [String]) -> Bool { !types.contains(where: skipTypes.contains) }

    private(set) var clips: [Clip] = []
    let maxItems: Int, maxItemBytes: Int
    private let dir: URL
    private var images: URL { dir.appendingPathComponent("images") }
    private var index: URL { dir.appendingPathComponent("history.json") }
    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let io = DispatchQueue(label: "fener.clipboard", qos: .utility)

    init(dir: URL, maxItems: Int = 200, maxItemBytes: Int = 5_000_000) {
        self.dir = dir
        self.maxItems = maxItems
        self.maxItemBytes = maxItemBytes
        let fm = FileManager.default
        try? fm.createDirectory(at: images, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        if let d = try? Data(contentsOf: index), let c = try? JSONDecoder().decode([Clip].self, from: d) { clips = c }
    }

    func start() {
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        let types = pb.types?.map(\.rawValue) ?? []
        guard Self.shouldRecord(types: types) else { return }

        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let text = urls.map(\.path).joined(separator: "\n")
            add(Clip(id: UUID().uuidString, kind: .files, text: text, hash: Self.sha(Data(text.utf8)), date: Date()))
        } else if let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard s.utf8.count <= maxItemBytes else { return }
            add(Clip(id: UUID().uuidString, kind: .text, text: s, hash: Self.sha(Data(s.utf8)), date: Date()))
        } else if let raw = pb.data(forType: .png) ?? pb.data(forType: .tiff), raw.count <= maxItemBytes * 4 {
            // Encode off the main thread: a large screenshot can take tens of milliseconds.
            io.async {
                guard let rep = NSBitmapImageRep(data: raw), let png = rep.representation(using: .png, properties: [:]),
                      png.count <= self.maxItemBytes else { return }
                let id = UUID().uuidString, name = id + ".png", hash = Self.sha(png)
                DispatchQueue.main.async {
                    if self.clips.contains(where: { $0.hash == hash }) { return self.add(Clip(id: id, kind: .image, text: "", hash: hash, date: Date())) }
                    try? png.write(to: self.images.appendingPathComponent(name), options: .atomic)
                    self.add(Clip(id: id, kind: .image, text: "", image: name, width: rep.pixelsWide, height: rep.pixelsHigh, hash: hash, date: Date()))
                }
            }
        }
    }

    /// Adds to the top; an identical earlier item moves up instead of duplicating.
    private func add(_ c: Clip) {
        if let i = clips.firstIndex(where: { $0.hash == c.hash }) {
            var old = clips.remove(at: i)
            old.date = c.date
            clips.insert(old, at: 0)
        } else {
            clips.insert(c, at: 0)
        }
        while clips.count > maxItems { remove(clips.count - 1) }
        save()
    }

    private func remove(_ i: Int) {
        let c = clips.remove(at: i)
        if let img = c.image { try? FileManager.default.removeItem(at: images.appendingPathComponent(img)) }
    }

    func clear() {
        while !clips.isEmpty { remove(0) }
        save()
    }

    private func save() {
        let snapshot = clips, url = index
        io.async {
            guard let d = try? JSONEncoder().encode(snapshot) else { return }
            try? d.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    /// Puts a clip back on the pasteboard (it then moves to the top of the history).
    func copy(_ c: Clip) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch c.kind {
        case .text: pb.setString(c.text, forType: .string)
        case .files: pb.writeObjects(c.text.split(separator: "\n").map { NSURL(fileURLWithPath: String($0)) })
        case .image:
            if let name = c.image, let img = NSImage(contentsOf: images.appendingPathComponent(name)) { pb.writeObjects([img]) }
        }
    }

    static func copyText(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    func imageURL(_ c: Clip) -> URL? { c.image.map { images.appendingPathComponent($0) } }

    private static func sha(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }
}
