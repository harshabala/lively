import Testing
@testable import LivelyCore

struct ConfigChangeDiffTests {
    @Test func refreshOnlyWhenAVisibleSpaceKeyChanged() {
        let current: Set<String> = ["1:a"]
        #expect(ConfigChangeDiff.currentSpaceKeysChanged(
            from: ["1:a", "2:b"], to: ["1:a", "2:c"], currentSpaceKeys: current) == false)
        #expect(ConfigChangeDiff.currentSpaceKeysChanged(
            from: ["1:a"], to: ["1:z"], currentSpaceKeys: current) == true)
    }

    @Test func identicalKeysAreANoOp() {
        #expect(!ConfigChangeDiff.currentSpaceKeysChanged(
            from: ["1:a"], to: ["1:a"], currentSpaceKeys: ["1:a"]))
    }
}
