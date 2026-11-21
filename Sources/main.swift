import AppKit
import ApplicationServices
import ImageIO
import OSLog
import UniformTypeIdentifiers

private let ink = NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1)
private let cream = NSColor(srgbRed: 0.97, green: 0.96, blue: 0.91, alpha: 1)
private let mint = NSColor(srgbRed: 0.77, green: 0.88, blue: 0.43, alpha: 1)
private let pink = NSColor(srgbRed: 0.76, green: 0.47, blue: 0.49, alpha: 1)
private let paper = NSColor(srgbRed: 0.97, green: 0.98, blue: 0.96, alpha: 1)
private let amber = NSColor(srgbRed: 0.98, green: 0.72, blue: 0.29, alpha: 1)
private func onDesk(_ point: CGPoint, height: CGFloat = 0) -> CGPoint {
    let across = (156 - point.x) / 190
    let towardViewer = (234 - point.y) / 67
    let depth = 1.12 - 0.24 * towardViewer + 0.038 * across
    return CGPoint(x: 155 + (across * 192 + towardViewer * 13) / depth,
                   y: 226 + (towardViewer * 48 + across * 13 - height) / depth)
}

private struct Cap {
    let label: String
    let code: UInt16
    let time: TimeInterval
}

private let rows: [[(String, UInt16)]] = [
    [("1",18),("2",19),("3",20),("4",21),("5",23),("6",22),("7",26),("8",28),("9",25),("0",29)],
    [("Q",12),("W",13),("E",14),("R",15),("T",17),("Y",16),("U",32),("I",34),("O",31),("P",35)],
    [("A",0),("S",1),("D",2),("F",3),("G",5),("H",4),("J",38),("K",40),("L",37),("↩",36)],
    [("⇧",56),("Z",6),("X",7),("C",8),("V",9),("B",11),("N",45),("M",46),(",",43),(".",47)],
    [("⌃",59),("⌥",58),("⌘",55),("␣",49),("⌘",54),("⌥",61),("←",123),("→",124)]
]

private let specialKeys: [UInt16: String] = [
    51:"⌫", 53:"Esc", 48:"⇥", 60:"⇧", 62:"⌃", 63:"fn", 76:"↩", 125:"↓", 126:"↑"
]

private let modifierKeys: [UInt16: CGEventFlags] = [
    54:.maskCommand, 55:.maskCommand, 56:.maskShift, 60:.maskShift,
    58:.maskAlternate, 61:.maskAlternate, 59:.maskControl, 62:.maskControl, 63:.maskSecondaryFn
]

private final class CatView: NSView {
    override var isFlipped: Bool { true }
    var now = ProcessInfo.processInfo.systemUptime
    var gaze = CGPoint.zero
    var pointerActivity = 0.0
    var clicked = false
    var caps: [Cap] = []
    var typingActivity = 0.0
    var previewBackground = false
    private var mouseUntil = 0.0
    private var strokes: [Cap?] = [nil, nil]
    private var dragOrigin: CGPoint?
    private var windowOrigin: CGPoint?
    var showMenu: ((NSEvent) -> Void)?
    var behavior = BlackCatBehavior()
    var fixedDesign = (UserDefaults.standard.object(forKey:"BlackCatFixedDesign") as? Int).flatMap(BlackCatDesign.init(rawValue:))

    func hit(code: UInt16, label: String) {
        let time = now
        let key = Cap(label: label, code: code, time: time)
        if let last = caps.last, last.code == code, time - last.time < 0.08 { return }
        caps.append(key)
        if caps.count > 5 { caps.removeFirst() }
        let point = keyPosition(code)
        strokes[point.x < 155 ? 0 : 1] = key
    }

    func animate(at time: TimeInterval, toward look: CGPoint, moved: Bool, clicked: Bool,
                 speed: Double? = nil, scroll: Bool = false) {
        now = time
        self.clicked = clicked
        if moved || clicked || scroll { mouseUntil = time + 0.55 }
        let target = time < mouseUntil ? 1.0 : 0.0
        pointerActivity += (target - pointerActivity) * (target > 0 ? 0.27 : 0.17)
        let lastKeyAge = caps.last.map { time - $0.time } ?? 1
        let typingTarget = lastKeyAge < 0.36 ? 1.0 : 0.0
        behavior.update(time:time,speed:speed ?? (moved ? 160 : 0),scroll:scroll,down:clicked,
                        typing:typingTarget > 0,fixed:fixedDesign)
        typingActivity += (typingTarget - typingActivity) * 0.28
        gaze = CGPoint(x: gaze.x * 0.75 + look.x * 0.25, y: gaze.y * 0.75 + look.y * 0.25)
        caps.removeAll { time - $0.time > 0.6 }
        needsDisplay = true
    }

    func animateDemo(frame: Int, at time: TimeInterval) {
        let usingMouse = (14...45).contains(frame) || (107...143).contains(frame)
        let look = CGPoint(x: sin(Double(frame) * 0.16) * 7, y: cos(Double(frame) * 0.10) * 6)
        animate(at: time, toward: look, moved: usingMouse, clicked: frame == 33 || frame == 119)
        let letters: [(UInt16, String)] = [(3,"F"),(38,"J"),(1,"S"),(56,"⇧"),(49,"␣"),(37,"L"),(9,"V")]
        if (58...105).contains(frame), frame % 7 == 2 {
            let key = letters[(frame / 7) % letters.count]
            hit(code: key.0, label: key.1)
        }
        if frame == 77 { hit(code: 34, label: "I") }
        if frame == 113 || frame == 125 || frame == 137 { hit(code: 3, label: "F") }
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = NSEvent.mouseLocation
        windowOrigin = window?.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin, let windowOrigin else { return }
        let pointer = NSEvent.mouseLocation
        window?.setFrameOrigin(CGPoint(x: windowOrigin.x + pointer.x - dragOrigin.x,
                                       y: windowOrigin.y + pointer.y - dragOrigin.y))
    }

    override func rightMouseDown(with event: NSEvent) { showMenu?(event) }

    private func fill(_ color: NSColor, _ path: CGPath, in context: CGContext) {
        context.setFillColor(color.cgColor)
        context.addPath(path)
        context.fillPath()
    }

    private func ellipse(_ color: NSColor, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, in ctx: CGContext) {
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: x, y: y, width: w, height: h))
    }

    private func box(_ color: NSColor, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, in ctx: CGContext) {
        fill(color, CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h),
                           cornerWidth: r, cornerHeight: r, transform: nil), in: ctx)
    }

    private func line(_ color: NSColor, _ width: CGFloat, from start: CGPoint, to end: CGPoint, in ctx: CGContext) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()
    }

    private func text(_ string: String, size: CGFloat, color: NSColor, center: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .semibold), .foregroundColor: color
        ]
        let measured = (string as NSString).size(withAttributes: attributes)
        (string as NSString).draw(at: CGPoint(x: center.x - measured.width / 2, y: center.y - measured.height / 2),
                                  withAttributes: attributes)
    }

    private func keyRect(row: Int, index: Int) -> CGRect {
        if row == 4 {
            let offsets: [CGFloat] = [0, 17, 34, 51, 101, 118, 135, 152]
            return CGRect(x: 75 + offsets[index], y: 246, width: index == 3 ? 47 : 14, height: 9)
        }
        let x = CGFloat(71 + index * 17 + row)
        let y = 208 + CGFloat(row) * 9.5
        return CGRect(x: x, y: y, width: 14.8, height: 8)
    }

    private func keyPosition(_ code: UInt16) -> CGPoint {
        let normalized: UInt16 = code == 60 ? 56 : code == 62 ? 59 : code
        for (row, keys) in rows.enumerated() {
            if let index = keys.firstIndex(where: { $0.1 == normalized }) {
                let bottom = [12,11,10,4,3,2,1,0]
                return BlackCatArtwork.keyCenter(row:row,column:row == 4 ? bottom[index] : 12-index)
            }
        }
        return BlackCatArtwork.keyCenter(row:2,column:code.isMultiple(of:2) ? 1 : 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        let scale = min(bounds.width/280,bounds.height/240)
        ctx.translateBy(x:(bounds.width-280*scale)/2,y:(bounds.height-240*scale)/2)
        ctx.scaleBy(x:scale,y:scale)
        if previewBackground { ctx.setFillColor(NSColor(white:0.93,alpha:1).cgColor); ctx.fill(CGRect(x:0,y:0,width:280,height:240)) }
        var pose = BlackCatPose(mouse:pointerActivity,gaze:CGPoint(x:gaze.x/8,y:gaze.y/8),
                                blink:max(0,1-abs(now.truncatingRemainder(dividingBy:4.35)-0.13)/0.13))
        pose.mix = behavior.weights
        pose.excitement = min(1,CGFloat(caps.count)/4) + behavior.weights[2]*0.5
        pose.phase = now*10
        for (index,event) in strokes.enumerated() {
            guard let event else { continue }
            let age = max(0,now-event.time)
            let strength = max(0,min(1,age/0.045))*max(0,min(1,(0.25-age)/0.12))
            let target = keyPosition(event.code)
            if index == 0 { pose.leftTarget = target; pose.leftPress = strength }
            else { pose.rightTarget = target; pose.keyPress = strength }
        }
        pose.gaze.y = min(1,pose.gaze.y*(1-typingActivity)+typingActivity*0.9)
        BlackCatArtwork.draw(behavior.selected,pose:pose,in:ctx)
        for (index,cap) in caps.enumerated() {
            let age = max(0,now-cap.time)
            guard age < 0.52 else { continue }
            let target = keyPosition(cap.code)
            let x = target.x+CGFloat(index%3-1)*6
            let y = 163-age*27-CGFloat(index%2)*6
            ctx.saveGState(); ctx.setAlpha(min(1,(0.52-age)*5))
            box(ink,x-10,y+1.4,20,15,4,in:ctx)
            box(paper,x-10,y,20,15,4,in:ctx)
            text(cap.label,size:10,color:ink,center:CGPoint(x:x,y:y+7))
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    private func surfacePath(_ rect: CGRect, radius: CGFloat, height: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let left = rect.minX, right = rect.maxX, top = rect.minY, bottom = rect.maxY
        path.move(to: onDesk(CGPoint(x: left + radius, y: top), height: height))
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: right - radius, y: top), CGPoint(x: right, y: top), CGPoint(x: right, y: top + radius)),
            (CGPoint(x: right, y: bottom - radius), CGPoint(x: right, y: bottom), CGPoint(x: right - radius, y: bottom)),
            (CGPoint(x: left + radius, y: bottom), CGPoint(x: left, y: bottom), CGPoint(x: left, y: bottom - radius)),
            (CGPoint(x: left, y: top + radius), CGPoint(x: left, y: top), CGPoint(x: left + radius, y: top))
        ]
        for (edge, corner, end) in corners {
            path.addLine(to: onDesk(edge, height: height))
            path.addQuadCurve(to: onDesk(end, height: height), control: onDesk(corner, height: height))
        }
        path.closeSubpath()
        return path
    }

    private func drawScene(in ctx: CGContext) {
        if previewBackground {
            ctx.setFillColor(NSColor(srgbRed: 0.88, green: 0.89, blue: 0.87, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 292))
        }
        let mouseWeight = pointerActivity
        let typingWeight = typingActivity * (1 - mouseWeight * 0.55)
        let latest = caps.last.map { max(0, 1 - (now - $0.time) / 0.22) } ?? 0
        let bob = sin(now * 2.2) * 1.2
        let hip = CGPoint(x: 139 + mouseWeight * 9, y: 192)
        let head = CGPoint(x: 137 - mouseWeight * 30 + typingWeight * 11 + gaze.x * 0.48,
                           y: 92 + bob + typingWeight * 7 + latest * 3)
        let neck = CGPoint(x: head.x + mouseWeight * 8, y: head.y + 21)
        let furShade = NSColor(srgbRed: 0.22, green: 0.22, blue: 0.25, alpha: 1)
        ellipse(NSColor.black.withAlphaComponent(0.14), 96, 195, 91, 15, in: ctx)

        let tailEnd = CGPoint(x: 227 + mouseWeight * 5, y: 163 + sin(now * 2.7) * (3 + typingWeight * 5))
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: hip.x + 30, y: hip.y - 6))
        tail.addCurve(to: tailEnd, control1: CGPoint(x: 210, y: 204), control2: CGPoint(x: 203, y: tailEnd.y + 1))
        ctx.setLineCap(.round)
        ctx.setLineWidth(10)
        ctx.setStrokeColor(ink.cgColor)
        ctx.addPath(tail)
        ctx.strokePath()
        ellipse(cream, tailEnd.x - 5, tailEnd.y - 4.5, 9, 8, in: ctx)

        let torso = CGMutablePath()
        torso.move(to: CGPoint(x: neck.x - 24, y: neck.y - 4))
        torso.addCurve(to: CGPoint(x: hip.x - 34, y: hip.y + 1),
                       control1: CGPoint(x: neck.x - 19, y: neck.y + 24), control2: CGPoint(x: hip.x - 48, y: hip.y - 16))
        torso.addCurve(to: CGPoint(x: hip.x - 18, y: hip.y + 12),
                       control1: CGPoint(x: hip.x - 37, y: hip.y + 9), control2: CGPoint(x: hip.x - 30, y: hip.y + 16))
        torso.addQuadCurve(to: CGPoint(x: hip.x + 14, y: hip.y + 10), control: CGPoint(x: hip.x, y: hip.y + 8))
        torso.addQuadCurve(to: CGPoint(x: hip.x + 32, y: hip.y + 4), control: CGPoint(x: hip.x + 34, y: hip.y + 17))
        torso.addCurve(to: CGPoint(x: neck.x + 23, y: neck.y - 6),
                       control1: CGPoint(x: hip.x + 50, y: hip.y - 11), control2: CGPoint(x: neck.x + 22, y: neck.y + 17))
        torso.closeSubpath()
        fill(ink, torso, in: ctx)

        let bib = CGMutablePath()
        bib.move(to: CGPoint(x: neck.x - 15, y: neck.y + 1))
        let chest = CGPoint(x: neck.x * 0.55 + hip.x * 0.45, y: neck.y + 42)
        bib.addCurve(to: CGPoint(x: chest.x - 5, y: chest.y - 3),
                     control1: CGPoint(x: neck.x - 18, y: neck.y + 17), control2: CGPoint(x: chest.x - 13, y: chest.y - 9))
        bib.addQuadCurve(to: CGPoint(x: chest.x + 1, y: chest.y + 5), control: CGPoint(x: chest.x - 4, y: chest.y + 1))
        bib.addCurve(to: CGPoint(x: neck.x + 16, y: neck.y + 1),
                     control1: CGPoint(x: chest.x + 14, y: chest.y - 3), control2: CGPoint(x: neck.x + 15, y: neck.y + 20))
        bib.closeSubpath()
        fill(cream, bib, in: ctx)

        let base = CGRect(x: 61, y: 201, width: 190, height: 67)
        fill(NSColor.black.withAlphaComponent(0.16), surfacePath(base.offsetBy(dx: -1, dy: -3), radius: 5, height: -3), in: ctx)
        fill(ink, surfacePath(base, radius: 4.5, height: -2.6), in: ctx)
        fill(furShade, surfacePath(base, radius: 4.5, height: 1.2), in: ctx)
        fill(NSColor(srgbRed: 0.77, green: 0.79, blue: 0.77, alpha: 1),
             surfacePath(base.insetBy(dx: 3, dy: 3), radius: 3, height: 2), in: ctx)

        for (row, keys) in rows.enumerated() {
            for (index, key) in keys.enumerated() {
                let rect = keyRect(row: row, index: index)
                let age = caps.last(where: { $0.code == key.1 || ($0.code == 60 && key.1 == 56) }).map { now - $0.time } ?? 1
                let pressing = age < 0.16
                fill(NSColor(srgbRed: 0.59, green: 0.62, blue: 0.60, alpha: 1), surfacePath(rect, radius: 1.5, height: 2), in: ctx)
                let accent = key.1 == 36 || key.1 == 56 || key.1 == 123
                let color = pressing ? mint : (accent ? amber : paper)
                let height: CGFloat = pressing ? 2.4 : 4.2
                fill(color, surfacePath(rect.insetBy(dx: 0.5, dy: 0.65), radius: 1.2, height: height), in: ctx)
                let center = onDesk(CGPoint(x: rect.midX, y: rect.midY), height: height)
                ctx.saveGState()
                ctx.translateBy(x: center.x, y: center.y)
                ctx.rotate(by: .pi + 0.07)
                ctx.scaleBy(x: 1, y: 0.67)
                text(key.0, size: 4.7, color: ink.withAlphaComponent(0.60), center: .zero)
                ctx.restoreGState()
            }
        }

        let mouseCenter = CGPoint(x: 280 - gaze.x * mouseWeight * 0.5, y: 235 - gaze.y * mouseWeight * 0.55)
        let mouse = CGRect(x: mouseCenter.x - 11, y: mouseCenter.y - 17, width: 22, height: 34)
        fill(NSColor.black.withAlphaComponent(0.14), surfacePath(mouse.offsetBy(dx: -1, dy: -2), radius: 10.8, height: -2), in: ctx)
        fill(furShade, surfacePath(mouse, radius: 10.8, height: 0), in: ctx)
        fill(clicked ? cream : paper, surfacePath(mouse, radius: 10.8, height: 4), in: ctx)
        let wheel = CGRect(x: mouseCenter.x - 1.3, y: mouseCenter.y - 9, width: 2.6, height: 8)
        fill(amber, surfacePath(wheel, radius: 1.2, height: 4.6), in: ctx)
        line(ink.withAlphaComponent(0.30), 0.7,
             from: onDesk(CGPoint(x: mouseCenter.x, y: mouseCenter.y - 9), height: 4),
             to: onDesk(CGPoint(x: mouseCenter.x, y: mouseCenter.y - 16), height: 4), in: ctx)
        let mouseContact = onDesk(CGPoint(x: mouseCenter.x, y: mouseCenter.y - 3), height: 5)

        for index in 0..<2 {
            let side = index == 0 ? -1.0 : 1.0
            var paw = CGPoint(x: hip.x + side * (18 + typingWeight * 9), y: 201 - typingWeight * 20)
            if index == 0 {
                paw.x += (mouseContact.x - paw.x) * mouseWeight
                paw.y += (mouseContact.y - (clicked ? 1 : 4) - paw.y) * mouseWeight
            }
            var reach = index == 0 ? mouseWeight : 0
            if let stroke = strokes[index] {
                let age = max(0, now - stroke.time)
                let down = min(1, age / 0.045)
                let up = max(0, min(1, (0.24 - age) / 0.10))
                let amount = down * up * up * (3 - 2 * up)
                let target = keyPosition(stroke.code)
                paw.x += (target.x - paw.x) * amount
                paw.y += (target.y - 3 - paw.y) * amount
                reach = max(reach, amount)
            }
            let root = CGPoint(x: neck.x + side * 22, y: neck.y - 9)
            let elbow = CGPoint(x: root.x * 0.54 + paw.x * 0.46 + side * (9 - 4 * reach),
                                y: root.y * 0.42 + paw.y * 0.58)
            let angle = atan2(elbow.x - paw.x, paw.y - elbow.y)
            let tangent = CGPoint(x: -sin(angle), y: cos(angle))
            let lateral = CGPoint(x: cos(angle) * side, y: sin(angle) * side)
            func tip(_ across: CGFloat, _ along: CGFloat) -> CGPoint {
                CGPoint(x: paw.x + across * lateral.x + along * tangent.x,
                        y: paw.y + across * lateral.y + along * tangent.y)
            }
            let arm = CGMutablePath()
            let elbowSlope = (paw.x - root.x) / max(1, paw.y - root.y)
            let outerElbow = CGPoint(x: elbow.x + side * 6.2, y: elbow.y)
            let innerElbow = CGPoint(x: elbow.x - side * 7, y: elbow.y - 2)
            arm.move(to: root)
            arm.addCurve(to: outerElbow,
                         control1: CGPoint(x: root.x + side * 0.8, y: root.y + 21),
                         control2: CGPoint(x: outerElbow.x - elbowSlope * 9, y: outerElbow.y - 9))
            arm.addCurve(to: tip(6.3, -4),
                         control1: CGPoint(x: outerElbow.x + elbowSlope * 9, y: outerElbow.y + 9),
                         control2: tip(4.8, -13))
            arm.addCurve(to: tip(-6.0, 2), control1: tip(9.3, 7.1), control2: tip(-2.8, 9))
            arm.addCurve(to: innerElbow, control1: tip(-6.2, -9),
                         control2: CGPoint(x: innerElbow.x + elbowSlope * 8, y: innerElbow.y + 8))
            arm.addCurve(to: CGPoint(x: root.x - side * 14, y: root.y + 12),
                         control1: CGPoint(x: innerElbow.x - elbowSlope * 8, y: innerElbow.y - 8),
                         control2: CGPoint(x: root.x - side * 12, y: root.y + 30))
            arm.closeSubpath()
            fill(ink, arm, in: ctx)
            ctx.saveGState()
            ctx.addPath(arm)
            ctx.clip()
            let crease = CGMutablePath()
            crease.move(to: tip(-5.5, -4))
            crease.addQuadCurve(to: tip(-5.4, -21), control: tip(-6.5, -10))
            ctx.setLineWidth(0.85)
            ctx.setStrokeColor(furShade.withAlphaComponent(0.8 * (1 - reach)).cgColor)
            ctx.addPath(crease)
            ctx.strokePath()
            let sock = CGMutablePath()
            sock.move(to: tip(-10, -6))
            sock.addCurve(to: tip(10, -4), control1: tip(-2, -9), control2: tip(3, -1))
            sock.addLine(to: tip(10, 12))
            sock.addLine(to: tip(-10, 12))
            sock.closeSubpath()
            fill(cream, sock, in: ctx)
            line(ink.withAlphaComponent(0.35), 0.6,
                 from: tip(0.8, 3.8), to: tip(1.2, 6.1), in: ctx)
            ctx.restoreGState()
        }

        ctx.saveGState()
        ctx.translateBy(x: head.x, y: head.y)
        ctx.rotate(by: -mouseWeight * 0.12 + typingWeight * 0.085 + gaze.x * 0.006)
        let silhouette = CGMutablePath()
        silhouette.move(to: CGPoint(x: -37, y: -8))
        silhouette.addCurve(to: CGPoint(x: -31, y: -40), control1: CGPoint(x: -40, y: -16), control2: CGPoint(x: -37, y: -39))
        silhouette.addQuadCurve(to: CGPoint(x: -13, y: -28), control: CGPoint(x: -28, y: -43))
        silhouette.addQuadCurve(to: CGPoint(x: 15, y: -27), control: CGPoint(x: 1, y: -32))
        silhouette.addQuadCurve(to: CGPoint(x: 31, y: -39), control: CGPoint(x: 27, y: -41))
        silhouette.addQuadCurve(to: CGPoint(x: 38, y: -8), control: CGPoint(x: 36, y: -37))
        silhouette.addCurve(to: CGPoint(x: 5, y: 27), control1: CGPoint(x: 47, y: 14), control2: CGPoint(x: 29, y: 28))
        silhouette.addCurve(to: CGPoint(x: -37, y: -8), control1: CGPoint(x: -20, y: 29), control2: CGPoint(x: -47, y: 17))
        fill(ink, silhouette, in: ctx)
        ctx.saveGState()
        ctx.addPath(silhouette)
        ctx.clip()
        let facePatch = CGMutablePath()
        facePatch.move(to: CGPoint(x: 26, y: -44))
        facePatch.addCurve(to: CGPoint(x: 14, y: -23), control1: CGPoint(x: 23, y: -33), control2: CGPoint(x: 21, y: -27))
        facePatch.addCurve(to: CGPoint(x: 5, y: -10), control1: CGPoint(x: 8, y: -20), control2: CGPoint(x: 5, y: -17))
        facePatch.addCurve(to: CGPoint(x: -5, y: 8), control1: CGPoint(x: 5, y: -2), control2: CGPoint(x: 1, y: 7))
        facePatch.addCurve(to: CGPoint(x: -16, y: 18), control1: CGPoint(x: -15, y: 8), control2: CGPoint(x: -19, y: 13))
        facePatch.addQuadCurve(to: CGPoint(x: -8, y: 30), control: CGPoint(x: -14, y: 24))
        facePatch.addLine(to: CGPoint(x: 44, y: 32))
        facePatch.addLine(to: CGPoint(x: 44, y: -44))
        facePatch.closeSubpath()
        fill(cream, facePatch, in: ctx)
        ctx.restoreGState()
        for side in [-1.0, 1.0] {
            let inside = CGMutablePath()
            inside.move(to: CGPoint(x: side * 30, y: -33))
            inside.addQuadCurve(to: CGPoint(x: side * 19, y: -23), control: CGPoint(x: side * 27, y: -31))
            inside.addQuadCurve(to: CGPoint(x: side * 33, y: -20), control: CGPoint(x: side * 27, y: -24))
            inside.addQuadCurve(to: CGPoint(x: side * 30, y: -33), control: CGPoint(x: side * 33, y: -29))
            fill(side < 0 ? furShade : pink.withAlphaComponent(0.52), inside, in: ctx)
        }

        let blinkTime = now.truncatingRemainder(dividingBy: 4.35)
        let open = min(1, abs(blinkTime - 0.13) / 0.13)
        let sideLook = gaze.x * (0.45 + mouseWeight * 0.25) + typingWeight
        let downLook = gaze.y * 0.48 * (1 - typingWeight) + typingWeight * 4.5
        for eye in [-16.0, 16.0] {
            let eyeHeight = 17.5 * open
            if eyeHeight < 3 {
                line(eye > 0 ? ink : mint, 1.4, from: CGPoint(x: eye - 7, y: -3), to: CGPoint(x: eye + 7, y: -3), in: ctx)
            } else {
                let eyeRect = CGRect(x: eye - 9, y: -3 - eyeHeight / 2, width: 18, height: eyeHeight)
                let rim = eyeRect.insetBy(dx: -0.9, dy: -0.9)
                ellipse(ink, rim.minX, rim.minY, rim.width, rim.height, in: ctx)
                ctx.saveGState()
                ctx.addEllipse(in: eyeRect)
                ctx.clip()
                ellipse(mint, eyeRect.minX, eyeRect.minY, eyeRect.width, eyeRect.height, in: ctx)
                ellipse(ink, eye + sideLook - 4.3, -3 + downLook - 6.3, 8.6, 12.6, in: ctx)
                ellipse(paper, eye + sideLook - 1.7, -5.2 + downLook, 1.9, 1.9, in: ctx)
                ctx.restoreGState()
            }
        }
        let nose = CGMutablePath()
        nose.move(to: CGPoint(x: -3.4, y: 11))
        nose.addQuadCurve(to: CGPoint(x: 3.2, y: 11), control: CGPoint(x: -0.2, y: 9))
        nose.addQuadCurve(to: CGPoint(x: 0.1, y: 14.3), control: CGPoint(x: 3.3, y: 12.8))
        nose.addQuadCurve(to: CGPoint(x: -3.4, y: 11), control: CGPoint(x: -2.8, y: 13.1))
        fill(pink, nose, in: ctx)
        for side in [-1.0, 1.0] {
            let mouth = CGMutablePath()
            mouth.move(to: CGPoint(x: 0.1, y: 14))
            mouth.addQuadCurve(to: CGPoint(x: side * 4, y: 16.5), control: CGPoint(x: side * 0.8, y: 17.7))
            ctx.addPath(mouth)
            ctx.setLineWidth(0.72)
            ctx.setStrokeColor(ink.withAlphaComponent(0.78).cgColor)
            ctx.strokePath()
            for whisker in 0..<3 {
                let spread = CGFloat(whisker) - 1
                line((side < 0 ? cream : furShade).withAlphaComponent(0.65), 0.67,
                     from: CGPoint(x: side * 25, y: 12 + spread * 2),
                     to: CGPoint(x: side * (39 - abs(spread) * 2), y: 12 + spread * 4.3), in: ctx)
            }
        }
        ctx.restoreGState()

        for (index, cap) in caps.enumerated() {
            let age = max(0, now - cap.time)
            guard age < 0.52 else { continue }
            let contact = keyPosition(cap.code)
            let width = cap.label.count > 2 ? 27.0 : 18.0
            let x = min(272 - width, max(70, contact.x + CGFloat(index % 3 - 1) * 7 - width / 2))
            let y = 182 - age * 29 - CGFloat(index % 2) * 7
            ctx.saveGState()
            ctx.setAlpha(min(1, (0.52 - age) * 5))
            box(ink.withAlphaComponent(0.75), x, y + 1.4, width, 15, 4, in: ctx)
            box(paper, x, y, width, 14.5, 4, in: ctx)
            text(cap.label, size: cap.label.count > 2 ? 7.5 : 10, color: ink,
                 center: CGPoint(x: x + width / 2, y: y + 7))
            ctx.restoreGState()
        }
    }
}

private final class CatPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class TypingWindow: NSWindow {
    var onKey: ((NSEvent) -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown || event.type == .flagsChanged {
            onKey?(event)
            if event.type == .keyDown && !event.modifierFlags.contains(.command) { return }
        }
        super.sendEvent(event)
    }
}

private final class DesktopCat: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "local.milkcat.desktop-pet", category: "Keyboard")
    private let cat = CatView(frame: NSRect(x: 0, y: 0, width: 270, height: 263))
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var panel: CatPanel!
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var lastPointer = NSEvent.mouseLocation
    private var lastSample = ProcessInfo.processInfo.systemUptime
    private var scrollCount = CGEventSource.counterForEventType(.combinedSessionState,eventType:.scrollWheel)
    private var modifiers: Set<UInt16> = []
    private var previouslyAllowed = false
    private var nextPermissionCheck = 0.0
    private var demoFrame: Int?
    private var typingWindow: TypingWindow?
    private var reportedStatus: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = CatPanel(contentRect: cat.frame, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = cat
        resetPosition()
        panel.orderFrontRegardless()
        status.button?.title = "🐾"
        status.button?.toolTip = "黑猫桌宠"
        menu.autoenablesItems = false
        status.menu = menu
        cat.showMenu = { [weak self] event in
            guard let self else { return }
            NSMenu.popUpContextMenu(self.menu, with: event, for: self.cat)
        }
        buildMenu()
        refreshPermission()
        timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in self?.tick() }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        #if VERIFY
        verify()
        #endif
    }

    #if VERIFY
    private func verify() {
        testTyping()
        guard let key = CGEvent(keyboardEventSource: nil, virtualKey: 3, keyDown: true),
              let event = NSEvent(cgEvent: key), let typingWindow else { exit(1) }
        if let tap {
            receive(.keyDown, key)
            guard cat.caps.last?.label == "F" else { exit(4) }
            cat.caps.removeAll()
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            CFMachPortInvalidate(tap)
            self.tap = nil
            self.source = nil
        }
        typingWindow.sendEvent(event)
        guard cat.caps.last?.label == "F" else {
            print("Typing test failed; visible=\(panel.isVisible), event=\(event.type.rawValue), code=\(event.keyCode), tap=\(tap != nil)")
            exit(2)
        }
        let before = cat.caps.last?.time ?? 0
        demo()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [self] in
            guard let demoFrame, demoFrame > 65, cat.caps.contains(where: { $0.time > before && $0.label != "F" }) else { exit(3) }
            print("Typing window dispatched F; demonstration timer animated additional keys.")
            exit(0)
        }
    }
    #endif

    private func buildMenu() {
        menu.removeAllItems()
        let styles = NSMenu()
        for (index,title) in ["自动感知","A · 端坐","B · 探身","C · 警觉","D · 困困"].enumerated() {
            let item = styles.addItem(withTitle:title,action:#selector(chooseDesign(_:)),keyEquivalent:"")
            item.target = self
            item.tag = index-1
            item.state = item.tag == (cat.fixedDesign?.rawValue ?? -1) ? .on : .off
        }
        let styleItem = menu.addItem(withTitle:"黑猫姿态",action:nil,keyEquivalent:"")
        styleItem.submenu = styles
        add(tap == nil ? "键盘联动待启用…" : "键盘联动已启用", #selector(enableKeyboard)).isEnabled = tap == nil
        add("打开打字测试窗…", #selector(testTyping))
        add("演示敲键效果", #selector(demo))
        menu.addItem(.separator())
        add(panel.ignoresMouseEvents ? "关闭鼠标穿透" : "开启鼠标穿透", #selector(toggleClickThrough))
        add(panel.isVisible ? "隐藏桌宠" : "显示桌宠", #selector(toggleVisibility))
        add("移回右下角", #selector(resetPosition))
        menu.addItem(.separator())
        add("退出黑猫", #selector(quit))
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func chooseDesign(_ sender: NSMenuItem) {
        cat.fixedDesign = BlackCatDesign(rawValue:sender.tag)
        UserDefaults.standard.set(sender.tag,forKey:"BlackCatFixedDesign")
        buildMenu()
    }
    @objc private func demo() {
        panel.orderFrontRegardless()
        demoFrame = 0
        buildMenu()
    }

    @objc private func testTyping() {
        if typingWindow == nil {
            let window = TypingWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 110),
                                      styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "黑猫 · 打字测试"
            window.isReleasedWhenClosed = false
            let hint = NSTextField(wrappingLabelWithString: "在这个窗口按 F、J 或 Shift，看猫扑向对应键位。\n要在其他 App 里联动，请在菜单栏 🐾 启用输入监控。")
            hint.frame = CGRect(x: 24, y: 15, width: 302, height: 72)
            window.contentView?.addSubview(hint)
            window.onKey = { [weak self] event in
                guard let self, self.tap == nil else { return }
                self.receiveKey(code: event.keyCode,
                                flags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)),
                                isModifier: event.type == .flagsChanged)
            }
            window.center()
            typingWindow = window
        }
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        typingWindow?.makeKeyAndOrderFront(nil)
        buildMenu()
    }

    @objc private func resetPosition() {
        guard let frame = NSScreen.main?.visibleFrame else { return }
        panel.setFrameOrigin(CGPoint(x: frame.maxX - panel.frame.width - 18, y: frame.minY + 12))
    }

    @objc private func toggleClickThrough() {
        panel.ignoresMouseEvents.toggle()
        buildMenu()
    }

    @objc private func toggleVisibility() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        buildMenu()
    }

    @objc private func enableKeyboard() {
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
            if let settings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(settings)
            }
        }
        refreshPermission()
        if tap == nil {
            let alert = NSAlert()
            alert.messageText = "在「输入监控」里打开奶牛猫桌宠"
            alert.informativeText = "如果列表里没有奶牛猫桌宠，用「+」添加这个 .app。系统提示重启时，选「退出并重新打开」。你也可以先在菜单栏打开打字测试窗。"
            alert.addButton(withTitle: "好")
            alert.addButton(withTitle: "退出并重新打开")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertSecondButtonReturn {
                let config = NSWorkspace.OpenConfiguration()
                config.createsNewApplicationInstance = true
                NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, error in
                    if error == nil { DispatchQueue.main.async { NSApp.terminate(nil) } }
                }
            }
        }
    }

    private func refreshPermission() {
        let allowed = CGPreflightListenEventAccess()
        if allowed, tap == nil {
            let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) |
                       (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                    options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
                if let context {
                    Unmanaged<DesktopCat>.fromOpaque(context).takeUnretainedValue().receive(type, event)
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
            if let tap {
                source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
                if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
                CGEvent.tapEnable(tap: tap, enable: true)
                buildMenu()
            }
        } else if !allowed, previouslyAllowed, let tap {
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            CFMachPortInvalidate(tap)
            self.tap = nil
            self.source = nil
            modifiers.removeAll()
            buildMenu()
        }
        previouslyAllowed = allowed
        let state = tap != nil ? "Listening" : (allowed ? "Event tap unavailable" : "Input Monitoring not granted")
        if state != reportedStatus {
            reportedStatus = state
            logger.notice("Keyboard status: \(state, privacy: .public)")
        }
    }

    private func receive(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard panel.isVisible else { return }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        receiveKey(code: code, flags: event.flags, isModifier: type == .flagsChanged)
    }

    private func receiveKey(code: UInt16, flags: CGEventFlags, isModifier: Bool) {
        if isModifier {
            guard let mask = modifierKeys[code] else { return }
            if !flags.contains(mask) || modifiers.remove(code) != nil {
                modifiers.remove(code)
                return
            }
            modifiers.insert(code)
        }
        let label = rows.joined().first(where: { $0.1 == code })?.0 ?? specialKeys[code]
        if let label { cat.hit(code: code, label: label); return }
        let numberKeys: [UInt16: String] = [18:"1",19:"2",20:"3",21:"4",23:"5",22:"6",26:"7",28:"8",25:"9",29:"0",24:"=",27:"-",30:"]",33:"[",39:"'",41:";",42:"\\",44:"/",50:"`"]
        if let label = numberKeys[code] { cat.hit(code: code, label: label) }
    }

    private func tick() {
        let time = ProcessInfo.processInfo.systemUptime
        if time > nextPermissionCheck {
            nextPermissionCheck = time + 2
            refreshPermission()
        }
        guard panel.isVisible else { return }
        let pointer = NSEvent.mouseLocation
        if let frame = demoFrame {
            lastPointer = pointer
            cat.animateDemo(frame: frame, at: time)
            demoFrame = frame < 155 ? frame + 1 : nil
            return
        }
        let dx = pointer.x - panel.frame.midX
        let dy = panel.frame.minY + panel.frame.height * 0.69 - pointer.y
        let distance = max(95, hypot(dx, dy))
        let travel = hypot(pointer.x - lastPointer.x, pointer.y - lastPointer.y)
        let speed = travel/max(0.01,time-lastSample)
        lastSample = time
        let count = CGEventSource.counterForEventType(.combinedSessionState,eventType:.scrollWheel)
        let scrolling = count != scrollCount
        scrollCount = count
        lastPointer = pointer
        cat.animate(at: time, toward: CGPoint(x: dx / distance * 8, y: dy / distance * 8),
                    moved: travel > 0.4, clicked: NSEvent.pressedMouseButtons != 0, speed:speed,scroll:scrolling)
    }
}

let app = NSApplication.shared
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--render-preview" {
    let cat = CatView(frame: NSRect(x: 0, y: 0, width: 600, height: 584))
    cat.previewBackground = true
    for frame in 0...129 { cat.animateDemo(frame: frame, at: 1 + Double(frame) / 30) }
    if let bitmap = cat.bitmapImageRepForCachingDisplay(in: cat.bounds) {
        cat.cacheDisplay(in: cat.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
} else if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--render-motion" {
    let cat = CatView(frame: NSRect(x: 0, y: 0, width: 250, height: 244))
    cat.previewBackground = true
    let url = URL(fileURLWithPath: CommandLine.arguments[2])
    guard let gif = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 78, nil),
          let bitmap = cat.bitmapImageRepForCachingDisplay(in: cat.bounds) else { exit(1) }
    CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for frame in 0..<156 {
        cat.animateDemo(frame: frame, at: 1 + Double(frame) / 30)
        if frame.isMultiple(of: 2) {
            cat.cacheDisplay(in: cat.bounds, to: bitmap)
            guard let image = bitmap.cgImage else { exit(1) }
            CGImageDestinationAddImage(gif, image,
                                       [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 15]] as CFDictionary)
        }
    }
    guard CGImageDestinationFinalize(gif) else { exit(1) }
} else {
    let delegate = DesktopCat()
    app.setActivationPolicy(.accessory)
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
