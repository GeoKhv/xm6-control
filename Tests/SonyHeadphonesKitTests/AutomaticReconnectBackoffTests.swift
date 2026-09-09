import Testing
@testable import SonyHeadphonesKit

struct AutomaticReconnectBackoffTests {
    @Test func reconnectDelayGrowsAndCapsAtThirtySeconds() {
        let seconds = (0...7).map {
            AutomaticReconnectBackoff.delayNanoseconds(forAttempt: $0) / 1_000_000_000
        }

        #expect(seconds == [2, 4, 8, 15, 30, 30, 30, 30])
    }

    @Test func negativeAttemptUsesInitialDelayDefensively() {
        #expect(AutomaticReconnectBackoff.delayNanoseconds(forAttempt: -1) == 2_000_000_000)
    }
}
