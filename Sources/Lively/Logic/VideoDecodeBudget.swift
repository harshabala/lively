import CoreGraphics

/// Decode-size hint for `AVPlayerItem.preferredMaximumResolution`.
/// Match Source (`preferredMaxHeight` 0) caps at 1080p instead of native 4K/5K.
public enum VideoDecodeBudget {
    public static func preferredMaximumResolution(
        maxResolution: AppPreferences.MaxResolution
    ) -> CGSize {
        let h = maxResolution.preferredMaxHeight
        if h > 0 {
            return CGSize(width: h * 16 / 9, height: h)
        }
        return CGSize(width: 1920, height: 1080)
    }
}
