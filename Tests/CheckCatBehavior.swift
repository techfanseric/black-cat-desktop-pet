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
    }
}
