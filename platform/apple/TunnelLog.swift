import Foundation

/// Where the extension writes down what it did.
///
/// A ring in memory is no use here. When the tunnel fails to start, the system
/// stops this process within a few hundred milliseconds, and anything held in
/// memory goes with it — including, in every attempt so far, the reason. The
/// app then asks a process that no longer exists and is told nothing.
///
/// A file in the shared container outlives the process, which is the whole
/// reason the app group exists.
enum TunnelLog {

    private static let group = "group.team.gdb.caelo"
    private static let name = "tunnel.log"

    /// Kept small and rewritten per attempt: the interesting run is the last
    /// one, and an accumulating file would eventually be all of them.
    private static let limit = 200

    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent(name)
    }

    static func begin() {
        write(lines: [], truncate: true)
        note("--- start ---")
    }

    static func note(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date()).suffix(9).prefix(8)
        write(lines: ["\(stamp)  \(message)"], truncate: false)
    }

    /// Reads back everything recorded. Used by the app, through the channel.
    static func read() -> [String] {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    private static func write(lines: [String], truncate: Bool) {
        guard let url else { return }

        var kept = truncate ? [] : read()
        kept.append(contentsOf: lines)
        if kept.count > limit { kept.removeFirst(kept.count - limit) }

        try? kept.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
