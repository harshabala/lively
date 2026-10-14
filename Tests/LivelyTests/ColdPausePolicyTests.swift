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

    @Test func cancelledOrResumedWorkMustNotTearDown() {
        #expect(!ColdPausePolicy.shouldCommitTearDown(isCancelled: true, wantsPlayback: false, isSamePlayer: true))
        #expect(!ColdPausePolicy.shouldCommitTearDown(isCancelled: false, wantsPlayback: true, isSamePlayer: true))
        #expect(!ColdPausePolicy.shouldCommitTearDown(isCancelled: false, wantsPlayback: false, isSamePlayer: false))
        #expect(ColdPausePolicy.shouldCommitTearDown(isCancelled: false, wantsPlayback: false, isSamePlayer: true))
    }

    @Test func alreadyScheduledGraceIsNotRestarted() {
        #expect(!ColdPausePolicy.shouldScheduleTearDown(alreadyScheduled: true, playerExists: true))
        #expect(!ColdPausePolicy.shouldScheduleTearDown(alreadyScheduled: false, playerExists: false))
        #expect(ColdPausePolicy.shouldScheduleTearDown(alreadyScheduled: false, playerExists: true))
    }
}
