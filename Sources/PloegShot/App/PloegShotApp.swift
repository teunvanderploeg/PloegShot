import AppKit
import CoreGraphics
import PloegKit
import SwiftUI

@main
struct PloegShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { PloegShotSettingsView() }
    }
}

private enum ShotSettingsPage: String, CaseIterable, Identifiable {
    case shortcuts = "Shortcuts"
    case permissions = "Permissions"
    case about = "About"

    var id: Self { self }
    var symbol: String {
        switch self {
        case .shortcuts: "keyboard"
        case .permissions: "lock.shield"
        case .about: "info.circle"
        }
    }
}

struct PloegShotSettingsView: View {
    @StateObject private var hotKeys = HotKeySettings.shared
    @State private var shortcutFeedback: String?
    @State private var page: ShotSettingsPage = .shortcuts
    @State private var hasScreenPermission = false
    var isDesignPreview = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(PloegTheme.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PloegSectionHeader(page.rawValue, subtitle: subtitle)
                    switch page {
                    case .shortcuts: shortcuts
                    case .permissions: permissions
                    case .about: about
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(PloegTheme.canvas)
        }
        .frame(width: 800, height: 550)
        .foregroundStyle(PloegTheme.ink)
        .tint(PloegTheme.accent)
        .onAppear { refreshPermission() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 10) {
                PloegAppIcon(.shot, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("PloegShot").font(.system(size: 17, weight: .semibold))
                    Text("Capture and annotate").font(.system(size: 11)).foregroundStyle(PloegTheme.muted)
                }
            }
            .padding(.horizontal, 8)

            VStack(spacing: 5) {
                ForEach(ShotSettingsPage.allCases) { item in
                    Button { page = item } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .font(.system(size: 13, weight: page == item ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .frame(height: 40)
                            .foregroundStyle(page == item ? PloegTheme.accent : PloegTheme.ink)
                            .background(page == item ? PloegTheme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(page == item ? "Selected" : "")
                }
            }
            Spacer()
            Label("Images stay on your Mac", systemImage: "desktopcomputer")
                .font(.system(size: 11))
                .foregroundStyle(PloegTheme.muted)
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 26)
        .frame(width: PloegTheme.sidebarWidth)
        .background(PloegTheme.sidebar)
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 18) {
            PloegCard(title: "Capture shortcuts", systemImage: "keyboard") {
                VStack(spacing: 0) {
                    shortcutRow("Capture area", description: "Choose a region on any display.", action: .area, binding: $hotKeys.area)
                    Divider().overlay(PloegTheme.line).padding(.vertical, 16)
                    shortcutRow("Previous area", description: "Adjust and reuse the last region.", action: .repeatArea, binding: $hotKeys.repeatArea)
                    Divider().overlay(PloegTheme.line).padding(.vertical, 16)
                    shortcutRow("Full screen", description: "Choose the display to capture.", action: .screen, binding: $hotKeys.screen)
                }
            }

            if let shortcutFeedback {
                Label(shortcutFeedback, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(PloegTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 18) {
                Text("Click a shortcut, then press a new combination. Press Escape to cancel.")
                    .font(.system(size: 12))
                    .foregroundStyle(PloegTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Restore defaults") { hotKeys.reset() }
                    .buttonStyle(PloegSecondaryButtonStyle())
                    .disabled(isDesignPreview)
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 18) {
            PloegCard(title: "Screen recording", systemImage: "rectangle.inset.filled.and.person.filled") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Text("Capture your screen").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        PloegStatusPill(hasScreenPermission ? "Allowed" : "Needs permission", systemImage: hasScreenPermission ? "checkmark.circle.fill" : "exclamationmark.circle.fill", color: hasScreenPermission ? PloegTheme.success : PloegTheme.warning)
                    }
                    Text("macOS requires Screen Recording permission before PloegShot can capture an area or display.")
                        .font(.system(size: 13))
                        .foregroundStyle(PloegTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Open System Settings") {
                            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(PloegPrimaryButtonStyle())
                        .disabled(isDesignPreview)
                        Button("Check again") { refreshPermission() }
                            .buttonStyle(PloegSecondaryButtonStyle())
                    }
                }
            }
            Text("PloegShot processes screenshots locally. Capture previews last for this app session; copied and saved images go where you choose.")
                .font(.system(size: 12))
                .foregroundStyle(PloegTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 18) {
            PloegCard {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 16) {
                        PloegAppIcon(.shot, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PloegShot").font(.system(size: 22, weight: .semibold))
                            Text("Capture, annotate and share.").font(.system(size: 13)).foregroundStyle(PloegTheme.muted)
                        }
                    }
                    Text("Capture an area or display, then add arrows, text, shapes, highlights or redactions. Copy or save at the original screenshot resolution.")
                        .font(.system(size: 13))
                        .foregroundStyle(PloegTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider().overlay(PloegTheme.line)
                    Label("Part of the Ploeg family", systemImage: "square.grid.2x2")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PloegTheme.muted)
                }
            }
        }
    }

    private var subtitle: String {
        switch page {
        case .shortcuts: "Choose how you start a capture."
        case .permissions: "Control access to your screen."
        case .about: "A focused screenshot tool for your Mac."
        }
    }

    private func refreshPermission() {
        hasScreenPermission = isDesignPreview || CGPreflightScreenCaptureAccess()
    }

    private func shortcutRow(_ title: String, description: String, action: CaptureHotKeyAction, binding: Binding<CaptureHotKey>) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(description).font(.system(size: 11)).foregroundStyle(PloegTheme.muted)
            }
            Spacer()
            HotKeyRecorder(
                hotKey: isDesignPreview ? .constant(binding.wrappedValue) : binding,
                validationMessage: { hotKeys.conflictDescription(for: $0, excluding: action) },
                onFeedback: { shortcutFeedback = $0 }
            )
            .frame(width: 136, height: 36)
            .disabled(isDesignPreview)
            .accessibilityLabel(title + " shortcut")
        }
    }
}
