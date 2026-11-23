import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

// Club branding (brand.js on the server): the club's logo shows to golfers and on the TVs instead of the Flagcast
// logo, which is kept for demos. Set by Flagcast staff (Admin → Clubs → Branding) or by the club (Settings).

/// Any picture (PNG, JPEG, HEIC, and SVG or PDF on the Mac) as the PNG data: URI the server takes: at most 1000 px
/// on its longest side, transparency kept, under about 280 KB.
enum LogoPrep {
    static func dataURI(_ data: Data) -> String? {
        var side: CGFloat = 1000
        for _ in 0..<6 {
            guard let png = png(data, maxSide: side) else { return nil }
            if png.count < 280_000 { return "data:image/png;base64," + png.base64EncodedString() }
            side *= 0.8
        }
        return nil
    }
    #if canImport(AppKit)
    private static func png(_ data: Data, maxSide: CGFloat) -> Data? {
        guard let img = NSImage(data: data), img.size.width > 0, img.size.height > 0 else { return nil }
        let rep0 = img.representations.first
        let px = CGSize(width: CGFloat(rep0?.pixelsWide ?? 0) > 0 ? CGFloat(rep0!.pixelsWide) : img.size.width,
                        height: CGFloat(rep0?.pixelsHigh ?? 0) > 0 ? CGFloat(rep0!.pixelsHigh) : img.size.height)
        let vector = !(rep0 is NSBitmapImageRep)
        let f = min(vector ? maxSide / max(px.width, px.height) : 1, maxSide / max(px.width, px.height))
        let w = max(1, Int(px.width * f)), h = max(1, Int(px.height * f))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: w, height: h)); NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
    #else
    private static func png(_ data: Data, maxSide: CGFloat) -> Data? {
        guard let img = UIImage(data: data), img.size.width > 0 else { return nil }
        let px = CGSize(width: img.size.width * img.scale, height: img.size.height * img.scale)
        let f = min(1, maxSide / max(px.width, px.height))
        let size = CGSize(width: max(1, (px.width * f).rounded()), height: max(1, (px.height * f).rounded()))
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = false
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }.pngData()
    }
    #endif
}

/// A photo for golfers (cover, hole, sponsor banner) as the JPEG data: URI the server takes: at most 1600 px on its
/// longest side, under about 1.1 MB.
enum PhotoPrep {
    static func dataURI(_ data: Data) -> String? {
        for (side, q) in [(1600.0, 0.82), (1600.0, 0.68), (1280.0, 0.65), (1000.0, 0.6)] {
            guard let j = jpeg(data, maxSide: side, quality: q) else { return nil }
            if j.count < 1_100_000 { return "data:image/jpeg;base64," + j.base64EncodedString() }
        }
        return nil
    }
    #if canImport(AppKit)
    private static func jpeg(_ data: Data, maxSide: CGFloat, quality: Double) -> Data? {
        guard let img = NSImage(data: data), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let f = min(1, maxSide / CGFloat(max(cg.width, cg.height)))
        let w = max(1, Int(CGFloat(cg.width) * f)), h = max(1, Int(CGFloat(cg.height) * f))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.cgContext.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h)); NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
    #else
    private static func jpeg(_ data: Data, maxSide: CGFloat, quality: Double) -> Data? {
        guard let img = UIImage(data: data), img.size.width > 0 else { return nil }
        let px = CGSize(width: img.size.width * img.scale, height: img.size.height * img.scale)
        let f = min(1, maxSide / max(px.width, px.height))
        let size = CGSize(width: max(1, (px.width * f).rounded()), height: max(1, (px.height * f).rounded()))
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = true
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: quality)
    }
    #endif
}

/// One photo spot for the Manager apps: the picture (or "Add …"), tap to pick one (Photos on iPhone, a file on the
/// Mac), with a remove button. Saves at once.
struct PhotoSpot: View {
    @Bindable var doc: DeskDoc
    let slot: String
    let label: String
    let url: URL?
    var height: CGFloat = 90
    @State private var importing = false
    #if os(iOS)
    @State private var picked: PhotosPickerItem?
    #endif
    var body: some View {
        let busy = doc.photoBusy.contains(slot)
        picker(tile(busy))
            .disabled(busy)
            .overlay(alignment: .topTrailing) {
                if url != nil && !busy {
                    Button { Task { await doc.setPhoto(slot, nil) } } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(.white, .black.opacity(0.55)) }
                        .buttonStyle(.plain).padding(5).accessibilityLabel("Remove \(label)")
                }
            }
            .accessibilityLabel(url == nil ? "Add \(label)" : label)
    }
    private func tile(_ busy: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12))
                .overlay { if let url { RemotePhoto(url: url) } }
                .overlay { if url == nil { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4])) } }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(url == nil ? "Add \(label.lowercased())" : label)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(url == nil ? Color.secondary : .white)
                .shadow(color: url == nil ? .clear : .black.opacity(0.6), radius: 3)
                .padding(8)
            if busy { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .frame(height: height)
        .contentShape(Rectangle())
    }
    #if os(iOS)
    private func picker(_ t: some View) -> some View {
        PhotosPicker(selection: $picked, matching: .images) { t }
            .buttonStyle(.plain)
            .onChange(of: picked) { _, item in
                guard let item else { return }
                picked = nil
                Task { if let d = try? await item.loadTransferable(type: Data.self) { await doc.setPhoto(slot, d) } else { doc.flash("That photo couldn’t be opened.") } }
            }
    }
    #else
    private func picker(_ t: some View) -> some View {
        Button { importing = true } label: { t }
            .buttonStyle(.plain)
            .contextMenu {
                Button(url == nil ? "Add Photo…" : "Change Photo…") { importing = true }
                if url != nil { Button("Remove Photo", role: .destructive) { Task { await doc.setPhoto(slot, nil) } } }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.jpeg, .png, .heic, .webP, .image]) { r in
                guard case .success(let file) = r else { return }
                let ok = file.startAccessingSecurityScopedResource(); defer { if ok { file.stopAccessingSecurityScopedResource() } }
                let d = try? Data(contentsOf: file)
                Task { await doc.setPhoto(slot, d) }
            }
    }
    #endif
}

/// A photo from the server by address, filling its frame.
struct RemotePhoto: View {
    let url: URL
    @State private var image: Image?
    @MainActor private static var cache: [URL: Image] = [:]
    var body: some View {
        Color.clear.overlay { if let image { image.resizable().aspectRatio(contentMode: .fill) } }
            .clipped()
            .task(id: url) {
                if let c = Self.cache[url] { image = c; return }
                guard let (d, r) = try? await Net.session.data(from: url), (r as? HTTPURLResponse)?.statusCode == 200 else { return }
                #if canImport(AppKit)
                guard let n = NSImage(data: d) else { return }; let i = Image(nsImage: n)
                #else
                guard let u = UIImage(data: d) else { return }; let i = Image(uiImage: u)
                #endif
                if Self.cache.count > 60 { Self.cache.removeAll() }
                Self.cache[url] = i; image = i
            }
    }
}

/// A picture from the server by address (club logos), kept in memory once loaded.
struct RemoteLogo: View {
    let url: URL
    @State private var image: Image?
    @MainActor private static var cache: [URL: Image] = [:]
    var body: some View {
        Group { if let image { image.resizable().scaledToFit() } else { Color.clear } }
            .task(id: url) {
                if let c = Self.cache[url] { image = c; return }
                guard let (d, r) = try? await Net.session.data(from: url), (r as? HTTPURLResponse)?.statusCode == 200 else { return }
                #if canImport(AppKit)
                guard let i = NSImage(data: d) else { return }; let img = Image(nsImage: i)
                #else
                guard let i = UIImage(data: d) else { return }; let img = Image(uiImage: i)
                #endif
                Self.cache[url] = img; image = img
            }
    }
}

/// a club logo address from the server ('' = none) as a full URL
func logoURL(_ path: String?) -> URL? { (path ?? "").isEmpty ? nil : Net.url(path!) }

extension Color {
    /// "#1a6b3c" → Color
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")); guard h.count == 6, let v = Int(h, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
    /// Color → "#1a6b3c"
    var hex: String {
        #if canImport(AppKit)
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "" }
        let (r, g, b) = (c.redComponent, c.greenComponent, c.blueComponent)
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0; UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return String(format: "#%02x%02x%02x", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

/// The club's logo and colour, with Choose / Remove. `save` sends the changes (logo, accent, powered) and says whether
/// they took; the caller reloads so `logo` shows the new one.
struct BrandingEditor: View {
    var logo: URL?
    var accent: String
    var forWhat = "Your club’s logo shows on the TVs, the live page and the players’ app instead of the Flagcast logo."
    var showPowered = false
    var powered = false
    var save: (_ changes: [String: Any]) async -> String?   // nil = saved, else the problem
    @State private var importing = false
    @State private var color = Color.green
    @State private var hasColor = false
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.07, green: 0.21, blue: 0.16))
                    if let logo { RemoteLogo(url: logo).padding(8) } else { Text("Flagcast logo\nfor now").font(.caption).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.8)) }
                }
                .frame(width: 170, height: 76)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button(logo == nil ? "Choose Logo…" : "Change Logo…") { importing = true }.disabled(busy)
                        if logo != nil { Button("Remove", role: .destructive) { send(["logo": ""]) }.disabled(busy) }
                        if busy { ProgressView().controlSize(.small) }
                    }
                    Text(logo == nil ? "No logo yet, so golfers see the Flagcast logo." : "A PNG with a see-through background looks best on the dark TV screens.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(forWhat).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                ColorPicker("Club colour", selection: $color, supportsOpacity: false).onChange(of: color) { _, _ in hasColor = true }
                Spacer()
                if hasColor && color.hex != accent { Button("Save Colour") { send(["accent": color.hex]) }.disabled(busy) }
                if !accent.isEmpty { Button("No Colour") { send(["accent": ""]) }.disabled(busy) }
            }
            if showPowered {
                Toggle("Show “Powered by Flagcast” (small, under the club’s logo)", isOn: Binding(get: { powered }, set: { v in send(["powered": v]) })).disabled(busy)
            }
            if let problem { Text(problem).font(.caption).foregroundStyle(.red) }
        }
        .onAppear { if let c = Color(hex: accent) { color = c } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg, .heic, .svg, .pdf, .webP, .image]) { r in
            guard case .success(let url) = r else { return }
            let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
            guard let d = try? Data(contentsOf: url) else { problem = "That file couldn’t be opened."; return }
            guard let uri = LogoPrep.dataURI(d) else { problem = "That file isn’t a picture this app can read. Try a PNG."; return }
            send(["logo": uri])
        }
    }
    private func send(_ changes: [String: Any]) {
        busy = true; problem = nil
        Task { problem = await save(changes); busy = false; if problem == nil, changes["accent"] != nil { hasColor = false } }
    }
}

/// The DEMO chip: a tournament Flagcast Admin marked Demo shows the Flagcast logo.
struct DemoChip: View {
    var body: some View {
        Text("DEMO").font(.caption2.monospaced().weight(.bold)).tracking(1)
            .padding(.horizontal, 6).padding(.vertical, 2).background(Color.orange.opacity(0.2), in: Capsule()).foregroundStyle(.orange)
            .accessibilityLabel("Demo: shows the Flagcast logo")
    }
}

#if canImport(AppKit)
/// Setup → Logo: the club's logo (the usual), or one just for this tournament (a sponsor's event, a charity day).
struct TournamentLogoField: View {
    @Binding var logo: String
    @State private var importing = false
    @State private var problem: String?
    private var preview: NSImage? {
        guard let i = logo.range(of: "base64,"), let d = Data(base64Encoded: String(logo[i.upperBound...])) else { return nil }
        return NSImage(data: d)
    }
    var body: some View {
        HStack(spacing: 8) {
            if let p = preview { Image(nsImage: p).resizable().scaledToFit().frame(width: 90, height: 28).padding(3).background(Color(red: 0.07, green: 0.21, blue: 0.16), in: RoundedRectangle(cornerRadius: 5)) }
            else { Text("The club’s logo").foregroundStyle(.secondary) }
            Spacer()
            Button(logo.isEmpty ? "Use Another…" : "Change…") { importing = true }
            if !logo.isEmpty { Button("Use the Club’s") { logo = "" } }
        }
        .help("Golfers and the TVs see the club’s logo. Pick another just for this tournament, then Save.")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg, .heic, .svg, .pdf, .webP, .image]) { r in
            guard case .success(let url) = r else { return }
            let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let d = try? Data(contentsOf: url), let uri = LogoPrep.dataURI(d) { logo = uri } else { problem = "That file isn’t a picture this app can read." }
        }
        .overlay(alignment: .bottomLeading) { if let problem { Text(problem).font(.caption).foregroundStyle(.red).offset(y: 16) } }
    }
}
#endif

// ---- club logos in Admin (Mac and iPhone) ----

/// How Admin's club cards look (both kept, picked on the Clubs page and remembered on each device): the club's logo
/// on a tile over its place photo, or the logo big on the club's own colour. A club with no logo yet keeps its photo either way.
enum ClubLook: String, CaseIterable, Identifiable {
    case photo, logo
    var id: String { rawValue }
    var title: String { self == .photo ? "Logo on photo" : "Logo on colour" }
    static let key = "admin.clubLook"
}

extension AdminModel {
    /// a club's logo address by its id (nil when it has none, or the clubs haven't loaded)
    func logo(club id: String) -> URL? { logoURL(clubs.first { $0.id == id }?.logo) }
    /// the logo to show beside a tournament in Admin: its club's uploaded logo, else the one the tournament itself shows
    func logo(for e: AdminEvent) -> URL? { logo(club: e.club) ?? logoURL(e.logo) }
}

/// "Oak Hollow Golf Club" → "OH": for a club with no logo yet
func clubInitials(_ name: String) -> String {
    let skip: Set<String> = ["the", "golf", "club", "country", "gc", "cc", "and", "of", "&"]
    let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    let keep = words.filter { !skip.contains($0.lowercased()) }
    return String((keep.isEmpty ? words : keep).prefix(2).compactMap(\.first)).uppercased()
}

/// The club's logo on a tile (or its initials when it has none): Admin's club cards and tournament rows.
/// Dark logos sit on white; a light logo (a white one, say) sits on dark green so it doesn't vanish.
struct ClubLogoTile: View {
    var url: URL?
    var name: String
    var size: CGFloat = 32
    @State private var loaded: TileLogo?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22).fill(url == nil ? FC.green2 : (loaded?.light == true ? FC.green : Color.white))
            if url != nil { if let loaded { loaded.image.resizable().scaledToFit().padding(size * 0.12) } }
            else { Text(clubInitials(name)).font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(Color.white) }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(name) logo")
        .task(id: url) { loaded = nil; if let url { loaded = await TileLogo.load(url) } }
    }
}

/// a logo for a ClubLogoTile, and whether it's mostly light (so it goes on a dark tile)
struct TileLogo {
    let image: Image, light: Bool
    @MainActor private static var cache: [URL: TileLogo] = [:]
    @MainActor static func load(_ url: URL) async -> TileLogo? {
        if let c = cache[url] { return c }
        guard let (d, r) = try? await Net.session.data(from: url), (r as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        #if canImport(AppKit)
        guard let n = NSImage(data: d) else { return nil }; let img = Image(nsImage: n); let cg = n.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        guard let u = UIImage(data: d) else { return nil }; let img = Image(uiImage: u); let cg = u.cgImage
        #endif
        let t = TileLogo(image: img, light: cg.map(isLight) ?? false)
        if cache.count > 80 { cache.removeAll() }
        cache[url] = t; return t
    }
    /// shrinks the logo to 24×24 and averages the brightness of the pixels that aren't see-through
    static func isLight(_ cg: CGImage) -> Bool {
        let w = 24, h = 24; var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0.0, weight = 0.0, clear = 0
        for i in stride(from: 0, to: px.count, by: 4) {
            let a = Double(px[i + 3]) / 255; guard a > 0.15 else { clear += 1; continue }
            let lum = (0.299 * Double(px[i]) + 0.587 * Double(px[i + 1]) + 0.114 * Double(px[i + 2])) / 255 / a   // undo premultiplying
            sum += min(lum, 1) * a; weight += a
        }
        // a logo with no see-through background (a JPEG, say) brings its own backdrop: leave it on white
        return clear > w * h / 20 && weight > 0 && sum / weight > 0.82
    }
}

/// Option B behind a club card: the club's colour with its logo big in the middle (nothing when it has no logo, so the photo shows).
struct ClubLogoBackdrop: View {
    let club: AdminClub
    var body: some View {
        if let u = logoURL(club.logo) {
            ZStack {
                Color(hex: club.accent) ?? FC.green
                RemoteLogo(url: u).padding(.horizontal, 48).padding(.top, 40).padding(.bottom, 118)
            }
        }
    }
}
