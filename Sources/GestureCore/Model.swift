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

/// Turning the hand like a knob, as seen from above the trackpad. Right is clockwise.
public enum RotateDirection: String, Codable, CaseIterable, Sendable {
    case left, right

    public var arrow: String {
        switch self {
        case .left: "↺"
        case .right: "↻"
        }
    }
}

public enum Trigger: Hashable, Codable, Sendable {
    case swipe(fingers: Int, direction: SwipeDirection)
    /// Turn the hand, then optionally drag in `then` before lifting.
    case rotate(fingers: Int, direction: RotateDirection, then: SwipeDirection? = nil)
    /// `taps` consecutive taps with the same number of fingers, e.g. 2 for a double tap.
    case tap(fingers: Int, taps: Int = 1)
    case shape(name: String)

    public var displayName: String {
        switch self {
        case let .swipe(fingers, direction): "\(fingers)-finger swipe \(direction.rawValue) \(direction.arrow)"
        case let .rotate(fingers, direction, then):
            "\(fingers)-finger rotate \(direction.rawValue) \(direction.arrow)" + (then.map { " then swipe \($0.rawValue) \($0.arrow)" } ?? "")
        case let .tap(fingers, taps): "\(fingers)-finger \(Self.tapName(taps))"
        case let .shape(name): "Draw “\(name)”"
        }
    }

    public static func tapName(_ taps: Int) -> String {
        switch taps {
        case 1: "tap"
        case 2: "double tap"
        case 3: "triple tap"
        default: "\(taps)× tap"
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.tap) {
            // Configs from before multi-taps have no `taps`.
            let tap = try c.nestedContainer(keyedBy: TapCodingKeys.self, forKey: .tap)
            self = try .tap(fingers: tap.decode(Int.self, forKey: .fingers),
                            taps: tap.decodeIfPresent(Int.self, forKey: .taps) ?? 1)
        } else if c.contains(.swipe) {
            let swipe = try c.nestedContainer(keyedBy: SwipeCodingKeys.self, forKey: .swipe)
            self = try .swipe(fingers: swipe.decode(Int.self, forKey: .fingers),
                              direction: swipe.decode(SwipeDirection.self, forKey: .direction))
        } else if c.contains(.rotate) {
            let rotate = try c.nestedContainer(keyedBy: RotateCodingKeys.self, forKey: .rotate)
            self = try .rotate(fingers: rotate.decode(Int.self, forKey: .fingers),
                               direction: rotate.decode(RotateDirection.self, forKey: .direction),
                               then: rotate.decodeIfPresent(SwipeDirection.self, forKey: .then))
        } else {
            let shape = try c.nestedContainer(keyedBy: ShapeCodingKeys.self, forKey: .shape)
            self = try .shape(name: shape.decode(String.self, forKey: .name))
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
    case system(action: SystemAction)
}

/// Inputs a Mac keyboard can't send (or that the shortcut recorder can't capture): mouse buttons, media keys,
/// and the window-management gestures you lose by turning off macOS's own trackpad gestures.
public enum SystemAction: String, Codable, CaseIterable, Sendable {
    case back, forward, middleClick
    case playPause, nextTrack, previousTrack
    case volumeUp, volumeDown, mute
    case brightnessUp, brightnessDown, sleepDisplay
    case missionControl, appExpose, showDesktop
    case nextProfile

    public var title: String {
        switch self {
        case .back: "Back"
        case .forward: "Forward"
        case .middleClick: "Middle Click"
        case .playPause: "Play / Pause"
        case .nextTrack: "Next Track"
        case .previousTrack: "Previous Track"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute"
        case .brightnessUp: "Brightness Up"
        case .brightnessDown: "Brightness Down"
        case .sleepDisplay: "Sleep Display"
        case .missionControl: "Mission Control"
        case .appExpose: "App Exposé"
        case .showDesktop: "Show Desktop"
        case .nextProfile: "Next Profile"
        }
    }

    /// Picker sections, in display order.
    public static let groups: [(String, [SystemAction])] = [
        ("Navigation", [.back, .forward, .middleClick]),
        ("Media", [.playPause, .nextTrack, .previousTrack, .volumeUp, .volumeDown, .mute]),
        ("Display", [.brightnessUp, .brightnessDown, .sleepDisplay]),
        ("Windows", [.missionControl, .appExpose, .showDesktop]),
        ("GestureKeys", [.nextProfile]),
    ]
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
    /// How far (degrees) the fingers must turn around their centre to count as a rotation.
    public var rotateAngleDegrees = 15.0
    /// Longest touch (seconds) that still counts as a tap.
    public var tapMaxDuration = 0.25
    /// Most any finger may move (mm) during a tap.
    public var tapMaxMovementMM = 3.0
    /// Modifiers that must be held to draw a shape with one finger. Empty disables drawing.
    public var drawModifiers: ModifierSet = [.option]
    /// Recognizer score (0...1) a stroke must reach to count as a shape.
    public var minimumShapeScore = 0.80
    /// Longest gap (seconds, lift to lift) between taps that still counts as one double/triple tap.
    public var multiTapInterval = 0.35

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EngineSettings()
        swipeDistanceMM = try c.decodeIfPresent(Double.self, forKey: .swipeDistanceMM) ?? d.swipeDistanceMM
        rotateAngleDegrees = try c.decodeIfPresent(Double.self, forKey: .rotateAngleDegrees) ?? d.rotateAngleDegrees
        tapMaxDuration = try c.decodeIfPresent(Double.self, forKey: .tapMaxDuration) ?? d.tapMaxDuration
        tapMaxMovementMM = try c.decodeIfPresent(Double.self, forKey: .tapMaxMovementMM) ?? d.tapMaxMovementMM
        drawModifiers = try c.decodeIfPresent(ModifierSet.self, forKey: .drawModifiers) ?? d.drawModifiers
        minimumShapeScore = try c.decodeIfPresent(Double.self, forKey: .minimumShapeScore) ?? d.minimumShapeScore
        multiTapInterval = try c.decodeIfPresent(Double.self, forKey: .multiTapInterval) ?? d.multiTapInterval
    }
}

/// A named set of bindings. Exactly one profile is active at a time.
public struct Profile: Identifiable, Hashable, Codable, Sendable {
    public var id = UUID()
    public var name: String
    public var bindings: [GestureBinding]

    public init(name: String, bindings: [GestureBinding] = []) {
        self.name = name
        self.bindings = bindings
    }
}

/// Everything persisted in config.json (shapes live in their own file).
public struct AppConfig: Hashable, Codable, Sendable {
    public var enabled = true
    public var showHUD = true
    public var engine = EngineSettings()
    /// Never empty.
    public var profiles = [Profile(name: "Default")]
    public var activeProfileID: UUID

    public init() {
        activeProfileID = profiles[0].id
    }

    private enum LegacyKeys: String, CodingKey { case bindings }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        showHUD = try c.decodeIfPresent(Bool.self, forKey: .showHUD) ?? d.showHUD
        engine = try c.decodeIfPresent(EngineSettings.self, forKey: .engine) ?? d.engine
        profiles = try c.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
        if profiles.isEmpty {
            // Configs from before profiles kept a single list of bindings at the top level.
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            profiles = try [Profile(name: "Default", bindings: legacy.decodeIfPresent([GestureBinding].self, forKey: .bindings) ?? [])]
        }
        activeProfileID = try c.decodeIfPresent(UUID.self, forKey: .activeProfileID) ?? profiles[0].id
        if !profiles.contains(where: { $0.id == activeProfileID }) { activeProfileID = profiles[0].id }
    }

    public var activeProfileIndex: Int {
        profiles.firstIndex { $0.id == activeProfileID } ?? 0
    }

    public var activeProfile: Profile { profiles[activeProfileIndex] }

    /// The active profile's bindings.
    public var bindings: [GestureBinding] {
        get { profiles[activeProfileIndex].bindings }
        set { profiles[activeProfileIndex].bindings = newValue }
    }

    /// Makes the profile after the active one active, wrapping around.
    public mutating func activateNextProfile() {
        activeProfileID = profiles[(activeProfileIndex + 1) % profiles.count].id
    }

    /// The binding to run for `trigger` when `bundleID` is frontmost.
    public func binding(for trigger: Trigger, frontmostApp bundleID: String?) -> GestureBinding? {
        let candidates = bindings.filter { $0.enabled && $0.trigger == trigger }
        return candidates.first { $0.appBundleID != nil && $0.appBundleID == bundleID }
            ?? candidates.first { $0.appBundleID == nil }
    }

    /// The most taps any usable binding wants for a `fingers`-finger tap, so a single tap only waits for more
    /// taps when a double/triple tap could follow.
    public func maxTaps(fingers: Int, frontmostApp bundleID: String?) -> Int {
        bindings
            .filter { $0.enabled && ($0.appBundleID == nil || $0.appBundleID == bundleID) }
            .compactMap { if case let .tap(f, taps) = $0.trigger, f == fingers { taps } else { nil } }
            .max() ?? 1
    }
}
