#if DEBUG
import SwiftUI

/// Test builds only: FLAGCAST_SNAPSHOTS=<folder> opens the first tournament, steps through every section and saves
/// a picture of the window for each (for checking the layout without anyone at the Mac).
@MainActor
enum Snapshots {
    static func run(_ model: AppModel) {
        guard let dir = ProcessInfo.processInfo.environment["FLAGCAST_SNAPSHOTS"] else { return }
        log("snapshots: start, windows:", NSApp.windows.count)
        if ProcessInfo.processInfo.environment["FLAGCAST_SNAPSHOT_LIGHT"] == "1" { NSApp.appearance = NSAppearance(named: .aqua) }
        Task {
            try? await Task.sleep(for: .seconds(3))
            shot(dir, "home")
            guard let first = model.events.first else { NSApp.terminate(nil); return }
            model.selection = first.id
            for s in Section.allCases {
                model.section = s
                try? await Task.sleep(for: .seconds(s == .setup ? 4 : 2.5))
                shot(dir, s.rawValue)
            }
            // Admin (the test copy shows it; the local site lets any sign-in in)
            model.forceAdmin = true
            for a in AdminSection.allCases { model.adminSection = a; try? await Task.sleep(for: .seconds(a == .clubs ? 5 : 3)); shot(dir, "admin-\(a.rawValue)") }
            model.adminSection = nil
            // dark mode
            NSApp.appearance = NSAppearance(named: .darkAqua)
            for s in [Section.overview, .setup, .teams, .scores] { model.section = s; try? await Task.sleep(for: .seconds(2.5)); shot(dir, "\(s.rawValue)-dark") }
            model.selection = nil; try? await Task.sleep(for: .seconds(2.5)); shot(dir, "home-dark")
            model.adminSection = .clubs; try? await Task.sleep(for: .seconds(3)); shot(dir, "admin-clubs-dark")
            NSApp.terminate(nil)
        }
    }
    static func log(_ items: Any...) { FileHandle.standardError.write((items.map { "\($0)" }.joined(separator: " ") + "\n").data(using: .utf8)!) }
    static func shot(_ dir: String, _ name: String) {
        guard let w = NSApp.windows.first(where: { $0.isVisible }), let frame = w.contentView?.superview ?? w.contentView else { log("snapshots: no window"); return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        // 1) the system screenshot of the window (needs Screen Recording); 2) the window's layers drawn by hand
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-x", "-o", "-l", "\(w.windowNumber)", url.path]
        try? task.run(); task.waitUntilExit()
        if FileManager.default.fileExists(atPath: url.path) { log("snapshots: saved", name); return }
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
