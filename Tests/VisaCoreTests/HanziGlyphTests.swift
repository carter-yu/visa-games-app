import Foundation
import VisaCore

/// H0 hanzi data pack (design hanzi-tap v2 + six-target addendum 2026-11-06). Offline: reads the pack, the
/// shared cue sprite and the Traditional-only fixture from the repository.
final class HanziGlyphTests {
    private static let week = ["人", "上", "下", "左", "右", "木"]
    private static let orders: [String: [String]] = [
        "人": ["撇", "捺"], "上": ["豎", "橫", "橫"], "下": ["橫", "豎", "點"],
        "左": ["橫", "撇", "橫", "豎", "橫"], "右": ["橫", "撇", "豎", "橫折", "橫"], "木": ["橫", "豎", "撇", "捺"],
        "入": ["撇", "捺"], "八": ["撇", "捺"], "本": ["橫", "豎", "撇", "捺", "橫"], "未": ["橫", "橫", "豎", "撇", "捺"]
    ]

    private func loadPack() throws -> HanziPack {
        try HanziPack.load(url: URL(fileURLWithPath: "Resources/HanziTap/hanzi-pack.json"))
    }

    private func p(_ x: Double, _ y: Double) -> LineMatchPoint { LineMatchPoint(x: x, y: y) }

    /// Nearest distance from `point` to the sampled centre line (point-to-segment).
    private func offset(_ point: LineMatchPoint, from path: TracePath) -> Double {
        var best = Double.infinity
        for (a, b) in zip(path.points, path.points.dropFirst()) {
            let vx = b.x - a.x, vy = b.y - a.y
            let span = vx * vx + vy * vy
            let t = span > 0 ? min(1, max(0, ((point.x - a.x) * vx + (point.y - a.y) * vy) / span)) : 0
            best = min(best, point.distance(to: LineMatchPoint(x: a.x + t * vx, y: a.y + t * vy)))
        }
        return best
    }

    func testPackParsesSixTargetsAndBoard() throws {
        let pack = try loadPack()
        expectEqual(pack.schema, HanziPack.schemaID)
        expectTrue(pack.problems.isEmpty, "pack problems: \(pack.problems)")
        expectEqual(pack.board.targetWeek, Self.week)
        expectEqual(pack.defaults.week, Self.week)
        expectEqual(pack.characters.keys.sorted(), Self.week.sorted())
        expectEqual(pack.board.rows, 2)
        expectEqual(pack.board.columns, 5)
        expectEqual(pack.board.symbolsPerRow, 5)
        expectEqual(pack.board.targetCards, 2)
        expectTrue(pack.board.oneTargetPerRow && pack.board.distinctRows && pack.board.distinctTargetColumns)
        expectEqual(pack.board.approvedFindOnlyPool, ["入", "八", "本", "未"])
        expectEqual(pack.findOnly.keys.sorted(), ["入", "八", "本", "未"].sorted())
        expectEqual(pack.dealableFindOnly, ["入", "八", "本", "未"])
        let pairs = Set(pack.board.confusablePairs.map { Set($0) })
        expectEqual(pairs, [["上", "下"], ["左", "右"], ["人", "入"], ["人", "八"], ["木", "本"], ["木", "未"]])
        // Six targets: after the guard drops a target's paired glyphs, at least four week distractors remain,
        // so a five-glyph row never needs a find-only filler.
        for target in Self.week {
            let paired = pack.board.confusablePairs.filter { $0.contains(target) }.flatMap { $0 }
            let left = Self.week.filter { $0 != target && !paired.contains($0) }
            expectTrue(left.count >= pack.board.symbolsPerRow - 1, "distractors for \(target)")
        }
        expectFalse(pack.defaults.findEnabled || pack.defaults.writeEnabled, "both games start off")
        expectFalse(pack.defaults.audioEnabled || pack.defaults.jyutpingEnabled, "audio and jyutping start off")
        expectEqual(pack.defaults.guideLevel, .standard)
        expectEqual(pack.defaults.reviewEveryRounds, 4)
        expectTrue(pack.defaults.confusableGuard && pack.defaults.unlockStarsAfterOwnPlaytest)
        expectEqual(pack.defaults.grid, "tianzi")
        expectFalse(pack.defaults.miziGridEnabled)
        expectEqual(pack.board.scheduler.retryAfterInterveningRounds, 2)
        expectEqual(pack.board.scheduler.reviewEveryRounds, 4)
        expectTrue(pack.board.scheduler.cycleTargetsOnceBeforeShuffle && pack.board.scheduler.noImmediateTargetRepeat)
        // No fallback: an unknown glyph has no strokes and no paths.
        for glyph in ["大", "A", "人人", ""] {
            expectFalse(pack.isTarget(glyph) || pack.isFindOnly(glyph), glyph)
            expectTrue(pack.strokes(of: glyph).isEmpty && HanziGlyphs.paths(glyph, in: pack).isEmpty, glyph)
        }
        expectTrue(pack.isFindOnly("本") && !pack.isTarget("本") && pack.isTarget("木"))
    }

    func testStrokeCountsOrderAndBounds() throws {
        let pack = try loadPack()
        expectEqual(Self.week.map { pack.characters[$0]!.strokes.count }, [2, 3, 3, 5, 5, 4])
        for glyph in Self.week {
            let entry = pack.characters[glyph]!
            expectEqual(entry.strokes.map(\.type), Self.orders[glyph]!, "order of \(glyph)")
            expectEqual(entry.strokes.map(\.n), Array(1...entry.strokes.count))
            expectEqual(entry.moeSource.strokeCount, entry.strokes.count, "MOE count \(glyph)")
            expectEqual(entry.id, "hanzi:\(glyph)")
            let paths = HanziGlyphs.paths(glyph, in: pack)
            expectEqual(paths.count, entry.strokes.count)
            for (stroke, path) in zip(entry.strokes, paths) {
                let name = "\(glyph) stroke \(stroke.n)"
                expectEqual(path.start.x, stroke.start.x, accuracy: 0.01)
                expectEqual(path.start.y, stroke.start.y, accuracy: 0.01)
                expectEqual(path.end.x, stroke.end.x, accuracy: 0.01)
                expectEqual(path.end.y, stroke.end.y, accuracy: 0.01)
                expectTrue(path.length > 50, "parsed \(name)")
                // The 36-unit lane around every centre line stays inside the 300 × 300 box.
                let half = HanziGlyphs.laneWidth / 2
                expectTrue(path.points.allSatisfy { $0.x >= half && $0.x <= 300 - half && $0.y >= half && $0.y <= 300 - half },
                           "lane inside the box: \(name)")
                for index in 0..<(path.points.count - 1) {
                    expectTrue(path.points[index].distance(to: path.points[index + 1]) <= TracePath.sampleSpacing + 0.01)
                }
                expectEqual(stroke.marker?.label, "\(stroke.n)")
                expectEqual(stroke.marker?.anchor, stroke.start)
                if let shift = stroke.marker?.reviewLabelOffset {
                    expectEqual(stroke.marker?.leaderToActualStart, true, "leader for \(name)")
                    let label = p(stroke.start.x + shift.x, stroke.start.y + shift.y)
                    expectTrue((0...300).contains(label.x) && (0...300).contains(label.y), "label inside the box: \(name)")
                }
                let dx = stroke.end.x - stroke.start.x, dy = stroke.end.y - stroke.start.y
                switch stroke.type {
                case "橫": expectTrue(dx > 50 && abs(dy) < 0.5, "level left-to-right \(name)")
                case "豎": expectTrue(dy > 50 && abs(dx) < 0.5, "straight top-to-bottom \(name)")
                case "撇": expectTrue(dx < -50 && dy > 50, "down-left \(name)")
                case "捺", "點": expectTrue(dx > 40 && dy > 30, "down-right \(name)")
                case "橫折": expectTrue(dx > 50 && dy > 50, "across then down \(name)")
                default: expectTrue(false, "kind \(stroke.type)")
                }
                if glyph == "右" && stroke.n == 4 {
                    expectEqual(path.corners.count, 1)
                    expectEqual(path.point(at: path.corners[0]), p(226, 160))
                    expectTrue(path.corners[0] > 50 && path.corners[0] < path.length - 50, "turn inside the stroke")
                } else {
                    expectTrue(stroke.corners.isEmpty && path.corners.isEmpty, "no turn in \(name)")
                }
            }
        }
        // Run-1 centre lines are carried verbatim; 木's are the H0 MOE-derived ones.
        expectEqual(pack.characters["人"]!.strokes.map(\.svg), ["M158 54 C147 102 120 174 72 246", "M151 112 C180 170 208 217 255 250"])
        expectEqual(pack.characters["上"]!.strokes.map(\.svg), ["M137 43 L137 237", "M137 119 L231 119", "M62 237 L253 237"])
        expectEqual(pack.characters["下"]!.strokes.map(\.svg), ["M62 65 L252 65", "M142 65 L142 254", "M145 148 L196 181"])
        expectEqual(pack.characters["左"]!.strokes.map(\.svg), ["M90 75 L225 75", "M154 46 C143 91 112 145 67 184",
                                                               "M112 158 L229 158", "M171 158 L171 242", "M96 242 L247 242"])
        expectEqual(pack.characters["右"]!.strokes.map(\.svg), ["M90 80 L253 80", "M155 47 C146 90 115 139 76 169",
                                                               "M118 160 L118 244", "M118 160 L226 160 L226 244", "M118 244 L226 244"])
        expectEqual(pack.characters["木"]!.strokes.map(\.svg), ["M81 118 L207 118", "M142 56 L142 244",
                                                               "M138 122 C131 167 84 190 51 213", "M149 132 C176 162 198 211 249 201"])
        // 右 (D12): strokes 3 and 4 share one start with separate labels; the 口 inset names the true corner.
        let right = pack.characters["右"]!
        expectEqual(right.strokes[2].start, right.strokes[3].start)
        expectFalse(right.strokes[2].marker?.reviewLabelOffset == right.strokes[3].marker?.reviewLabelOffset, "separate leaders")
        let inset = right.mouthInset!
        expectEqual(inset.sharedStart, HanziPoint(x: 118, y: 160))
        expectEqual(inset.sharedStartStrokes, [3, 4])
        expectEqual(inset.sharedStartLabels, ["③↓", "④→"])
        expectEqual(inset.stopCorner, right.strokes[3].corners[0])
        expectTrue(inset.noLiftAtCorner && inset.separateLabelLeaders)
        let corner = right.guide.cornerContract!
        expectEqual(corner.strokeOneBased, 4)
        expectEqual(corner.point, HanziPoint(x: 226, y: 160))
        expectTrue(corner.penDownContinuous && corner.pauseExactlyOnce && corner.aheadMustNotPause && !corner.newStartAtCorner)
        expectEqual(corner.demoPauseSeconds, 0.3, accuracy: 0.0001)
        expectTrue(Self.week.filter { $0 != "右" }.allSatisfy { pack.characters[$0]!.guide.cornerContract == nil })
    }

    func testMuOrderAndShapesFollowMOETracks() throws {
        let pack = try loadPack()
        let mu = pack.characters["木"]!
        expectEqual(mu.strokes.map(\.type), ["橫", "豎", "撇", "捺"])
        expectEqual(mu.moeSource.page, "https://stroke-order.learningweb.moe.edu.tw/dictView.jsp?ID=26408&la=0")
        expectEqual(mu.moeSource.strokeData, "https://stroke-order.learningweb.moe.edu.tw/provideStrokeInfo.do?ucs=6728&useAlt=0")
        expectEqual(mu.moeSource.strokeCount, 4)
        expectEqual(mu.moeSource.checked, ["count", "order", "shape"])
        expectTrue(mu.moeSource.note.contains("404") && mu.moeSource.note.contains("xml[26408]"), "木 retrieval note")
        expectEqual(mu.jyutping, "muk6")
        expectEqual(mu.meaning.zhHK, "一棵樹")
        expectEqual(mu.cuePictures, ["tree", "tree-2"])
        // Track ends of the embedded xml[26408] (MOE 2048 grid), as in visa-games-sessions/hanzi/moe/mu-verified.json.
        let raw: [[Double]] = [[393, 810, 1545, 661], [960, 171, 935, 1880], [917, 767, 123, 1600], [1016, 863, 1923, 1487]]
        let track = mu.moeSource.track!
        expectEqual(track.ends.map { [$0[0].x, $0[0].y, $0[1].x, $0[1].y] }, raw)
        expectEqual(track.map.scale, 0.11, accuracy: 0.0001)
        // Every MOE-shaped glyph: each authored stroke starts and ends within 10 units of its own MOE track
        // (levelling a 橫 moves an end by at most 8.5), and its kind matches the MOE track's direction.
        var shaped: [String] = []
        for glyph in Self.week + pack.board.approvedFindOnlyPool {
            let source = pack.characters[glyph]?.moeSource ?? pack.findOnly[glyph]!.moeSource
            guard let track = source.track else {
                expectFalse(source.checked.contains("shape"), "\(glyph) claims a shape check without tracks")
                continue
            }
            shaped.append(glyph)
            expectEqual(source.checked, ["count", "order", "shape"])
            let strokes = pack.strokes(of: glyph)
            for (stroke, ends) in zip(strokes, track.ends) {
                let start = track.mapped(ends[0]), end = track.mapped(ends[1])
                expectTrue(start.distance(to: stroke.start.point) <= 10 && end.distance(to: stroke.end.point) <= 10,
                           "\(glyph) stroke \(stroke.n) follows its MOE track")
                let dx = end.x - start.x, dy = end.y - start.y
                let kind = abs(dy) < 0.3 * abs(dx) && dx > 0 ? "橫"
                    : abs(dx) < 0.3 * abs(dy) && dy > 0 ? "豎" : dx < 0 && dy > 0 ? "撇" : "捺"
                expectEqual(kind, stroke.type, "\(glyph) stroke \(stroke.n) kind from MOE")
            }
            // The order is pinned: any other stroke's track is far from this stroke's ends.
            for (i, stroke) in strokes.enumerated() {
                for (j, ends) in track.ends.enumerated() where j != i {
                    let far = track.mapped(ends[0]).distance(to: stroke.start.point) > 10
                        || track.mapped(ends[1]).distance(to: stroke.end.point) > 10
                    expectTrue(far, "\(glyph) stroke \(i + 1) is not MOE stroke \(j + 1)")
                }
            }
        }
        expectEqual(shaped, ["木", "入", "八", "本", "未"])
    }

    func testFindOnlyFormsAndReviewStatus() throws {
        let pack = try loadPack()
        let expected: [String: (count: Int, partner: String, id: Int, ucs: String)] = [
            "入": (2, "人", 20837, "5165"), "八": (2, "人", 20843, "516B"), "本": (5, "木", 26412, "672C"), "未": (5, "木", 26410, "672A")
        ]
        for (glyph, facts) in expected {
            let entry = pack.findOnly[glyph]!
            expectFalse(pack.isTarget(glyph), "\(glyph) is never a target")
            expectEqual(entry.id, "hanzi:\(glyph)")
            expectEqual(entry.strokes.count, facts.count)
            expectEqual(entry.strokes.map(\.type), Self.orders[glyph]!, "order of \(glyph)")
            expectEqual(entry.moeSource.strokeCount, facts.count)
            expectEqual(entry.confusableWith, [facts.partner])
            expectTrue(entry.moeSource.page == "https://stroke-order.learningweb.moe.edu.tw/dictView.jsp?ID=\(facts.id)&la=0",
                       "\(glyph) MOE page")
            expectTrue(entry.moeSource.strokeData.hasSuffix("ucs=\(facts.ucs)&useAlt=0"), "\(glyph) stroke data")
            expectTrue(entry.strokes.allSatisfy { $0.marker == nil }, "\(glyph) has no writing starts")
            expectFalse(entry.displayFormNote.isEmpty)
            expectEqual(HanziGlyphs.paths(glyph, in: pack).count, facts.count)
        }
        // Display-form review (design: forms pass H0 review before a deal shows them). All four are checked
        // against their MOE stroke XML and stay find-only (D2): never a target, no starts, no writing progress.
        expectTrue(expected.keys.allSatisfy { pack.findOnly[$0]!.displayFormVerified }, "display forms verified")
        expectTrue(pack.findOnly["入"]!.displayFormNote.contains("ID=20837"))
        expectTrue(pack.findOnly["八"]!.displayFormNote.contains("ID=20843"))
        // Track ends of the embedded xml[20837] / xml[20843] (MOE 2048 grid), from visa-games-sessions/hanzi/moe/.
        let ends: (String) -> [[Double]] = { glyph in
            pack.findOnly[glyph]!.moeSource.track!.ends.map { [$0[0].x, $0[0].y, $0[1].x, $0[1].y] }
        }
        expectEqual(ends("入"), [[918, 672, 124, 1570], [635, 485, 1940, 1564]])
        expectEqual(ends("八"), [[728, 902, 114, 1566], [725, 500, 1932, 1530]])
        // 人 starts with the 撇 on top. MOE 入 is the reverse: the 捺 starts above and left, and the 撇 starts on
        // the 捺. MOE 八 also has the 捺 head on top, above the 撇 start, but the two strokes never meet.
        let ren = HanziGlyphs.paths("人", in: pack), ru = HanziGlyphs.paths("入", in: pack), ba = HanziGlyphs.paths("八", in: pack)
        expectTrue(ren[0].start.y < ren[1].start.y, "人: the 撇 starts on top")
        expectTrue(ru[1].start.y < ru[0].start.y && ru[1].start.x < ru[0].start.x, "入: the 捺 starts above and left")
        expectTrue(offset(ru[0].start, from: ru[1]) <= 3, "入: the 撇 starts on the 捺")
        expectTrue(offset(ru[1].start, from: ru[0]) > 20, "入: the 捺 does not start on the 撇, as in 人")
        expectTrue(ba[1].start.y < ba[0].start.y && abs(ba[1].start.x - ba[0].start.x) <= 5, "八: the 捺 head is above the 撇")
        expectTrue(offset(ba[0].start, from: ba[1]) > 20 && offset(ba[1].start, from: ba[0]) > 20, "八: the strokes do not meet")
        // 未 (short top 橫, long lower 橫) is not 末; 本 adds a short 橫 below 木's skeleton.
        let wei = pack.findOnly["未"]!.strokes
        expectTrue(wei[0].end.x - wei[0].start.x < wei[1].end.x - wei[1].start.x && wei[0].start.y < wei[1].start.y)
        let ben = pack.findOnly["本"]!.strokes
        expectTrue(ben[4].start.y > ben[2].start.y && ben[4].start.y > ben[3].start.y, "本 bottom 橫 is last and lowest")
        expectTrue(ben[4].end.x - ben[4].start.x < ben[0].end.x - ben[0].start.x, "本 bottom 橫 is short")
    }

    func testGuideBeatsCuesAndSignPolicy() throws {
        let pack = try loadPack()
        let cueCounts: [String: Int] = ["人": 0, "上": 1, "下": 0, "左": 1, "右": 2, "木": 1]
        var stops = 0
        for glyph in Self.week {
            let entry = pack.characters[glyph]!
            let paths = HanziGlyphs.paths(glyph, in: pack)
            let guide = entry.guide
            expectEqual(guide.cues.count, cueCounts[glyph]!, "cues for \(glyph)")
            expectEqual(Set(guide.beats.map(\.stroke)), Set(0..<paths.count), "every stroke has a beat \(glyph)")
            expectTrue(guide.beats.allSatisfy { $0.seconds > 0 && $0.seconds <= 2 }, "beat seconds \(glyph)")
            for beat in guide.beats {
                if let until = beat.until {
                    expectTrue(offset(until.point.point, from: paths[beat.stroke]) <= 2, "beat point on \(glyph)")
                }
            }
            for cue in guide.cues {
                expectTrue(offset(cue.point.point, from: paths[cue.stroke]) <= 2, "cue on its stroke \(glyph)")
                expectTrue((0...300).contains(cue.signAt.x) && (0...300).contains(cue.signAt.y), "sign on the board \(glyph)")
                expectTrue(cue.signAt.point.distance(to: cue.point.point) >= 30, "sign clear of its cue point \(glyph)")
                switch cue.sign {
                case .ahead:
                    // D11: AHEAD only where the pen-down stroke passes a finished stroke.
                    let junction = paths[..<cue.stroke].contains { offset(cue.point.point, from: $0) <= 2 }
                    expectTrue(junction, "AHEAD at a junction \(glyph)")
                case .stop:
                    stops += 1
                    expectTrue(entry.strokes[cue.stroke].corners.contains(cue.point), "STOP at a true turn \(glyph)")
                }
            }
        }
        expectEqual(stops, 1)
        let right = pack.characters["右"]!.guide
        expectEqual(right.beats.count, 6)
        expectEqual(right.beats[3].until?.point, HanziPoint(x: 226, y: 160))
        expectEqual(right.cues.map(\.sign), [.ahead, .stop])
        let mu = pack.characters["木"]!.guide
        expectEqual(mu.beats.map(\.line.zhHK), ["橫先行！", "直落！", "撇落去！", "捺出去！"])
        expectEqual(mu.cues[0].stroke, 1)
        expectEqual(mu.cues[0].point, HanziPoint(x: 142, y: 118))
        expectEqual(mu.cues[0].sign, .ahead)
        expectEqual(mu.lastStroke.zhHK, "最後一筆：捺出去！")
        expectEqual(pack.characters["上"]!.guide.beats.map(\.line.zhHK), ["直落！", "短橫過去！", "長橫托住！"])
        expectEqual(right.beats.map(\.line.zhHK), ["橫先行！", "撇落去！", "口字左邊直落！", "口字上面橫過去！", "轉彎直落！", "口字下面一橫！"])
    }

    func testCopyIsHongKongTraditional() throws {
        let pack = try loadPack()
        var zh: [String] = []
        var en: [String] = []
        func add(_ text: HanziText) {
            zh += [text.zhHK] + [text.zhHKSub].compactMap { $0 }
            en += [text.en] + [text.enSub].compactMap { $0 }
        }
        pack.copy.values.forEach(add)
        for entry in pack.characters.values {
            add(entry.meaning)
            add(entry.guide.merge)
            add(entry.guide.lastStroke)
            add(entry.guide.hop)
            entry.guide.beats.forEach { add($0.line) }
            entry.guide.cues.forEach { add($0.line) }
            zh += [entry.meaningCue?.zhHK].compactMap { $0 } + (entry.mouthInset?.stepLabels ?? [])
        }
        pack.findOnly.values.forEach { add($0.meaning) }
        // 托 (托住, hold up from below) is standard Traditional; the OpenCC list flags it only because Simplified
        // 托 also stands for Traditional 託 (entrust). The locked spec line 「長橫托住！」 keeps it.
        let simplified = try Self.simplifiedOnly().subtracting(["托"])
        for line in zh {
            expectFalse(line.isEmpty)
            expectTrue(isTraditionalChineseOnly(line) && perfTraditionalOnly(line), line)
            expectFalse(line.contains { simplified.contains($0) }, "Simplified character in \(line)")
            expectFalse(line.contains("熄"), "build-80 wording: \(line)")
        }
        for line in en {
            expectFalse(line.isEmpty || line.contains { simplified.contains($0) }, line)
        }
        expectEqual(pack.copy.count, 29)
        expectEqual(pack.copy["header"]?.zhHK, "搵晒『{H}』！")
        expectEqual(pack.copy["writeHeader"]?.zhHK, "而家寫『{H}』！")
        expectEqual(pack.copy["writeSubline"]?.zhHK, "由綠色起點，跟住箭嘴寫。")
        expectEqual(pack.copy["wrong"]?.zhHK, "嗰個係『{Y}』。")
        expectEqual(pack.copy["foundPair"]?.zhHK, "『{H}』，{MEANING_ZH}！")
        expectEqual(pack.characters["左"]?.meaningCue?.zhHK, "我隻左手")
        expectEqual(pack.characters["右"]?.meaningCue?.zhHK, "我隻右手")
        expectEqual(pack.characters["左"]?.meaningCue?.directionArrow, "left")
        expectEqual(pack.characters["右"]?.meaningCue?.directionArrow, "right")
        // Placeholders are the four the find/write copy defines.
        let allowed: Set<String> = ["{H}", "{Y}", "{MEANING_ZH}", "{MEANING_EN}"]
        for line in zh + en {
            var rest = Substring(line)
            while let open = rest.firstIndex(of: "{") {
                guard let close = rest[open...].firstIndex(of: "}") else { expectTrue(false, line); break }
                expectTrue(allowed.contains(String(rest[open...close])), "placeholder in \(line)")
                rest = rest[rest.index(after: close)...]
            }
        }
    }

    func testCuePicturesExistInTheSharedSprite() throws {
        let pack = try loadPack()
        let sprite = try String(contentsOfFile: pack.cueArt.sprite, encoding: .utf8)
        let css = try String(contentsOfFile: pack.cueArt.stylesheet, encoding: .utf8)
        var symbols: [String: String] = [:]
        var bodies: [String: String] = [:]
        for chunk in sprite.components(separatedBy: "<symbol id=\"").dropFirst() {
            let id = String(chunk.prefix { $0 != "\"" })
            guard let box = chunk.range(of: "viewBox=\""), let end = chunk.range(of: "</symbol>") else {
                expectTrue(false, "symbol \(id)"); continue
            }
            symbols[id] = String(chunk[box.upperBound...].prefix { $0 != "\"" })
            bodies[id] = String(chunk[..<end.lowerBound])
        }
        let cues = Self.week.flatMap { pack.characters[$0]!.cuePictures }
        expectEqual(cues.count, 12)
        expectEqual(Set(cues).count, 12)
        for glyph in Self.week {
            expectEqual(pack.characters[glyph]!.cuePictures.count, 2, "two pictures for \(glyph)")
        }
        for id in cues {
            expectEqual(symbols[id], pack.cueArt.viewBox, "symbol \(id)")
        }
        // The new trees use the shared tokens only (D8): known classes, no inline colours, parseable paths.
        let defined = Set(css.components(separatedBy: ".").dropFirst().map { token in
            String(token.prefix { $0.isLetter || $0 == "-" })
        })
        for id in ["tree", "tree-2"] {
            let body = bodies[id] ?? ""
            expectFalse(body.isEmpty, id)
            for chunk in body.components(separatedBy: "class=\"").dropFirst() {
                for name in chunk.prefix(while: { $0 != "\"" }).split(separator: " ") {
                    expectTrue(defined.contains(String(name)), "\(id) class \(name)")
                }
            }
            expectFalse(body.contains("#") || body.contains("style="), "\(id) uses token classes, not inline colour")
            for chunk in body.components(separatedBy: " d=\"").dropFirst() {
                let data = String(chunk.prefix { $0 != "\"" })
                expectTrue((try? SVGPathData.parse(data))?.isEmpty == false, "\(id) path \(data)")
            }
            expectEqual(body.components(separatedBy: "class=\"ground-shadow\"").count - 1, 1, "\(id) one ground shadow")
        }
    }

    func testEveryTargetStrokeTracesAtExistingTolerances() throws {
        let pack = try loadPack()
        for glyph in Self.week {
            let paths = HanziGlyphs.paths(glyph, in: pack)
            let shape = ShapeTraceShape(slot: "hanzi", kind: .numeral, strokes: paths, colorIndex: 0,
                                        frame: LineMatchRect(x: 0, y: 0, width: 300, height: 300))
            let question = ShapeTraceQuestion(itemID: "hanzi:\(glyph)", kind: .tapCountTrace, level: .l1,
                scene: .numeralBoard, shift: 0, big: false, slant: false, shapes: [shape], laneWidth: HanziGlyphs.laneWidth,
                promptKey: "", promptTraditionalChinese: "", promptEnglish: "")
            for tolerance in [LineMatchTolerance.narrow, .standard, .wide] {
                var board = ShapeTraceBoard(question: question, tolerance: tolerance, directionHint: true)
                var clock = 0.0
                var attempts = 0
                while !board.isComplete && attempts < paths.count + 2 {
                    attempts += 1
                    guard let path = board.currentPath else { break }
                    clock += 0.1
                    _ = board.penDown(at: path.start, now: clock)
                    var distance = 0.0
                    while distance <= path.length + 16 {
                        clock += 0.02
                        let move = board.penMove(to: path.point(at: min(distance, path.length)), now: clock)
                        if case .strokeDone = move { break }
                        if case .shapeDone = move { break }
                        if case .allDone = move { break }
                        distance += 6
                    }
                    board.penUp()
                }
                expectTrue(board.isComplete, "\(glyph) at \(tolerance)")
                expectEqual(attempts, paths.count, "\(glyph) one pen-down per stroke at \(tolerance)")
            }
        }
    }

    /// A broken pack never loads in part: schema, references, geometry, sign policy and decoding all fail closed.
    func testLoaderFailsClosed() throws {
        let original = try Data(contentsOf: URL(fileURLWithPath: "Resources/HanziTap/hanzi-pack.json"))
        let root = try JSONSerialization.jsonObject(with: original)
        func set(_ node: Any, _ path: ArraySlice<Any>, _ value: Any) -> Any {
            guard let key = path.first else { return value }
            if let name = key as? String, var object = node as? [String: Any] {
                object[name] = set(object[name] as Any, path.dropFirst(), value)
                return object
            }
            if let index = key as? Int, var array = node as? [Any] {
                array[index] = set(array[index], path.dropFirst(), value)
                return array
            }
            preconditionFailure("no \(key) in the pack")
        }
        func load(_ path: [Any], _ value: Any) throws -> HanziPack {
            try HanziPack.load(data: JSONSerialization.data(withJSONObject: set(root, path[...], value)))
        }
        func rejects(_ path: [Any], _ value: Any, _ problem: String? = nil) {
            do {
                _ = try load(path, value)
                expectTrue(false, "accepted \(path)")
            } catch HanziPack.LoadError.invalid(let problems) {
                expectTrue(problem.map { fragment in problems.contains { $0.contains(fragment) } } ?? true,
                           "\(path): \(problems)")
            } catch {
                expectTrue(problem == nil, "\(path): \(error)")
            }
        }
        expectEqual(try load(["schema"], HanziPack.schemaID), try loadPack())
        expectThrowsError(try load(["schema"], "visagames.hanziPack.v0"))
        rejects(["characters", "木", "strokes", 1, "svg"], "M142 56 L142 344", "木 stroke 2 start/end differ")
        rejects(["characters", "木", "strokes", 1, "end"], [142, 344], "木 stroke 2 start/end differ")
        rejects(["characters", "木", "moeSource", "strokeCount"], 5, "木 stroke count")
        rejects(["characters", "木", "strokes", 2, "type"], "提", "木 stroke 3 kind")
        rejects(["characters", "木", "guide", "cues", 0, "sign"], "stop", "STOP is only allowed at a true turn")
        rejects(["characters", "上", "strokes", 0, "svg"], "M137 43 L137 237 M10 10 L20 20", "上 stroke 1 path")
        rejects(["characters", "右", "strokes", 3, "corners"], [[226, 200]], "右 stroke 4 corner")
        rejects(["characters", "下", "strokes", 1, "marker", "label"], "3", "下 marker 2")
        rejects(["characters", "左", "guide", "beats", 4, "until"], ["point": [171, 242], "pass": 1] as [String: Any], "左 stroke 5 needs a beat")
        rejects(["board", "targetWeek"], ["人", "上", "下", "左", "右", "大"], "defaults.week")
        rejects(["board", "targetWeek"], ["人", "上"], "fewer than 3 week targets")
        rejects(["findOnly", "本", "confusableWith"], ["上"], "本 confusableWith")
        rejects(["characters", "人", "guide", "beats", 0, "until"], "middle")
        rejects(["characters", "木", "strokes", 0, "start"], [81, 118, 0])
        rejects(["defaults", "guideLevel"], "most")
        rejects(["characters", "木", "cuePictures"], NSNull())
        // The Mac bundle ships the pack where `loadBundled` looks for it (bundle.sh does not run on Linux).
        let bundle = try String(contentsOfFile: "scripts/bundle.sh", encoding: .utf8)
        expectTrue(bundle.contains("cp Resources/HanziTap/hanzi-pack.json \"$bundle/Contents/Resources/HanziTap/hanzi-pack.json\""))
    }

    /// H1 adapters (fix round 1): each target as the shared stroke-order glyph (`StrokeGlyph.hanzi`) and guide
    /// (`HanziGuideData.spec`, `NumeralGuide(hanzi:in:)`), keyed `hanzi:<glyph>` and built from exactly the pack's
    /// centre lines in MOE order. Find-only and unknown glyphs are never written, so they get neither.
    func testStrokeOrderAndGuideAdapters() throws {
        let pack = try loadPack()
        var counts: [Int] = []
        for glyph in Self.week {
            let entry = pack.characters[glyph]!
            let paths = HanziGlyphs.paths(glyph, in: pack)
            guard let strokeGlyph = StrokeGlyph.hanzi(glyph, in: pack), let spec = HanziGuideData.spec(glyph, in: pack),
                  let guide = NumeralGuide(hanzi: glyph, in: pack) else {
                expectTrue(false, "adapters for \(glyph)")
                continue
            }
            counts.append(strokeGlyph.strokes.count)
            expectEqual(strokeGlyph.id, "hanzi:\(glyph)")
            expectEqual(strokeGlyph.progressKey, "hanzi:\(glyph)")
            expectEqual(strokeGlyph.script, .hanzi)
            expectEqual(strokeGlyph.orderStandard, "MOE")
            expectTrue(strokeGlyph.box.width == 300 && strokeGlyph.box.height == 300 && strokeGlyph.alternates.isEmpty, glyph)
            // Stroke i is the pack's stroke i: the trace board's path, its 筆劃 kind, its start and end, inside the box.
            expectEqual(strokeGlyph.strokes.map(\.path), paths)
            expectEqual(strokeGlyph.strokes.map(\.kind), Self.orders[glyph]!.map { Optional($0) })
            for (stroke, source) in zip(strokeGlyph.strokes, entry.strokes) {
                let name = "\(glyph) stroke \(source.n)"
                expectTrue(stroke.path.start.distance(to: source.start.point) < 0.01
                           && stroke.path.end.distance(to: source.end.point) < 0.01, name)
                expectTrue(stroke.path.points.allSatisfy { (0...300).contains($0.x) && (0...300).contains($0.y) }, name)
                // A turn only at the declared true corner (右's 橫折), where the trace board stops too.
                expectEqual(stroke.turns, stroke.path.corners, name)
                expectEqual(stroke.turns.isEmpty, !(glyph == "右" && source.n == 4), name)
            }
            // The shared player draws them in that order, lifts between strokes and pauses only at 右's corner.
            var drawn: [Int] = []
            var lifts = 0
            var pauses: [Int] = []
            for step in StrokeOrderTimeline(glyph: strokeGlyph, dosage: .remind).steps {
                switch step.kind {
                case .draw(let stroke, _, _): if drawn.last != stroke { drawn.append(stroke) }
                case .lift: lifts += 1
                case .pause(let stroke, _): pauses.append(stroke)
                case .lead, .hold: break
                }
            }
            expectEqual(drawn, Array(0..<entry.strokes.count), glyph)
            expectEqual(lifts, entry.strokes.count - 1, glyph)
            expectEqual(pauses, glyph == "右" ? [3] : [], glyph)
            // The guide spec: the pack's beats, cues and lines in order; `zh` is the HK Traditional line.
            let source = entry.guide
            expectEqual(spec.beats.map(\.stroke), source.beats.map(\.stroke), glyph)
            expectEqual(spec.beats.map(\.seconds), source.beats.map(\.seconds), glyph)
            expectEqual(spec.beats.map { $0.until.map { LineMatchPoint(x: $0.x, y: $0.y) } },
                        source.beats.map { $0.until?.point.point }, glyph)
            expectEqual(spec.beats.map(\.until?.pass), source.beats.map(\.until?.pass), glyph)
            expectEqual(spec.beats.map(\.line.zh), source.beats.map(\.line.zhHK), glyph)
            expectEqual(spec.beats.map(\.line.en), source.beats.map(\.line.en), glyph)
            expectEqual(spec.cues.map(\.sign.rawValue), source.cues.map(\.sign.rawValue), glyph)
            expectEqual(spec.cues.map(\.signAt), source.cues.map(\.signAt.point), glyph)
            expectEqual(spec.cues.map(\.line.zh), source.cues.map(\.line.zhHK), glyph)
            expectEqual([spec.merge.zh, spec.hop?.zh, spec.lastStroke?.zh] as [String?],
                        [source.merge.zhHK, source.hop.zhHK, source.lastStroke.zhHK], glyph)
            // Resolved on the same paths: each beat ends on its stroke, a stroke's closing beat at its end.
            expectEqual(guide.glyphKey, "hanzi:\(glyph)")
            expectEqual(guide.paths, paths)
            expectEqual(guide.beats.map(\.stroke), source.beats.map(\.stroke), glyph)
            for (beat, beatSource) in zip(guide.beats, source.beats) {
                let length = paths[beat.stroke].length
                expectTrue(beat.end > 0 && beat.end <= length, glyph)
                if beatSource.until == nil { expectEqual(beat.end, length, accuracy: 0.001) }
            }
            expectEqual(guide.cues.count, source.cues.count, glyph)
            // A placement moves lines and signs together (the 田字格 stage placement itself is H3).
            let offset = LineMatchPoint(x: 400, y: 100)
            let placed = NumeralGuide(hanzi: glyph, in: pack, offset: offset, scale: 1.5)!
            expectEqual(placed.paths, HanziGlyphs.paths(glyph, in: pack, offset: offset, scale: 1.5))
            expectEqual(placed.cues.count, guide.cues.count, glyph)
            for (cue, base) in zip(placed.cues, guide.cues) {
                expectEqual(cue.signPoint.x, 400 + base.signPoint.x * 1.5, accuracy: 0.001)
                expectEqual(cue.signPoint.y, 100 + base.signPoint.y * 1.5, accuracy: 0.001)
            }
        }
        expectEqual(counts, [2, 3, 3, 5, 5, 4])
        for glyph in ["入", "八", "本", "未", "大", "a", "", "人人", "hanzi:人"] {
            expectNil(StrokeGlyph.hanzi(glyph, in: pack))
            expectNil(HanziGuideData.spec(glyph, in: pack))
            expectNil(NumeralGuide(hanzi: glyph, in: pack))
        }
    }

    /// `Fixtures/traditional-check/simplified-only.txt`: one character per entry, `#` lines are comments.
    private static func simplifiedOnly() throws -> Set<Character> {
        let beside = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/traditional-check/simplified-only.txt")
        let url = FileManager.default.fileExists(atPath: beside.path) ? beside
            : URL(fileURLWithPath: "Tests/VisaCoreTests/Fixtures/traditional-check/simplified-only.txt")
        var characters: Set<Character> = []
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") where !line.hasPrefix("#") {
            for character in line where !character.isWhitespace { characters.insert(character) }
        }
        return characters
    }
}
