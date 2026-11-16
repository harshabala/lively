import Testing
@testable import LivelyCore

struct ColdPausePolicyTests {
    private func reason(
        paused: Bool = false, throttled: Bool = false, battery: Bool = false,
        lowPower: Bool = false, system: Bool = false
    ) -> PlaybackHaltReason? {
        PlaybackHaltPolicy.reason(
            isPaused: paused, isThrottled: throttled, isBatteryPaused: battery,
            isLowPowerMode: lowPower, isSystemSuspended: system
        )
    }

    @Test func playsWhenNothingHalts() {
        #expect(reason() == nil)
    }

    @Test func eachInputHalts() {
        #expect(reason(paused: true) == .userPause)
        #expect(reason(throttled: true) == .thermal)
        #expect(reason(battery: true) == .battery)
        #expect(reason(lowPower: true) == .lowPowerMode)
        #expect(reason(system: true) == .system)
    }

    @Test func systemReasonWinsOverOthers() {
        #expect(reason(paused: true, battery: true, lowPower: true, system: true) == .system)
        #expect(reason(paused: true, lowPower: true) == .userPause)
    }

    @Test func everyReasonHasAGracePeriodUnderTheOcclusionGrace() {
        for r in PlaybackHaltReason.allCases {
            #expect(ColdPausePolicy.grace(for: r) > .zero)
            #expect(ColdPausePolicy.grace(for: r) <= ColdPausePolicy.occlusionGrace)
        }
    }

    @Test func releasesOnlyWhenIdleWithAPosterFrame() {
        #expect(ColdPausePolicy.shouldRelease(shouldDecode: false, playerExists: true, hasPosterFrame: true))
        #expect(!ColdPausePolicy.shouldRelease(shouldDecode: true, playerExists: true, hasPosterFrame: true))
        #expect(!ColdPausePolicy.shouldRelease(shouldDecode: false, playerExists: false, hasPosterFrame: true))
        #expect(!ColdPausePolicy.shouldRelease(shouldDecode: false, playerExists: true, hasPosterFrame: false))
    }

    @Test func rebuildsOnlyWhenDecodingAgainWithoutAPlayer() {
        #expect(ColdPausePolicy.shouldRebuild(shouldDecode: true, playerExists: false))
        #expect(!ColdPausePolicy.shouldRebuild(shouldDecode: false, playerExists: false))
        #expect(!ColdPausePolicy.shouldRebuild(shouldDecode: true, playerExists: true))
    }

    @Test func coveredOrHaltedNeverDecodes() {
        #expect(!WallpaperPlaybackPolicy.shouldDecode(wantsPlayback: true, isOccluded: true))
        #expect(!WallpaperPlaybackPolicy.shouldDecode(wantsPlayback: false, isOccluded: false))
        #expect(WallpaperPlaybackPolicy.shouldDecode(wantsPlayback: true, isOccluded: false))
    }
}
