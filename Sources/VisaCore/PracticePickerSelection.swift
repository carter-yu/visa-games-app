import Foundation

public enum PracticePickerIntent: Sendable {
    case toggle(String)
    case replaceFromPreset(String)
    case revert
}

public enum PracticePickerSelection {
    /// Editing may produce an empty draft. The host checks `minimum` at Save.
    public static func reduce(model: PracticePickerModel, enabledIDs: Set<String>,
                              intent: PracticePickerIntent) -> Set<String> {
        switch intent {
        case .revert: return model.enabledIDs
        case .replaceFromPreset(let id):
            guard let preview = model.previewPreset(id), preview.canApply else { return enabledIDs }
            return Set(preview.includedIDs)
        case .toggle(let id):
            guard model.items.contains(where: { $0.id == id && $0.role == .target }) else { return enabledIDs }
            var next = enabledIDs
            if next.contains(id) { next.remove(id) }
            else if model.isSelectable(id) && next.count < model.maximum { next.insert(id) }
            return next
        }
    }
}
