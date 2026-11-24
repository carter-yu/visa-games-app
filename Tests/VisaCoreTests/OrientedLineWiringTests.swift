import Foundation
import VisaCore

/// 畫直線・四方 R3 (0.42.0 / 92; four-direction design §11.2 R3 Linux gates): the app wiring, pinned by source guards
/// because SwiftUI / AppKit are not built on this box (the 中文字 and 分類 precedent). T16 (the held finish, exactly once,
/// the 試玩 lane apart), T20 (the open round reads its dealt snapshot, never live settings), no copied mastery and no
/// shared 畫形狀設定 (C3, C4), the board's layer order, mirrored car but never mirrored words (T4b), and the card's own
/// parent panel. The new AppModel code is also type-checked on the box by a harness (session evidence).
final class OrientedLineWiringTests {
    private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The declaration that starts with `signature`, up to its matching brace.
    private func body(of signature: String, in text: String) -> String {
        guard let start = text.range(of: signature) else { return "" }
        var depth = 0
        var seenBrace = false
        var index = start.lowerBound
        while index < text.endIndex {
            let character = text[index]
            if character == "{" { depth += 1; seenBrace = true }
            if character == "}" {
                depth -= 1
                if seenBrace, depth == 0 { return String(text[start.lowerBound...index]) }
            }
            index = text.index(after: index)
        }
        return ""
    }

    private func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }

    private func ordered(_ first: String, _ second: String, in text: String) -> Bool {
        guard let a = text.range(of: first), let b = text.range(of: second) else { return false }
        return a.lowerBound < b.lowerBound
    }

    private func newCardExtension(_ model: String) -> String {
        let start = model.components(separatedBy: "// MARK: - 畫直線・四方 (four-direction design; 0.42.0 / 92)").dropFirst().first ?? ""
        return start.components(separatedBy: "// MARK: - 分類 · 邊個唔同類").first ?? ""
    }

    /// T16 (app part), M17, M18: the child's finish is held under parent controls and stamps once on Return; resets drop
    /// it; the 試玩 lane never holds and never writes 識咗; 畫直線 · 熱身's finish path is untouched (C6).
    func testHeldFinishAndPlaytestLane() throws {
        let model = try source("Sources/VisaGames/AppDelegate.swift")
        let finish = body(of: "private func finishOrientedLineRound(", in: model)
        let playtestPart = finish.components(separatedBy: "        guard taskRoundOpen, activeActivityKind == .traceOrientedLines").first ?? ""
        expectFalse(playtestPart.isEmpty || playtestPart == finish)
        expectFalse(playtestPart.contains("orientedLineFinishHold"), "a 試玩 never holds")
        expectTrue(playtestPart.contains("parentPlaytestLog.recording(.traceOrientedLines, on: Date())"), "its own 試玩 record")
        expectTrue(ordered("choiceDealSeed == token", "guard orientedLineFinishHold.finishesNow(token, mode: session.mode) else {",
                           in: finish))
        expectTrue(ordered("guard orientedLineFinishHold.finishesNow(token, mode: session.mode) else {",
                           "applyEntrySuccess(assisted: false)", in: finish), "held before anything stamps")
        let held = body(of: "private func finishHeldOrientedLineRound()", in: model)
        expectTrue(held.contains("orientedLineFinishHold.release(openRound: taskRoundOpen ? choiceDealSeed : nil,"))
        expectTrue(held.contains("finishOrientedLineRound(token: round, playtest: false)"))
        let back = body(of: "func returnToChild(", in: model)
        expectTrue(ordered("update { $0.leaveParent(now: Date()) }", "finishHeldOrientedLineRound()", in: back))
        expectEqual(count("finishHeldOrientedLineRound()", in: model), 2)
        expectTrue(body(of: "private func resetTaskRound()", in: model).contains("orientedLineFinishHold.drop()"))
        expectEqual(count("orientedLineFinishHold.", in: model), 3)
        for signature in ["func startPlaytest(kind: ActivityKind)", "private func discardPlaytestCover(reason: String)"] {
            let text = body(of: signature, in: model)
            expectFalse(text.isEmpty)
            expectFalse(text.contains("orientedLineFinishHold") || text.contains("orientedLineProgressStore"), signature)
        }
        // 識咗 is written in one place, after a line is done, through the lane rule (a 試玩 writes nothing).
        let commit = body(of: "func orientedLineCommit(", in: model)
        expectEqual(count("orientedLineProgressStore.save(", in: model), 1)
        expectTrue(commit.contains("lane: playtest ? .playtest : .child)"))
        expectTrue(ordered("if let learned = OrientedLineLearning.lineDone(", "orientedLineProgressStore.save(learned)", in: commit))
        // Exactly once: only a successor of the lane's board is taken, and the finish is scheduled once per round.
        expectTrue(commit.contains("guard next.isMonotonicSuccessor(of: current) else {"))
        expectTrue(commit.contains("guard next.isComplete, !current.isComplete else { return }"))
        expectEqual(count("self?.finishOrientedLineRound(token: token, playtest: playtest)", in: model), 1)
        // The original card's finish path is untouched (its body is also hashed by T17).
        let original = body(of: "private func finishShapeTraceRound(", in: model)
        expectFalse(original.isEmpty || original.contains("Hold") || original.contains("orientedLine"))
        print("  畫直線・四方 T16 (app): the child's finish held under parent controls, once on Return, dropped by a reset; 試玩 never holds or writes 識咗; 畫直線 · 熱身's path unchanged")
        checkCompletionPathContracts(model)
    }

    /// T20 (app part), M32, M34, C4: the open round reads its dealt question, never the live settings; this card never
    /// touches 畫形狀設定, 連一連's tolerance or another card's learning; its settings save to its own store and key.
    func testOpenRoundReadsItsSnapshotAndItsOwnStoresOnly() throws {
        let model = try source("Sources/VisaGames/AppDelegate.swift")
        let card = newCardExtension(model)
        expectTrue(card.count > 5_000)
        for signature in ["func orientedLineCommit(", "private func finishOrientedLineRound(", "func orientedLineHelpShown(",
                          "private func orientedLineStartLine(", "func speakOrientedLinePrompt(", "func orientedLineDemoAgain()",
                          "func orientedLineDemoTouch()", "private var orientedLineInputOpen:", "private func orientedLineSay("] {
            let text = body(of: signature, in: model)
            expectFalse(text.isEmpty, signature)
            expectFalse(text.contains("orientedLineSettings"), "\(signature) reads live settings")
        }
        let make = body(of: "private func makeOrientedLineBoard(", in: model)
        expectTrue(make.contains("OrientedLineGenerator.make(seed: seed, settings: orientedLineSettings,"))
        expectFalse(make.contains("shapeTrace") || make.contains("lineMatch"), "no 畫形狀設定, no 跟連一連")
        expectTrue(model.contains("orientedLineGuide = orientedLineBoard.map { OrientedLineGuideTally(question: $0.question) }"))
        expectTrue(model.contains(
            "playtestOrientedLineGuide = playtestOrientedLineBoard.map { OrientedLineGuideTally(question: $0.question) }"))
        expectTrue(body(of: "private func dealFacts(", in: model)
            .contains("PerfChoiceCatalog.facts(orientedLines: orientedLine?.question ?? OrientedLineGenerator.reference)"))
        let commit = body(of: "func orientedLineCommit(", in: model)
        expectTrue(commit.contains(
            "let fields = OrientedLineRecord.resultFields(board: next, guide: playtest ? playtestOrientedLineGuide : orientedLineGuide,"))
        expectTrue(commit.contains("let variant = next.lines[index].variant"), "識咗 of the dealt line's variant")
        for forbidden in ["shapeTraceSettings", "ShapeTraceSettingsStore", "lineMatchSettings", "tapCountGuideProgress",
                          "TapCountGuideProgressStore", ".traceLines"] {
            expectFalse(card.contains(forbidden), forbidden)
        }
        // C4: only its own stores fill its state (declaration, launch load, and after a line through the lane rule).
        expectEqual(count("orientedLineProgress = ", in: model), 3)
        expectTrue(model.contains("orientedLineProgress = OrientedLineGuideProgressStore().load()"))
        expectTrue(model.contains("orientedLineSettings = OrientedLineSettingsStore().load()"))
        expectEqual(count("orientedLineSettings = ", in: model), 3)
        // Settings: parent mode only, saved at once in its own store with its own config key; the advisory for 線形 / 方向.
        let save = body(of: "private func saveOrientedLineSettings(", in: model)
        expectTrue(save.contains("orientedLineSettingsStore.save(next)"))
        expectTrue(save.contains("perf.orientedLineSettingChanged(what: what, value: value)"))
        for (setter, advisory) in [("func setOrientedLineShape(", true), ("func setOrientedLineDirection(", true),
                                   ("func setOrientedLineHelp(", false), ("func setOrientedLineTolerance(", false)] {
            let text = body(of: setter, in: model)
            expectTrue(text.contains("guard session.mode == .parent,"), setter)
            expectTrue(text.contains("lineSetChanged: \(advisory))"), setter)
        }
        let recorder = try source("Sources/VisaGames/PerformanceRecorder.swift")
        let record = body(of: "func orientedLineSettingChanged(", in: recorder)
        expectTrue(record.contains("\"what\": .string(OrientedLineWeekly.configKey(what))"))
        expectTrue(record.contains("ActivityKind.traceOrientedLines.rawValue"))
        expectTrue(body(of: "func shapeTraceSettingChanged(", in: recorder).contains("\"what\": .string(\"shapeTrace_\\(what)\")"))
        print("  畫直線・四方 T20 (app): live settings read only at the deal and by the parent setters; guidance and facts from the dealt question; no 畫形狀設定, 跟連一連 or other learning")
    }

    /// Astra code review minors 2 and 5: every line said for this card goes through `orientedLineSay`, which sets the
    /// caption before it speaks (the round's line itself is the header); the board shows every caption line and hides it
    /// once F moves on its own current board; a help line is chosen from the view's current board, passed with the help.
    func testSaidIsShownAndHelpUsesTheLiveBoard() throws {
        let model = try source("Sources/VisaGames/AppDelegate.swift")
        let card = newCardExtension(model)
        let say = body(of: "private func orientedLineSay(", in: model)
        expectTrue(ordered("orientedLineCaption = OrientedLineCaption(lines, on: board)",
                           "guideVoice.speakQueued(line, english: english, interrupt: interrupt && index == 0)", in: say))
        expectEqual(count("guideVoice.", in: card), 3)
        expectEqual(count("guideVoice.speak(board.question.prompt)", in: card), 2)
        expectEqual(count("guideVoice.speakQueued(", in: card), 1)
        expectEqual(count("OrientedLineCopy.lineStart(", in: card), 4)
        expectFalse(card.contains("frontier + 20") || card.contains("orientedLineNotice") || card.contains("orientedLineBubble"))
        let commit = body(of: "func orientedLineCommit(", in: model)
        expectTrue(commit.contains("on: next, interrupt: true)"))
        expectTrue(commit.contains("orientedLineSay(said, on: next, interrupt: true)"))
        let help = body(of: "func orientedLineHelpShown(", in: model)
        expectTrue(help.contains("func orientedLineHelpShown(_ help: OrientedLineHelp, on snapshot: OrientedLineBoard)"))
        expectTrue(help.contains("snapshot == current || snapshot.isMonotonicSuccessor(of: current)"))
        expectTrue(help.contains("OrientedLineCopy.helpLine(help, board: snapshot)"))
        expectTrue(help.contains("orientedLineSay(said, on: snapshot, interrupt: true)"))
        expectFalse(help.contains("board.frontier") || help.contains("board.penIsDown"), "the line is chosen in VisaCore, from the snapshot")
        // Said once a line per lane (design §6.4, recheck m2): a 試玩 keeps its own record and never clears the child's.
        expectTrue(help.contains("orientedLineSpoken.firstTime(prompt.key, lane: playtest ? .playtest : .child)"))
        expectTrue(body(of: "private func orientedLineStartLine(", in: model)
            .contains("orientedLineSpoken.newLine(playtest ? .playtest : .child)"))
        expectTrue(body(of: "private func resetOrientedLineTransient(lane: OrientedLineLane)", in: model)
            .contains("orientedLineSpoken.newLine(lane)"))
        expectTrue(body(of: "func startPlaytest(kind: ActivityKind)", in: model).contains("resetOrientedLineTransient(lane: .playtest)"))
        expectEqual(count("resetOrientedLineTransient(lane: .child)", in: model), 1)
        expectEqual(count("resetOrientedLineTransient(lane: .playtest)", in: model), 1)
        expectTrue(model.contains("private var orientedLineSpoken = OrientedLineSpokenLines()"))
        expectEqual(count("orientedLineSpoken", in: model), 4)
        let view = try source("Sources/VisaGames/OrientedLineBoardView.swift")
        expectTrue(view.contains("if key != nil { view.onHelp(help, board) }"))
        let rows = body(of: "private var captionRows:", in: view)
        expectTrue(rows.contains("if let caption = view.caption, caption.isShowing(on: board) {"))
        expectTrue(rows.contains("return caption.lines.map { ($0.traditionalChinese, $0.english) }"))
        print("  畫直線・四方 R3 parity: every line said goes through orientedLineSay (caption first), shown until F moves; help lines from the view's live board")
    }

    /// The board view, the route and the parent panel: layer order, the clip at G, the swallowed demo touch, faded ink,
    /// a mirrored car but upright words (T4b, M31), and the card's own panel with no 原本.
    func testBoardViewRouteAndParentPanel() throws {
        let host = try source("Sources/VisaGames/CanvasActivityHost.swift")
        expectTrue(host.contains("case .traceOrientedLines:\n                orientedLines"))
        expectTrue(host.contains("case .traceLines, .traceShapesDotted, .traceShapesArrows, .traceShapesFree:\n                shapeTrace"))
        let route = body(of: "private var orientedLines: some View {", in: host)
        expectTrue(route.contains("OrientedLineBoardView(") && route.contains("model.orientedLineCommit(next)"))
        expectTrue(route.contains("caption: model.orientedLineCaption,"))
        expectTrue(route.contains("onHelp: { help, board in model.orientedLineHelpShown(help, on: board) }"))
        expectFalse(route.contains("Settings"))
        let view = try source("Sources/VisaGames/OrientedLineBoardView.swift")
        expectFalse(view.contains("TextField") || view.contains("Settings"))
        expectTrue(view.contains("if let local, local.isMonotonicSuccessor(of: view.board) { return local }"))
        expectTrue(view.contains("OrientedLineCoach.help(plan: run.plan, run: run, board: board, now: view.now)"))
        let changed = body(of: "private func dragChanged(", in: view)
        expectTrue(ordered("if run?.demoPending(now: clock) == true {", "next.penDown(at:", in: changed))
        expectTrue(changed.contains("swallowing = true\n                view.onDemoTouch()\n                return"))
        let layers = body(of: "private var lineLayers: some View {", in: view)
        for (first, second) in [("OrientedLineDrawing.road(", "OrientedLineDrawing.staticGuidance("),
                                ("OrientedLineDrawing.staticGuidance(", "OrientedLineDrawing.bars("),
                                ("OrientedLineDrawing.bars(", "OrientedLineDrawing.signs("),
                                ("OrientedLineDrawing.signs(", "OrientedLineDrawing.ink("),
                                ("guidanceLayer(line, help: help)", "OrientedLineDrawing.car(")] {
            expectTrue(ordered(first, second, in: layers), "\(first) before \(second)")
        }
        let guidance = body(of: "private func guidanceLayer(", in: view)
        expectTrue(ordered("OrientedLineDrawing.clipToGuidance(line, in: &g)", "OrientedLineDrawing.demo(", in: guidance))
        expectTrue(ordered("OrientedLineDrawing.clipToGuidance(line, in: &g)", "OrientedLineDrawing.help(", in: guidance))
        expectTrue(guidance.contains(".overlay(alignment: .topLeading) {\n            stageCanvas { g in OrientedLineDrawing.bars(line, in: &g) }"),
                   "the bars stay above the timed guidance")
        // Recheck m3: the demo is drawn from the coach's frame (its fades after the drive, design §6.1), and a ghost to
        // the finish under Reduce Motion as the coach's lit stretch (design §6.2).
        expectTrue(guidance.contains("OrientedLineCoach.demoFrame(line: line, run: run, now: clock, reduceMotion: reduce)"))
        expectTrue(guidance.contains("lit: OrientedLineCoach.litStretch(help, line: line, now: clock, reduceMotion: reduce),"))
        expectFalse(view.contains("demoPending(now: view.now)"), "the demo is not cut off when its drive ends")
        let demo = body(of: "static func demo(", in: view)
        expectTrue(demo.contains("glow.opacity(frame.routeOpacity)") && demo.contains("if let ghost = frame.ghost"))
        let helpDrawing = body(of: "static func help(", in: view)
        expectTrue((helpDrawing.components(separatedBy: "case .ghostToEnd:").last ?? "").contains("if let lit {"))
        expectTrue(ordered("clipToGuidance(line, in: &layer)", "layer.stroke(", in: body(of: "static func staticGuidance(", in: view)))
        let clip = body(of: "static func clipToGuidance(", in: view)
        expectTrue(clip.contains("let G = line.guidanceLimit") && clip.contains("g.clip(to: half)"))
        expectTrue(view.contains("g.stroke(road, with: .color(Self.glow), style: StrokeStyle(lineWidth: 54, lineCap: .butt))"))
        // T4b / M31: the sign words and the flag are drawn upright on an unturned context; only the taxi turns or mirrors.
        let signs = body(of: "static func signs(", in: view)
        expectFalse(signs.contains("rotate") || signs.contains("scaleBy"))
        expectTrue(signs.contains("g.draw(Text(OrientedLineCopy.startSign)") && signs.contains("g.draw(Text(OrientedLineCopy.finishSign)"))
        expectTrue(signs.contains("y: green.y - 15 + line.unit.y * 18"), "the start arrow sits above the word, along u")
        // The arrow's tip is on the red side (+u) and its tail on the green side, so it never points back (M2b).
        expectTrue(signs.contains("let tip = CGPoint(x: green.x + line.unit.x * 18, y: green.y - 15 + line.unit.y * 18)"))
        expectTrue(signs.contains("let tail = CGPoint(x: green.x - line.unit.x * 18, y: green.y - 15 - line.unit.y * 18)"))
        expectTrue(ordered("arrow.move(to: tail)", "arrow.addLine(to: tip)", in: signs))
        // Every chevron is a ">" along +u: its point at s + half, its arms at s − half (M2c).
        let chevron = body(of: "static func chevron(", in: view)
        for part in ["path.move(to: at(line, s - half, -16 * k))", "path.addLine(to: at(line, s + half, 0))",
                     "path.addLine(to: at(line, s - half, 16 * k))"] {
            expectTrue(chevron.contains(part), part)
        }
        let taxi = body(of: "static func taxi(", in: view)
        expectTrue(taxi.contains("let mirrored = !line.variant.isRightward"))
        expectTrue(taxi.contains("layer.scaleBy(x: mirrored ? -carScale : carScale, y: carScale)"))
        expectEqual(count("rotate(by:", in: view), 1)
        expectEqual(count("scaleBy(x: mirrored", in: view), 1)
        // Ink edges take the shared rule (the edge into a join stays faded); dots keep their own sample's flag.
        let ink = body(of: "static func ink(", in: view)
        expectTrue(ink.contains("for edge in OrientedLineInk.edges(strokes) {"))
        expectTrue(ink.contains("navy.opacity(edge.counted ? 1 : 0.4)") && ink.contains("if edge.counted {"))
        expectFalse(ink.contains(".counted ? 1 : 0.4)), style") && ink.contains("b.counted"))
        // The 上方進度列 under the header (DECISIONS Q6); the caption in the tray; the tray's old status rect is gone.
        expectTrue(body(of: "private var progressRow: some View {", in: view).contains("let rect = OrientedLineLayout.progressRow"))
        expectTrue(body(of: "private var captionView: some View {", in: view).contains("let rect = OrientedLineLayout.caption"))
        expectFalse(view.contains("OrientedLineLayout.status"))
        expectTrue(view.contains("            progressRow\n            captionView\n            header"))
        // The card's own panel, after the shared 畫形狀設定 panel; no 原本 and no 跟連一連.
        let settings = try source("Sources/VisaGames/ParentSettingsView.swift")
        expectTrue(ordered("ParentShapeTraceSettingsView(", "ParentOrientedLineSettingsView(", in: settings))
        expectTrue(settings.contains("playtestedOn: model.parentPlaytestLog.playtestedOn(.traceOrientedLines),"))
        expectTrue(settings.contains("static let versionLabel = \"Visa Games v0.42.0\""))
        let panel = try source("Sources/VisaGames/ParentOrientedLineSettingsView.swift")
        expectFalse(panel.contains("TextField") || panel.contains("原本") || panel.contains("classic") || panel.contains("toleranceFollow"))
        for row in ["OrientedLineShapeSetting.allCases", "OrientedLineDirectionSetting.allCases", "TapCountGuidanceLevel.allCases",
                    "LineMatchTolerance.allCases"] {
            expectTrue(panel.contains("ForEach(\(row), id: \\.self)"), row)
        }
        expectTrue(panel.contains("OrientedLineCopy.changedAdvisory"))
        let gameCard = try source("Sources/VisaGames/ParentGameCard.swift")
        expectTrue(ordered("} else if kind == .traceOrientedLines {", "} else if kind.isShapeTraceFamily {", in: gameCard))
        // No Simplified character in the new app files.
        let fixture = URL(fileURLWithPath: "Tests/VisaCoreTests/Fixtures/traditional-check/simplified-only.txt")
        let simplified = Set(try String(contentsOf: fixture, encoding: .utf8).split(separator: "\n")
            .filter { !$0.hasPrefix("#") }.joined().filter { !$0.isWhitespace })
        for (name, text) in [("OrientedLineBoardView", view), ("ParentOrientedLineSettingsView", panel),
                             ("AppModel 畫直線・四方", newCardExtension(try source("Sources/VisaGames/AppDelegate.swift")))] {
            let found = text.filter { simplified.contains($0) }
            expectTrue(found.isEmpty, "\(name): Simplified \(found)")
        }
        print("  畫直線・四方 R3 view: road → guidance clipped at G → bars → signs → ink → car; demo touch swallowed; upright words, mirrored car; own panel without 原本")
    }

    /// A+ (architecture review 2026-11-23, DECISION-RFC-A-PLUS; run from T16): four named source contracts of this card's
    /// completion path. Each is read from the function it is about, never from a whole-file occurrence (other cards'
    /// commits and finishes, e.g. `shapeTraceCommit` and `finishShapeTraceRound`, hold several of the same lines). Each
    /// must hold on the real text and reject every in-memory edited copy below. Source text only, not runtime: no
    /// AppModel runs and no time passes, so a failure is contract drift to inspect, not necessarily a product bug.
    private func checkCompletionPathContracts(_ model: String) {
        let commit = body(of: "func orientedLineCommit(", in: model)
        let finish = body(of: "private func finishOrientedLineRound(", in: model)
        let back = body(of: "func returnToChild(", in: model)
        let groups: [(String, [(String, Bool)])] = [
            ("A1_CAPTURE", captureContract(commit)), ("A2_DELAY", delayContract(commit)),
            ("A3_ELIGIBILITY", eligibilityContract(finish)),
            ("A4_HOLD_ORDER", holdOrderContract(finish) + returnReleaseContract(back))]
        for (group, assertions) in groups {
            for (name, holds) in assertions { expectTrue(holds, "\(group): \(name)") }
        }
        // Negative controls: (name, [(anchor, replacement)]) applied to a copy of the function's text.
        let token = "let token = playtest ? playtestChoiceDealSeed : choiceDealSeed"
        let callback = "self?.finishOrientedLineRound(token: token, playtest: playtest)"
        let transition = "guard next.isComplete, !current.isComplete else { return }"
        let capture: [(String, [(String, String)])] = [
            ("token from the child's seed in both lanes", [(token, "let token = choiceDealSeed")]),
            ("token seeds swapped", [(token, "let token = playtest ? choiceDealSeed : playtestChoiceDealSeed")]),
            ("token from the live lane rule",
             [(token, "let token = orientedLineUsesPlaytest ? playtestChoiceDealSeed : choiceDealSeed")]),
            ("callback lane fixed to the child", [(callback, "self?.finishOrientedLineRound(token: token, playtest: false)")]),
            ("callback lane read when it fires",
             [(callback, "self?.finishOrientedLineRound(token: token, playtest: self?.orientedLineUsesPlaytest == true)")]),
            ("callback token read when it fires",
             [(callback, "self?.finishOrientedLineRound(token: self?.choiceDealSeed ?? token, playtest: playtest)")])]
        let delay: [(String, [(String, String)])] = [
            ("2.5 s", [(".now() + 2.4", ".now() + 2.5")]),
            ("no delay", [("DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {", "DispatchQueue.main.async {")]),
            ("off the main queue", [("DispatchQueue.main.", "DispatchQueue.global().")]),
            ("strong self", [("{ [weak self] in", "{"), ("self?.finishOrientedLineRound(", "self.finishOrientedLineRound(")]),
            ("any complete board schedules", [(transition, "guard next.isComplete else { return }")]),
            ("scheduled before the transition guard",
             [(transition + "\n", ""), (callback + "\n        }\n", callback + "\n        }\n        " + transition + "\n")]),
            ("token taken before the transition guard", [(token + "\n", ""), (transition, token + "\n        " + transition)]),
            ("transition guard only in the playtest lane", [(transition, "if playtest {\n            " + transition + "\n        }")]),
            ("transition guard only in the child lane", [(transition, "if !playtest {\n            " + transition + "\n        }")])]
        let eligibility: [(String, [(String, String)])] = [
            ("playtest without !playtestCompleted", [("!playtestCompleted, ", "")]),
            ("playtest board present, not complete",
             [("playtestOrientedLineBoard?.isComplete == true", "playtestOrientedLineBoard != nil")]),
            ("playtest without isParentPlaytest", [("guard isParentPlaytest, ", "guard ")]),
            ("playtest without its kind", [("playtestKind == .traceOrientedLines, ", "")]),
            ("playtest without its deal", [("playtestChoiceDealSeed == token,", "")]),
            ("child without !activityJustCompleted", [(" !activityJustCompleted,", "")]),
            ("child board present, not complete",
             [("orientedLineBoard?.isComplete == true else { return }", "orientedLineBoard != nil else { return }")]),
            ("child without taskRoundOpen", [("guard taskRoundOpen, ", "guard ")]),
            ("child without its kind", [("activeActivityKind == .traceOrientedLines, ", "")]),
            ("child without its deal", [(" choiceDealSeed == token,", "")]),
            ("child's !activityJustCompleted only in the playtest guard",
             [(" !activityJustCompleted,", ""), ("guard isParentPlaytest, ", "guard isParentPlaytest, !activityJustCompleted, ")]),
            ("playtest's !playtestCompleted only in the child guard",
             [("!playtestCompleted, ", ""), ("guard taskRoundOpen, ", "guard taskRoundOpen, !playtestCompleted, ")])]
        let child = finishLanes(finish).child
        let hold = body(of: "guard orientedLineFinishHold.finishesNow(token, mode: session.mode) else {", in: child)
        let fuel = body(of: "guard pendingAwardMinutes > 0 else {", in: child)
        let validation = child.range(of: " else { return }")
            .map { child[..<$0.upperBound].trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        let order: [(String, [(String, String)])] = [
            ("fuel checked before the hold", [(fuel, ""), (hold, fuel + "\n        " + hold)]),
            ("depot before the hold", [(hold, "if pendingAwardMinutes == 0 { returnToDepotOutOfFuel(); return }\n        " + hold)]),
            ("stamp before the hold", [(hold, "applyEntrySuccess(assisted: false)\n        " + hold)]),
            ("completed flag before the hold", [(hold, "activityJustCompleted = true\n        " + hold)]),
            ("stamp in the held branch",
             [("mode: session.mode) else {\n", "mode: session.mode) else {\n            applyEntrySuccess(assisted: false)\n")]),
            ("validation after the hold", [(validation, ""), (hold, hold + "\n        " + validation)])]
        let release: [(String, [(String, String)])] = [
            ("held release before leaveParent",
             [("finishHeldOrientedLineRound()\n", ""),
              ("update { $0.leaveParent(now: Date()) }", "finishHeldOrientedLineRound()\n        update { $0.leaveParent(now: Date()) }")]),
            ("an extra held release before leaveParent",
             [("discardPlaytestCover(reason: \"leaveParent\")",
               "finishHeldOrientedLineRound()\n        discardPlaytestCover(reason: \"leaveParent\")")])]
        for (name, edits) in capture { expectRejected("A1_CAPTURE: \(name)", commit, edits, by: captureContract) }
        for (name, edits) in delay { expectRejected("A2_DELAY: \(name)", commit, edits, by: delayContract) }
        for (name, edits) in eligibility { expectRejected("A3_ELIGIBILITY: \(name)", finish, edits, by: eligibilityContract) }
        for (name, edits) in order { expectRejected("A4_HOLD_ORDER: \(name)", finish, edits, by: holdOrderContract) }
        for (name, edits) in release { expectRejected("A4_HOLD_ORDER: \(name)", back, edits, by: returnReleaseContract) }
        let named = groups.map { "\($0.1.count)" }.joined(separator: " / ")
        let rejected = [capture.count, delay.count, eligibility.count, order.count + release.count].map { "\($0)" }
            .joined(separator: " / ")
        print("  畫直線・四方 A+ source contracts (source text, not runtime): A1_CAPTURE / A2_DELAY / A3_ELIGIBILITY / A4_HOLD_ORDER — \(named) named assertions hold; \(rejected) in-memory negative controls rejected")
    }

    /// A negative control on an in-memory copy (nothing is written): each anchor must occur exactly once before it is
    /// edited, so a control never passes as a no-op, and the same contract must then fail on the edited copy.
    private func expectRejected(_ name: String, _ text: String, _ edits: [(String, String)],
                                by contract: (String) -> [(String, Bool)]) {
        var copy = text
        for (anchor, replacement) in edits {
            expectEqual(anchor.isEmpty ? 0 : count(anchor, in: copy), 1, "\(name): its anchor must occur once")
            copy = copy.replacingOccurrences(of: anchor, with: replacement)
        }
        expectFalse(copy == text || contract(copy).allSatisfy { $0.1 }, "\(name): the contract accepts the edit")
    }

    /// A1_CAPTURE, in `orientedLineCommit`: the lane Bool is taken once from the lane rule, the token is chosen from that
    /// Bool, and the commit's one finish call (the delayed callback) gets that token and that lane.
    private func captureContract(_ commit: String) -> [(String, Bool)] {
        let lane = "let playtest = orientedLineUsesPlaytest\n"
        let token = "let token = playtest ? playtestChoiceDealSeed : choiceDealSeed\n"
        let callback = "self?.finishOrientedLineRound(token: token, playtest: playtest)\n"
        return [("the lane Bool taken once, from the lane rule", count("let playtest = ", in: commit) == 1 && commit.contains(lane)),
                ("the token chosen once, from that Bool", count("let token = ", in: commit) == 1 && commit.contains(token)),
                ("the one finish call gets that token and that lane",
                 count("finishOrientedLineRound(", in: commit) == 1 && commit.contains(callback)),
                ("lane, then token, then callback", ordered(lane, token, in: commit) && ordered(token, callback, in: commit))]
    }

    /// A2_DELAY, in `orientedLineCommit`: one main-queue `asyncAfter(deadline: .now() + 2.4)` with `[weak self]` that calls
    /// the finish through the weak reference, after the newly-complete transition guard and the token. The guard, the
    /// token and the schedule end the commit line after line at its top level, so no branch can keep the guard to one
    /// lane (Astra implementation review, major). The source only, not when the callback actually runs.
    private func delayContract(_ commit: String) -> [(String, Bool)] {
        let transition = "guard next.isComplete, !current.isComplete else { return }\n"
        let token = "let token = playtest ? playtestChoiceDealSeed : choiceDealSeed\n"
        let schedule = "DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in\n"
        let path = "\n        " + transition + "        " + token + "        " + schedule
            + "            self?.finishOrientedLineRound(token: token, playtest: playtest)\n        }\n    }"
        return [("one schedule: main queue, now + 2.4, weak self", count("DispatchQueue.", in: commit) == 1 && commit.contains(schedule)),
                ("the finish called inside it, through the weak self",
                 body(of: schedule, in: commit).contains("self?.finishOrientedLineRound(")),
                ("transition guard, then token, then schedule",
                 ordered(transition, token, in: commit) && ordered(token, schedule, in: commit)),
                ("guard, token and schedule unbroken at the top level, ending the commit", commit.hasSuffix(path))]
    }

    /// `finishOrientedLineRound`'s two lanes: its `if playtest { … }` block, and the child's code after it.
    private func finishLanes(_ finish: String) -> (playtest: String, child: String) {
        let playtest = body(of: "if playtest {", in: finish)
        guard !playtest.isEmpty, let end = finish.range(of: playtest)?.upperBound else { return ("", "") }
        return (playtest, String(finish[end...]))
    }

    /// The conditions of the `guard … else { return }` that opens `branch` right after `opening`; nil when anything else
    /// comes first.
    private func openingGuard(of branch: String, after opening: String) -> [String]? {
        guard branch.hasPrefix(opening) else { return nil }
        let rest = branch.dropFirst(opening.count).drop(while: \.isWhitespace)
        guard rest.hasPrefix("guard ") else { return nil }
        let conditions = rest.dropFirst(6)
        guard let end = conditions.range(of: " else { return }") else { return nil }
        return conditions[..<end.lowerBound].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// A3_ELIGIBILITY, in `finishOrientedLineRound`: each lane's branch opens with its own guard, and that guard (not the
    /// other branch, not another function) checks the lane's mode / kind / deal / open state, its not-completed flag and
    /// its complete board. The child's mode is checked by the hold (A4).
    private func eligibilityContract(_ finish: String) -> [(String, Bool)] {
        let lanes = finishLanes(finish)
        let expected: [(String, [String]?, [String])] = [
            ("playtest", openingGuard(of: lanes.playtest, after: "if playtest {"),
             ["isParentPlaytest", "playtestKind == .traceOrientedLines", "playtestChoiceDealSeed == token", "!playtestCompleted",
              "playtestOrientedLineBoard?.isComplete == true"]),
            ("child", openingGuard(of: lanes.child, after: ""),
             ["taskRoundOpen", "activeActivityKind == .traceOrientedLines", "choiceDealSeed == token", "!activityJustCompleted",
              "orientedLineBoard?.isComplete == true"])]
        var result: [(String, Bool)] = []
        for (lane, conditions, clauses) in expected {
            result.append(("the \(lane) branch opens with its guard", conditions != nil))
            for clause in clauses { result.append(("the \(lane) guard checks \(clause)", conditions?.contains(clause) == true)) }
        }
        return result
    }

    /// A4_HOLD_ORDER, in the child branch of `finishOrientedLineRound`: its guard, then the hold, nothing between; the
    /// fuel check, the depot and every completion effect only after the hold (none before it, none in the held branch).
    private func holdOrderContract(_ finish: String) -> [(String, Bool)] {
        let child = finishLanes(finish).child
        let hold = body(of: "guard orientedLineFinishHold.finishesNow(token, mode: session.mode) else {", in: child)
        let parts = hold.isEmpty ? [child] : child.components(separatedBy: hold)
        let before = parts[0], after = parts.count == 2 ? parts[1] : ""
        let between = before.range(of: " else { return }").map { String(before[$0.upperBound...]) } ?? "missing"
        let commentsOnly = between.split(separator: "\n").allSatisfy {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return line.isEmpty || line.hasPrefix("//")
        }
        var result: [(String, Bool)] = [("the child branch holds once", parts.count == 2),
                                        ("its guard, then the hold, nothing between",
                                         openingGuard(of: before, after: "") != nil && commentsOnly)]
        for effect in ["pendingAwardMinutes", "returnToDepotOutOfFuel(", "lastCorrectChoiceID", "lastIncorrectChoiceID",
                       "activityJustCompleted = true", "applyEntrySuccess("] {
            result.append(("\(effect) only after the hold",
                           after.contains(effect) && !before.contains(effect) && !hold.contains(effect)))
        }
        return result
    }

    /// A4_HOLD_ORDER, in `returnToChild`: parent controls are left once, then the held finish is released once.
    private func returnReleaseContract(_ back: String) -> [(String, Bool)] {
        let parts = back.components(separatedBy: "update { $0.leaveParent(now: Date()) }")
        let before = parts[0], after = parts.count == 2 ? parts[1] : ""
        let early = ["finishHeldOrientedLineRound(", "orientedLineFinishHold.", "finishOrientedLineRound("]
        return [("Return leaves parent controls once", parts.count == 2),
                ("nothing released or finished before that", !early.contains { before.contains($0) }),
                ("the held finish released once, after it", count("finishHeldOrientedLineRound()", in: after) == 1)]
    }
}
