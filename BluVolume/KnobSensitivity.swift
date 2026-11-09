import Foundation

/// Converts finger rotation into a volume change.
///
/// This is the heart of the "fine control" behaviour: the more degrees you
/// have to turn per percent, the easier it is to land exactly on 7, 8 or 9 %.
enum KnobSensitivity {
    /// - Parameters:
    ///   - degrees: Rotation since the previous touch event. Positive = clockwise (louder).
    ///   - currentVolume: The volume before this change (0...100, may be fractional).
    ///   - degreesPerStep: How many degrees make one percent, from the settings
    ///     (e.g. 4 rotations for 0–100 % → 14.4° per percent).
    /// - Returns: The change in volume, in percent (may be fractional).
    static func volumeDelta(forDegrees degrees: Double,
                            currentVolume: Double,
                            degreesPerStep: Double) -> Double {
        // Linear: every percent costs the same rotation, across the whole scale.
        //
        // Want it even finer at low volume, where your Powernode is most
        // sensitive? This is the place to shape that curve, for example by
        // making `degreesPerStep` larger when `currentVolume` is below ~15.
        return degrees / degreesPerStep
    }
}
