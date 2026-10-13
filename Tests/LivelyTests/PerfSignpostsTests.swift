import Testing
@testable import LivelyCore

struct PerfSignpostsTests {
    @Test func intervalRunsBodyAndReturnsValue() {
        var ran = false
        let value = PerfSignposts.interval("test") {
            ran = true
            return 42
        }
        #expect(ran)
        #expect(value == 42)
    }

    @Test func intervalRethrows() {
        enum Probe: Error { case boom }
        var caught = false
        do {
            try PerfSignposts.interval("test") {
                throw Probe.boom
            }
        } catch is Probe {
            caught = true
        } catch {
            Issue.record("unexpected error \(error)")
        }
        #expect(caught)
    }

    @Test func subsystemAndCategoryMatchBundle() {
        #expect(PerfSignposts.subsystem == "com.lively.app")
        #expect(PerfSignposts.category == "Performance")
    }
}
