import Foundation
import VisaCore

final class LetterPickerTests {
    private let all = Array("abcdefghijklmnopqrstuvwxyz").map(String.init)

    func testSaveFeedbackCoversEveryTypedFailure() {
        let validation: [LetterSelectionSettings.ValidationError] = [
            .emptyFocus, .tooMany, .invalidLetter, .unavailableFocus, .noWriteTargets,
            .insufficientBoardLetters, .invalidReview, .invalidOrder, .invalidSchema
        ]
        for error in validation {
            expectFalse(LetterPickerSaveCheck.reason(for: error).isEmpty)
        }
        expectEqual(Set(validation.map { LetterPickerSaveCheck.reason(for: $0) }).count, validation.count)
        let storage: [LetterSelectionSettingsStore.StoreError] = [.notParent, .corruptStored, .writeFailed]
        for error in storage {
            expectFalse(LetterPickerSaveCheck.reason(for: error).isEmpty)
        }
        expectEqual(Set(storage.map { LetterPickerSaveCheck.reason(for: $0) }).count, storage.count)
    }

    func testDraftSaveCheckShowsReasonBeforeSave() throws {
        let bank = try LetterWordBank.load(url: URL(fileURLWithPath: "Resources/LetterTap/starter-bank.json"))
        let ready = LetterAvailability.resolve(bank: bank, decks: .init())
        let valid = LetterSelectionSettings.defaults
        func check(_ value: LetterSelectionSettings, load: LetterSelectionLoad = .fresh,
                   repair: Bool = false, available: Bool = true) -> LetterPickerSaveCheck {
            LetterPickerSaveCheck.evaluate(value, availability: ready, writingAssigned: true,
                allowedReview: [], load: load, repairCorruptV2: repair, bankAvailable: available)
        }
        expectTrue(check(valid).canSave)
        expectFalse(check(valid, load: .corruptV2).canSave)
        expectTrue(check(valid, load: .corruptV2, repair: true).canSave)
        expectFalse(check(valid, available: false).canSave)
        var empty = valid
        empty.focusLetters = []
        expectEqual(check(empty).reason, LetterPickerSaveCheck.reason(for: .emptyFocus))
        var noWrite = valid
        noWrite.focusLetters = ["a"]
        var findOnly = ready
        findOnly["a"] = LetterCapability(canDisplay: true, canFind: true, canWrite: false)
        let blocked = LetterPickerSaveCheck.evaluate(noWrite, availability: findOnly, writingAssigned: true,
            allowedReview: [], load: .fresh, repairCorruptV2: false)
        expectEqual(blocked.reason, LetterPickerSaveCheck.reason(for: .noWriteTargets))
    }

    func testDraftReplaceReviewAndDiscard() {
        let saved = LetterSelectionSettings(focusLetters: ["b", "f", "h"],
            focusOrder: ["b", "f", "h"], reviewEvery: 4, reviewLetters: ["a", "c"])
        var draft = LetterPickerDraft(saved: saved)
        draft.toggleFocus("a")
        expectEqual(draft.value.reviewLetters, ["c"])
        draft.toggleFocus("a")
        expectEqual(draft.value.reviewLetters, ["c"])
        draft.replaceFocus(["f", "g", "h"], source: "fghij")
        expectEqual(draft.value.focusLetters, ["f", "g", "h"])
        expectEqual(draft.value.source, "fghij")
        draft.replaceFocus(["s", "a", "t", "i", "p", "n"], source: "school.jolly.1")
        expectEqual(draft.value.focusOrder, ["s", "a", "t", "i", "p", "n"])
        draft.toggleFocus("b")
        expectEqual(draft.value.focusOrder, ["a", "b", "i", "n", "p", "s", "t"])
        expectEqual(draft.value.source, "custom")
        draft.cancel()
        expectEqual(draft.value, saved)
        draft.toggleFocus("b")
        draft.revert()
        expectEqual(draft.value, saved)
    }

    func testWritingAssignmentNeedsWriteReadyFocusAndLastGameStillProtected() throws {
        let bank = try LetterWordBank.load(url: URL(fileURLWithPath: "Resources/LetterTap/starter-bank.json"))
        var ready = LetterAvailability.resolve(bank: bank, decks: .init())
        ready["a"] = LetterCapability(canDisplay: true, canFind: true, canWrite: false)
        let onlyFind = LetterSelectionSettings(focusLetters: ["a"], focusOrder: ["a"])
        expectThrowsError(try onlyFind.validated(availability: ready, writingAssigned: true))
        expectEqual(try onlyFind.validated(availability: ready, writingAssigned: false).focusLetters, ["a"])
        let star = ChildDifficulty.easy
        var stars = Dictionary(uniqueKeysWithValues: ActivityCatalog.playableKinds.map { ($0, Set<ChildDifficulty>()) })
        stars[.tapLetterAll] = [star]
        let assignment = MissionGameAssignment(enabledStars: stars)
        expectEqual(assignment.toggling(.tapLetterAll, star: star), .rejectedLastStar)
    }

    func testHistoricalLetterScopeCanonicalisation() {
        expectEqual(WeeklySignature.letterSet(["h", "b", "f", "b"]), "b f h")
        expectEqual(WeeklySignature.letterSet(["b", "f", "h"]), "b f h")
        expectEqual(WeeklySignature.guardValue(.string("on")), "on")
        expectEqual(WeeklySignature.guardValue(.bool(true)), "on")
        expectEqual(WeeklyComparison.kinds(forConfig: "tapLetter_focus_letters", kind: nil),
                    [ActivityKind.tapLetterAll.rawValue, ActivityKind.tapLetterWrite.rawValue])
    }

    func testWeeklySelectedScopeAndAskedTargetsStayHistorical() {
        let date = Date(timeIntervalSince1970: 100 * 86_400)
        let window = WeeklyWindow(containing: date)
        func deal(_ round: String, _ target: String, _ focus: PerfValue, _ actor: PerfActor = .child) -> PerfEvent {
            PerfEvent(type: .gameDealt, timestamp: date, tz: "+08:00", mono: 1,
                launch: "L\(round)", seq: 1, app: "0.37.0", actor: actor, mode: "lock", session: "s\(round)",
                fields: ["round": .string(round), "kind": .string(ActivityKind.tapLetterAll.rawValue),
                         "target": .string(target), "this_week": focus, "stars": .int(1)])
        }
        func result(_ round: String) -> PerfEvent {
            PerfEvent(type: .roundResult, timestamp: date.addingTimeInterval(30), tz: "+08:00", mono: 2,
                launch: "L\(round)", seq: 2, app: "0.37.0", actor: .child, mode: "lock", session: "s\(round)",
                fields: ["round": .string(round), "kind": .string(ActivityKind.tapLetterAll.rawValue),
                         "outcome": .string("solved"), "answers": .int(1), "first_try": .bool(true),
                         "misses": .int(0), "hint_used": .bool(false), "assisted": .bool(false),
                         "total_ms": .int(30_000), "active_ms": .int(4_000), "earned_min": .int(5)])
        }
        let events = [deal("a", "f", .strings(["h", "b", "f"])), result("a"),
                      deal("b", "a", .strings(["f", "b", "h"])), result("b"),
                      deal("parent", "z", .strings(["z"]), .parentPlaytest)]
        let report = WeeklyReportTextBuilder.build(events: events, rollup: PerfRollup(), window: window)
        expectEqual(report.letterFocusScopes, ["b f h"])
        expectEqual(report.letterTargets, ["a", "f"])
        let html = WeeklyReportHTML.render(report, options: WeeklyReportHTMLOptions(generatedAt: date))
        expectTrue(html.contains("題目記錄嘅主練字母"))
        expectTrue(html.contains("今週實際練過"))
    }

    func testFirstSavedScopeWithoutDealIsSettingOnly() {
        let date = Date(timeIntervalSince1970: 100 * 86_400)
        let event = PerfEvent(type: .configChange, timestamp: date, tz: "+08:00", mono: 1,
            launch: "Lsettings", seq: 1, app: "0.37.0", actor: .parent, mode: "parent", session: "parent",
            fields: ["what": .string("tapLetter_focus_letters"), "kind": .string(ActivityKind.tapLetterAll.rawValue),
                     "value": .string("b f h"), "selection_revision": .int(1)])
        let report = WeeklyReportTextBuilder.build(events: [event], rollup: PerfRollup(),
                                                   window: WeeklyWindow(containing: date))
        expectEqual(report.letterTargets, [])
        expectEqual(report.analysis.changes.settings.first?.old, nil)
        let html = WeeklyReportHTML.render(report, options: WeeklyReportHTMLOptions(generatedAt: date))
        expectTrue(html.contains("字母設定已改"))
        expectTrue(html.contains("b f h"))
        expectFalse(html.contains("今週實際練過"))
    }

    func testSharedSelectionContract() {
        let items = [PracticePickerItem(id: "quantity:2", label: "2", role: .target),
                     PracticePickerItem(id: "quantity:10", label: "10", role: .target),
                     PracticePickerItem(id: "hanzi:人", label: "人", role: .target),
                     PracticePickerItem(id: "hanzi:入", label: "入", role: .distractorOnly)]
        let available = Dictionary(uniqueKeysWithValues: items.map { ($0.id, PracticePickerAvailability(consumers: ["find"])) })
        let model = PracticePickerModel(catalogID: "fixture", catalogRevision: "1", items: items,
                                        availabilityByItem: available, enabledIDs: ["quantity:10"],
                                        presets: [PracticePickerPreset(id: "school", label: "School", itemIDs: ["hanzi:入", "hanzi:人", "missing"])],
                                        minimum: 1, maximum: 4)
        expectEqual(model.items.map(\.id), items.map(\.id))
        expectEqual(model.previewPreset("school")?.includedIDs, ["hanzi:人"])
        expectEqual(model.previewPreset("school")?.omittedIDs, ["hanzi:入", "missing"])
        let replaced = PracticePickerSelection.reduce(model: model, enabledIDs: model.enabledIDs,
                                                        intent: .replaceFromPreset("school"))
        expectEqual(replaced, Set(["hanzi:人"]))
        expectEqual(PracticePickerSelection.reduce(model: model, enabledIDs: replaced,
                                                    intent: .toggle("quantity:10")), Set(["hanzi:人", "quantity:10"]))
        expectEqual(PracticePickerSelection.reduce(model: model, enabledIDs: replaced,
                                                    intent: .toggle("hanzi:入")), replaced)
        expectEqual(PracticePickerSelection.reduce(model: model, enabledIDs: replaced,
                                                    intent: .revert), model.enabledIDs)
        let numbers = PracticePickerModel(catalogID: "numbers", catalogRevision: "1", items: items.prefix(2).map { $0 },
                                          availabilityByItem: available, enabledIDs: ["quantity:10"], presets: [], minimum: 1, maximum: 2)
        expectEqual(numbers.items.map(\.id), ["quantity:2", "quantity:10"])
        expectEqual(PracticePickerSelection.reduce(model: numbers, enabledIDs: numbers.enabledIDs,
                                                    intent: .toggle("hanzi:人")), numbers.enabledIDs)
        expectEqual(PracticePickerSelection.reduce(model: numbers, enabledIDs: numbers.enabledIDs,
                                                    intent: .toggle("quantity:10")), Set<String>())
        let hanziItems = [PracticePickerItem(id: "hanzi:人", label: "人", role: .target),
                          PracticePickerItem(id: "hanzi:上", label: "上", role: .target),
                          PracticePickerItem(id: "hanzi:左", label: "左", role: .target),
                          PracticePickerItem(id: "hanzi:入", label: "入", role: .distractorOnly)]
        let hanzi = PracticePickerModel(catalogID: "hanzi", catalogRevision: "1", items: hanziItems,
            availabilityByItem: Dictionary(uniqueKeysWithValues: hanziItems.map {
                ($0.id, PracticePickerAvailability(consumers: ["find"])) }), enabledIDs: ["hanzi:人"],
            presets: [PracticePickerPreset(id: "first", label: "First", itemIDs: hanziItems.map(\.id))],
            minimum: 1, maximum: 3)
        expectEqual(hanzi.items.map(\.id), ["hanzi:人", "hanzi:上", "hanzi:左", "hanzi:入"])
        expectEqual(hanzi.previewPreset("first")?.includedIDs, ["hanzi:人", "hanzi:上", "hanzi:左"])
        expectEqual(hanzi.previewPreset("first")?.omittedIDs, ["hanzi:入"])
    }

    func testLetterCapabilitiesAndSelectionSize() throws {
        let bank = try LetterWordBank.load(url: URL(fileURLWithPath: "Resources/LetterTap/starter-bank.json"))
        let readiness = LetterAvailability.resolve(bank: bank, decks: LetterWordDecks())
        expectEqual(all.filter { readiness[$0]?.canWrite == true }, Array("abcdefgh").map(String.init))
        expectEqual(all.filter { readiness[$0]?.canFind == true && readiness[$0]?.canWrite == false }, [])
        let picker = LetterAvailability.pickerModel(bank: bank, decks: .init(), enabled: ["b"])
        expectEqual(picker.previewPreset("fghij")?.includedIDs, ["f", "g", "h"])
        expectEqual(picker.previewPreset("fghij")?.omittedIDs, ["i", "j"])
        for count in [1, 2, 7, 8, 26] {
            expectEqual(try LetterSelectionSettings.canonical(Array(all.prefix(count))).count, count)
        }
        expectThrowsError(try LetterSelectionSettings.canonical([]))
        expectThrowsError(try LetterSelectionSettings.canonical(["A"]))
        expectThrowsError(try LetterSelectionSettings.canonical(["ab"]))
        let assets = LetterAvailability.Assets(display: true, trace: true, judge: true, guide: false, mnemonic: true)
        let findOnly = LetterAvailability.check(letter: "a", bank: bank, decks: .init(), assets: assets)
        expectTrue(findOnly.canFind)
        expectFalse(findOnly.canWrite)
        let dot = LetterAvailability.Assets(display: true, trace: true, judge: false, guide: true, mnemonic: true)
        expectTrue(LetterAvailability.check(letter: "a", bank: bank, decks: .init(), assets: dot).canFind)
        expectFalse(LetterAvailability.check(letter: "a", bank: bank, decks: .init(), assets: dot).canWrite)
        var decks = LetterWordDecks()
        for word in bank.letters["a"]?.words?.filter({ $0.tier == "core" }) ?? [] { decks.hiddenIDs["a", default: []].append(word.id) }
        expectFalse(LetterAvailability.check(letter: "a", bank: bank, decks: decks).canFind)
        let emptyPaths = LetterAvailability.Assets(display: false, trace: false, judge: false, guide: true, mnemonic: true)
        expectFalse(LetterAvailability.check(letter: "a", bank: bank, decks: .init(), assets: emptyPaths).canFind)
        let url = URL(fileURLWithPath: "Resources/LetterTap/starter-bank.json")
        var raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        var entries = raw["letters"] as! [String: [String: Any]]
        var entry = entries["a"]!
        var words = entry["words"] as! [[String: Any]]
        for index in words.indices { words[index]["image_id"] = "word.missing" }
        entry["words"] = words; entries["a"] = entry; raw["letters"] = entries
        let missingArt = try JSONDecoder().decode(LetterWordBank.self, from: JSONSerialization.data(withJSONObject: raw))
        expectFalse(LetterAvailability.check(letter: "a", bank: missingArt, decks: .init()).canFind)
        raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        entries = raw["letters"] as! [String: [String: Any]]; entry = entries["a"]!
        words = entry["words"] as! [[String: Any]]
        let extraIndex = words.firstIndex { $0["tier"] as? String == "extra" }!
        let staleID = words[extraIndex]["id"] as! String
        words[extraIndex]["image_id"] = "word.missing"
        entry["words"] = words; entries["a"] = entry; raw["letters"] = entries
        let partialArt = try JSONDecoder().decode(LetterWordBank.self, from: JSONSerialization.data(withJSONObject: raw))
        var staleDeck = LetterWordDecks()
        staleDeck.schoolWords["a"] = [SchoolWord(id: staleID, expiresAt: Date().addingTimeInterval(86_400))]
        for seed in 0..<30 {
            let dealt = partialArt.deal(letter: "a", box: .practising, seed: "\(seed)",
                                        decks: &staleDeck, now: Date())
            expectEqual(dealt.count, 2)
            expectFalse(dealt.contains { $0.id == staleID })
        }
        expectFalse(staleDeck.schoolWords["a"]?.contains(where: { $0.id == staleID }) ?? true)
        raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        entries = raw["letters"] as! [String: [String: Any]]; entry = entries["a"]!
        words = entry["words"] as! [[String: Any]]
        for index in words.indices { words[index]["highlight"] = [-1, 0] }
        entry["words"] = words; entries["a"] = entry; raw["letters"] = entries
        let corrupt = try JSONDecoder().decode(LetterWordBank.self, from: JSONSerialization.data(withJSONObject: raw))
        expectFalse(LetterAvailability.check(letter: "a", bank: corrupt, decks: .init()).canFind)
    }

    func testV2StoreMigrationAndFailure() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = LetterSelectionSettingsStore(defaults: defaults)
        expectEqual(store.load(), .fresh)
        expectEqual(store.load().effective?.reviewEvery, 0)
        expectEqual(store.load().effective?.focusLetters, Array("abcde").map(String.init))
        expectTrue(defaults.data(forKey: LetterSelectionSettingsStore.key) == nil)
        let legacy = TapLetterSettings(thisWeek: Array("abcdefghi").map(String.init), reviewEvery: 3, writingStyle: "ballstick")
        let blob = try JSONEncoder().encode(legacy)
        defaults.set(blob, forKey: TapLetterSettingsStore.key)
        guard case .legacy(let draft, let oldCadence) = store.load() else { expectTrue(false); return }
        expectEqual(draft.focusLetters, Array("abcdefg").map(String.init))
        expectEqual(oldCadence, 3)
        expectEqual(draft.reviewEvery, 0)
        expectEqual(draft.writingStyle, "ballstick")
        expectTrue(defaults.data(forKey: LetterSelectionSettingsStore.key) == nil)
        let bank = try LetterWordBank.load(url: URL(fileURLWithPath: "Resources/LetterTap/starter-bank.json"))
        let ready = LetterAvailability.resolve(bank: bank, decks: .init())
        var edited = draft
        edited.focusLetters = Array("hgfedcba").map(String.init)
        edited.writingStyle = "accidental-change"
        let saved = try store.save(edited, availability: ready, writingAssigned: true, at: Date(timeIntervalSince1970: 100))
        expectEqual(saved.focusLetters, Array("abcdefgh").map(String.init))
        expectEqual(saved.writingStyle, "ballstick")
        expectEqual(defaults.data(forKey: TapLetterSettingsStore.key), blob)
        defaults.set(Data("bad-v1".utf8), forKey: TapLetterSettingsStore.key)
        expectEqual(store.load(), .saved(saved))
        defaults.set(blob, forKey: TapLetterSettingsStore.key)
        expectEqual(try store.save(saved, availability: ready, writingAssigned: true, at: Date(timeIntervalSince1970: 200)), saved)
        expectEqual(defaults.data(forKey: TapLetterSettingsStore.key), blob)
        var invalid = saved
        invalid.focusLetters = []
        expectThrowsError(try store.save(invalid, availability: ready, writingAssigned: true, at: Date()))
        expectEqual(store.load(), .saved(saved))
        var findOnlyReady = ready
        findOnlyReady["a"] = LetterCapability(canDisplay: true, canFind: true, canWrite: false)
        var findOnlyDraft = saved
        findOnlyDraft.focusLetters = ["a"]
        findOnlyDraft.focusOrder = ["a"]
        expectThrowsError(try store.save(findOnlyDraft, availability: findOnlyReady,
                                         writingAssigned: true, at: Date()))
        let fourReady = ready.filter { ["a", "b", "c", "d"].contains($0.key) }
        expectThrowsError(try store.save(findOnlyDraft, availability: fourReady,
                                         writingAssigned: false, at: Date()))
        let findOnlySaved = try store.save(findOnlyDraft, availability: findOnlyReady,
                                          writingAssigned: false, at: Date(timeIntervalSince1970: 150))
        expectEqual(findOnlySaved.focusLetters, ["a"])
        expectEqual(defaults.data(forKey: TapLetterSettingsStore.key), blob)
        var reviewDraft = findOnlySaved
        reviewDraft.reviewEvery = 4
        reviewDraft.reviewLetters = ["b"]
        expectThrowsError(try store.save(reviewDraft, availability: ready, writingAssigned: false, at: Date()))
        let reviewSaved = try store.save(reviewDraft, availability: ready, writingAssigned: false,
                                         allowedReview: ["b"], at: Date(timeIntervalSince1970: 160))
        expectEqual(reviewSaved.reviewLetters, ["b"])
        expectEqual(try store.save(reviewSaved, availability: ready, writingAssigned: false,
                                   at: Date(timeIntervalSince1970: 170)), reviewSaved)
        _ = try store.save(saved, availability: ready, writingAssigned: true, at: Date(timeIntervalSince1970: 175))
        var duplicate = saved
        duplicate.focusLetters = ["b", "a", "b"]
        duplicate.focusOrder = ["b", "a"]
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        defaults.set(try encoder.encode(duplicate), forKey: LetterSelectionSettingsStore.key)
        guard case .saved(let normalized) = store.load() else { expectTrue(false); return }
        expectEqual(normalized.focusLetters, ["a", "b"])
        let normalizedSave = try store.save(normalized, availability: ready, writingAssigned: true, at: Date(timeIntervalSince1970: 250))
        expectEqual(normalizedSave.revision, normalized.revision)
        let canonicalBlob = defaults.data(forKey: LetterSelectionSettingsStore.key)!
        expectEqual((try decoderForLetterPicker().decode(LetterSelectionSettings.self, from: canonicalBlob)).focusLetters, ["a", "b"])
        duplicate.focusLetters = ["A"]
        defaults.set(try encoder.encode(duplicate), forKey: LetterSelectionSettingsStore.key)
        expectEqual(store.load(), .corruptV2)
        defaults.set(Data("corrupt".utf8), forKey: LetterSelectionSettingsStore.key)
        expectEqual(store.load(), .corruptV2)
        expectThrowsError(try store.save(saved, availability: ready, writingAssigned: true, at: Date()))
        expectEqual(defaults.data(forKey: LetterSelectionSettingsStore.key), Data("corrupt".utf8))
        let repaired = try store.save(saved, availability: ready, writingAssigned: true,
                                      at: Date(timeIntervalSince1970: 300), repairCorruptV2: true)
        expectEqual(repaired.focusLetters, saved.focusLetters)
        expectEqual(defaults.data(forKey: LetterSelectionSettingsStore.corruptBackupKey), Data("corrupt".utf8))
        expectEqual(defaults.data(forKey: TapLetterSettingsStore.key), blob)
        defaults.removeObject(forKey: LetterSelectionSettingsStore.key)
        defaults.set(Data("bad".utf8), forKey: TapLetterSettingsStore.key)
        guard case .repairV1 = store.load() else { expectTrue(false); return }
        let mixedLegacy = TapLetterSettings(thisWeek: ["b", "b", "A", "a", "é"])
        defaults.set(try JSONEncoder().encode(mixedLegacy), forKey: TapLetterSettingsStore.key)
        guard case .legacy(let mixedDraft, _) = store.load() else { expectTrue(false); return }
        expectEqual(mixedDraft.focusLetters, ["a", "b"])
    }

    private func decoderForLetterPicker() -> JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder
    }

    func testScopedDealsAndReviewCadence() throws {
        let bank = try LetterWordBank.load(url: URL(fileURLWithPath: "Resources/LetterTap/starter-bank.json"))
        let ready = LetterAvailability.resolve(bank: bank, decks: .init())
        var settings = LetterSelectionSettings.defaults
        settings.focusLetters = ["b", "f", "h"]
        settings.focusOrder = settings.focusLetters
        var schedule = LetterSelectionSchedule()
        var progress = LetterProgress()
        var targets: [String] = []
        for round in 1...9 {
            let result = TapLetterGenerator.makeScoped(seed: "scope-\(round)", kind: .tapLetterAll, n: round,
                settings: settings, schedule: &schedule, progress: progress, decks: .init(), bank: bank, now: Date())
            guard case .deal(let deal) = result else { expectTrue(false); return }
            expectTrue(settings.focusLetters.contains(deal.target))
            expectTrue(deal.board.letters.allSatisfy { ready[$0]?.canFind == true })
            targets.append(deal.target)
            progress.record(deal.target, clean: true, round: round, at: Date(), lane: deal.lane)
            schedule.completedChildRound()
        }
        expectEqual(Set(targets.prefix(3)), Set(settings.focusLetters))
        var one = settings
        one.focusLetters = ["b"]
        one.focusOrder = ["b"]
        for seed in 0..<50 {
            var local = LetterSelectionSchedule()
            let result = TapLetterGenerator.makeScoped(seed: "singleton-\(seed)", kind: .tapLetterAll, n: 1,
                settings: one, schedule: &local, progress: .init(), decks: .init(), bank: bank, now: Date())
            guard case .deal(let deal) = result else { expectTrue(false); return }
            expectEqual(deal.target, "b")
            expectEqual(Set(deal.board.letters).count, 5)
            expectEqual(deal.board.targetCards.count, 2)
            expectTrue(deal.board.letters.allSatisfy { ready[$0]?.canFind == true })
            expectTrue(deal.board.targetCards[0] % 5 != deal.board.targetCards[1] % 5)
            one.focusLetters = ["f"]
            expectEqual(deal.selection?.focusLetters, ["b"])
            one.focusLetters = ["b"]
        }
        settings.reviewLetters = ["a"]
        settings.reviewEvery = 4
        schedule = .init()
        progress = .init()
        progress.record("a", clean: true, round: 1, at: Date(timeIntervalSince1970: 0))
        var reviewRounds: [Int] = []
        for round in 1...12 {
            let kind: ActivityKind = round.isMultiple(of: 2) ? .tapLetterWrite : .tapLetterAll
            let result = TapLetterGenerator.makeScoped(seed: "mixed-\(round)", kind: kind, n: round,
                settings: settings, schedule: &schedule, progress: progress, decks: .init(), bank: bank, now: Date(timeIntervalSince1970: 10 * 86_400))
            guard case .deal(let deal) = result else { expectTrue(false); return }
            if deal.lane == .review { reviewRounds.append(round); expectEqual(deal.target, "a") }
            schedule.completedChildRound()
        }
        expectEqual(reviewRounds, [4, 8, 12])
        var interrupted = LetterSelectionSchedule()
        interrupted.completedChildRound(); interrupted.completedChildRound(); interrupted.completedChildRound()
        let firstOpportunity = interrupted.next(seed: "review-once", kind: .tapLetterAll, n: 4,
            settings: settings, availability: ready, progress: progress, now: Date(timeIntervalSince1970: 10 * 86_400))
        expectEqual(firstOpportunity?.lane, .review)
        let afterZeroed = interrupted.next(seed: "zeroed", kind: .tapLetterWrite, n: 5,
            settings: settings, availability: ready, progress: progress, now: Date(timeIntervalSince1970: 10 * 86_400))
        expectTrue(afterZeroed?.lane != .review)
        var noDue = LetterSelectionSchedule()
        noDue.completedChildRound(); noDue.completedChildRound(); noDue.completedChildRound()
        var recentlyKnown = LetterProgress()
        var knownState = LetterState()
        knownState.box = .known
        knownState.lastSeen = Date(timeIntervalSince1970: 10 * 86_400)
        knownState.hasTargetRound = true
        recentlyKnown.letters["a"] = knownState
        let ordinary = noDue.next(seed: "no-due", kind: .tapLetterAll, n: 4,
            settings: settings, availability: ready, progress: recentlyKnown,
            now: Date(timeIntervalSince1970: 10 * 86_400))
        expectTrue(ordinary?.lane != .review)
        let noDebt = noDue.next(seed: "no-debt", kind: .tapLetterWrite, n: 5,
            settings: settings, availability: ready, progress: progress, now: Date(timeIntervalSince1970: 10 * 86_400))
        expectTrue(noDebt?.lane != .review)
        settings.reviewEvery = 0
        var stale = LetterProgress()
        stale.retryQueue = [LetterRetry(letter: "z", dueRound: 1)]
        let result = TapLetterGenerator.makeScoped(seed: "stale", kind: .tapLetterWrite, n: 20,
            settings: settings, schedule: &schedule, progress: stale, decks: .init(), bank: bank, now: Date())
        guard case .deal(let deal) = result else { expectTrue(false); return }
        expectTrue(settings.focusLetters.contains(deal.target))
        var empty = settings
        empty.focusLetters = ["i"]
        let noDeal = TapLetterGenerator.makeScoped(seed: "empty", kind: .tapLetterWrite, n: 1,
            settings: empty, schedule: &schedule, progress: .init(), decks: .init(), bank: bank, now: Date())
        expectEqual(noDeal.reason, .noEligibleFocus)
        var shortDecks = LetterWordDecks()
        for letter in "efgh" {
            shortDecks.hiddenIDs[String(letter)] = bank.letters[String(letter)]?.words?.filter { $0.tier == "core" }.map(\.id) ?? []
        }
        var singleton = settings
        singleton.focusLetters = ["a"]
        singleton.focusOrder = ["a"]
        let short = TapLetterGenerator.makeScoped(seed: "short", kind: .tapLetterAll, n: 1,
            settings: singleton, schedule: &schedule, progress: .init(), decks: shortDecks, bank: bank, now: Date())
        expectEqual(short.reason, .insufficientBoardLetters)
        expectEqual(LetterTicketEligibility.eligible([.tapLetterAll], settings: singleton,
            bank: bank, decks: shortDecks, progress: .init()), [])
        expectEqual(LetterTicketEligibility.eligible([.tapLetterAll, .twoPictureChoose], settings: singleton,
            bank: bank, decks: shortDecks, progress: .init()), [.twoPictureChoose])
    }

    func testFocusBagSizesKindsAndCapabilityChange() {
        for count in [1, 2, 8, 26] {
            var settings = LetterSelectionSettings.defaults
            settings.focusLetters = Array(all.prefix(count))
            settings.focusOrder = settings.focusLetters
            let readiness = Dictionary(uniqueKeysWithValues: all.map { ($0,
                LetterCapability(canDisplay: true, canFind: true, canWrite: true)) })
            var schedule = LetterSelectionSchedule()
            var seen: [String] = []
            for n in 1...count {
                let target = schedule.next(seed: "bag-\(n)", kind: .tapLetterAll, n: n,
                    settings: settings, availability: readiness, progress: .init(), now: Date())
                seen.append(target!.target)
            }
            expectEqual(Set(seen), Set(settings.focusLetters))
            expectEqual(schedule.focusBags[ActivityKind.tapLetterAll.rawValue], [])
            expectTrue(schedule.focusBags[ActivityKind.tapLetterWrite.rawValue] == nil)
        }
        var settings = LetterSelectionSettings.defaults
        settings.focusLetters = ["b", "f", "h", "i", "j"]
        settings.focusOrder = settings.focusLetters
        var readiness = Dictionary(uniqueKeysWithValues: all.map { ($0,
            LetterCapability(canDisplay: true, canFind: true, canWrite: ["b", "f", "h"].contains($0))) })
        expectEqual(settings.focus(for: .tapLetterAll, availability: readiness), settings.focusLetters)
        expectEqual(settings.focus(for: .tapLetterWrite, availability: readiness), ["b", "f", "h"])
        var schedule = LetterSelectionSchedule()
        for n in 1...3 {
            let write = schedule.next(seed: "write-\(n)", kind: .tapLetterWrite, n: n,
                settings: settings, availability: readiness, progress: .init(), now: Date())
            expectTrue(["b", "f", "h"].contains(write!.target))
        }
        let find = schedule.next(seed: "find", kind: .tapLetterAll, n: 4,
            settings: settings, availability: readiness, progress: .init(), now: Date())
        expectEqual(find?.target, "b")
        readiness["i"] = LetterCapability(canDisplay: true, canFind: true, canWrite: true)
        expectEqual(settings.focus(for: .tapLetterWrite, availability: readiness), ["b", "f", "h", "i"])
        let upgraded = schedule.next(seed: "new", kind: .tapLetterWrite, n: 5,
            settings: settings, availability: readiness, progress: .init(), now: Date())
        expectEqual(upgraded?.target, "b")
        expectEqual(schedule.focusBags[ActivityKind.tapLetterAll.rawValue]?.count, 4)
    }

    func testPreviewValueCopiesDoNotMutateChildState() {
        let childSchedule = LetterSelectionSchedule()
        let childProgress = LetterProgress()
        let childDecks = LetterWordDecks()
        let childWriting = LetterWriteProgress()
        let childStrokes = StrokeOrderProgress()
        var previewSchedule = childSchedule
        var previewProgress = childProgress
        var previewDecks = childDecks
        var previewWriting = childWriting
        var previewStrokes = childStrokes
        previewSchedule.completedChildRound()
        previewProgress.record("b", clean: false, round: 1, at: Date())
        previewDecks.hiddenIDs["b"] = ["b.ball"]
        previewWriting.record("b", clean: true)
        previewStrokes.noteTraced("latin:b", today: 1)
        expectEqual(childSchedule.completedChildRounds, 0)
        expectEqual(childProgress, LetterProgress())
        expectEqual(childDecks, LetterWordDecks())
        expectEqual(childWriting, LetterWriteProgress())
        expectEqual(childStrokes, StrokeOrderProgress())
    }

    func testChildTargetHistoryFiltersActorsAndExclusions() {
        let cutoff = Date(timeIntervalSince1970: 100 * 86_400)
        func event(_ type: PerfEventType, _ letter: String, _ round: String,
                   _ day: Int, _ actor: PerfActor = .child, _ session: String = "child") -> PerfEvent {
            PerfEvent(type: type, timestamp: Date(timeIntervalSince1970: Double(day) * 86_400),
                      tz: "+08:00", mono: Double(day), launch: "L\(round)", seq: day,
                      app: "test", actor: actor, mode: "lock", session: session,
                      fields: ["kind": .string(ActivityKind.tapLetterAll.rawValue),
                               "target": .string(letter), "round": .string(round)])
        }
        var events = [event(.gameDealt, "a", "a", 99), event(.gameDealt, "a", "a", 99),
                      event(.gameDealt, "b", "b", 99, .parentPlaytest),
                      event(.gameDealt, "f", "f", 99, .parentTestVisa),
                      event(.gameDealt, "g", "g", 99, .parentUAT),
                      event(.gameDealt, "c", "c", 99, .child, "excluded"),
                      event(.gameDealt, "d", "d", 1),
                      event(.gameDealt, "ab", "e", 99)]
        events.append(PerfEvent(type: .statsExclude, timestamp: cutoff, tz: "+08:00", mono: 0,
            launch: "Lexclude", seq: 1, app: "test", actor: .parent, mode: "parent", session: "parent",
            fields: ["target_session": .string("excluded")]))
        expectEqual(LetterTargetHistory.practiced(in: events, at: cutoff), ["a"])
        events.append(PerfEvent(type: .statsInclude, timestamp: cutoff, tz: "+08:00", mono: 1,
            launch: "Linclude", seq: 1, app: "test", actor: .parent, mode: "parent", session: "parent",
            fields: ["target_session": .string("excluded")]))
        expectEqual(LetterTargetHistory.practiced(in: events, at: cutoff), ["a", "c"])
    }

    func testAppRoutingAndPreviewSourceGuards() throws {
        let source = try String(contentsOfFile: "Sources/VisaGames/AppDelegate.swift", encoding: .utf8)
        guard let pool = source.range(of: "let pool = eligibleLetterTicketPool"),
              let empty = source.range(of: "guard !pool.isEmpty else {", range: pool.upperBound..<source.endIndex),
              let choose = source.range(of: "ActivityCatalog.kind(forRoundSeed: seed, pool: pool)", range: empty.upperBound..<source.endIndex),
              let preview = source.range(of: "if tapLetterUsesPlaytest && board.deal.selection != nil"),
              let childStore = source.range(of: "LetterProgressStore().save(tapLetterProgress)", range: preview.upperBound..<source.endIndex) else {
            expectTrue(false, "Scoped ticket routing and preview branches exist")
            return
        }
        expectTrue(pool.lowerBound < empty.lowerBound && empty.lowerBound < choose.lowerBound)
        expectTrue(preview.lowerBound < childStore.lowerBound)
        expectTrue(source.contains("previewLetterWriteProgress = writing"))
        expectTrue(source.contains("previewStrokeOrderProgress = strokes"))
        expectTrue(source.contains("LetterSelectionScheduleStore().save(schedule)"))
        expectTrue(source.contains("guard session.mode == .parent else { throw LetterSelectionSettingsStore.StoreError.notParent }"))
        expectTrue(source.contains("unavailableLetterTicket = true"))
    }
}
