import Foundation
import Network
import Observation
import AppKit

// NDI® cameras for par 3s (Flagcast Admin → Cameras). TVs and phones can't play NDI, so this Mac receives the
// camera on the club network and
//   1. serves it to the clubhouse TVs as a low-delay HLS stream: a TV opens http://<this Mac>:8790/g/<id>/board,
//      which this Mac passes through to flagcast.app, and the board plays /local-cams/<id>/<hole>/ first;
//   2. pushes it by RTMPS to Cloudflare Stream Live (when Stream is set up), so phones, the live page and replays
//      get it too (the server sets the hole's camera link to the Stream playback address).
// The bridges run while this app is open. NDI comes from the NDI runtime or SDK installed on this Mac; video is
// encoded by ffmpeg (Homebrew), with the Mac's hardware encoder.
// NDI® is a registered trademark of Vizrt NDI AB. https://ndi.video

let NDI_NOTICE = "NDI® is a registered trademark of Vizrt NDI AB. https://ndi.video"
let LOCAL_PORT: UInt16 = 8790

// MARK: - the NDI library (loaded at run time, no SDK headers in the build)

final class NDILib: @unchecked Sendable {
    static let shared = NDILib()
    private typealias FInit = @convention(c) () -> Bool
    private typealias FFindCreate = @convention(c) (UnsafeRawPointer?) -> OpaquePointer?
    private typealias FFindWait = @convention(c) (OpaquePointer?, UInt32) -> Bool
    private typealias FFindSources = @convention(c) (OpaquePointer?, UnsafeMutablePointer<UInt32>) -> UnsafeRawPointer?
    private typealias FRecvCreate = @convention(c) (UnsafeRawPointer?) -> OpaquePointer?
    private typealias FRecvCapture = @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UInt32) -> Int32
    private typealias FRecvFree = @convention(c) (OpaquePointer?, UnsafeRawPointer?) -> Void
    private typealias FRecvDestroy = @convention(c) (OpaquePointer?) -> Void

    private var findCreate: FFindCreate?, findWait: FFindWait?, findSources: FFindSources?
    private var recvCreate: FRecvCreate?, recvCapture: FRecvCapture?, recvFree: FRecvFree?, recvDestroy: FRecvDestroy?
    let loaded: Bool

    private init() {
        let paths = [Bundle.main.privateFrameworksPath.map { "\($0)/libndi.dylib" }, "/usr/local/lib/libndi.dylib",
                     "/Library/NDI SDK for Apple/lib/macOS/libndi.dylib", "/Library/NDI Runtime/lib/libndi.dylib"].compactMap { $0 }
        var h: UnsafeMutableRawPointer?
        for p in paths where FileManager.default.fileExists(atPath: p) { h = dlopen(p, RTLD_NOW); if h != nil { break } }
        func sym<T>(_ n: String) -> T? { h.flatMap { dlsym($0, n) }.map { unsafeBitCast($0, to: T.self) } }
        let initialize: FInit? = sym("NDIlib_initialize")
        findCreate = sym("NDIlib_find_create_v2"); findWait = sym("NDIlib_find_wait_for_sources"); findSources = sym("NDIlib_find_get_current_sources")
        recvCreate = sym("NDIlib_recv_create_v3"); recvCapture = sym("NDIlib_recv_capture_v3"); recvFree = sym("NDIlib_recv_free_video_v2"); recvDestroy = sym("NDIlib_recv_destroy")
        loaded = initialize?() == true && findCreate != nil && recvCreate != nil && recvCapture != nil
    }

    // NDIlib_find_create_t { bool show_local_sources; const char* p_groups; const char* p_extra_ips; } = 24 bytes
    func makeFinder() -> OpaquePointer? {
        guard loaded else { return nil }
        let s = UnsafeMutableRawPointer.allocate(byteCount: 24, alignment: 8); defer { s.deallocate() }
        s.initializeMemory(as: UInt8.self, repeating: 0, count: 24)
        s.storeBytes(of: true, as: Bool.self)
        return findCreate?(UnsafeRawPointer(s))
    }
    /// The NDI sources on the network now (NDIlib_source_t is two C strings: name, address).
    func sources(_ finder: OpaquePointer?, wait ms: UInt32) -> [String] {
        guard let finder else { return [] }
        _ = findWait?(finder, ms)
        var n: UInt32 = 0
        guard let p = findSources?(finder, &n), n > 0 else { return [] }
        return (0..<Int(n)).compactMap { i in p.load(fromByteOffset: i * 16, as: UnsafePointer<CChar>?.self).map { String(cString: $0) } }
    }
    // NDIlib_recv_create_v3_t { source_t (2 ptrs); color_format i32; bandwidth i32; bool allow_fields; const char* name } = 40 bytes
    func makeReceiver(_ source: String) -> OpaquePointer? {
        guard loaded else { return nil }
        let s = UnsafeMutableRawPointer.allocate(byteCount: 40, alignment: 8); defer { s.deallocate() }
        s.initializeMemory(as: UInt8.self, repeating: 0, count: 40)
        return source.withCString { src in
            "Flagcast camera".withCString { name in
                s.storeBytes(of: src, toByteOffset: 0, as: UnsafePointer<CChar>.self)
                s.storeBytes(of: Int32(1), toByteOffset: 16, as: Int32.self)        // UYVY (BGRA only with alpha): half the bytes
                s.storeBytes(of: Int32(100), toByteOffset: 20, as: Int32.self)      // highest bandwidth
                s.storeBytes(of: false, toByteOffset: 24, as: Bool.self)            // no fields
                s.storeBytes(of: name, toByteOffset: 32, as: UnsafePointer<CChar>.self)
                return recvCreate?(UnsafeRawPointer(s))
            }
        }
    }
    struct Frame { var w: Int, h: Int, stride: Int, fpsN: Int32, fpsD: Int32, uyvy: Bool, data: UnsafeMutablePointer<UInt8> }
    /// One video frame (NDIlib_video_frame_v2_t, 72 bytes), or nil after `ms` (or when the source is gone).
    func capture(_ r: OpaquePointer?, ms: UInt32, _ use: (Frame) -> Void) -> Bool? {
        let v = UnsafeMutableRawPointer.allocate(byteCount: 80, alignment: 8); defer { v.deallocate() }
        v.initializeMemory(as: UInt8.self, repeating: 0, count: 80)
        let t = recvCapture?(r, v, nil, nil, ms) ?? 0
        if t == 4 { return nil }                      // NDIlib_frame_type_error: connection lost
        guard t == 1 else { return false }            // video
        let w = Int(v.load(fromByteOffset: 0, as: Int32.self)), h = Int(v.load(fromByteOffset: 4, as: Int32.self))
        let n = v.load(fromByteOffset: 12, as: Int32.self), d = v.load(fromByteOffset: 16, as: Int32.self)
        if let data = v.load(fromByteOffset: 40, as: UnsafeMutablePointer<UInt8>?.self) {
            let fourcc = v.load(fromByteOffset: 8, as: UInt32.self)       // 'UYVY' = 0x59565955
            use(Frame(w: w, h: h, stride: Int(v.load(fromByteOffset: 48, as: Int32.self)), fpsN: n, fpsD: d, uyvy: fourcc == 0x59565955, data: data))
        }
        recvFree?(r, UnsafeRawPointer(v))
        return true
    }
    func destroy(_ r: OpaquePointer?) { recvDestroy?(r) }
}

// MARK: - the bridges

/// State the camera threads and the TV server read off the main thread.
final class Shared<T>: @unchecked Sendable {
    private let lock = NSLock(); private var v: T
    init(_ v: T) { self.v = v }
    var value: T { get { lock.lock(); defer { lock.unlock() }; return v } set { lock.lock(); v = newValue; lock.unlock() } }
}

/// The NDI sources seen on the network (looked up every few seconds while Admin → Cameras is open).
@MainActor @Observable
final class NDISources {
    static let shared = NDISources()
    var names: [String] = []
    var available: Bool { NDILib.shared.loaded }
    @ObservationIgnored private var running = false
    func watch() {
        guard !running, NDILib.shared.loaded else { return }
        running = true
        Thread.detachNewThread {
            let f = NDILib.shared.makeFinder()
            while true {
                let list = NDILib.shared.sources(f, wait: 2500).sorted()
                Task { @MainActor in if NDISources.shared.names != list { NDISources.shared.names = list } }
                Thread.sleep(forTimeInterval: 1.5)
            }
        }
    }
}

/// One par 3's NDI camera: receive → ffmpeg → local HLS (+ RTMPS to Cloudflare Stream).
@MainActor @Observable
final class CameraBridge: Identifiable {
    nonisolated let id: String
    let event: String, hole: Int, source: String
    var state = "Starting…"
    var receiving = false
    var uploading: Bool?            // nil: no cloud push
    var size = ""
    var lastFrame: Date { get { lastSeen.value } set { lastSeen.value = newValue } }
    nonisolated let lastSeen = Shared(Date.distantPast)
    nonisolated private let stopFlag = Shared(false)
    @ObservationIgnored private var proc: Process?
    @ObservationIgnored private let rtmps: String?

    init(event: String, hole: Int, source: String, rtmps: String?) {
        self.event = event; self.hole = hole; self.source = source; self.rtmps = rtmps
        id = "\(event)-\(hole)"
        uploading = rtmps == nil ? nil : false
    }
    var dir: URL { Bridges.root.appendingPathComponent(event).appendingPathComponent("\(hole)") }

    func start() {
        guard let ffmpeg = Bridges.ffmpeg else { state = "Needs ffmpeg: in Terminal, brew install ffmpeg"; return }
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dir = self.dir, src = source, rtmps = self.rtmps
        Thread.detachNewThread { [weak self] in
            let r = NDILib.shared.makeReceiver(src)
            var pipe: FileHandle?, shape = ""
            var buf = [UInt8]()
            let stopped = self?.stopFlag
            while let me = self, stopped?.value == false {
                let got = NDILib.shared.capture(r, ms: 1000) { f in
                    let s = "\(f.w)x\(f.h)@\(f.fpsN)/\(max(1, f.fpsD))\(f.uyvy ? "u" : "b")"
                    if s != shape {        // first frame, or the camera changed size: (re)start the encoder
                        shape = s; pipe = nil
                        let p = CameraBridge.encoder(ffmpeg, w: f.w, h: f.h, uyvy: f.uyvy, fps: f.fpsN > 0 ? Double(f.fpsN) / Double(max(1, f.fpsD)) : 30, dir: dir, rtmps: rtmps)
                        Task { @MainActor in me.swap(p.0); me.size = "\(f.w)×\(f.h)" }
                        pipe = p.1
                    }
                    let row = f.w * (f.uyvy ? 2 : 4)
                    if f.stride == row { pipe?.write(Data(bytesNoCopy: f.data, count: row * f.h, deallocator: .none)) }
                    else {
                        if buf.count != row * f.h { buf = [UInt8](repeating: 0, count: row * f.h) }
                        buf.withUnsafeMutableBytes { b in for y in 0..<f.h { memcpy(b.baseAddress! + y * row, f.data + y * f.stride, row) } }
                        pipe?.write(Data(buf))
                    }
                }
                let now = Date()
                Task { @MainActor in
                    if got == true { me.lastFrame = now; if !me.receiving { me.receiving = true; me.state = "Receiving" } }
                    else if now.timeIntervalSince(me.lastFrame) > 3 { me.receiving = false; me.state = got == nil ? "Source lost: looking for it again" : "No signal from \(src)" }
                }
            }
            NDILib.shared.destroy(r)
            try? pipe?.close()
        }
    }
    private func swap(_ p: Process) { proc?.terminate(); proc = p; watch(p) }
    func stop() { stopFlag.value = true; proc?.terminate(); proc = nil; receiving = false; state = "Stopped" }

    /// Upload health from ffmpeg's messages (RTMPS errors mean the cloud push stopped).
    private func watch(_ p: Process) {
        guard let err = p.standardError as? Pipe else { return }
        err.fileHandleForReading.readabilityHandler = { [weak self] h in
            let s = String(decoding: h.availableData, as: UTF8.self)
            guard !s.isEmpty else { h.readabilityHandler = nil; return }
            #if DEBUG
            FileHandle.standardError.write(Data("ffmpeg: \(s)".utf8))
            #endif
            Task { @MainActor in
                guard let self, self.rtmps != nil else { return }
                if s.contains("frame=") { self.uploading = true }
                if s.localizedCaseInsensitiveContains("rtmp") && (s.localizedCaseInsensitiveContains("error") || s.localizedCaseInsensitiveContains("failed")) { self.uploading = false }
            }
        }
    }

    /// ffmpeg: raw frames in (UYVY, or BGRA with alpha) → H.264 (hardware) → 1-second HLS segments here, and the same to RTMPS.
    nonisolated static func encoder(_ ffmpeg: String, w: Int, h: Int, uyvy: Bool, fps: Double, dir: URL, rtmps: String?) -> (Process, FileHandle) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        let fpsS = String(format: "%.3f", fps), gop = "\(max(1, Int(fps.rounded())))"
        // each output gets its own queue (use_fifo), so a slow or failing upload never holds up the TVs' copy or the camera
        let hls = "[f=hls:use_fifo=1:hls_time=1:hls_list_size=8:hls_flags=delete_segments+independent_segments+omit_endlist+program_date_time:hls_segment_filename=\(dir.path)/s%05d.ts]\(dir.path)/index.m3u8"
        var outs = [hls]
        if let rtmps { outs.append("[f=flv:onfail=ignore:use_fifo=1:fifo_options=drop_pkts_on_overflow=1\\:attempt_recovery=1\\:recovery_wait_time=2\\:queue_size=120]\(rtmps)") }
        p.arguments = ["-hide_banner", "-loglevel", "warning", "-stats", "-stats_period", "5",
                       "-thread_queue_size", "64", "-f", "rawvideo", "-pix_fmt", uyvy ? "uyvy422" : "bgra", "-s", "\(w)x\(h)", "-framerate", fpsS, "-i", "pipe:0",
                       "-re", "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",     // silent sound, at real speed (Stream wants audio)
                       "-map", "0:v", "-map", "1:a", "-shortest",
                       "-c:v", "h264_videotoolbox", "-realtime", "1", "-b:v", "5M", "-maxrate", "6M", "-g", gop, "-pix_fmt", "yuv420p",
                       "-c:a", "aac", "-b:a", "96k",
                       "-f", "tee", outs.joined(separator: "|")]
        let input = Pipe()
        p.standardInput = input
        p.standardError = Pipe(); p.standardOutput = FileHandle.nullDevice
        try? p.run()
        return (p, input.fileHandleForWriting)
    }
}

/// Every running NDI camera, the local server for the clubhouse TVs, and quitting with cameras running.
@MainActor @Observable
final class Bridges {
    static let shared = Bridges()
    var running: [String: CameraBridge] = [:] { didSet { seen.value = running.values.map { ($0.event, $0.hole, $0.lastSeen) } } }
    nonisolated private let seen = Shared<[(String, Int, Shared<Date>)]>([])
    var serverError: String?
    static let root: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("local-cams")
    static let ffmpeg: String? = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.isExecutableFile(atPath: $0) }
    @ObservationIgnored private var server: LocalServer?

    func bridge(_ event: String, _ hole: Int) -> CameraBridge? { running["\(event)-\(hole)"] }
    func start(event: String, hole: Int, source: String, rtmps: String?) {
        stop(event: event, hole: hole)
        let b = CameraBridge(event: event, hole: hole, source: source, rtmps: rtmps)
        running[b.id] = b
        b.start()
        if server == nil { server = LocalServer(); do { try server?.start() } catch { serverError = "The TV address couldn’t start: \(error.localizedDescription)" } }
        UserDefaults.standard.set(source, forKey: "ndi.\(b.id)")
    }
    func stop(event: String, hole: Int) {
        running.removeValue(forKey: "\(event)-\(hole)")?.stop()
        UserDefaults.standard.removeObject(forKey: "ndi.\(event)-\(hole)")
    }
    func stopAll() { for b in running.values { b.stop() }; running = [:] }
    /// holes of one tournament with frames in the last few seconds (for the board's /local-cams/<id>/index.json)
    nonisolated func liveHoles(_ event: String) -> [Int] {
        seen.value.filter { $0.0 == event && Date().timeIntervalSince($0.2.value) < 5 }.map(\.1)
    }
    /// what a clubhouse TV opens to get the local cameras: http://<this Mac on the club network>:8790/g/<id>/board
    static func tvURL(_ event: String) -> String? { lanAddress().map { "http://\($0):\(LOCAL_PORT)/g/\(event)/board" } }
    static func lanAddress() -> String? {
        var ifs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifs) == 0, let first = ifs else { return nil }
        defer { freeifaddrs(ifs) }
        var best: String?
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let a = p.pointee
            guard let sa = a.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET), (Int32(a.ifa_flags) & IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host), name = String(cString: a.ifa_name)
            if name == "en0" { return ip }
            if best == nil, name.hasPrefix("en") { best = ip }
        }
        return best
    }
}

// MARK: - the local server for clubhouse TVs

/// http://<this Mac>:8790: /local-cams/… from this Mac; everything else passed through to flagcast.app (pages, API
/// and the live WebSocket), so a TV's board page and its local cameras come from the same place.
final class LocalServer: @unchecked Sendable {
    private var listener: NWListener?
    private let q = DispatchQueue(label: "flagcast.localserver")

    func start() throws {
        let l = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: LOCAL_PORT)!)
        l.newConnectionHandler = { [weak self] c in self?.handle(c) }
        l.start(queue: q)
        listener = l
    }

    private func handle(_ c: NWConnection) {
        c.start(queue: q)
        readHead(c, Data()) { [weak self] head, rest in
            guard let self, let head, let text = String(data: head, encoding: .utf8) else { c.cancel(); return }
            let line = text.split(separator: "\r\n").first.map(String.init) ?? ""
            let parts = line.split(separator: " ")
            let path = parts.count > 1 ? String(parts[1]) : "/"
            if path.hasPrefix("/local-cams/") { self.serveLocal(c, path) } else { self.proxy(c, text, rest) }
        }
    }
    private func readHead(_ c: NWConnection, _ got: Data, _ done: @escaping (Data?, Data) -> Void) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { d, _, end, err in
            var all = got; if let d { all.append(d) }
            if let r = all.range(of: Data("\r\n\r\n".utf8)) { done(all.subdata(in: 0..<r.upperBound), all.subdata(in: r.upperBound..<all.count)); return }
            if end || err != nil || all.count > 65536 { done(nil, Data()); return }
            self.readHead(c, all, done)
        }
    }
    private func serveLocal(_ c: NWConnection, _ rawPath: String) {
        let path = rawPath.split(separator: "?").first.map(String.init) ?? rawPath
        let parts = path.split(separator: "/").map(String.init)   // ["local-cams", id, (hole, file) | "index.json"]
        var status = "404 Not Found", type = "text/plain", body = Data("Not found".utf8)
        if parts.count == 3, parts[2] == "index.json" {
            let holes = Dictionary(uniqueKeysWithValues: Bridges.shared.liveHoles(parts[1]).map { ("\($0)", true) })
            body = (try? JSONSerialization.data(withJSONObject: ["holes": holes])) ?? Data("{}".utf8); status = "200 OK"; type = "application/json"
        } else if parts.count == 4, parts[1].allSatisfy({ $0.isLetter || $0.isNumber }), Int(parts[2]) != nil,
                  parts[3].range(of: #"^(index\.m3u8|s\d+\.ts)$"#, options: .regularExpression) != nil {
            let f = Bridges.root.appendingPathComponent(parts[1]).appendingPathComponent(parts[2]).appendingPathComponent(parts[3])
            if let d = try? Data(contentsOf: f) { body = d; status = "200 OK"; type = parts[3].hasSuffix(".m3u8") ? "application/vnd.apple.mpegurl" : "video/mp2t" }
        }
        let head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
        c.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in c.cancel() })
    }
    /// Pass the request to flagcast.app over HTTPS and copy bytes both ways (a WebSocket stays open the same way).
    private func proxy(_ c: NWConnection, _ head: String, _ rest: Data) {
        let base = Server.base
        let host = base.host ?? "flagcast.app", tls = base.scheme == "https", port = base.port ?? (tls ? 443 : 80)
        var lines = head.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        let upgrade = lines.contains { $0.lowercased().hasPrefix("upgrade:") }
        lines = lines.enumerated().compactMap { i, l in
            if i == 0 { return l }
            let k = l.lowercased()
            if k.hasPrefix("host:") { return "Host: \(host)" + (base.port.map { ":\($0)" } ?? "") }
            if !upgrade && k.hasPrefix("connection:") { return nil }
            if k.hasPrefix("origin:") { return "Origin: \(base.scheme ?? "https")://\(host)" }
            return l
        }
        if !upgrade { lines.append("Connection: close") }
        let up = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: tls ? .tls : .tcp)
        up.start(queue: q)
        up.send(content: Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8) + rest, completion: .contentProcessed { _ in })
        pump(c, up); pump(up, c)
    }
    private func pump(_ from: NWConnection, _ to: NWConnection) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 262144) { [weak self] d, _, end, err in
            if let d, !d.isEmpty { to.send(content: d, completion: .contentProcessed { _ in }) }
            if end || err != nil { to.send(content: nil, isComplete: true, completion: .contentProcessed { _ in to.cancel(); from.cancel() }); return }
            self?.pump(from, to)
        }
    }
}
