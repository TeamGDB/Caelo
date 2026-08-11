import Foundation
import NetworkExtension

#if os(macOS)
import FlutterMacOS
import SystemExtensions
#else
import Flutter
#endif

/// Drives the tunnel from the app's side.
///
/// The app never touches the tunnel itself on either Apple platform. It describes one to the
/// system, asks the system to start it, and is told what happened. The tunnel
/// runs in CaeloPacketTunnel, in another process, and the two share no memory —
/// so anything the interface wants to show has to be asked for across that
/// boundary.
///
/// The channel is named the same as Android's on purpose: the Dart side of both
/// platforms then differs only where the platforms genuinely differ.
final class VpnManager {

    static let channelName = "team.gdb.caelo/vpn"

    // Which bundle the system starts to run the tunnel. On iOS that is the app
    // extension shipped inside the app; on macOS it is the system extension,
    // which is a different bundle with a different identifier. Naming the iOS
    // one here would have macOS save a configuration pointing at a provider
    // that does not exist on the machine.
    #if os(macOS)
    private static let providerBundleIdentifier = "team.gdb.caelo.SystemExtension"
    #else
    private static let providerBundleIdentifier = "team.gdb.caelo.PacketTunnel"
    #endif

    private let channel: FlutterMethodChannel
    private var manager: NETunnelProviderManager?

    #if os(macOS)
    private let installer = SystemExtensionInstaller()
    #endif

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result)
        }

        // The system can stop the tunnel without the app being involved: another
        // VPN starts, the user turns it off in Settings, the network goes away.
        // Without this the screen goes on claiming to be connected.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(statusChanged),
            name: .NEVPNStatusDidChange,
            object: nil
        )
    }

    // MARK: - Channel

    private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        switch call.method {
        case "prepare":
            // Nothing to prepare separately. Saving a configuration is what
            // raises the system's consent prompt, and that happens on connect.
            result(true)

        case "connect":
            guard let config = call.arguments as? String else {
                result(FlutterError(code: "connect", message: "no configuration", details: nil))
                return
            }
            #if os(macOS)
            // The extension has to be installed before there is anything to
            // describe a tunnel to. On iOS it ships inside the app and is
            // simply there; here the system installs it, and asks the user
            // first. Doing this on every connect is deliberate: it returns
            // immediately when the extension is already installed, and it is
            // the only moment we know the user wants the tunnel enough to be
            // interrupted for.
            installer.activate { refusal in
                guard refusal == nil else {
                    result(FlutterError(code: "extension", message: refusal, details: nil))
                    return
                }
                self.connect(config, result)
            }
            #else
            connect(config, result)
            #endif

        case "disconnect":
            load { manager in
                manager?.connection.stopVPNTunnel()
                result(nil)
            }

        case "isRunning":
            load { manager in
                result(manager?.connection.status == .connected)
            }

        case "status":
            load { manager in
                result(Self.name(for: manager?.connection.status ?? .invalid))
            }

        // Everything the tunnel knows lives in the other process. This is the
        // only way to see it.
        // Read from the shared container rather than asked for, so it works
        // when the extension has already been stopped -- which is exactly when
        // the question is worth asking.
        case "log":
            result(Self.sharedLog())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func connect(_ config: String, _ result: @escaping FlutterResult) {
        load { [weak self] existing in
            guard let self else { return }

            let manager = existing ?? NETunnelProviderManager()

            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = Self.providerBundleIdentifier
            // Shown in Settings under VPN. The system insists on something.
            proto.serverAddress = Self.endpoint(in: config) ?? "Caelo"
            // Carried in the configuration rather than through a shared file:
            // the system hands this dictionary to the extension when it starts
            // it, so there is nothing to keep in sync and nothing left behind.
            proto.providerConfiguration = ["config": config]

            manager.protocolConfiguration = proto
            manager.localizedDescription = "Caelo"
            manager.isEnabled = true

            // Saving is what raises "Caelo would like to add VPN
            // configurations". A refusal is a decision, not a failure.
            manager.saveToPreferences { error in
                if let error {
                    result(FlutterError(code: "save", message: error.localizedDescription, details: nil))
                    return
                }
                // Reloaded before starting: the freshly saved configuration is
                // not the object the system will actually run until it comes
                // back from preferences.
                manager.loadFromPreferences { error in
                    if let error {
                        result(FlutterError(code: "load", message: error.localizedDescription, details: nil))
                        return
                    }
                    do {
                        try manager.connection.startVPNTunnel()
                        self.manager = manager
                        result(nil)
                    } catch {
                        result(FlutterError(code: "start", message: error.localizedDescription, details: nil))
                    }
                }
            }
        }
    }

    /// What the extension wrote down, from the container they share.
    private static func sharedLog() -> String? {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.team.gdb.caelo")?
            .appendingPathComponent("tunnel.log") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Asks the extension something and hands back whatever it says.
    private func ask(_ message: String, _ result: @escaping FlutterResult) {
        load { manager in
            guard let session = manager?.connection as? NETunnelProviderSession,
                  manager?.connection.status != .invalid else {
                result(nil)
                return
            }
            do {
                try session.sendProviderMessage(Data(message.utf8)) { reply in
                    result(reply.flatMap { String(data: $0, encoding: .utf8) })
                }
            } catch {
                // The extension is not running, which is an ordinary state
                // rather than an error: there is simply nothing to say yet.
                result(nil)
            }
        }
    }

    // MARK: - Preferences

    /// Finds our configuration among any others on the device.
    private func load(_ done: @escaping (NETunnelProviderManager?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            let ours = managers?.first {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                    .providerBundleIdentifier == Self.providerBundleIdentifier
            }
            self.manager = ours ?? self.manager
            DispatchQueue.main.async { done(ours) }
        }
    }

    @objc private func statusChanged(_ notification: Notification) {
        guard let connection = notification.object as? NEVPNConnection else { return }
        DispatchQueue.main.async {
            self.channel.invokeMethod("status", arguments: Self.name(for: connection.status))
        }
    }

    private static func name(for status: NEVPNStatus) -> String {
        switch status {
        case .connected: return "connected"
        case .connecting, .reasserting: return "connecting"
        case .disconnecting: return "disconnecting"
        case .disconnected, .invalid: return "disconnected"
        @unknown default: return "disconnected"
        }
    }

    /// Pulls the endpoint out of the configuration for the label in Settings.
    /// Deliberately not a parser: the core owns that, and this is one line of
    /// display text.
    private static func endpoint(in config: String) -> String? {
        config
            .split(separator: "\n")
            .first { $0.lowercased().hasPrefix("endpoint") }
            .flatMap { $0.split(separator: "=").last }
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

#if os(macOS)

/// Asks the system to install the tunnel extension.
///
/// macOS does not run an extension because it is inside an app bundle. It has
/// to be handed to the system, which puts it somewhere of its own choosing and
/// asks the user to approve it in System Settings — and will refuse outright
/// unless the app is in /Applications and the extension is notarised.
final class SystemExtensionInstaller: NSObject, OSSystemExtensionRequestDelegate {

    private static let identifier = "team.gdb.caelo.SystemExtension"

    /// Called with nil when the extension is installed, or with the reason it
    /// is not. The reason is carried rather than reduced to a flag: every way
    /// this can fail is a different thing to do about it, and reporting them
    /// all as "not approved" sends the reader to System Settings to look at a
    /// switch that was never the problem.
    private var pending: ((String?) -> Void)?

    func activate(_ done: @escaping (String?) -> Void) {
        pending = done

        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: Self.identifier,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    private func finish(_ reason: String?) {
        let done = pending
        pending = nil
        DispatchQueue.main.async { done?(reason) }
    }

    // MARK: - OSSystemExtensionRequestDelegate

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension replacement: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        // Always replace. The one in the bundle is the one this build was
        // tested with, and leaving an older extension running against a newer
        // app is how two versions of the same tunnel end up disagreeing.
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        // The user is now looking at System Settings. Nothing to do but wait:
        // the result arrives through one of the two methods below.
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFinishWithResult result: OSSystemExtensionRequest.Result) {
        // willCompleteAfterReboot is not success. Reporting it as such would
        // have the app try to start a tunnel that cannot exist until a restart.
        finish(result == .completed
               ? nil
               : "the extension will not be in place until the machine restarts")
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        finish(Self.explain(error))
    }

    /// Turns the system's refusal into something that says what to do.
    ///
    /// `OSSystemExtensionError` descriptions are written for whoever wrote the
    /// app, not for whoever is looking at it, and two of these are routinely
    /// caused by the machine rather than the build — a second copy of the app
    /// lying around is enough for the system to inspect the wrong bundle.
    private static func explain(_ error: Error) -> String {
        let failure = error as NSError
        let code = failure.domain == OSSystemExtensionErrorDomain
            ? OSSystemExtensionError.Code(rawValue: failure.code) ?? .unknown
            : .unknown

        let advice: String? = switch code {
        case .extensionNotFound:
            "the system looked inside an app bundle that has no extension in it — "
                + "usually another copy of Caelo still registered on this machine"
        case .unsupportedParentBundleLocation:
            "Caelo has to be run from /Applications"
        case .authorizationRequired, .forbiddenBySystemPolicy:
            "approve it in System Settings → General → Login Items & Extensions"
        case .codeSignatureInvalid:
            "the extension's signature was rejected"
        case .validationFailed:
            "the system rejected the extension bundle"
        default:
            nil
        }

        let described = error.localizedDescription
        return advice.map { "\($0) (\(described))" } ?? described
    }
}

#endif
