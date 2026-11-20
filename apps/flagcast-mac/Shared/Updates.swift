import Foundation
import Sparkle

/// One-click updates with Sparkle. The feed is SUFeedURL in Info.plist (flagcast.app/updates/<app>/appcast.xml, from
/// the latest GitHub release), checked at launch and from Check for Updates…. Sparkle asks before installing:
/// "Install and Relaunch" or later. Updates are signed (SUPublicEDKey) as well as notarized by Apple.
final class Updates: NSObject {
    static let shared = Updates()
    private var controller: SPUStandardUpdaterController?

    func start() {
        #if DEBUG
        return   // test builds don't update themselves
        #else
        guard Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller?.updater.automaticallyChecksForUpdates = UserDefaults.standard.object(forKey: "updates.auto") as? Bool ?? true
        #endif
    }
    func check() {
        if let c = controller { c.checkForUpdates(nil); return }
        let a = NSAlert()
        a.messageText = "Updates aren’t switched on in this copy"
        a.informativeText = "This copy of Flagcast was built for testing. The installed app checks flagcast.app for new versions by itself."
        a.runModal()
    }
    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? true }
}

import AppKit
