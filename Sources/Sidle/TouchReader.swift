import Foundation
import MTBridge

/// One finger on the trackpad, in a coordinate system with origin at the bottom-left.
struct Touch {
    var id: Int32
    var state: Int32
    var x: Double          // 0..1 normalized
    var y: Double          // 0..1 normalized
    var mmX: Double        // millimetres
    var mmY: Double
    var size: Double
    var isDown: Bool { state >= 3 && state <= 5 }
}

struct TouchFrame {
    var device: MTDeviceRef
    var touches: [Touch]
    var timestamp: Double
    var surfaceWidthMM: Double
    var surfaceHeightMM: Double
}

/// Reads raw contact frames from every trackpad through MultitouchSupport.
final class TouchReader {
    static let shared = TouchReader()
    var onFrame: ((TouchFrame) -> Void)?
    private(set) var isRunning = false
    private var surfaceCache: [UnsafeMutableRawPointer: (Double, Double)] = [:]
    private let lock = NSLock()

    private init() {}

    @discardableResult
    func start() -> Int {
        let count = Int(MTBridgeStart(TouchReader.handleFrame))
        isRunning = count > 0
        return count
    }

    func stop() {
        MTBridgeStop()
        isRunning = false
    }

    private func surfaceSize(for device: MTDeviceRef) -> (Double, Double) {
        lock.lock(); defer { lock.unlock() }
        if let cached = surfaceCache[device] { return cached }
        var w = 0.0, h = 0.0
        MTBridgeSurfaceSizeMM(device, &w, &h)
        if w <= 0 || h <= 0 { w = 130; h = 80 }   // sensible fallback for a MacBook trackpad
        surfaceCache[device] = (w, h)
        return (w, h)
    }

    private static let handleFrame: MTBridgeTouchHandler = { device, touches, count, timestamp, _ in
        guard let device, let touches, count >= 0 else { return }
        let reader = TouchReader.shared
        let (w, h) = reader.surfaceSize(for: device)
        var list: [Touch] = []
        list.reserveCapacity(Int(count))
        for i in 0..<Int(count) {
            let t = touches[i]
            list.append(Touch(id: t.identifier, state: t.state,
                              x: Double(t.normalized.position.x), y: Double(t.normalized.position.y),
                              mmX: Double(t.normalized.position.x) * w, mmY: Double(t.normalized.position.y) * h,
                              size: Double(t.size)))
        }
        let frame = TouchFrame(device: device, touches: list, timestamp: timestamp, surfaceWidthMM: w, surfaceHeightMM: h)
        reader.onFrame?(frame)
    }
}
