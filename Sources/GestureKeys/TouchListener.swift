import CMultitouch
import CoreGraphics
import Foundation
import GestureCore

/// Receives raw contact frames from every trackpad and forwards them to the main queue.
final class TouchListener {
    static let shared = TouchListener()

    /// Called on the main queue with (device id, touches, timestamp).
    var onFrame: ((UInt, [TouchPoint], Double) -> Void)?
    private(set) var deviceCount = 0

    /// Returns false if MultitouchSupport could not be loaded.
    @discardableResult
    func start() -> Bool {
        let result = MTBridgeStart { device, touches, count, timestamp, _ in
            TouchListener.shared.receive(device: device, touches: touches, count: Int(count), timestamp: timestamp)
            return 0
        }
        deviceCount = max(Int(result), 0)
        return result >= 0
    }

    func stop() {
        MTBridgeStop()
        deviceCount = 0
    }

    /// Physical size of a device's surface; falls back to a typical MacBook trackpad.
    func surfaceSize(of device: UInt) -> CGSize {
        var width: Int32 = 0, height: Int32 = 0
        if MTBridgeSurfaceSize(UnsafeMutableRawPointer(bitPattern: device), &width, &height) != 0 {
            return CGSize(width: Double(width) / 100, height: Double(height) / 100)
        }
        return CGSize(width: 160, height: 100)
    }

    // Runs on MultitouchSupport's private thread.
    private func receive(device: MTDeviceRef?, touches: UnsafePointer<MTTouch>?, count: Int, timestamp: Double) {
        var points: [TouchPoint] = []
        if let touches {
            points.reserveCapacity(count)
            for i in 0..<count {
                let t = touches[i]
                points.append(TouchPoint(id: t.identifier,
                                         x: Double(t.normalized.position.x),
                                         y: Double(t.normalized.position.y),
                                         isTouching: t.state == 3 || t.state == 4))
            }
        }
        let key = UInt(bitPattern: device)
        DispatchQueue.main.async {
            self.onFrame?(key, points, timestamp)
        }
    }
}
