import SwiftUI
import WebKit
import SafariServices

/// Flagcast Manager and Flagcast Admin for iPhone and iPad: the same pages the Mac apps load
/// (flagcast.app/golf/ and /golf/admin/), laid out for phones and tablets, in a native shell so they can be
/// used on the course. Sign-ins stay on the device; pages from other sites open in Safari view; files the
/// pages hand out (reports) go to the share sheet; pull down to reload.
struct AppConfig {
    var name: String          // "Flagcast Manager"
    var startPath: String     // "/golf/" or "/golf/admin/"
    var agent: String         // added to the user agent, so pages can tell they're in the app

    static let production = URL(string: "https://flagcast.app")!
    /// Debug builds can point at a local copy of the site: launch argument -FlagcastServer http://localhost:8787
    var base: URL {
        #if DEBUG
        if let s = UserDefaults.standard.string(forKey: "FlagcastServer"), let u = URL(string: s) { return u }
        #endif
        return Self.production
    }
    var startURL: URL { URL(string: startPath, relativeTo: base)!.absoluteURL }
}

let fcGreen = Color(red: 0x12 / 255, green: 0x36 / 255, blue: 0x28 / 255)
let fcFlag = Color(red: 0xe8 / 255, green: 0xc5 / 255, blue: 0x47 / 255)

@MainActor @Observable
final class ShellModel {
    var canGoBack = false
    var loading = false
    var failed: String?
    var title = ""
    var atHome = true
    var external: URL?
    var share: URL?
    weak var web: WKWebView?
}

struct ShellView: View {
    let config: AppConfig
    @State private var model = ShellModel()
    @Environment(\.scenePhase) private var phase

    var body: some View {
        VStack(spacing: 0) {
            if !model.atHome {
                HStack(spacing: 4) {
                    Button { if model.canGoBack { model.web?.goBack() } else { model.web?.load(URLRequest(url: config.startURL)) } } label: {
                        Label("Back", systemImage: "chevron.left").font(.body.weight(.semibold))
                    }
                    Spacer()
                    Text(model.title).font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Button { model.web?.load(URLRequest(url: config.startURL)) } label: { Image(systemName: "house.fill") }
                        .accessibilityLabel("Home")
                }
                .padding(.horizontal, 14).frame(height: 40)
                .foregroundStyle(fcFlag)
                .background(fcGreen)
            }
            ZStack {
                WebView(config: config, model: model).ignoresSafeArea(edges: .bottom)
                if let f = model.failed {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.slash").font(.largeTitle)
                        Text("Can’t reach Flagcast").font(.title2.weight(.bold))
                        Text("Check this phone’s connection, then try again.").foregroundStyle(.white.opacity(0.75))
                        Text(f).font(.footnote).foregroundStyle(.white.opacity(0.5))
                        Button("Try again") { model.failed = nil; model.web?.reload() }
                            .font(.headline).padding(.horizontal, 22).frame(minHeight: 46)
                            .background(fcFlag, in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(.black)
                    }
                    .multilineTextAlignment(.center).padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(fcGreen).foregroundStyle(.white)
                }
            }
        }
        .background(fcGreen.ignoresSafeArea())
        .sheet(item: $model.external) { SafariSheet(url: $0).ignoresSafeArea() }
        .sheet(item: $model.share) { ShareSheet(items: [$0]) }
        .onChange(of: phase) { _, p in
            // back on the course after the phone slept: pick up anything that changed
            if p == .active, model.failed != nil { model.failed = nil; model.web?.reload() }
        }
    }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

struct WebView: UIViewRepresentable {
    let config: AppConfig
    let model: ShellModel

    func makeCoordinator() -> Coordinator { Coordinator(config: config, model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = .default()           // sign-ins and settings stay on this device
        c.allowsInlineMediaPlayback = true
        c.mediaTypesRequiringUserActionForPlayback = []
        c.applicationNameForUserAgent = config.agent
        let w = WKWebView(frame: .zero, configuration: c)
        w.navigationDelegate = context.coordinator
        w.uiDelegate = context.coordinator
        w.allowsBackForwardNavigationGestures = true
        w.isOpaque = false
        w.backgroundColor = UIColor(red: 0xf2 / 255, green: 0xf4 / 255, blue: 0xef / 255, alpha: 1)   // the pages' paper colour
        w.scrollView.contentInsetAdjustmentBehavior = .automatic
        let refresh = UIRefreshControl()
        refresh.tintColor = .white
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.pull(_:)), for: .valueChanged)
        w.scrollView.refreshControl = refresh
        #if DEBUG
        if #available(iOS 16.4, *) { w.isInspectable = true }
        #endif
        model.web = w
        context.coordinator.observe(w)
        w.load(URLRequest(url: config.startURL))
        return w
    }
    func updateUIView(_ w: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        let config: AppConfig
        let model: ShellModel
        private var obs: [NSKeyValueObservation] = []
        private var downloads: [WKDownload: URL] = [:]
        init(config: AppConfig, model: ShellModel) { self.config = config; self.model = model }

        func observe(_ w: WKWebView) {
            obs = [
                w.observe(\.canGoBack, options: [.new]) { [weak self] w, _ in Task { @MainActor in self?.model.canGoBack = w.canGoBack } },
                w.observe(\.title, options: [.new]) { [weak self] w, _ in Task { @MainActor in self?.model.title = w.title ?? "" } },
                w.observe(\.url, options: [.new]) { [weak self] w, _ in Task { @MainActor in self?.updateHome(w.url) } },
            ]
        }
        private func updateHome(_ u: URL?) {
            guard let u else { return }
            let home = config.startURL
            model.atHome = u.host == home.host && u.path == home.path
        }
        @objc func pull(_ r: UIRefreshControl) { model.web?.reload(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { r.endRefreshing() } }

        private func ours(_ u: URL) -> Bool {
            u.host == config.base.host || u.scheme == "about" || u.scheme == "blob" || u.scheme == "data"
        }

        func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let u = a.request.url else { return .cancel }
            if a.shouldPerformDownload { return .download }
            if ["mailto", "tel", "sms"].contains(u.scheme ?? "") { await UIApplication.shared.open(u); return .cancel }
            if ours(u) { return .allow }
            // links to other sites (sponsors, help pages): Safari view, the page stays put
            if a.navigationType == .linkActivated || a.targetFrame == nil { model.external = u; return .cancel }
            return .allow   // other sites a page loads inside itself (camera players)
        }
        func webView(_ w: WKWebView, decidePolicyFor r: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            if let h = r.response as? HTTPURLResponse, let cd = h.value(forHTTPHeaderField: "Content-Disposition"), cd.lowercased().contains("attachment") { return .download }
            return r.canShowMIMEType ? .allow : .download
        }
        func webView(_ w: WKWebView, navigationAction: WKNavigationAction, didBecome d: WKDownload) { d.delegate = self }
        func webView(_ w: WKWebView, navigationResponse: WKNavigationResponse, didBecome d: WKDownload) { d.delegate = self }

        // target=_blank / window.open: Flagcast pages open here (swipe or Back to return), others in Safari view
        func webView(_ w: WKWebView, createWebViewWith c: WKWebViewConfiguration, for a: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let u = a.request.url {
                if ours(u) { w.load(URLRequest(url: u)) } else { model.external = u }
            }
            return nil
        }
        func webView(_ w: WKWebView, runJavaScriptAlertPanelWithMessage m: String, initiatedByFrame f: WKFrameInfo) async {
            await present(UIAlertController(title: nil, message: m, preferredStyle: .alert), actions: [("OK", .default, true)])
        }
        func webView(_ w: WKWebView, runJavaScriptConfirmPanelWithMessage m: String, initiatedByFrame f: WKFrameInfo) async -> Bool {
            await present(UIAlertController(title: nil, message: m, preferredStyle: .alert), actions: [("Cancel", .cancel, false), ("OK", .default, true)])
        }
        func webView(_ w: WKWebView, runJavaScriptTextInputPanelWithPrompt p: String, defaultText d: String?, initiatedByFrame f: WKFrameInfo) async -> String? {
            await withCheckedContinuation { cont in
                let ac = UIAlertController(title: nil, message: p, preferredStyle: .alert)
                ac.addTextField { $0.text = d }
                ac.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in cont.resume(returning: nil) })
                ac.addAction(UIAlertAction(title: "OK", style: .default) { _ in cont.resume(returning: ac.textFields?.first?.text ?? "") })
                top()?.present(ac, animated: true)
            }
        }
        private func present(_ ac: UIAlertController, actions: [(String, UIAlertAction.Style, Bool)]) async -> Bool {
            await withCheckedContinuation { cont in
                for (t, s, v) in actions { ac.addAction(UIAlertAction(title: t, style: s) { _ in cont.resume(returning: v) }) }
                top()?.present(ac, animated: true)
            }
        }
        private func top() -> UIViewController? {
            var vc = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
            while let p = vc?.presentedViewController { vc = p }
            return vc
        }

        func webView(_ w: WKWebView, didStartProvisionalNavigation n: WKNavigation!) { model.loading = true }
        func webView(_ w: WKWebView, didFinish n: WKNavigation!) { model.loading = false; model.failed = nil; updateHome(w.url) }
        func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { fail(e) }
        func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { fail(e) }
        private func fail(_ e: Error) {
            model.loading = false
            let ns = e as NSError
            if ns.code == NSURLErrorCancelled || ns.domain == "WebKitErrorDomain" { return }
            model.failed = e.localizedDescription
        }

        // reports and other files the pages hand out: saved to a temporary file, then the share sheet
        func download(_ d: WKDownload, decideDestinationUsing r: URLResponse, suggestedFilename name: String) async -> URL? {
            let u = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: u)
            downloads[d] = u
            return u
        }
        func downloadDidFinish(_ d: WKDownload) { if let u = downloads.removeValue(forKey: d) { model.share = u } }
        func download(_ d: WKDownload, didFailWithError e: Error, resumeData: Data?) { downloads[d] = nil; model.failed = e.localizedDescription }
    }
}

struct SafariSheet: UIViewControllerRepresentable {
    var url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ c: SFSafariViewController, context: Context) {}
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ c: UIActivityViewController, context: Context) {}
}
