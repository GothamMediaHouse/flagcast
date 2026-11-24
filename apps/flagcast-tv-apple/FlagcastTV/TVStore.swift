import Foundation
import Observation

/// What the TV is doing: showing a code until the club adds it in the Manager, then asking Flagcast what to show
/// (the tournament of the day, as pages, or the club's idle screen). The token stays in UserDefaults, so it's added once.
@MainActor @Observable
final class TVStore {
    enum Screen { case starting, pairing, idle, live }
    var screen: Screen = .starting
    var hello: Hello?
    var now: Now?
    var problem: String?
    var offline = false

    private let tokenKey = "flagcast.tv.token"
    private var token: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }
    private var loop: Task<Void, Never>?

    func start() {
        loop?.cancel()
        loop = Task { await run() }
    }

    private static var today: String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func run() async {
        while !Task.isCancelled {
            if let t = token { await check(t) } else { await pair() }
        }
    }

    // ---- not connected ----
    private func pair() async {
        if screen != .pairing { screen = .pairing }
        if hello == nil || Date().timeIntervalSince1970 * 1000 > (hello?.exp ?? 0) - 15000 {
            do { hello = try await Server.post("hello", ["kind": "appletv"]); problem = nil }
            catch { problem = (error as? ServerError)?.errorDescription ?? "Can’t reach Flagcast. Check the Apple TV’s internet."; await sleep(15); return }
        }
        guard let h = hello else { return }
        do {
            let w: Wait = try await Server.post("wait", ["code": h.code, "pair": h.pair])
            if let t = w.token { token = t; hello = nil; screen = .starting; return }
        } catch let e as ServerError where e.status == 410 { hello = nil; return }
        catch { problem = "Can’t reach Flagcast. Check the Apple TV’s internet." }
        await sleep(3)
    }

    // ---- connected ----
    private func check(_ t: String) async {
        do {
            let n: Now = try await Server.post("now", ["token": t, "today": Self.today, "feed": 1])
            now = n; offline = false; problem = nil
            screen = n.event != nil && n.feed != nil ? .live : .idle
            await sleep(n.event != nil ? 10 : max(30, n.check ?? 60))  // fresh scores every 10 seconds on the day
        } catch let e as ServerError where e.status == 401 {
            token = nil; now = nil; screen = .pairing   // removed in the Manager: show a new code
        } catch {
            offline = true; await sleep(15)
        }
    }

    private func sleep(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
}
