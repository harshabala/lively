import Foundation

/// Whether a config-key edit should refresh the visible Space snapshot.
/// Inactive-Space assignments persist; they must not rebuild `screenSpaces`.
public enum ConfigChangeDiff {
    public static func currentSpaceKeysChanged(
        from: Set<String>,
        to: Set<String>,
        currentSpaceKeys: Set<String>
    ) -> Bool {
        !from.symmetricDifference(to).isDisjoint(with: currentSpaceKeys)
    }
}
