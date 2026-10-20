import Combine
import CoreGraphics
import Foundation
import GestureCore
import os

/// Loads and saves ~/Library/Application Support/GestureKeys/{config,shapes}.json.
/// Both files are pretty-printed so they can be edited by hand while the app is quit.
final class ConfigStore: ObservableObject {
    @Published var config: AppConfig { didSet { if config != oldValue { save(config, to: configURL) } } }
    @Published var shapes: [ShapeTemplate] { didSet { if shapes != oldValue { save(shapes, to: shapesURL) } } }

    let directory: URL
    /// True when there was no config file yet, i.e. the app has never run.
    let isFirstLaunch: Bool
    private let configURL: URL
    private let shapesURL: URL
    private static let log = Logger(subsystem: "com.donjmilligan.GestureKeys", category: "config")

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GestureKeys", isDirectory: true)
        configURL = directory.appendingPathComponent("config.json")
        shapesURL = directory.appendingPathComponent("shapes.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        isFirstLaunch = !FileManager.default.fileExists(atPath: configURL.path)

        config = Self.load(AppConfig.self, from: configURL) ?? AppConfig()
        shapes = Self.load([ShapeTemplate].self, from: shapesURL) ?? BuiltInShapes.all
        if !FileManager.default.fileExists(atPath: configURL.path) { save(config, to: configURL) }
        if !FileManager.default.fileExists(atPath: shapesURL.path) { save(shapes, to: shapesURL) }
    }

    func upsert(_ binding: GestureBinding) {
        if let index = config.bindings.firstIndex(where: { $0.id == binding.id }) {
            config.bindings[index] = binding
        } else {
            config.bindings.append(binding)
        }
    }

    // MARK: Profiles

    func addProfile(named name: String, copying source: Profile? = nil) {
        var profile = Profile(name: name)
        // Fresh IDs so the copies are independent rows in the bindings table.
        profile.bindings = source?.bindings.map { var b = $0; b.id = UUID(); return b } ?? []
        config.profiles.append(profile)
        config.activeProfileID = profile.id
    }

    func deleteActiveProfile() {
        guard config.profiles.count > 1 else { return }
        let index = config.activeProfileIndex
        config.profiles.remove(at: index)
        config.activeProfileID = config.profiles[max(0, index - 1)].id
    }

    /// Adds a recorded stroke to the shape called `name`, creating the shape if needed.
    func addSample(_ stroke: [CGPoint], toShapeNamed name: String) {
        guard let normalized = ShapeRecognizer.normalize(stroke) else { return }
        // Keep the file compact: 64 points rounded to 3 decimals is plenty.
        let sample = normalized.map { CGPoint(x: ($0.x * 1000).rounded() / 1000, y: ($0.y * 1000).rounded() / 1000) }
        if let index = shapes.firstIndex(where: { $0.name == name }) {
            shapes[index].samples.append(sample)
        } else {
            shapes.append(ShapeTemplate(name: name, samples: [sample]))
        }
    }

    func renameShape(id: UUID, to newName: String) {
        guard let index = shapes.firstIndex(where: { $0.id == id }) else { return }
        let oldName = shapes[index].name
        shapes[index].name = newName
        for p in config.profiles.indices {
            for i in config.profiles[p].bindings.indices where config.profiles[p].bindings[i].trigger == .shape(name: oldName) {
                config.profiles[p].bindings[i].trigger = .shape(name: newName)
            }
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            // Don't clobber a hand-edited file with a typo in it; set it aside and start fresh.
            let backup = url.appendingPathExtension("broken-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: url, to: backup)
            log.error("Couldn't parse \(url.lastPathComponent): \(error.localizedDescription). Moved to \(backup.lastPathComponent)")
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            Self.log.error("Couldn't save \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
