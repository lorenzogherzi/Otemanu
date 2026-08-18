import AppKit
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape.fill"
        case .about: "info.circle.fill"
        }
    }
}

struct SettingsView: View {
    @State private var selectedPane: SettingsPane = .general
    @ObservedObject private var settings = OtemanuSettings.shared

    var body: some View {
        ZStack {
            SettingsBackdrop()

            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 14) {
                    settingsLayout
                }
            } else {
                settingsLayout
            }
        }
        .frame(minWidth: 720, minHeight: 500)
        .animation(.smooth(duration: 0.24), value: selectedPane)
    }

    private var settingsLayout: some View {
        HStack(spacing: 14) {
            sidebar

            ScrollView {
                detailView
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 30)
                    .padding(.top, 54)
                    .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Otemanu")
                    .font(.title3.weight(.semibold))

                Text("Settings")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 52)
            .padding(.bottom, 20)

            VStack(spacing: 7) {
                ForEach(SettingsPane.allCases) { pane in
                    SettingsSidebarButton(
                        pane: pane,
                        isSelected: pane == selectedPane
                    ) {
                        selectedPane = pane
                    }
                }
            }

            Spacer(minLength: 24)

            HStack(spacing: 8) {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)

                Text("Local Jupyter monitor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 8)
        .frame(width: 204)
        .frame(maxHeight: .infinity)
        .settingsGlassSurface(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedPane {
        case .general:
            generalPane
                .transition(.opacity.combined(with: .move(edge: .leading)))
        case .about:
            aboutPane
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeader(
                title: "General",
                subtitle: "Choose how Otemanu presents running and completed cells."
            )

            SettingsCard {
                VStack(spacing: 0) {
                    SettingsRow(
                        icon: "rectangle.expand.vertical",
                        tint: .purple,
                        title: "Open when execution starts",
                        detail: settings.openIslandWhenExecutionStarts
                            ? "Show the complete monitor as soon as a cell starts."
                            : "Start with the compact busy indicator and elapsed time."
                    ) {
                        Toggle(
                            "Open when execution starts",
                            isOn: $settings.openIslandWhenExecutionStarts
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.regular)
                    }

                    Divider()
                        .padding(.leading, 54)

                    SettingsRow(
                        icon: "rectangle.compress.vertical",
                        tint: .blue,
                        title: "Close after execution",
                        detail: "Automatically hide the island after the completion notice."
                    ) {
                        Toggle(
                            "Close after execution",
                            isOn: $settings.automaticallyHideMonitor
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.regular)
                    }

                    Divider()
                        .padding(.leading, 54)

                    SettingsRow(
                        icon: "timer",
                        tint: .orange,
                        title: "Close delay",
                        detail: settings.automaticallyHideMonitor
                            ? "Keep Cell complete visible before closing."
                            : "Enable automatic closing to use this option."
                    ) {
                        HStack(spacing: 10) {
                            Text(delayLabel)
                                .font(.body.weight(.medium))
                                .foregroundStyle(
                                    settings.automaticallyHideMonitor ? .primary : .tertiary
                                )
                                .frame(minWidth: 68, alignment: .trailing)

                            Stepper(
                                "Close delay",
                                value: $settings.automaticHideDelay,
                                in: 1...30,
                                step: 1
                            )
                            .labelsHidden()
                        }
                    }
                    .disabled(!settings.automaticallyHideMonitor)
                }
            }

            Label {
                Text(
                    settings.automaticallyHideMonitor
                        ? "The completed cell remains in memory only while the notification is visible."
                        : "The completed cell is cleared when you click the island to close it.")
            } icon: {
                Image(systemName: "memorychip")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
    }

    private var aboutPane: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeader(
                title: "About",
                subtitle: "A focused, private monitor for local Jupyter sessions."
            )

            SettingsCard {
                HStack(spacing: 20) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 88, height: 88)
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Otemanu")
                            .font(.title.weight(.semibold))

                        Text("Version \(appVersion) (\(appBuild))")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Label("Monitoring stays on this Mac", systemImage: "lock.shield.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                            .padding(.top, 8)
                    }

                    Spacer(minLength: 0)
                }
                .padding(22)
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Designed for focus", systemImage: "sparkles")
                        .font(.headline)

                    Text(
                        "Otemanu observes the active cell, reports its progress and resources, then releases the completed snapshot when the island disappears."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(22)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.1.0"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "1"
    }

    private var delayLabel: String {
        let seconds = Int(settings.automaticHideDelay.rounded())
        return seconds == 1 ? "1 second" : "\(seconds) seconds"
    }
}

private struct SettingsSidebarButton: View {
    let pane: SettingsPane
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: pane.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .font(.body.weight(.semibold))
                    .frame(width: 22)

                Text(pane.title)
                    .font(.body.weight(isSelected ? .semibold : .regular))

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .settingsSelectionSurface(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SettingsHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.title.weight(.bold))

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsGlassSurface(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct SettingsRow<Accessory: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(color: tint.opacity(0.24), radius: 5, y: 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 18)

            accessory
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }
}

private struct SettingsBackdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            RadialGradient(
                colors: [Color.accentColor.opacity(0.16), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 470
            )

            RadialGradient(
                colors: [Color.cyan.opacity(0.09), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    @ViewBuilder
    fileprivate func settingsGlassSurface<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay {
                    shape.stroke(.white.opacity(0.12), lineWidth: 0.5)
                }
        }
    }

    @ViewBuilder
    fileprivate func settingsSelectionSurface(isSelected: Bool) -> some View {
        if isSelected {
            if #available(macOS 26.0, *) {
                glassEffect(
                    .regular.tint(Color.accentColor.opacity(0.22)).interactive(),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            } else {
                background(
                    Color.accentColor.opacity(0.16),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
        } else {
            background(.clear)
        }
    }
}
