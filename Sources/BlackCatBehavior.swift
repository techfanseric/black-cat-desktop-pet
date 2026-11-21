import Foundation

enum CatGesture: Int, CaseIterable {
    case listen, groom, scratch

    var duration: Double {
        switch self {
        case .listen: return 0.85
        case .groom: return 2.45
        case .scratch: return 2.05
        }
    }
}

struct GestureFrame {
    var kind: CatGesture
    var age: Double
    var side: Double
    var strength = 1.0

    func ramp(_ start: Double, _ end: Double) -> Double {
        let unit = min(1, max(0, (age - start) / (end - start)))
        return unit * unit * (3 - 2 * unit)
    }
    var lift: Double {
        switch kind {
        case .listen: return 0
        case .groom: return strength * (ramp(0, 0.52) - ramp(1.94, 2.45))
        case .scratch: return ramp(0.13, 0.44) - ramp(0.66, 1.04)
        }
    }
    var lick: Double {
        guard kind == .groom else { return 0 }
        return strength * (ramp(0.58, 0.81) - ramp(0.83, 1.05) + ramp(1.27, 1.52) - ramp(1.54, 1.78))
    }
    var ear: Double {
        guard kind == .listen else { return 0 }
        return ramp(0, 0.14) - ramp(0.22, 0.48) + 0.42 * (ramp(0.48, 0.57) - ramp(0.57, 0.85))
    }
    var slash: Double { kind == .scratch ? ramp(0.44, 0.66) : 0 }
    var markAlpha: Double { slash > 0 ? 1 - ramp(1.0, 2.05) : 0 }
}

struct BlackCatBehavior {
    private var touchTime = 0.0
    private(set) var enjoying = 0.0
    private(set) var cheek = 0.0
    private var activity: Double?
    private var curiousUntil = 0.0
    private var alertUntil = 0.0
    private var tracking = 0.0
    private var lastTick: Double?
    private var lastClick = -10.0
    private var buttonDown = false
    private var gestureStart = 0.0
    private var cancelledAt: Double?
    private var demonstrating = false
    private(set) var gesture: GestureFrame?
    private var groomed = false
    private var nextScratch = 0.0
    private var nextListen = 0.0
    private var near = false
    private var extremeX = 0.0
    private var direction = 0.0
    private var turns = 0
    private var lastLeg = 0.0
    private(set) var selected = BlackCatDesign.original
    private(set) var weights = SIMD4<Double>(1,0,0,0)

    mutating func update(time: Double, speed: Double, scroll: Bool, down: Bool, typing: Bool,
                         fixed: BlackCatDesign?, pointer: CGPoint? = nil, headTouch: Double? = nil) {
        let elapsed = min(0.12,max(0.001,time-(lastTick ?? time-1/30)))
        lastTick = time
        if time < (activity ?? .infinity) { activity = time }
        let moved = speed > 12
        let stroking = headTouch != nil && !typing && !scroll && speed < 440 && gesture?.kind != .scratch && !((gesture != nil) && demonstrating)
        touchTime = stroking ? touchTime + elapsed : 0
        let content = touchTime >= 0.33
        enjoying += ((content ? 1.0 : 0.0)-enjoying)*(1-exp(-elapsed*(content ? 7 : 5)))
        if let headTouch, stroking { cheek += (headTouch-cheek)*(1-exp(-elapsed*8)) }
        if moved || scroll || down || typing || stroking { activity = time }
        if down && !buttonDown {
            if time-lastClick < 0.38 { alertUntil = time+1.15 }
            lastClick = time
        }
        buttonDown = down
        if speed > 1750 { alertUntil = time+0.95 }
        tracking = moved ? min(1,tracking+elapsed) : max(0,tracking-elapsed*2)
        if scroll || down || tracking > 0.17 { curiousUntil = time+0.55 }
        if let fixed { selected = fixed }
        else if alertUntil > time { selected = .startled }
        else if typing || content { selected = .original }
        else if curiousUntil > time { selected = .lanky }
        else if time-(activity ?? time) >= 35 { selected = .sleepy }
        else { selected = .original }
        var target = SIMD4<Double>.zero
        target[selected.rawValue] = 1
        weights += (target-weights)*(1-exp(-elapsed*(selected == .sleepy ? 2.2 : 7.2)))
        let busy = moved || down || scroll || typing || stroking
        if busy { groomed = false }
        if var frame = gesture {
            if frame.kind == .groom && busy && !demonstrating && cancelledAt == nil { cancelledAt = time }
            frame.age = (cancelledAt ?? time) - gestureStart
            if let cancelledAt { frame.strength = max(0, 1 - (time - cancelledAt) / 0.20) }
            gesture = frame.age >= frame.kind.duration || frame.strength <= 0 ? nil : frame
        }
        if !groomed && gesture == nil && (12..<35).contains(time - (activity ?? time)) {
            start(.groom, time: time, side: -1)
        }
        guard let pointer, !typing, !scroll, !down, !stroking else {
            near = false
            turns = 0
            return
        }
        let distance = hypot((pointer.x - 140) / 85, (pointer.y - 96) / 77)
        guard distance <= (near ? 1.18 : 1) else {
            near = false
            turns = 0
            return
        }
        let side = pointer.x < 140 ? -1.0 : 1.0
        if !near || time - lastLeg > 0.95 {
            if !near && moved && time >= nextListen && gesture == nil {
                start(.listen, time: time, side: side)
            }
            direction = 0
            turns = 0
            extremeX = pointer.x
            lastLeg = time
        }
        near = true
        let delta = pointer.x - extremeX
        if direction * delta > 0 { extremeX = pointer.x }
        guard abs(delta) >= 23 && direction * delta <= 0 else { return }
        if direction != 0 { turns += 1 }
        direction = delta < 0 ? -1 : 1
        extremeX = pointer.x
        lastLeg = time
        if turns >= 2 && time >= nextScratch && (gesture == nil || (gesture?.kind == .listen && !demonstrating)) {
            start(.scratch, time: time, side: side)
            turns = 0
        }
    }

    mutating func start(_ kind: CatGesture, time: Double, side: Double, demo: Bool = false) {
        gesture = GestureFrame(kind: kind, age: 0, side: side)
        gestureStart = time
        cancelledAt = nil
        demonstrating = demo
        switch kind {
        case .listen: nextListen = time + 3
        case .scratch: nextScratch = time + 6
        case .groom: groomed = true
        }
    }
}
