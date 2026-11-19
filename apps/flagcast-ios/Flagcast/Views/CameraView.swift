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
    @State private var cam: CameraController

    init(hole: Int, camURL: URL?, replays: [Replay]) {
        self.hole = hole; self.camURL = camURL; self.replays = replays
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
            }
            .aspectRatio(16 / 9, contentMode: .fit)
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
