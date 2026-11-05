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
        // Build 78: the empty-pool / kind choice moved into `LetterTicketDesk.prepare`
        // (executable tests: testTicketDeskFailedDealKeepsRoundAndRecoveryClears).
        guard let pool = source.range(of: "let pool = eligibleLetterTicketPool"),
              let choose = source.range(of: "desk.prepare(pool: pool", range: pool.upperBound..<source.endIndex),
              let preview = source.range(of: "if tapLetterUsesPlaytest && board.deal.selection != nil"),
              let childStore = source.range(of: "LetterProgressStore().save(tapLetterProgress)", range: preview.upperBound..<source.endIndex) else {
            expectTrue(false, "Scoped ticket routing and preview branches exist")
            return
        }
        expectTrue(pool.lowerBound < choose.lowerBound)
        expectTrue(preview.lowerBound < childStore.lowerBound)
        expectTrue(source.contains("previewLetterWriteProgress = writing"))
        expectTrue(source.contains("previewStrokeOrderProgress = strokes"))
        expectTrue(source.contains("LetterSelectionScheduleStore().save(schedule)"))
        expectTrue(source.contains("guard session.mode == .parent else { throw LetterSelectionSettingsStore.StoreError.notParent }"))
        expectTrue(source.contains("var unavailableLetterTicket: Bool { letterTicketDesk.unavailable }"))
    }

    func testParentLetterDraftLifecycleSourceGuards() throws {
        let page = try String(contentsOfFile: "Sources/VisaGames/ParentSettingsView.swift", encoding: .utf8)
        let card = try String(contentsOfFile: "Sources/VisaGames/ParentTapLetterSettingsView.swift", encoding: .utf8)
        let picker = try String(contentsOfFile: "Sources/VisaGames/ParentPracticeItemPicker.swift", encoding: .utf8)
        expectTrue(page.contains("if library == .games {\n                        ParentLetterSettingsSaveBar"))
        expectFalse(page.contains("library == .games && letterState.draft != nil"))
        expectTrue(page.contains("if library == .games { letterState.open(model: model) }"))
        expectTrue(page.range(of: #"\.onDisappear\s*\{[^}]*letterState\.clear\(\)"#,
                              options: .regularExpression) != nil)
        expectTrue(card.contains("func open(model: AppModel) {\n        guard draft == nil, !isLoading else { return }"))
        expectTrue(card.contains("func clear() {\n        guard draft != nil || isLoading else { return }"))
        expectTrue(card.contains(".frame(height: 116)"))
        expectTrue(card.contains("ParentActionButton(title: \"還原\", subtitle: \"Revert\""))
        expectTrue(card.contains("ParentActionButton(title: \"取消\", subtitle: \"Cancel\""))
        expectTrue(card.contains("ParentActionButton(title: \"儲存\", subtitle: \"Save\""))
        expectTrue(card.contains(".disabled(!state.saveCheck.canSave)"))
        // Status words are VisaCore `LetterPickerStatus` (executed in testLetterStatusText…).
        expectTrue(card.contains("LetterPickerStatus.text(load: load, hasDraft: draft != nil"))
        expectFalse(card.contains(".onAppear { state.open(model: model) }"))
        expectFalse(card.contains(".onDisappear { state.clear() }"))
        // Build 79 (UX m1): host-supplied columns (letters: 9, design D2), eager rows.
        expectTrue(picker.contains("ForEach(Array(targets.dropFirst(row * columns).prefix(columns)), id: \\.id)"))
    }

    // MARK: Build 78

    /// (a) With neither key the child keeps the v1 generator (abcde, review every 4) until the
    /// first explicit v2 Save; the editor still proposes review-off for that Save (ADR 0026).
    func testFreshAndLegacyKeepV1UntilFirstSave() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = LetterSelectionSettingsStore(defaults: defaults)
        let fresh = store.load()
        expectEqual(fresh, .fresh)
        expectTrue(fresh.activeSelection == nil)
        expectEqual(fresh.previousReviewEvery, 4)
        expectEqual(fresh.effective?.reviewEvery, 0)
        let v1 = TapLetterSettingsStore(defaults: defaults).load()
        expectEqual(v1, TapLetterSettings.defaults)
        expectEqual(v1.reviewEvery, 4)
        expectEqual(v1.validWeek, Array("abcde").map(String.init))
        let bank = try LetterWordBank.load(url: URL(fileURLWithPath: "Resources/LetterTap/starter-bank.json"))
        let v1Deal = TapLetterGenerator.make(seed: "fresh-v1", n: 1, settings: v1, progress: .init(),
                                             decks: .init(), bank: bank, now: Date())
        expectTrue(v1Deal != nil)
        expectTrue(v1Deal?.selection == nil, "before a v2 Save the child deal is a v1 deal")
        expectEqual(LetterSelectionLoad.repairV1.previousReviewEvery, 4)
        expectTrue(LetterSelectionLoad.repairV1.activeSelection == nil)
        expectTrue(LetterSelectionLoad.corruptV2.activeSelection == nil)
        expectTrue(LetterSelectionLoad.corruptV2.previousReviewEvery == nil)
        defaults.set(try JSONEncoder().encode(TapLetterSettings(reviewEvery: 3)), forKey: TapLetterSettingsStore.key)
        let legacy = store.load()
        expectTrue(legacy.activeSelection == nil)
        expectEqual(legacy.previousReviewEvery, 3)
        let ready = LetterAvailability.resolve(bank: bank, decks: .init())
        let saved = try store.save(legacy.effective!, availability: ready, writingAssigned: true, at: Date(timeIntervalSince1970: 10))
        expectEqual(store.load().activeSelection, saved)
        expectTrue(store.load().previousReviewEvery == nil)
        expectEqual(["fresh", "legacy", "repairV1", "saved", "corruptV2"],
                    [LetterSelectionLoad.fresh, legacy, .repairV1, .saved(saved), .corruptV2].map(\.logName))
        let app = try String(contentsOfFile: "Sources/VisaGames/AppDelegate.swift", encoding: .utf8)
        expectTrue(app.contains("private var activeLetterSelection: LetterSelectionSettings? { letterSelectionLoad.activeSelection }"))
        expectFalse(app.contains("case .fresh: return .defaults"))
    }

    /// (b) The unchanged default draft saves against the REAL bundled bank from `.fresh`, writes
    /// the v2 key and reads back; a missing bank never offers Save.
    func testDefaultDraftSavesAgainstRealBundledBank() throws {
        let bank = try LetterWordBank.load(url: URL(fileURLWithPath: "Resources/LetterTap/starter-bank.json"))
        let resources = LetterPickerResources(bank: bank, decks: .init(), history: [])
        expectTrue(resources.bankAvailable)
        expectFalse(LetterPickerResources(bank: nil, decks: .init(), history: ["a"]).bankAvailable)
        for writingAssigned in [true, false] {
            let defaults = UserDefaults(suiteName: UUID().uuidString)!
            let store = LetterSelectionSettingsStore(defaults: defaults)
            let load = store.load()
            let draft = LetterPickerDraft(saved: load.effective!)
            expectFalse(draft.hasChanges)
            let check = LetterPickerSaveCheck.evaluate(draft.value, availability: resources.capabilities,
                writingAssigned: writingAssigned, allowedReview: Set(resources.history), load: load,
                repairCorruptV2: false, bankAvailable: resources.bankAvailable)
            expectTrue(check.canSave, "defaults must be savable: \(check.reason ?? "")")
            let saved = try store.save(draft.value, availability: resources.capabilities,
                writingAssigned: writingAssigned, allowedReview: Set(resources.history), at: Date(timeIntervalSince1970: 20))
            expectTrue(defaults.data(forKey: LetterSelectionSettingsStore.key) != nil, "v2 key written")
            expectEqual(store.load(), .saved(saved))
            expectEqual(saved.revision, 1)
            expectEqual(saved.focusLetters, Array("abcde").map(String.init))
            expectEqual(saved.reviewEvery, 0)
        }
    }

    /// (b) Review can never stay on with no letters, so Save is never blocked by a review reason
    /// the parent did not choose.
    func testReviewTurnsOffWhenItsLastLetterBecomesFocus() throws {
        let bank = try LetterWordBank.load(url: URL(fileURLWithPath: "Resources/LetterTap/starter-bank.json"))
        let ready = LetterAvailability.resolve(bank: bank, decks: .init())
        let saved = LetterSelectionSettings(focusLetters: Array("abcde").map(String.init),
            focusOrder: Array("abcde").map(String.init), reviewEvery: 4, reviewLetters: ["f"])
        func canSave(_ draft: LetterPickerDraft) -> Bool {
            LetterPickerSaveCheck.evaluate(draft.value, availability: ready, writingAssigned: true,
                allowedReview: ["f"], load: .saved(saved), repairCorruptV2: false).canSave
        }
        var toggled = LetterPickerDraft(saved: saved)
        expectTrue(canSave(toggled))
        toggled.toggleFocus("f")
        expectEqual(toggled.value.reviewLetters, [])
        expectEqual(toggled.value.reviewEvery, 0)
        expectTrue(canSave(toggled))
        toggled.toggleFocus("f")
        expectTrue(toggled.hasChanges, "review stays off after f leaves focus again")
        var replaced = LetterPickerDraft(saved: saved)
        replaced.replaceFocus(["f", "g", "h"], source: "fghij")
        expectEqual(replaced.value.reviewEvery, 0)
        expectTrue(canSave(replaced))
        var refreshed = LetterPickerDraft(saved: saved)
        refreshed.refreshReview(["a", "b"])
        expectEqual(refreshed.value.reviewEvery, 0)
        var enabled = LetterPickerDraft(saved: LetterSelectionSettings.defaults)
        enabled.setReviewEvery(4, candidates: ["a"])
        expectEqual(enabled.value.reviewEvery, 0)
        enabled.setReviewEvery(4, candidates: ["f"])
        expectEqual(enabled.value.reviewEvery, 4)
        expectEqual(enabled.value.reviewLetters, ["f"])
    }

    /// (c) One shared parse; failures are retried, not cached.
    func testLetterWordBankCacheParsesOnceAndRetriesFailures() throws {
        let bank = try LetterWordBank.load(url: URL(fileURLWithPath: "Resources/LetterTap/starter-bank.json"))
        let counter = LetterBankLoadCounter()
        let cache = LetterWordBankCache(loader: {
            counter.loads += 1
            if counter.failNext { counter.failNext = false; throw LetterBankLoadFailure() }
            return bank
        })
        expectThrowsError(try cache.load())
        _ = try cache.load()
        _ = try cache.load()
        expectEqual(counter.loads, 2)
    }

    /// (c)(d)(e)(f) App-target guards: AppKit/SwiftUI code is not compiled on Linux.
    func testBuild78AppSourceGuards() throws {
        let app = try String(contentsOfFile: "Sources/VisaGames/AppDelegate.swift", encoding: .utf8)
        let card = try String(contentsOfFile: "Sources/VisaGames/ParentTapLetterSettingsView.swift", encoding: .utf8)
        let page = try String(contentsOfFile: "Sources/VisaGames/ParentSettingsView.swift", encoding: .utf8)
        let hooks = try String(contentsOfFile: "Sources/VisaGames/ParentScrollHooks.swift", encoding: .utf8)
        let recorder = try String(contentsOfFile: "Sources/VisaGames/PerformanceRecorder.swift", encoding: .utf8)
        func body(_ source: String, from start: String, to end: String) -> Substring? {
            guard let lower = source.range(of: start),
                  let upper = source.range(of: end, range: lower.upperBound..<source.endIndex) else { return nil }
            return source[lower.lowerBound..<upper.lowerBound]
        }
        // (c) No bank parse or event-store read on main for the parent editor or Save.
        expectFalse(app.contains("LetterWordBank.loadBundled()"))
        expectFalse(app.contains("PerfEventStore(directory"))
        expectFalse(card.contains("practicedLetterTargets"))
        expectTrue(card.contains("model.withLetterPickerResources"))
        expectTrue(card.contains("model.saveLetterSelection(draft.value, resources: resources"))
        expectTrue(recorder.contains("func letterPickerResources(decks: LetterWordDecks, bankCache: LetterWordBankCache"))
        // (b) Save outcome is always logged.
        for result in ["result=notReady", "result=blocked", "result=saved", "result=invalid", "result=storeError", "result=error"] {
            expectTrue(card.contains("DRAFT save \(result)"), result)
        }
        expectTrue(app.contains("DRAFT save stored key="))
        // (d) Wiring only: the transition itself is executed in testTicketDesk… (VisaCore).
        for (start, end, route) in [("private func enterParentAfterAuthentication()", "func soakEnterParent()", ".parentEntered"),
                                    ("func returnToChild(reason: String", "providerBlockedParentHint = nil", ".returnedToChild"),
                                    ("case .updated(let next):", "case .rejectedLastStar:", ".assignmentChanged"),
                                    ("@discardableResult func saveLetterSelection(", "private func makeTapLetterBoard(", ".lettersSaved")] {
            guard let section = body(app, from: start, to: end) else { expectTrue(false, start); continue }
            expectTrue(section.contains("recoverLetterTicket(\(route))"), start)
        }
        guard let select = body(app, from: "func selectDifficulty(stars: Int)", to: "tapLetterWriteRound = kind ==") else {
            expectTrue(false, "selectDifficulty"); return
        }
        guard let prepare = select.range(of: "desk.prepare(pool: pool"),
              let ready = select.range(of: "guard case .ready(let seed, let kind, let preparedLetterBoard) = outcome else {"),
              let reset = select.range(of: "resetTaskRound()") else {
            expectTrue(false, "selectDifficulty order markers"); return
        }
        expectTrue(prepare.lowerBound < ready.lowerBound && ready.lowerBound < reset.lowerBound)
        expectTrue(select.contains("tapLetterBoard = preparedLetterBoard"))
        // (e) Hooks are opt-in and nil-safe.
        expectTrue(hooks.contains("static let isEnabled = ParentScrollOptions.stackHooksEnabled()"))
        expectTrue(hooks.contains("guard isEnabled else {"))
        expectTrue(hooks.contains("(AnyObject, Selector, AnyObject?) -> Void"))
        expectFalse(hooks.contains("(AnyObject, Selector, AnyObject) -> Void"))
        // (f) No lazy grid above the Games letter card; the clock no longer publishes the page.
        guard let quick = body(page, from: "private var quickActions: some View {", to: "private var allowlistSection"),
              let games = body(page, from: "private func gamesSection(proxy: ScrollViewProxy)", to: "private var unbuiltRow") else {
            expectTrue(false, "page sections"); return
        }
        expectFalse(quick.contains("LazyVGrid("), "no lazy grid code in quickActions")
        expectFalse(games.contains("LazyVGrid("), "no lazy grid code in gamesSection")
        expectTrue(quick.contains("ParentEagerRows("))
        expectTrue(games.contains("ParentEagerRows("))
        expectFalse(page.contains("GeometryReader"))
        expectFalse(app.contains("@Published private(set) var now"))
        expectTrue(app.contains("if publishClock { objectWillChange.send() }"))
        expectTrue(app.contains("if next != session {"))
    }
}

extension LetterPickerTests {
    /// Review finding 2: executable ticket transition. A failed deal leaves the round as it
    /// was, and every recovery route clears the unavailable state without a letter Save.
    func testTicketDeskFailedDealKeepsRoundAndRecoveryClears() {
        // The caller's contract (AppModel.selectDifficulty): only `.ready` touches the round.
        struct Round: Equatable { var stars: Int?; var seed: String?; var kind: ActivityKind?; var board: String? }
        func select(_ desk: inout LetterTicketDesk, _ round: inout Round, pool: [ActivityKind],
                    seed: String, board: String?, dealt: inout [ActivityKind]) {
            let outcome: LetterTicketDesk.Outcome<String> = desk.prepare(pool: pool, seed: seed) { kind in
                dealt.append(kind)
                return board
            }
            guard case .ready(let seed, let kind, let letterBoard) = outcome else { return }
            round = Round(stars: 2, seed: seed, kind: kind, board: letterBoard)
        }
        let before = Round(stars: nil, seed: nil, kind: nil, board: nil)
        var desk = LetterTicketDesk()
        var round = before
        var dealt: [ActivityKind] = []
        select(&desk, &round, pool: [], seed: "empty", board: "b", dealt: &dealt)
        expectTrue(desk.unavailable)
        expectEqual(round, before)
        expectEqual(dealt, [])
        desk = LetterTicketDesk()
        select(&desk, &round, pool: [.tapLetterAll], seed: "nodeal", board: nil, dealt: &dealt)
        expectTrue(desk.unavailable, "failed letter deal")
        expectEqual(round, before, "round state untouched by a failed deal")
        expectEqual(dealt, [.tapLetterAll])
        // Recovery without a letter Save, per route; recovering twice changes nothing.
        for route in LetterTicketDesk.Recovery.allCases where route != .lettersSaved {
            var blocked = desk
            expectTrue(blocked.recover(route), route.rawValue)
            expectFalse(blocked.unavailable, route.rawValue)
            expectFalse(blocked.recover(route), route.rawValue)
        }
        // After an assignment change the pool has no letter kind: the next ticket deals.
        var recovered = desk
        recovered.recover(.assignmentChanged)
        dealt = []
        select(&recovered, &round, pool: [.twoPictureChoose], seed: "pictures", board: nil, dealt: &dealt)
        expectFalse(recovered.unavailable)
        expectEqual(round.kind, ActivityKind.twoPictureChoose)
        expectTrue(round.board == nil)
        expectEqual(dealt, [], "the letter dealer runs only for letter kinds")
        // A successful letter deal clears the state too and hands over the board.
        select(&desk, &round, pool: [.tapLetterWrite], seed: "write", board: "w", dealt: &dealt)
        expectFalse(desk.unavailable)
        expectEqual(round, Round(stars: 2, seed: "write", kind: .tapLetterWrite, board: "w"))
    }

    /// Review finding 3: clearing records or (un)excluding a session invalidates the editor's
    /// history snapshot; an in-flight load is dropped and pending waiters get a fresh load.
    func testLetterHistorySnapshotInvalidatesAfterRecordChanges() {
        var cache = VersionedLoadCache<[String], String>()
        guard case .startLoad(let first) = cache.request("open") else { expectTrue(false, "first load"); return }
        guard case .queued = cache.request("second") else { expectTrue(false, "queued"); return }
        guard let restart = cache.invalidate() else { expectTrue(false, "pending waiters restart"); return }
        expectTrue(cache.deliver(["a", "c"], token: first) == nil, "in-flight pre-change result dropped")
        expectTrue(cache.value == nil)
        expectEqual(cache.deliver(["a"], token: restart) ?? [], ["open", "second"])
        guard case .cached(let cached) = cache.request("reopen") else { expectTrue(false, "cached"); return }
        expectEqual(cached, ["a"])
        expectTrue(cache.invalidate() == nil, "no waiters: nothing to restart")
        expectTrue(cache.value == nil, "cached snapshot dropped")
        guard case .startLoad(let late) = cache.request("editor") else { expectTrue(false, "reload"); return }
        cache.reset()
        expectTrue(cache.deliver(["x"], token: late) == nil, "leaving parent drops everything")
        // The real history changes under those operations.
        let cutoff = Date(timeIntervalSince1970: 100 * 86_400)
        func dealt(_ letter: String, session: String) -> PerfEvent {
            PerfEvent(type: .gameDealt, timestamp: cutoff.addingTimeInterval(-3600), tz: "+08:00", mono: 1,
                      launch: "L", seq: 1, app: "test", actor: .child, mode: "lock", session: session,
                      fields: ["kind": .string(ActivityKind.tapLetterAll.rawValue),
                               "target": .string(letter), "round": .string("r-\(letter)")])
        }
        var events = [dealt("a", session: "keep"), dealt("c", session: "drop")]
        let before = LetterPickerResources(bank: nil, decks: .init(),
            history: LetterTargetHistory.practiced(in: events, at: cutoff))
        expectEqual(before.history, ["a", "c"])
        events.append(PerfEvent(type: .statsExclude, timestamp: cutoff, tz: "+08:00", mono: 2, launch: "L", seq: 2,
            app: "test", actor: .parent, mode: "parent", session: "parent",
            fields: ["target_session": .string("drop")]))
        expectEqual(LetterTargetHistory.practiced(in: events, at: cutoff), ["a"], "excluded session leaves the pool")
        expectEqual(LetterTargetHistory.practiced(in: [], at: cutoff), [], "cleared records leave no history")
        let app = try? String(contentsOfFile: "Sources/VisaGames/AppDelegate.swift", encoding: .utf8)
        expectTrue(app?.contains("invalidateParentLetterResources(reason: excluded ? \"sessionExcluded\" : \"sessionIncluded\")") == true)
        expectTrue(app?.contains("self.invalidateParentLetterResources(reason: ok ? \"recordsCleared\" : \"recordsClearFailed\")") == true)
    }

    /// Review finding 4: a corrupt v2 says letter games are suspended and need repair.
    func testLetterStatusTextNamesCorruptRepair() {
        let saved = LetterSelectionSettings.defaults
        expectEqual(LetterPickerStatus.text(load: .fresh, hasDraft: false, hasChanges: false), "載入中…")
        expectEqual(LetterPickerStatus.text(load: .fresh, hasDraft: true, hasChanges: false), "未儲存 · 而家用緊舊設定")
        expectEqual(LetterPickerStatus.text(load: .legacy(saved, 4), hasDraft: true, hasChanges: false), "未儲存 · 而家用緊舊設定")
        expectEqual(LetterPickerStatus.text(load: .repairV1, hasDraft: true, hasChanges: false), "未儲存 · 而家用緊舊設定")
        expectEqual(LetterPickerStatus.text(load: .fresh, hasDraft: true, hasChanges: true), "未儲存")
        expectEqual(LetterPickerStatus.text(load: .saved(saved), hasDraft: true, hasChanges: false), "已儲存")
        expectEqual(LetterPickerStatus.text(load: .saved(saved), hasDraft: true, hasChanges: true), "未儲存")
        for changes in [false, true] {
            let corrupt = LetterPickerStatus.text(load: .corruptV2, hasDraft: true, hasChanges: changes)
            expectTrue(corrupt.contains("暫停") && corrupt.contains("修復"), corrupt)
            expectFalse(corrupt.contains("舊設定"), "corrupt v2 never claims the old settings are in use")
            expectTrue(isTraditionalChineseOnly(corrupt) && perfTraditionalOnly(corrupt))
        }
    }
}

// MARK: Build 79 — UX review (style/copy only; behaviour unchanged from 78)

extension LetterPickerTests {
    /// UX m5/n2: bilingual status words and one loading wording.
    func testLetterStatusEnglishAndLoadingWording() {
        let saved = LetterSelectionSettings.defaults
        func both(_ load: LetterSelectionLoad, _ draft: Bool, _ changes: Bool) -> (String, String) {
            (LetterPickerStatus.text(load: load, hasDraft: draft, hasChanges: changes),
             LetterPickerStatus.english(load: load, hasDraft: draft, hasChanges: changes))
        }
        expectTrue(both(.fresh, false, false) == ("載入中…", "Loading…"))
        expectTrue(both(.fresh, true, false) == ("未儲存 · 而家用緊舊設定", "Unsaved · using the previous settings"))
        expectTrue(both(.saved(saved), true, false) == ("已儲存", "Saved"))
        expectTrue(both(.saved(saved), true, true) == ("未儲存", "Unsaved"))
        expectTrue(both(.corruptV2, true, false).1.contains("repair needed"))
        expectTrue(both(.corruptV2, true, true).1.contains("paused"))
        expectEqual(LetterPickerStatus.loadingLetters, "字母卡載入中…")
        expectTrue(LetterPickerStatus.loadingLetters.hasSuffix("…") && LetterPickerStatus.loadingLettersEnglish.hasSuffix("…"))
        let card = (try? String(contentsOfFile: "Sources/VisaGames/ParentTapLetterSettingsView.swift", encoding: .utf8)) ?? ""
        expectFalse(card.contains("載入中。"), "one loading punctuation")
        expectFalse(card.contains("\"字母卡載入中"), "the card uses LetterPickerStatus.loadingLetters")
    }

    /// UX m4: presets carry an English sub-line; the shared preset type stays source-compatible.
    func testPresetSubtitles() throws {
        let bank = try LetterWordBank.load(url: URL(fileURLWithPath: "Resources/LetterTap/starter-bank.json"))
        let picker = LetterAvailability.pickerModel(bank: bank, decks: .init(), enabled: [])
        expectEqual(picker.presets.map(\.subtitle), ["ABC group · 5 letters", "ABC group · 5 letters"])
        expectEqual(picker.presets.map(\.label), ["a b c d e", "f g h i j"])
        expectEqual(PracticePickerPreset(id: "x", label: "X", itemIDs: ["a"]).subtitle, "")
        // The fghij sub-line names its omitted letters from the same preview the apply step uses.
        expectEqual(picker.previewPreset("fghij")?.omittedIDs, ["i", "j"])
    }

    /// UX m1/M4/m2/m3/m6/m7/m8/m9/M1/M2/M3/n1–n4: app-target guards (SwiftUI is not compiled offline).
    func testBuild79PickerUXSourceGuards() throws {
        func source(_ path: String) throws -> String { try String(contentsOfFile: path, encoding: .utf8) }
        let card = try source("Sources/VisaGames/ParentTapLetterSettingsView.swift")
        let picker = try source("Sources/VisaGames/ParentPracticeItemPicker.swift")
        let controls = try source("Sources/VisaGames/ParentPickerControls.swift")
        let ticket = try source("Sources/VisaGames/LetterUnavailableTicketView.swift")
        // M1 / M2: no stock macOS buttons, toggles or disclosure groups in the picker panel.
        for (name, text) in [("card", card), ("picker", picker)] {
            for banned in [".bordered", "DisclosureGroup", "Toggle(", "Button(\"", "Button(state."] {
                expectFalse(text.contains(banned), "\(name) must not use \(banned)")
            }
        }
        expectTrue(controls.contains("struct ParentDisclosureButton") && controls.contains("打開 / Show")
                   && controls.contains("收埋 / Hide") && controls.contains(".contentShape(Rectangle())"))
        // Build 80: Carter's 開／關 via the shared ParentToggleCopy (was 開 / 熄 in 79).
        expectTrue(controls.contains("ParentToggleCopy.pill(on)"))
        expectTrue(picker.contains("ParentDisclosureButton(title: secondaryPresetTitle"))
        expectTrue(card.contains("ParentDisclosureButton(title: \"更多字母設定\""))
        expectTrue(card.contains("ParentOnOffRow("))
        expectTrue(card.contains("ParentChoiceButton(title: \"\\(ParentToggleCopy.off) · 只練揀咗嘅\""))
        expectTrue(picker.contains("ChunkyButtonStyle(fill: state.fill"))
        // M4: lamp + ✓ when lit, and the selected-but-unavailable warning state.
        expectTrue(picker.contains("Image(systemName: \"lightbulb.fill\")\n                Image(systemName: \"checkmark\")"))
        expectTrue(picker.contains("case selectedUnavailable") && picker.contains("\"已揀・暫停\"")
                   && picker.contains("Selected · unavailable") && picker.contains("Palette.tomato"))
        // m1: nine columns of 84 pt fill the card's 820 pt inner width exactly (8 pt gaps).
        expectTrue(card.contains("private static let columns = 9"))
        expectTrue(picker.contains("static let tileWidth: CGFloat = 84") && picker.contains("static let tileSpacing: CGFloat = 8"))
        expectEqual(9 * 84 + 8 * 8, Int(ParentGridColumns.parentContentWidth(viewportWidth: 1905)) - 2 * 16)
        // m2: the legend uses the specified copy and the tiles' own marks.
        for text in ["亮起＝已揀", "暗色＝未揀", "鎖住＝未開放", "Lit = enabled; dim = off; locked = not ready.",
                     "ParentPickerLamp(state: state, size: 10)"] {
            expectTrue(picker.contains(text), text)
        }
        // m3: 睇吓練習建議 is the disabled fourth preset, not a stray button.
        expectTrue(card.contains("placeholderAction: ParentPickerPlaceholderAction(") && card.contains("title: \"睇吓練習建議\""))
        expectTrue(picker.contains(".disabled(true)"))
        // m6 / m7: unsaved note and the 940 pt bar column.
        expectTrue(card.contains("未儲存嘅改動唔會套用。") && card.contains("Unsaved changes will not apply."))
        expectTrue(card.contains(".frame(maxWidth: 940)") && card.contains(".frame(height: 116)"))
        // m8 / m9 / n1: 下局, the count badge with the 3–5 hint, spoken HK Cantonese.
        for banned in ["下一題", "下一局", "請檢查後選擇修復", "已選擇修復", "尚未提供", "儲存前必須移除", "未能讀取"] {
            expectFalse(card.contains(banned) || picker.contains(banned), "copy: \(banned)")
        }
        expectTrue(card.contains("ParentPill(text: \"已揀 \\(count) 個 / \\(count) selected\""))
        expectTrue(card.contains("想集中練習，可以先揀 3–5 個"))
        // n2 / n4: reserved loading layout; outlined summary panel.
        expectTrue(card.contains("ParentPracticeItemPickerPlaceholder(") && picker.contains("struct ParentPracticeItemPickerPlaceholder"))
        expectTrue(card.contains(".modifier(ChunkyPanel(fill: .white, cornerRadius: 12, shadowDepth: 3, lineWidth: 2))"))
        expectFalse(card.contains("Color.white.opacity(0.7)"))
        // M3: the child board scales with the stage and pairs HK Cantonese with English.
        expectTrue(ticket.contains("DesignTokens.stageLayout(") && ticket.contains("CanvasText(\"呢張遊戲票暫時玩唔到\""))
        expectTrue(ticket.contains("This ticket can't be played right now."))
        expectTrue(ticket.contains(".allowsHitTesting(false)"))
        expectFalse(ticket.contains(".font(.system(size: 64))") || ticket.contains("CanvasFont.font(size: 34"))
        // HK Traditional only, never Simplified.
        for (name, text) in [("card", card), ("picker", picker), ("controls", controls), ("ticket", ticket)] {
            expectTrue(isTraditionalChineseOnly(text) && perfTraditionalOnly(text), "\(name) is Traditional only")
        }
    }
}

// MARK: Build 80 — remaining picker minors/nits (Carter 2026-11-05 18:58 HKT); copy/layout only

extension LetterPickerTests {
    private func appSource(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    /// Item 1: one 開／關 wording for every parent toggle; no 熄 left in parent UI sources.
    func testParentToggleWordingIsOpenClose() {
        expectEqual(ParentToggleCopy.on, "開")
        expectEqual(ParentToggleCopy.off, "關")
        expectEqual(ParentToggleCopy.pill(true), "開 On")
        expectEqual(ParentToggleCopy.pill(false), "關 Off")
        expectEqual(TapCountCopy.on, ParentToggleCopy.on)
        expectEqual(TapCountCopy.off, ParentToggleCopy.off)
        expectEqual(StrokeOrderCopy.short(.off), "關")
        expectTrue(StrokeOrderCopy.detail(.off).hasPrefix("關："))
        let parentUI = ["Sources/VisaGames/ParentTapLetterSettingsView.swift", "Sources/VisaGames/ParentPracticeItemPicker.swift",
                        "Sources/VisaGames/ParentPickerControls.swift", "Sources/VisaGames/ParentShapeTraceSettingsView.swift",
                        "Sources/VisaGames/ParentTapCountSettingsView.swift", "Sources/VisaGames/ParentYouTubeBrowserView.swift",
                        "Sources/VisaGames/ParentSettingsView.swift", "Sources/VisaCore/LetterPickerSaveCheck.swift",
                        "Sources/VisaCore/StrokeOrder.swift"]
        for path in parentUI {
            let text = appSource(path)
            expectFalse(text.isEmpty, path)
            expectFalse(text.contains("熄"), "\(path) uses 開／關, not 熄")
        }
        for path in ["Sources/VisaGames/ParentPickerControls.swift", "Sources/VisaGames/ParentShapeTraceSettingsView.swift"] {
            expectTrue(appSource(path).contains("ParentLabel(ParentToggleCopy.pill(on)"), path)
        }
        expectTrue(appSource("Sources/VisaGames/ParentTapCountSettingsView.swift").contains("TapCountCopy.off) Off"))
    }

    /// Items 2 and 7: group/count sub-lines on every preset; a partial group's headline shows
    /// only its ready letters (mockup 01 「f g h」), while IDs, items and applying are unchanged.
    func testPresetHeadlinesSourcesAndOmissions() throws {
        let bank = try LetterWordBank.load(url: URL(fileURLWithPath: "Resources/LetterTap/starter-bank.json"))
        let picker = LetterAvailability.pickerModel(bank: bank, decks: .init(), enabled: [])
        expectEqual(picker.presets.map(\.id), ["abcde", "fghij"])
        expectEqual(picker.presets.map(\.itemIDs), [Array("abcde").map(String.init), Array("fghij").map(String.init)])
        expectEqual(picker.label(forPreset: "abcde"),
                    PracticePickerPresetLabel(headline: "a b c d e", source: "ABC group · 5 letters", omitted: ""))
        expectEqual(picker.label(forPreset: "fghij"),
                    PracticePickerPresetLabel(headline: "f g h", source: "ABC group · 5 letters", omitted: "i、j"))
        expectEqual(picker.previewPreset("fghij")?.includedIDs, ["f", "g", "h"], "applying is unchanged")
        expectTrue(picker.label(forPreset: "missing") == nil)
        // A named (not list-style) preset keeps its name; a fully locked list keeps its label.
        let named = PracticePickerModel(catalogID: "t", catalogRevision: "1",
            items: ["a", "i"].map { PracticePickerItem(id: $0, label: $0, role: .target) },
            availabilityByItem: ["a": PracticePickerAvailability(consumers: ["find"]),
                                 "i": PracticePickerAvailability(consumers: [])],
            enabledIDs: [],
            presets: [PracticePickerPreset(id: "p90", label: "近 90 日練過", subtitle: "Practised in 90 days", itemIDs: ["a", "i"]),
                      PracticePickerPreset(id: "locked", label: "i", subtitle: "x", listsItems: true, itemIDs: ["i"])],
            minimum: 1, maximum: 26)
        expectEqual(named.label(forPreset: "p90"),
                    PracticePickerPresetLabel(headline: "近 90 日練過", source: "Practised in 90 days", omitted: "i"))
        expectEqual(named.label(forPreset: "locked")?.headline, "i")
        let card = appSource("Sources/VisaGames/ParentTapLetterSettingsView.swift")
        expectTrue(card.contains("subtitle: \"\\(title) \\(index + 1) · \\(letters.count) letters\", listsItems: true"))
        expectTrue(card.contains("label: \"近 90 日練過\", subtitle: \"Practised in 90 days\""))
        let pickerView = appSource("Sources/VisaGames/ParentPracticeItemPicker.swift")
        expectTrue(pickerView.contains("model.label(forPreset: preset.id)"))
        expectTrue(pickerView.contains("presetLabel(title: wording.headline, subtitle: wording.source, note: note)"))
    }

    /// Item 3: every block reason, storage error and save notice has an English line; which
    /// reason applies (and its HK Chinese text) is unchanged.
    func testSaveMessagesAreBilingual() throws {
        let validation: [LetterSelectionSettings.ValidationError] = [
            .emptyFocus, .tooMany, .invalidLetter, .unavailableFocus, .noWriteTargets,
            .insufficientBoardLetters, .invalidReview, .invalidOrder, .invalidSchema
        ]
        let storage: [LetterSelectionSettingsStore.StoreError] = [.notParent, .corruptStored, .writeFailed]
        var messages = validation.map { LetterPickerSaveCheck.message(for: $0) } + storage.map { LetterPickerSaveCheck.message(for: $0) }
        for error in validation { expectEqual(LetterPickerSaveCheck.message(for: error).zh, LetterPickerSaveCheck.reason(for: error)) }
        for error in storage { expectEqual(LetterPickerSaveCheck.message(for: error).zh, LetterPickerSaveCheck.reason(for: error)) }
        messages += [LetterPickerSaveCheck.loading, LetterPickerSaveCheck.bankUnavailable, LetterPickerSaveCheck.checkFailed,
                     LetterPickerSaveCheck.saved, LetterPickerSaveCheck.saveFailed]
        for message in messages {
            expectFalse(message.zh.isEmpty || message.en.isEmpty, message.zh)
            expectTrue(isTraditionalChineseOnly(message.zh) && perfTraditionalOnly(message.zh), message.zh)
            expectFalse(message.zh.contains("熄"), message.zh)
        }
        expectEqual(Set(messages.map(\.en)).count, messages.count, "one English line per message")
        expectEqual(LetterPickerSaveCheck.saved, LetterPickerMessage(zh: "儲存咗，下局開始用。", en: "Saved. Applies next round."))
        // evaluate carries the English line with the same reason.
        let bank = try LetterWordBank.load(url: URL(fileURLWithPath: "Resources/LetterTap/starter-bank.json"))
        let ready = LetterAvailability.resolve(bank: bank, decks: .init())
        var empty = LetterSelectionSettings.defaults
        empty.focusLetters = []
        let blocked = LetterPickerSaveCheck.evaluate(empty, availability: ready, writingAssigned: true,
                                                     allowedReview: [], load: .fresh, repairCorruptV2: false)
        expectEqual(blocked.reason, LetterPickerSaveCheck.reason(for: .emptyFocus))
        expectEqual(blocked.message, LetterPickerSaveCheck.message(for: .emptyFocus))
        expectEqual(LetterPickerSaveCheck.evaluate(.defaults, availability: ready, writingAssigned: true, allowedReview: [],
                                                   load: .fresh, repairCorruptV2: false, bankAvailable: false).message,
                    LetterPickerSaveCheck.bankUnavailable)
        expectTrue(LetterPickerSaveCheck.evaluate(.defaults, availability: ready, writingAssigned: true, allowedReview: [],
                                                  load: .fresh, repairCorruptV2: false).message == nil)
        let card = appSource("Sources/VisaGames/ParentTapLetterSettingsView.swift")
        for text in ["@Published private(set) var notice: LetterPickerMessage?", "notice = saveCheck.message",
                     "notice = LetterPickerSaveCheck.saved", "notice = LetterPickerSaveCheck.saveFailed",
                     "if let message = state.saveCheck.message ?? state.notice", "ParentLabel(message.en, size: 11"] {
            expectTrue(card.contains(text), text)
        }
        expectTrue(appSource("Sources/VisaGames/AppDelegate.swift")
            .contains("請先揀可寫嘅字母。 / Find & write can't play with these letters yet."))
    }

    /// Item 4: loading draws the whole loaded card structure (picker blocks, note slot, footnote,
    /// summary, review, more settings, footer) from the settings the draft will start from.
    func testLoadingReservesTheWholeLoadedCard() {
        let card = appSource("Sources/VisaGames/ParentTapLetterSettingsView.swift")
        let picker = appSource("Sources/VisaGames/ParentPracticeItemPicker.swift")
        expectTrue(card.contains("belowGrid(sections, interactive: true)"))
        expectTrue(card.contains("belowGrid(provisionalSections, interactive: false)"))
        // Provisional sections come from the same source the state's draft uses.
        expectTrue(card.contains("let value = model.letterParentLoad.effective ?? .defaults"))
        expectTrue(card.contains("draft = LetterPickerDraft(saved: model.letterParentLoad.effective ?? .defaults)"))
        guard let below = card.range(of: "private func belowGrid("),
              let end = card.range(of: "private func summary(", range: below.upperBound..<card.endIndex) else {
            expectTrue(false, "belowGrid"); return
        }
        let section = card[below.lowerBound..<end.lowerBound]
        for part in ["有玩過，唔代表已經熟晒。", "summary(sections)", "reviewControls(sections)", "moreSettings(sections)",
                     "儲存、取消同還原喺頁頂。"] {
            expectTrue(section.contains(part), part)
        }
        expectTrue(card.contains(".frame(minHeight: reserved)"))
        // Picker blocks have fixed heights and the placeholder reserves the same note slot.
        expectTrue(picker.contains(".frame(height: ParentPickerMetrics.presetHeight)"))
        expectTrue(picker.contains("static let noteSlotHeight: CGFloat = 38"))
        expectTrue(picker.contains(".frame(height: ParentPickerMetrics.noteSlotHeight, alignment: .topLeading)"))
        // Fix round 1: both note slots and the summary status row are always reserved.
        expectTrue(picker.contains("ParentPickerNotes(notes: [])"))
        expectTrue(picker.contains("return ParentPickerNotes(notes: notes)"))
        expectTrue(picker.contains("static let noteSlotCount = 2"))
        expectTrue(picker.contains(".frame(height: ParentPickerMetrics.notesHeight, alignment: .topLeading)"))
        expectTrue(card.contains("summaryStatus(summary, showRecovery: summary.writeEmpty && writeAssigned)"))
        expectTrue(card.contains(".frame(height: Self.statusRowHeight)"))
        expectTrue(card.contains("Sections(summary: LetterSelectionSummary(focus: value.focusLetters, capabilities: state.capabilities)"))
        expectTrue(card.contains("Sections(summary: .loading(focus: value.focusLetters)"))
        expectFalse(card.contains("if !sections.findOnly.isEmpty"), "no conditional warnings block")
        expectFalse(card.contains("if sections.write.isEmpty"), "no conditional recovery block")
        // Loading stays off the main thread (unchanged from 78).
        expectTrue(card.contains("model.withLetterPickerResources"))
    }

    /// Item 5: the 15 letters without authored paths get a parent-only rounded-font fallback;
    /// child rendering and readiness are untouched.
    func testParentLetterSymbolFallback() {
        let missing = Array("abcdefghijklmnopqrstuvwxyz").filter { letter in
            LatinGlyphs.paths(letter, offset: LineMatchPoint(x: 0, y: 0), scale: 1).isEmpty
        }
        expectEqual(String(missing), "ijlmnpqrstvwxyz")
        for letter in "abcdefghijklmnopqrstuvwxyz" {
            expectEqual(LatinGlyphs.hasPaths(String(letter)), !missing.contains(letter), String(letter))
        }
        expectFalse(LatinGlyphs.hasPaths("ab") || LatinGlyphs.hasPaths(""))
        let card = appSource("Sources/VisaGames/ParentTapLetterSettingsView.swift")
        expectTrue(card.contains("struct ParentLetterSymbol: View") && card.contains("if LatinGlyphs.hasPaths(letter) {"))
        expectTrue(card.contains("Text(letter)\n                .font(CanvasFont.font(size: fallbackSize, weight: 700))"))
        expectTrue(card.contains("ParentLetterSymbol(letter: item.label, fallbackSize: 34)"))
        expectTrue(card.contains("ParentLetterSymbol(letter: letter, fallbackSize: 16)"))
        for child in ["Sources/VisaGames/TapLetterBoardView.swift", "Sources/VisaGames/CanvasActivityHost.swift"] {
            let text = appSource(child)
            expectFalse(text.contains("ParentLetterSymbol") || text.contains("hasPaths"), "\(child) unchanged")
        }
    }

    /// Item 6: the suggestion button says it isn't in this build; it never implies unlocking.
    func testSuggestionCopySaysNotInThisBuild() {
        let card = appSource("Sources/VisaGames/ParentTapLetterSettingsView.swift")
        expectTrue(card.contains("呢個版本未有練習建議。/ Review suggestions aren't available in this build."))
        expectTrue(card.contains("note: \"呢個版本未有 · Not in this build\""))
        for banned in ["要等有足夠", "need enough practice records", "Review suggestions · 未開放"] {
            expectFalse(card.contains(banned), banned)
        }
        expectTrue(appSource("Sources/VisaGames/ParentPracticeItemPicker.swift").contains(".disabled(true)"))
    }
}

// MARK: Build 80 fix round 1

extension LetterPickerTests {
    /// Fix 1: one summary layout for any selection. The rows reserve the whole focus set and
    /// every warning shares one status line, so default and unavailable selections (e.g. a
    /// legacy f–j week with i/j not ready) keep the loading card's height.
    func testLetterSummaryKeepsOneLayoutForAnySelection() throws {
        let bank = try LetterWordBank.load(url: URL(fileURLWithPath: "Resources/LetterTap/starter-bank.json"))
        let ready = LetterAvailability.resolve(bank: bank, decks: .init())
        let abcde = Array("abcde").map(String.init)
        let defaults = LetterSelectionSummary(focus: abcde, capabilities: ready)
        expectEqual(defaults.find, abcde)
        expectEqual(defaults.write, abcde)
        expectFalse(defaults.hasWarning || defaults.writeEmpty)
        expectEqual(defaults.status, LetterPickerMessage(zh: "兩個遊戲都可以用呢組字母。", en: "Both letter games can use these letters."))
        // Astra's example through the real legacy path: v1 week f–j, i and j not ready.
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        suite.set(try JSONEncoder().encode(TapLetterSettings(thisWeek: Array("fghij").map(String.init))),
                  forKey: TapLetterSettingsStore.key)
        guard case .legacy(let legacyDraft, _) = LetterSelectionSettingsStore(defaults: suite).load() else {
            expectTrue(false, "legacy load"); return
        }
        let legacy = LetterSelectionSummary(focus: legacyDraft.focusLetters, capabilities: ready)
        expectEqual(legacy.focus, Array("fghij").map(String.init))
        expectEqual(legacy.unavailable, ["i", "j"])
        expectEqual(legacy.find, ["f", "g", "h"])
        expectEqual(legacy.write, ["f", "g", "h"])
        expectEqual(legacy.status, LetterPickerMessage(zh: "已揀・暫停：i、j，儲存之前要移除。",
                                                       en: "Selected · unavailable: i, j — remove before saving."))
        // Nothing writable, and find-only letters: still one status line.
        let ij = LetterSelectionSummary(focus: ["i", "j"], capabilities: ready)
        expectTrue(ij.writeEmpty)
        expectEqual(ij.status.zh, "已揀・暫停：i、j，儲存之前要移除；呢組暫時玩唔到『搵完寫』。")
        expectEqual(ij.status.en, "Selected · unavailable: i, j — remove before saving. This set can't play Find & write yet.")
        var findOnlyReady = ready
        findOnlyReady["a"] = LetterCapability(canDisplay: true, canFind: true, canWrite: false)
        let a = LetterSelectionSummary(focus: ["a"], capabilities: findOnlyReady)
        expectEqual(a.findOnly, ["a"])
        expectEqual(a.status.zh, "a 暫時只可以搵，未可以寫；呢組暫時玩唔到『搵完寫』。")
        // The loading stand-in has the same layout inputs as every loaded outcome.
        let all = Array("abcdefghijklmnopqrstuvwxyz").map(String.init)
        for focus in [abcde, legacyDraft.focusLetters, ["i", "j"], ["a"], all] {
            let loading = LetterSelectionSummary.loading(focus: focus)
            expectFalse(loading.resolved || loading.hasWarning || loading.writeEmpty)
            expectEqual(loading.status, LetterPickerSaveCheck.loading)
            for capabilities in [ready, findOnlyReady, [:]] {
                let loaded = LetterSelectionSummary(focus: focus, capabilities: capabilities)
                expectEqual(loading.chipRows, loaded.chipRows)
                expectTrue(loaded.find.count <= focus.count && loaded.write.count <= focus.count)
            }
        }
        expectEqual(LetterSelectionSummary.loading(focus: all).chipRows, 2)
        for summary in [defaults, legacy, ij, a] {
            expectTrue(isTraditionalChineseOnly(summary.status.zh) && perfTraditionalOnly(summary.status.zh))
        }
    }

    /// Fix 2: Carter's 開／關 in the weekly report, report HTML and CSV notes too; the Python
    /// reference generators say the same, and the goldens (which never turn anything off) still
    /// match byte for byte in the golden checks.
    func testReportOffWordingIsOpenClose() {
        expectEqual(WeeklyTemplates.byID["setting.off"]?.zh, "關咗「{game}」{stars}")
        expectEqual(WeeklyTemplates.byID["setting.on"]?.zh, "開咗「{game}」{stars}")
        expectEqual(WeeklyReportLabels.table["assign.off"]?.zh, "{date}關咗「{game}」{stars}。")
        expectEqual(WeeklyReportLabels.table["assign.on"]?.zh, "{date}開咗「{game}」{stars}。")
        let fixtures = "Tests/VisaCoreTests/Fixtures/weekly-ranking-5.6"
        expectTrue(appSource("\(fixtures)/reference_text.py").contains("\"setting.off\": (\"關咗「{game}」{stars}\""))
        expectTrue(appSource("\(fixtures)/reference_html.py").contains("\"assign.off\": (\"{date}關咗「{game}」{stars}。\""))
        let templates = appSource("Sources/VisaCore/WeeklyTextTemplates.swift")
        expectEqual(templates.components(separatedBy: "WeeklyWords(ParentToggleCopy.off, \"Off\")").count - 1, 2)
        expectTrue(appSource("Sources/VisaCore/WeeklyReportHTML.swift").contains("$0.isEmpty ? ParentToggleCopy.off : $0"))
        expectTrue(appSource("Sources/VisaCore/PerformanceCSV.swift").contains("小朋友冇辦法中途關片"))
        // No 熄 anywhere in the sources, the reference generators or the goldens.
        var scanned = 0
        for root in ["Sources", "Tests/VisaCoreTests/Fixtures"] {
            guard let walker = FileManager.default.enumerator(atPath: root) else { expectTrue(false, root); continue }
            for case let path as String in walker
            where [".swift", ".py", ".json", ".html", ".md"].contains(where: { path.hasSuffix($0) }) {
                scanned += 1
                expectFalse(appSource("\(root)/\(path)").contains("熄"), "\(root)/\(path)")
            }
        }
        expectTrue(scanned > 50, "scanned \(scanned) files")
    }
}

private final class LetterBankLoadCounter: @unchecked Sendable {
    var loads = 0
    var failNext = true
}

private struct LetterBankLoadFailure: Error {}
