import Foundation

/// Bounded, serialized lifecycle history shared with the app. Live core lines
/// are requested separately, so an export need not stop the VPN to see a fault.
enum TunnelLog {
    private static let store: TunnelLogStore? = {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.team.gdb.caelo") else { return nil }
        return TunnelLogStore(url: root.appendingPathComponent("Library/Caches/Caelo/tunnel.log"), legacyURL: root.appendingPathComponent("tunnel.log"))
    }()
    static func begin() {
        write(lines: ["\(stamp())  --- start ---"], truncate: true)
    }
    static func stamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return String(formatter.string(from: date).dropFirst(11).prefix(12))
    }
    static func note(_ message: String) { write(lines: ["\(stamp())  \(message)"], truncate: false) }
    static func core(_ lines: [String]) { write(lines: lines.map(TunnelReport.coreLine), truncate: false) }
    static func read() -> [String] { store?.read() ?? [] }
    static func clear() { store?.clear() }
    private static func write(lines: [String], truncate: Bool) { store?.write(lines: lines, truncate: truncate) }
}

final class TunnelLogStore {
    private let lock = NSLock()
    private let url: URL
    private let legacyURL: URL?
    private let limit: Int
    init(url: URL, legacyURL: URL? = nil, limit: Int = 400) { self.url = url; self.legacyURL = legacyURL; self.limit = limit }
    func read() -> [String] { lock.lock(); defer { lock.unlock() }; return readUnlocked() }
    func clear() {
        lock.lock(); defer { lock.unlock() }
        for path in [url, legacyURL].compactMap({ $0 }) { try? FileManager.default.removeItem(at: path) }
    }
    private func readUnlocked() -> [String] {
        for path in [url, legacyURL].compactMap({ $0 }) {
            if let text = try? String(contentsOf: path, encoding: .utf8) { return text.split(separator: "\n").map(String.init) }
        }
        return []
    }
    func write(lines: [String], truncate: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        var kept = truncate ? [] : readUnlocked()
        var seen = Set(kept)
        for line in lines.map(TunnelReport.redact) where seen.insert(line).inserted { kept.append(line) }
        if kept.count > limit { kept.removeFirst(kept.count - limit) }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try kept.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            // Once migrated, a purged cache must not resurrect an older attempt.
            if let legacyURL, legacyURL != url { try? FileManager.default.removeItem(at: legacyURL) }
        } catch { /* The live core report remains available if persistence fails. */ }
    }
}

/// Formatting is independent of NetworkExtension so malformed/old IPC replies
/// and redaction can be tested without changing a real machine's VPN.
enum TunnelReport {
    private static let secrets = try! NSRegularExpression(pattern:
        #"(?i)vless://[^\s]+|https?://[^\s]+/sub/[^\s]+|(?:private|public|preshared)[_ ]?key\s*[=:]\s*\S+|[A-Za-z0-9+/]{42}[A-Za-z0-9+/=]{1,2}|\b[0-9a-f]{64}\b|\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#)
    static func redact(_ text: String) -> String {
        secrets.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "<redacted>")
    }
    static func coreLine(_ line: String) -> String {
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return "\(TunnelLog.stamp())  core \(line)" }
        return "\(parts[0])  core \(parts[1])"
    }
    static func failure(_ status: [String: Any]) -> String? {
        guard let details = status["diagnostics"] as? [String: Any],
              let reason = details["failure"] as? String, !reason.isEmpty else { return nil }
        return redact(reason)
    }
    static func summary(_ status: [String: Any]) -> String {
        var safe: [String: Any] = [:]
        for key in ["up", "protocol", "variant", "since_unix", "handshake_unix", "latency_ms"] {
            if let value = status[key] { safe[key] = value }
        }
        if let details = status["diagnostics"] as? [String: Any] {
            if let counters = details["counters"] as? [String: Any] {
                let allowed = ["outbound_downlink_bytes", "last_reply_unix_ms", "last_probe_unix_ms",
                    "guard_host_read_packets", "guard_engine_write_packets", "guard_engine_read_packets",
                    "guard_host_write_packets", "guard_ipv6_filtered_packets", "guard_write_pressure_events",
                    "guard_dropped_packets", "guard_last_host_read_ms", "guard_last_engine_read_ms"]
                var numbers: [String: Any] = [:]
                for key in allowed { if let value = counters[key] as? NSNumber { numbers[key] = value } }
                safe["counters"] = numbers
            }
            if let reason = failure(status) { safe["failure"] = reason }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: safe, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "unavailable" }
        return redact(text)
    }
    static func render(saved: [String], live: String?, now: Date = Date()) -> String {
        var lines = saved
        if let data = live?.data(using: .utf8),
           let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let core = payload["lines"] as? [String] { lines.append(contentsOf: core.map(coreLine)) }
            if let status = payload["status"] as? [String: Any] {
                lines.append("\(TunnelLog.stamp(now))  state (live): \(summary(status))")
            }
        } else {
            lines.append("\(TunnelLog.stamp(now))  diagnostics: saved history; live extension unavailable")
        }
        var seen = Set<String>()
        return lines.map(redact).filter { seen.insert($0).inserted }.joined(separator: "\n")
    }
}

/// A reply and its timeout may arrive together. Flutter results must fire once.
final class TunnelReply {
    private let lock = NSLock()
    private var callback: ((String?) -> Void)?
    init(_ callback: @escaping (String?) -> Void) { self.callback = callback }
    func finish(_ value: String?) {
        lock.lock(); let done = callback; callback = nil; lock.unlock()
        done?(value)
    }
}

/// Watch only a confirmed local failure, not idle traffic or an absent reply.
/// It runs in the extension even when the app is in the background.
final class TunnelHealthMonitor {
    private let queue = DispatchQueue(label: "team.gdb.caelo.tunnel-health")
    private let key = DispatchSpecificKey<Bool>()
    private var timer: DispatchSourceTimer?
    init() { queue.setSpecific(key: key, value: true) }
    deinit { stop() }
    private func serialized(_ body: () -> Void) {
        if DispatchQueue.getSpecific(key: key) == true { body() } else { queue.sync(execute: body) }
    }
    func start(interval: DispatchTimeInterval = .seconds(2), read: @escaping () -> [String: Any]?, onFailure: @escaping (String) -> Void) {
        serialized {
            timer?.cancel()
            let next = DispatchSource.makeTimerSource(queue: queue)
            next.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(100))
            next.setEventHandler { [weak self] in
                guard let self, let status = read(), let failure = TunnelReport.failure(status) else { return }
                self.timer?.cancel(); self.timer = nil
                onFailure(failure)
            }
            timer = next; next.resume()
        }
    }
    func stop() { serialized { timer?.cancel(); timer = nil } }
}
