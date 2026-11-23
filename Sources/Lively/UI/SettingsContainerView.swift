import SwiftUI
import AppKit

public enum LivelyTab: Hashable {
    case displays
    case settings
}

public struct SettingsContainerView: View {
    @ObservedObject public var spaceMonitor: SpaceMonitor
    public let configStore: ConfigStore
    @EnvironmentObject var wallpaperController: WallpaperController
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject private var updateChecker = UpdateChecker.shared

    @ViewState private var selectedTab: LivelyTab = .displays
    @ViewState private var settingsSection: SettingsSection = .general
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Fixed popover size — never grows with Logs content.
    public static let windowSize = CGSize(width: 620, height: 580)

    public init(spaceMonitor: SpaceMonitor, configStore: ConfigStore) {
        self.spaceMonitor = spaceMonitor
        self.configStore = configStore
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topChrome

                statusBanners

                ZStack {
                    switch selectedTab {
                    case .displays:
                        DisplaysView(spaceMonitor: spaceMonitor, configStore: configStore)
                            .transition(LivelyBrand.contentTransition)
                    case .settings:
                        PreferencesView(
                            spaceMonitor: spaceMonitor,
                            configStore: configStore,
                            section: $settingsSection,
                            onOpenDisplays: {
                                withAnimation(reduceMotion ? nil : LivelyBrand.Motion.normal) {
                                    selectedTab = .displays
                                }
                            }
                        )
                        .transition(LivelyBrand.contentTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(reduceMotion ? nil : LivelyBrand.Motion.normal, value: selectedTab)
            }
            .disabled(!preferences.hasCompletedWelcome)
            .allowsHitTesting(preferences.hasCompletedWelcome)
            .accessibilityHidden(!preferences.hasCompletedWelcome)

            if !preferences.hasCompletedWelcome {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .accessibilityHidden(true)

                WelcomeSheet(
                    onChooseVideo: {
                        preferences.hasCompletedWelcome = true
                        preferences.hasDismissedDisplaysTip = true
                        selectedTab = .displays
                        NotificationCenter.default.post(name: .livelyRequestFirstVideoPick, object: nil)
                    },
                    onDismiss: {
                        preferences.hasCompletedWelcome = true
                    }
                )
                .transition(LivelyBrand.contentTransition)
                .zIndex(20)
            }
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        // Structural material: content scrolls under chrome hierarchy without decorative glass stacks.
        .background {
            ZStack {
                LivelyBrand.background
                GlassEffect(material: .headerView, blendingMode: .withinWindow)
                    .opacity(0.55)
            }
        }
        .preferredColorScheme(preferences.appearance.colorScheme)
        .onChange(of: preferences.appearance) { _, newValue in
            AppPreferences.applyAppAppearance(newValue)
        }
        .animation(reduceMotion ? nil : LivelyBrand.Motion.normal, value: preferences.hasCompletedWelcome)
    }

    // MARK: - Top chrome

    private var topChrome: some View {
        HStack(spacing: LivelyBrand.Spacing.md) {
            primaryTabs

            Spacer(minLength: LivelyBrand.Spacing.sm)

            HStack(spacing: LivelyBrand.Spacing.sm) {
                // Matched chrome capsules: Pause (primary) / Quit (destructive text)
                chromeActionButton(
                    title: wallpaperController.isPaused ? "Resume" : "Pause",
                    systemImage: wallpaperController.isPaused ? "play.fill" : "pause.fill",
                    tint: LivelyBrand.foreground
                ) {
                    wallpaperController.togglePause()
                }
                .help(wallpaperController.isPaused ? "Resume wallpapers" : "Pause wallpapers")
                .accessibilityLabel(wallpaperController.isPaused ? "Resume Lively" : "Pause Lively")

                chromeActionButton(
                    title: "Quit",
                    systemImage: nil,
                    tint: LivelyBrand.destructive
                ) {
                    NSApp.terminate(nil)
                }
                .help("Quit Lively")
                .accessibilityLabel("Quit Lively")
            }
        }
        .padding(.horizontal, LivelyBrand.Spacing.lg)
        .padding(.top, LivelyBrand.Spacing.lg)
        .padding(.bottom, LivelyBrand.Spacing.md)
    }

    private var primaryTabs: some View {
        HStack(spacing: LivelyBrand.Spacing.xs) {
            primaryTabButton(title: "Displays", systemImage: "display", tab: .displays)
            primaryTabButton(title: "Settings", systemImage: "gearshape", tab: .settings)
        }
    }

    private func primaryTabButton(title: String, systemImage: String, tab: LivelyTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(reduceMotion ? nil : LivelyBrand.Motion.normal) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: LivelyBrand.Spacing.xxs) {
                HStack(spacing: LivelyBrand.Spacing.xxs) {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    Text(title)
                        .font(LivelyBrand.Typography.nav)
                }
                .foregroundStyle(isSelected ? LivelyBrand.foreground : LivelyBrand.mutedForeground)
                .padding(.horizontal, LivelyBrand.Spacing.md)
                .padding(.vertical, LivelyBrand.Spacing.sm)
                .frame(minHeight: LivelyBrand.Spacing.controlMin)

                Rectangle()
                    .fill(isSelected ? LivelyBrand.primary : Color.clear)
                    .frame(height: 2)
                    .padding(.horizontal, LivelyBrand.Spacing.sm)
            }
            .contentShape(Rectangle())
        }
        // Brand ring instead of the system blue rect on segmented chrome.
        .buttonStyle(PressScaleButtonStyle())
        .livelyFocusRing(cornerRadius: LivelyBrand.Radius.sm)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func chromeActionButton(
        title: String,
        systemImage: String?,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: LivelyBrand.Spacing.xxs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(LivelyBrand.Typography.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, LivelyBrand.Spacing.md)
            .frame(minHeight: LivelyBrand.Spacing.controlMin)
            .background(
                Capsule()
                    .fill(LivelyBrand.controlFill)
            )
            .overlay(
                Capsule()
                    .strokeBorder(LivelyBrand.border.opacity(0.45), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleButtonStyle())
        .livelyFocusRing(cornerRadius: LivelyBrand.Spacing.controlMin / 2)
    }

    // MARK: - Status banners

    private enum StatusBannerKind: Equatable, Hashable {
        case update(String)
        case thermal
        case battery
        case manualPause
    }

    private var activeBannerKinds: [StatusBannerKind] {
        var kinds: [StatusBannerKind] = []
        if let version = updateChecker.availableVersion {
            kinds.append(.update(version))
        }
        if wallpaperController.isThrottled {
            kinds.append(.thermal)
        } else if wallpaperController.isBatteryPaused {
            kinds.append(.battery)
        } else if wallpaperController.isPaused {
            kinds.append(.manualPause)
        }
        return kinds
    }

    @ViewBuilder
    private var statusBanners: some View {
        VStack(spacing: 0) {
            ForEach(activeBannerKinds, id: \.self) { kind in
                bannerView(for: kind)
                    .transition(LivelyBrand.contentTransition)
            }
        }
        .animation(reduceMotion ? nil : LivelyBrand.Motion.fast, value: activeBannerKinds)
    }

    @ViewBuilder
    private func bannerView(for kind: StatusBannerKind) -> some View {
        switch kind {
        case .update(let version):
            updateBanner(version: version)
        case .thermal:
            statusBanner(
                icon: "thermometer.medium",
                text: WallpaperController.thermalPauseNotice,
                color: Color(nsColor: .systemOrange)
            )
        case .battery:
            statusBanner(
                icon: wallpaperController.isForcedBatteryPause ? "battery.0percent" : "battery.25",
                text: batteryBannerText,
                color: wallpaperController.isForcedBatteryPause
                    ? Color(nsColor: .systemOrange)
                    : LivelyBrand.mutedForeground
            )
        case .manualPause:
            statusBanner(
                icon: "pause.circle.fill",
                text: "Wallpapers paused. Press Resume to play again.",
                color: LivelyBrand.mutedForeground
            )
        }
    }

    private var batteryBannerText: String {
        let pct = wallpaperController.batteryLevelPercent.map { "\(Int($0.rounded()))%" } ?? "unknown"
        if wallpaperController.isForcedBatteryPause {
            return "Battery \(pct). Wallpapers paused (required at \(Int(AppPreferences.forcedBatteryPausePercent))% or below)."
        }
        let threshold = Int(preferences.batteryPauseThreshold.rounded())
        return "Battery \(pct). Wallpapers paused (threshold \(threshold)%). Plug in to resume."
    }

    private func updateBanner(version: String) -> some View {
        HStack(spacing: LivelyBrand.Spacing.sm) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(LivelyBrand.primary)
            Text("Update available: v\(version)")
                .font(LivelyBrand.Typography.caption.weight(.semibold))
                .foregroundStyle(LivelyBrand.foreground)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("View") {
                updateChecker.openReleasePage()
            }
            .buttonStyle(.plain)
            .font(LivelyBrand.Typography.caption.weight(.semibold))
            .foregroundStyle(LivelyBrand.primary)
            .livelyFocusRing(cornerRadius: LivelyBrand.Radius.sm)
            .accessibilityLabel("View update on GitHub")
        }
        .padding(.vertical, LivelyBrand.Spacing.sm)
        .padding(.horizontal, LivelyBrand.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: LivelyBrand.Spacing.controlMin + LivelyBrand.Spacing.xs, alignment: .leading)
        .background(LivelyBrand.primary.opacity(0.12))
    }

    private func statusBanner(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: LivelyBrand.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(LivelyBrand.Typography.caption)
                .foregroundStyle(LivelyBrand.foreground)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(text)
        }
        .padding(.vertical, LivelyBrand.Spacing.sm)
        .padding(.horizontal, LivelyBrand.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: LivelyBrand.Spacing.controlMin + LivelyBrand.Spacing.xs, alignment: .leading)
        .background(color.opacity(0.10))
    }
}
