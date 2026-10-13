// A deterministic native app symbol in the existing coral brand color.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
let size=1024
let context=CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red:0.055,green:0.063,blue:0.078,alpha:1));context.fill(CGRect(x:0,y:0,width:size,height:size))
context.setFillColor(CGColor(red:1,green:0.39,blue:0.34,alpha:1));context.addPath(CGPath(roundedRect:CGRect(x:150,y:226,width:724,height:572),cornerWidth:128,cornerHeight:128,transform:nil));context.fillPath()
context.setFillColor(CGColor(red:1,green:1,blue:1,alpha:1));context.move(to:CGPoint(x:424,y:370));context.addLine(to:CGPoint(x:424,y:654));context.addLine(to:CGPoint(x:667,y:512));context.closePath();context.fillPath()
let image=context.makeImage()!
let output=URL(fileURLWithPath:CommandLine.arguments[1])
let destination=CGImageDestinationCreateWithURL(output as CFURL,UTType.png.identifier as CFString,1,nil)!
CGImageDestinationAddImage(destination,image,nil)
precondition(CGImageDestinationFinalize(destination))
