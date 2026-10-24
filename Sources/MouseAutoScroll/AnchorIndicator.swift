import AppKit
import CoreGraphics

@MainActor
final class AnchorIndicator {
  private let panel: NSPanel

  init() {
    let size = NSSize(width: 42, height: 42)
    panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.ignoresMouseEvents = true
    panel.level = .statusBar
    panel.collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .stationary,
      .ignoresCycle,
    ]
    panel.contentView = AnchorIndicatorView(frame: NSRect(origin: .zero, size: size))
  }

  func show(atQuartzPoint point: CGPoint) {
    guard let appKitPoint = Self.appKitPoint(fromQuartzPoint: point) else { return }

    let frame = panel.frame
    panel.setFrameOrigin(
      NSPoint(
        x: appKitPoint.x - frame.width / 2,
        y: appKitPoint.y - frame.height / 2
      ))
    panel.orderFrontRegardless()
  }

  func hide() {
    panel.orderOut(nil)
  }

  private static func appKitPoint(fromQuartzPoint point: CGPoint) -> NSPoint? {
    for screen in NSScreen.screens {
      guard
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
      else { continue }

      let displayBounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
      guard displayBounds.contains(point) else { continue }

      return NSPoint(
        x: screen.frame.minX + point.x - displayBounds.minX,
        y: screen.frame.maxY - (point.y - displayBounds.minY)
      )
    }
    return nil
  }
}

private final class AnchorIndicatorView: NSView {
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    let circleRect = bounds.insetBy(dx: 2, dy: 2)
    NSColor.controlBackgroundColor.withAlphaComponent(0.94).setFill()
    NSBezierPath(ovalIn: circleRect).fill()

    NSColor.labelColor.withAlphaComponent(0.85).setStroke()
    let outline = NSBezierPath(ovalIn: circleRect)
    outline.lineWidth = 1.5
    outline.stroke()

    guard
      let symbol = NSImage(
        systemSymbolName: "arrow.up.and.down",
        accessibilityDescription: "自动滚动锚点"
      )
    else { return }

    let configuration = NSImage.SymbolConfiguration(pointSize: 21, weight: .semibold)
    let configured = symbol.withSymbolConfiguration(configuration) ?? symbol
    configured.isTemplate = true

    NSColor.labelColor.set()
    configured.draw(
      in: bounds.insetBy(dx: 10, dy: 8),
      from: .zero,
      operation: .sourceOver,
      fraction: 0.9,
      respectFlipped: true,
      hints: nil
    )
  }
}
