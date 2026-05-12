import SwiftUI

enum SpriteAnimationPhase {
    // Anchor legacy looping callers to an absolute phase unless a one-shot animation provides its own start date.
    static let sharedLoopAnchor = Date(timeIntervalSinceReferenceDate: 0)
}

struct SpriteSheetView: View {
    let spriteSheet: String
    var frameCount: Int = 6
    var columns: Int = 6
    var fps: Double = 10
    var isAnimating: Bool = true
    var animationStartDate: Date = SpriteAnimationPhase.sharedLoopAnchor
    var repeatsAnimation: Bool = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / fps, paused: !isAnimating)) { timeline in
            SpriteFrameView(
                spriteSheet: spriteSheet,
                frameCount: frameCount,
                columns: columns,
                currentFrame: currentFrame(at: timeline.date)
            )
        }
    }

    private func currentFrame(at date: Date) -> Int {
        guard isAnimating else { return 0 }
        let elapsed = max(0, date.timeIntervalSince(animationStartDate))
        let frame = Int(elapsed * fps)

        if repeatsAnimation {
            return frame % frameCount
        }

        return min(frame, frameCount - 1)
    }
}

private struct SpriteFrameView: View {
    let spriteSheet: String
    let frameCount: Int
    let columns: Int
    let currentFrame: Int

    var body: some View {
        GeometryReader { geometry in
            let frameWidth = geometry.size.width
            let frameHeight = geometry.size.height
            let rows = (frameCount + columns - 1) / columns

            let col = currentFrame % columns
            let row = currentFrame / columns

            Image(spriteSheet)
                .interpolation(.none)
                .resizable()
                .frame(width: frameWidth * CGFloat(columns),
                       height: frameHeight * CGFloat(rows))
                .offset(x: -frameWidth * CGFloat(col),
                        y: -frameHeight * CGFloat(row))
        }
        .clipped()
    }
}
