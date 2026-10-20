import GestureCore
import ServiceManagement
import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var controller: GestureController
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Toggle("Gestures enabled", isOn: $store.config.enabled)
                Toggle("Show a confirmation when a gesture fires", isOn: $store.config.showHUD)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section("Drawing") {
                LabeledContent("Hold to draw") {
                    HStack {
                        ForEach(ModifierSet.ordered, id: \.1) { modifier, symbol in
                            Toggle(symbol, isOn: drawModifier(modifier)).toggleStyle(.button)
                        }
                    }
                }
                slider("Required match", value: $store.config.engine.minimumShapeScore, in: 0.6...0.95,
                       format: { "\(Int($0 * 100))%" })
                Text("Drawing is off when no key is selected. If you pick fn, set “Press 🌐 key to” to “Do Nothing” in System Settings › Keyboard.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Sensitivity") {
                slider("Swipe distance", value: $store.config.engine.swipeDistanceMM, in: 6...40,
                       format: { "\(Int($0)) mm" })
                slider("Rotate angle", value: $store.config.engine.rotateAngleDegrees, in: 5...45,
                       format: { "\(Int($0))°" })
                slider("Tap max duration", value: $store.config.engine.tapMaxDuration, in: 0.1...0.5,
                       format: { "\(Int($0 * 1000)) ms" })
                slider("Tap max movement", value: $store.config.engine.tapMaxMovementMM, in: 1...10,
                       format: { String(format: "%.1f mm", $0) })
                slider("Multi-tap window", value: $store.config.engine.multiTapInterval, in: 0.2...0.8,
                       format: { "\(Int($0 * 1000)) ms" })
            }

            Section("Status") {
                LabeledContent("Accessibility") {
                    if controller.accessibilityTrusted {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant…") {
                            controller.requestAccessibility()
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                LabeledContent("Trackpads") {
                    HStack {
                        Text(controller.listenerFailed ? "MultitouchSupport unavailable" : "\(controller.deviceCount) connected")
                        Button("Restart Listener") { controller.restartListener() }
                    }
                }
                LabeledContent("Config files") {
                    Button("Show in Finder") { NSWorkspace.shared.open(store.directory) }
                }
            }

            Section("Avoiding conflicts with macOS") {
                Text("macOS gestures still fire alongside GestureKeys. In System Settings › Trackpad › More Gestures, turn off any that use the same finger count — typically “Swipe between full-screen apps”, “Mission Control”, “App Exposé” (4 fingers) and “Launchpad” / “Show Desktop” (pinch with thumb and three fingers).")
                    .font(.callout)
                Button("Open Trackpad Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func drawModifier(_ modifier: ModifierSet) -> Binding<Bool> {
        Binding(
            get: { store.config.engine.drawModifiers.contains(modifier) },
            set: { on in
                if on { store.config.engine.drawModifiers.insert(modifier) } else { store.config.engine.drawModifiers.remove(modifier) }
            }
        )
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>,
                        format: @escaping (Double) -> String) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range)
                Text(format(value.wrappedValue))
                    .monospacedDigit()
                    .frame(width: 64, alignment: .trailing)
            }
        }
    }
}
