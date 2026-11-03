import Foundation

/// Call before ActivityCatalog.kind(forRoundSeed:pool:), whose empty-pool legacy fallback is unsafe here.
public enum LetterTicketEligibility {
    public static func eligible(_ pool: [ActivityKind], settings: LetterSelectionSettings,
                                bank: LetterWordBank, decks: LetterWordDecks,
                                progress: LetterProgress) -> [ActivityKind] {
        let availability = LetterAvailability.resolve(bank: bank, decks: decks)
        let legal = availability.filter { $0.value.canFind }.map(\.key)
        return pool.filter { kind in
            !kind.isTapLetterFamily || settings.focus(for: kind, availability: availability).contains { letter in
                LetterBoardBuilder.makeScoped(seed: "eligibility", target: letter,
                    mirrorGuard: settings.mirrorGuard, progress: progress, legalLetters: legal) != nil
            }
        }
    }
}
