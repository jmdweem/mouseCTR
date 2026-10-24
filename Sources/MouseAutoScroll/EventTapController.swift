import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
final class EventTapController {
  enum Status: Equatable {
    case stopped
    case ready
    case scrolling
    case permissionRequired
    case failed(String)

    var menuText: String {
      switch self {
      case .stopped:
        return "状态：已停用"
      case .ready:
        return "状态：等待中键"
      case .scrolling:
        return "状态：自动滚动中（任意鼠标键退出）"
      case .permissionRequired:
        return "状态：需要输入监控和辅助功能权限"
      case .failed(let message):
        return "状态：\(message)"
      }
    }
  }

  var onStatusChange: ((Status) -> Void)?

  private(set) var status: Status = .stopped {
    didSet {
      guard oldValue != status else { return }
      onStatusChange?(status)
    }
  }

  private let indicator = AnchorIndicator()
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var timer: DispatchSourceTimer?
  private var anchor = CGPoint.zero
  private var scrollRemainder: CGFloat = 0
  private var lastTick = ContinuousClock.now
  private var hasPostedScroll = false
  private var consumeActivationMiddleUp = false
  private var targetProcessIdentifier: pid_t?
  private var enabled = true

  private let syntheticEventMarker: Int64 = 0x4D_41_53_43  // "MASC"
  private lazy var eventSource: CGEventSource? = {
    let source = CGEventSource(stateID: .combinedSessionState)
    source?.localEventsSuppressionInterval = 0
    return source
  }()

  func start(requestPermissions: Bool) {
    enabled = true
    tearDownEventTap()

    guard checkPermissions(requestIfNeeded: requestPermissions) else {
      status = .permissionRequired
      return
    }

    installEventTap()
  }

  func setEnabled(_ shouldEnable: Bool) {
    enabled = shouldEnable
    if shouldEnable {
      start(requestPermissions: false)
    } else {
      stopAutoScroll()
      tearDownEventTap()
      status = .stopped
    }
  }

  func stopAutoScroll() {
    guard status == .scrolling else { return }

    timer?.cancel()
    timer = nil

    if hasPostedScroll {
      postScroll(delta: 0, phase: .ended)
    }

    indicator.hide()
    scrollRemainder = 0
    hasPostedScroll = false
    targetProcessIdentifier = nil
    status = enabled && eventTap != nil ? .ready : .stopped
  }

  func applicationEnvironmentChanged() {
    stopAutoScroll()
  }

  private func checkPermissions(requestIfNeeded: Bool) -> Bool {
    var canListen = CGPreflightListenEventAccess()
    var canPost = CGPreflightPostEventAccess()
    var accessibilityTrusted = AXIsProcessTrusted()

    if requestIfNeeded {
      if !canListen {
        canListen = CGRequestListenEventAccess()
      }
      if !canPost {
        canPost = CGRequestPostEventAccess()
      }
      if !accessibilityTrusted {
        let options =
          [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
          ] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
      }
    }

    return canListen && canPost && accessibilityTrusted
  }

  private func installEventTap() {
    let mask = Self.eventMask(for: [
      .leftMouseDown,
      .rightMouseDown,
      .otherMouseDown,
      .otherMouseUp,
      .keyDown,
    ])

    let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: { _, type, event, userInfo in
          guard let userInfo else { return Unmanaged.passUnretained(event) }
          let controller = Unmanaged<EventTapController>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
          return controller.handleEvent(type: type, event: event)
        },
        userInfo: opaqueSelf
      )
    else {
      status = .failed("无法创建全局事件监听")
      return
    }

    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    eventTap = tap
    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    status = .ready
  }

  private func tearDownEventTap() {
    stopAutoScroll()

    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
    }
    runLoopSource = nil
    eventTap = nil
  }

  private nonisolated func handleEvent(
    type: CGEventType,
    event: CGEvent
  ) -> Unmanaged<CGEvent>? {
    MainActor.assumeIsolated {
      if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let eventTap {
          CGEvent.tapEnable(tap: eventTap, enable: true)
        }
        return Unmanaged.passUnretained(event)
      }

      let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)

      if type == .otherMouseUp,
        buttonNumber == 2,
        consumeActivationMiddleUp
      {
        consumeActivationMiddleUp = false
        return nil
      }

      if status == .scrolling {
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
          stopAutoScroll()
          return Unmanaged.passUnretained(event)
        }

        if type == .keyDown,
          event.getIntegerValueField(.keyboardEventKeycode) == 53
        {
          stopAutoScroll()
          return nil
        }

        return Unmanaged.passUnretained(event)
      }

      if status == .ready,
        type == .otherMouseDown,
        buttonNumber == 2
      {
        beginAutoScroll(at: event.location)
        consumeActivationMiddleUp = true
        return nil
      }

      return Unmanaged.passUnretained(event)
    }
  }

  private func beginAutoScroll(at point: CGPoint) {
    anchor = point
    scrollRemainder = 0
    hasPostedScroll = false
    targetProcessIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier
    lastTick = .now
    indicator.show(atQuartzPoint: point)
    status = .scrolling

    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(
      deadline: .now(),
      repeating: .milliseconds(8),
      leeway: .milliseconds(1)
    )
    timer.setEventHandler { [weak self] in
      self?.tick()
    }
    self.timer = timer
    timer.resume()
  }

  private func tick() {
    guard status == .scrolling else { return }

    if NSWorkspace.shared.frontmostApplication?.processIdentifier != targetProcessIdentifier {
      stopAutoScroll()
      return
    }

    guard let pointerEvent = CGEvent(source: nil) else { return }

    let now = ContinuousClock.now
    let elapsed = lastTick.duration(to: now)
    lastTick = now
    let seconds = min(1.0 / 30.0, max(0, elapsed.timeInterval))

    let displacement = pointerEvent.location.y - anchor.y
    let speed = ScrollPhysics.wheelSpeed(forVerticalDisplacement: displacement)
    guard speed != 0 else {
      scrollRemainder = 0
      return
    }

    scrollRemainder += speed * seconds
    let wholeDelta = scrollRemainder.rounded(.towardZero)
    guard abs(wholeDelta) >= 1 else { return }
    scrollRemainder -= wholeDelta

    let phase: CGScrollPhase = hasPostedScroll ? .changed : .began
    postScroll(delta: Int32(wholeDelta), phase: phase)
    hasPostedScroll = true
  }

  private func postScroll(delta: Int32, phase: CGScrollPhase) {
    guard
      let event = CGEvent(
        scrollWheelEvent2Source: eventSource,
        units: .pixel,
        wheelCount: 1,
        wheel1: delta,
        wheel2: 0,
        wheel3: 0
      )
    else { return }

    // Do not overwrite the scroll event's location with the anchor. On recent
    // macOS versions, posting a scroll event with a stale fixed location can
    // feed that location back into the cursor state and pull the pointer
    // toward the anchor. The anchor is only a reference for speed/direction;
    // CGEvent supplies the current pointer location for event delivery.
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(delta))
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
    event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
    event.post(tap: .cgSessionEventTap)
  }

  private static func eventMask(for types: [CGEventType]) -> CGEventMask {
    types.reduce(0) { mask, type in
      mask | (CGEventMask(1) << type.rawValue)
    }
  }
}

extension Duration {
  fileprivate var timeInterval: TimeInterval {
    let components = self.components
    return TimeInterval(components.seconds)
      + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
  }
}
