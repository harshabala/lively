import SwiftUI
import AppKit

public struct AboutView: View {
    public init() {}

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    public var body: some View {
        VStack(spacing: LivelyBrand.Spacing.lg) {
            VStack(spacing: LivelyBrand.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(LivelyBrand.primary.opacity(0.12))
                        .frame(width: 64, height: 64)
                    if let appIcon = NSImage(named: NSImage.applicationIconName) {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                    } else {
                        Image(systemName: "play.tv.fill")
                            .font(.largeTitle.weight(.semibold))
                            .foregroundStyle(LivelyBrand.primary)
                    }
                }

                Text("Lively")
                    .font(LivelyBrand.Typography.title)
                Text(appVersion)
                    .font(LivelyBrand.Typography.mono)
                    .foregroundStyle(LivelyBrand.mutedForeground)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, LivelyBrand.Spacing.sm)

            VStack(spacing: 0) {
                linkRow(title: "View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right", url: githubURL)
                Divider().overlay(LivelyBrand.border.opacity(0.3))
                linkRow(title: "Report an Issue", systemImage: "exclamationmark.bubble", url: issuesURL)
                Divider().overlay(LivelyBrand.border.opacity(0.3))
                linkRow(title: "Privacy Policy", systemImage: "hand.raised", url: privacyURL)
            }
            .background(
                RoundedRectangle(cornerRadius: LivelyBrand.Radius.lg)
                    .fill(LivelyBrand.card.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LivelyBrand.Radius.lg)
                    .strokeBorder(LivelyBrand.border.opacity(0.35))
            )

            firstLaunchHelpCard

            Text(String(format: "© %d Harsha Balakrishnan. All rights reserved.", Calendar.current.component(.year, from: Date())))
                .font(LivelyBrand.Typography.footnote)
                .foregroundStyle(LivelyBrand.mutedForeground)
                .frame(maxWidth: .infinity)
                .padding(.bottom, LivelyBrand.Spacing.sm)
        }
    }

    private var firstLaunchHelpCard: some View {
        VStack(alignment: .leading, spacing: LivelyBrand.Spacing.sm) {
            Text("First launch help")
                .font(LivelyBrand.Typography.section)
            Text("Lively lives in the menu bar (top-right). There is no Dock icon.")
                .font(LivelyBrand.Typography.footnote)
                .foregroundStyle(LivelyBrand.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            Text("If macOS blocks the app after download, run once in Terminal:")
                .font(LivelyBrand.Typography.footnote)
                .foregroundStyle(LivelyBrand.mutedForeground)
            Text("xattr -dr com.apple.quarantine /Applications/Lively.app")
                .font(LivelyBrand.Typography.mono)
                .foregroundStyle(LivelyBrand.foreground)
                .textSelection(.enabled)
                .padding(LivelyBrand.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: LivelyBrand.Radius.sm)
                        .fill(LivelyBrand.controlFill)
                )
            Text("Or right-click Lively.app → Open, then confirm. Prefer the DMG: drag Lively into Applications.")
                .font(LivelyBrand.Typography.footnote)
                .foregroundStyle(LivelyBrand.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(LivelyBrand.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.lg)
                .fill(LivelyBrand.card.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.lg)
                .strokeBorder(LivelyBrand.border.opacity(0.35))
        )
        .accessibilityElement(children: .combine)
    }

    private func linkRow(title: String, systemImage: String, url: URL?) -> some View {
        Button {
            if let url {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: LivelyBrand.Spacing.md) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LivelyBrand.primary)
                    .frame(width: 20)
                Text(title)
                    .font(LivelyBrand.Typography.body.weight(.medium))
                    .foregroundStyle(LivelyBrand.foreground)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LivelyBrand.mutedForeground)
            }
            .padding(.horizontal, LivelyBrand.Spacing.lg)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .livelyFocusRing(cornerRadius: LivelyBrand.Radius.sm)
        .disabled(url == nil)
        .accessibilityLabel(title)
        .accessibilityHint("Opens in browser")
    }

    private var githubURL: URL? {
        URL(string: "https://github.com/harshabala/Lively")
    }

    private var issuesURL: URL? {
        URL(string: "https://github.com/harshabala/Lively/issues")
    }

    private var privacyURL: URL? {
        URL(string: "https://github.com/harshabala/Lively/blob/master/README.md#privacy")
    }
}
