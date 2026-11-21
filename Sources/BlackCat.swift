import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

enum BlackCatDesign: Int, CaseIterable {
    case original, lanky, startled, sleepy
}

struct BlackCatPose {
    var mouse: CGFloat = 0
    var gaze = CGPoint.zero
    var blink: CGFloat = 0
    var keyPress: CGFloat = 0
    var leftPress: CGFloat = 0
    var leftTarget: CGPoint?
    var rightTarget: CGPoint?
    var excitement: CGFloat = 0
    var phase: CGFloat = 0
    var mix: SIMD4<Double>?
}

private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
private func ease(_ value: CGFloat) -> CGFloat {
    let unit = min(1,max(0,value))
    return unit*unit*(3-2*unit)
}
private func blend(_ start: CGPoint, _ end: CGPoint, _ amount: CGFloat) -> CGPoint {
    point(start.x+(end.x-start.x)*amount,start.y+(end.y-start.y)*amount)
}
private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
}
private let fur = color(0.075,0.077,0.085)
private let lime = color(0.79,0.91,0.31)
private let keyFace = color(0.973,0.974,0.945)
private let gold = color(0.98,0.74,0.20)
private let seam = color(0.26,0.265,0.265)

private struct Ink {
    let ctx: CGContext
    func shape(_ paint: CGColor, _ draw: (CGMutablePath) -> Void) {
        let path = CGMutablePath()
        draw(path)
        path.closeSubpath()
        ctx.setFillColor(paint)
        ctx.addPath(path)
        ctx.fillPath()
    }
    func stroke(_ paint: CGColor, _ width: CGFloat, _ draw: (CGMutablePath) -> Void) {
        let path = CGMutablePath()
        draw(path)
        ctx.setStrokeColor(paint)
        ctx.setLineWidth(width)
        ctx.addPath(path)
        ctx.strokePath()
    }
    func oval(_ paint: CGColor, _ x: CGFloat,_ y: CGFloat,_ width: CGFloat,_ height: CGFloat) {
        ctx.setFillColor(paint)
        ctx.fillEllipse(in: CGRect(x:x,y:y,width:width,height:height))
    }
}

private extension CGMutablePath {
    func start(_ x: CGFloat,_ y: CGFloat) { move(to: point(x,y)) }
    func line(_ x: CGFloat,_ y: CGFloat) { addLine(to: point(x,y)) }
    func cubic(_ x1: CGFloat,_ y1: CGFloat,_ x2: CGFloat,_ y2: CGFloat,_ x: CGFloat,_ y: CGFloat) {
        addCurve(to:point(x,y),control1:point(x1,y1),control2:point(x2,y2))
    }
}

struct BlackCatArtwork {
    static let size = CGSize(width: 280, height: 240)
    static func desk(_ across: CGFloat,_ depth: CGFloat,_ height: CGFloat = 0) -> CGPoint {
        let perspective = 1 + depth*0.12
        return point(160 + across*151/perspective + depth*5, 202 + (depth * -32 + across*7 - height)/perspective)
    }
    private static let mouseCenter = desk(-0.588,0.115,3)

    static func draw(_ design: BlackCatDesign, pose: BlackCatPose, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        let ink = Ink(ctx:ctx)
        let reach = max(0,min(1,pose.mouse))
        let press = max(0,min(1,pose.keyPress))
        var preset = SIMD4<Double>.zero
        preset[design.rawValue] = 1
        let weights = pose.mix ?? preset
        func mix(_ values: SIMD4<Double>) -> CGFloat {
            CGFloat((weights * values).sum())
        }
        let shift = mix([25,26,33,24]), torsoWidth = mix([34,29,37,38])
        let headSize = mix([0.96,0.90,1.01,0.99]), headY = mix([84,73,92,91])
        let tilt = mix([-0.045,-0.075,-0.19,0.085])
        let weight = ease(reach / 0.84)
        let settled = ease((reach-0.60)/0.40)
        let stepping = sin(.pi*reach)
        let pressing = ease(press)
        func body(_ across: CGFloat, _ level: CGFloat) -> CGPoint {
            let upper = ease(level)
            let center = 146 - shift*weight*upper + 3.5*settled*(1-upper)
            let widening = 1 + 0.08*stepping*sin(.pi*level) + 0.035*pressing
            return point(center + across*widening,
                         178 + (headY-178)*level + upper*(4*stepping+1.7*settled+2.8*pressing))
        }
        let head = body(0,1)
        let hip = body(0,0)
        ink.oval(CGColor(gray:0,alpha:0.10),hip.x-39,180,85,10)
        let tailLift = mix([0,0,-9,7]) + sin(pose.phase)*pose.excitement*6
        ink.stroke(fur,9) { path in
            path.start(hip.x+17,hip.y-9)
            path.cubic(hip.x+58,hip.y+2,hip.x+49,hip.y-33+tailLift,hip.x+75,hip.y-33+tailLift)
        }
        ink.shape(fur) { path in
            path.move(to:body(-18,0.83))
            path.addCurve(to:body(-torsoWidth,0.13),control1:body(-17,0.68),control2:body(-torsoWidth-4,0.33))
            path.addCurve(to:body(-15,-0.055),control1:body(-torsoWidth,0.025),control2:body(-25,-0.09))
            path.addCurve(to:body(15,-0.055),control1:body(-8,-0.027),control2:body(7,-0.02))
            path.addCurve(to:body(torsoWidth,0.11),control1:body(31,-0.12),control2:body(torsoWidth+3,-0.025))
            path.addCurve(to:body(19,0.84),control1:body(torsoWidth+3,0.37),control2:body(17,0.64))
        }
        let highlight = [(pose.leftTarget,pose.leftPress),(pose.rightTarget,press)].compactMap {
            $0.1 > 0.65 ? $0.0 : nil
        }
        drawDesk(ink, highlight:highlight)
        let mouseStep = ease((reach-0.10)/0.85)
        let keyStep = ease((press-0.06)/0.91)
        var left = blend(point(133,184),point(mouseCenter.x,mouseCenter.y-2),mouseStep)
        var right = blend(point(158,184),pose.rightTarget ?? desk(0.14,0.16,4),keyStep)
        left.y -= 8*sin(.pi*mouseStep)
        if let target = pose.leftTarget {
            left = blend(left,target,ease(pose.leftPress))
        }
        right.y -= 4*sin(.pi*keyStep)
        let leftAxilla = body(-13,0.27+0.23*mouseStep)
        let rightAxilla = body(13,0.27+0.14*keyStep)
        let leftWrist = point(left.x-5.0,left.y-4.0)
        let rightWrist = point(right.x+5.0,right.y-4.0)
        ink.shape(fur) { path in
            path.move(to:body(-20,0.92))
            path.addCurve(to:body(-23,0.68),control1:body(-19,0.83),control2:body(-22,0.75))
            path.addCurve(to:leftWrist,control1:body(-24,0.61),
                          control2:point(leftWrist.x+11*mouseStep,leftWrist.y-20))
            path.cubic(left.x-6.5-2*mouseStep,left.y-1,left.x-6.8,left.y+3.6,left.x-2,left.y+4.1)
            path.cubic(left.x+2.7,left.y+4.6,left.x+5.5,left.y+2.5,left.x+5.5,left.y-1.6)
            path.addCurve(to:leftAxilla,control1:point(left.x+5.5,left.y-10),
                          control2:point(leftAxilla.x-3-8*mouseStep,leftAxilla.y+16))
            path.addCurve(to:body(0,0.15),control1:point(leftAxilla.x+3,leftAxilla.y-8),control2:body(-9,0.15))
            path.addCurve(to:rightAxilla,control1:body(10,0.15),control2:point(rightAxilla.x-3,rightAxilla.y-8))
            path.addCurve(to:point(right.x-5.5,right.y-2),control1:point(rightAxilla.x+3,rightAxilla.y+9),
                          control2:point(right.x-5.5,right.y-11))
            path.cubic(right.x-5.5,right.y+2,right.x-3,right.y+4.6,right.x+1.5,right.y+4.2)
            path.cubic(right.x+6.5,right.y+4,right.x+7,right.y,rightWrist.x,rightWrist.y)
            path.addCurve(to:body(23,0.68),control1:point(rightWrist.x-3*keyStep,rightWrist.y-17),control2:body(25,0.60))
            path.addCurve(to:body(20,0.92),control1:body(21,0.76),control2:body(19,0.85))
        }
        for (paw,side,amount) in [(left,-1.0,mouseStep),(right,1.0,keyStep)] {
            ink.stroke(seam.copy(alpha:0.70*(1-amount))!,0.65) { path in
                path.move(to:point(paw.x-side*4.5,paw.y-3))
                path.addQuadCurve(to:body(side*8,0.23),control:point(paw.x-side*4.2,paw.y-12))
            }
        }
        ctx.saveGState()
        ctx.translateBy(x:head.x,y:head.y)
        ctx.rotate(by:tilt*(0.35+0.65*reach))
        ctx.scaleBy(x:headSize,y:headSize)
        let earTop = mix([-29,-34,-29,-25])
        ink.shape(fur) { path in
            path.start(-28,-5)
            path.cubic(-30,-12,-27,earTop-1,-23,earTop)
            path.cubic(-20,earTop-1,-15,-20,-12,-18)
            path.cubic(-4,-20,5,-20,12,-18)
            path.cubic(18,-23,21,earTop-2,25,earTop-1)
            path.cubic(28,earTop,29,-15,28,-7)
            path.cubic(36,11,24,23,4,24)
            path.cubic(-16,25,-37,16,-28,-5)
        }
        let gaze = point(max(-1,min(1,pose.gaze.x)),max(-1,min(1,pose.gaze.y)))
        for side in [-1.0,1.0] {
            let wide = mix([8.9,8.9,10.4,8.9]), tall = mix([7.9,7.9,10.6,4.2])
            let eyeY = side*mix([0,0,1.3,0])-1
            let pupilWidth = mix([3.2,3.2,2.5,3.2])
            let factor = 1-max(0,min(1,pose.blink))
            ctx.saveGState()
            ctx.translateBy(x:side*13.0,y:eyeY)
            ctx.rotate(by:side * mix([0,0,0,-0.16]))
            let eyeRect = CGRect(x:-wide,y:-max(0.6,tall*factor),width:wide*2,height:max(1.2,tall*factor*2))
            ctx.addEllipse(in:eyeRect); ctx.clip()
            ctx.setFillColor(lime); ctx.fill(eyeRect)
            if factor > 0.13 {
                ink.oval(fur, gaze.x*(wide-pupilWidth-0.8)-pupilWidth, gaze.y*tall*0.45 - tall*0.70, pupilWidth*2, tall*1.43)
            }
            ctx.restoreGState()
            for strand in 0..<3 {
                let offset = CGFloat(strand)
                ink.stroke(CGColor(gray:0.68,alpha:0.85),0.6) { path in
                    path.start(side*17,10+offset*2)
                    path.line(side*(23-offset),9+offset*3)
                }
            }
        }
        ctx.restoreGState()
    }

    static func keyCenter(row: Int, column: Int) -> CGPoint {
        let offset = row == 4 && column == 4 ? 0.1745 : 0.0335
        return desk(-0.452+CGFloat(column)*0.0708+offset,-0.26+CGFloat(row)*0.17+0.079,4.2)
    }
    private static func drawDesk(_ ink: Ink, highlight: [CGPoint]) {
        func tile(_ left: CGFloat,_ near: CGFloat,_ right: CGFloat,_ far: CGFloat,_ height: CGFloat,_ fill: CGColor) {
            ink.shape(fill) { path in
                path.move(to:desk(left,near,height)); path.addLine(to:desk(right,near,height))
                path.addLine(to:desk(right,far,height)); path.addLine(to:desk(left,far,height))
            }
        }
        tile(-0.47,-0.31,0.48,0.62,-1.6,fur)
        tile(-0.47,-0.31,0.48,0.62,2.7,color(0.29,0.29,0.29))
        for row in 0..<5 {
            for column in 0..<13 {
                if row == 4 && (5...8).contains(column) { continue }
                let left = -0.452+CGFloat(column)*0.0708
                let near = -0.26+CGFloat(row)*0.17
                let width = row == 4 && column == 4 ? 0.349 : 0.067
                let center = keyCenter(row:row,column:column)
                let active = highlight.contains { abs($0.x-center.x)<0.5 && abs($0.y-center.y)<0.5 }
                tile(left,near,left+width,near+0.158,active ? 3.4 : 4.2,
                     active ? lime : (row == 3 && column == 0)||(row == 0 && column == 12) ? gold : keyFace)
            }
        }
        let center = mouseCenter
        ink.oval(CGColor(gray:0,alpha:0.14),center.x-8.7,center.y-5.5,18.3,16.5)
        ink.oval(color(0.48,0.48,0.46),center.x-8.4,center.y-8,17.3,17.1)
        ink.oval(keyFace,center.x-8.4,center.y-9.3,17.1,17)
        ink.stroke(gold,1.2) { path in path.start(center.x,center.y+1); path.line(center.x-0.5,center.y+4) }
    }
}

#if SHEET
@main struct BlackCatSheet {
    static func main() {
        let width = 1120, height = 648, scale = 2
        guard let ctx = CGContext(data:nil,width:width*scale,height:height*scale,bitsPerComponent:8,bytesPerRow:0,
                                  space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)
        else { exit(1) }
        ctx.translateBy(x:0,y:CGFloat(height*scale)); ctx.scaleBy(x:CGFloat(scale),y:-CGFloat(scale))
        func label(_ value: String,_ x: CGFloat,_ y: CGFloat,_ size: CGFloat,_ weight: NSFont.Weight) {
            ctx.saveGState()
            ctx.translateBy(x:x,y:y); ctx.scaleBy(x:1,y:-1)
            let string = NSAttributedString(string:value,attributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),
                                                                       .foregroundColor:NSColor.darkGray])
            ctx.textPosition = .zero
            CTLineDraw(CTLineCreateWithAttributedString(string),ctx)
            ctx.restoreGState()
        }
        let names = ["A   原片坐姿","B   细长高耳","C   突然警觉","D   困困值班"]
        for design in BlackCatDesign.allCases {
            let index = design.rawValue
            ctx.saveGState()
            ctx.translateBy(x:CGFloat(index%2)*560,y:CGFloat(index/2)*324)
            let base: CGFloat = index == 1 || index == 2 ? 0.915 : 0.958
            ctx.setFillColor(color(base,base+0.004,base-0.014)); ctx.fill(CGRect(x:0,y:0,width:560,height:324))
            label(names[index],24,34,19,.semibold)
            for state in 0..<2 {
                ctx.saveGState()
                ctx.translateBy(x:CGFloat(state*280),y:38)
                let pose = BlackCatPose(mouse:CGFloat(state),gaze:state == 0 ? .zero : point(design == .startled ? 0.85 : -0.68,design == .startled ? -0.8 : 0.32))
                BlackCatArtwork.draw(design,pose:pose,in:ctx)
                ctx.restoreGState()
                label(state == 0 ? "端坐" : "握鼠标", CGFloat(state*280+117),286,13,.regular)
            }
            ctx.restoreGState()
        }
        guard CommandLine.arguments.count == 2, let image = ctx.makeImage(),
              let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath:CommandLine.arguments[1]) as CFURL,UTType.png.identifier as CFString,1,nil) else { exit(1) }
        CGImageDestinationAddImage(destination,image,nil)
        guard CGImageDestinationFinalize(destination) else { exit(1) }
    }
}
#endif
