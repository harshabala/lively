import Testing
@testable import LivelyCore

struct AudioTrackPolicyTests {
    @Test func mutedDisablesAudioOnly() {
        #expect(!AudioTrackPolicy.isEnabled(isAudioMedia: true, muted: true))
        #expect(AudioTrackPolicy.isEnabled(isAudioMedia: false, muted: true))
    }

    @Test func unmutedLeavesAudioEnabled() {
        #expect(AudioTrackPolicy.isEnabled(isAudioMedia: true, muted: false))
        #expect(AudioTrackPolicy.isEnabled(isAudioMedia: false, muted: false))
    }
}
