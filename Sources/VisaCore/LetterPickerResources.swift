import Foundation

/// One parent visit's immutable letter inputs. Building it reads disk (bank JSON and the
/// performance event store), so the host builds it off the main thread. Opening the
/// editor, checking a draft and Save all use this one value, so the Save check and the
/// persisted validation see the same capabilities and history.
public struct LetterPickerResources: Sendable {
    /// Nil when the bundled bank could not be read; Save stays unavailable then.
    public let picker: PracticePickerModel?
    public let capabilities: [String: LetterCapability]
    /// Letters the child practised in the last 90 days (the only legal review pool).
    public let history: [String]

    public var bankAvailable: Bool { picker != nil }

    public init(bank: LetterWordBank?, decks: LetterWordDecks, history: [String]) {
        let ready = bank.map { LetterAvailability.resolve(bank: $0, decks: decks) } ?? [:]
        capabilities = ready
        picker = bank == nil ? nil : LetterAvailability.pickerModel(capabilities: ready, enabled: [])
        self.history = history
    }
}

/// The bundled bank never changes during a launch. The first successful parse is shared
/// by parent snapshots and child deals; a failed parse is not cached and can be retried.
public final class LetterWordBankCache: @unchecked Sendable {
    public static let bundled = LetterWordBankCache()

    private let lock = NSLock()
    private let loader: @Sendable () throws -> LetterWordBank
    private var bank: LetterWordBank?

    public init(loader: @escaping @Sendable () throws -> LetterWordBank = { try LetterWordBank.loadBundled() }) {
        self.loader = loader
    }

    /// The first call parses JSON: warm it off the main thread at launch. The lock is
    /// held through the parse so concurrent first callers share one parse.
    public func load() throws -> LetterWordBank {
        lock.lock()
        defer { lock.unlock() }
        if let bank { return bank }
        let loaded = try loader()
        bank = loaded
        return loaded
    }
}
