import Foundation

public struct RestartPolicy: Sendable {
    public let maxAutomaticRestarts: Int
    public let window: TimeInterval
    private var crashTimestamps: [Date]

    public init(maxAutomaticRestarts: Int = 1, window: TimeInterval = 60, crashTimestamps: [Date] = []) {
        self.maxAutomaticRestarts = maxAutomaticRestarts
        self.window = window
        self.crashTimestamps = crashTimestamps
    }

    public mutating func registerCrash(at date: Date = Date()) -> Bool {
        crashTimestamps.append(date)
        let cutoff = date.addingTimeInterval(-window)
        crashTimestamps = crashTimestamps.filter { $0 >= cutoff }
        return crashTimestamps.count <= maxAutomaticRestarts
    }

    public mutating func reset() {
        crashTimestamps.removeAll()
    }
}
