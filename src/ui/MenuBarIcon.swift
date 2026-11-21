import AppKit

/// The status item follows transport health before the System EQ switch.
enum MenuBarIconState: Equatable {
    case on, off, blocked

    static func choose(status: RoutingStatus, isBypassed: Bool) -> Self {
        switch status {
        case .error, .driverNotInstalled: .blocked
        case .active: isBypassed ? .off : .on
        case .idle, .starting: .off
        }
    }
}

extension MenuBarIconState {
    @MainActor
    func image() -> NSImage {
        // The dot-matrix mark from Resources; off is dimmed, blocked is crossed.
        let mark = NSImage(named: "MenuBarIcon")
        let size = mark?.size ?? NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            mark?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: self == .on ? 1 : 0.45)
            if self == .blocked {
                NSColor.black.set()
                let cross = NSBezierPath()
                cross.move(to: NSPoint(x: 1, y: 1))
                cross.line(to: NSPoint(x: size.width - 1, y: size.height - 1))
                cross.lineWidth = 1.4
                cross.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
