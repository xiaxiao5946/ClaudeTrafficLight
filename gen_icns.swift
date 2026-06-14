import AppKit

// Generate the icon using our TrafficLightIcon design
// We'll create it manually since we can't import our module here

let size = NSSize(width: 256, height: 256)
let image = NSImage(size: size)
image.lockFocus()

let bg = NSBezierPath(roundedRect: NSRect(x: 8, y: 8, width: 240, height: 240), xRadius: 48, yRadius: 48)
NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0).setFill()
bg.fill()
NSColor.white.withAlphaComponent(0.08).setStroke()
bg.lineWidth = 2
bg.stroke()

let dotR: CGFloat = 28
let cx: CGFloat = 88
let ys: [CGFloat] = [180, 128, 76]
let colors: [(CGFloat, CGFloat, CGFloat)] = [(1,0.15,0.15), (1,0.78,0), (0.15,0.88,0.25)]
for i in 0..<3 {
    let glow = NSBezierPath(ovalIn: NSRect(x: cx - dotR - 4, y: ys[i] - dotR - 4, width: dotR*2 + 8, height: dotR*2 + 8))
    NSColor(red: colors[i].0, green: colors[i].1, blue: colors[i].2, alpha: 0.10).setFill()
    glow.fill()
    let dot = NSBezierPath(ovalIn: NSRect(x: cx - dotR, y: ys[i] - dotR, width: dotR*2, height: dotR*2))
    NSColor(red: colors[i].0, green: colors[i].1, blue: colors[i].2, alpha: 1.0).setFill()
    dot.fill()
}

let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 72, weight: .bold),
    .foregroundColor: NSColor.white.withAlphaComponent(0.9)
]
let cc = "CC"
let ts = (cc as NSString).size(withAttributes: attrs)
(cc as NSString).draw(at: NSPoint(x: 156 + (72 - ts.width) / 2, y: (256 - ts.height) / 2), withAttributes: attrs)

image.unlockFocus()

// Save as iconset
let iconset = "/tmp/CTL.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [(16,"16x16"), (32,"16x16@2x"), (32,"32x32"), (64,"32x32@2x"), (128,"128x128"), (256,"128x128@2x"), (256,"256x256"), (512,"256x256@2x"), (512,"512x512"), (1024,"512x512@2x")]

for (sz, name) in sizes {
    let img = NSImage(size: NSSize(width: sz, height: sz))
    img.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: sz, height: sz))
    img.unlockFocus()
    let rep = img.tiffRepresentation!
    let bitmap = NSBitmapImageRep(data: rep)!
    let png = bitmap.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "\(iconset)/icon_\(name).png"))
}

// Use iconutil
let icns = "/tmp/CTL.icns"
try? FileManager.default.removeItem(atPath: icns)
Process.launchedProcess(launchPath: "/usr/bin/iconutil", arguments: ["-c", "icns", iconset]).waitUntilExit()
print("ICNS generated: \(icns)")
