#if DEBUG
import SwiftUI

/// Test builds only: FLAGCAST_SNAPSHOTS=<folder> opens the first tournament, steps through every section and saves
/// a picture of the window for each (for checking the layout without anyone at the Mac).
@MainActor
enum Snapshots {
    /// FLAGCAST_FLYTEST=<tournament id> (and FLAGCAST_FLYHOLE=<n>): open its Course map off-screen, fly the hole, and
    /// log the camera (FLAGCAST_FLYLOG) to check the flight moves down the hole.
    static func flyTest(_ model: AppModel) {
        let env = ProcessInfo.processInfo.environment
        guard let id = env["FLAGCAST_FLYTEST"] else { return }
        log("flytest: start")
        Task {
            try? await Task.sleep(for: .seconds(3))
            // on the screen but see-through and click-through (off the screen, macOS stops drawing the map)
            if let w = NSApp.windows.first(where: { $0.isVisible }) { w.alphaValue = 0; w.ignoresMouseEvents = true; w.level = .init(rawValue: -1000); w.setFrame(NSRect(x: 0, y: 0, width: 1300, height: 860), display: true) }
            log("flytest: events", model.events.map(\.id), "windows", NSApp.windows.count)
            model.selection = id; model.section = .map
            for _ in 0..<30 { if model.doc(id)?.loaded == true { break }; try? await Task.sleep(for: .seconds(1)) }
            log("flytest: loaded", model.doc(id)?.loaded ?? false, model.doc(id)?.error ?? "", "section", model.section.rawValue, "holes", model.doc(id)?.ev.map.holes.count ?? -1)
            try? await Task.sleep(for: .seconds(5))
            log("flytest: flying")
            NotificationCenter.default.post(name: .init("FlagcastFlyTest"), object: Int(env["FLAGCAST_FLYHOLE"] ?? "") ?? 2)
            try? await Task.sleep(for: .seconds(20))
            NSApp.terminate(nil)
        }
    }
    static func run(_ model: AppModel) {
        guard let dir = ProcessInfo.processInfo.environment["FLAGCAST_SNAPSHOTS"] else { return }
        log("snapshots: start, windows:", NSApp.windows.count)
        if ProcessInfo.processInfo.environment["FLAGCAST_SNAPSHOT_LIGHT"] == "1" { NSApp.appearance = NSAppearance(named: .aqua) }
        let env = ProcessInfo.processInfo.environment
        // FLAGCAST_SNAPSHOT_OFFSCREEN=1: the window sits off the screen (nobody at the Mac sees it) and pictures are
        // drawn from its layers; FLAGCAST_SNAPSHOT_EVENT picks the tournament; FLAGCAST_SNAPSHOT_WIDTHS="1000,1500"
        // shoots every section at each window width
        let offscreen = env["FLAGCAST_SNAPSHOT_OFFSCREEN"] == "1"
        let widths = (env["FLAGCAST_SNAPSHOT_WIDTHS"] ?? "").split(separator: ",").compactMap { Double($0) }
        Task {
            try? await Task.sleep(for: .seconds(3))
            if offscreen, let w = NSApp.windows.first(where: { $0.isVisible }) { w.setFrame(NSRect(x: -30000, y: -30000, width: widths.first ?? 1300, height: 860), display: true) }
            shot(dir, "home")
            guard let first = model.events.first(where: { $0.id == env["FLAGCAST_SNAPSHOT_EVENT"] }) ?? model.events.first else { NSApp.terminate(nil); return }
            model.selection = first.id
            for width in (widths.isEmpty ? [0] : widths) {
                if width > 0, let w = NSApp.windows.first(where: { $0.isVisible }) { var f = w.frame; f.size.width = width; w.setFrame(f, display: true) }
                for s in Section.allCases {
                    model.section = s
                    try? await Task.sleep(for: .seconds(s == .setup ? 4 : 2.5))
                    shot(dir, width > 0 ? "\(s.rawValue)-\(Int(width))" : s.rawValue)
                }
            }
            if env["FLAGCAST_SNAPSHOT_ADMIN"] == "0" { NSApp.terminate(nil); return }
            // Admin (the test copy shows it; the local site lets any sign-in in)
            model.forceAdmin = true
            model.adminMode = true
            for a in AdminSection.allCases { model.adminSection = a; try? await Task.sleep(for: .seconds(a == .clubs ? 5 : 3)); shot(dir, "admin-\(a.rawValue)") }
            model.adminMode = false
            // dark mode
            NSApp.appearance = NSAppearance(named: .darkAqua)
            for s in [Section.overview, .setup, .teams, .scores] { model.section = s; try? await Task.sleep(for: .seconds(2.5)); shot(dir, "\(s.rawValue)-dark") }
            model.selection = nil; try? await Task.sleep(for: .seconds(2.5)); shot(dir, "home-dark")
            model.adminMode = true; model.adminSection = .clubs; try? await Task.sleep(for: .seconds(3)); shot(dir, "admin-clubs-dark")
            NSApp.terminate(nil)
        }
    }
    static func log(_ items: Any...) { FileHandle.standardError.write((items.map { "\($0)" }.joined(separator: " ") + "\n").data(using: .utf8)!) }
    static func shot(_ dir: String, _ name: String) {
        guard let w = NSApp.windows.first(where: { $0.isVisible }), let frame = w.contentView?.superview ?? w.contentView else { log("snapshots: no window"); return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        // 1) the system screenshot of the window (needs Screen Recording); 2) the window's layers drawn by hand
        // (always, when the window is off the screen)
        if ProcessInfo.processInfo.environment["FLAGCAST_SNAPSHOT_OFFSCREEN"] != "1" {
            let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-x", "-o", "-l", "\(w.windowNumber)", url.path]
            try? task.run(); task.waitUntilExit()
            if FileManager.default.fileExists(atPath: url.path) { log("snapshots: saved", name); return }
        }
        frame.layoutSubtreeIfNeeded(); frame.displayIfNeeded()
        guard let layer = frame.layer else { log("snapshots: no layer"); return }
        let scale = w.backingScaleFactor, size = frame.bounds.size
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return }
        ctx.scaleBy(x: scale, y: scale)
        if !frame.isFlipped { } else { ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1) }
        layer.render(in: ctx)
        guard let img = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: img)
        do { try rep.representation(using: .png, properties: [:])?.write(to: url); log("snapshots: drew", name) } catch { log("snapshots:", error) }
    }
}
#endif

#if DEBUG
import Foundation
/// Test builds only: FLAGCAST_SELFTEST=1 loads the first tournament, saves it unchanged, and checks that the
/// server's copy of every setup field is the same before and after (nothing lost or changed by the Mac app's model).
@MainActor
/// Test builds: FLAGCAST_NDI_TEST=1 finds an NDI source, bridges it to hole 3 of a pretend tournament for 12 seconds,
/// checks the local HLS files and the TV server (/local-cams index and a page passed through), then quits.
enum NDISelfTest {
    static func run() {
        guard ProcessInfo.processInfo.environment["FLAGCAST_NDI_TEST"] == "1" else { return }
        Task {
            func log(_ s: String) { FileHandle.standardError.write(Data("ndi-test: \(s)\n".utf8)) }
            log("library loaded: \(NDILib.shared.loaded), ffmpeg: \(Bridges.ffmpeg ?? "none")")
            NDISources.shared.watch()
            for _ in 0..<20 where NDISources.shared.names.isEmpty { try? await Task.sleep(for: .seconds(1)) }
            log("sources: \(NDISources.shared.names)")
            let want = ProcessInfo.processInfo.environment["FLAGCAST_NDI_SOURCE"] ?? ""
            for _ in 0..<10 where !want.isEmpty && !NDISources.shared.names.contains(where: { $0.contains(want) }) { try? await Task.sleep(for: .seconds(1)) }
            guard let src = NDISources.shared.names.first(where: { want.isEmpty || $0.contains(want) }) ?? NDISources.shared.names.first else { log("FAIL no NDI source"); NSApp.terminate(nil); return }
            let env = ProcessInfo.processInfo.environment
            let ev = env["FLAGCAST_NDI_EVENT"] ?? "selftest", hole = Int(env["FLAGCAST_NDI_HOLE"] ?? "") ?? 3
            log("using: \(src)")
            Bridges.shared.start(event: ev, hole: hole, source: src, rtmps: env["FLAGCAST_NDI_RTMPS"])
            try? await Task.sleep(for: .seconds(Double(env["FLAGCAST_NDI_SECS"] ?? "") ?? 12))
            if let b = Bridges.shared.bridge(ev, hole) { log("upload: \(b.uploading.map { $0 ? "sending" : "not sending" } ?? "off")") }
            let b = Bridges.shared.bridge(ev, hole)
            log("bridge: receiving=\(b?.receiving ?? false) size=\(b?.size ?? "") state=\(b?.state ?? "")")
            let files = (try? FileManager.default.contentsOfDirectory(atPath: b?.dir.path ?? "")) ?? []
            log("hls files: \(files.sorted().prefix(6))")
            func get(_ path: String) async -> (Int, String) {
                guard let (d, r) = try? await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(LOCAL_PORT)\(path)")!) else { return (0, "") }
                return ((r as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: d.prefix(120), as: UTF8.self))
            }
            log("index.json: \(await get("/local-cams/\(ev)/index.json"))")
            let pl = await get("/local-cams/\(ev)/\(hole)/index.m3u8"); log("playlist: \(pl.0) \(pl.1.replacingOccurrences(of: "\n", with: " | "))")
            let page = await get("/golf/"); log("proxied /golf/: \(page.0) \(page.1.prefix(40))")
            let api = await get("/golf/api/courses?q=ironhorse"); log("proxied api: \(api.0) \(api.1.prefix(60))")
            Bridges.shared.stopAll()
            log("done"); NSApp.terminate(nil)
        }
    }
}

@MainActor
enum SelfTest {
    static func run(_ model: AppModel) {
        guard ProcessInfo.processInfo.environment["FLAGCAST_SELFTEST"] == "1", let e = model.events.first else { return }
        Task {
            func raw() async throws -> [String: Any] { Net.json(try await Net.post("/golf/api/\(e.id)/desk", ["key": e.key, "op": "get"])) }
            do {
                let before = try await raw()
                let ev = try await Net.deskGet(e.id, e.key)
                _ = try await Net.deskSave(e.id, e.key, ev)
                let after = try await raw()
                let keys = ["name", "club", "date", "course", "format", "sideGames", "flights", "teams", "screens", "cams", "sponsors", "schedule", "pins", "displays", "fund", "contests", "map", "locked"]
                var diffs: [String] = []
                for k in keys { diff(before[k], after[k], k, &diffs) }
                Snapshots.log("selftest:", diffs.isEmpty ? "OK, every setup field the same after a save" : "DIFFERENT:\n" + diffs.prefix(30).joined(separator: "\n"))
            } catch { Snapshots.log("selftest: error", error) }
            NSApp.terminate(nil)
        }
    }
    static func diff(_ a: Any?, _ b: Any?, _ path: String, _ out: inout [String]) {
        switch (a, b) {
        case let (x as [String: Any], y as [String: Any]):
            for k in Set(x.keys).union(y.keys) { diff(x[k], y[k], "\(path).\(k)", &out) }
        case let (x as [Any], y as [Any]):
            if x.count != y.count { out.append("\(path): \(x.count) items vs \(y.count)"); return }
            for i in x.indices { diff(x[i], y[i], "\(path)[\(i)]", &out) }
        default:
            let s1 = a.map { "\($0)" } ?? "nil", s2 = b.map { "\($0)" } ?? "nil"
            if s1 != s2 && !(path.hasSuffix(".at") && path.hasPrefix("map")) { out.append("\(path): \(s1) → \(s2)") }
        }
    }
}
#endif
