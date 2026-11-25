import SwiftUI
import AVFoundation
import UIKit
import VideoToolbox
import HaishinKit
import SRTHaishinKit
import RTMPHaishinKit

// Go live from an iPhone at the hole. Pros (the player app's pro tools, with their PIN), club staff and Flagcast
// Admin (Manager) pick a hole and send this phone's camera to it. The server (golf.js day op "golive") hands back the
// hole's Cloudflare Stream live input and points the hole's camera link at it, so the club TVs, the players' Cameras
// tab, the live page and replays play it like any par 3 camera. Stop takes it off again.
// Shared by the player app (ProView) and Manager (ScreensSide), so it only uses plain SwiftUI colours.
//
// The phone sends with SRT (it copes with a patchy cell signal better), or RTMPS if SRT can't connect. The picture is
// 1280 × 720 landscape, and the bitrate drops by itself when the signal does (StreamVideoAdaptiveBitRateStrategy).

/// One hole on the picker.
struct GoLiveHole: Hashable, Identifiable {
    var n: Int, par: Int, yds: Int
    var id: Int { n }
}

/// Sends a "golive" day op (with the desk key or the pro's PIN) and gives back the server's answer, or throws its words.
typealias GoLiveSend = @MainActor (_ body: [String: Any]) async throws -> [String: Any]

@MainActor @Observable
final class GoLiveModel {
    enum Phase: Equatable { case setup, starting, live, stopping, ended }
    enum Signal { case good, weak, lost }

    let holes: [GoLiveHole]
    private let send: GoLiveSend
    var hole: Int?
    var phase: Phase = .setup
    var message: String?
    var toTVs = true
    var toPhones = false
    /// connected to Cloudflare and sending
    private(set) var connected = false
    private(set) var signal: Signal = .lost
    private(set) var kbps = 0
    private(set) var startedAt: Date?
    private(set) var battery: Float = -1
    private(set) var charging = false
    private(set) var hot = false
    /// the phone is upright: the picture is still sent sideways, so ask them to turn it
    private(set) var upright = false
    private(set) var cameraReady = false
    private(set) var cameraDenied = false
    var dimmed = false

    @ObservationIgnored let mixer = MediaMixer()
    @ObservationIgnored private var session: (any StreamSession)?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var lastWeak = Date.distantPast
    @ObservationIgnored private var lastTouch = Date()
    @ObservationIgnored private var brightness: CGFloat = 0.5
    @ObservationIgnored private var orientation: AVCaptureVideoOrientation = .landscapeRight
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var output: MTHKView?
    @ObservationIgnored private var creds: [String: Any] = [:]
    @ObservationIgnored private static var registered = false

    init(holes: [GoLiveHole], send: @escaping GoLiveSend) {
        self.holes = holes
        self.send = send
        hole = holes.first(where: { $0.par == 3 })?.n
    }

    // MARK: camera

    /// Asks for the camera, then starts the preview (nothing is sent yet).
    func open() async {
        if !Self.registered {
            Self.registered = true
            await StreamSessionBuilderFactory.shared.register(SRTSessionFactory())
            await StreamSessionBuilderFactory.shared.register(RTMPSessionFactory())
        }
        var ok = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if !ok { ok = await AVCaptureDevice.requestAccess(for: .video) }
        guard ok else { cameraDenied = true; return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        readBattery()
        followOrientation()
        observers.append(NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.followOrientation() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.hot = [.serious, .critical].contains(ProcessInfo.processInfo.thermalState) }
        })
        hot = [.serious, .critical].contains(ProcessInfo.processInfo.thermalState)
        brightness = UIScreen.main.brightness
        let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        try? await mixer.setFrameRate(30)
        try? await mixer.attachVideo(back, track: 0) { unit in unit.isVideoMirrored = false }
        await mixer.setVideoOrientation(orientation)
        await mixer.startRunning()
        if let output { await mixer.addOutput(output) }
        cameraReady = true
        // battery, the "dim the screen" timer and the signal, every few seconds
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self else { return }
                self.tick()
            }
        })
    }

    func attach(_ view: MTHKView) {
        output = view
        guard cameraReady else { return }
        Task { await mixer.addOutput(view) }
    }

    private func followOrientation() {
        switch UIDevice.current.orientation {
        case .landscapeLeft: orientation = .landscapeRight; upright = false
        case .landscapeRight: orientation = .landscapeLeft; upright = false
        case .portrait, .portraitUpsideDown: upright = true
        default: break
        }
        Task { await mixer.setVideoOrientation(orientation) }
    }

    private func readBattery() {
        battery = UIDevice.current.batteryLevel
        charging = [.charging, .full].contains(UIDevice.current.batteryState)
    }

    private func tick() {
        readBattery()
        if phase == .live {
            signal = !connected ? .lost : Date().timeIntervalSince(lastWeak) < 10 || kbps < 300 ? .weak : .good
            // dim the screen after a minute untouched, to save battery (a tap brings it back)
            if !dimmed && Date().timeIntervalSince(lastTouch) > 60 { dimmed = true; UIScreen.main.brightness = 0.05 }
        }
    }

    func touched() {
        lastTouch = Date()
        if dimmed { dimmed = false; UIScreen.main.brightness = brightness }
    }

    // MARK: going live

    func start() async {
        guard let hole, phase == .setup || phase == .ended else { return }
        phase = .starting; message = nil
        do {
            creds = try await send(["op": "golive", "hole": hole])
        } catch {
            phase = .setup; message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription; return
        }
        // SRT first, RTMPS if SRT can't get through
        var urls: [URL] = []
        if let srt = creds["srt"] as? [String: Any], let u = Self.srtURL(srt) { urls.append(u) }
        if let r = creds["rtmps"] as? [String: Any], let u = Self.rtmpsURL(r) { urls.append(u) }
        guard !urls.isEmpty else { await stopOnServer(); phase = .setup; message = "Flagcast didn’t send a place to stream to. Try again."; return }
        for url in urls {
            if await connect(url) {
                phase = .live; startedAt = Date(); lastTouch = Date(); signal = .good
                UIApplication.shared.isIdleTimerDisabled = true
                await route()
                return
            }
        }
        await stopOnServer()
        phase = .setup
        message = "Couldn’t get the video out from here. Check the phone has signal (or Wi‑Fi) and try again."
    }

    /// Sends the picture to one address. true when it connected.
    private func connect(_ url: URL) async -> Bool {
        do {
            guard let s = try await StreamSessionBuilderFactory.shared.make(url).setMode(.publish).build() else { return false }
            var v = await s.stream.videoSettings
            v.videoSize = CGSize(width: 1280, height: 720)
            v.bitRate = 2_500_000
            v.profileLevel = kVTProfileLevel_H264_High_AutoLevel as String
            v.maxKeyFrameIntervalDuration = 2
            v.expectedFrameRate = 30
            try? await s.stream.setVideoSettings(v)
            await s.stream.setBitRateStrategy(GoLiveRate(inner: StreamVideoAdaptiveBitRateStrategy(mamimumVideoBitrate: 2_500_000)) { [weak self] bytes, weak in
                Task { @MainActor in
                    guard let self else { return }
                    self.kbps = bytes * 8 / 1000
                    if weak { self.lastWeak = Date() }
                }
            })
            await s.setMaxRetryCount(20)
            await mixer.addOutput(s.stream)
            session = s
            tasks.append(Task { [weak self] in
                for await state in await s.readyState {
                    guard let self else { return }
                    self.connected = state == .open
                    if state != .open && self.phase == .live { self.signal = .lost }
                }
            })
            try await s.connect { }
            return true
        } catch {
            if let s = session { await mixer.removeOutput(s.stream); try? await s.close() }
            session = nil
            return false
        }
    }

    /// Put it on the TVs and the players' phones if they asked.
    private func route() async {
        guard let hole else { return }
        if toTVs { _ = try? await send(["op": "screen", "display": "*", "page": ["k": "cam", "hole": hole]]) }
        if toPhones { await sendToPhones() }
        if toTVs && toPhones { message = "On the TVs and players’ phones" } else if toTVs { message = "On the TVs" }
    }

    func sendToPhones() async {
        guard let hole else { return }
        do {
            _ = try await send(["op": "screen", "display": ["phones"], "page": ["k": "cam", "hole": hole], "text": "Live from the course"])
            message = "Sent to players’ phones. They get a Watch banner."
        } catch { message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    func stop() async {
        guard phase == .live || phase == .starting else { return }
        phase = .stopping
        if let s = session { await mixer.removeOutput(s.stream); try? await s.close() }
        session = nil; connected = false
        await stopOnServer()
        UIApplication.shared.isIdleTimerDisabled = false
        touched()
        phase = .ended; startedAt = nil
        message = "Stopped. The TVs and phones are back to normal."
    }

    private func stopOnServer() async {
        guard let hole else { return }
        _ = try? await send(["op": "golive", "hole": hole, "stop": true])
    }

    /// Leaving the screen: stop sending and put the camera away.
    func close() async {
        await stop()
        for t in tasks { t.cancel() }
        tasks.removeAll()
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        if let output { await mixer.removeOutput(output) }
        await mixer.stopRunning()
        try? await mixer.attachVideo(nil, track: 0)
        if dimmed { UIScreen.main.brightness = brightness; dimmed = false }
    }

    // MARK: addresses

    /// srt://live.cloudflare.com:778?streamid=…&passphrase=… (HaishinKit reads the query as it is, so only plain values)
    static func srtURL(_ srt: [String: Any]) -> URL? {
        guard let base = srt["url"] as? String, base.hasPrefix("srt://"), let sid = srt["streamId"] as? String, !sid.isEmpty else { return nil }
        let pass = srt["passphrase"] as? String ?? ""
        let plain = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
        guard sid.unicodeScalars.allSatisfy(plain.contains), pass.unicodeScalars.allSatisfy(plain.contains) else { return nil }
        return URL(string: "\(base)?mode=caller&streamid=\(sid)" + (pass.isEmpty ? "" : "&passphrase=\(pass)"))
    }

    /// rtmps://live.cloudflare.com:443/live/<stream key>
    static func rtmpsURL(_ r: [String: Any]) -> URL? {
        guard let base = r["url"] as? String, base.hasPrefix("rtmp"), let key = r["streamKey"] as? String, !key.isEmpty else { return nil }
        return URL(string: (base.hasSuffix("/") ? base : base + "/") + key)
    }

    var elapsed: String {
        guard let startedAt else { return "" }
        let s = Int(Date().timeIntervalSince(startedAt))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

extension GoLiveModel: MTHKViewRepresentable.PreviewSource {
    nonisolated func connect(to view: MTHKView) {
        Task { @MainActor in self.attach(view) }
    }
}

/// The adaptive bitrate, plus the upload rate and "not enough signal" for the screen.
struct GoLiveRate: StreamBitRateStrategy {
    let inner: StreamVideoAdaptiveBitRateStrategy
    let report: @Sendable (_ bytesPerSecond: Int, _ weak: Bool) -> Void
    var mamimumVideoBitRate: Int { inner.mamimumVideoBitRate }
    var mamimumAudioBitRate: Int { 0 }
    func adjustBitrate(_ event: NetworkMonitorEvent, stream: some StreamConvertible) async {
        switch event {
        case .status(let r): report(r.currentBytesOutPerSecond, false)
        case .publishInsufficientBWOccured(let r): report(r.currentBytesOutPerSecond, true)
        case .reset: break
        }
        await inner.adjustBitrate(event, stream: stream)
    }
}

// MARK: - the screen

struct GoLiveView: View {
    @State var model: GoLiveModel
    /// who else is live now (hole → name), from the live feed
    var liveNow: [Int: String] = [:]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmStop = false

    private static let red = Color(red: 0.78, green: 0.19, blue: 0.17)
    private static let gold = Color(red: 0.91, green: 0.77, blue: 0.28)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if model.cameraDenied {
                denied
            } else {
                MTHKViewRepresentable(previewSource: model, videoGravity: .resizeAspect).ignoresSafeArea()
                if model.phase == .live || model.phase == .stopping { liveOverlay } else { setupOverlay }
            }
            if model.dimmed { Color.black.opacity(0.85).ignoresSafeArea().allowsHitTesting(false) }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { model.touched() })
        .statusBarHidden(model.phase == .live)
        .task { await model.open() }
        .onDisappear { Task { await model.close() } }
        .confirmationDialog("Stop the live video?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop", role: .destructive) { Task { await model.stop() } }
        } message: { Text("The TVs and players’ phones go back to normal.") }
    }

    // before going live: hole, checks, where it shows
    private var setupOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Button { Task { await model.close(); dismiss() } } label: {
                    Image(systemName: "xmark").font(.headline).foregroundStyle(.white).padding(10).background(.black.opacity(0.5), in: Circle())
                }
                .accessibilityLabel("Close")
                Spacer()
                if model.upright { pill("Turn the phone sideways", systemImage: "rotate.right", bg: Self.gold, fg: .black) }
            }
            .padding()
            Spacer()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Go live").font(.title2.bold())
                    Text("Which hole?").font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 9), spacing: 6) {
                        ForEach(model.holes) { h in
                            let taken = liveNow[h.n] != nil
                            Button { model.hole = h.n } label: {
                                Text("\(h.n)").font(.subheadline.weight(.bold)).frame(maxWidth: .infinity, minHeight: 34)
                                    .background(model.hole == h.n ? Color(red: 0.07, green: 0.21, blue: 0.16) : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(h.par == 3 ? Self.gold : .clear, lineWidth: 1.5))
                                    .foregroundStyle(model.hole == h.n ? .white : taken ? .secondary : .primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Hole \(h.n), par \(h.par)\(taken ? ", already live" : "")")
                        }
                    }
                    if let h = model.hole, let who = liveNow[h] {
                        Label("Hole \(h) is live from \(who)’s phone now.", systemImage: "video.fill").font(.footnote).foregroundStyle(.orange)
                    }
                    VStack(spacing: 0) {
                        row("Battery", model.battery < 0 ? "—" : "\(Int(model.battery * 100))%" + (model.charging ? " · charging" : " · plug in a power pack"),
                            warn: !model.charging && model.battery >= 0 && model.battery < 0.8)
                        Divider()
                        row("Picture", "720p, lower on a weak signal", warn: false)
                        if model.hot { Divider(); row("Heat", "The phone is hot. Shade it or it may stop the camera.", warn: true) }
                        Divider()
                        Toggle("Put on the club TVs", isOn: $model.toTVs).padding(.vertical, 8)
                        Divider()
                        Toggle("Tell players’ phones", isOn: $model.toPhones).padding(.vertical, 8)
                    }
                    .font(.subheadline)
                    if let m = model.message { Text(m).font(.footnote).foregroundStyle(model.phase == .ended ? Color.secondary : Color.orange) }
                    Button { Task { await model.start() } } label: {
                        HStack {
                            if model.phase == .starting { ProgressView().tint(.white) } else { Image(systemName: "record.circle") }
                            Text(model.phase == .starting ? "Starting…" : model.hole.map { "Go live on hole \($0)" } ?? "Pick a hole")
                        }
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                        .background(Self.red, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white)
                    }
                    .disabled(model.hole == nil || model.phase == .starting || !model.cameraReady)
                    Text("Use a mount and a power pack. Video uses about 1 GB of data an hour. Keep this screen open while you’re live.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(18)
            }
            .frame(maxWidth: 560, maxHeight: 520)
            .fixedSize(horizontal: false, vertical: true)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .padding(.horizontal, 12).padding(.bottom, 12)
        }
    }

    // while live: LIVE, hole, signal, rate, battery, Send to phones, Stop
    private var liveOverlay: some View {
        VStack {
            HStack(spacing: 8) {
                pill("LIVE \(model.elapsed)", systemImage: "circle.fill", bg: Self.red, fg: .white)
                if let h = model.hole { pill("Hole \(h)", systemImage: nil, bg: .black.opacity(0.55), fg: .white) }
                Spacer()
                if model.upright { pill("Turn sideways", systemImage: "rotate.right", bg: Self.gold, fg: .black) }
            }
            .padding()
            if let m = model.message {
                Text(m).font(.footnote).foregroundStyle(.white).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.07, green: 0.21, blue: 0.16).opacity(0.92), in: RoundedRectangle(cornerRadius: 11)).padding(.horizontal)
            }
            if model.hot {
                Text("The phone is getting hot. Shade it, or the camera may stop.").font(.footnote.weight(.semibold)).foregroundStyle(.black)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Self.gold, in: RoundedRectangle(cornerRadius: 11)).padding(.horizontal)
            }
            Spacer()
            HStack(spacing: 6) {
                stat(model.signal == .good ? "Good" : model.signal == .weak ? "Weak" : "Lost", "Signal",
                     color: model.signal == .good ? .green : model.signal == .weak ? Self.gold : Self.red)
                stat(model.kbps >= 1000 ? String(format: "%.1f Mb/s", Double(model.kbps) / 1000) : "\(model.kbps) kb/s", "Sending", color: .white)
                stat(model.battery < 0 ? "—" : "\(model.charging ? "⚡ " : "")\(Int(model.battery * 100))%", model.charging ? "Charging" : "Battery",
                     color: !model.charging && model.battery >= 0 && model.battery < 0.25 ? Self.red : .white)
            }
            .padding(.horizontal)
            HStack(spacing: 8) {
                Button { Task { await model.sendToPhones() } } label: {
                    Label("Send to phones", systemImage: "megaphone.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                        .background(Self.gold, in: RoundedRectangle(cornerRadius: 13)).foregroundStyle(.black)
                }
                Button { confirmStop = true } label: {
                    Label("Stop", systemImage: "stop.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 13)).foregroundStyle(Self.red)
                }
                .disabled(model.phase == .stopping)
            }
            .padding()
        }
    }

    private var denied: some View {
        VStack(spacing: 14) {
            Image(systemName: "video.slash.fill").font(.largeTitle)
            Text("Flagcast needs the camera to go live.").font(.headline)
            Text("Turn on Camera for this app in Settings.").font(.subheadline).foregroundStyle(.white.opacity(0.7))
            Button("Open Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) } }.buttonStyle(.borderedProminent)
            Button("Close") { dismiss() }.foregroundStyle(.white)
        }
        .foregroundStyle(.white).padding()
    }

    private func row(_ title: String, _ value: String, warn: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).fontWeight(.semibold)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing).foregroundStyle(warn ? Color.orange : Color.secondary)
        }
        .padding(.vertical, 9)
    }

    private func pill(_ text: String, systemImage: String?, bg: Color, fg: Color) -> some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.caption2) }
            Text(text).font(.caption.monospaced().weight(.bold))
        }
        .padding(.horizontal, 9).padding(.vertical, 5).background(bg, in: RoundedRectangle(cornerRadius: 6)).foregroundStyle(fg)
    }

    private func stat(_ value: String, _ label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 7).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

extension GoLiveHole {
    /// the holes of a course, for the picker
    static func from(_ holes: [Hole]) -> [GoLiveHole] { holes.map { GoLiveHole(n: $0.n, par: $0.par, yds: $0.yds) } }
}
