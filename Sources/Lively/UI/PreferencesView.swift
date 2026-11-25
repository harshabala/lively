import SwiftUI
import ServiceManagement
import AppKit

// MARK: - Settings section

public enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case playback
    case screenSetup
    case logs
    case about

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .playback: return "Playback"
        case .screenSetup: return "Screen Setup"
        case .logs: return "Logs"
        case .about: return "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Configure how Lively behaves on your Mac."
        case .playback: return "Balance visual quality against CPU and battery usage."
        case .screenSetup: return "Assign and preview wallpapers across your displays."
        case .logs: return "View and export application logs."
        case .about: return "Version info and project links."
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .playback: return "play.circle"
        case .screenSetup: return "rectangle.3.group"
        case .logs: return "doc.text"
        case .about: return "info.circle"
        }
    }
}

// MARK: - PreferencesView

public struct PreferencesView: View {
    @ObservedObject public var spaceMonitor: SpaceMonitor
    public let configStore: ConfigStore
    @Binding var section: SettingsSection
    var onOpenDisplays: () -> Void

    @ObservedObject private var preferences = AppPreferences.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewState private var showResetConfirm = false
    @ViewState private var configErrorMessage: String?
    @ViewState private var launchAtLoginError: String?

    public init(
        spaceMonitor: SpaceMonitor,
        configStore: ConfigStore,
        section: Binding<SettingsSection>,
        onOpenDisplays: @escaping () -> Void
    ) {
        self.spaceMonitor = spaceMonitor
        self.configStore = configStore
        self._section = section
        self.onOpenDisplays = onOpenDisplays
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 152)

            Divider()
                .background(LivelyBrand.border)

            contentPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(LivelyBrand.foreground)
        .onReceive(configStore.errors) { error in
            configErrorMessage = message(for: error)
            if let configErrorMessage {
                AccessibilityNotification.Announcement(configErrorMessage).post()
            }
        }
        .onChange(of: launchAtLoginError) { _, newValue in
            if let newValue {
                AccessibilityNotification.Announcement(newValue).post()
            }
        }
    }

    // MARK: - Sidebar (filled-pill selection language)

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSection.allCases) { item in
                sidebarRow(item)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, LivelyBrand.Spacing.md)
        .padding(.horizontal, LivelyBrand.Spacing.sm)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private func sidebarRow(_ item: SettingsSection) -> some View {
        let isSelected = section == item
        return Button {
            withAnimation(reduceMotion ? nil : LivelyBrand.Motion.fast) {
                section = item
            }
        } label: {
            HStack(spacing: LivelyBrand.Spacing.sm) {
                Image(systemName: item.systemImage)
                    .font(.callout.weight(.semibold))
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? LivelyBrand.primary : LivelyBrand.mutedForeground)

                Text(item.title)
                    .font(LivelyBrand.Typography.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? LivelyBrand.primary : LivelyBrand.mutedForeground)

                Spacer(minLength: 0)
            }
            .padding(.vertical, LivelyBrand.Spacing.sm)
            .padding(.horizontal, LivelyBrand.Spacing.md)
            .frame(minHeight: LivelyBrand.Spacing.controlMin)
            // Active: filled rounded rect only (no left accent bar).
            .background(
                RoundedRectangle(cornerRadius: LivelyBrand.Radius.navItem)
                    .fill(isSelected ? LivelyBrand.selectionFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Content pane (fixed height region)

    @ViewBuilder
    private var contentPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let configErrorMessage {
                errorBanner(configErrorMessage)
                    .padding(.horizontal, LivelyBrand.Spacing.lg)
                    .padding(.top, LivelyBrand.Spacing.md)
                    .transition(.opacity)
            }

            ZStack(alignment: .topLeading) {
                switch section {
                case .general:
                    generalPane
                        .transition(LivelyBrand.contentTransition)
                case .playback:
                    playbackPane
                        .transition(LivelyBrand.contentTransition)
                case .screenSetup:
                    screenSetupPane
                        .transition(LivelyBrand.contentTransition)
                case .logs:
                    logsPane
                        .transition(LivelyBrand.contentTransition)
                case .about:
                    aboutPane
                        .transition(LivelyBrand.contentTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(reduceMotion ? nil : LivelyBrand.Motion.normal, value: section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func paneHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: LivelyBrand.Spacing.xs) {
            Text(title)
                .font(LivelyBrand.Typography.title)
                .foregroundStyle(LivelyBrand.foreground)
            Text(subtitle)
                .font(LivelyBrand.Typography.caption)
                .foregroundStyle(LivelyBrand.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LivelyBrand.Spacing.lg)
        .padding(.top, LivelyBrand.Spacing.lg)
        .padding(.bottom, LivelyBrand.Spacing.md)
    }

    // MARK: General

    private var generalPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LivelyBrand.Spacing.lg) {
                paneHeader(title: "General", subtitle: SettingsSection.general.subtitle)

                settingsCard {
                    toggleRow(
                        title: "Launch at Login",
                        subtitle: "Start Lively automatically when you log in.",
                        isOn: launchAtLoginBinding
                    )
                    cardDivider()
                    toggleRow(
                        title: "Start Minimized",
                        subtitle: "Launch Lively in the background.",
                        isOn: $preferences.startMinimized
                    )
                    cardDivider()
                    toggleRow(
                        title: "Pause on Battery",
                        subtitle: "Pause wallpapers when battery is at or below your threshold.",
                        isOn: $preferences.pauseOnBattery
                    )
                    if preferences.pauseOnBattery {
                        cardDivider()
                        batteryThresholdRow
                    }
                    cardDivider()
                    Text("Always pauses at \(Int(AppPreferences.forcedBatteryPausePercent))% or below on battery, even if Pause on Battery is off.")
                        .font(LivelyBrand.Typography.footnote)
                        .foregroundStyle(LivelyBrand.mutedForeground)
                        .padding(.vertical, 6)
                    cardDivider()
                    pickerRow(
                        title: "Appearance",
                        subtitle: "Light, Dark, or match your Mac’s system setting.",
                        selection: $preferences.appearance,
                        options: AppPreferences.AppAppearance.allCases.map { ($0, $0.displayName) }
                    )
                    cardDivider()
                    toggleRow(
                        title: "Check for Updates",
                        subtitle: "Check GitHub Releases in the background and show a banner when a newer version is available.",
                        isOn: $preferences.checkForUpdates
                    )
                }

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(LivelyBrand.Typography.footnote)
                        .foregroundStyle(LivelyBrand.destructive)
                        .padding(.horizontal, LivelyBrand.Spacing.lg)
                }

                // Destructive action as its own card (same density as other General groups).
                // "Reset Data" = clear wallpapers + preferences, not uninstall the app.
                settingsCard {
                    HStack(alignment: .center, spacing: LivelyBrand.Spacing.md) {
                        VStack(alignment: .leading, spacing: LivelyBrand.Spacing.tiny) {
                            Text("Reset Data")
                                .font(LivelyBrand.Typography.body.weight(.semibold))
                                .foregroundStyle(LivelyBrand.foreground)
                            Text("Remove all wallpapers and preferences. This cannot be undone.")
                                .font(LivelyBrand.Typography.footnote)
                                .foregroundStyle(LivelyBrand.mutedForeground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: LivelyBrand.Spacing.sm)
                        Button(role: .destructive) {
                            showResetConfirm = true
                        } label: {
                            Text("Reset…")
                                .font(LivelyBrand.Typography.caption.weight(.semibold))
                                .foregroundStyle(LivelyBrand.destructive)
                                .padding(.horizontal, LivelyBrand.Spacing.md)
                                .frame(minHeight: LivelyBrand.Spacing.controlMin)
                                .background(
                                    RoundedRectangle(cornerRadius: LivelyBrand.Radius.sm)
                                        .fill(LivelyBrand.destructive.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: LivelyBrand.Radius.sm)
                                        .strokeBorder(LivelyBrand.destructive.opacity(0.35), lineWidth: 1)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: LivelyBrand.Radius.sm))
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        .accessibilityLabel("Reset data")
                        .accessibilityHint("Removes all wallpapers and preferences")
                    }
                    .padding(.vertical, LivelyBrand.Spacing.xs)
                }
                .alert("Reset Data?", isPresented: $showResetConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset Data", role: .destructive) {
                        // Match the promise in the alert: assignments, library
                        // files, and preferences all go back to a clean slate.
                        configStore.clearAllData()
                        WallpaperLibraryManager.shared.reload()
                        preferences.resetToDefaults()
                    }
                } message: {
                    Text("This removes every wallpaper assignment and the videos saved in your Library, and restores preferences to defaults. Your original video files are not touched. This cannot be undone.")
                }
                .padding(.bottom, LivelyBrand.Spacing.lg)
            }
        }
        .scrollIndicators(.hidden)
    }

    private var batteryThresholdRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pause below")
                    .font(LivelyBrand.Typography.body.weight(.semibold))
                    .foregroundStyle(LivelyBrand.foreground)
                Spacer()
                Text("\(Int(preferences.batteryPauseThreshold.rounded()))%")
                    .font(LivelyBrand.Typography.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(LivelyBrand.primary)
                    .accessibilityLabel("Pause below \(Int(preferences.batteryPauseThreshold.rounded())) percent")
            }
            Slider(
                value: $preferences.batteryPauseThreshold,
                in: AppPreferences.batteryThresholdRange,
                step: 5
            )
            .tint(LivelyBrand.primary)
            .accessibilityLabel("Battery pause threshold")
            .accessibilityValue("\(Int(preferences.batteryPauseThreshold.rounded())) percent")

            Text("Wallpapers pause on battery when charge is at or below this level. Minimum is \(Int(AppPreferences.forcedBatteryPausePercent))%.")
                .font(LivelyBrand.Typography.footnote)
                .foregroundStyle(LivelyBrand.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }

    // MARK: Playback (expanded controls)

    private var playbackPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LivelyBrand.Spacing.lg) {
                paneHeader(title: "Playback", subtitle: SettingsSection.playback.subtitle)

                settingsCard {
                    pickerRow(
                        title: "Playback Quality",
                        subtitle: "Choose the balance between quality and performance.",
                        selection: $preferences.playbackQuality,
                        options: AppPreferences.PlaybackQuality.allCases.map { ($0, $0.displayName) }
                    )
                    cardDivider()
                    pickerRow(
                        title: "Loop Behavior",
                        subtitle: "Loop continuously, or play once and freeze on the last frame.",
                        selection: $preferences.loopBehavior,
                        options: AppPreferences.LoopBehavior.allCases.map { ($0, $0.displayName) }
                    )
                    cardDivider()
                    toggleRow(
                        title: "Hardware Decoding",
                        subtitle: "Use the GPU when available. Turn off to reduce GPU load.",
                        isOn: $preferences.hardwareDecoding
                    )
                    cardDivider()
                    pickerRow(
                        title: "Max Resolution",
                        subtitle: "Cap decode resolution for cooler, quieter playback.",
                        selection: $preferences.maxResolution,
                        options: AppPreferences.MaxResolution.allCases.map { ($0, $0.displayName) }
                    )
                }

                Text(preferences.playbackQuality.detail)
                    .font(LivelyBrand.Typography.footnote)
                    .foregroundStyle(LivelyBrand.mutedForeground)
                    .padding(.horizontal, LivelyBrand.Spacing.lg)
                    .padding(.bottom, LivelyBrand.Spacing.lg)
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Screen Setup (live display map)

    private var screenSetupPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LivelyBrand.Spacing.lg) {
                paneHeader(title: "Screen Setup", subtitle: SettingsSection.screenSetup.subtitle)

                ScreenSetupPreviewView(
                    spaceMonitor: spaceMonitor,
                    configStore: configStore,
                    onManageDisplay: onOpenDisplays
                )
                .padding(.horizontal, LivelyBrand.Spacing.lg)
                .padding(.bottom, LivelyBrand.Spacing.lg)
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Logs

    private var logsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneHeader(title: "Logs", subtitle: SettingsSection.logs.subtitle)
            LoggerView(embeddedInSettings: true)
                .padding(.horizontal, LivelyBrand.Spacing.lg)
                .padding(.bottom, LivelyBrand.Spacing.lg)
                .frame(maxHeight: .infinity)
        }
    }

    // MARK: About

    private var aboutPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LivelyBrand.Spacing.lg) {
                paneHeader(title: "About", subtitle: SettingsSection.about.subtitle)
                AboutView()
                    .padding(.horizontal, LivelyBrand.Spacing.lg)
                    .padding(.bottom, LivelyBrand.Spacing.lg)
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Shared building blocks

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, LivelyBrand.Spacing.lg)
        .padding(.vertical, LivelyBrand.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.lg)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.lg)
                .strokeBorder(LivelyBrand.border.opacity(0.55), lineWidth: 1)
        )
        .padding(.horizontal, LivelyBrand.Spacing.lg)
    }

    private func cardDivider() -> some View {
        Divider()
            .background(LivelyBrand.border)
            .padding(.vertical, 2)
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: LivelyBrand.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LivelyBrand.Typography.body.weight(.semibold))
                    .foregroundStyle(LivelyBrand.foreground)
                    .accessibilityHidden(true)
                Text(subtitle)
                    .font(LivelyBrand.Typography.caption)
                    .foregroundStyle(LivelyBrand.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .tint(LivelyBrand.primary)
                .labelsHidden()
                .accessibilityLabel(title)
                .accessibilityHint(subtitle)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private func pickerRow<T: Hashable>(
        title: String,
        subtitle: String,
        selection: Binding<T>,
        options: [(T, String)]
    ) -> some View {
        HStack(alignment: .center, spacing: LivelyBrand.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LivelyBrand.Typography.body.weight(.semibold))
                    .foregroundStyle(LivelyBrand.foreground)
                    .accessibilityHidden(true)
                Text(subtitle)
                    .font(LivelyBrand.Typography.caption)
                    .foregroundStyle(LivelyBrand.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            Picker("", selection: selection) {
                ForEach(options, id: \.0) { value, label in
                    Text(label).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 128)
            .accessibilityLabel(title)
            .accessibilityHint(subtitle)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: LivelyBrand.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(LivelyBrand.destructive)
            Text(message)
                .font(LivelyBrand.Typography.caption)
                .foregroundStyle(LivelyBrand.foreground)
        }
        .padding(LivelyBrand.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.md)
                .fill(LivelyBrand.destructive.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.md)
                .strokeBorder(LivelyBrand.destructive.opacity(0.3))
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { newValue in
                launchAtLoginError = nil
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLoginError = "Launch at login could not be updated. The app may need to be signed for distribution."
                    LivelyLogger.config.error("Launch at login failed: \(error.localizedDescription)")
                }
            }
        )
    }

    private func message(for error: ConfigStore.Error) -> String {
        switch error {
        case .persistFailed:
            return "Could not save settings. Check disk space and try again."
        case .loadFailed:
            return "Could not load saved settings. Starting fresh."
        case .bookmarkRefreshFailed, .bookmarkCreationFailed:
            return "Could not access a video file. Re-select it in Displays."
        case .directoryCreationFailed:
            return "Could not create the Lively data folder."
        }
    }
}
