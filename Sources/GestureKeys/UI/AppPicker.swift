import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AppList {
    struct Entry: Hashable {
        var bundleID: String
        var name: String
    }

    static func name(for bundleID: String?) -> String {
        guard let bundleID else { return "All apps" }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    static var running: [Entry] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.bundleIdentifier.map { Entry(bundleID: $0, name: app.localizedName ?? $0) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// "All apps", any running app, or any app chosen from disk.
struct AppPicker: View {
    @Binding var selection: String?
    @State private var entries: [AppList.Entry] = []

    var body: some View {
        HStack {
            Picker("App", selection: $selection) {
                Text("All apps").tag(String?.none)
                Divider()
                ForEach(entries, id: \.self) { Text($0.name).tag(Optional($0.bundleID)) }
            }
            Button("Choose…", action: choose)
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        var list = AppList.running
        if let selection, !list.contains(where: { $0.bundleID == selection }) {
            list.insert(AppList.Entry(bundleID: selection, name: AppList.name(for: selection)), at: 0)
        }
        entries = list
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        selection = id
        reload()
    }
}
