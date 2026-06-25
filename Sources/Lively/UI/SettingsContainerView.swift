import SwiftUI

public enum LivelyTab: Hashable {
    case displays
    case settings
}

// MARK: - Primary Tab Bar

private struct PrimaryTabBar: View {
    @Binding var selection: LivelyTab
    @Namespace private var tabIndicator

    var body: some View {
        HStack(spacing: 2) {
            tabButton("Displays", tab: .displays)
            tabButton("Settings", tab: .settings)
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private func tabButton(_ label: String, tab: LivelyTab) -> some View {
        Button {
            withAnimation(LivelyBrand.Motion.fast) { selection = tab }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .hidden()
                .overlay {
                    Text(label)
                        .font(.system(size: 12, weight: selection == tab ? .semibold : .regular))
                        .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background {
                    if selection == tab {
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

public struct SettingsContainerView: View {
    @ObservedObject public var spaceMonitor: SpaceMonitor
    public let configStore: ConfigStore
    @EnvironmentObject var wallpaperController: WallpaperController
    
    @State private var selectedTab: LivelyTab = .displays
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(spaceMonitor: SpaceMonitor, configStore: ConfigStore) {
        self.spaceMonitor = spaceMonitor
        self.configStore = configStore
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Custom Navigation Header
            HStack {
                PrimaryTabBar(selection: $selectedTab)
                
                Spacer()
                
                // Action Chip
                HStack(spacing: 12) {
                    Button(action: {
                        wallpaperController.togglePause()
                    }) {
                        Image(systemName: wallpaperController.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(wallpaperController.isPaused ? "Resume Wallpapers" : "Pause Wallpapers")
                    
                    Divider()
                        .frame(height: 12)
                        .background(Color.secondary.opacity(0.5))
                    
                    Button(action: {
                        NSApplication.shared.terminate(nil)
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Quit Lively")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
            .padding(.horizontal, LivelyBrand.Spacing.xl)
            .padding(.top, LivelyBrand.Spacing.lg)
            .padding(.bottom, LivelyBrand.Spacing.md)
            
            Divider()
                .overlay(LivelyBrand.border.opacity(0.45))
            
            // Content Area
            ZStack {
                switch selectedTab {
                case .displays:
                    DisplaysView(spaceMonitor: spaceMonitor, configStore: configStore)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 6)),
                            removal: .opacity.combined(with: .offset(y: -4))
                        ))
                case .settings:
                    PreferencesView(configStore: configStore)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 6)),
                            removal: .opacity.combined(with: .offset(y: -4))
                        ))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : LivelyBrand.Motion.normal, value: selectedTab)
        }
        .frame(width: 480, height: 560)
        .background(
            ZStack {
                LivelyBrand.backgroundGradient
                    .ignoresSafeArea()
                    .opacity(0.72)
                
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
            }
        )
    }
}
