import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

private let supportedVideoTypes: [UTType] = [.mpeg4Movie, .quickTimeMovie, .movie]

// MARK: - Screen Card View

struct ScreenCardView: View {
    let space: ScreenSpace
    let configStore: ConfigStore
    @ObservedObject var spaceMonitor: SpaceMonitor
    /// 1-based index among connected displays (Display 1, Display 2, …).
    var displayIndex: Int = 1
    /// First display receives welcome-sheet “Choose a video…” file picker.
    var isPrimaryDisplay: Bool = false

    @ObservedObject private var preferences = AppPreferences.shared
    @EnvironmentObject var wallpaperController: WallpaperController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewState private var currentConfig: SpaceConfig?
    @ViewState private var isTargetedMain = false
    @ViewState private var isTargetedLight = false
    @ViewState private var isTargetedDark = false
    @ViewState private var isValidatingMain = false
    @ViewState private var isValidatingLight = false
    @ViewState private var isValidatingDark = false
    @ViewState private var resolvedStaticURL: URL?
    @ViewState private var resolvedLightURL: URL?
    @ViewState private var resolvedDarkURL: URL?

    @ViewState private var errorMessage: String?
    @ViewState private var errorClearTask: Task<Void, Swift.Error>?

    /// Sticky success chip (not auto-dismiss) after assign.
    @ViewState private var showPlayingBanner = false
    @ViewState private var showSpacesCoach = false
    @ViewState private var showApplyAllConfirm = false

    private var config: SpaceConfig? { currentConfig }

    private var currentWallpaper: DynamicWallpaper {
        config?.dynamicWallpaper ?? DynamicWallpaper()
    }

    private var assignedVideoLabel: String? {
        if let url = currentWallpaper.staticURL, currentWallpaper.mode == .staticVideo {
            return url.lastPathComponent
        }
        if currentWallpaper.mode == .appearance {
            if let light = currentWallpaper.lightURL, let dark = currentWallpaper.darkURL {
                return "\(light.lastPathComponent) · \(dark.lastPathComponent)"
            }
            return (currentWallpaper.lightURL ?? currentWallpaper.darkURL)?.lastPathComponent
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            displayHeader

            Divider()
                .overlay(LivelyBrand.border.opacity(0.35))

            VStack(spacing: LivelyBrand.Spacing.sm) {
                PillTabBar(
                    tabs: [("Wallpaper", DynamicMode.staticVideo), ("Light & Dark", DynamicMode.appearance)],
                    selection: Binding(
                        get: { currentWallpaper.mode },
                        set: { newMode in
                            var updated = currentWallpaper
                            updated.mode = newMode
                            configStore.assign(dynamicWallpaper: updated, toSpaceKey: space.spaceKey)
                        }
                    )
                )

                if currentWallpaper.mode == .appearance {
                    Text("Different videos for light and dark mode")
                        .font(LivelyBrand.Typography.footnote)
                        .foregroundStyle(LivelyBrand.mutedForeground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, LivelyBrand.Spacing.md)
            .padding(.vertical, LivelyBrand.Spacing.md)

            if hasMissingAssignment {
                missingFileBanner
                    .padding(.horizontal, LivelyBrand.Spacing.md)
                    .padding(.bottom, LivelyBrand.Spacing.sm)
                    .transition(LivelyBrand.contentTransition)
            }

            HStack(spacing: LivelyBrand.Spacing.md) {
                dropZone(
                    title: currentWallpaper.mode == .appearance ? "Light mode" : "",
                    icon: currentWallpaper.mode == .appearance ? "sun.max.fill" : "film",
                    url: currentWallpaper.mode == .appearance ? resolvedLightURL : resolvedStaticURL,
                    isTargeted: currentWallpaper.mode == .appearance ? $isTargetedLight : $isTargetedMain,
                    isValidating: currentWallpaper.mode == .appearance ? $isValidatingLight : $isValidatingMain,
                    fileMissing: currentWallpaper.mode == .staticVideo && hasMissingStatic,
                    onDrop: { url in
                        acceptWallpaper(url, role: .mainOrLight)
                    },
                    onClear: {
                        clearMainOrLight()
                    }
                )

                if currentWallpaper.mode == .appearance {
                    dropZone(
                        title: "Dark mode",
                        icon: "moon.stars.fill",
                        url: resolvedDarkURL,
                        isTargeted: $isTargetedDark,
                        isValidating: $isValidatingDark,
                        fileMissing: hasMissingDark,
                        onDrop: { url in
                            acceptWallpaper(url, role: .dark)
                        },
                        onClear: {
                            clearDark()
                        }
                    )
                    .transition(LivelyBrand.contentTransition)
                }
            }
            .padding(.horizontal, LivelyBrand.Spacing.md)
            .padding(.bottom, LivelyBrand.Spacing.md)

            if showPlayingBanner {
                stickyPlayingBanner
                    .padding(.horizontal, LivelyBrand.Spacing.md)
                    .padding(.bottom, LivelyBrand.Spacing.sm)
                    .transition(LivelyBrand.contentTransition)
            }

            if showSpacesCoach {
                spacesCoachBanner
                    .padding(.horizontal, LivelyBrand.Spacing.md)
                    .padding(.bottom, LivelyBrand.Spacing.sm)
                    .transition(LivelyBrand.contentTransition)
            }

            if config != nil {
                displaySettingsSection
                    .transition(LivelyBrand.contentTransition)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.lg)
                .fill(LivelyBrand.card.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.lg)
                .strokeBorder(LivelyBrand.border.opacity(0.45))
        )
        .animation(reduceMotion ? nil : LivelyBrand.Motion.fast, value: errorMessage)
        .animation(reduceMotion ? nil : LivelyBrand.Motion.normal, value: currentWallpaper.mode)
        .animation(reduceMotion ? nil : LivelyBrand.Motion.normal, value: config != nil)
        .overlay(alignment: .top) {
            if let error = errorMessage {
                Text(error)
                    .font(LivelyBrand.Typography.footnote.weight(.medium))
                    .foregroundStyle(LivelyBrand.onDestructive)
                    .padding(.horizontal, LivelyBrand.Spacing.md)
                    .padding(.vertical, LivelyBrand.Spacing.xxs)
                    .background(LivelyBrand.destructive.opacity(0.92))
                    .clipShape(.rect(cornerRadius: LivelyBrand.Radius.sm))
                    .padding(.top, LivelyBrand.Spacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .onReceive(wallpaperController.playbackErrors) { (targetSpaceKey, message) in
            if targetSpaceKey == space.spaceKey {
                showPlayingBanner = false
                showError("Playback failed: \(message)")
            }
        }
        .onAppear {
            currentConfig = configStore.configs[space.spaceKey]
            refreshResolvedURLs()
        }
        .onReceive(configStore.$configs) { newConfigs in
            let newConfig = newConfigs[space.spaceKey]
            if currentConfig?.dynamicWallpaper != newConfig?.dynamicWallpaper
                || (currentConfig == nil && newConfig != nil)
                || (currentConfig != nil && newConfig == nil) {
                currentConfig = newConfig
                refreshResolvedURLs()
                if newConfig == nil {
                    showPlayingBanner = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .livelyRequestFirstVideoPick)) { _ in
            guard isPrimaryDisplay else { return }
            openFilePicker(isValidating: $isValidatingMain) { url in
                acceptWallpaper(url, role: .mainOrLight)
            }
        }
        .confirmationDialog(
            "Apply this wallpaper to every connected display?",
            isPresented: $showApplyAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Apply to All Displays") {
                applyToAllDisplays()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Missing file / sticky banners

    private var hasMissingStatic: Bool {
        currentWallpaper.mode == .staticVideo
            && currentWallpaper.staticURL != nil
            && resolvedStaticURL == nil
            && config != nil
    }

    private var hasMissingLight: Bool {
        currentWallpaper.mode == .appearance
            && currentWallpaper.lightURL != nil
            && resolvedLightURL == nil
    }

    private var hasMissingDark: Bool {
        currentWallpaper.mode == .appearance
            && currentWallpaper.darkURL != nil
            && resolvedDarkURL == nil
    }

    private var hasMissingAssignment: Bool {
        hasMissingStatic || hasMissingLight || hasMissingDark
    }

    private var missingFileBanner: some View {
        HStack(spacing: LivelyBrand.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(nsColor: .systemOrange))
            VStack(alignment: .leading, spacing: 2) {
                Text("File missing")
                    .font(LivelyBrand.Typography.caption.weight(.semibold))
                Text("The video was moved or deleted. Reselect it to restore this wallpaper.")
                    .font(LivelyBrand.Typography.footnote)
                    .foregroundStyle(LivelyBrand.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Reselect…") {
                let binding = hasMissingDark && !hasMissingStatic && !hasMissingLight
                    ? $isValidatingDark
                    : (hasMissingLight ? $isValidatingLight : $isValidatingMain)
                openFilePicker(isValidating: binding) { url in
                    if hasMissingDark && currentWallpaper.mode == .appearance && resolvedDarkURL == nil
                        && currentWallpaper.darkURL != nil && resolvedLightURL != nil {
                        acceptWallpaper(url, role: .dark)
                    } else {
                        acceptWallpaper(url, role: .mainOrLight)
                    }
                }
            }
            .buttonStyle(PressScaleButtonStyle())
            .font(LivelyBrand.Typography.caption.weight(.semibold))
            .foregroundStyle(LivelyBrand.primary)
            .livelyFocusRing(cornerRadius: LivelyBrand.Radius.sm)
        }
        .padding(LivelyBrand.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.sm)
                .fill(Color(nsColor: .systemOrange).opacity(0.12))
        )
    }

    private var stickyPlayingBanner: some View {
        HStack(spacing: LivelyBrand.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(LivelyBrand.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Playing on this display")
                    .font(LivelyBrand.Typography.caption.weight(.semibold))
                if preferences.playbackQuality == .high {
                    Text("If your Mac gets warm, try Power Saver under Settings → Playback.")
                        .font(LivelyBrand.Typography.footnote)
                        .foregroundStyle(LivelyBrand.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if spaceMonitor.screenSpaces.count > 1, currentWallpaper.staticURL != nil || resolvedStaticURL != nil {
                Button("Apply to All") {
                    showApplyAllConfirm = true
                }
                .font(LivelyBrand.Typography.footnote.weight(.semibold))
                .foregroundStyle(LivelyBrand.primary)
                .buttonStyle(PressScaleButtonStyle())
            }
            Button {
                showPlayingBanner = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LivelyBrand.mutedForeground)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityLabel("Dismiss playing status")
        }
        .padding(LivelyBrand.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.sm)
                .fill(LivelyBrand.primary.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.sm)
                .strokeBorder(LivelyBrand.primary.opacity(0.22), lineWidth: 1)
        )
    }

    private var spacesCoachBanner: some View {
        HStack(spacing: LivelyBrand.Spacing.sm) {
            Image(systemName: "rectangle.on.rectangle")
                .foregroundStyle(LivelyBrand.primary)
            Text("Tip: switch Spaces (Control + ←/→) to set a different wallpaper on another desktop.")
                .font(LivelyBrand.Typography.footnote)
                .foregroundStyle(LivelyBrand.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Got it") {
                showSpacesCoach = false
                preferences.hasSeenSpacesCoach = true
            }
            .font(LivelyBrand.Typography.caption.weight(.semibold))
            .foregroundStyle(LivelyBrand.primary)
            .buttonStyle(PressScaleButtonStyle())
            .livelyFocusRing(cornerRadius: LivelyBrand.Radius.sm)
        }
        .padding(LivelyBrand.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.sm)
                .fill(LivelyBrand.controlFill.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.sm)
                .strokeBorder(LivelyBrand.border.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: Header

    private var displayTitle: String {
        "Display \(displayIndex)"
    }

    private var displayHeader: some View {
        HStack(spacing: LivelyBrand.Spacing.md) {
            Image(systemName: "display")
                .font(LivelyBrand.Typography.iconControl)
                .foregroundStyle(LivelyBrand.mutedForeground)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                // Hierarchy: index label (section) + hardware name (title)
                HStack(alignment: .firstTextBaseline, spacing: LivelyBrand.Spacing.sm) {
                    Text(displayTitle)
                        .font(LivelyBrand.Typography.section)
                        .foregroundStyle(LivelyBrand.mutedForeground)
                    Text(space.displayName)
                        .font(LivelyBrand.Typography.title)
                        .foregroundStyle(LivelyBrand.foreground)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(displayTitle), \(space.displayName)")

                if let label = assignedVideoLabel {
                    Text(label)
                        .font(LivelyBrand.Typography.mono)
                        .foregroundStyle(LivelyBrand.mutedForeground)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: LivelyBrand.Spacing.sm)

            if config != nil {
                Button {
                    confirmRemoveWallpaper()
                } label: {
                    Label("Remove wallpaper", systemImage: "trash")
                        .labelStyle(.iconOnly)
                        .font(LivelyBrand.Typography.iconControl)
                        .foregroundStyle(LivelyBrand.destructive)
                        .frame(minWidth: LivelyBrand.Spacing.controlMin, minHeight: LivelyBrand.Spacing.controlMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel("Remove wallpaper")
                .accessibilityHint("Removes the assigned wallpaper from this display")
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .padding(.horizontal, LivelyBrand.Spacing.lg)
        .padding(.vertical, LivelyBrand.Spacing.lg)
    }

    // MARK: - Display Settings

    private var displaySettingsSection: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(LivelyBrand.border.opacity(0.35))

            HStack(spacing: LivelyBrand.Spacing.md) {
                HStack(spacing: LivelyBrand.Spacing.sm) {
                    Text("Scale")
                        .font(LivelyBrand.Typography.caption.weight(.semibold))
                        .foregroundStyle(LivelyBrand.mutedForeground)
                        .accessibilityHidden(true)

                    Picker("Scale", selection: Binding(
                        get: { currentWallpaper.videoGravity },
                        set: { newValue in
                            configStore.updateDisplaySettings(
                                for: space.spaceKey,
                                gravity: newValue,
                                isMuted: currentWallpaper.isMuted,
                                volume: currentWallpaper.volume
                            )
                        }
                    )) {
                        Text("Fill").tag(VideoGravity.fill)
                        Text("Fit").tag(VideoGravity.fit)
                    }
                    .pickerStyle(.menu)
                    .controlSize(.regular)
                    .labelsHidden()
                    .font(LivelyBrand.Typography.body)
                    .frame(minHeight: LivelyBrand.Spacing.controlMin)
                }

                Spacer(minLength: LivelyBrand.Spacing.sm)

                Button {
                    let newValue = !currentWallpaper.isMuted
                    configStore.updateDisplaySettings(
                        for: space.spaceKey,
                        gravity: currentWallpaper.videoGravity,
                        isMuted: newValue,
                        volume: newValue ? 0 : currentWallpaper.volume
                    )
                } label: {
                    Group {
                        if !reduceMotion {
                            Image(systemName: currentWallpaper.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .contentTransition(.symbolEffect(.replace))
                        } else {
                            Image(systemName: currentWallpaper.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        }
                    }
                    .font(LivelyBrand.Typography.iconSmall)
                    .foregroundStyle(currentWallpaper.isMuted ? LivelyBrand.mutedForeground : LivelyBrand.primary)
                    .frame(minWidth: LivelyBrand.Spacing.controlMin + 4, minHeight: LivelyBrand.Spacing.controlMin + 4)
                    .contentShape(Circle())
                    .background(
                        Circle()
                            .fill(currentWallpaper.isMuted ? Color.clear : LivelyBrand.primary.opacity(0.15))
                    )
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel(currentWallpaper.isMuted ? "Unmute" : "Mute")

                if !currentWallpaper.isMuted {
                    Slider(
                        value: Binding(
                            get: { currentWallpaper.volume },
                            set: { newValue in
                                configStore.updateDisplaySettings(
                                    for: space.spaceKey,
                                    gravity: currentWallpaper.videoGravity,
                                    isMuted: currentWallpaper.isMuted,
                                    volume: newValue
                                )
                            }
                        ),
                        in: 0...1
                    )
                    .tint(LivelyBrand.primary)
                    .controlSize(.regular)
                    .frame(width: 100)
                    .frame(minHeight: LivelyBrand.Spacing.controlMin)
                    .accessibilityLabel("Volume")
                    .accessibilityValue("\(Int(currentWallpaper.volume * 100)) percent")
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, LivelyBrand.Spacing.lg)
            .padding(.vertical, LivelyBrand.Spacing.md)
            .animation(reduceMotion ? nil : LivelyBrand.Motion.fast, value: currentWallpaper.isMuted)
        }
    }

    // MARK: Drop Zone

    private func refreshResolvedURLs() {
        resolvedStaticURL = configStore.resolveBookmark(for: space.spaceKey, bookmarkKey: "static")
        resolvedLightURL = configStore.resolveBookmark(for: space.spaceKey, bookmarkKey: "light")
        resolvedDarkURL = configStore.resolveBookmark(for: space.spaceKey, bookmarkKey: "dark")
    }

    // C-1 fix: DropZoneView owns its own @ViewState so each instance has
    // independent auroraRotation — no shared state glitch in .appearance mode.
    private func dropZone(
        title: String,
        icon: String,
        url: URL?,
        isTargeted: Binding<Bool>,
        isValidating: Binding<Bool>,
        fileMissing: Bool = false,
        onDrop: @escaping @MainActor (URL) -> Void,
        onClear: @escaping @MainActor () -> Void
    ) -> some View {
        DropZoneView(
            title: title,
            icon: icon,
            url: url,
            isTargeted: isTargeted,
            isValidating: isValidating,
            fileMissing: fileMissing,
            reduceMotion: reduceMotion,
            onFilePick: { openFilePicker(isValidating: isValidating, onPick: onDrop) },
            onURLDrop: { dropped in
                handleURLSelection(dropped, isValidating: isValidating, onAccept: onDrop)
            },
            onError: { message in
                showError(message)
            },
            onClear: onClear
        )
    }

    // MARK: - Interactions

    private enum WallpaperRole {
        case mainOrLight
        case dark
    }

    private func acceptWallpaper(_ url: URL, role: WallpaperRole) {
        let wasFirstTime = !AppMetrics.shared.isActivated
        var updated = currentWallpaper
        switch role {
        case .mainOrLight:
            if updated.mode == .appearance {
                updated.lightURL = url
            } else {
                updated.staticURL = url
            }
        case .dark:
            updated.darkURL = url
        }
        configStore.assign(dynamicWallpaper: updated, toSpaceKey: space.spaceKey)
        showPlayingBanner = true
        AccessibilityNotification.Announcement("Playing on this display.").post()
        if wasFirstTime || !preferences.hasSeenSpacesCoach {
            showSpacesCoach = true
        }
    }

    private func clearMainOrLight() {
        var updated = currentWallpaper
        if updated.mode == .appearance {
            updated.lightURL = nil
            if updated.darkURL == nil {
                configStore.remove(spaceKey: space.spaceKey)
            } else {
                configStore.assign(dynamicWallpaper: updated, toSpaceKey: space.spaceKey)
            }
        } else {
            configStore.remove(spaceKey: space.spaceKey)
        }
        showPlayingBanner = false
    }

    private func clearDark() {
        var updated = currentWallpaper
        updated.darkURL = nil
        if updated.lightURL == nil {
            configStore.remove(spaceKey: space.spaceKey)
        } else {
            configStore.assign(dynamicWallpaper: updated, toSpaceKey: space.spaceKey)
        }
    }

    private func applyToAllDisplays() {
        let url = resolvedStaticURL ?? currentWallpaper.staticURL
        guard let url else { return }
        let keys = spaceMonitor.screenSpaces.map(\.spaceKey)
        configStore.applyStaticWallpaper(url, toAllSpaceKeys: keys)
        showPlayingBanner = true
        AccessibilityNotification.Announcement("Wallpaper applied to all displays.").post()
    }

    private func showError(_ message: String) {
        errorMessage = message
        AccessibilityNotification.Announcement(message).post()
        errorClearTask?.cancel()
        errorClearTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(5))
                errorMessage = nil
            } catch {
                // Task was cancelled — do not update state
            }
        }
    }

    private func handleURLSelection(
        _ url: URL,
        isValidating: Binding<Bool>,
        onAccept: @escaping @MainActor (URL) -> Void
    ) {
        Task { @MainActor in
            isValidating.wrappedValue = true
            defer { isValidating.wrappedValue = false }

            switch await VideoValidator.validate(url) {
            case .invalid(let message):
                showError(message)
            case .valid:
                errorMessage = nil
                onAccept(url)
            }
        }
    }

    @MainActor
    private func confirmRemoveWallpaper() {
        let alert = NSAlert()
        alert.messageText = "Remove wallpaper?"
        alert.informativeText = "This removes the assigned video configuration from this Space."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            configStore.remove(spaceKey: space.spaceKey)
        }
    }

    @MainActor
    private func openFilePicker(
        isValidating: Binding<Bool>,
        onPick: @escaping @MainActor (URL) -> Void
    ) {
        NSApp.activate()

        let panel = NSOpenPanel()
        panel.allowedContentTypes = supportedVideoTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a video wallpaper"
        panel.prompt = "Select"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.handleURLSelection(url, isValidating: isValidating, onAccept: onPick)
            }
        }
    }
}

// MARK: - Drop Zone View (C-1: each instance owns its own auroraRotation)

/// Self-contained drop zone. By being a separate `View` struct, each instance
/// gets its own `@ViewState private var auroraRotation`, preventing the shared-state
/// glitch that occurred in `.appearance` mode when one zone's `.onDisappear`
/// reset the other zone's animation.
private struct DropZoneView: View {
    let title: String
    let icon: String
    let url: URL?
    let isTargeted: Binding<Bool>
    let isValidating: Binding<Bool>
    let fileMissing: Bool
    let reduceMotion: Bool
    let onFilePick: @MainActor () -> Void
    let onURLDrop: @MainActor (URL) -> Void
    let onError: @MainActor (String) -> Void
    let onClear: @MainActor () -> Void

    @ViewState private var auroraRotation: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            if isValidating.wrappedValue {
                progressView
            } else if let url = url {
                activeVideoView(url: url)
            } else if fileMissing {
                missingPlaceholderView
            } else {
                emptyPlaceholderView
            }
        }
        .padding(LivelyBrand.Spacing.md)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 60)
        .background(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.md)
                .fill(
                    isTargeted.wrappedValue
                        ? LivelyBrand.primary.opacity(0.12)
                        : LivelyBrand.controlFill.opacity(0.55)
                )
        )
        .scaleEffect(isTargeted.wrappedValue ? 1.03 : 1.0)
        .animation(reduceMotion ? nil : LivelyBrand.Motion.dropTarget, value: isTargeted.wrappedValue)
        .accessibilityLabel(
            url.map { "\(title.isEmpty ? "Wallpaper" : title), \($0.lastPathComponent)" }
                ?? "\(title.isEmpty ? "Wallpaper" : title), choose video"
        )
        .accessibilityHint(url == nil ? "Drag and drop a video, or click to browse" : "Click to change video, or click the clear button in the top-right corner to remove it")
        .onDrop(of: [.fileURL], isTargeted: isTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                if let error = error {
                    Task { @MainActor in
                        onError(error.localizedDescription)
                    }
                    return
                }
                guard
                    let data = item as? Data,
                    let url = URL(dataRepresentation: data, relativeTo: nil)
                else {
                    Task { @MainActor in
                        onError("Failed to parse dropped file.")
                    }
                    return
                }
                Task { @MainActor in onURLDrop(url) }
            }
            return true
        }
    }

    // MARK: - Sub-views (fixes compiler type-check timeout)

    @ViewBuilder
    private var progressView: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, minHeight: 80)
    }

    @ViewBuilder
    private func activeVideoView(url: URL) -> some View {
        VStack(spacing: LivelyBrand.Spacing.sm) {
            ZStack(alignment: .topTrailing) {
                Button {
                    onFilePick()
                } label: {
                    VideoThumbnailView(url: url)
                        .contentShape(Rectangle())
                        .overlay(alignment: .bottomLeading) {
                            Text("Click to change")
                                .font(LivelyBrand.Typography.badge)
                                .foregroundStyle(.white)
                                .padding(.horizontal, LivelyBrand.Spacing.xxs)
                                .padding(.vertical, LivelyBrand.Spacing.tiny)
                                .background(LivelyBrand.overlayBackground)
                                .clipShape(.rect(cornerRadius: LivelyBrand.Radius.sm))
                                .padding(LivelyBrand.Spacing.xxs)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Change video for \(title.isEmpty ? "Wallpaper" : title)")
                .accessibilityHint("Double tap to open the file picker and select a new video")
                
                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, LivelyBrand.clearButtonBackground)
                        .font(LivelyBrand.Typography.iconSmall)
                        .padding(LivelyBrand.Spacing.xxs)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Clear this video")
                .accessibilityLabel("Remove video")
            }
            .frame(height: 90)
            .clipShape(.rect(cornerRadius: LivelyBrand.Radius.sm))
            
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(LivelyBrand.primary)
                    .font(LivelyBrand.Typography.caption)
                Text(url.lastPathComponent)
                    .font(LivelyBrand.Typography.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, LivelyBrand.Spacing.sm)
            .padding(.vertical, LivelyBrand.Spacing.xs)

            if !title.isEmpty {
                Text(title)
                    .font(LivelyBrand.Typography.caption)
                    .foregroundStyle(LivelyBrand.mutedForeground)
            }
        }
    }

    private var missingPlaceholderView: some View {
        Button {
            onFilePick()
        } label: {
            VStack(spacing: LivelyBrand.Spacing.xxs) {
                Image(systemName: "exclamationmark.triangle")
                    .font(LivelyBrand.Typography.iconLarge)
                    .foregroundStyle(Color(nsColor: .systemOrange))
                Text(title.isEmpty ? "File missing — click to reselect" : "\(title): file missing — reselect")
                    .font(LivelyBrand.Typography.caption)
                    .foregroundStyle(LivelyBrand.mutedForeground)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 80)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var emptyPlaceholderView: some View {
        Button {
            onFilePick()
        } label: {
            VStack(spacing: LivelyBrand.Spacing.xxs) {
                Group {
                    if !reduceMotion {
                        Image(systemName: isTargeted.wrappedValue ? "arrow.down.circle.fill" : icon)
                            .symbolEffect(.pulse, value: isTargeted.wrappedValue)
                            .contentTransition(.symbolEffect(.replace))
                    } else {
                        Image(systemName: isTargeted.wrappedValue ? "arrow.down.circle.fill" : icon)
                    }
                }
                .font(LivelyBrand.Typography.iconLarge)
                .foregroundStyle(isTargeted.wrappedValue ? LivelyBrand.primary : LivelyBrand.mutedForeground)

                if isTargeted.wrappedValue {
                    Text("Drop here")
                        .font(LivelyBrand.Typography.caption)
                        .foregroundStyle(LivelyBrand.foreground)
                        .transition(.opacity)
                } else if title.isEmpty {
                    Text("Drop a video, or click to browse")
                        .font(LivelyBrand.Typography.caption)
                        .foregroundStyle(LivelyBrand.mutedForeground)
                } else {
                    VStack(spacing: 2) {
                        Text(title)
                            .font(LivelyBrand.Typography.caption.weight(.semibold))
                            .foregroundStyle(LivelyBrand.foreground)
                        Text("Drop a video, or click to browse")
                            .font(LivelyBrand.Typography.footnote)
                            .foregroundStyle(LivelyBrand.mutedForeground)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 80)
            .overlay {
                if isTargeted.wrappedValue && !reduceMotion {
                    RoundedRectangle(cornerRadius: LivelyBrand.Radius.sm)
                        .stroke(
                            AngularGradient(
                                colors: [
                                    LivelyBrand.primary,
                                    LivelyBrand.primarySoft,
                                    LivelyBrand.primary.opacity(0.4),
                                    LivelyBrand.primarySoft,
                                    LivelyBrand.primary
                                ],
                                center: .center,
                                angle: .degrees(auroraRotation)
                            ),
                            lineWidth: 2
                        )
                        .onChange(of: isTargeted.wrappedValue) { _, targeted in
                            if targeted && !reduceMotion {
                                auroraRotation = 0
                                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                                    auroraRotation = 360
                                }
                            } else {
                                withAnimation(nil) { auroraRotation = 0 }
                            }
                        }
                        .onAppear {
                            guard isTargeted.wrappedValue, !reduceMotion else {
                                auroraRotation = 0
                                return
                            }
                            auroraRotation = 0
                            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                                auroraRotation = 360
                            }
                        }
                        .onDisappear {
                            withAnimation(nil) { auroraRotation = 0 }
                        }
                } else {
                    RoundedRectangle(cornerRadius: LivelyBrand.Radius.sm)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundStyle(
                            isTargeted.wrappedValue
                                ? LivelyBrand.primary.opacity(0.68)
                                : LivelyBrand.border.opacity(0.52)
                        )
                }
            }
        }
        .buttonStyle(.plain)
    }
}