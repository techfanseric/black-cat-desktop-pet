import AppKit
import ImageIO
import UniformTypeIdentifiers

@main struct BlackCatMotion {
    static func main() {
        let frameCount = 120
        let width = 840, height = 690
        guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL,
                                                                 UTType.gif.identifier as CFString,frameCount,nil) else { exit(1) }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
        for frame in 0..<frameCount {
            autoreleasepool {
                guard let ctx = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,
                                          space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)
                else { exit(1) }
                ctx.translateBy(x:0,y:CGFloat(height)); ctx.scaleBy(x:1.5,y:-1.5)
                let time = Double(frame) / 25
                func ramp(_ start: Double,_ end: Double) -> Double { min(1,max(0,(time-start)/(end-start))) }
                let reach = ramp(0.40,1.55)-ramp(2.85,4.13)
                let key = ramp(1.7,1.90)-ramp(2.0,2.26)+ramp(2.37,2.57)-ramp(2.69,2.94)
                for design in BlackCatDesign.allCases {
                    let index = design.rawValue
                    ctx.saveGState()
                    ctx.translateBy(x:CGFloat(index%2)*280,y:CGFloat(index/2)*230)
                    let shade = index == 1 || index == 2 ? 0.918 : 0.958
                    ctx.setFillColor(CGColor(srgbRed:shade,green:shade+0.004,blue:shade-0.014,alpha:1))
                    ctx.fill(CGRect(x:0,y:0,width:280,height:230))
                    let glance = ramp(0.20,0.60)-ramp(3.7,4.2)
                    let direction = design == .startled ? 0.86 : -0.72
                    let blink = ramp(4.18,4.27)-ramp(4.29,4.43)
                    BlackCatArtwork.draw(design,pose:BlackCatPose(mouse:reach,gaze:CGPoint(x:glance*direction,y:-glance*0.55+key),
                                                                  blink:blink,keyPress:key),in:ctx)
                    ctx.restoreGState()
                }
                guard let image = ctx.makeImage() else { exit(1) }
                CGImageDestinationAddImage(destination,image,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.04]] as CFDictionary)
            }
        }
        guard CGImageDestinationFinalize(destination) else { exit(1) }
    }
}
