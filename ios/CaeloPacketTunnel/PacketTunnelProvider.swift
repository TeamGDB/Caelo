import Foundation
import NetworkExtension
import os

/// Runs the tunnel.
///
/// On iOS this is where the tunnel actually lives: a separate process the
/// system starts, hands a utun descriptor, and stops when it decides to. The
/// app cannot do any of it, which is why the split here is nothing like macOS
/// or Android.
///
/// This file does not know what AmneziaWG is, and should not learn. It asks the
/// core to describe the configuration, tells the system what the tunnel looks
/// like, and hands the descriptor over. Everything else is Go.
class PacketTunnelProvider: NEPacketTunnelProvider {

    // os_log rather than Logger: the latter is iOS 14 in an app extension, and
    // raising the deployment target for a logging call would drop iOS 13
    // devices from the tunnel to gain nothing.
    private let log = OSLog(subsystem: "team.gdb.caelo", category: "tunnel")

    // Both, deliberately. os_log is for anyone with the device attached to a
    // Mac; the file is for everyone else, and it is the one that survives this
    // process being stopped.
    private func note(_ message: String) {
        os_log("%{public}@", log: log, type: .info, message)
        TunnelLog.note(message)
    }

    private func fault(_ message: String) {
        os_log("%{public}@", log: log, type: .error, message)
        TunnelLog.note("error: \(message)")
    }

    override func startTunnel(options: [String: NSObject]?) async throws {
        TunnelLog.begin()
        note("startTunnel")

        guard let config = configuration() else {
            fault("started with no configuration")
            throw NEVPNError(.configurationInvalid)
        }

        // The core owns the format. A second parser on this side would
        // eventually disagree with the one that actually dials, and this is
        // the side nobody would be testing.
        guard let described = call({ caelo_describe(strdup(config)) }) else {
            throw NEVPNError(.configurationInvalid)
        }
        guard described["ok"] as? Bool == true else {
            fault("core refused the configuration: \(described["error"] ?? "no reason given")")
            throw NEVPNError(.configurationInvalid)
        }

        note("core described the configuration: endpoint \(described["endpoint"] ?? "?"), mtu \(described["mtu"] ?? "?"), routes \((described["allowed_ips"] as? [String])?.count ?? 0)")

        do {
            try await setTunnelNetworkSettings(settings(from: described))
            note("network settings applied")
        } catch {
            fault("the system rejected the network settings: \(error)")
            throw error
        }

        // Only valid once the settings are applied: before that there is no
        // interface to have a descriptor for.
        let fd = tunnelDescriptor()
        note("tunnel descriptor \(fd)")
        guard fd >= 0 else {
            fault("the system provided no tunnel descriptor")
            throw NEVPNError(.connectionFailed)
        }

        let started = call { caelo_connect_fd(Int32(fd), strdup(config)) }
        guard started?["ok"] as? Bool == true else {
            fault("the core could not adopt the descriptor: \(started?["error"] ?? "no reason given")")
            throw NEVPNError(.connectionFailed)
        }

        protectSockets()
        note("tunnel up")

        // The core's own account of the handshake, folded into the same file so
        // that one thing survives the process rather than two.
        if let core = call({ caelo_log() }), let lines = core["lines"] as? [String] {
            lines.suffix(60).forEach { TunnelLog.note("core \($0)") }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        note("stopping, reason \(reason.rawValue)")
        if let core = call({ caelo_log() }), let lines = core["lines"] as? [String] {
            lines.suffix(60).forEach { TunnelLog.note("core \($0)") }
        }
        _ = call { caelo_disconnect_fd() }
    }

    /// Answers the app. The app and this process share no memory, so anything
    /// the interface wants to show has to be asked for.
    override func handleAppMessage(_ data: Data) async -> Data? {
        guard let request = String(data: data, encoding: .utf8) else { return nil }

        switch request {
        case "log":
            guard let payload = call({ caelo_log() }) else { return nil }
            return try? JSONSerialization.data(withJSONObject: payload)
        case "status":
            guard let payload = call({ caelo_status_fd() }) else { return nil }
            return try? JSONSerialization.data(withJSONObject: payload)
        default:
            return nil
        }
    }

    // MARK: - The core

    /// Calls into the core and decodes what it says.
    ///
    /// Every string the core returns is ours to free, and forgetting leaks a
    /// little on every call — which is why this is the only place that talks
    /// to it.
    private func call(_ body: () -> UnsafeMutablePointer<CChar>?) -> [String: Any]? {
        guard let raw = body() else { return nil }
        defer { caelo_free(raw) }

        let json = String(cString: raw)
        return (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
    }

    /// Excludes the tunnel's own sockets from the routes it just installed.
    ///
    /// Advisory, as it is on Android: a descriptor that cannot be found comes
    /// back as -1 and is skipped. Treating that as fatal would refuse to
    /// connect on a device that has no IPv6.
    private func protectSockets() {
        guard let fds = call({ caelo_socket_fds() }) else { return }
        for key in ["v4", "v6"] {
            if let fd = fds[key] as? Int, fd >= 0 {
                var flag: Int32 = 1
                setsockopt(Int32(fd), SOL_SOCKET, SO_NOSIGPIPE, &flag, socklen_t(MemoryLayout<Int32>.size))
            }
        }
    }

    // MARK: - Plumbing

    private func configuration() -> String? {
        let proto = protocolConfiguration as? NETunnelProviderProtocol
        return proto?.providerConfiguration?["config"] as? String
    }

    /// Turns what the core said into what the system wants to hear.
    private func settings(from described: [String: Any]) -> NEPacketTunnelNetworkSettings {
        let endpoint = (described["endpoint"] as? String) ?? ""
        let host = endpoint.split(separator: ":").first.map(String.init) ?? "127.0.0.1"

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: host)
        settings.mtu = NSNumber(value: (described["mtu"] as? Int) ?? 1420)

        let addresses = (described["addresses"] as? [String]) ?? []
        let v4 = addresses.filter { !$0.contains(":") }
        if !v4.isEmpty {
            let ipv4 = NEIPv4Settings(addresses: v4, subnetMasks: v4.map { _ in "255.255.255.255" })
            // Every route the configuration allows. An empty list would leave
            // the tunnel up and carrying nothing.
            ipv4.includedRoutes = ((described["allowed_ips"] as? [String]) ?? [])
                .filter { !$0.contains(":") }
                .compactMap(Self.route)
            settings.ipv4Settings = ipv4
        }

        if let dns = described["dns"] as? [String], !dns.isEmpty {
            let resolver = NEDNSSettings(servers: dns)
            // Resolution has to happen inside the tunnel, so this resolver
            // answers for everything rather than for a list of domains.
            resolver.matchDomains = [""]
            settings.dnsSettings = resolver
        }

        return settings
    }

    private static func route(_ cidr: String) -> NEIPv4Route? {
        let parts = cidr.split(separator: "/")
        guard let address = parts.first.map(String.init) else { return nil }
        let bits = parts.count > 1 ? Int(parts[1]) ?? 32 : 32

        if address == "0.0.0.0" && bits == 0 { return NEIPv4Route.default() }

        var mask: UInt32 = bits == 0 ? 0 : ~UInt32(0) << (32 - bits)
        let octets = (0..<4).map { _ -> String in
            defer { mask <<= 8 }
            return String((mask & 0xFF00_0000) >> 24)
        }
        return NEIPv4Route(destinationAddress: address, subnetMask: octets.joined(separator: "."))
    }

    /// The descriptor behind packetFlow.
    ///
    /// There is no public accessor, and the obvious trick — reading
    /// packetFlow's "socket.fileDescriptor" key path — is undocumented and has
    /// stopped working. So the socket is found rather than asked for: every
    /// descriptor this process holds is examined until one turns out to be
    /// connected to the kernel's utun control, which only the tunnel's can be.
    ///
    /// The approach is wireguard-apple's, which has survived a decade of iOS
    /// releases the key path did not.
    ///
    /// The alternative is copying every packet through readPackets and
    /// writePackets, at a copy in each direction for no benefit.
    private func tunnelDescriptor() -> Int32 {
        var control = ctl_info()
        withUnsafeMutablePointer(to: &control.ctl_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: $0.pointee)) {
                _ = strcpy($0, "com.apple.net.utun_control")
            }
        }

        for fd in Int32(0)...1024 {
            var address = sockaddr_ctl()
            var length = socklen_t(MemoryLayout.size(ofValue: address))
            var result: Int32 = -1

            withUnsafeMutablePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    result = getpeername(fd, $0, &length)
                }
            }
            guard result == 0, address.sc_family == AF_SYSTEM else { continue }

            if control.ctl_id == 0, ioctl(fd, CTLIOCGINFO, &control) != 0 { continue }
            if address.sc_id == control.ctl_id { return fd }
        }

        return -1
    }
}
