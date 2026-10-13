import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct LoggerView: View {
    /// When true, shows the full always-visible logs table used in Settings → Logs.
    public var embeddedInSettings: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var logStore = LogStore.shared
    @ViewState private var isExpanded = false
    @ViewState private var isCopied = false

    public init(embeddedInSettings: Bool = false) {
        self.embeddedInSettings = embeddedInSettings
    }

    public var body: some View {
        if embeddedInSettings {
            settingsLogs
        } else {
            compactLogs
        }
    }

    // MARK: - Settings pane

    private var settingsLogs: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Level")
                    .frame(width: 72, alignment: .leading)
                Text("Message")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Time")
                    .frame(width: 148, alignment: .trailing)
            }
            .font(LivelyBrand.Typography.footnote.weight(.semibold))
            .foregroundStyle(LivelyBrand.mutedForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))

            Divider().background(LivelyBrand.border)

            // Internal scroll only — does not grow the window.
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if logStore.entries.isEmpty {
                            emptyState
                        } else {
                            ForEach(logStore.entries) { entry in
                                logRow(entry)
                                    .id(entry.id)
                                Divider().background(LivelyBrand.border.opacity(0.5))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: logStore.entries.count) { _, _ in
                    if let last = logStore.entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onAppear {
                    if let last = logStore.entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider().background(LivelyBrand.border)

            HStack(spacing: LivelyBrand.Spacing.sm) {
                Button {
                    copyLogs()
                } label: {
                    HStack(spacing: 5) {
                        if isCopied {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(LivelyBrand.foreground)
                        }
                        Text(isCopied ? "Copied" : "Copy Logs")
                    }
                    .font(LivelyBrand.Typography.caption.weight(.medium))
                    .foregroundStyle(LivelyBrand.foreground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: LivelyBrand.Radius.sm)
                            .strokeBorder(LivelyBrand.border.opacity(0.55), lineWidth: 1)
                    )
                }
                .buttonStyle(PressScaleButtonStyle())
                .focusEffectDisabled()
                .disabled(logStore.entries.isEmpty)
                .accessibilityLabel(isCopied ? "Logs copied" : "Copy logs")

                Spacer()

                Button {
                    downloadLogs()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Download Logs")
                            .font(LivelyBrand.Typography.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: LivelyBrand.Radius.sm)
                            .fill(LivelyBrand.primary)
                    )
                }
                .buttonStyle(PressScaleButtonStyle())
                .focusEffectDisabled()
                .disabled(logStore.entries.isEmpty)
                .accessibilityLabel("Download logs")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.lg)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LivelyBrand.Radius.lg)
                .strokeBorder(LivelyBrand.border.opacity(0.55), lineWidth: 1)
        )
        .animation(reduceMotion ? nil : LivelyBrand.Motion.fast, value: isCopied)
    }

    private var emptyState: some View {
        VStack(spacing: LivelyBrand.Spacing.sm) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(LivelyBrand.mutedForeground)
            Text("No activity yet")
                .font(LivelyBrand.Typography.body.weight(.semibold))
                .foregroundStyle(LivelyBrand.foreground)
            Text("Logs will appear here as Lively runs.")
                .font(LivelyBrand.Typography.caption)
                .foregroundStyle(LivelyBrand.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(entry.level.rawValue)
                .font(LivelyBrand.Typography.footnote.weight(.semibold))
                .foregroundStyle(levelColor(entry.level))
                .frame(width: 72, alignment: .leading)

            Text(entry.message)
                .font(LivelyBrand.Typography.footnote)
                .foregroundStyle(LivelyBrand.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text(entry.timeString)
                .font(LivelyBrand.Typography.footnote)
                .foregroundStyle(LivelyBrand.mutedForeground)
                .frame(width: 148, alignment: .trailing)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.level.rawValue): \(entry.message), \(entry.timeString)")
    }

    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .error: return LivelyBrand.destructive
        case .warning: return Color(nsColor: .systemOrange)
        case .info: return LivelyBrand.foreground
        case .debug: return LivelyBrand.mutedForeground
        }
    }

    // MARK: - Compact

    private var compactLogs: some View {
        VStack(spacing: 0) {
            HStack {
                Text("View and copy application logs for troubleshooting.")
                    .font(LivelyBrand.Typography.caption)
                    .foregroundStyle(LivelyBrand.mutedForeground)
                Spacer()
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Text(isExpanded ? "Hide Logs" : "View Logs")
                            .font(LivelyBrand.Typography.caption)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(PressScaleButtonStyle())
                .focusEffectDisabled()
            }

            if isExpanded {
                settingsLogs
                    .padding(.top, 8)
                    .frame(height: 280)
            }
        }
        .animation(reduceMotion ? nil : LivelyBrand.Motion.normal, value: isExpanded)
    }

    // MARK: - Actions

    private func copyLogs() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnosticsText(), forType: .string)
        isCopied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            isCopied = false
        }
    }

    private func downloadLogs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "lively-logs-\(dateStamp()).txt"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try diagnosticsText().write(to: url, atomically: true, encoding: .utf8)
                LivelyLogger.config.info("Exported logs to \(url.lastPathComponent)")
            } catch {
                LivelyLogger.config.error("Failed to export logs: \(error.localizedDescription)")
            }
        }
    }

    /// Redacted support report (versions, display count, preferences, recent log).
    private func diagnosticsText() -> String {
        let prefs = AppPreferences.shared
        return logStore.diagnosticsReport(
            displayCount: NSScreen.screens.count,
            preferences: [
                "pauseOnBattery": String(prefs.pauseOnBattery),
                "batteryPauseThreshold": String(Int(prefs.batteryPauseThreshold)),
                "playbackQuality": prefs.playbackQuality.rawValue,
                "loopBehavior": prefs.loopBehavior.rawValue,
                "hardwareDecoding": String(prefs.hardwareDecoding),
                "maxResolution": prefs.maxResolution.rawValue,
                "checkForUpdates": String(prefs.checkForUpdates),
            ]
        )
    }

    private func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
