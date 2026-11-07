import Foundation
import VisaCore

/// Hanzi H2 finding UI (0.38.0 / 83): the 2 × 5 中文字 Find & flip board against design hanzi-tap v2 § ★ 搵字翻卡 and
/// its child copy table. Offline: reads the bundled pack, the cue-art sources, the Traditional-only fixture and the
/// app source.
final class HanziFindTests {
    private static let week = ["人", "上", "下", "左", "右", "木"]
    private static let findOnly = ["入", "八", "本", "未"]
    private static let day = Date(timeIntervalSince1970: 1_800_000_000)
    private static let packURL = URL(fileURLWithPath: "Resources/HanziTap/hanzi-pack.json")

    private func loadPack() throws -> HanziPack { try HanziPack.load(url: Self.packURL) }

    private func editedPack(_ edit: (inout [String: Any]) -> Void) throws -> HanziPack {
        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.packURL)) as! [String: Any]
        edit(&root)
        return try HanziPack.load(data: JSONSerialization.data(withJSONObject: root))
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    }

    /// `name`'s declaration in `text`, up to the next member declaration at the same indent (or the end of the type).
    private func body(of name: String, in text: String) -> String {
        guard let start = text.range(of: name) else { return "" }
        let after = text[start.upperBound...]
        let ends = ["\n    func ", "\n    private func ", "\n    var ", "\n    private var ", "\n}\n"]
            .compactMap { after.range(of: $0)?.lowerBound }
        return String(text[start.lowerBound..<(ends.min() ?? text.endIndex)])
    }

    private func deal(_ seed: String, kind: ActivityKind = .tapHanziAll, n: Int = 1, settings: HanziTapSettings = .defaults,
                      progress: HanziProgress = HanziProgress(), decks: HanziCueDecks = HanziCueDecks(),
                      pack: HanziPack, now: Date = HanziFindTests.day) -> HanziDeal? {
        TapHanziGenerator.make(seed: seed, kind: kind, n: n, settings: settings, progress: progress, decks: decks,
                               pack: pack, now: now).deal
    }

    /// (1) The letter board's tap rules, step for step: a known-wrong card or a double tap never adds a second
    /// penalty, and a found card never re-counts.
    func testTapRulesMatchLettersAndNeverDoublePenalize() throws {
        let pack = try loadPack()
        let bank = try LetterWordBank.load(url: URL(fileURLWithPath: "Resources/LetterTap/starter-bank.json"))
        // Explicit sequence first.
        guard let first = deal("double-penalty", pack: pack), var board = TapHanziBoard(deal: first, pack: pack) else {
            expectTrue(false, "no Hanzi deal")
            return
        }
        let targets = first.board.targetCards
        let wrong = (0..<10).filter { !targets.contains($0) }
        expectEqual(board.remaining, 2)
        expectEqual(board.tap(-1, at: 0.1), .ignored)
        expectEqual(board.tap(10, at: 0.2), .ignored)
        expectEqual(board.tap(wrong[0], at: 1), .miss)
        expectEqual(board.misses, 1)
        expectEqual(board.tap(wrong[0], at: 1.2), .doubleTapIgnored, "double tap")
        expectEqual(board.tap(wrong[0], at: 2), .knownWrongRetap, "known-wrong card again")
        expectEqual(board.tap(wrong[0], at: 5), .knownWrongRetap)
        expectEqual(board.misses, 1, "one penalty per wrong card")
        expectEqual(board.tap(wrong[1], at: 6), .miss)
        expectEqual(board.misses, 2)
        expectEqual(board.tap(targets[1], at: 7), .found)
        expectEqual(board.tap(targets[1], at: 7.1), .doubleTapIgnored)
        expectEqual(board.tap(targets[1], at: 8), .foundRetap)
        expectEqual(board.remaining, 1)
        expectEqual(board.tap(targets[0], at: 9), .allFound)
        expectEqual(board.tap(wrong[2], at: 10), .ignored, "a finished board takes no input")
        expectEqual([board.misses, board.knownWrong.count, board.found.count, board.remaining], [2, 2, 2, 0])
        expectEqual(board.tapOrder, [wrong[0], wrong[1], targets[1], targets[0]])
        expectFalse(board.isClean)
        board.showHint()
        expectTrue(board.assisted)

        // Parity: scripted taps by role (target k / wrong card k) give the same outcome and counts on a letter board.
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        let gaps = [0.1, 0.3, 0.39, 0.41, 0.8, 2.0]
        var misses = 0
        for s in 0..<150 {
            let kind: ActivityKind = s % 2 == 0 ? .tapHanziAll : .tapHanziWrite
            guard let hanziDeal = deal("parity-\(s)", kind: kind, n: s + 1, pack: pack),
                  var hanzi = TapHanziBoard(deal: hanziDeal, pack: pack),
                  let letterDeal = TapLetterGenerator.make(seed: "parity-\(s)", n: 1, settings: .defaults,
                      progress: LetterProgress(), decks: LetterWordDecks(), bank: bank, now: Self.day) else {
                expectTrue(false, "parity deal \(s)")
                continue
            }
            var letters = TapLetterBoard(deal: letterDeal)
            func cards(_ targetCards: [Int]) -> [Int] { targetCards + (0..<10).filter { !targetCards.contains($0) } }
            let hanziRoles = cards(hanziDeal.board.targetCards)
            let letterRoles = cards(letterDeal.board.targetCards)
            var clock = 0.0
            var penalised: [Int: Int] = [:]
            for step in 0..<16 {
                let role = next(10) < 3 ? next(2) : 2 + next(8)
                clock += gaps[next(gaps.count)]
                let outcome = hanzi.tap(hanziRoles[role], at: clock)
                let letterOutcome = letters.tap(letterRoles[role], at: clock)
                expectEqual(outcome, letterOutcome, "seed \(s) step \(step) role \(role)")
                if outcome == .miss { penalised[role, default: 0] += 1 }
                expectEqual([hanzi.misses, hanzi.found.count, hanzi.knownWrong.count, hanzi.remaining],
                            [letters.misses, letters.found.count, letters.knownWrong.count, letters.remaining],
                            "seed \(s) step \(step)")
                expectEqual(hanzi.tapOrder.map { hanziRoles.firstIndex(of: $0)! },
                            letters.tapOrder.map { letterRoles.firstIndex(of: $0)! })
                expectEqual(hanzi.isComplete, letters.isComplete)
                // Every penalty is a distinct wrong card: `misses` counts cards, never taps.
                expectEqual(hanzi.misses, hanzi.knownWrong.count)
                expectTrue(penalised.values.allSatisfy { $0 == 1 } && penalised.keys.allSatisfy { $0 >= 2 })
            }
            misses += hanzi.misses
        }
        expectTrue(misses > 100, "the scripts exercise misses: \(misses)")
    }

    /// (2) Render data: every card keeps its glyph in every state (unflipped, one flipped with 「仲有一張」, both
    /// flipped, after a wrong tap); a flip shows its own cue picture, the target glyph and the meaning, and the
    /// collection slots fill in target order. Deals from the week, retry and review lanes; both kinds.
    func testEveryStateKeepsItsGlyphsAndFlipsToPictureGlyphAndMeaning() throws {
        let pack = try loadPack()
        guard let copy = HanziFindCopy(pack: pack) else {
            expectTrue(false, "pack copy")
            return
        }
        let meanings = ["人": "一個人", "上": "上面", "下": "下面", "左": "我隻左手", "右": "我隻右手", "木": "一棵樹"]
        var progress = HanziProgress()
        var decks = HanziCueDecks()
        var lanes: Set<String> = []
        var targets: Set<String> = []
        var pictures: Set<String> = []
        for n in 1...48 {
            // Rounds 1–6 play 左右木; later rounds play 人上下, so every fourth round can review an older target.
            let settings = HanziTapSettings(week: n <= 6 ? ["左", "右", "木"] : ["人", "上", "下"])
            let kind: ActivityKind = n % 3 == 0 ? .tapHanziWrite : .tapHanziAll
            let now = Self.day.addingTimeInterval(Double(n) * 86_400)
            guard let dealt = deal("faces-\(n)", kind: kind, n: n, settings: settings, progress: progress, decks: decks,
                                   pack: pack, now: now),
                  var board = TapHanziBoard(deal: dealt, pack: pack) else {
                expectTrue(false, "faces deal \(n)")
                continue
            }
            let label = "round \(n) \(dealt.choice.target) \(dealt.choice.lane)"
            let cards = dealt.board.cards
            let targetCards = dealt.board.targetCards
            func expectGlyphs(except flipped: Set<Int>) {
                for card in 0..<10 where !flipped.contains(card) {
                    expectEqual(board.face(card, pack: pack), .glyph(cards[card]), label)
                }
                for card in 0..<10 {
                    expectEqual(board.face(card, pack: pack)?.glyph, cards[card], label)
                    expectFalse(HanziGlyphs.paths(cards[card], in: pack).isEmpty, "\(cards[card]) has centre lines")
                }
                expectTrue(board.face(10, pack: pack) == nil && board.face(-1, pack: pack) == nil)
            }
            func art(_ slot: Int) -> HanziFlipArt {
                HanziFlipArt(glyph: dealt.board.target, picture: dealt.cues[slot], meaning: meanings[dealt.board.target]!)
            }
            // Unflipped: ten glyph cards, both targets unmarked like every distractor, empty slots.
            expectGlyphs(except: [])
            expectTrue(board.slot(0, pack: pack) == nil && board.slot(1, pack: pack) == nil, label)
            expectEqual(copy.remaining(board.remaining), "點晒兩張。")
            // A wrong card stays a glyph card, available for comparison.
            let missed = n % 4 == 1
            if missed, let wrong = (0..<10).first(where: { !targetCards.contains($0) }) {
                expectEqual(board.tap(wrong, at: 1), .miss)
                expectGlyphs(except: [])
            }
            // One flipped (the review board): the found card shows its own picture, the other target is still a
            // readable glyph, and the tray says 「仲有一張」.
            let firstSlot = n % 2
            expectEqual(board.tap(targetCards[firstSlot], at: 2), .found)
            expectEqual(board.face(targetCards[firstSlot], pack: pack), .flipped(art(firstSlot)), label)
            expectEqual(board.face(targetCards[1 - firstSlot], pack: pack), .glyph(dealt.board.target), label)
            expectGlyphs(except: [targetCards[firstSlot]])
            expectEqual(board.slot(firstSlot, pack: pack), art(firstSlot))
            expectTrue(board.slot(1 - firstSlot, pack: pack) == nil, label)
            expectEqual(copy.remaining(board.remaining), "仲有一張")
            // Both flipped: two different pictures of the target, both slots full in target-card order.
            expectEqual(board.tap(targetCards[1 - firstSlot], at: 3), .allFound)
            expectGlyphs(except: Set(targetCards))
            expectEqual([board.face(targetCards[0], pack: pack), board.face(targetCards[1], pack: pack)],
                        [.flipped(art(0)), .flipped(art(1))])
            expectEqual([board.slot(0, pack: pack), board.slot(1, pack: pack)], [art(0), art(1)])
            expectEqual(Set(dealt.cues), Set(pack.characters[dealt.board.target]!.cuePictures), label)
            expectEqual(copy.remaining(board.remaining), "搵晒喇！")
            expectEqual(board.finish, kind == .tapHanziWrite ? .awaitWriteRound : .stamp)
            expectEqual(board.isClean, !missed)
            progress.record(dealt.choice, clean: board.isClean, round: n, at: now)
            decks = dealt.decks
            lanes.insert("\(dealt.choice.lane)")
            targets.insert(dealt.board.target)
            pictures.formUnion(dealt.cues)
        }
        expectEqual(targets, Set(Self.week))
        expectEqual(lanes, ["week", "retry", "review"])
        expectEqual(pictures, Set(pack.characters.values.flatMap(\.cuePictures)))
        // A deal a board cannot fully draw is refused (no deal), never shown with a hole: here a cue picture with
        // no artwork. (A glyph without centre lines cannot load: `HanziPack.problems` rejects it.)
        guard let dealt = deal("refuse", pack: pack) else {
            expectTrue(false, "refuse deal")
            return
        }
        let missingArt = try editedPack { root in
            var characters = root["characters"] as! [String: Any]
            var entry = characters[dealt.board.target] as! [String: Any]
            entry["cuePictures"] = (entry["cuePictures"] as! [String]).map { $0 == dealt.cues[0] ? "missing-art" : $0 }
            characters[dealt.board.target] = entry
            root["characters"] = characters
        }
        expectTrue(TapHanziBoard(deal: dealt, pack: missingArt) == nil, "cue picture no longer in the pack")
        guard let again = deal("refuse", pack: missingArt) else {
            expectTrue(false, "refuse deal, edited pack")
            return
        }
        expectTrue(again.cues.contains("missing-art"))
        expectTrue(TapHanziBoard(deal: again, pack: missingArt) == nil, "cue picture without artwork")
    }

    /// (3) Copy: the design table's lines from the pack, HK Traditional only, placeholders filled.
    func testFindCopyIsThePacksHongKongTraditional() throws {
        let pack = try loadPack()
        guard let copy = HanziFindCopy(pack: pack) else {
            expectTrue(false, "pack copy")
            return
        }
        expectEqual(copy.header("上"), "搵晒『上』！")
        expectEqual(copy.subline, "點晒兩張。")
        expectEqual(copy.foundPair("上", pack: pack), "『上』，上面！")
        expectEqual(copy.remaining(1), "仲有一張")
        expectEqual(copy.remaining(2), "點晒兩張。")
        expectEqual(copy.remaining(0), "搵晒喇！")
        expectEqual(copy.allFound, "搵晒喇！")
        expectEqual(copy.wrong("右"), "嗰個係『右』。")
        expectEqual(copy.wrong("本"), "嗰個係『本』。")
        expectEqual(copy.hint("上"), "呢張係『上』！")
        expectEqual(copy.findAgain("上"), "再搵『上』！")
        expectEqual(copy.idle("上"), "搵『上』！")
        expectEqual(copy.prompt("上"), "搵晒『上』！點晒兩張。")
        expectEqual([copy.headerParts.before, copy.headerParts.after], ["搵晒『", "』！"])
        expectEqual(["人", "下", "左", "右", "木"].map { copy.foundPair($0, pack: pack) },
                    ["『人』，一個人！", "『下』，下面！", "『左』，左邊！", "『右』，右邊！", "『木』，一棵樹！"])
        let fixture = URL(fileURLWithPath: "Tests/VisaCoreTests/Fixtures/traditional-check/simplified-only.txt")
        let simplified = Set(try String(contentsOf: fixture, encoding: .utf8).split(separator: "\n")
            .filter { !$0.hasPrefix("#") }.joined().filter { !$0.isWhitespace })
        for glyph in Self.week + Self.findOnly {
            var lines = [copy.header(glyph), copy.subline, copy.prompt(glyph), copy.findAgain(glyph), copy.idle(glyph),
                         copy.wrong(glyph), copy.hint(glyph), copy.allFound, copy.remaining(1), copy.remaining(2)]
            if pack.isTarget(glyph) { lines.append(copy.foundPair(glyph, pack: pack)) }
            for line in lines {
                expectFalse(line.isEmpty || line.contains("{") || line.contains("}"), line)
                expectTrue(isTraditionalChineseOnly(line) && perfTraditionalOnly(line), line)
                expectFalse(line.contains { simplified.contains($0) }, "Simplified character in \(line)")
                expectFalse(line.contains { $0.isASCII && $0.isLetter }, "no English or romanisation in \(line)")
            }
        }
        // The pack keeps zhHK, jyutping and voiceKey apart; the board shows no jyutping (D4, OFF).
        expectEqual(pack.characters["上"]?.jyutping, "soeng6")
        expectEqual(pack.characters["上"]?.voiceKey, "hanzi.char.shang.location")
        expectFalse(copy.foundPair("上", pack: pack).contains("soeng"))
        // Fail closed: a missing find line or a template without its placeholder gives no copy (no deal).
        for key in HanziFindCopy.keys.keys.sorted() {
            let removed = try editedPack { root in
                var lines = root["copy"] as! [String: Any]
                lines[key] = nil
                root["copy"] = lines
            }
            expectTrue(HanziFindCopy(pack: removed) == nil, "without \(key)")
        }
        let broken = try editedPack { root in
            var lines = root["copy"] as! [String: Any]
            lines["wrong"] = ["zhHK": "嗰個唔係。", "en": "Not that one."]
            root["copy"] = lines
        }
        expectTrue(HanziFindCopy(pack: broken) == nil, "wrong without {Y}")
    }

    /// (4) Flip art is the H0 sprite in the shared tokens (D8), regenerated from the current sources, with 右 the
    /// mirror of 左 and its direction arrow (D7).
    func testCueArtIsTheSharedSpriteAndUpToDate() throws {
        let pack = try loadPack()
        func fnv(_ path: String) throws -> UInt64 {
            var value: UInt64 = 0xCBF2_9CE4_8422_2325
            for byte in try Data(contentsOf: URL(fileURLWithPath: path)) {
                value ^= UInt64(byte)
                value = value &* 0x0000_0100_0000_01B3
            }
            return value
        }
        let fingerprint = HanziCueArt.sourceFingerprint
        expectEqual(try fnv("docs/hanzi-cue-art/illustrations.svg"), fingerprint.sprite,
                    "re-run scripts/svg_to_hanzicueart.py after a sprite change")
        expectEqual(try fnv("docs/hanzi-cue-art/illustration-style.css"), fingerprint.stylesheet,
                    "re-run scripts/svg_to_hanzicueart.py after a token change")
        // Colours: the token sheet's values, plus left-hand-2's documented second skin tone.
        let css = try source("docs/hanzi-cue-art/illustration-style.css").lowercased()
        var palette = Set<UInt32>([0xFFFFFF, 0xE9B37E, 0xD69A65])
        let hex = try NSRegularExpression(pattern: "#([0-9a-f]{6})")
        for match in hex.matches(in: css, range: NSRange(css.startIndex..., in: css)) {
            palette.insert(UInt32(String(css[Range(match.range(at: 1), in: css)!]), radix: 16)!)
        }
        func points(_ geometry: CanvasArtGeometry) -> [(Double, Double)] {
            switch geometry {
            case .path(let commands):
                return commands.flatMap { command -> [(Double, Double)] in
                    switch command {
                    case .move(let x, let y), .line(let x, let y): return [(x, y)]
                    case .quad(let cx, let cy, let x, let y): return [(cx, cy), (x, y)]
                    case .cubic(let ax, let ay, let bx, let by, let x, let y): return [(ax, ay), (bx, by), (x, y)]
                    case .close: return []
                    }
                }
            case .rect(let x, let y, let width, let height, _): return [(x, y), (x + width, y + height)]
            case .circle(let cx, let cy, let r): return [(cx - r, cy - r), (cx + r, cy + r)]
            case .ellipse(let cx, let cy, let rx, let ry): return [(cx - rx, cy - ry), (cx + rx, cy + ry)]
            }
        }
        func bounds(_ element: CanvasArtElement) -> [Double] {
            let all = points(element.geometry)
            return [all.map(\.0).min()!, all.map(\.1).min()!, all.map(\.0).max()!, all.map(\.1).max()!]
        }
        let cueIDs = pack.characters.values.flatMap(\.cuePictures)
        expectEqual(cueIDs.count, 12)
        for id in cueIDs + ["robot"] {
            guard let art = HanziCueArt.picture(id) else {
                expectTrue(false, "no artwork for \(id)")
                continue
            }
            expectEqual(art.name, "hanziCue.\(id)")
            expectTrue(art.width == 240 && art.height == 200 && art.elements.count >= 5, id)
            for element in art.elements {
                if case .path(let commands) = element.geometry { expectFalse(commands.isEmpty, "\(id) path parses") }
                for colour in [element.style.fill, element.style.stroke].compactMap({ $0 }) {
                    expectTrue(palette.contains(colour), "\(id) colour \(String(colour, radix: 16)) is a token")
                }
                if element.style.stroke == 0x302A35 { expectTrue(element.style.lineWidth > 0, id) }
                let box = bounds(element)
                expectTrue(box[0] >= -1 && box[1] >= -1 && box[2] <= 241 && box[3] <= 201, "\(id) inside its viewBox")
            }
            // Outlines are the token widths (5.5 / 3.5), scaled only where the sprite scales a shared part: the
            // under-bridge pictures stretch the bridge by 1.4 and shrink the car to 0.84, so they have no unscaled one.
            let inked = art.elements.filter { $0.style.stroke == 0x302A35 }.map(\.style.lineWidth)
            expectTrue(!inked.isEmpty && inked.allSatisfy { $0 >= 2.5 && $0 <= 7 }, id)
            if !id.hasPrefix("below-bridge") {
                expectTrue(inked.contains { abs($0 - 5.5) < 0.01 }, "\(id) token outline")
            }
        }
        for id in ["", "person", "hanziCue.tree", "car", "Tree"] { expectTrue(HanziCueArt.picture(id) == nil, id) }
        // 右 mirrors 左 (D7: the same hand system, the arrow pointing the other way).
        for (left, right) in [(HanziCueArt.leftHand, HanziCueArt.rightHand), (HanziCueArt.leftHand2, HanziCueArt.rightHand2)] {
            expectEqual(left.elements.count, right.elements.count)
            for (l, r) in zip(left.elements, right.elements) {
                expectEqual(l.style, r.style)
                let a = bounds(l), b = bounds(r)
                expectEqual(b[0], 240 - a[2], accuracy: 0.02)
                expectEqual(b[2], 240 - a[0], accuracy: 0.02)
                expectEqual(b[1], a[1], accuracy: 0.02)
                expectEqual(b[3], a[3], accuracy: 0.02)
            }
            let leftArrow = left.elements.filter { $0.style.fill == 0xED4B41 }.map(bounds)
            let rightArrow = right.elements.filter { $0.style.fill == 0xED4B41 }.map(bounds)
            expectTrue(!leftArrow.isEmpty && leftArrow.allSatisfy { $0[2] < 120 }, "向左 arrow on the left")
            expectTrue(!rightArrow.isEmpty && rightArrow.allSatisfy { $0[0] > 120 }, "向右 arrow on the right")
        }
        // The second hand keeps its inline skin override (H0 cue-art README); the first uses the token skin.
        func fills(_ art: CanvasArtwork) -> Set<UInt32> { Set(art.elements.compactMap(\.style.fill)) }
        for art in [HanziCueArt.leftHand2, HanziCueArt.rightHand2] {
            expectTrue(fills(art).isSuperset(of: [0xE9B37E, 0xD69A65]) && !fills(art).contains(0xF5D5A1), art.name)
        }
        for art in [HanziCueArt.leftHand, HanziCueArt.rightHand] {
            expectTrue(fills(art).contains(0xF5D5A1) && fills(art).isDisjoint(with: [0xE9B37E, 0xD69A65]), art.name)
        }
        // Ground shadows keep the token's 0.12 opacity.
        expectTrue(HanziCueArt.tree.elements.contains { $0.style.fill == 0x302A35 && abs($0.style.opacity - 0.12) < 0.001 })
        expectTrue(try source("Sources/VisaCore/HanziCueArt.swift").hasPrefix("// GENERATED by scripts/svg_to_hanzicueart.py"))
    }

    /// (5) Wiring: 翻字卡 and (since H3) 搵完寫 are playable but OFF until a parent's own playtest (D6); the ticket
    /// desk deals a Hanzi board before the round changes; the app penalises only a first wrong tap, speaks only with
    /// audio on, and the find board never draws or saves a write (搵完寫 stamps only once its write round is drawn).
    func testWiringKeepsKindsOffAndTheAppPenalisesOncePerCard() throws {
        expectTrue(ActivityCatalog.playableKinds.contains(.tapHanziAll))
        expectTrue(ActivityCatalog.playableKinds.contains(.tapHanziWrite), "搵完寫 joins with its write round (H3)")
        expectEqual(Array(ActivityCatalog.playableKinds.suffix(2)), [.tapHanziAll, .tapHanziWrite])
        for kind in [ActivityKind.tapHanziAll, .tapHanziWrite] {
            expectTrue(ActivityCatalog.defaultOffKinds.contains(kind) && kind.requiresPlaytestBeforeStars)
            expectFalse(ActivityCatalog.defaultOnKinds.contains(kind))
            expectEqual(MissionGameAssignment.defaultStars(for: kind), [])
        }
        let fresh = MissionGameAssignment.defaults
        expectEqual(fresh.enabledStars[.tapHanziAll], [])
        expectEqual(fresh.enabledStars[.tapHanziWrite], [])
        for star in ChildDifficulty.allCases {
            expectFalse(fresh.pool(for: star).contains { $0.isTapHanziFamily })
        }
        expectTrue(ParentPlaytestLog().allowsStars(for: .tapHanziAll) == false, "stars wait for its own playtest")
        expectTrue(ParentPlaytestLog().recording(.tapHanziAll, on: Self.day).allowsStars(for: .tapHanziAll))
        expectFalse(ParentPlaytestLog().recording(.tapLetterAll, on: Self.day).allowsStars(for: .tapHanziAll))

        // The desk deals the fallible Hanzi board before the caller touches the round, as for letters.
        struct Round: Equatable { var kind: ActivityKind?; var board: String? }
        var desk = LetterTicketDesk()
        var dealt: [ActivityKind] = []
        var round = Round()
        func select(pool: [ActivityKind], board: String?) {
            let outcome: LetterTicketDesk.Outcome<String> = desk.prepare(pool: pool, seed: "hanzi-desk") { kind in
                dealt.append(kind)
                return board
            }
            guard case .ready(_, let kind, let prepared) = outcome else { return }
            round = Round(kind: kind, board: prepared)
        }
        select(pool: [.tapHanziAll], board: nil)
        expectTrue(desk.unavailable, "a failed Hanzi deal")
        expectEqual(round, Round(), "round untouched")
        expectEqual(dealt, [.tapHanziAll])
        expectTrue(desk.recover(.parentEntered))
        select(pool: [.tapHanziAll], board: "board")
        expectFalse(desk.unavailable)
        expectEqual(round, Round(kind: .tapHanziAll, board: "board"))
        dealt = []
        select(pool: [.findTheSame], board: nil)
        expectEqual(dealt, [], "other kinds deal no board")

        // App source guards (SwiftUI / AppKit are not built on this box).
        let host = try source("Sources/VisaGames/CanvasActivityHost.swift")
        let model = try source("Sources/VisaGames/AppDelegate.swift")
        let view = try source("Sources/VisaGames/TapHanziBoardView.swift")
        expectTrue(host.contains("case .tapHanziAll, .tapHanziWrite:\n                tapHanzi"))
        expectTrue(host.contains("TapHanziBoardView(board: board"))
        let tap = body(of: "func tapHanziTap(card: Int)", in: model)
        expectTrue(tap.contains("guard outcome != .ignored && outcome != .doubleTapIgnored else { return }"))
        expectTrue(tap.contains("case .miss, .knownWrongRetap:"))
        // One penalty path, taken only for a first miss; the wrong line shows before (and whatever) the voice does.
        expectEqual(tap.components(separatedBy: "handleEvaluation(.incorrect").count, 2)
        expectEqual(tap.components(separatedBy: "playtestHandle(.incorrect").count, 2)
        expectTrue(tap.contains("if outcome == .miss {"))
        let missBranch = tap.components(separatedBy: "case .miss, .knownWrongRetap:")[1]
        let shown = missBranch.range(of: "tapHanziShowBubble(line")
        let spoken = missBranch.range(of: "tapHanziSpeak(")
        expectTrue(shown != nil && spoken != nil && shown!.lowerBound < spoken!.lowerBound)
        // Voice: one gate, OFF by default (D4); nothing in H2 turns audio on or saves the Hanzi settings.
        let speak = body(of: "private func tapHanziSpeak(", in: model)
        expectTrue(speak.contains("guard hanziSettings.audioEnabled else { return }"))
        expectTrue(speak.contains("guideVoice."))
        expectFalse(model.contains("audioEnabled = true") || model.contains("HanziTapSettingsStore().save"))
        for name in ["func tapHanziTap(card: Int)", "func speakTapHanziPrompt()", "private func tapHanziAfterPause(",
                     "private func tapHanziIdleCheck(", "private func finishTapHanziFind(",
                     "private func finishTapHanziRound("] {
            let text = body(of: name, in: model)
            expectFalse(text.isEmpty, name)
            expectFalse(text.contains("guideVoice."), "\(name) speaks only through tapHanziSpeak")
        }
        // 搵完寫 stamps only once its write round is drawn (H3; `HanziWriteTests` (8) pins the write path). The find
        // board, the tap and the find's finish never draw or save a write.
        let finish = body(of: "private func finishTapHanziFind(", in: model)
        expectTrue(finish.contains("case .awaitWriteRound:"))
        expectTrue(finish.components(separatedBy: "case .awaitWriteRound:")[1]
            .contains("WriteRound)?.canStamp == true {\n                finishTapHanziRound(token: token, playtest: playtest)"))
        for name in ["TapLetterWriteBoardView", "ShapeTraceBoard", "TapLetterWriteRound", "HanziWriteProgressStore().save"] {
            expectFalse(view.contains(name) || tap.contains(name) || finish.contains(name), name)
        }
        // The playtest never saves the child's Hanzi stores.
        let save = body(of: "private func tapHanziSaveRound(", in: model)
        let preview = save.range(of: "if playtest {")
        let firstSave = save.range(of: "Store().save(")
        expectTrue(preview != nil && firstSave != nil && preview!.lowerBound < firstSave!.lowerBound)
        expectTrue(save.components(separatedBy: "if playtest {")[1].components(separatedBy: "}")[0].contains("return"))
        // Glyphs come from the pack's centre lines on every card, plaque and slot (no font fallback for them).
        expectTrue(view.contains("HanziGlyphs.paths(glyph, in: pack"))
        expectTrue(view.contains("HanziCueArt.picture("))
        expectFalse(view.contains("LetterWordArt") || view.contains("LatinLetterGlyph"))
    }

    /// (6) Parent controls during the reveal: the second target is found, parent controls open before the stroke
    /// reveal's finish comes due, then Return. Before the fix the finish saved the round under parent controls,
    /// marked it complete and could not start the visa (`Session.startPlayVisa` needs the lock), so the child came
    /// back to a finished board that took no taps, with no visa. Now the finish is held for its round and runs once
    /// on Return: one progress record, one award, one visa. A reset drops it; a Return into a running visa releases
    /// nothing.
    func testParentDuringTheRevealFinishesOnceOnReturn() throws {
        let pack = try loadPack()
        let calendar = Calendar(identifier: .gregorian)
        guard let dealt = deal("parent-during-reveal", pack: pack), var board = TapHanziBoard(deal: dealt, pack: pack) else {
            expectTrue(false, "no Hanzi deal")
            return
        }
        expectEqual(board.tap(dealt.board.targetCards[0], at: 1), .found)
        expectEqual(board.tap(dealt.board.targetCards[1], at: 2), .allFound, "second target: the reveal starts")
        expectEqual(board.finish, .stamp)
        let round = "round-A"

        /// AppModel's finish order on the real session, ledger, progress and hold: `finishTapHanziFind` holds an open
        /// child round outside the lock (`fixed` only), `finishTapHanziRound` saves once and marks the round complete,
        /// `applyEntrySuccess` banks the award and starts the visa only in the lock, and `returnToChild` leaves parent,
        /// then releases the hold. The source guards below pin AppModel to the same order.
        struct Kiosk {
            let fixed: Bool
            let now: Date
            var board: TapHanziBoard
            var dealSeed: String              // choiceDealSeed
            var session: Session
            var ledger = RewardLedger(policy: RewardPolicy(initialAllowanceSeconds: 60, rewardCapSeconds: 1_200))
            var progress = HanziProgress()
            var hold = ChildFinishHold()
            var roundOpen = true              // taskRoundOpen
            var completed = false             // activityJustCompleted
            var roundIndex = 0                // hanziRoundIndex
            var visas = 0

            init(fixed: Bool, board: TapHanziBoard, round: String, now: Date) {
                self.fixed = fixed
                self.now = now
                self.board = board
                dealSeed = round
                session = Session(snapshot: Snapshot(configured: true), now: now)
            }

            /// The reveal's finish comes due (`finishTapHanziFind` → `finishTapHanziRound` → `applyEntrySuccess`).
            mutating func revealFinished(_ token: String) {
                guard dealSeed == token, board.isComplete else { return }
                if fixed, roundOpen, !hold.finishesNow(token, mode: session.mode) { return }
                guard roundOpen, !completed else { return }
                progress.record(board.deal.choice, clean: board.isClean, round: roundIndex + 1, at: now)
                roundIndex += 1
                completed = true
                guard session.mode == .lock else { return }
                let calendar = Calendar(identifier: .gregorian)
                ledger.completeEntryActivity(now: now, calendar: calendar)
                ledger.applyCompletion(id: token, rewardSeconds: 300, kind: board.assisted ? .assisted : .unassisted,
                                       now: now, calendar: calendar)
                session.startPlayVisa(seconds: 300, now: now)
                guard session.mode == .play else { return }
                visas += 1
                roundOpen = false
            }

            mutating func enterParent() { session.enterParent(authenticated: true, now: now) }

            mutating func returnToChild() {
                session.leaveParent(now: now)
                guard fixed, let token = hold.release(openRound: roundOpen ? dealSeed : nil, mode: session.mode) else {
                    return
                }
                revealFinished(token)
            }

            /// `resetTaskRound`: a new ticket, out of fuel, a storage reset or a visa ending.
            mutating func reset() {
                roundOpen = false
                dealSeed = ""
                completed = false
                hold.drop()
            }
        }

        // Before the fix: saved and completed under parent controls, no visa, and the board takes no taps.
        var stranded = Kiosk(fixed: false, board: board, round: round, now: Self.day)
        stranded.enterParent()
        stranded.revealFinished(round)
        expectEqual(stranded.session.mode, .parent)
        stranded.returnToChild()
        expectEqual(stranded.session.mode, .lock)
        expectTrue(stranded.completed && stranded.roundOpen, "completed, never stamped")
        expectEqual([stranded.roundIndex, stranded.visas, stranded.ledger.successRecords.count], [1, 0, 0])
        expectEqual(stranded.board.tap(dealt.board.targetCards[0], at: 9), .ignored)

        // Fixed: held under parent controls with nothing saved, then finished once on Return.
        var kiosk = Kiosk(fixed: true, board: board, round: round, now: Self.day)
        kiosk.enterParent()
        kiosk.revealFinished(round)
        expectEqual(kiosk.hold.round, round, "held for its round")
        expectEqual(kiosk.progress, HanziProgress(), "nothing saved under parent controls")
        expectEqual([kiosk.roundIndex, kiosk.visas, kiosk.ledger.successRecords.count], [0, 0, 0])
        expectFalse(kiosk.completed)
        kiosk.returnToChild()
        expectEqual(kiosk.session.mode, .play, "Return stamps and the visa runs")
        expectEqual([kiosk.roundIndex, kiosk.visas], [1, 1])
        expectEqual(kiosk.ledger.successRecords.map(\.completionID), [round])
        expectEqual(kiosk.progress.state(for: dealt.board.target).cleanRounds, 1)
        expectTrue(kiosk.hold.round == nil && kiosk.completed && !kiosk.roundOpen)
        // Exactly once: a late finish, another parent visit and Return (into the running visa), the ledger's own check.
        let finished = kiosk.progress
        kiosk.revealFinished(round)
        kiosk.enterParent()
        kiosk.revealFinished(round)
        kiosk.returnToChild()
        expectEqual(kiosk.session.mode, .play)
        expectEqual(kiosk.progress, finished)
        expectEqual([kiosk.roundIndex, kiosk.visas, kiosk.ledger.successRecords.count], [1, 1, 1])
        expectTrue(kiosk.hold.round == nil)
        expectEqual(kiosk.ledger.applyCompletion(id: round, rewardSeconds: 300, kind: .unassisted, now: Self.day,
                                                 calendar: calendar), .duplicateRejected)

        // Back before the finish is due: nothing is held, and the finish runs in the lock as before.
        var early = Kiosk(fixed: true, board: board, round: round, now: Self.day)
        early.enterParent()
        early.returnToChild()
        expectTrue(early.hold.round == nil && early.session.mode == .lock)
        early.revealFinished(round)
        expectEqual([early.roundIndex, early.visas], [1, 1])

        // Return into a running visa (測試一分鐘簽證 leaves parent straight into play): nothing is released; the visa's
        // end resets the round and drops the hold, saving nothing.
        var test = Kiosk(fixed: true, board: board, round: round, now: Self.day)
        test.enterParent()
        test.revealFinished(round)
        test.session.grant(seconds: 60, now: Self.day)
        test.returnToChild()
        expectEqual(test.session.mode, .play)
        expectEqual(test.hold.round, round, "a running visa releases nothing")
        test.session.endPlayVisa(now: Self.day)
        test.reset()
        test.returnToChild()
        expectTrue(test.hold.round == nil && test.session.mode == .lock)
        expectEqual([test.roundIndex, test.visas, test.ledger.successRecords.count], [0, 0, 0])

        // A reset under parent controls (清除簽證及重設儲存) drops it: Return finishes nothing.
        var cleared = Kiosk(fixed: true, board: board, round: round, now: Self.day)
        cleared.enterParent()
        cleared.revealFinished(round)
        cleared.reset()
        cleared.returnToChild()
        expectEqual([cleared.roundIndex, cleared.visas, cleared.ledger.successRecords.count], [0, 0, 0])

        // The hold itself: only the lock finishes or releases, once, and only for the round still open.
        var hold = ChildFinishHold()
        for mode in [Mode.parent, .play, .setup] {
            expectFalse(hold.finishesNow("A", mode: mode))
            expectTrue(hold.release(openRound: "A", mode: mode) == nil && hold.round == "A", "\(mode) keeps it")
            hold.drop()
            expectTrue(hold.round == nil)
        }
        expectTrue(hold.finishesNow("A", mode: .lock) && hold.round == nil)
        _ = hold.finishesNow("A", mode: .parent)
        expectEqual(hold.release(openRound: "A", mode: .lock), "A")
        expectTrue(hold.release(openRound: "A", mode: .lock) == nil, "once")
        for open in ["B", nil] as [String?] {
            _ = hold.finishesNow("A", mode: .parent)
            expectTrue(hold.release(openRound: open, mode: .lock) == nil && hold.round == nil, "a round no longer open")
        }
        _ = hold.finishesNow("A", mode: .parent)
        expectTrue(hold.finishesNow("A", mode: .lock), "due again in the lock")
        expectTrue(hold.round == nil && hold.release(openRound: "A", mode: .lock) == nil)

        // AppModel follows the same order (SwiftUI / AppKit are not built on this box).
        let model = try source("Sources/VisaGames/AppDelegate.swift")
        let find = body(of: "private func finishTapHanziFind(", in: model)
        let held = body(of: "private func finishHeldTapHanziFind(", in: model)
        let stamp = body(of: "private func finishTapHanziRound(", in: model)
        let back = body(of: "func returnToChild(", in: model)
        let tap = body(of: "func tapHanziTap(card: Int)", in: model)
        // Held before the reveal wait and before anything is saved or stamped; an open child round only.
        let check = find.range(of: "if !playtest, taskRoundOpen, !tapHanziFinishHold.finishesNow(token, mode: session.mode) {")
        let wait = find.range(of: "if let reveal = tapHanziStrokeReveal {")
        let finish = find.range(of: "finishTapHanziRound(token: token, playtest: playtest)")
        expectTrue(check != nil && wait != nil && finish != nil)
        expectTrue(check!.lowerBound < wait!.lowerBound && wait!.lowerBound < finish!.lowerBound)
        expectTrue(find[check!.upperBound...].components(separatedBy: "}")[0].contains("return"), "a held finish stops")
        // Its only caller: 翻字卡 after the find, 搵完寫 once its write round is drawn (H3), both in finishTapHanziFind.
        expectEqual(model.components(separatedBy: "finishTapHanziRound(token:").count, 4, "one caller: finishTapHanziFind")
        expectEqual(find.components(separatedBy: "finishTapHanziRound(token: token, playtest: playtest)").count, 3)
        // Each lane reads its own board: a parent's Hanzi 試玩 swaps `currentTapHanziBoard`, not the child's round.
        for text in [find, stamp] {
            expectTrue(text.contains("let board = playtest ? playtestTapHanziBoard : tapHanziBoard"))
            expectFalse(text.contains("currentTapHanziBoard"))
        }
        expectTrue(tap.contains("(playtest ? self.playtestTapHanziBoard : self.tapHanziBoard)?.isComplete == true"))
        // Return releases it last: after any playtest is dropped and parent is left.
        let playtestDropped = back.range(of: "discardPlaytestCover(reason: \"leaveParent\")")
        let left = back.range(of: "update { $0.leaveParent(now: Date()) }")
        let release = back.range(of: "finishHeldTapHanziFind()")
        expectTrue(playtestDropped != nil && left != nil && release != nil)
        expectTrue(playtestDropped!.lowerBound < left!.lowerBound && left!.lowerBound < release!.lowerBound)
        expectEqual(model.components(separatedBy: "finishHeldTapHanziFind()").count, 3, "declared once, called once")
        expectTrue(held.contains("tapHanziFinishHold.release(openRound: taskRoundOpen ? choiceDealSeed : nil,"))
        expectTrue(held.contains("mode: session.mode) else { return }"))
        expectTrue(held.contains("finishTapHanziFind(token: round, playtest: false)"))
        expectFalse(held.contains("guideVoice."), "speaks only through tapHanziSpeak")
        // A reset drops it, and every new ticket and visa end resets; nothing else touches the hold.
        expectTrue(body(of: "private func resetTaskRound(", in: model).contains("tapHanziFinishHold.drop()"))
        expectTrue(body(of: "func selectDifficulty(stars: Int)", in: model).contains("resetTaskRound()"))
        expectTrue(body(of: "func update(_ action:", in: model).contains("resetTaskRound()"))
        expectEqual(model.components(separatedBy: "tapHanziFinishHold").count, 5, "declared; finishesNow, release, drop")
    }
}
