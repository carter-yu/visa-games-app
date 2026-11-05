import Foundation

/// Parent on/off wording, one source for every parent toggle and report label (build 80).
/// Carter chose 開／關 on 2026-11-05; the count card already used it.
public enum ParentToggleCopy {
    public static let on = "開"
    public static let off = "關"

    /// The chunky pill's label: HK Chinese then English, as the count card shows it.
    public static func pill(_ isOn: Bool) -> String { isOn ? "\(on) On" : "\(off) Off" }
}
