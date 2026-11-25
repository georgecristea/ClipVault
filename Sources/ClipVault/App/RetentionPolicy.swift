import Foundation

/// How long unpinned clips are kept, and the ranges of the controls that set it.
enum RetentionPolicy {
    static let sliderRange = 5...365
    static let step = 5
    static let fieldRange = 1...3650

    /// Clips last copied before this date are deleted; nil keeps everything.
    static func cutoff(days: Int, keepForever: Bool, now: Date) -> Date? {
        keepForever ? nil : now.addingTimeInterval(-Double(clampField(days)) * 86_400)
    }

    /// The slider position for a day count: the nearest step within the slider range.
    static func sliderValue(for days: Int) -> Int {
        let stepped = Int((Double(days) / Double(step)).rounded()) * step
        return min(max(stepped, sliderRange.lowerBound), sliderRange.upperBound)
    }

    static func clampField(_ days: Int) -> Int {
        min(max(days, fieldRange.lowerBound), fieldRange.upperBound)
    }

    /// Ask before applying a shorter period only when it would delete clips.
    static func needsConfirmation(affected: Int) -> Bool { affected > 0 }
}
