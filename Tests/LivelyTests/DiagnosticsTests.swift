import Testing
import Foundation
@testable import LivelyCore

struct DiagnosticsTests {

    @Test func redactorRemovesHomeAndOtherUserPaths() {
        let text = "Opened /Users/alice/Movies/a.mp4 and /Users/bob/x.mov"
        let out = DiagnosticsRedactor.redact(text, homeDirectory: "/Users/alice")
        #expect(!out.contains("alice"))
        #expect(!out.contains("bob"))
        #expect(out.contains("~/Movies/a.mp4"))
    }

    @Test func redactorLeavesPlainTextAlone() {
        #expect(DiagnosticsRedactor.redact("Loaded 3 assignment(s)", homeDirectory: "/Users/alice") == "Loaded 3 assignment(s)")
    }

    @Test func reportContainsSummaryAndRedactsLog() {
        let snapshot = DiagnosticsReport.Snapshot(
            appVersion: "1.2.0", build: "120", osVersion: "macOS 14",
            displayCount: 2, assignmentCount: 3, isPaused: false,
            preferences: ["b": "2", "a": "1"],
            previousRunEndedUncleanly: true,
            logLines: ["failed /Users/alice/Movies/secret.mp4"]
        )
        let report = DiagnosticsReport.render(snapshot, homeDirectory: "/Users/alice")
        #expect(report.contains("App version: 1.2.0 (120)"))
        #expect(report.contains("Displays: 2"))
        #expect(report.contains("Previous run ended unexpectedly: yes"))
        #expect(!report.contains("alice"))
        // Preferences are listed in a stable, sorted order.
        let a = report.range(of: "a = 1")!.lowerBound
        let b = report.range(of: "b = 2")!.lowerBound
        #expect(a < b)
    }

    @Test func reportKeepsOnlyTheLastLines() {
        let lines = (0..<500).map { "line \($0)" }
        let snapshot = DiagnosticsReport.Snapshot(
            appVersion: "1", build: "1", osVersion: "x", displayCount: 1,
            assignmentCount: 0, isPaused: false, preferences: [:],
            previousRunEndedUncleanly: false, logLines: lines
        )
        let report = DiagnosticsReport.render(snapshot)
        #expect(report.contains("line 499"))
        #expect(!report.contains("line 299\n"))
        #expect(report.contains("line 300"))
    }

    @Test func runMarkerDetectsUncleanExit() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lively-marker-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let marker = RunMarker(url: dir.appendingPathComponent("running.marker"))

        #expect(marker.begin() == false)   // first ever launch
        #expect(marker.begin() == true)    // previous run never called end()
        marker.end()
        #expect(marker.begin() == false)   // clean shutdown last time
        marker.end()
    }
}
