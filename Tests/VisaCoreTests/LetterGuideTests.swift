import Foundation
import VisaCore

final class LetterGuideTests {
    func testLetterDataAndGeometry() {
        for letter in LatinGlyphs.supported {
            guard let spec = LetterGuideData.letter(letter), let guide = NumeralGuide(letter: letter) else {
                expectTrue(false, "guide for \(letter)")
                continue
            }
            expectFalse(spec.beats.isEmpty, "beats for \(letter)")
            expectTrue(spec.beats.allSatisfy { !$0.line.en.isEmpty && $0.line.zh.isEmpty }, "English-only beats \(letter)")
            let strokes = LatinGlyphs.strokes(letter)
            for beat in spec.beats where beat.until != nil {
                let p = beat.until!
                expectTrue((NumeralGuide.glyphOffset(of: p, on: strokes[beat.stroke]) ?? 99) <= 6, "beat point \(letter)")
            }
            for cue in spec.cues {
                expectTrue((NumeralGuide.glyphOffset(of: cue.point, on: strokes[cue.stroke]) ?? 99) <= 6, "cue point \(letter)")
                expectTrue(!cue.line.en.isEmpty && cue.line.zh.isEmpty, "English-only cue \(letter)")
            }
            for cue in guide.cues {
                expectTrue((440...840).contains(cue.signPoint.x) && (126...534).contains(cue.signPoint.y), "sign on board \(letter)")
            }
        }
        expectTrue(LetterGuideData.letter("f") == nil, "unsupported letter")
    }


    func testEStallAndLevelGates() throws {
        let bank = try LetterWordBank.load(url: URL(fileURLWithPath: "Resources/LetterTap/starter-bank.json"))
        let settings = TapLetterSettings(thisWeek: ["e"])
        guard let deal = TapLetterGenerator.make(seed: "guide-e", n: 1, settings: settings,
                progress: LetterProgress(), decks: LetterWordDecks(), bank: bank, now: Date()),
              deal.target == "e", let guide = NumeralGuide(letter: "e") else {
            expectTrue(false, "e deal and guide"); return
        }
        var round = TapLetterWriteRound(deal: deal)
        _ = round.tap(deal.board.targetCards[0], at: 1)
        _ = round.tap(deal.board.targetCards[1], at: 2)
        round.beginWriting(demo: false)
        var trace = round.trace
        let path = trace.currentPath!
        _ = trace.penDown(at: path.start, now: 10)
        for d in stride(from: 0.0, through: 317.0, by: 4) {
            _ = trace.penMove(to: path.point(at: d), now: 10 + d / 100)
            if d == 100 { expectEqual(TapCountGuideCoach.activeCue(guide: guide, trace: trace)?.sign, .stop) }
        }
        expectEqual(TapCountGuideCoach.headlights(plan: TapCountGuidePlan(level: .standard, learned: false),
            guide: guide, trace: trace), [360, 390, 420], "e junction headlights")
        let at = trace.lastProgressAt ?? 13
        let plan = TapCountGuidePlan(level: .standard, learned: false)
        let cue = TapCountGuideCoach.activeCue(guide: guide, trace: trace)
        expectEqual(cue?.sign, .ahead)
        let help = TapCountGuideCoach.help(plan: plan, guide: guide, trace: trace, readyAt: 10, now: at + 2.1)
        if case let .stall(_, _, end, _) = help { expectEqual(end, path.length, accuracy: 3) }
        else { expectTrue(false, "2 s stall") }
        let ghost = TapCountGuideCoach.help(plan: plan, guide: guide, trace: trace, readyAt: 10, now: at + 8.1)
        if case .ghostToEnd = ghost {} else { expectTrue(false, "8 s ghost") }
        trace.penUp()
        let replay = TapCountGuideCoach.help(plan: plan, guide: guide, trace: trace, readyAt: 10, now: at + 20.1)
        if case .redemo = replay {} else { expectTrue(false, "20 s pen-up re-demo") }
        let less = TapCountGuidePlan(level: .less, learned: false)
        expectTrue(less.stallSeconds == nil)
        expectFalse(less.headlights)
    }

    func testECuesAndTangent() {
        guard let e = NumeralGuide(letter: "e"), let six = NumeralGuide(6) else { expectTrue(false, "guides"); return }
        expectEqual(e.cues.count, 2)
        expectEqual(e.cues[0].sign, .stop)
        expectEqual(e.cues[1].sign, .ahead)
        expectEqual(e.spec.cues[0].line.en, "Stop! Now up and round!")
        expectEqual(e.spec.cues[1].line.en, "Keep going, round the bottom!")
        expectTrue(abs(e.aheadAngle(for: e.cues[1]) - 1.26) < 0.5, "e ahead tangent")
        if let cue = six.cues.first(where: { $0.sign == .ahead }) {
            expectTrue(abs(six.aheadAngle(for: cue)) > 1, "six ahead tangent")
        }
        expectEqual(e.spec.beats[2].line.en, "Then round the bottom!")
        let plan = TapCountGuidePlan(level: .less, learned: false)
        expectFalse(plan.demo, "less demo")
        expectFalse(plan.headlights, "less headlights")
    }
}
