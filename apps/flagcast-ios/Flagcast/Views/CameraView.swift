import SwiftUI
import AVKit
import Observation

/// A par 3 camera link. HLS (.m3u8) plays in the app; anything else (a YouTube or camera-maker page) opens in Safari view.
struct CameraLink: Identifiable, Hashable {
    var hole: Int
    var url: URL
    var id: String { "\(hole):\(url.absoluteString)" }
    var isHLS: Bool { url.path.lowercased().hasSuffix(".m3u8") }
}

/// Plays one hole's camera: live, 30 s back, or a replay (matches public/golf/replay.js).
/// A replay is a clip link played from the start, or a mark on the live HLS camera played back from
/// `back` seconds before the mark, found with the stream's EXT-X-PROGRAM-DATE-TIME clock, for back + 6 s.
@MainActor @Observable
final class CameraController {
    let camURL: URL?
    let player = AVPlayer()
    private(set) var replay: Replay?
    private(set) var message: String?
    private(set) var loading = false
    @ObservationIgnored private var stop: Task<Void, Never>?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    init(camURL: URL?) {
        self.camURL = camURL
        player.isMuted = true
    }

    /// Whether the camera keeps enough of the stream to go back (checked each second: AVPlayer isn't observable).
    private(set) var canRewind = false
    @ObservationIgnored private var poll: Task<Void, Never>?

    func start() {
        goLive()
        poll?.cancel()
        poll = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let r = self.player.currentItem?.seekableTimeRanges.last?.timeRangeValue
                let ok = self.replay == nil && (r?.duration.seconds ?? 0) > 10
                if ok != self.canRewind { self.canRewind = ok }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    func pause() { player.pause(); stop?.cancel(); poll?.cancel() }

    func goLive() {
        stop?.cancel(); clearEnd()
        replay = nil; message = nil
        guard let camURL else { return }
        if (player.currentItem?.asset as? AVURLAsset)?.url != camURL {
            player.replaceCurrentItem(with: AVPlayerItem(url: camURL))
        }
        if let r = player.currentItem?.seekableTimeRanges.last?.timeRangeValue, r.duration.seconds > 10 {
            player.seek(to: CMTimeSubtract(r.end, CMTime(seconds: 3, preferredTimescale: 600)))
        }
        player.play()
    }

    func rewind(_ secs: Double = 30) {
        guard let item = player.currentItem, let r = item.seekableTimeRanges.first?.timeRangeValue else { return }
        let t = max(r.start.seconds + 1, item.currentTime().seconds - secs)
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600))
        player.play()
    }

    func play(_ r: Replay) async {
        stop?.cancel(); clearEnd()
        message = nil
        replay = r
        loading = true; defer { loading = false }
        if r.isClip, let u = URL(string: r.url) {
            let item = AVPlayerItem(url: u)
            player.replaceCurrentItem(with: item)
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.goLive() }
            }
            player.play()
            return
        }
        guard let camURL, camURL.path.lowercased().hasSuffix(".m3u8") else { fail("This camera can’t be replayed."); return }
        let item = AVPlayerItem(url: camURL)
        player.replaceCurrentItem(with: item)
        guard await ready(item) else { fail("The replay didn’t load. Try again."); return }
        let from = Date(timeIntervalSince1970: (r.at - r.back * 1000) / 1000)
        guard let range = item.seekableTimeRanges.first?.timeRangeValue else { fail("This replay is older than the camera keeps."); return }
        if let now = item.currentDate() {
            // the stream has a clock: check the moment is still in its window, then seek to it
            let startDate = now.addingTimeInterval(range.start.seconds - item.currentTime().seconds)
            guard from >= startDate.addingTimeInterval(-0.5) else { fail("This replay is older than the camera keeps."); return }
            let ok = await item.seek(to: from)
            guard ok else { fail("This replay is older than the camera keeps."); return }
        } else {
            // no clock in the stream: count back from the live edge
            let edge = range.end.seconds
            let t = edge - Date().timeIntervalSince(from)
            guard t >= range.start.seconds - 0.5 else { fail("This replay is older than the camera keeps."); return }
            await player.seek(to: CMTime(seconds: t, preferredTimescale: 600))
        }
        player.play()
        let len = r.back + 6
        stop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(len))
            if !Task.isCancelled { self?.goLive() }
        }
    }

    private func ready(_ item: AVPlayerItem) async -> Bool {
        for _ in 0..<60 {   // up to 12 s
            if item.status == .readyToPlay && !item.seekableTimeRanges.isEmpty { return true }
            if item.status == .failed { return false }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    private func fail(_ m: String) {
        message = m
        replay = nil
        if camURL != nil { goLiveKeepingMessage() }
    }
    private func goLiveKeepingMessage() { let m = message; goLive(); message = m }
    private func clearEnd() { if let e = endObserver { NotificationCenter.default.removeObserver(e); endObserver = nil } }
}

/// The camera picture, with LIVE / REPLAY tag, ⟲ 30s and Live buttons, and the hole's replays underneath.
struct CameraBox: View {
    var hole: Int
    var camURL: URL?
    var replays: [Replay]
    /// the hole's name over the bottom of the picture ("HOLE 7", "165 yds · Par 3"), as on the Par 3s tab
    var title: String? = nil
    var sub: String? = nil
    @State private var cam: CameraController
    @State private var fullscreen = false

    init(hole: Int, camURL: URL?, replays: [Replay], title: String? = nil, sub: String? = nil) {
        self.hole = hole; self.camURL = camURL; self.replays = replays; self.title = title; self.sub = sub
        _cam = State(initialValue: CameraController(camURL: camURL))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                Color(UIColor(hex: 0x0a120e))
                if camURL != nil || cam.replay != nil { VideoPlayer(player: cam.player) }
                else { Text("No camera on this hole").font(.subheadline).foregroundStyle(Color(UIColor(hex: 0xa9bdb0))).frame(maxWidth: .infinity, maxHeight: .infinity) }
                Text(cam.replay != nil ? "REPLAY" : "LIVE").font(.caption2.monospaced().weight(.semibold)).tracking(1)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(cam.replay != nil ? Color(UIColor(hex: 0xe8c547)) : Color(UIColor(hex: 0xc8312b)))
                    .foregroundStyle(cam.replay != nil ? Color.fcOnFlag : .white)
                    .padding(8).allowsHitTesting(false)
                if cam.loading { ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity) }
                if let title {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer()
                        Text(title).font(.system(size: 30, weight: .heavy)).fontWidth(.condensed).textCase(.uppercase)
                        if let sub { Text(sub).font(.footnote.weight(.semibold)).opacity(0.85) }
                    }
                    .foregroundStyle(.white).shadow(color: .black.opacity(0.5), radius: 6, y: 1)
                    .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom))
                    .allowsHitTesting(false)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                if camURL != nil || cam.replay != nil {
                    Button { fullscreen = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.subheadline.weight(.bold))
                            .frame(width: 36, height: 36).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(.white)
                    }
                    .padding(8)
                    .accessibilityLabel("Full screen")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if camURL != nil || !replays.isEmpty {
                HStack(spacing: 8) {
                    if cam.replay != nil {
                        Button { cam.goLive() } label: { Label("Back to live", systemImage: "dot.radiowaves.left.and.right") }
                            .buttonStyle(.fc(.primary, full: false))
                    } else if camURL != nil {
                        Button { cam.rewind(30) } label: { Label("30s", systemImage: "gobackward.30") }
                            .buttonStyle(.fc(.plain, full: false)).disabled(!cam.canRewind)
                        Button { cam.goLive() } label: { Label("Live", systemImage: "dot.radiowaves.left.and.right") }
                            .buttonStyle(.fc(.plain, full: false))
                    }
                }
                .font(.subheadline)
            }
            if let m = cam.message { Text(m).font(.footnote).foregroundStyle(Color.fcRed) }
            if !replays.isEmpty {
                Text("Replays").fcLabel()
                FlowLayout(spacing: 6) {
                    ForEach(replays) { r in
                        Chip(title: "\(r.label.isEmpty ? "Replay" : r.label) · \(Fmt.time(r.at))", on: cam.replay?.id == r.id) {
                            Task { await cam.play(r) }
                        }
                    }
                }
            }
        }
        .onAppear { cam.start() }
        .onDisappear { if !fullscreen { cam.pause() } }
        .fullScreenCover(isPresented: $fullscreen) { FullscreenCamera(cam: cam, hole: hole, replays: replays) }
    }
}

/// One camera filling the screen (turn the phone sideways for the biggest picture). Tap to show or hide the
/// controls: live, 30 s back, and the hole's replays.
struct FullscreenCamera: View {
    var cam: CameraController
    var hole: Int
    var replays: [Replay]
    @Environment(\.dismiss) private var dismiss
    @State private var controls = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: cam.player).ignoresSafeArea().allowsHitTesting(false)
            Color.clear.contentShape(Rectangle()).onTapGesture { withAnimation { controls.toggle() }; autoHide() }
            if controls {
                VStack {
                    HStack(spacing: 10) {
                        Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44).background(.black.opacity(0.55), in: Circle()) }
                            .accessibilityLabel("Close")
                        Text("Hole \(hole)").font(.system(.title3, weight: .heavy)).fontWidth(.condensed).textCase(.uppercase)
                        Text(cam.replay != nil ? "REPLAY" : "LIVE").font(.caption2.monospaced().weight(.semibold)).tracking(1)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(cam.replay != nil ? Color(UIColor(hex: 0xe8c547)) : Color(UIColor(hex: 0xc8312b)))
                            .foregroundStyle(cam.replay != nil ? Color.fcOnFlag : .white)
                        Spacer()
                    }
                    Spacer()
                    if let m = cam.message { Text(m).font(.footnote).padding(8).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8)) }
                    HStack(spacing: 8) {
                        if cam.replay != nil {
                            Button { cam.goLive() } label: { Label("Back to live", systemImage: "dot.radiowaves.left.and.right") }.buttonStyle(.fc(.primary, full: false))
                        } else if cam.camURL != nil {
                            Button { cam.rewind(30) } label: { Label("30s", systemImage: "gobackward.30") }.buttonStyle(.fc(.dark, full: false)).disabled(!cam.canRewind)
                            Button { cam.goLive() } label: { Label("Live", systemImage: "dot.radiowaves.left.and.right") }.buttonStyle(.fc(.dark, full: false))
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(replays) { r in
                                    Chip(title: "\(r.label.isEmpty ? "Replay" : r.label) · \(Fmt.time(r.at))", on: cam.replay?.id == r.id) { Task { await cam.play(r) }; autoHide() }
                                }
                            }
                        }
                    }
                    .font(.subheadline)
                }
                .padding(16)
                .foregroundStyle(.white)
                .transition(.opacity)
            }
        }
        .statusBarHidden(!controls)
        .persistentSystemOverlays(.hidden)
        .onAppear { cam.player.play(); autoHide() }
        .preferredColorScheme(.dark)
    }

    private func autoHide() {
        hideTask?.cancel()
        hideTask = Task { try? await Task.sleep(for: .seconds(4)); if !Task.isCancelled { withAnimation { controls = false } } }
    }
}

/// Every par 3 camera at once, in a grid (two across; turn the phone sideways for a 2×2 quad). Tap one for it alone.
struct AllPar3s: View {
    var state: EventState
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Int?

    var holes: [Hole] { state.course.holes.filter { $0.par == 3 && (state.cams[$0.n].map { $0.lowercased().contains(".m3u8") } ?? false) } }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: holes.count == 1 ? 1 : 2)
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()
                LazyVGrid(columns: cols, spacing: 4) {
                    ForEach(holes, id: \.n) { h in
                        QuadTile(hole: h, url: URL(string: state.cams[h.n] ?? ""), height: wide ? (geo.size.height - 4) / 2 : nil)
                            .onTapGesture { picked = h.n }
                    }
                }
                .frame(maxHeight: .infinity, alignment: wide ? .center : .center)
                Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).foregroundStyle(.white).frame(width: 44, height: 44).background(.black.opacity(0.55), in: Circle()) }
                    .padding(12).accessibilityLabel("Close")
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .fullScreenCover(item: Binding(get: { picked.map { PickedHole(n: $0) } }, set: { picked = $0?.n })) { p in
            SingleCamera(hole: p.n, url: URL(string: state.cams[p.n] ?? ""), replays: state.replays.filter { $0.hole == p.n })
        }
    }
    struct PickedHole: Identifiable { var n: Int; var id: Int { n } }
}

/// A par 3 tile in the quad: live, muted, with the hole number.
private struct QuadTile: View {
    var hole: Hole
    var url: URL?
    var height: CGFloat?
    @State private var cam: CameraController
    init(hole: Hole, url: URL?, height: CGFloat?) {
        self.hole = hole; self.url = url; self.height = height
        _cam = State(initialValue: CameraController(camURL: url))
    }
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(UIColor(hex: 0x0a120e))
            VideoPlayer(player: cam.player).allowsHitTesting(false)
            HStack(spacing: 6) {
                Text("LIVE").font(.caption2.monospaced().weight(.semibold)).padding(.horizontal, 5).padding(.vertical, 1).background(Color(UIColor(hex: 0xc8312b)))
                Text("Hole \(hole.n)").font(.subheadline.weight(.heavy)).fontWidth(.condensed).textCase(.uppercase)
                if hole.yds > 0 { Text("\(hole.yds) yds").font(.caption.monospaced()).foregroundStyle(.white.opacity(0.75)) }
            }
            .foregroundStyle(.white).padding(8).background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxHeight: height)
        .contentShape(Rectangle())
        .onAppear { cam.start() }
        .onDisappear { cam.pause() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows this camera full screen")
    }
}

/// One camera full screen with its own player (opened from the quad).
private struct SingleCamera: View {
    var hole: Int
    var url: URL?
    var replays: [Replay]
    @State private var cam: CameraController
    init(hole: Int, url: URL?, replays: [Replay]) {
        self.hole = hole; self.url = url; self.replays = replays
        _cam = State(initialValue: CameraController(camURL: url))
    }
    var body: some View {
        FullscreenCamera(cam: cam, hole: hole, replays: replays)
            .onAppear { cam.start() }
            .onDisappear { cam.pause() }
    }
}

/// The camera on its own screen, from the scorecard's "Watch the camera" button.
struct CameraSheet: View {
    var link: CameraLink
    var replays: [Replay] = []
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        if link.isHLS || !replays.isEmpty {
            NavigationStack {
                ScrollView {
                    CameraBox(hole: link.hole, camURL: link.isHLS ? link.url : nil, replays: replays).padding(16)
                }
                .background(Color.fcPaper)
                .navigationTitle("Hole \(link.hole) camera").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
        } else {
            SafariView(url: link.url).ignoresSafeArea()
        }
    }
}

/// A replay full screen, straight away (the scorecard's "New replay" banner), with "Back to live" when the hole has a camera.
struct ReplayFullscreen: View {
    var replay: Replay
    var camURL: URL?
    var replays: [Replay]
    @State private var cam: CameraController
    init(replay: Replay, camURL: URL?, replays: [Replay]) {
        self.replay = replay; self.camURL = camURL; self.replays = replays
        _cam = State(initialValue: CameraController(camURL: camURL))
    }
    var body: some View {
        FullscreenCamera(cam: cam, hole: replay.hole, replays: replays)
            .task { await cam.play(replay) }
            .onDisappear { cam.pause() }
    }
}

/// "New replay" on the scorecard: each replay once, only ones made since this phone first opened the tournament.
enum ReplayCast {
    private static func key(_ id: String) -> String { "flagcast:replay:\(id)" }
    /// the newest replay this phone hasn't been shown (a replay from the last 15 minutes)
    static func current(_ s: EventState, id: String) -> Replay? {
        let d = UserDefaults.standard
        guard let newest = s.replays.max(by: { $0.at < $1.at }) else { return nil }
        if d.object(forKey: key(id)) == nil { d.set(newest.at, forKey: key(id)); return nil }   // first look: older ones aren't news
        guard newest.at > d.double(forKey: key(id)), Date().timeIntervalSince1970 * 1000 - newest.at < 15 * 60_000 else { return nil }
        return newest
    }
    static func seen(_ r: Replay, id: String) { UserDefaults.standard.set(r.at, forKey: key(id)) }
}

struct ReplayBanner: View {
    var replay: Replay
    var watch: () -> Void
    var close: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Text("NEW REPLAY").font(.caption2.monospaced().weight(.bold)).tracking(1.2)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color(UIColor(hex: 0xe8c547)), in: RoundedRectangle(cornerRadius: 3)).foregroundStyle(Color.fcOnFlag)
            VStack(alignment: .leading, spacing: 2) {
                Text("Hole \(replay.hole)").font(.subheadline.weight(.bold)).foregroundStyle(Color.fcOnGreen)
                if !replay.label.isEmpty { Text(replay.label).font(.caption).foregroundStyle(Color.fcOnGreenMuted).lineLimit(1) }
            }
            Spacer(minLength: 4)
            Image(systemName: "play.fill").font(.headline).foregroundStyle(Color.fcOnFlag)
                .frame(width: 44, height: 40).background(Color(UIColor(hex: 0xe8c547)), in: RoundedRectangle(cornerRadius: 8))
            Button { close() } label: { Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(Color.fcOnGreenMuted).frame(width: 32, height: 40) }
                .accessibilityLabel("Close")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color(UIColor(hex: 0x123628)), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18)))
        .shadow(color: .black.opacity(0.35), radius: 15, y: 8)
        .contentShape(Rectangle())
        .onTapGesture { watch() }
        .padding(.horizontal, 12).frame(maxWidth: 560)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
        .accessibilityLabel("New replay, hole \(replay.hole). \(replay.label)").accessibilityHint("Plays it full screen")
    }
}
