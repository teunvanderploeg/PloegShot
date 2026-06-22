import SwiftUI

@main
struct PloegShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            PloegShotSettingsView()
        }
    }
}

struct PloegShotSettingsView: View {
    @StateObject private var hotKeys = HotKeySettings.shared
    @State private var shortcutFeedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                if let logo = AppResources.logo {
                    Image(nsImage: logo)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Text("PloegShot").font(.title2.bold())
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                shortcutRow("Capture area", action: .area, binding: $hotKeys.area)
                shortcutRow("Previous area", action: .repeatArea, binding: $hotKeys.repeatArea)
                shortcutRow("Full screen", action: .screen, binding: $hotKeys.screen)
            }
            if let shortcutFeedback {
                Text(shortcutFeedback)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Text("Click a shortcut, then press a new combination.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restore Defaults") { hotKeys.reset() }
            }
            Text("Screen Recording permission is required.")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 430)
    }

    @ViewBuilder
    private func shortcutRow(_ title: String, action: CaptureHotKeyAction, binding: Binding<CaptureHotKey>) -> some View {
        GridRow {
            Text(title)
            HotKeyRecorder(
                hotKey: binding,
                validationMessage: { hotKeys.conflictDescription(for: $0, excluding: action) },
                onFeedback: { shortcutFeedback = $0 }
            )
        }
    }
}
