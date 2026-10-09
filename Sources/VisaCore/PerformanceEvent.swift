import Foundation

// MARK: - D10 performance records (v0.20.0, ADR 0008)
//
// One append-only JSON Lines event log, separate from `state.json` and from the text logs.
// Every line is one `PerfEvent`: a fixed envelope plus a flat set of event fields.
// Nothing here touches `Session`, `SnapshotStore` or the reward ledger.

/// A small JSON value so event payloads stay `Sendable`, `Equatable` and schema-tolerant.
public enum PerfValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([PerfValue])
    case object([String: PerfValue])
    case null

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value) where value.isFinite && value == value.rounded() && abs(value) < 1e15:
            return Int(value)
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let value): return value
        case .int(let value): return Double(value)
        default: return nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var arrayValue: [PerfValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: PerfValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// Strings of an array value (non-strings are skipped).
    public var stringArray: [String] {
        (arrayValue ?? []).compactMap(\.stringValue)
    }

    /// Doubles are rounded to 3 decimals so lines stay short and stable.
    public static func seconds(_ value: Double?) -> PerfValue {
        guard let value, value.isFinite else { return .null }
        return .double((value * 1000).rounded() / 1000)
    }

    public static func strings(_ values: [String]) -> PerfValue {
        .array(values.map { .string($0) })
    }

    public static func optionalString(_ value: String?) -> PerfValue {
        value.map { .string($0) } ?? .null
    }

    public static func optionalInt(_ value: Int?) -> PerfValue {
        value.map { .int($0) } ?? .null
    }

    public static func optionalBool(_ value: Bool?) -> PerfValue {
        value.map { .bool($0) } ?? .null
    }
}

extension PerfValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([PerfValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: PerfValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value.isFinite ? value : 0)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

/// Event types of schema v1. Unknown names still decode (as `.unknown`) so a newer
/// writer never breaks an older reader.
public enum PerfEventType: Sendable, Equatable, Hashable {
    case appLaunch, appTerminate, sessionStart
    case parentEnter, parentLeave, uatMode
    case gameDealt, answerAttempt, hintShown, roundResult
    case visaStart, visaEnd
    case pickerVisit, videoImpressions, videoPick
    case resumeOffered, resumeUsed
    case videoStart, videoProgress, videoEnd
    case allowlistChange, configChange
    case statsExclude, statsInclude, statsMarker, clockJump
    case unknown(String)

    public static let known: [PerfEventType] = [
        .appLaunch, .appTerminate, .sessionStart, .parentEnter, .parentLeave, .uatMode,
        .gameDealt, .answerAttempt, .hintShown, .roundResult, .visaStart, .visaEnd,
        .pickerVisit, .videoImpressions, .videoPick, .resumeOffered, .resumeUsed,
        .videoStart, .videoProgress, .videoEnd, .allowlistChange, .configChange,
        .statsExclude, .statsInclude, .statsMarker, .clockJump
    ]

    public var rawValue: String {
        switch self {
        case .appLaunch: return "app_launch"
        case .appTerminate: return "app_terminate"
        case .sessionStart: return "session_start"
        case .parentEnter: return "parent_enter"
        case .parentLeave: return "parent_leave"
        case .uatMode: return "uat_mode"
        case .gameDealt: return "game_dealt"
        case .answerAttempt: return "answer_attempt"
        case .hintShown: return "hint_shown"
        case .roundResult: return "round_result"
        case .visaStart: return "visa_start"
        case .visaEnd: return "visa_end"
        case .pickerVisit: return "picker_visit"
        case .videoImpressions: return "video_impressions"
        case .videoPick: return "video_pick"
        case .resumeOffered: return "resume_offered"
        case .resumeUsed: return "resume_used"
        case .videoStart: return "video_start"
        case .videoProgress: return "video_progress"
        case .videoEnd: return "video_end"
        case .allowlistChange: return "allowlist_change"
        case .configChange: return "config_change"
        case .statsExclude: return "stats_exclude"
        case .statsInclude: return "stats_include"
        case .statsMarker: return "stats_marker"
        case .clockJump: return "clock_jump"
        case .unknown(let raw): return raw
        }
    }

    public init(rawValue: String) {
        self = Self.known.first { $0.rawValue == rawValue } ?? .unknown(rawValue)
    }

    /// Video-surface events. A parent-mode video event is tagged `parent_preview`.
    public var isVideoEvent: Bool {
        switch self {
        case .pickerVisit, .videoImpressions, .videoPick, .resumeOffered, .resumeUsed,
             .videoStart, .videoProgress, .videoEnd:
            return true
        default:
            return false
        }
    }
}

/// Who an event belongs to. Only `child` is ever counted (`PerfFilter`).
public enum PerfActor: String, Sendable, Equatable, CaseIterable, Codable {
    case child
    /// 「家長測試中」 switch on (60-minute auto-off, memory only).
    case parentUAT = "parent_uat"
    /// Picks and watching inside a parent 「測試一分鐘簽證」 visa.
    case parentTestVisa = "parent_test_visa"
    /// Parent game playtest cover (no visa).
    case parentPlaytest = "parent_playtest"
    /// Parent 試播 inline preview.
    case parentPreview = "parent_preview"
    /// Any other parent-mode action.
    case parent
    /// App lifecycle and housekeeping.
    case system
}

/// Fixed envelope + flat fields. Encoded as one JSON object per line (sorted keys).
public struct PerfEvent: Sendable, Equatable {
    public static let schemaVersion = 1
    /// Keys owned by the envelope. Field keys must not collide with these.
    public static let envelopeKeys: Set<String> = [
        "v", "t", "ts", "tz", "mono", "launch", "seq", "app", "actor", "mode", "session"
    ]

    public var v: Int
    public var type: PerfEventType
    /// Wall clock of the event (UTC on disk, ISO-8601 with milliseconds).
    public var timestamp: Date
    /// Local UTC offset when written, e.g. "+08:00".
    public var tz: String
    /// `ProcessInfo.systemUptime` seconds. Durations use this (no wall-clock jumps).
    public var mono: Double
    public var launch: String
    public var seq: Int
    public var app: String
    public var actor: PerfActor
    /// `Session.mode` when the event fired (`setup`, `lock`, `parent`, `play`).
    public var mode: String
    public var session: String
    public var fields: [String: PerfValue]

    public init(
        v: Int = PerfEvent.schemaVersion,
        type: PerfEventType,
        timestamp: Date,
        tz: String,
        mono: Double,
        launch: String,
        seq: Int,
        app: String,
        actor: PerfActor,
        mode: String,
        session: String,
        fields: [String: PerfValue] = [:]
    ) {
        self.v = v
        self.type = type
        self.timestamp = timestamp
        self.tz = tz
        self.mono = mono
        self.launch = launch
        self.seq = seq
        self.app = app
        self.actor = actor
        self.mode = mode
        self.session = session
        self.fields = fields.filter { !Self.envelopeKeys.contains($0.key) }
    }

    public subscript(_ key: String) -> PerfValue? { fields[key] }

    public func string(_ key: String) -> String? { fields[key]?.stringValue }
    public func int(_ key: String) -> Int? { fields[key]?.intValue }
    public func double(_ key: String) -> Double? { fields[key]?.doubleValue }
    public func bool(_ key: String) -> Bool? { fields[key]?.boolValue }
}

/// Encoding / tolerant decoding of single lines.
public enum PerfCodec {
    /// ISO-8601 UTC with milliseconds and `Z` (same shape as `VisaGamesLog`).
    public static func formatTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    public static func parseTimestamp(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    /// "+08:00" style offset of `timeZone` at `date`.
    public static func offsetString(_ timeZone: TimeZone, at date: Date) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        let absolute = abs(seconds)
        return String(format: "%@%02d:%02d", sign, absolute / 3600, (absolute % 3600) / 60)
    }

    /// One line, no trailing newline. Keys sorted so output is deterministic.
    public static func encodeLine(_ event: PerfEvent) throws -> String {
        var object = event.fields
        object["v"] = .int(event.v)
        object["t"] = .string(event.type.rawValue)
        object["ts"] = .string(formatTimestamp(event.timestamp))
        object["tz"] = .string(event.tz)
        object["mono"] = .seconds(event.mono)
        object["launch"] = .string(event.launch)
        object["seq"] = .int(event.seq)
        object["app"] = .string(event.app)
        object["actor"] = .string(event.actor.rawValue)
        object["mode"] = .string(event.mode)
        object["session"] = .string(event.session)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(object)
        guard let line = String(data: data, encoding: .utf8), !line.contains("\n") else {
            throw CodecError.notOneLine
        }
        return line
    }

    public enum DecodeOutcome: Equatable, Sendable {
        case event(PerfEvent)
        /// Torn line, not JSON, missing envelope, or a newer schema (`v > 1`).
        case skipped
        /// Blank line (not counted as skipped).
        case blank
    }

    public static func decodeLine(_ line: Substring) -> DecodeOutcome {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .blank }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONDecoder().decode([String: PerfValue].self, from: data),
              let v = object["v"]?.intValue, v == PerfEvent.schemaVersion,
              let t = object["t"]?.stringValue, !t.isEmpty,
              let tsText = object["ts"]?.stringValue, let ts = parseTimestamp(tsText) else {
            return .skipped
        }
        let actor = object["actor"]?.stringValue.flatMap(PerfActor.init(rawValue:)) ?? .system
        var fields = object
        for key in PerfEvent.envelopeKeys { fields.removeValue(forKey: key) }
        return .event(PerfEvent(
            v: v,
            type: PerfEventType(rawValue: t),
            timestamp: ts,
            tz: object["tz"]?.stringValue ?? "+00:00",
            mono: object["mono"]?.doubleValue ?? 0,
            launch: object["launch"]?.stringValue ?? "",
            seq: object["seq"]?.intValue ?? 0,
            app: object["app"]?.stringValue ?? "",
            actor: actor,
            mode: object["mode"]?.stringValue ?? "",
            session: object["session"]?.stringValue ?? "",
            fields: fields
        ))
    }

    /// Decodes a whole file's text. Unreadable lines are counted, never fatal.
    public static func decodeLines(_ text: String) -> (events: [PerfEvent], skipped: Int) {
        var events: [PerfEvent] = []
        var skipped = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            switch decodeLine(line) {
            case .event(let event): events.append(event)
            case .skipped: skipped += 1
            case .blank: break
            }
        }
        return (events, skipped)
    }

    /// Readers never assume file order: (launch, seq) inside a launch, `ts` across launches.
    public static func ordered(_ events: [PerfEvent]) -> [PerfEvent] {
        var firstSeen: [String: Date] = [:]
        for event in events {
            if let seen = firstSeen[event.launch] {
                if event.timestamp < seen { firstSeen[event.launch] = event.timestamp }
            } else {
                firstSeen[event.launch] = event.timestamp
            }
        }
        return events.sorted { lhs, rhs in
            if lhs.launch == rhs.launch {
                if lhs.seq != rhs.seq { return lhs.seq < rhs.seq }
                return lhs.timestamp < rhs.timestamp
            }
            let l = firstSeen[lhs.launch] ?? lhs.timestamp
            let r = firstSeen[rhs.launch] ?? rhs.timestamp
            if l != r { return l < r }
            return lhs.launch < rhs.launch
        }
    }

    public enum CodecError: Error { case notOneLine }
}
