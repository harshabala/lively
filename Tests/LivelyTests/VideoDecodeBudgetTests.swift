import Testing
import CoreGraphics
@testable import LivelyCore

struct VideoDecodeBudgetTests {
    @Test func matchSourceCapsAt1080() {
        let size = VideoDecodeBudget.preferredMaximumResolution(maxResolution: .matchSource)
        #expect(size == CGSize(width: 1920, height: 1080))
    }

    @Test func p1080Is1080() {
        #expect(VideoDecodeBudget.preferredMaximumResolution(maxResolution: .p1080)
            == CGSize(width: 1920, height: 1080))
    }

    @Test func p4kIs2160() {
        #expect(VideoDecodeBudget.preferredMaximumResolution(maxResolution: .p4k)
            == CGSize(width: 3840, height: 2160))
    }
}
