import Testing
import Foundation
@testable import LivelyCore

struct PerfHarnessTests {
    @Test func parseMissingEnvIsOff() {
        let request = PerfHarness.Request.parse(environment: [:])
        #expect(request.mode == .off)
        #expect(request.fixtureURL == nil)
        #expect(PerfHarness.isValidRequest(request))
    }

    @Test func parseUnknownModeIsOff() {
        let request = PerfHarness.Request.parse(environment: ["LIVELY_PERF_MODE": "turbo"])
        #expect(request.mode == .off)
    }

    @Test func parseIdle() {
        let request = PerfHarness.Request.parse(environment: ["LIVELY_PERF_MODE": "idle"])
        #expect(request.mode == .idle)
        #expect(PerfHarness.isValidRequest(request))
    }

    @Test func playingRequiresSupportedFixture() {
        let missing = PerfHarness.Request.parse(environment: ["LIVELY_PERF_MODE": "playing"])
        #expect(missing.mode == .playing)
        #expect(!PerfHarness.isValidRequest(missing))

        let badExt = PerfHarness.Request.parse(environment: [
            "LIVELY_PERF_MODE": "playing",
            "LIVELY_PERF_FIXTURE": "/tmp/clip.avi"
        ])
        #expect(!PerfHarness.isValidRequest(badExt))

        let ok = PerfHarness.Request.parse(environment: [
            "LIVELY_PERF_MODE": "PAUSED",
            "LIVELY_PERF_FIXTURE": "/tmp/clip.mp4"
        ])
        #expect(ok.mode == .paused)
        #expect(ok.fixtureURL?.path == "/tmp/clip.mp4")
        #expect(PerfHarness.isValidRequest(ok))
    }
}
