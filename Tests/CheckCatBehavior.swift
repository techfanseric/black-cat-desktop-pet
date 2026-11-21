import Foundation

@main struct CheckCatBehavior {
    static func main() {
        var state = BlackCatBehavior()
        var time = 0.0
        func tick(_ count: Int = 1, speed: Double = 0, scroll: Bool = false, down: Bool = false,
                  typing: Bool = false, fixed: BlackCatDesign? = nil) {
            for _ in 0..<count {
                time += 1/30
                state.update(time:time,speed:speed,scroll:scroll,down:down,typing:typing,fixed:fixed)
                precondition(abs(state.weights.sum()-1)<0.000001 && state.weights.min() >= 0)
            }
        }
        tick(); precondition(state.selected == .original)
        tick(12,speed:100); precondition(state.selected == .lanky)
        tick(1,speed:2200); precondition(state.selected == .startled && state.weights[2]<0.5)
        tick(40,typing:true); precondition(state.selected == .original)
        tick(1100); precondition(state.selected == .sleepy)
        tick(scroll:true); precondition(state.selected == .lanky)
        tick(down:true); tick(); tick(down:true); precondition(state.selected == .startled)
        tick(100,speed:2300,fixed:.sleepy); precondition(state.selected == .sleepy && state.weights[3]>0.99)
        print("Verified automatic transitions, normalized smooth blending, wakeup and manual selection.")
        state = BlackCatBehavior()
        time = 0
        tick(360)
        precondition(state.gesture == nil)
        tick(27)
        precondition(state.gesture?.kind == .groom && state.gesture!.lick > 0.8)
        tick(1,typing:true)
        tick(3)
        precondition((0.1...0.9).contains(state.gesture!.strength))
        tick(5)
        precondition(state.gesture == nil)
        tick(450)
        precondition(state.gesture == nil)
        tick(660)
        precondition(state.selected == .sleepy && state.gesture == nil)

        func move(_ x: Double, down: Bool = false, far: Bool = false) {
            time += 0.10
            state.update(time:time,speed:360,scroll:false,down:down,typing:false,fixed:.original,
                         pointer:CGPoint(x:x,y:far ? 220 : 92))
        }
        for x in [98,155,105,160] { move(Double(x),far:true) }
        precondition(state.gesture == nil)
        move(98)
        precondition(state.gesture?.kind == .listen && state.gesture?.side == -1)
        move(156); move(108)
        precondition(state.gesture?.kind == .listen)
        move(163)
        precondition(state.gesture?.kind == .scratch && state.gesture?.side == 1)
        tick(12)
        precondition(state.gesture?.markAlpha == 0)
        tick(5)
        precondition((0.1...0.9).contains(state.gesture!.slash) && state.gesture!.markAlpha == 1)
        tick(30)
        precondition(state.gesture!.lift == 0 && (0.1...0.9).contains(state.gesture!.markAlpha))
        tick(17)
        precondition(state.gesture == nil)
        for x in [155,103,160,100] { move(Double(x)) }
        precondition(state.gesture?.kind != .scratch)
        tick(185)
        for x in [155,103,160,100] { move(Double(x),down:true) }
        precondition(state.gesture == nil)
        for x in [155,103,160,100] { move(Double(x)) }
        precondition(state.gesture?.kind == .scratch && state.gesture?.side == -1)
        print("Verified grooming and interruption, approach direction, deliberate teasing, drag suppression, scratch contact, fade and cooldown.")
        state = BlackCatBehavior()
        func pet(_ count: Int, touch: Double?, speed: Double = 100, typing: Bool = false) {
            for _ in 0..<count {
                time += 1/30
                state.update(time:time,speed:speed,scroll:false,down:false,typing:typing,fixed:nil,
                             pointer:CGPoint(x:142,y:66),headTouch:touch)
            }
        }
        pet(6,touch:0.6)
        precondition(state.enjoying == 0)
        pet(40,touch:0.6)
        precondition(state.enjoying > 0.99 && state.cheek > 0.55 && state.gesture == nil)
        pet(20,touch:-0.8)
        precondition(state.cheek < -0.75)
        pet(6,touch:nil)
        precondition((0.2...0.6).contains(state.enjoying))
        pet(42,touch:0.5,speed:900)
        precondition(state.enjoying < 0.001)
        pet(30,touch:0.5,typing:true)
        precondition(state.enjoying < 0.001)
        print("Verified head contact, cheek following, release and fast-pass/typing suppression.")
    }
}
