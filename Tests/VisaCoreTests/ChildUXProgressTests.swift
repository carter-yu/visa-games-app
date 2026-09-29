import Foundation
import VisaCore

final class ChildUXProgressTests {
    func testAutoHintAfterTwoMisses() {
        expectFalse(ActivityHintPolicy.shouldAutoHint(afterMissCount: 0))
        expectFalse(ActivityHintPolicy.shouldAutoHint(afterMissCount: 1))
        expectTrue(ActivityHintPolicy.shouldAutoHint(afterMissCount: 2))
        expectTrue(ActivityHintPolicy.shouldAutoHint(afterMissCount: 3))
        expectEqual(ActivityHintPolicy.missesBeforeAutoHint, 2)
    }

    func testRoadTimerFractionAndMinutes() {
        let mid = RoadTimerProgress(elapsed: 300, total: 600, remaining: 300)
        expectClose(mid.fraction, 0.5)
        expectEqual(mid.remainingMinutesCeil, 5)
        expectFalse(mid.almostHome)

        let almost = RoadTimerProgress(elapsed: 560, total: 600, remaining: 40)
        expectClose(almost.fraction, 560.0 / 600.0)
        expectEqual(almost.remainingMinutesCeil, 1)
        expectTrue(almost.almostHome)

        let done = RoadTimerProgress(elapsed: 600, total: 600, remaining: 0)
        expectEqual(done.fraction, 1)
        expectEqual(done.remainingMinutesCeil, 0)
        expectFalse(done.almostHome)
    }

    func testRoadTimerFromEndsAt() {
        let now = Date(timeIntervalSince1970: 10_000)
        let ends = now.addingTimeInterval(90)
        let progress = RoadTimerProgress.from(endsAt: ends, totalSeconds: 600, now: now)
        expectEqual(progress.remainingMinutesCeil, 2)
        expectTrue(progress.almostHome == false) // 90s > 60
        let near = RoadTimerProgress.from(endsAt: now.addingTimeInterval(45), totalSeconds: 600, now: now)
        expectTrue(near.almostHome)
        expectEqual(near.remainingMinutesCeil, 1)
    }

    func testSpokenUXLinesAreTraditional() {
        for line in SpokenPrompt.allUXLines {
            expectFalse(line.traditionalChinese.isEmpty)
            expectFalse(line.english.isEmpty)
            expectTrue(isTraditionalChineseOnly(line.traditionalChinese))
        }
        expectEqual(SpokenPrompt.stamped.traditionalChinese, "蓋印！")
        expectEqual(SpokenPrompt.almostHome.traditionalChinese, "快到屋企喇！")
        let fire = SpokenPrompt.timesUp(for: MissionTicket.all[1])
        expectTrue(fire.traditionalChinese.contains("消防車"))
        expectTrue(fire.traditionalChinese.contains("瞓覺"))
        expectTrue(isTraditionalChineseOnly(fire.traditionalChinese))
    }
}

private func expectClose(_ actual: Double, _ expected: Double, file: StaticString = #file, line: UInt = #line) {
    precondition(abs(actual - expected) < 0.0001, "Expected \(expected), got \(actual)", file: file, line: line)
}
