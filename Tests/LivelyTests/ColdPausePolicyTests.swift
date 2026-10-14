import Testing
@testable import LivelyCore

struct ColdPausePolicyTests {
    @Test func lockSleepSaverAndUserPauseWaitTenSeconds() {
        let ten = Duration.seconds(10)
        #expect(ColdPausePolicy.grace(for: .lockSleepOrSaver) == ten)
        #expect(ColdPausePolicy.grace(for: .userPause) == ten)
        #expect(!ColdPausePolicy.shouldTearDown(elapsed: .seconds(9), grace: ten))
        #expect(ColdPausePolicy.shouldTearDown(elapsed: ten, grace: ten))
    }

    @Test func batteryAndThermalTearDownImmediately() {
        #expect(ColdPausePolicy.grace(for: .batteryOrThermal) == .seconds(0))
        #expect(ColdPausePolicy.shouldTearDown(elapsed: .seconds(0), grace: .seconds(0)))
    }
}
