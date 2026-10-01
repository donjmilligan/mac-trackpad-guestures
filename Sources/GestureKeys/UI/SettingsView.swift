import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var controller: GestureController

    var body: some View {
        VStack(spacing: 0) {
            if !controller.accessibilityTrusted {
                PermissionBanner()
            }
            TabView {
                BindingsView()
                    .tabItem { Label("Gestures", systemImage: "hand.raised") }
                ShapesView()
                    .tabItem { Label("Shapes", systemImage: "scribble") }
                PreferencesView()
                    .tabItem { Label("Preferences", systemImage: "gearshape") }
            }
            .padding()
        }
        .frame(minWidth: 720, minHeight: 500)
    }
}

private struct PermissionBanner: View {
    @EnvironmentObject var controller: GestureController

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text("GestureKeys needs Accessibility permission to send keyboard shortcuts.")
            Spacer()
            Button("Open System Settings") {
                controller.requestAccessibility()
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
        .padding(10)
        .background(.yellow.opacity(0.15))
    }
}
