import Foundation

/// Line protocol over a Unix domain socket: the client sends "command args\n",
/// the app answers "ok\n" or "error: …\n" and closes. Socket is mode 0600 in the cache dir.
enum IPC {
    static let commands: Set = ["toggle", "show", "hide", "reload", "ping", "query"]

    static var socketPath: String {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("fener")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("fener.sock").path
    }

    private static func address(_ path: String) -> sockaddr_un {
        var a = sockaddr_un()
        a.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &a.sun_path) { buf in
            path.utf8CString.withUnsafeBytes { buf.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(buf.count - 1))) }
        }
        return a
    }

    /// True when an instance already answers on the socket.
    static func isRunning() -> Bool {
        guard let fd = connect(socketPath) else { return false }
        close(fd)
        return true
    }

    private static func connect(_ path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var a = address(path)
        let ok = withUnsafePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if ok != 0 { close(fd); return nil }
        return fd
    }

    private static func setTimeout(_ fd: Int32, seconds: Int) {
        var tv = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func readAll(_ fd: Int32, untilNewline: Bool) -> String {
        var data = [UInt8](), buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            data += buf[0..<n]
            if untilNewline, data.contains(10) { break }
            if data.count > 65536 { break }
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Client side. Returns the process exit code.
    static func send(_ args: [String]) -> Int32 {
        signal(SIGPIPE, SIG_IGN)
        guard let fd = connect(socketPath) else {
            FileHandle.standardError.write("fener: app is not running (start it with `fener` or the LaunchAgent)\n".data(using: .utf8)!)
            return 2
        }
        defer { close(fd) }
        setTimeout(fd, seconds: 3)
        let line = args.joined(separator: " ") + "\n"
        _ = line.withCString { write(fd, $0, strlen($0)) }
        let reply = readAll(fd, untilNewline: false).trimmingCharacters(in: .whitespacesAndNewlines)
        if reply == "ok" { return 0 }
        if reply.hasPrefix("ok\n") { print(reply.dropFirst(3)); return 0 }
        FileHandle.standardError.write("fener: \(reply.isEmpty ? "no reply" : reply)\n".data(using: .utf8)!)
        return 1
    }

    /// Server side. Calls `handle` on the main queue with the words of each request.
    final class Server {
        private let fd: Int32
        private let source: DispatchSourceRead

        /// Returns nil when another instance already answers on the socket.
        init?(path: String, handle: @escaping ([String]) -> String) {
            if let other = IPC.connect(path) { close(other); return nil }
            signal(SIGPIPE, SIG_IGN)  // a client that hangs up early must not kill the app
            unlink(path)
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            self.fd = fd
            var a = IPC.address(path)
            let old = umask(0o177)  // socket file becomes 0600
            let bound = withUnsafePointer(to: &a) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            umask(old)
            guard fd >= 0, bound == 0, listen(fd, 8) == 0 else { fatalError("fener: cannot listen on \(path): \(String(cString: strerror(errno)))") }
            source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [fd] in
                let c = accept(fd, nil, nil)
                guard c >= 0 else { return }
                IPC.setTimeout(c, seconds: 1)
                let words = IPC.readAll(c, untilNewline: true)
                    .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\r" }).map(String.init)
                let reply = words.isEmpty ? "error: empty request" : handle(words)
                _ = (reply + "\n").withCString { write(c, $0, strlen($0)) }
                close(c)
            }
            source.resume()
        }
    }
}
