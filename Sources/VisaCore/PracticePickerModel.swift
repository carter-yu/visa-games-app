import Foundation

public enum PracticePickerRole: String, Sendable { case target, distractorOnly }

public struct PracticePickerItem: Sendable, Equatable {
    public let id: String
    public let label: String
    public let role: PracticePickerRole
    public init(id: String, label: String, role: PracticePickerRole) {
        self.id = id; self.label = label; self.role = role
    }
}

public struct PracticePickerAvailability: Sendable, Equatable {
    public let consumers: Set<String>
    public let reason: String?
    public let reasonsByConsumer: [String: String]
    public init(consumers: Set<String>, reason: String? = nil,
                reasonsByConsumer: [String: String] = [:]) {
        self.consumers = consumers; self.reason = reason
        self.reasonsByConsumer = reasonsByConsumer
    }
}

public struct PracticePickerPreset: Sendable, Equatable {
    public let id: String
    public let label: String
    /// Smaller English/source line under the label (presentation only; build 79).
    public let subtitle: String
    public let itemIDs: [String]
    public init(id: String, label: String, subtitle: String = "", itemIDs: [String]) {
        self.id = id; self.label = label; self.subtitle = subtitle; self.itemIDs = itemIDs
    }
}

public struct PracticePickerPresetPreview: Sendable, Equatable {
    public let includedIDs: [String]
    public let omittedIDs: [String]
    public var canApply: Bool { !includedIDs.isEmpty }
}

/// Presentation value only. IDs are opaque; item order is supplied by the adapter.
public struct PracticePickerModel: Sendable {
    public let catalogID: String
    public let catalogRevision: String
    public let items: [PracticePickerItem]
    public let availabilityByItem: [String: PracticePickerAvailability]
    public let enabledIDs: Set<String>
    public let presets: [PracticePickerPreset]
    public let minimum: Int
    public let maximum: Int

    public init(catalogID: String, catalogRevision: String, items: [PracticePickerItem],
                availabilityByItem: [String: PracticePickerAvailability], enabledIDs: Set<String>,
                presets: [PracticePickerPreset], minimum: Int, maximum: Int) {
        self.catalogID = catalogID; self.catalogRevision = catalogRevision; self.items = items
        self.availabilityByItem = availabilityByItem; self.enabledIDs = enabledIDs
        self.presets = presets; self.minimum = minimum; self.maximum = maximum
    }

    public func isSelectable(_ id: String) -> Bool {
        items.contains { $0.id == id && $0.role == .target } &&
            !(availabilityByItem[id]?.consumers.isEmpty ?? true)
    }

    public func previewPreset(_ id: String) -> PracticePickerPresetPreview? {
        guard let preset = presets.first(where: { $0.id == id }) else { return nil }
        var included: [String] = []
        var omitted: [String] = []
        for id in preset.itemIDs where !included.contains(id) && !omitted.contains(id) {
            if isSelectable(id) && included.count < maximum { included.append(id) }
            else { omitted.append(id) }
        }
        return PracticePickerPresetPreview(includedIDs: included, omittedIDs: omitted)
    }
}
