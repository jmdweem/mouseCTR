import CoreGraphics
import Foundation

enum ScrollPhysics {
  static let deadZone: CGFloat = 16
  static let maximumSpeed: CGFloat = 2_400

  /// Converts the pointer's vertical displacement from the anchor into
  /// Quartz wheel points per second. Positive screen displacement is down,
  /// while a negative wheel delta scrolls the document down.
  static func wheelSpeed(forVerticalDisplacement displacement: CGFloat) -> CGFloat {
    let distance = abs(displacement)
    guard distance > deadZone else { return 0 }

    let effectiveDistance = distance - deadZone
    let magnitude = min(maximumSpeed, 1.1 * pow(effectiveDistance, 1.35))
    return displacement > 0 ? -magnitude : magnitude
  }
}
