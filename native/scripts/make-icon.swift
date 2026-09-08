import AppKit
let destination=URL(fileURLWithPath:CommandLine.arguments[1])
try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
for (points,scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let size=points*scale
    let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
    let s=CGFloat(size)
    NSColor(calibratedWhite:0.12,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:s*0.065,y:s*0.065,width:s*0.87,height:s*0.87),xRadius:s*0.2,yRadius:s*0.2).fill()
    NSColor(calibratedRed:0.94,green:0.91,blue:0.81,alpha:1).setStroke()
    let circle=NSBezierPath(ovalIn:NSRect(x:s*0.30,y:s*0.30,width:s*0.40,height:s*0.40)); circle.lineWidth=s*0.046; circle.stroke()
    for i in 0..<8 {
        let a=CGFloat(i)*CGFloat.pi/4
        let ray=NSBezierPath(); ray.lineCapStyle = .round; ray.lineWidth=s*0.033
        ray.move(to:NSPoint(x:s*(0.5+cos(a)*0.286),y:s*(0.5+sin(a)*0.286)))
        ray.line(to:NSPoint(x:s*(0.5+cos(a)*0.335),y:s*(0.5+sin(a)*0.335))); ray.stroke()
    }
    let hand=NSBezierPath();hand.lineCapStyle = .round;hand.lineJoinStyle = .round;hand.lineWidth=s*0.036
    hand.move(to:NSPoint(x:s*0.5,y:s*0.62));hand.line(to:NSPoint(x:s*0.5,y:s*0.5));hand.line(to:NSPoint(x:s*0.59,y:s*0.45));hand.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let suffix=scale == 2 ? "@2x" : ""
    try bitmap.representation(using:.png,properties:[:])!.write(to:destination.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
}
