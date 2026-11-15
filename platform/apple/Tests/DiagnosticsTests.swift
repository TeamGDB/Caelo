import Foundation
import XCTest
@testable import CaeloAppleDiagnostics

final class DiagnosticsTests: XCTestCase {
    func testLiveExportKeepsTheFailureWithoutStopping() throws {
        let line = "12:00:01.123  vless: packet guard stopped: descriptor closed"
        let saved = ["12:00:00.000  tunnel up", TunnelReport.coreLine(line)]
        let payload: [String: Any] = ["lines": [line], "status": ["up": false, "diagnostics": ["failure": "descriptor closed", "counters": ["guard_host_read_packets": 8, "guard_write_pressure_events": 3]]]]
        let live = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
        let result = TunnelReport.render(saved: saved, live: live)
        XCTAssertTrue(result.contains("state (live)"))
        XCTAssertTrue(result.contains("guard_write_pressure_events"))
        XCTAssertTrue(result.contains("\"failure\":\"descriptor closed\""))
        XCTAssertEqual(result.components(separatedBy: TunnelReport.coreLine(line)).count, 2)
    }
    func testMissingOrOldExtensionUsesPersistedHistory() {
        for live in [nil, "not JSON"] as [String?] {
            let result = TunnelReport.render(saved: ["12:00:00.000  error: saved failure"], live: live)
            XCTAssertTrue(result.contains("saved failure"))
            XCTAssertTrue(result.contains("live extension unavailable"))
        }
    }
    func testSecretsAndUnexpectedStatusFieldsStayOutOfExport() {
        let uuid = "12345678-1234-1234-1234-123456789abc"
        let key = String(repeating: "A", count: 43) + "="
        let input = "vless://\(uuid)@example.invalid:443 private_key=\(key) https://example.invalid/sub/private-token"
        let text = TunnelReport.render(saved: [input], live: nil)
        XCTAssertFalse(text.contains(uuid)); XCTAssertFalse(text.contains(key)); XCTAssertFalse(text.contains("private-token"))
        let summary = TunnelReport.summary(["up": true, "config": input, "endpoint": "example.invalid:443", "diagnostics": ["counters": ["secret": 1, "guard_host_read_packets": 3]]])
        XCTAssertFalse(summary.contains("example.invalid")); XCTAssertFalse(summary.contains("secret"))
        XCTAssertTrue(summary.contains("guard_host_read_packets"))
    }
    func testStoreMigratesLegacyAndSerializesWriters() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("tunnel.log")
        try "old session".write(to: legacy, atomically: true, encoding: .utf8)
        let store = TunnelLogStore(url: root.appendingPathComponent("Library/Caches/Caelo/tunnel.log"), legacyURL: legacy)
        XCTAssertEqual(store.read(), ["old session"])
        DispatchQueue.concurrentPerform(iterations: 100) { i in store.write(lines: ["line \(i)"]) }
        XCTAssertEqual(Set(store.read()).count, 101)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        store.write(lines: ["new session"], truncate: true)
        XCTAssertEqual(store.read(), ["new session"])
        store.clear(); XCTAssertEqual(store.read(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        let bounded = TunnelLogStore(url: root.appendingPathComponent("bounded.log"), limit: 3)
        bounded.write(lines: ["1", "2", "2", "3", "4"])
        XCTAssertEqual(bounded.read(), ["2", "3", "4"])
    }
    func testRacingIPCReplyCompletesExactlyOnce() {
        let lock = NSLock(); var count = 0
        let reply = TunnelReply { _ in lock.lock(); count += 1; lock.unlock() }
        DispatchQueue.concurrentPerform(iterations: 100) { i in reply.finish(i == 0 ? nil : "late reply") }
        XCTAssertEqual(count, 1)
        var result: String? = "untouched"
        let timeout = TunnelReply { result = $0 }
        timeout.finish(nil); timeout.finish("late")
        XCTAssertNil(result)
    }
    func testMonitorIgnoresPressureAndReportsPermanentFailureOnce() {
        let lock = NSLock(); var failed = false; var callbacks = 0
        let signalled = DispatchSemaphore(value: 0)
        let inspected = DispatchSemaphore(value: 0)
        let monitor = TunnelHealthMonitor()
        monitor.start(interval: .milliseconds(2), read: {
            lock.lock(); let failure = failed; lock.unlock()
            if !failure { inspected.signal() }
            return ["up": !failure, "diagnostics": ["failure": failure ? "closed descriptor" : "", "counters": ["guard_write_pressure_events": 100]]]
        }, onFailure: { reason in
            XCTAssertEqual(reason, "closed descriptor")
            callbacks += 1
            monitor.stop() // Safe from the monitor's own queue too.
            signalled.signal()
        })
        XCTAssertEqual(inspected.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(signalled.wait(timeout: .now() + .milliseconds(5)), .timedOut)
        lock.lock(); failed = true; lock.unlock()
        XCTAssertEqual(signalled.wait(timeout: .now() + 1), .success)
        monitor.stop()
        XCTAssertEqual(callbacks, 1)
        monitor.start(interval: .milliseconds(2), read: { nil }, onFailure: { _ in XCTFail("missing data is not a fatal packet failure") })
        monitor.stop()
        XCTAssertNil(TunnelReport.failure(["up": false]))
    }
}
