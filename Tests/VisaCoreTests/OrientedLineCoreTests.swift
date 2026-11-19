import Foundation
import VisaCore

/// 畫直線・四方 R0 (0.42.0; four-direction design §11.3): the card's registration and deal facts, kept apart from
/// 畫直線 · 熱身; the 3 × 3 deal matrix (T1); direction contracts, polarity and reverse twins (T2, T2b, the geometry of
/// T4b); footprints, bounds and keep-outs (T3); its own settings store (T5); copy (T6).
final class OrientedLineCoreTests {
    private static let pairs: [(OrientedLineShapeSetting, OrientedLineDirectionSetting)] =
        OrientedLineShapeSetting.allCases.flatMap { shape in OrientedLineDirectionSetting.allCases.map { (shape, $0) } }

    private static func deg(_ radians: Double) -> Double { radians * 180 / Double.pi }

    // MARK: Registration and facts

    func testRegistrationAndFactsKeepTheOriginalCardApart() {
        let kind = ActivityKind.traceOrientedLines
        expectEqual(kind.rawValue, "traceOrientedLines")
        // C1: the exact locked title (separator U+30FB); the English subtitle is an implementer default.
        expectEqual(kind.parentCardTitle, "畫直線・四方")
        expectEqual(kind.parentCardTitle.unicodeScalars.map(\.value)[3], 0x30FB)
        expectEqual(kind.parentCardEnglish, "Straight lines · Four ways")
        expectEqual(kind.parentShortLabel, "四方")
        expectEqual(kind.parentHelpTraditionalChinese, "由綠色起點，跟住箭嘴畫去紅色終點！")
        expectFalse(kind.parentHeroAssetIDs.isEmpty)
        // Not part of the shared 畫形狀設定 family; its own D11 試玩 gate; default OFF on every star (D7).
        expectFalse(kind.isShapeTraceFamily)
        expectTrue(kind.requiresPlaytestBeforeStars)
        expectTrue(ActivityCatalog.defaultOffKinds.contains(kind))
        expectFalse(ActivityCatalog.defaultOnKinds.contains(kind))
        expectEqual(MissionGameAssignment.defaultStars(for: kind), [])
        for star in ChildDifficulty.allCases { expectFalse(MissionGameAssignment.defaults.isEnabled(kind, star: star)) }
        expectEqual(StatusRoute(board: kind), .lineMatchFamily)
        expectEqual(WeeklyArea.of(kind: kind.rawValue), .pen)
        expectTrue(QuestionGeneration.isGenerated(kind))
        expectEqual(PerfChoiceCatalog.chance(for: kind), 1)
        expectNil(PerfChoiceCatalog.correctChoice(for: kind))
        expectEqual(PerfChoiceCatalog.item(for: kind), OrientedLineGenerator.reference.itemID)
        expectEqual(ActivityCatalog.hintTraditionalChinese(for: kind), OrientedLineCopy.hint)

        // Deal facts come from the round's own snapshot and never carry the shared 畫形狀設定 fields.
        let settings = OrientedLineSettings(lineShape: .diagonal, lineDirection: .leftward, lineHelp: .less, tolerance: .wide)
        let question = OrientedLineGenerator.make(seed: "facts", settings: settings)
        let facts = PerfChoiceCatalog.facts(orientedLines: question)
        expectEqual(facts.item, question.itemID)
        expectEqual(facts.chance, 1)
        expectNil(facts.correctChoice)
        expectEqual(facts.level, .l1)
        expectEqual(facts.slots, ["line1", "line2", "line3"])
        let fields = facts.dealtFields
        expectEqual(Set(fields.keys), ["gen", "level", "practice", "shapes", "slots_drawn", "footprints", "shape_trace_level",
                                       "tolerance", "line_shape", "line_direction", "line_help", "trace_rule", "match_mode"])
        expectEqual(fields["shapes"], .strings(["down_left", "down_left", "down_left"]))
        expectEqual(fields["line_shape"], .string("diagonal"))
        expectEqual(fields["line_direction"], .string("leftward"))
        expectEqual(fields["line_help"], .string("less"))
        expectEqual(fields["tolerance"], .string("wide"))
        expectEqual(fields["trace_rule"], .string("connected_coverage_v2"))
        expectEqual(fields["match_mode"], .string("guided"))
        expectEqual(fields["practice"], .string("shape_trace"))
        for shared in ["direction_coaching", "slant_enabled", "stop_coaching", "dot_style", "shape_mix"] {
            expectNil(fields[shared])
        }
        // Practice only in review and rollups, even without `match_mode`.
        let bare = PerfEvent(type: .gameDealt, timestamp: Date(timeIntervalSince1970: 1_800_000_000), tz: "+08:00", mono: 0,
                             launch: "L", seq: 1, app: "0.42.0", actor: .child, mode: "lock", session: "s",
                             fields: ["round": .string("r"), "kind": .string(kind.rawValue), "stars": .int(1)])
        expectTrue(PerfQuestionGeneration.isPracticeOnly(bare))
        print("  畫直線・四方: own kind beside 畫直線 · 熱身 — title U+30FB, default OFF, own 試玩 gate, practice facts from the snapshot, no shared 畫形狀設定 field")
    }

    // MARK: T1 deal matrix

    func testDealsFollowTheThreeByThreeMatrix() {
        expectEqual(OrientedLineShapeSetting.allCases, [.across, .diagonal, .both])
        expectEqual(OrientedLineDirectionSetting.allCases, [.rightward, .leftward, .both])
        var digest = ""
        var deals = 0
        for (shape, direction) in Self.pairs {
            let settings = OrientedLineSettings(lineShape: shape, lineDirection: direction)
            let allowed = Set(OrientedLineGenerator.compositions(shape, direction).map { $0 })
            var seenCompositions = Set<[OrientedLineVariant]>()
            var seenFootprints = Set<OrientedLineFootprint>()
            for i in 0..<300 {
                let q = OrientedLineGenerator.make(seed: "m\(i)", settings: settings)
                deals += 1
                expectEqual(q, OrientedLineGenerator.make(seed: "m\(i)", settings: settings))
                expectTrue(q.isWellFormed, q.itemID)
                expectEqual(q.kind, .traceOrientedLines)
                expectEqual(q.dealt, settings)
                expectEqual(q.lines.count, 3)
                expectTrue(q.itemID.hasPrefix("traceOrientedLines.v1.\(shape.rawValue).\(direction.rawValue)."))
                expectFalse(q.itemID.hasPrefix("traceLines"))
                let variants = q.lines.map(\.variant)
                expectTrue(allowed.contains(variants), "\(variants)")
                // Shapes (§3.3): 橫線 A-A-A, 斜線 D-D-D, 橫斜都有 A-D-A or A-D-D (the first line is horizontal).
                switch shape {
                case .across: expectTrue(variants.allSatisfy(\.isHorizontal))
                case .diagonal: expectTrue(variants.allSatisfy { !$0.isHorizontal })
                case .both:
                    expectTrue(variants[0].isHorizontal && !variants[1].isHorizontal)
                }
                // Directions: all rightward, all leftward, or at least one of each.
                switch direction {
                case .rightward: expectTrue(variants.allSatisfy(\.isRightward))
                case .leftward: expectTrue(variants.allSatisfy { !$0.isRightward })
                case .both: expectTrue(variants.contains(where: \.isRightward) && variants.contains { !$0.isRightward })
                }
                seenCompositions.insert(variants)
                for line in q.lines { seenFootprints.insert(line.footprint) }
                // The next deal never repeats the last item, and stays within the new kind.
                let again = OrientedLineGenerator.make(seed: "m\(i)", settings: settings, avoidingItem: q.itemID)
                expectTrue(again.itemID != q.itemID, "no back-to-back repeat")
                expectTrue(again.itemID.hasPrefix("traceOrientedLines.v1."))
                if i < 20 { digest += q.itemID + "\n" }
            }
            expectEqual(seenCompositions, allowed)
            let expectedFootprints = (shape == .diagonal ? 0 : 27) + (shape == .across ? 0 : 3)
            expectEqual(seenFootprints.count, expectedFootprints)
        }
        // The composition table of §3.2 / §3.3.
        expectEqual(OrientedLineGenerator.compositions(.across, .rightward), [[.right, .right, .right]])
        expectEqual(OrientedLineGenerator.compositions(.diagonal, .leftward), [[.downLeft, .downLeft, .downLeft]])
        expectEqual(Set(OrientedLineGenerator.compositions(.both, .rightward)),
                    [[.right, .upRight, .right], [.right, .upRight, .upRight]])
        expectEqual(OrientedLineGenerator.compositions(.both, .both).count, 12)
        expectEqual(OrientedLineGenerator.compositions(.across, .both).count, 6)
        // The defaults (C2): 橫斜都有 + 兩個方向都有, 標準 help, 標準 tolerance; the reference item is well formed.
        expectEqual(OrientedLineSettings.defaults,
                    OrientedLineSettings(lineShape: .both, lineDirection: .both, lineHelp: .standard, tolerance: .standard))
        expectTrue(OrientedLineGenerator.reference.isWellFormed)
        expectEqual(OrientedLineGenerator.make(seed: "x").dealt, .defaults)
        // Pinned across processes (FNV-1a of 20 seeds × 9 pairs).
        expectEqual(OrientedLineRegressionTests.fnv(digest), "3a2e0989e453bebb")
        print("  畫直線・四方 T1: \(deals) deals over the 3 × 3 matrix — compositions, footprints, no repeat, pinned across processes")
    }

    // MARK: T2, T2b, T4b geometry

    func testDirectionContractsPolarityAndTwins() {
        let lines = OrientedLineGenerator.allLines
        expectEqual(lines.count, 60)
        for line in lines {
            let dx = line.finish.x - line.start.x, dy = line.finish.y - line.start.y
            switch line.variant {
            case .right: expectTrue(dx > 0 && dy == 0, "→ \(line.footprint.code)")
            case .left: expectTrue(dx < 0 && dy == 0, "← \(line.footprint.code)")
            case .upRight: expectTrue(dx > 0 && dy < 0, "↗ \(line.footprint.code)")
            case .downLeft: expectTrue(dx < 0 && dy > 0, "↙ \(line.footprint.code)")
            }
            if !line.variant.isHorizontal {
                let size = Self.deg(atan2(abs(dy), abs(dx)))
                expectTrue(size >= 30 && size <= 40)
            }
            expectTrue(line.meetsContract)
            // T2b: u is a unit vector along P0 → P1; s(P0) = 0, s(P1) = L, s grows toward red.
            let u = line.unit
            expectEqual(u.x * u.x + u.y * u.y, 1, accuracy: 1e-9)
            expectEqual(line.progress(of: line.start), 0, accuracy: 1e-9)
            expectEqual(line.progress(of: line.finish), line.length, accuracy: 1e-9)
            expectEqual(line.progress(of: line.point(at: 40)), 40, accuracy: 1e-9)
            expectTrue(line.progress(of: line.point(at: 41)) > line.progress(of: line.point(at: 40)))
            let n = line.normal
            expectEqual(line.lateral(of: LineMatchPoint(x: line.start.x + 7 * n.x, y: line.start.y + 7 * n.y)), 7,
                        accuracy: 1e-9)
            expectTrue(n.y >= 0, "n points to the screen-down side")
            // Signs: green at P0 − 130u, red at P1 + 130u; C = L − 10, G = L − 15.5.
            expectEqual(line.greenSign.distance(to: LineMatchPoint(x: line.start.x - 130 * u.x, y: line.start.y - 130 * u.y)),
                        0, accuracy: 1e-9)
            expectEqual(line.redSign.distance(to: LineMatchPoint(x: line.finish.x + 130 * u.x, y: line.finish.y + 130 * u.y)),
                        0, accuracy: 1e-9)
            expectEqual(line.completion, line.length - 10, accuracy: 1e-9)
            expectEqual(line.guidanceLimit, line.length - 15.5, accuracy: 1e-9)
            // T4b geometry: arrows, chevrons and the car point along u: 0°, 180°, −35°, 145°.
            let angle = Self.deg(line.angle)
            switch line.variant {
            case .right: expectEqual(angle, 0, accuracy: 1e-9)
            case .left: expectEqual(abs(angle), 180, accuracy: 1e-9)
            case .upRight: expectEqual(angle, -35, accuracy: 0.05)
            case .downLeft: expectEqual(angle, 145, accuracy: 0.05)
            }
        }
        // A reverse line uses exactly its twin's footprint: same bars and sign centres, P0 / P1 and the colours swapped;
        // the same normal, so d is direction-free.
        for (forward, reverse) in [(OrientedLineVariant.right, OrientedLineVariant.left), (.upRight, .downLeft)] {
            let footprints = forward.isHorizontal ? OrientedLineFootprint.allHorizontal : OrientedLineFootprint.allDiagonal
            for footprint in footprints {
                let a = OrientedLine(variant: forward, footprint: footprint)
                let b = OrientedLine(variant: reverse, footprint: footprint)
                expectEqual(a.start, b.finish)
                expectEqual(a.finish, b.start)
                expectEqual(a.greenSign.distance(to: b.redSign), 0, accuracy: 1e-9)
                expectEqual(a.redSign.distance(to: b.greenSign), 0, accuracy: 1e-9)
                expectEqual(a.normal.distance(to: b.normal), 0, accuracy: 1e-12)
                let probe = LineMatchPoint(x: a.start.x + 33, y: a.start.y + 21)
                expectEqual(a.lateral(of: probe), b.lateral(of: probe), accuracy: 1e-9)
                expectEqual(a.progress(of: probe) + b.progress(of: probe), a.length, accuracy: 1e-9)
            }
        }
        // §4.1 worked rows (standard middle footprints).
        let right = OrientedLine(variant: .right, footprint: .horizontal(left: 1, right: 1, row: 1))
        expectEqual(right.start, LineMatchPoint(x: 330, y: 330))
        expectEqual(right.finish, LineMatchPoint(x: 900, y: 330))
        expectEqual(right.greenSign, LineMatchPoint(x: 200, y: 330))
        expectEqual(right.redSign, LineMatchPoint(x: 1030, y: 330))
        let left = OrientedLine(variant: .left, footprint: .horizontal(left: 1, right: 1, row: 1))
        expectEqual(left.greenSign, LineMatchPoint(x: 1030, y: 330))
        expectEqual(left.redSign, LineMatchPoint(x: 200, y: 330))
        let up = OrientedLine(variant: .upRight, footprint: .diagonal(1))
        expectEqual(up.start, LineMatchPoint(x: 450, y: 446))
        expectEqual(up.finish, LineMatchPoint(x: 728.5, y: 251))
        expectEqual(up.length, 340, accuracy: 0.05)
        expectEqual(up.greenSign.x, 343.5, accuracy: 0.05)
        expectEqual(up.greenSign.y, 520.6, accuracy: 0.05)
        expectEqual(up.redSign.x, 835.0, accuracy: 0.05)
        expectEqual(up.redSign.y, 176.4, accuracy: 0.05)
        let down = OrientedLine(variant: .downLeft, footprint: .diagonal(1))
        expectEqual(down.start, LineMatchPoint(x: 728.5, y: 251))
        expectEqual(down.greenSign.x, 835.0, accuracy: 0.05)
        expectEqual(down.redSign.y, 520.6, accuracy: 0.05)
        // Item ids encode each line's variant and footprint.
        let q = OrientedLineGenerator.reference
        expectEqual(q.itemID, "traceOrientedLines.v1.both.both.right-downLeft-left.a22y2-d2-a22y2")
        print("  畫直線・四方 T2: 60 lines — → ← ↗ ↙ contracts, s from green to red, signs at P0 − 130u / P1 + 130u, reverse twins share the footprint, 0° 180° −35° 145°")
    }

    // MARK: T3 bounds and keep-outs

    func testFootprintsFitTheBoardAndKeepOuts() {
        var lengths: [Double] = []
        var outerTop = Double.greatestFiniteMagnitude, outerBottom = 0.0, outerLeft = Double.greatestFiniteMagnitude
        var outerRight = 0.0
        for line in OrientedLineGenerator.allLines {
            expectTrue(line.fitsLayout, "\(line.variant) \(line.footprint.code)")
            let top = min(line.start.y, line.finish.y), bottom = max(line.start.y, line.finish.y)
            expectTrue(top - 50 >= 118 && bottom <= 540)
            let outer = line.outerBounds
            expectTrue(outer.x >= 0 && outer.maxX <= 1280 && outer.y >= 120)
            // Clock keep-out K (x ≥ 1182, y ≤ 56), the parent corner (x ≥ 1060, y ≥ 560), the status block
            // (x 440–840, y ≥ 580).
            expectFalse(outer.maxX >= 1182 && outer.y <= 56)
            expectFalse(outer.maxX >= 1060 && outer.maxY >= 560)
            expectFalse(outer.maxY >= 580 && outer.maxX >= 440 && outer.x <= 840)
            outerTop = min(outerTop, outer.y)
            outerBottom = max(outerBottom, outer.maxY)
            outerLeft = min(outerLeft, outer.x)
            outerRight = max(outerRight, outer.maxX)
            if line.variant.isHorizontal { lengths.append(line.length) }
            else { expectEqual(line.length, 340, accuracy: 0.05) }
        }
        expectEqual(lengths.min() ?? 0, 510)
        expectEqual(lengths.max() ?? 0, 630)
        // §4.2 extents: horizontal x 114 … 1116; diagonal top 120.4, bottom 576.6, x 257.5 … 921.0.
        expectEqual(outerLeft, 114, accuracy: 0.05)
        expectEqual(outerRight, 1116, accuracy: 0.05)
        expectEqual(outerTop, 120.4, accuracy: 0.05)
        expectEqual(outerBottom, 576.6, accuracy: 0.05)
        let diagonals = OrientedLineGenerator.allLines.filter { !$0.variant.isHorizontal }.map(\.outerBounds)
        expectEqual(diagonals.map(\.x).min() ?? 0, 257.5, accuracy: 0.05)
        expectEqual(diagonals.map(\.maxX).max() ?? 0, 921.0, accuracy: 0.05)
        print("  畫直線・四方 T3: 30 footprints × 2 directions inside the board — L 510–630 / 340 u, top 120.4, bottom 576.6, K, the parent corner and the status block clear")
    }

    // MARK: T5 settings

    func testSettingsDecodeMatrixAndOwnStore() throws {
        let suite = "VisaGames.orientedLine.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OrientedLineSettingsStore(defaults: defaults)
        expectEqual(OrientedLineSettingsStore.key, "VisaGames.orientedLineSettings.v1")
        expectEqual(store.load(), .defaults)
        // Every 線形 × 方向 × 畫線提示 × 畫線寬容度 round-trips.
        var count = 0
        for (shape, direction) in Self.pairs {
            for help in TapCountGuidanceLevel.allCases {
                for tolerance in LineMatchTolerance.allCases {
                    let settings = OrientedLineSettings(lineShape: shape, lineDirection: direction, lineHelp: help,
                                                        tolerance: tolerance)
                    store.save(settings)
                    expectEqual(store.load(), settings)
                    count += 1
                }
            }
        }
        expectEqual(count, 81)
        func decode(_ json: String) -> OrientedLineSettings {
            defaults.set(Data(json.utf8), forKey: OrientedLineSettingsStore.key)
            return store.load()
        }
        // Missing keys → both / both / standard / standard (C2: a missing 線形 is 橫斜都有, never 原本 or anything else).
        expectEqual(decode("{}"), .defaults)
        expectEqual(decode("{\"lineDirection\":\"leftward\"}").lineShape, .both)
        expectEqual(decode("{\"lineDirection\":\"leftward\"}").lineDirection, .leftward)
        expectEqual(decode("{\"lineShape\":\"across\"}").lineDirection, .both)
        expectEqual(decode("{\"lineShape\":\"across\"}").lineHelp, .standard)
        expectEqual(decode("{\"lineShape\":\"across\"}").tolerance, .standard)
        // Unknown values, a stored classic and wrong types → that field's default, field by field.
        expectEqual(decode("{\"lineShape\":\"classic\",\"lineDirection\":\"rightward\"}"),
                    OrientedLineSettings(lineDirection: .rightward))
        expectEqual(decode("{\"lineShape\":7,\"lineDirection\":\"up\",\"lineHelp\":\"lots\",\"lineTolerance\":\"huge\"}"), .defaults)
        expectEqual(decode("{\"lineShape\":\"diagonal\",\"lineHelp\":\"more\",\"lineTolerance\":\"narrow\"}"),
                    OrientedLineSettings(lineShape: .diagonal, lineHelp: .more, tolerance: .narrow))
        // The never-shipped lineSet key is ignored; a corrupt blob or a non-object reads as the defaults.
        expectEqual(decode("{\"lineSet\":\"classic\",\"lineDirection\":\"leftward\"}"), OrientedLineSettings(lineDirection: .leftward))
        expectEqual(decode("nope"), .defaults)
        expectEqual(decode("[\"across\"]"), .defaults)
        expectFalse(OrientedLineShapeSetting.allCases.map(\.rawValue).contains("classic"))
        // Its own key only: 畫形狀設定 (VisaGames.shapeTraceSettings.v1) is never read or written by this store.
        let shapeStore = ShapeTraceSettingsStore(defaults: defaults)
        var shapes = ShapeTraceSettings.defaults
        shapes.tolerance = .wide
        shapes.directionHint = false
        shapeStore.save(shapes)
        let before = defaults.data(forKey: ShapeTraceSettingsStore.key)
        store.save(OrientedLineSettings(tolerance: .narrow))
        expectEqual(store.load().tolerance, .narrow)
        expectEqual(defaults.data(forKey: ShapeTraceSettingsStore.key), before)
        defaults.removeObject(forKey: OrientedLineSettingsStore.key)
        expectEqual(store.load(), .defaults, "畫形狀設定's tolerance never becomes this card's")
        expectEqual(shapeStore.load(), shapes)
        let fresh = UserDefaults(suiteName: suite + ".fresh")!
        defer { fresh.removePersistentDomain(forName: suite + ".fresh") }
        OrientedLineSettingsStore(defaults: fresh).save(.defaults)
        expectNil(fresh.data(forKey: ShapeTraceSettingsStore.key))
        // Stored bytes are stable (sorted keys).
        expectEqual(String(decoding: OrientedLineSettingsStore.encode(.defaults), as: UTF8.self),
                    "{\"lineDirection\":\"both\",\"lineHelp\":\"standard\",\"lineShape\":\"both\",\"lineTolerance\":\"standard\"}")
        // The variants a selection deals (the parent panel's lit thumbnails).
        expectEqual(OrientedLineSettings.defaults.variants, [.right, .left, .upRight, .downLeft])
        expectEqual(OrientedLineSettings(lineShape: .across, lineDirection: .leftward).variants, [.left])
        expectEqual(OrientedLineSettings(lineShape: .diagonal).variants, [.upRight, .downLeft])
        // The judged half-width follows the dealt tolerance only: 50 / 75 / 110 u.
        for (tolerance, half) in zip(LineMatchTolerance.allCases, [50.0, 75, 110]) {
            expectEqual(OrientedLineGenerator.make(seed: "w", settings: OrientedLineSettings(tolerance: tolerance)).halfWidth,
                        half, accuracy: 1e-9)
        }
        print("  畫直線・四方 T5: 81 settings round-trip in VisaGames.orientedLineSettings.v1; missing → 橫斜都有 / 兩個方向都有 / 標準 / 標準 field by field; classic, lineSet, corrupt; 畫形狀設定 never read or written")
    }

    // MARK: T6 copy

    func testCopyIsTraditionalAndNamesTheActualGreenEnd() throws {
        let fixture = URL(fileURLWithPath: "Tests/VisaCoreTests/Fixtures/traditional-check/simplified-only.txt")
        let simplified = Set(try String(contentsOf: fixture, encoding: .utf8).split(separator: "\n")
            .filter { !$0.hasPrefix("#") }.joined().filter { !$0.isWhitespace })
        expectTrue(simplified.count > 2000)
        let kind = ActivityKind.traceOrientedLines
        let traditional = OrientedLineCopy.allTraditionalLines
            + [kind.parentCardTitle, kind.parentShortLabel, kind.parentHelpTraditionalChinese]
        for line in traditional {
            expectFalse(line.isEmpty)
            expectFalse(line.contains { simplified.contains($0) }, "Simplified character in \(line)")
            expectFalse(line.contains("喎"))
        }
        let english = OrientedLineCopy.allEnglishLines + [kind.parentCardEnglish, kind.parentHelpEnglish]
        for line in english {
            expectFalse(line.isEmpty)
            expectTrue(line.unicodeScalars.allSatisfy { $0.isASCII || $0 == "·" }, "non-ASCII English: \(line)")
        }
        // Every variant has every keyed line, each with its own key; → keeps today's start and cue lines.
        var keys = Set<String>()
        for v in OrientedLineVariant.allCases {
            for prompt in [OrientedLineCopy.prompt([v, v, v]), OrientedLineCopy.start(v), OrientedLineCopy.demo(v),
                           OrientedLineCopy.wrongStart(v), OrientedLineCopy.reverse(v), OrientedLineCopy.earlyFinish(v),
                           OrientedLineCopy.pause(v), OrientedLineCopy.cue(v)] {
                expectTrue(keys.insert(prompt.key).inserted, prompt.key)
                expectFalse(prompt.traditionalChinese.isEmpty || prompt.english.isEmpty)
            }
        }
        expectEqual(keys.count, 32)
        expectEqual(OrientedLineCopy.start(.right), ShapeTraceCopy.start(.across)!)
        expectEqual(OrientedLineCopy.cue(.right), ShapeTraceCopy.cue(.across))
        // Side words name the actual green end, by where the green sign really is.
        for line in OrientedLineGenerator.allLines {
            let v = line.variant
            let greenLeft = line.greenSign.x < line.redSign.x
            expectTrue(v.sideTraditionalChinese.contains(greenLeft ? "左" : "右"))
            expectTrue(v.sideEnglish.contains(greenLeft ? "left" : "right"))
            if !v.isHorizontal {
                let greenLow = line.greenSign.y > line.redSign.y
                expectTrue(v.sideTraditionalChinese.contains(greenLow ? "下" : "上"))
                expectTrue(v.sideEnglish.contains(greenLow ? "bottom" : "top"))
                expectTrue(v.wayTraditionalChinese.contains(greenLow ? "上" : "下"))
            }
            expectTrue(v.wayTraditionalChinese.contains(greenLeft ? "右" : "左"))
            expectTrue(OrientedLineCopy.wrongStart(v).traditionalChinese.contains(v.sideTraditionalChinese))
            expectTrue(OrientedLineCopy.reverse(v).traditionalChinese.contains(v.sideTraditionalChinese))
        }
        // The design's §7 lines.
        expectEqual(OrientedLineCopy.prompt([.right, .downLeft, .left]).traditionalChinese, "由綠色起點，跟住箭嘴畫去紅色終點！")
        expectEqual(OrientedLineCopy.prompt([.right, .downLeft, .left]).key, "lines.prompt.mixed")
        expectEqual(OrientedLineCopy.prompt([.upRight, .upRight, .upRight]).traditionalChinese, "由綠色起點，斜斜向右上畫去紅色終點！")
        expectEqual(OrientedLineCopy.prompt([.left, .left, .left]).traditionalChinese, "由綠色起點，向左畫去紅色終點！")
        expectEqual(OrientedLineCopy.start(.downLeft).traditionalChinese, "斜斜，向左下！")
        expectEqual(OrientedLineCopy.start(.left).traditionalChinese, "打橫，向左！")
        expectEqual(OrientedLineCopy.demo(.right).traditionalChinese, "由起點向右，去到終點。")
        expectEqual(OrientedLineCopy.wrongStart(.downLeft).traditionalChinese, "綠色起點喺右上，由嗰度開始啊！")
        expectEqual(OrientedLineCopy.wrongStart(.upRight).traditionalChinese, "綠色起點喺左下，由嗰度開始啊！")
        expectEqual(OrientedLineCopy.reverse(.left).traditionalChinese, "紅色係終點；由右邊綠色起點開始啊！")
        expectEqual(OrientedLineCopy.reverse(.right).traditionalChinese, "紅色係終點；由左邊綠色起點開始啊！")
        expectEqual(OrientedLineCopy.earlyFinish(.downLeft).traditionalChinese, "由架車度繼續斜斜向左下畫，去紅色終點！")
        expectEqual(OrientedLineCopy.pause(.left).traditionalChinese, "向左，畫去紅色終點！")
        expectEqual(OrientedLineCopy.cue(.left).traditionalChinese, "打橫向左")
        expectEqual(OrientedLineCopy.bubble(.upRight), "斜斜向右上、up to the right")
        expectEqual(OrientedLineCopy.lifted.traditionalChinese, "架車等緊你，由架車度繼續畫！")
        expectEqual(OrientedLineCopy.arrive.traditionalChinese, "到終點喇！")
        expectEqual(OrientedLineCopy.demoWatch.traditionalChinese, "睇住架車先！")
        expectEqual(OrientedLineCopy.demoTurn.traditionalChinese, "到你喇！")
        expectEqual(OrientedLineCopy.redemo.traditionalChinese, "再睇多次架車點行！")
        expectEqual([OrientedLineCopy.startSign, OrientedLineCopy.finishSign], ["起點", "終點"])
        expectEqual(OrientedLineCopy.badgeTitle, ActivityKind.traceOrientedLines.parentCardTitle)
        expectEqual(OrientedLineCopy.changedAdvisory.components(separatedBy: " / ").first, "改咗線款，建議試玩")
        expectEqual(OrientedLineDirectionSetting.both.badgeTraditionalChinese, "左右都有 · Both ways")
        expectEqual(OrientedLineShapeSetting.allCases.map(\.labelTraditionalChinese), ["橫線", "斜線", "橫斜都有"])
        expectEqual(OrientedLineDirectionSetting.allCases.map(\.labelTraditionalChinese), ["左→右", "右→左", "兩個方向都有"])
        print("  畫直線・四方 T6: \(traditional.count) Traditional lines (OpenCC fixture), \(english.count) ASCII English lines; 32 keyed lines name the actual green end")
    }
}
