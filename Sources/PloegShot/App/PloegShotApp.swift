import SwiftUI

@main
struct PloegShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            VStack(alignment: .leading, spacing: 8) {
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
                Text("Area: ⌘⇧2  •  Previous area: ⌘⇧R  •  Display: ⌘⇧F")
                Text("Screen Recording permission is required.")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 360)
        }
    }
}
