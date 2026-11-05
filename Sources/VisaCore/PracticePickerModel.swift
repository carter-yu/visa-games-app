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
    /// Smaller English/source line under the label, e.g. "ABC group · 5 letters"
    /// (presentation only; build 79, counts since 80).
    public let subtitle: String
    /// The label is the item list itself ("f g h i j"), so the button headline shows only
    /// the ready items (mockup 01: "f g h"). Presentation only (build 80); IDs and the
    /// apply step are unchanged.
    public let listsItems: Bool
    public let itemIDs: [String]
    public init(id: String, label: String, subtitle: String = "", listsItems: Bool = false, itemIDs: [String]) {
        self.id = id; self.label = label; self.subtitle = subtitle; self.listsItems = listsItems
        self.itemIDs = itemIDs
    }
}

/// What a preset button says (build 80, UX m4 / review nit): the ready items for list-style
/// presets, the source group/count line, and the group's items that are not ready.
public struct PracticePickerPresetLabel: Sendable, Equatable {
    public let headline: String
    public let source: String
    /// Not-ready item labels joined with 「、」, empty when the whole group is ready.
    public let omitted: String

    public init(headline: String, source: String, omitted: String) {
        self.headline = headline; self.source = source; self.omitted = omitted
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

    /// The button wording for one preset. Uses the same preview as the apply step, so the
    /// headline never shows an item that applying would drop. A list-style preset with no
    /// ready item keeps its full label (the button is disabled anyway).
    public func label(forPreset id: String) -> PracticePickerPresetLabel? {
        guard let preset = presets.first(where: { $0.id == id }), let preview = previewPreset(id) else { return nil }
        func labels(_ ids: [String]) -> [String] {
            ids.map { id in items.first(where: { $0.id == id })?.label ?? id }
        }
        let headline = preset.listsItems && !preview.includedIDs.isEmpty
            ? labels(preview.includedIDs).joined(separator: " ") : preset.label
        return PracticePickerPresetLabel(headline: headline, source: preset.subtitle,
                                         omitted: labels(preview.omittedIDs).joined(separator: "、"))
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
