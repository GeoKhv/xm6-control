enum AutomaticReconnectBackoff {
    private static let delaysInSeconds: [UInt64] = [2, 4, 8, 15, 30]

    static func delayNanoseconds(forAttempt attempt: Int) -> UInt64 {
        let index = min(max(attempt, 0), delaysInSeconds.count - 1)
        return delaysInSeconds[index] * 1_000_000_000
    }
}
