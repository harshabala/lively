import SwiftUI
import AppKit

/// First-launch welcome coaching the core path: choose a video wallpaper.
struct WelcomeSheet: View {
    var onChooseVideo: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LivelyBrand.Spacing.lg) {
            HStack(spacing: LivelyBrand.Spacing.md) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "play.tv.fill")
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(LivelyBrand.primary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Lively")
                        .font(LivelyBrand.Typography.title)
                    Text("Video wallpapers for every display on your Mac.")
                        .font(LivelyBrand.Typography.caption)
                        .foregroundStyle(LivelyBrand.mutedForeground)
                }
            }

            VStack(alignment: .leading, spacing: LivelyBrand.Spacing.sm) {
                bullet(icon: "film", text: "Drop an MP4, MOV, or M4V (H.264 / HEVC) onto a display card.")
                bullet(icon: "display.2", text: "Each monitor gets its own wallpaper. Switch Spaces for more.")
                bullet(icon: "menubar.rectangle", text: "Find Lively in the menu bar — it stays out of the Dock.")
            }

            HStack(spacing: LivelyBrand.Spacing.sm) {
                Button("Not now") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(PressScaleButtonStyle())
                .livelyFocusRing()
                .font(LivelyBrand.Typography.caption.weight(.medium))
                .foregroundStyle(LivelyBrand.mutedForeground)
                .padding(.horizontal, LivelyBrand.Spacing.md)
                .frame(minHeight: LivelyBrand.Spacing.controlMin)

                Spacer(minLength: 0)

                Button {
                    onChooseVideo()
                } label: {
                    Text("Choose a Video…")
                        .font(LivelyBrand.Typography.caption.weight(.semibold))
                        .foregroundStyle(LivelyBrand.onPrimary)
                        .padding(.horizontal, LivelyBrand.Spacing.lg)
                        .frame(minHeight: LivelyBrand.Spacing.controlMin)
                        .background(RoundedRectangle(cornerRadius: LivelyBrand.Radius.sm).fill(LivelyBrand.primary))
                        .contentShape(RoundedRectangle(cornerRadius: LivelyBrand.Radius.sm))
                }
                .buttonStyle(PressScaleButtonStyle())
                .livelyFocusRing(cornerRadius: LivelyBrand.Radius.sm)
                .accessibilityLabel("Choose a video wallpaper")
            }
        }
        .padding(LivelyBrand.Spacing.xl)
        .frame(maxWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.lg)
                .fill(LivelyBrand.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.lg)
                .strokeBorder(LivelyBrand.border.opacity(0.45))
        )
        .shadow(color: LivelyBrand.Shadow.color, radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onDismiss)
        .onExitCommand(perform: onDismiss)
    }

    private func bullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: LivelyBrand.Spacing.sm) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(LivelyBrand.primary)
                .frame(width: 18)
            Text(text)
                .font(LivelyBrand.Typography.caption)
                .foregroundStyle(LivelyBrand.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
