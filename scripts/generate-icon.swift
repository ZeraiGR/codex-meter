import AppKit
import Foundation

let directory=URL(fileURLWithPath:CommandLine.arguments[1])
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
for (name,size) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    let context=NSGraphicsContext(bitmapImageRep:rep)!
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
    let scale=CGFloat(size)/1024
    context.cgContext.scaleBy(x:scale,y:scale)
    let body=NSBezierPath(roundedRect:NSRect(x:64,y:64,width:896,height:896),xRadius:208,yRadius:208)
    NSGradient(starting:NSColor(srgbRed:0.12,green:0.19,blue:0.23,alpha:1),ending:NSColor(srgbRed:0.035,green:0.07,blue:0.09,alpha:1))!.draw(in:body,angle:-90)
    let ring=NSBezierPath();ring.appendArc(withCenter:NSPoint(x:512,y:512),radius:265,startAngle:-40,endAngle:220,clockwise:false);ring.lineWidth=62;ring.lineCapStyle = .round
    NSColor(srgbRed:0.15,green:0.26,blue:0.28,alpha:1).setStroke();ring.stroke()
    let arc=NSBezierPath();arc.appendArc(withCenter:NSPoint(x:512,y:512),radius:265,startAngle:30,endAngle:220,clockwise:false);arc.lineWidth=62;arc.lineCapStyle = .round
    NSColor(srgbRed:0.1,green:0.86,blue:0.7,alpha:1).setStroke();arc.stroke()
    let needle=NSBezierPath();needle.move(to:NSPoint(x:512,y:512));needle.line(to:NSPoint(x:644,y:660));needle.lineWidth=35;needle.lineCapStyle = .round;NSColor.white.setStroke();needle.stroke()
    NSColor.white.setFill();NSBezierPath(ovalIn:NSRect(x:478,y:478,width:68,height:68)).fill()
    let dash=NSBezierPath(roundedRect:NSRect(x:418,y:252,width:188,height:40),xRadius:20,yRadius:20);NSColor(srgbRed:0.1,green:0.86,blue:0.7,alpha:1).setFill();dash.fill()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent(name+".png"))
}
