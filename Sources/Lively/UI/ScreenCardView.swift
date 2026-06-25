import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

private let supportedVideoTypes: [UTType] = [.mpeg4Movie, .quickTimeMovie, .movie]

// MARK: - Secondary Tab Bar

private struct SecondaryTabBar: View {
    @Binding var selection: DynamicMode
    @Namespace private var tabIndicator

    var body: some View {
        HStack(spacing: 2) {
            tabButton("Wallpaper", mode: .staticVideo)
            tabButton("Appearance", mode: .appearance)
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private func tabButton(_ label: String, mode: DynamicMode) -> some View {
        Button {
            withAnimation(LivelyBrand.Motion.fast) { selection = mode }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .hidden()
                .overlay {
                    Text(label)
                        .font(.system(size: 12, weight: selection == mode ? .semibold : .regular))
                        .foregroundStyle(selection == mode ? Color.primary : Color.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background {
                    if selection == mode {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.background)
                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                            .matchedGeometryEffect(id: "pill", in: tabIndicator)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Screen Card View

struct ScreenCardView: View {
    let space: ScreenSpace
    let configStore: ConfigStore

    @State private var currentConfig: SpaceConfig?

    // Drop targeting states
    @State private var isTargetedMain = false
    @State private var isTargetedLight = false
    @State private var isTargetedDark = false

    // Settings disclosure removed
    // @State private var showSettings = false

    // Remove confirmation
    @State private var showRemoveConfirm = false

    // Environment
    @EnvironmentObject var wallpaperController: WallpaperController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Error feedback
    @State private var errorMessage: String?
    @State private var errorClearTask: Task<Void, Swift.Error>?

    private var config: SpaceConfig? {
        currentConfig
    }
    
    private var currentWallpaper: DynamicWallpaper {
        config?.dynamicWallpaper ?? DynamicWallpaper()
    }

    var body: some View {
        VStack(spacing: 0) {
            displayHeader
            
            Divider()
                .overlay(LivelyBrand.border.opacity(0.35))
            
            // Mode Selection — custom secondary tab bar
            SecondaryTabBar(selection: Binding(
                get: { currentWallpaper.mode },
                set: { newMode in
                    var updated = currentWallpaper
                    updated.mode = newMode
                    configStore.assign(dynamicWallpaper: updated, toSpaceKey: space.spaceKey)
                }
            ))
            .padding(.horizontal, LivelyBrand.Spacing.md)
            .padding(.vertical, LivelyBrand.Spacing.md)
            
            HStack(spacing: 12) {
                dropZone(
                    title: currentWallpaper.mode == .appearance ? "Light mode" : "",
                    icon: currentWallpaper.mode == .appearance ? "sun.max.fill" : "film",
                    url: currentWallpaper.mode == .appearance 
                        ? configStore.resolveBookmark(for: space.spaceKey, bookmarkKey: "light", fallbackURL: currentWallpaper.lightURL)
                        : configStore.resolveBookmark(for: space.spaceKey, bookmarkKey: "static", fallbackURL: currentWallpaper.staticURL),
                    isTargeted: currentWallpaper.mode == .appearance ? $isTargetedLight : $isTargetedMain,
                    onDrop: { url in
                        var updated = currentWallpaper
                        if updated.mode == .appearance {
                            updated.lightURL = url
                        } else {
                            updated.staticURL = url
                        }
                        configStore.assign(dynamicWallpaper: updated, toSpaceKey: space.spaceKey)
                    }
                )

                if currentWallpaper.mode == .appearance {
                    dropZone(
                        title: "Dark mode",
                        icon: "moon.stars.fill",
                        url: configStore.resolveBookmark(for: space.spaceKey, bookmarkKey: "dark", fallbackURL: currentWallpaper.darkURL),
                        isTargeted: $isTargetedDark,
                        onDrop: { url in
                            var updated = currentWallpaper
                            updated.darkURL = url
                            configStore.assign(dynamicWallpaper: updated, toSpaceKey: space.spaceKey)
                        }
                    )
                    .transition(modeTransition)
                }
            }
            .padding(.horizontal, LivelyBrand.Spacing.md)
            .padding(.bottom, LivelyBrand.Spacing.md)
            
            // Per-video display settings (only when a wallpaper is assigned)
            if config != nil {
                displaySettingsSection
            }
        }
        .liquidGlass(.regular.tint(LivelyBrand.card).opacity(0.12), in: RoundedRectangle(cornerRadius: LivelyBrand.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.lg)
                .strokeBorder(LivelyBrand.border.opacity(0.45))
        )
        .animation(reduceMotion ? nil : LivelyBrand.Motion.fast, value: errorMessage)
        // .animation(reduceMotion ? nil : LivelyBrand.Motion.normal, value: showSettings)
        .animation(reduceMotion ? nil : LivelyBrand.Motion.normal, value: currentWallpaper.mode)
        .overlay(alignment: .top) {
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(LivelyBrand.destructive.opacity(0.92))
                    .cornerRadius(LivelyBrand.Radius.sm)
                    .padding(.top, LivelyBrand.Spacing.sm)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .zIndex(10)
            }
        }
        .onReceive(wallpaperController.playbackErrors) { (targetSpaceKey, message) in
            // Only show the error on the card for the display that failed
            if targetSpaceKey == space.spaceKey {
                errorMessage = "Playback failed: \(message)"
                AccessibilityNotification.Announcement("Playback failed: \(message)").post()
                
                // Cancel any pending clear
                errorClearTask?.cancel()
                
                // Auto-clear after 5 seconds
                errorClearTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(5))
                    if !Task.isCancelled {
                        errorMessage = nil
                    }
                }
            }
        }
        .onAppear {
            currentConfig = configStore.configs[space.spaceKey]
        }
        .onReceive(configStore.$configs) { newConfigs in
            let newConfig = newConfigs[space.spaceKey]
            if currentConfig?.dynamicWallpaper != newConfig?.dynamicWallpaper || (currentConfig == nil && newConfig != nil) || (currentConfig != nil && newConfig == nil) {
                currentConfig = newConfig
            }
        }
    }

    // MARK: Header

    private var displayHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "display")
                .font(.system(size: 14))
                .foregroundStyle(Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(space.displayName)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let url = space.desktopImageURL {
                    Text(url.lastPathComponent)
                        .font(.system(size: 13))
                        .foregroundStyle(LivelyBrand.mutedForeground)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()
            
            if config != nil {
                Button {
                    showRemoveConfirm = true
                } label: {
                    Label("Remove wallpaper", systemImage: "trash")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 11))
                        .foregroundStyle(LivelyBrand.destructive)
                }
                .buttonStyle(.glass)
                .accessibilityHint("Removes the assigned wallpaper from this display")
                .popover(isPresented: $showRemoveConfirm) {
                    VStack(spacing: 12) {
                        Text("Remove wallpaper?")
                            .font(.system(size: 13, weight: .semibold))
                        
                        HStack(spacing: 8) {
                            Button("Cancel") {
                                showRemoveConfirm = false
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Remove") {
                                configStore.remove(spaceKey: space.spaceKey)
                                showRemoveConfirm = false
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                    }
                    .padding(LivelyBrand.Spacing.lg)
                }
            }
        }
        .padding(.horizontal, LivelyBrand.Spacing.lg)
        .padding(.vertical, LivelyBrand.Spacing.lg)
    }
    
    // MARK: - Display Settings
    
    private var displaySettingsSection: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.15)
                .overlay(LivelyBrand.border.opacity(0.35))
            
            HStack(spacing: 16) {
                // Video Gravity (Fill/Fit) — native popup menu
                HStack(spacing: 6) {
                    Text("Scale:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LivelyBrand.mutedForeground)
                    
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
                    .controlSize(.small)
                    .labelsHidden()
                }
                
                Spacer()
                
                // Mute/Unmute
                Button {
                    let newValue = !currentWallpaper.isMuted
                    configStore.updateDisplaySettings(
                        for: space.spaceKey,
                        gravity: currentWallpaper.videoGravity,
                        isMuted: newValue,
                        volume: newValue ? 0 : currentWallpaper.volume
                    )
                } label: {
                    Image(systemName: currentWallpaper.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(currentWallpaper.isMuted ? LivelyBrand.mutedForeground : LivelyBrand.primary)
                        .padding(6)
                        .background(
                            Circle()
                                .fill(currentWallpaper.isMuted ? Color.clear : LivelyBrand.primary.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(currentWallpaper.isMuted ? "Unmute" : "Mute")
                
                // Volume slider (only when not muted)
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
                    .tint(Color.accentColor)
                    .controlSize(.mini)
                    .frame(width: 60)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, LivelyBrand.Spacing.lg)
            .padding(.vertical, LivelyBrand.Spacing.md)
        }
    }

    // MARK: - Transitions

    /// Mode content swap: subtle enter from bottom, exit via opacity only (Jakub's rule).
    private var modeTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 6)),
            removal: .opacity
        )
    }

    // MARK: Drop Zone
    
    private func dropZone(
        title: String,
        icon: String,
        url: URL?,
        isTargeted: Binding<Bool>,
        onDrop: @escaping @MainActor (URL) -> Void
    ) -> some View {
        Button {
            openFilePicker(onPick: onDrop)
        } label: {
            VStack(spacing: 8) {
                if let url = url {
                    VideoThumbnailView(url: url)
                    
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(LivelyBrand.primary)
                            .font(.system(size: 12))
                        Text(url.lastPathComponent)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, LivelyBrand.Spacing.sm)
                    .padding(.vertical, LivelyBrand.Spacing.xs)
                    .background(LivelyBrand.accent.opacity(0.7))
                    .cornerRadius(LivelyBrand.Radius.sm)
                    
                    if !title.isEmpty {
                        Text(title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(LivelyBrand.mutedForeground)
                    }
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: isTargeted.wrappedValue ? "arrow.down.circle.fill" : icon)
                            .font(.system(size: 28))
                            .symbolEffect(.bounce, value: isTargeted.wrappedValue)
                            .foregroundStyle(isTargeted.wrappedValue ? LivelyBrand.primary : LivelyBrand.mutedForeground)
                        
                        if isTargeted.wrappedValue {
                            Text("Drop Here")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(LivelyBrand.foreground)
                        } else if title.isEmpty {
                            Text("Drop video or click to browse")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(LivelyBrand.mutedForeground)
                        } else {
                            Text(title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(LivelyBrand.mutedForeground)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: LivelyBrand.Radius.sm)
                            .strokeBorder(
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                            )
                            .foregroundStyle(
                                isTargeted.wrappedValue
                                    ? LivelyBrand.primary.opacity(0.68)
                                    : LivelyBrand.border.opacity(0.52)
                            )
                    )
                }
            }
            .padding(LivelyBrand.Spacing.md)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 60)
            .liquidGlass(
                isTargeted.wrappedValue
                    ? .regular.tint(LivelyBrand.primary).opacity(0.16)
                    : .regular.tint(LivelyBrand.accent).opacity(0.10),
                in: RoundedRectangle(cornerRadius: LivelyBrand.Radius.md)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isTargeted.wrappedValue ? 0.98 : 1.0)
        .accessibilityLabel(url == nil ? "\(title.isEmpty ? "Wallpaper" : title), choose video" : "\(title.isEmpty ? "Wallpaper" : title), \(url?.lastPathComponent ?? "video assigned")")
        .accessibilityHint("Drag and drop a video, or click to browse")
        .onDrop(of: [.fileURL], isTargeted: isTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard
                    let data = item as? Data,
                    let url = URL(dataRepresentation: data, relativeTo: nil)
                else { return }

                Task { @MainActor in
                    await acceptURL(url, onAccept: onDrop)
                }
            }
            return true
        }
    }

    // MARK: - Interactions

    private func showError(_ message: String) {
        errorMessage = message
        AccessibilityNotification.Announcement(message).post()
        errorClearTask?.cancel()
        errorClearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { errorMessage = nil }
        }
    }

    // Validates extension, reachability, and codec before accepting a URL.
    // VP9 and AV1 are rejected — AVPlayer wallpaper sessions can't reliably decode them.
    private func acceptURL(_ url: URL, onAccept: @escaping @MainActor (URL) -> Void) async {
        guard isValidLivelyVideoFile(url) else {
            showError("Unsupported format. Use .mp4, .mov, or .m4v")
            return
        }

        let scopeGranted = url.startAccessingSecurityScopedResource()

        guard FileManager.default.fileExists(atPath: url.path) else {
            if scopeGranted { url.stopAccessingSecurityScopedResource() }
            showError("File not found or not accessible.")
            return
        }

        let asset = AVURLAsset(url: url)
        if let tracks = try? await asset.loadTracks(withMediaType: .video) {
            for track in tracks {
                if let descs = try? await track.load(.formatDescriptions) {
                    for desc in descs {
                        let codec = CMFormatDescriptionGetMediaSubType(desc)
                        if codec == kCMVideoCodecType_VP9 || codec == kCMVideoCodecType_AV1 {
                            if scopeGranted { url.stopAccessingSecurityScopedResource() }
                            showError("VP9/AV1 codec not supported. Re-encode to H.264 or HEVC.")
                            return
                        }
                    }
                }
            }
        }

        if scopeGranted { url.stopAccessingSecurityScopedResource() }
        errorMessage = nil
        onAccept(url)
    }

    private func openFilePicker(onPick: @escaping @MainActor (URL) -> Void) {
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
                await self.acceptURL(url, onAccept: onPick)
            }
        }
    }
}
