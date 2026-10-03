import Foundation
import VisaCore

final class MissionGameAssignmentTests {
    func testDefaultsAllStarsOn() {
        let assignment = MissionGameAssignment.allOn
        expectEqual(ActivityCatalog.playableKinds.count, 10)
        for kind in ActivityCatalog.playableKinds {
            for star in ChildDifficulty.allCases {
                expectTrue(assignment.isEnabled(kind, star: star))
            }
            expectFalse(assignment.isHiddenFromMissions(kind))
        }
        for star in ChildDifficulty.allCases {
            expectEqual(assignment.pool(for: star), ActivityCatalog.playableKinds)
        }
    }

    func testMultiStarDoesNotClearOthers() {
        var assignment = MissionGameAssignment.allOn
        guard case .updated(let off) = assignment.toggling(.twoPictureChoose, star: .medium) else {
            preconditionFailure("turning off one star must succeed")
        }
        assignment = off
        expectTrue(assignment.isEnabled(.twoPictureChoose, star: .easy))
        expectFalse(assignment.isEnabled(.twoPictureChoose, star: .medium))
        expectTrue(assignment.isEnabled(.twoPictureChoose, star: .challenge))
        expectTrue(assignment.pool(for: .medium).contains(.findTheSame))
        expectFalse(assignment.pool(for: .medium).contains(.twoPictureChoose))
        guard case .updated(let on) = assignment.toggling(.twoPictureChoose, star: .medium) else {
            preconditionFailure("turning the star back on must succeed")
        }
        expectTrue(on.isEnabled(.twoPictureChoose, star: .easy))
        expectTrue(on.isEnabled(.twoPictureChoose, star: .medium))
        expectTrue(on.isEnabled(.twoPictureChoose, star: .challenge))
    }

    func testRejectsEmptyTier() {
        var assignment = MissionGameAssignment.allOn
        let kinds = ActivityCatalog.playableKinds
        for kind in kinds.dropLast() {
            guard case .updated(let next) = assignment.toggling(kind, star: .easy) else {
                preconditionFailure("off while another kind remains")
            }
            assignment = next
        }
        let before = assignment
        expectEqual(assignment.toggling(kinds[kinds.count - 1], star: .easy), .rejectedLastStar)
        expectEqual(assignment, before)
        expectEqual(assignment.pool(for: .easy), [kinds[kinds.count - 1]])
        // Other stars untouched.
        expectEqual(assignment.pool(for: .challenge).count, 10)
    }

    func testHiddenKindLeavesOtherStarsIntact() {
        var assignment = MissionGameAssignment.allOn
        for star in ChildDifficulty.allCases {
            guard case .updated(let next) = assignment.toggling(.emptyBay, star: star) else {
                preconditionFailure("hiding one kind must succeed")
            }
            assignment = next
        }
        expectTrue(assignment.isHiddenFromMissions(.emptyBay))
        for star in ChildDifficulty.allCases {
            expectFalse(assignment.pool(for: star).contains(.emptyBay))
            expectEqual(assignment.pool(for: star).count, 9)
        }
    }

    func testCorruptOrMissingStoreFallsBackAllOn() {
        let suite = "VisaGames.assignment.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = MissionGameAssignmentStore(defaults: defaults)
        expectEqual(store.load(), MissionGameAssignment.allOn)
        defaults.set(Data("not-json".utf8), forKey: MissionGameAssignmentStore.key)
        expectEqual(store.load(), MissionGameAssignment.allOn)
        defaults.set(Data("{}".utf8), forKey: MissionGameAssignmentStore.key)
        expectEqual(store.load(), MissionGameAssignment.allOn)
        defaults.removePersistentDomain(forName: suite)
    }

    func testUnseenKindOptsIntoAllStars() {
        var enabled = MissionGameAssignment.allOn.enabledStars
        enabled.removeValue(forKey: .shadowMatch)
        let assignment = MissionGameAssignment(enabledStars: enabled).normalized()
        for star in ChildDifficulty.allCases {
            expectTrue(assignment.isEnabled(.shadowMatch, star: star))
        }
        expectTrue(assignment.pool(for: .easy).contains(.shadowMatch))
    }

    func testEmptyStarFallsBackToAllPlayable() {
        let onlyHard = Set<ChildDifficulty>([.medium, .challenge])
        var enabled: [ActivityKind: Set<ChildDifficulty>] = [:]
        for kind in ActivityCatalog.playableKinds {
            enabled[kind] = onlyHard
        }
        let assignment = MissionGameAssignment(enabledStars: enabled).normalized()
        expectEqual(assignment.pool(for: .easy), ActivityCatalog.playableKinds)
        expectEqual(assignment.pool(for: .medium).count, 10)
        expectFalse(assignment.pool(for: .medium).isEmpty)
    }

    func testRotationStaysInsidePool() {
        var assignment = MissionGameAssignment.allOn
        let keep: Set<ActivityKind> = [.findTheSame, .countVehicles]
        for kind in ActivityCatalog.playableKinds where !keep.contains(kind) {
            guard case .updated(let next) = assignment.toggling(kind, star: .easy) else {
                preconditionFailure("pool shrink")
            }
            assignment = next
        }
        let pool = assignment.pool(for: .easy)
        expectEqual(Set(pool), keep)
        var seen = Set<ActivityKind>()
        for i in 0..<80 {
            let kind = ActivityCatalog.kind(forRoundSeed: "star-pool-\(i)", pool: pool)
            expectTrue(pool.contains(kind))
            seen.insert(kind)
        }
        expectEqual(seen, keep)
        // Unrestricted hash still covers the full catalog.
        var all = Set<ActivityKind>()
        for i in 0..<200 {
            all.insert(ActivityCatalog.kind(forRoundSeed: "round-\(i)"))
        }
        expectEqual(all, Set(ActivityCatalog.playableKinds))
        expectEqual(ActivityCatalog.kind(forRoundSeed: "seed-alpha", pool: []), ActivityCatalog.kind(forRoundSeed: "seed-alpha"))
    }

    func testParentCardNamesAreTraditionalAndUnbuiltAreNotKinds() {
        expectEqual(ActivityKind.allCases.count, 10)
        expectEqual(ActivityKind.twoPictureChoose.parentCardTitle, "邊架消防車")
        expectEqual(ActivityKind.findTheSame.parentShortLabel, "搵相同")
        expectEqual(ActivityKind.emptyBay.parentCardEnglish, "Empty parking bay")
        expectTrue(ActivityKind.countVehicles.parentHelpTraditionalChinese.contains("數"))
        let banned = ["游戏", "视频", "设置", "哪辆", "连点"]
        for kind in ActivityKind.allCases {
            let blob = kind.parentCardTitle + kind.parentShortLabel + kind.parentHelpTraditionalChinese
            for word in banned {
                expectFalse(blob.contains(word))
            }
            expectFalse(kind.parentCardTitle.isEmpty)
            expectFalse(kind.parentHeroAssetIDs.isEmpty)
        }
        expectEqual(ActivityCatalog.unbuiltParentActivities.count, 4)
        expectEqual(ActivityCatalog.unbuiltParentActivities.map(\.traditionalChinese), ["描線", "迷宮", "形狀分類", "連點"])
        expectEqual(ActivityCatalog.stubKinds, [])
        expectTrue(MissionGameAssignment.emptyTierBanner.contains("每個星級至少要有一個遊戲"))
        expectTrue(MissionGameAssignment.emptyTierBanner.contains("Each star needs at least one game"))
    }

    func testStoreRoundTripDoesNotUseRewardSnapshot() {
        let suite = "VisaGames.assignment.round.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        var assignment = MissionGameAssignment.allOn
        guard case .updated(let next) = assignment.toggling(.halfMatch, star: .challenge) else {
            preconditionFailure("toggle")
        }
        assignment = next
        let store = MissionGameAssignmentStore(defaults: defaults)
        store.save(assignment)
        let loaded = MissionGameAssignmentStore(defaults: defaults).load()
        expectEqual(loaded, assignment.normalized())
        expectFalse(loaded.isEnabled(.halfMatch, star: .challenge))
        expectTrue(loaded.isEnabled(.halfMatch, star: .easy))
        expectTrue(MissionGameAssignmentStore.key.contains("missionGameAssignment"))
        expectFalse(MissionGameAssignmentStore.key.contains("state.json"))
        expectFalse(MissionGameAssignmentStore.key == VideoAllowlistStore.key)
        defaults.removePersistentDomain(forName: suite)
    }
}
