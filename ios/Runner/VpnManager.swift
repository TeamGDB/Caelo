import Flutter
import Foundation
import NetworkExtension

/// Drives the tunnel from the app's side.
///
/// On iOS the app never touches the tunnel itself. It describes one to the
/// system, asks the system to start it, and is told what happened. The tunnel
/// runs in CaeloPacketTunnel, in another process, and the two share no memory —
/// so anything the interface wants to show has to be asked for across that
/// boundary.
///
/// The channel is named the same as Android's on purpose: the Dart side of both
/// platforms then differs only where the platforms genuinely differ.
final class VpnManager {

    static let channelName = "team.gdb.caelo/vpn"

    private static let providerBundleIdentifier = "team.gdb.caelo.PacketTunnel"

    private let channel: FlutterMethodChannel
    private var manager: NETunnelProviderManager?

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
            connect(config, result)

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
