import AppKit
import CryptoKit
import Security

/// Clipboard history. Polls NSPasteboard.changeCount every 0.5 s and keeps the last
/// `maxItems` text, file and image items, for at most `keepDays` days.
///
/// Never recorded: items marked org.nspasteboard.ConcealedType or TransientType (password
/// managers), and anything copied while an app in `ignoreApps` is in front.
///
/// Stored in ~/Library/Application Support/fener/clipboard (owner-only, excluded from
/// backups), encrypted with AES-GCM under a random key kept in the login Keychain. If the
/// key cannot be read, history stays in memory and nothing is written. Nothing leaves this Mac.
final class Clipboard {
    struct Clip: Codable {
        enum Kind: String, Codable { case text, files, image }
        var id: String
        var kind: Kind
        var text: String           // the text, or file paths one per line; empty for images
        var image: String?         // encrypted PNG file name inside the images folder
        var width = 0, height = 0
        var hash: String
        var date: Date
    }

    static let skipTypes: Set = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"]
    static func shouldRecord(types: [String]) -> Bool { !types.contains(where: skipTypes.contains) }

    private(set) var clips: [Clip] = []
    var maxItems: Int, maxItemBytes: Int
    var keepDays = 30
    var ignoreApps: Set<String> = []       // bundle ids or app names, lowercased
    private let dir: URL
    private var key: SymmetricKey?
    private var images: URL { dir.appendingPathComponent("images") }
    private var index: URL { dir.appendingPathComponent("history.enc") }
    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var thumbs: [String: NSImage] = [:]
    private let io = DispatchQueue(label: "fener.clipboard", qos: .utility)

    /// `legacy`: the old plaintext folder (~/Library/Caches/fener/clipboard), migrated and removed.
    init(dir: URL, legacy: URL? = nil, maxItems: Int = 200, maxItemBytes: Int = 5_000_000,
         loadKey: @escaping () -> SymmetricKey? = Keychain.clipboardKey) {
        self.dir = dir
        self.maxItems = maxItems
        self.maxItemBytes = maxItemBytes
        let fm = FileManager.default
        try? fm.createDirectory(at: images, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var d = dir; try? d.setResourceValues(values)
        // The Keychain may ask for permission; never block the launcher on that.
        io.async {
            let k = loadKey()
            DispatchQueue.main.async { self.unlocked(k, legacy: legacy) }
        }
    }

    private func unlocked(_ k: SymmetricKey?, legacy: URL?) {
        guard let k else {
            Log.error("clipboard: no Keychain key; history is kept in memory only")
            return
        }
        key = k
        let recent = clips   // copied while the key was loading
        if let sealed = try? Data(contentsOf: index), let plain = decrypt(sealed),
           let saved = try? JSONDecoder().decode([Clip].self, from: plain) {
            clips = saved
        }
        if let legacy { migrate(from: legacy) }
        for c in recent.reversed() { merge(c) }
        purgeExpired()
        save()
    }

    /// Moves the old plaintext history into the encrypted store, then deletes it.
    private func migrate(from old: URL) {
        let fm = FileManager.default
        guard let d = try? Data(contentsOf: old.appendingPathComponent("history.json")),
              let legacy = try? JSONDecoder().decode([Clip].self, from: d) else { return }
        for var c in legacy where !clips.contains(where: { $0.hash == c.hash }) {
            if let name = c.image {
                guard let png = try? Data(contentsOf: old.appendingPathComponent("images/" + name)), let sealed = encrypt(png) else { continue }
                c.image = c.id + ".png.enc"
                try? sealed.write(to: images.appendingPathComponent(c.image!), options: .atomic)
            }
            clips.append(c)
        }
        clips.sort { $0.date > $1.date }
        try? fm.removeItem(at: old)
        Log.info("clipboard: moved \(legacy.count) items to the encrypted store")
    }

    func stop() { timer?.invalidate(); timer = nil }

    func start() {
        guard timer == nil else { return }
        lastChange = NSPasteboard.general.changeCount  // never record what was copied while off
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    static func ignored(bundleId: String?, name: String?, in list: Set<String>) -> Bool {
        guard !list.isEmpty else { return false }
        return list.contains(bundleId?.lowercased() ?? "\u{0}") || list.contains(name?.lowercased() ?? "\u{0}")
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        let types = pb.types?.map(\.rawValue) ?? []
        guard Self.shouldRecord(types: types), !Self.ignored(bundleId: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                                                     name: NSWorkspace.shared.frontmostApplication?.localizedName, in: ignoreApps) else { return }

        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let text = urls.map(\.path).joined(separator: "\n")
            add(Clip(id: UUID().uuidString, kind: .files, text: text, hash: Self.sha(Data(text.utf8)), date: Date()))
        } else if let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard s.utf8.count <= maxItemBytes else { return }
            add(Clip(id: UUID().uuidString, kind: .text, text: s, hash: Self.sha(Data(s.utf8)), date: Date()))
        } else if let raw = pb.data(forType: .png) ?? pb.data(forType: .tiff), raw.count <= maxItemBytes * 4 {
            // Encode and encrypt off the main thread: a large screenshot can take tens of milliseconds.
            io.async {
                guard let rep = NSBitmapImageRep(data: raw), let png = rep.representation(using: .png, properties: [:]),
                      png.count <= self.maxItemBytes else { return }
                let id = UUID().uuidString, hash = Self.sha(png)
                let name = id + ".png.enc", sealed = self.key.flatMap { _ in self.encrypt(png) }
                DispatchQueue.main.async {
                    if self.clips.contains(where: { $0.hash == hash }) { return self.add(Clip(id: id, kind: .image, text: "", hash: hash, date: Date())) }
                    if let sealed { try? sealed.write(to: self.images.appendingPathComponent(name), options: .atomic) }
                    else { self.thumbs[id] = NSImage(data: png) }   // no key: keep the picture in memory only
                    self.add(Clip(id: id, kind: .image, text: "", image: sealed == nil ? nil : name,
                                  width: rep.pixelsWide, height: rep.pixelsHigh, hash: hash, date: Date()))
                }
            }
        }
    }

    /// Adds to the top; an identical earlier item moves up instead of duplicating.
    private func add(_ c: Clip) {
        merge(c)
        purgeExpired()
        save()
    }

    private func merge(_ c: Clip) {
        if let i = clips.firstIndex(where: { $0.hash == c.hash }) {
            var old = clips.remove(at: i)
            old.date = c.date
            clips.insert(old, at: 0)
        } else {
            clips.insert(c, at: 0)
        }
        while clips.count > maxItems { remove(clips.count - 1) }
    }

    /// Drops items older than `keepDays`.
    func purgeExpired(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Double(max(1, keepDays)) * 86_400)
        let before = clips.count
        while let last = clips.last, last.date < cutoff { remove(clips.count - 1) }
        if clips.count != before { save() }
    }

    private func remove(_ i: Int) {
        let c = clips.remove(at: i)
        thumbs[c.id] = nil
        if let img = c.image { try? FileManager.default.removeItem(at: images.appendingPathComponent(img)) }
    }

    func delete(_ id: String) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        remove(i)
        save()
    }

    func clear() {
        while !clips.isEmpty { remove(0) }
        save()
    }

    private func save() {
        guard key != nil else { return }   // never write history without encryption
        let snapshot = clips, url = index
        io.async {
            guard let d = try? JSONEncoder().encode(snapshot), let sealed = self.encrypt(d) else { return }
            try? sealed.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    func encrypt(_ d: Data) -> Data? { key.flatMap { try? AES.GCM.seal(d, using: $0).combined } }
    func decrypt(_ d: Data) -> Data? { key.flatMap { k in (try? AES.GCM.SealedBox(combined: d)).flatMap { try? AES.GCM.open($0, using: k) } } }

    /// The full image of an image clip, decrypted.
    func image(_ c: Clip) -> NSImage? {
        if let name = c.image, let sealed = try? Data(contentsOf: images.appendingPathComponent(name)), let png = decrypt(sealed) {
            return NSImage(data: png)
        }
        return thumbs[c.id]
    }

    /// A small square thumbnail for the list, cached.
    func thumbnail(_ c: Clip, side: CGFloat) -> NSImage? {
        if let t = thumbs[c.id], c.image != nil { return t }
        guard let full = image(c), let cg = full.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let m = min(cg.width, cg.height)
        guard let sq = cg.cropping(to: CGRect(x: (cg.width - m) / 2, y: (cg.height - m) / 2, width: m, height: m)) else { return nil }
        let t = NSImage(cgImage: sq, size: NSSize(width: side, height: side))
        if c.image != nil { thumbs[c.id] = t }
        return t
    }

    /// Puts a clip back on the pasteboard (it then moves to the top of the history).
    func copy(_ c: Clip) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch c.kind {
        case .text: pb.setString(c.text, forType: .string)
        case .files: pb.writeObjects(c.text.split(separator: "\n").map { NSURL(fileURLWithPath: String($0)) })
        case .image: if let img = image(c) { pb.writeObjects([img]) }
        }
    }

    static func copyText(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private static func sha(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }
}

/// The clipboard's encryption key: 256 random bits in the login Keychain, readable only after
/// first unlock and never synced to other devices.
enum Keychain {
    static let service = "io.github.omerdikyol.fener", account = "clipboard-key"

    static func clipboardKey() -> SymmetricKey? {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                      kSecAttrAccount: account, kSecReturnData: true]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecSuccess, let d = out as? Data, d.count == 32 { return SymmetricKey(data: d) }
        guard status == errSecItemNotFound else {
            Log.error("clipboard: Keychain read failed (\(status))")
            return nil
        }
        let key = SymmetricKey(size: .bits256)
        let add: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
                                    kSecAttrLabel: "fener clipboard history key",
                                    kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                    kSecValueData: key.withUnsafeBytes { Data($0) }]
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { Log.error("clipboard: Keychain write failed (\(added))"); return nil }
        Log.info("clipboard: created the encryption key in the Keychain")
        return key
    }
}
