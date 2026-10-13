import Testing
import Foundation
@testable import LivelyCore

struct AppSupportPathsTests {
    @Test func overrideBeatsUserDomain() {
        let dir = AppSupportPaths.applicationSupportDirectory(
            environment: ["LIVELY_APPLICATION_SUPPORT": "/tmp/lively-perf-support"]
        )
        #expect(dir.path == "/tmp/lively-perf-support")
        let lively = AppSupportPaths.livelyDirectory(
            environment: ["LIVELY_APPLICATION_SUPPORT": "/tmp/lively-perf-support"]
        )
        #expect(lively.path == "/tmp/lively-perf-support/Lively")
    }

    @Test func emptyOverrideFallsBack() {
        let dir = AppSupportPaths.applicationSupportDirectory(environment: ["LIVELY_APPLICATION_SUPPORT": "  "])
        #expect(!dir.path.contains("lively-perf-support"))
        #expect(dir.path.contains("Application Support"))
    }

    @Test func perfDefaultsUseIsolatedSuite() {
        let defaults = AppSupportPaths.perfUserDefaults(environment: ["LIVELY_PERF_MODE": "idle"])
        #expect(defaults !== UserDefaults.standard)
        let off = AppSupportPaths.perfUserDefaults(environment: [:])
        #expect(off === UserDefaults.standard)
    }
}
