#if os(macOS)
import Foundation
import FlutterMacOS
import Sparkle

/// Keeps the macOS app up to date, on the terms set out in docs/updates.md.
///
/// Sparkle rather than something of ours: replacing a running application on
/// macOS means staging a copy, checking its signature, quitting, swapping the
/// bundle and relaunching, and from inside a sandbox it means doing the swap
/// from a helper because the app itself cannot write to /Applications. Sparkle
/// has done all of that for twenty years and we would be reimplementing it
/// badly.
///
/// What is not delegated is the decision to ask at all, and what the asking
/// reveals. Sparkle will happily attach a system profile — model, CPU, OS
/// version, how many times the app has been launched — to the feed request. For
/// most software that is telemetry nobody minds. For a VPN client it is a
/// fingerprint, and the whole point of docs/updates.md is that two installations
/// send the same bytes. So the defaults are overridden explicitly below rather
/// than trusted to stay as they are across a Sparkle upgrade.
final class Updater: NSObject {
    static let channelName = "team.gdb.caelo/updates"

    private let controller: SPUStandardUpdaterController
    private let channel: FlutterMethodChannel

    init(messenger: FlutterBinaryMessenger) {
        // startingUpdater: false, because a controller that starts itself checks
        // on a schedule before anybody has told it whether checking is allowed.
        // The setting lives in Dart, and this waits to be told.
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
        super.init()

        let updater = controller.updater

        // Named for the program and not for the build. A user agent carrying a
        // version sorts installations into groups for anybody counting, and this
        // one reaches a server on every check.
        updater.userAgentString = "Caelo"

        // The profile is the fingerprint. Off in Info.plist as well; set here
        // too because one of the two is the one somebody will change without
        // realising what it did.
        updater.sendsSystemProfile = false

        // Nothing extra. Any header added here would be sent by every copy and
        // would have to be identical in all of them to be worth adding at all.
        updater.httpHeaders = nil

        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result)
        }
    }

    private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            // Told, not assumed. `enabled` is the switch in Settings, and it has
            // to reach Sparkle before the updater starts its cycle -- starting
            // first and disabling after would let one check escape.
            let enabled = call.arguments as? Bool ?? false
            controller.updater.automaticallyChecksForUpdates = enabled

            // Downloads are never automatic. Checking is small and can happen
            // quietly; fetching a disk image is not, and the person's connection
            // may be metered.
            controller.updater.automaticallyDownloadsUpdates = false

            if enabled {
                controller.startUpdater()
            }
            result(nil)

        case "setEnabled":
            let enabled = call.arguments as? Bool ?? false
            controller.updater.automaticallyChecksForUpdates = enabled
            result(nil)

        case "checkNow":
            // The one path that shows Sparkle's own interface, because somebody
            // asked for it and is waiting to see something happen.
            controller.checkForUpdates(nil)
            result(nil)

        case "canCheck":
            result(controller.updater.canCheckForUpdates)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
#endif
