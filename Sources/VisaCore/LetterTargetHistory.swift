import Foundation

/// Countable child targets from raw events. Rollups cannot reconstruct letter identities.
public enum LetterTargetHistory {
    public static func practiced(in events: [PerfEvent], at cutoff: Date,
                                 days: Int = 90) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        let start = calendar.date(byAdding: .day, value: 1 - days,
                                 to: calendar.startOfDay(for: cutoff))!
        let excluded = PerfFilter.excludedSessions(in: events.filter { $0.timestamp <= cutoff })
        var rounds = Set<String>()
        var letters = Set<String>()
        for event in PerfCodec.ordered(events) where event.type == .gameDealt &&
            PerfFilter.countable(event, excludedSessions: excluded) &&
            event.timestamp >= start && event.timestamp <= cutoff {
            guard let kind = event.string("kind"),
                  kind == ActivityKind.tapLetterAll.rawValue || kind == ActivityKind.tapLetterWrite.rawValue,
                  let round = event.string("round"), !round.isEmpty,
                  let target = event.string("target"), LetterSelectionSettings.isASCII(target),
                  rounds.insert(round).inserted else { continue }
            letters.insert(target)
        }
        return letters.sorted()
    }
}
