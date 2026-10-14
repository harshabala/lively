import Foundation

/// Whether an `AVPlayerItemTrack` should stay enabled.
/// Muted wallpapers still built an AudioToolbox graph in P1 (13.7% CPU).
public enum AudioTrackPolicy {
    public static func isEnabled(isAudioMedia: Bool, muted: Bool) -> Bool {
        if isAudioMedia && muted { return false }
        return true
    }
}
