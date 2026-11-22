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
}
