import SwiftUI
import AppKit

// MARK: - DisplaysView

public struct DisplaysView: View {
    @ObservedObject public var spaceMonitor: SpaceMonitor
    public let configStore: ConfigStore
    @ObservedObject private var preferences = AppPreferences.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var displayedDays: Int = 0

    public init(spaceMonitor: SpaceMonitor, configStore: ConfigStore) {
        self.spaceMonitor = spaceMonitor
        self.configStore = configStore
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LivelyBrand.Spacing.xl) {
                if !preferences.hasDismissedDisplaysTip {
                    displaysTipStrip
                }

                screensSection

                Divider()
                    .overlay(LivelyBrand.border.opacity(0.45))

                metricsFooter
            }
            .padding(.horizontal, LivelyBrand.Spacing.xl)
            .padding(.vertical, LivelyBrand.Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(LivelyBrand.foreground)
    }

    // MARK: - First-run tip

    private var displaysTipStrip: some View {
        HStack(alignment: .top, spacing: LivelyBrand.Spacing.sm) {
            Image(systemName: "lightbulb.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(LivelyBrand.primary)
                .padding(.top, 2)

            Text("Drop a video on a display card, or click the zone to browse. H.264 / HEVC only.")
                .font(LivelyBrand.Typography.caption)
                .foregroundStyle(LivelyBrand.foreground)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: LivelyBrand.Spacing.xs)

            Button {
                preferences.hasDismissedDisplaysTip = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(LivelyBrand.mutedForeground)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle())
            .livelyFocusRing(cornerRadius: 6)
            .accessibilityLabel("Dismiss tip")
        }
        .padding(LivelyBrand.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.md)
                .fill(LivelyBrand.primary.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.md)
                .strokeBorder(LivelyBrand.primary.opacity(0.22), lineWidth: 1)
        )
    }

    private var screensSection: some View {
        // No redundant "Displays" subheading — the primary tab already names this surface.
        VStack(alignment: .leading, spacing: LivelyBrand.Spacing.md) {
            if spaceMonitor.isRefreshing && spaceMonitor.screenSpaces.isEmpty {
                detectingView
                    .transition(LivelyBrand.contentTransition)
            } else if spaceMonitor.screenSpaces.isEmpty {
                emptyDisplaysView
                    .transition(LivelyBrand.contentTransition)
            } else {
                VStack(spacing: LivelyBrand.Spacing.md) {
                    ForEach(Array(spaceMonitor.screenSpaces.enumerated()), id: \.element.id) { index, space in
                        ScreenCardView(
                            space: space,
                            configStore: configStore,
                            spaceMonitor: spaceMonitor,
                            displayIndex: index + 1,
                            isPrimaryDisplay: index == 0
                        )
                        .transition(LivelyBrand.contentTransition)
                        .animation(
                            reduceMotion ? nil : LivelyBrand.Motion.normal.delay(Double(min(index, 2)) * 0.04),
                            value: spaceMonitor.screenSpaces.count
                        )
                    }

                    libraryButton
                }
                .transition(LivelyBrand.contentTransition)
            }
        }
        .animation(reduceMotion ? nil : LivelyBrand.Motion.normal, value: spaceMonitor.screenSpaces.isEmpty)
        .animation(reduceMotion ? nil : LivelyBrand.Motion.normal, value: spaceMonitor.isRefreshing)
    }

    private var emptyDisplaysView: some View {
        VStack(alignment: .leading, spacing: LivelyBrand.Spacing.md) {
            Text("No displays detected")
                .font(LivelyBrand.Typography.body.weight(.semibold))
                .foregroundStyle(LivelyBrand.foreground)
            Text("Connect a monitor or enable Screen Recording for Lively so Spaces and displays can be detected.")
                .font(LivelyBrand.Typography.caption)
                .foregroundStyle(LivelyBrand.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            openScreenRecordingSettingsButton
        }
        .padding(LivelyBrand.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.lg)
                .fill(LivelyBrand.card.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.lg)
                .strokeBorder(LivelyBrand.border.opacity(0.42))
        )
        .accessibilityElement(children: .contain)
    }

    private var detectingView: some View {
        VStack(alignment: .leading, spacing: LivelyBrand.Spacing.md) {
            HStack(spacing: LivelyBrand.Spacing.md) {
                BreathingDotsView()
                Text("Detecting displays...")
                    .font(LivelyBrand.Typography.body)
                    .foregroundStyle(LivelyBrand.mutedForeground)
            }
            Text("If this takes more than a few seconds, grant Screen Recording to Lively in System Settings.")
                .font(LivelyBrand.Typography.footnote)
                .foregroundStyle(LivelyBrand.mutedForeground)
            openScreenRecordingSettingsButton
        }
        .padding(LivelyBrand.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.lg)
                .fill(LivelyBrand.card.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.lg)
                .strokeBorder(LivelyBrand.border.opacity(0.42))
        )
    }

    private var openScreenRecordingSettingsButton: some View {
        Button {
            openScreenRecordingPrivacySettings()
        } label: {
            Text("Open Screen Recording Settings")
                .font(LivelyBrand.Typography.caption.weight(.semibold))
                .foregroundStyle(LivelyBrand.primary)
                .padding(.horizontal, LivelyBrand.Spacing.md)
                .frame(minHeight: LivelyBrand.Spacing.controlMin)
                .background(
                    RoundedRectangle(cornerRadius: LivelyBrand.Radius.sm)
                        .fill(LivelyBrand.primary.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LivelyBrand.Radius.sm)
                        .strokeBorder(LivelyBrand.primary.opacity(0.28), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: LivelyBrand.Radius.sm))
        }
        .buttonStyle(PressScaleButtonStyle())
        .livelyFocusRing(cornerRadius: LivelyBrand.Radius.sm)
        .accessibilityHint("Opens System Settings to the Screen Recording privacy pane")
    }

    private func openScreenRecordingPrivacySettings() {
        // macOS Privacy & Security → Screen Recording
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Security.prefPane"))
        }
    }

    private var libraryButton: some View {
        Button {
            LibraryWindowController.shared.openLibraryWindow(spaceMonitor: spaceMonitor, configStore: configStore)
        } label: {
            HStack(spacing: LivelyBrand.Spacing.md) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(LivelyBrand.Typography.iconSmall)
                    .foregroundStyle(LivelyBrand.mutedForeground)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: LivelyBrand.Spacing.tiny) {
                    Text("Wallpaper Library")
                        .font(LivelyBrand.Typography.section)
                        .foregroundStyle(LivelyBrand.foreground)
                    Text("Save videos once and reuse them on any display.")
                        .font(LivelyBrand.Typography.footnote)
                        .foregroundStyle(LivelyBrand.mutedForeground)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(LivelyBrand.Typography.caption.weight(.semibold))
                    .foregroundStyle(LivelyBrand.mutedForeground)
            }
            .padding(LivelyBrand.Spacing.md)
            .frame(minHeight: LivelyBrand.Spacing.controlMin + LivelyBrand.Spacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .livelyFocusRing(cornerRadius: LivelyBrand.Radius.md)
        .background(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.md)
                .fill(LivelyBrand.card.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.md)
                .strokeBorder(LivelyBrand.border.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Open Wallpaper Library")
        .accessibilityHint("Open your reusable wallpaper library to add or apply videos.")
    }

    @ViewBuilder
    private var metricsFooter: some View {
        let target = AppMetrics.shared.daysWithWallpaperActive
        if target > 0 {
            VStack(spacing: LivelyBrand.Spacing.tiny) {
                HStack(spacing: LivelyBrand.Spacing.xs) {
                    Text("Active")
                        .font(LivelyBrand.Typography.caption)
                        .foregroundStyle(LivelyBrand.mutedForeground)
                    Text("\(displayedDays)")
                        .font(LivelyBrand.Typography.caption.weight(.semibold))
                        .foregroundStyle(LivelyBrand.primary)
                        .contentTransition(.numericText(value: Double(displayedDays)))
                        .monospacedDigit()
                    Text("days.")
                        .font(LivelyBrand.Typography.caption)
                        .foregroundStyle(LivelyBrand.mutedForeground)
                }
                Text("Counts days Lively was actively rendering.")
                    .font(LivelyBrand.Typography.footnote)
                    .foregroundStyle(LivelyBrand.mutedForeground.opacity(0.7))
                    .multilineTextAlignment(.center)
                Text("Stored only on this device. Never uploaded.")
                    .font(LivelyBrand.Typography.footnote)
                    .foregroundStyle(LivelyBrand.mutedForeground.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Active \(target) days. Counts days Lively was actively rendering. Stored only on this device. Never uploaded.")
            .task {
                guard !reduceMotion else {
                    displayedDays = target
                    return
                }
                let steps = min(target, 20)
                let stepSize = max(1, target / steps)
                for i in 0...steps {
                    do {
                        try await Task.sleep(for: .milliseconds(40))
                        withAnimation(reduceMotion ? nil : LivelyBrand.Motion.fast) {
                            displayedDays = (i == steps) ? target : min(i * stepSize, target)
                        }
                    } catch {
                        break
                    }
                }
            }
        }
    }
}
