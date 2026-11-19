import Foundation
import Observation

/// One tournament's live state: a first copy over HTTP, then every change over the WebSocket
/// (wss://flagcast.app/golf/api/<id>/ws sends { t: "state", s } on connect and after each change).
/// It pings every 25 s, reconnects with backoff, and reconnects at once when the app comes back to the
/// foreground. The last state is kept on the phone so a scorecard opens with no signal.
@MainActor @Observable
final class EventFeed {
    let id: String
    private(set) var state: EventState?
    private(set) var online = false
    /// The server said the tournament is gone (404), as opposed to no signal.
    private(set) var missing: String?

    @ObservationIgnored private var task: URLSessionWebSocketTask?
    @ObservationIgnored private var listen: Task<Void, Never>?
    @ObservationIgnored private var ping: Task<Void, Never>?
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var tries = 0
    @ObservationIgnored private var users = 0
    /// Called with each new state (the scorecard uses it to send waiting scores and to show nudges).
    @ObservationIgnored var onState: [String: (EventState) -> Void] = [:]
    @ObservationIgnored var onLink: [String: (Bool) -> Void] = [:]

    init(id: String) {
        self.id = id
        state = Cache.load(id)
    }

    /// Views call start() when they appear and stop() when they go; the link stays open while anyone needs it.
    func start() {
        users += 1
        guard users == 1 else { return }
        Task { await refresh() }
        open()
    }
    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        close()
        retry?.cancel()
    }

    /// The app came back to the foreground: if the link dropped while it was away, open it now.
    func wake() {
        guard users > 0, !online else { return }
        tries = 0
        retry?.cancel()
        open()
        Task { await refresh() }
    }

    func refresh() async {
        do { apply(try await API.state(id)); missing = nil }
        catch let e as APIError where e.status == 404 { missing = e.message }
        catch {}
    }

    private func apply(_ s: EventState) {
        state = s
        Cache.save(id, s)
        for f in onState.values { f(s) }
    }

    private func setOnline(_ on: Bool) {
        guard on != online else { return }
        online = on
        for f in onLink.values { f(on) }
    }

    private func open() {
        close()
        let t = API.session.webSocketTask(with: Server.webSocket(id))
        task = t
        t.resume()
        listen = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let m = try await t.receive()
                    self?.handle(m)
                } catch {
                    self?.dropped(t)
                    return
                }
            }
        }
        ping = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                if Task.isCancelled { return }
                guard let self, self.task === t else { return }
                t.send(.string("ping")) { _ in }
            }
        }
    }

    private func close() {
        listen?.cancel(); ping?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        setOnline(false)
    }

    private func handle(_ m: URLSessionWebSocketTask.Message) {
        let data: Data
        switch m {
        case .string(let s): if s == "pong" { return }; data = Data(s.utf8)
        case .data(let d): data = d
        @unknown default: return
        }
        tries = 0
        setOnline(true)
        struct Envelope: Decodable { let t: String; let s: EventState? }
        if let env = try? JSONDecoder().decode(Envelope.self, from: data), env.t == "state", let s = env.s { apply(s); missing = nil }
    }

    private func dropped(_ t: URLSessionWebSocketTask) {
        guard task === t else { return }
        task = nil
        ping?.cancel()
        setOnline(false)
        guard users > 0 else { return }
        let wait = min(15.0, pow(2.0, Double(tries)))
        tries += 1
        retry?.cancel()
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            if Task.isCancelled { return }
            self?.open()
        }
    }
}

/// Every open tournament feed, so the scorecard, leaderboard and pro screens for one tournament share one link.
@MainActor
enum Feeds {
    private static var all: [String: EventFeed] = [:]
    static func feed(_ id: String) -> EventFeed {
        if let f = all[id] { return f }
        let f = EventFeed(id: id)
        all[id] = f
        return f
    }
    static func wakeAll() { for f in all.values { f.wake() } }
}

/// The last state of each tournament, on disk, for opening with no signal.
enum Cache {
    static func url(_ id: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("state-\(id).json")
    }
    static func load(_ id: String) -> EventState? {
        guard let d = try? Data(contentsOf: url(id)) else { return nil }
        return try? JSONDecoder().decode(EventState.self, from: d)
    }
    static func save(_ id: String, _ s: EventState) {
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: url(id), options: .atomic) }
    }
}
