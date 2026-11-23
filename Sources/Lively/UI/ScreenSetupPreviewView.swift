import SwiftUI
import AppKit

/// Scaled live map of connected displays with wallpaper thumbnail previews.
struct ScreenSetupPreviewView: View {
    @ObservedObject var spaceMonitor: SpaceMonitor
    @ObservedObject var configStore: ConfigStore
    var onManageDisplay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LivelyBrand.Spacing.md) {
            if spaceMonitor.screenSpaces.isEmpty {
                emptyState
            } else {
                displayMap
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .padding(LivelyBrand.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: LivelyBrand.Radius.lg)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: LivelyBrand.Radius.lg)
                            .strokeBorder(LivelyBrand.border.opacity(0.5), lineWidth: 1)
                    )

                Button(action: onManageDisplay) {
                    HStack {
                        Text("Open Displays to assign wallpapers")
                            .font(LivelyBrand.Typography.caption.weight(.semibold))
                            .foregroundStyle(LivelyBrand.onPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(LivelyBrand.onPrimary)
                    }
                    .padding(.horizontal, LivelyBrand.Spacing.lg)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: LivelyBrand.Radius.md)
                            .fill(LivelyBrand.primary)
                    )
                }
                .buttonStyle(PressScaleButtonStyle())
                .livelyFocusRing(cornerRadius: LivelyBrand.Radius.md)
                .accessibilityLabel("Open Displays to assign wallpapers")
                .accessibilityHint("Switches to the Displays tab")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: LivelyBrand.Spacing.sm) {
            Image(systemName: "display.2")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(LivelyBrand.mutedForeground)
            Text("No displays detected")
                .font(LivelyBrand.Typography.body.weight(.semibold))
            Text("Connect a monitor or enable Screen Recording for Lively.")
                .font(LivelyBrand.Typography.caption)
                .foregroundStyle(LivelyBrand.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(LivelyBrand.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.lg)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var displayMap: some View {
        GeometryReader { geo in
            let layout = DisplayLayoutCalculator.layout(
                spaces: spaceMonitor.screenSpaces,
                in: geo.size,
                padding: 12
            )
            ZStack(alignment: .topLeading) {
                ForEach(layout) { item in
                    DisplayPreviewCard(
                        space: item.space,
                        configStore: configStore,
                        frame: item.frame
                    )
                    .frame(width: item.frame.width, height: item.frame.height)
                    .position(
                        x: item.frame.midX,
                        y: item.frame.midY
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Layout math

struct DisplayLayoutItem: Identifiable {
    var id: String { space.id }
    let space: ScreenSpace
    let frame: CGRect
}

@MainActor
enum DisplayLayoutCalculator {
    static func layout(spaces: [ScreenSpace], in size: CGSize, padding: CGFloat) -> [DisplayLayoutItem] {
        guard !spaces.isEmpty else { return [] }

        let frames = spaces.map { $0.screen.frame }
        let union = frames.reduce(CGRect.null) { $0.union($1) }
        guard union.width > 0, union.height > 0 else { return [] }

        let available = CGSize(
            width: max(size.width - padding * 2, 1),
            height: max(size.height - padding * 2, 1)
        )
        let scale = min(available.width / union.width, available.height / union.height)

        let scaledUnion = CGSize(width: union.width * scale, height: union.height * scale)
        let originX = padding + (available.width - scaledUnion.width) / 2
        // Flip Y: AppKit bottom-left origin → SwiftUI top-left
        let originY = padding + (available.height - scaledUnion.height) / 2

        return spaces.map { space in
            let f = space.screen.frame
            let x = originX + (f.minX - union.minX) * scale
            let y = originY + (union.maxY - f.maxY) * scale
            let w = max(f.width * scale, 48)
            let h = max(f.height * scale, 32)
            return DisplayLayoutItem(space: space, frame: CGRect(x: x, y: y, width: w, height: h))
        }
    }
}

// MARK: - Per-display card

private struct DisplayPreviewCard: View {
    let space: ScreenSpace
    let configStore: ConfigStore
    let frame: CGRect

    private var wallpaperURL: URL? {
        let appearance = NSApp?.effectiveAppearance
        return configStore.resolvedURL(for: space.spaceKey, appearance: appearance)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let url = wallpaperURL {
                    VideoThumbnailView(
                        url: url,
                        height: frame.height,
                        cornerRadius: LivelyBrand.Radius.sm,
                        showLabels: frame.height > 64
                    )
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: LivelyBrand.Radius.sm)
                            .fill(LivelyBrand.controlFill)
                        VStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.system(size: 14, weight: .light))
                                .foregroundStyle(LivelyBrand.mutedForeground)
                            if frame.height > 56 {
                                Text("No wallpaper")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(LivelyBrand.mutedForeground)
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: LivelyBrand.Radius.sm))

            Text(space.displayName)
                .font(LivelyBrand.Typography.badge)
                .foregroundStyle(.white)
                .padding(.horizontal, LivelyBrand.Spacing.xs)
                .padding(.vertical, 2)
                .background(Color(nsColor: .labelColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 3))
                .padding(LivelyBrand.Spacing.xs)
        }
        .overlay(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.sm)
                .strokeBorder(LivelyBrand.border.opacity(0.6), lineWidth: 1)
        )
        .shadow(
            color: LivelyBrand.Shadow.color,
            radius: 3,
            x: LivelyBrand.Shadow.x,
            y: 1
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(space.displayName), \(wallpaperURL == nil ? "no wallpaper assigned" : "wallpaper assigned")")
    }
}

