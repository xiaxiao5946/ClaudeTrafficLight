import AppKit

/// Generates a hand-drawn traffic-light NSImage for the menu bar status item.
/// Three colored circles (red / yellow / green) at 5px dots on a transparent
/// 30×18 canvas. Works on both light and dark menu bars (solid bright colors).
enum TrafficLightIcon {

    struct State {
        var redOn: Bool
        var yellowOn: Bool
        var greenOn: Bool
        var flashMask: UInt8 = 0  // bitmask: bit0=red, bit1=yellow, bit2=green
    }

    static func draw(state: State) -> NSImage {
        let size = NSSize(width: 30, height: 18)
        let image = NSImage(size: size)
        image.isTemplate = false

        image.lockFocus()

        let dotR: CGFloat = 5
        let y: CGFloat = 9
        let xs: [CGFloat] = [6, 15, 24]

        let onColors: [(red: CGFloat, green: CGFloat, blue: CGFloat)] = [
            (1.0, 0.15, 0.15),  // bright red
            (1.0, 0.78, 0.00),  // amber
            (0.15, 0.88, 0.25),  // bright green
        ]
        let offAlpha: CGFloat = 0.22

        let ons = [state.redOn, state.yellowOn, state.greenOn]
        let flashes = [(state.flashMask & 1) != 0, (state.flashMask & 2) != 0, (state.flashMask & 4) != 0]

        for i in 0..<3 {
            let path = NSBezierPath(
                ovalIn: NSRect(x: xs[i] - dotR / 2, y: y - dotR / 2,
                               width: dotR, height: dotR)
            )

            if ons[i] {
                // Draw glow
                let glow = NSBezierPath(
                    ovalIn: NSRect(x: xs[i] - dotR / 2 - 2, y: y - dotR / 2 - 2,
                                   width: dotR + 4, height: dotR + 4)
                )
                NSColor(red: onColors[i].red, green: onColors[i].green,
                        blue: onColors[i].blue, alpha: 0.15).setFill()
                glow.fill()

                // Draw solid dot
                let c = onColors[i]
                NSColor(red: c.red, green: c.green, blue: c.blue, alpha: 1.0).setFill()
                path.fill()
            } else if flashes[i] {
                // Flash on: bright but brief
                let c = onColors[i]
                NSColor(red: c.red, green: c.green, blue: c.blue, alpha: 0.7).setFill()
                path.fill()
            } else {
                // Off: dim
                NSColor.systemGray.withAlphaComponent(offAlpha).setFill()
                path.fill()
            }
        }

        image.unlockFocus()
        return image
    }

    /// Larger square icon for notifications
    static func drawNotificationIcon(state: State) -> NSImage {
        let size = NSSize(width: 48, height: 48)
        let image = NSImage(size: size)
        image.isTemplate = false

        image.lockFocus()

        let dotR: CGFloat = 10
        let xs: [CGFloat] = [12, 24, 36]
        let y: CGFloat = 24

        let onColors: [(red: CGFloat, green: CGFloat, blue: CGFloat)] = [
            (1.0, 0.15, 0.15),
            (1.0, 0.78, 0.00),
            (0.15, 0.88, 0.25),
        ]
        let offAlpha: CGFloat = 0.18

        let ons = [state.redOn, state.yellowOn, state.greenOn]

        for i in 0..<3 {
            let path = NSBezierPath(
                ovalIn: NSRect(x: xs[i] - dotR / 2, y: y - dotR / 2,
                               width: dotR, height: dotR)
            )
            if ons[i] {
                let glow = NSBezierPath(
                    ovalIn: NSRect(x: xs[i] - dotR / 2 - 3, y: y - dotR / 2 - 3,
                                   width: dotR + 6, height: dotR + 6)
                )
                NSColor(red: onColors[i].red, green: onColors[i].green,
                        blue: onColors[i].blue, alpha: 0.12).setFill()
                glow.fill()
                let c = onColors[i]
                NSColor(red: c.red, green: c.green, blue: c.blue, alpha: 1.0).setFill()
                path.fill()
            } else {
                NSColor.systemGray.withAlphaComponent(offAlpha).setFill()
                path.fill()
            }
        }

        image.unlockFocus()
        return image
    }
}
