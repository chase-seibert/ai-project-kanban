import AppKit

// Code-native artwork: a small three-lane board. No downloaded/generated bitmap source.
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
  let drawing = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: drawing, flipped: false)
  let context = NSGraphicsContext.current!.cgContext
  context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
  let background = NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024))
  NSGradient(starting: NSColor(red: 0.25, green: 0.19, blue: 0.67, alpha: 1),
             ending: NSColor(red: 0.48, green: 0.36, blue: 0.95, alpha: 1))!.draw(in: background, angle: 55)
  for (index, height) in [440.0, 570.0, 700.0].enumerated() {
    let x = 182.0 + Double(index) * 226.0
    NSColor.white.withAlphaComponent(index == 2 ? 1 : 0.8).setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: 162, width: 184, height: height), xRadius: 48, yRadius: 48).fill()
    NSColor(red: 0.37, green: 0.27, blue: 0.78, alpha: 0.6).setFill()
    NSBezierPath(roundedRect: NSRect(x: x + 37, y: height + 79, width: 110, height: 14), xRadius: 7, yRadius: 7).fill()
  }
  NSGraphicsContext.restoreGraphicsState()
  let bitmap = NSBitmapImageRep(cgImage: drawing.makeImage()!)
  try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("icon-\(size).png"))
}
