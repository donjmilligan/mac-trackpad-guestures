import CoreGraphics
import Foundation

public enum SwipeDirection: String, Codable, CaseIterable, Sendable {
    case up, down, left, right

    public var arrow: String {
        switch self {
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        }
    }
}

public enum Trigger: Hashable, Codable, Sendable {
    case swipe(fingers: Int, direction: SwipeDirection)
    case tap(fingers: Int)
    case shape(name: String)

    public var displayName: String {
        switch self {
        case let .swipe(fingers, direction): "\(fingers)-finger swipe \(direction.rawValue) \(direction.arrow)"
        case let .tap(fingers): "\(fingers)-finger tap"
        case let .shape(name): "Draw “\(name)”"
        }
    }
}

public struct ModifierSet: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = ModifierSet(rawValue: 1 << 0)
    public static let option = ModifierSet(rawValue: 1 << 1)
    public static let shift = ModifierSet(rawValue: 1 << 2)
    public static let command = ModifierSet(rawValue: 1 << 3)
    public static let function = ModifierSet(rawValue: 1 << 4)

    public static let ordered: [(ModifierSet, String)] = [
        (.function, "fn"), (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
    ]

    public var symbols: String {
        Self.ordered.filter { contains($0.0) }.map(\.1).joined()
    }
}

public struct KeyCombo: Hashable, Codable, Sendable {
    public var keyCode: UInt16
    public var modifiers: ModifierSet

    public init(keyCode: UInt16, modifiers: ModifierSet) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum GestureAction: Hashable, Codable, Sendable {
    case keyboardShortcut(combo: KeyCombo)
    case shellCommand(command: String)
}

public struct GestureBinding: Identifiable, Hashable, Codable, Sendable {
    public var id = UUID()
    public var trigger: Trigger
    public var action: GestureAction
    /// Bundle identifier of the app this binding is limited to; nil means every app.
    /// An app-specific binding wins over a global one for the same gesture.
    public var appBundleID: String?
    public var enabled = true

    public init(trigger: Trigger, action: GestureAction, appBundleID: String? = nil) {
        self.trigger = trigger
        self.action = action
        self.appBundleID = appBundleID
    }
}

/// A named shape with one or more recorded samples. More samples make recognition more forgiving.
public struct ShapeTemplate: Identifiable, Hashable, Codable, Sendable {
    public var id = UUID()
    public var name: String
    public var samples: [[CGPoint]]

    public init(name: String, samples: [[CGPoint]]) {
        self.name = name
        self.samples = samples
    }
}

public struct EngineSettings: Hashable, Codable, Sendable {
    /// Average finger travel (mm) before a multi-finger movement counts as a swipe.
    public var swipeDistanceMM = 15.0
    /// Longest touch (seconds) that still counts as a tap.
    public var tapMaxDuration = 0.25
    /// Most any finger may move (mm) during a tap.
    public var tapMaxMovementMM = 3.0
    /// Modifiers that must be held to draw a shape with one finger. Empty disables drawing.
    public var drawModifiers: ModifierSet = [.option]
    /// Recognizer score (0...1) a stroke must reach to count as a shape.
    public var minimumShapeScore = 0.80

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EngineSettings()
        swipeDistanceMM = try c.decodeIfPresent(Double.self, forKey: .swipeDistanceMM) ?? d.swipeDistanceMM
        tapMaxDuration = try c.decodeIfPresent(Double.self, forKey: .tapMaxDuration) ?? d.tapMaxDuration
        tapMaxMovementMM = try c.decodeIfPresent(Double.self, forKey: .tapMaxMovementMM) ?? d.tapMaxMovementMM
        drawModifiers = try c.decodeIfPresent(ModifierSet.self, forKey: .drawModifiers) ?? d.drawModifiers
        minimumShapeScore = try c.decodeIfPresent(Double.self, forKey: .minimumShapeScore) ?? d.minimumShapeScore
    }
}

/// Everything persisted in config.json (shapes live in their own file).
public struct AppConfig: Hashable, Codable, Sendable {
    public var enabled = true
    public var showHUD = true
    public var engine = EngineSettings()
    public var bindings: [GestureBinding] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        showHUD = try c.decodeIfPresent(Bool.self, forKey: .showHUD) ?? d.showHUD
        engine = try c.decodeIfPresent(EngineSettings.self, forKey: .engine) ?? d.engine
        bindings = try c.decodeIfPresent([GestureBinding].self, forKey: .bindings) ?? d.bindings
    }

    /// The binding to run for `trigger` when `bundleID` is frontmost.
    public func binding(for trigger: Trigger, frontmostApp bundleID: String?) -> GestureBinding? {
        let candidates = bindings.filter { $0.enabled && $0.trigger == trigger }
        return candidates.first { $0.appBundleID != nil && $0.appBundleID == bundleID }
            ?? candidates.first { $0.appBundleID == nil }
    }
}
