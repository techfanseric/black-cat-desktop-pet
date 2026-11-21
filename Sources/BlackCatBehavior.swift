import Foundation

struct BlackCatBehavior {
    private var activity: Double?
    private var curiousUntil = 0.0
    private var alertUntil = 0.0
    private var tracking = 0.0
    private var lastTick: Double?
    private var lastClick = -10.0
    private var buttonDown = false
    private(set) var selected = BlackCatDesign.original
    private(set) var weights = SIMD4<Double>(1,0,0,0)

    mutating func update(time: Double, speed: Double, scroll: Bool, down: Bool, typing: Bool,
                         fixed: BlackCatDesign?) {
        let elapsed = min(0.12,max(0.001,time-(lastTick ?? time-1/30)))
        lastTick = time
        if time < (activity ?? .infinity) { activity = time }
        let moved = speed > 12
        if moved || scroll || down || typing { activity = time }
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
        else if typing { selected = .original }
        else if curiousUntil > time { selected = .lanky }
        else if time-(activity ?? time) >= 35 { selected = .sleepy }
        else { selected = .original }
        var target = SIMD4<Double>.zero
        target[selected.rawValue] = 1
        weights += (target-weights)*(1-exp(-elapsed*(selected == .sleepy ? 2.2 : 7.2)))
    }
}
