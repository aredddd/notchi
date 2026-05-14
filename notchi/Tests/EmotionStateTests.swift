import XCTest
@testable import notchi

@MainActor
final class EmotionStateTests: XCTestCase {
    func testModerateHappyScoreUsesHappyEmotion() {
        let emotion = EmotionState.resolvedEmotion(for: [
            .happy: 0.7,
            .sad: 0.0
        ])

        XCTAssertEqual(emotion, .happy)
    }

    func testHighHappyScoreEscalatesToElated() {
        let emotion = EmotionState.resolvedEmotion(for: [
            .happy: 0.9,
            .sad: 0.0
        ])

        XCTAssertEqual(emotion, .elated)
    }

    func testHighSadScoreStillEscalatesToSob() {
        let emotion = EmotionState.resolvedEmotion(for: [
            .happy: 0.0,
            .sad: 0.9
        ])

        XCTAssertEqual(emotion, .sob)
    }
}
