import Foundation

/// Approved word art shared by readiness, dealers and the view.
public enum LetterWordArtCatalog {
    public static let pictures: [String: String] = [
        "word.apple":"🍎", "word.ant":"🐜", "word.arrow":"↗️", "word.ambulance":"🚑",
        "word.anchor":"⚓️", "word.astronaut":"👩‍🚀", "word.avocado":"🥑", "word.ankle":"🦶",
        "word.ball":"⚽️", "word.bus":"🚌", "word.bed":"🛏️", "word.bee":"🐝",
        "word.boat":"⛵️", "word.book":"📚", "word.bear":"🐻", "word.bike":"🚲",
        "word.balloon":"🎈", "word.bird":"🐦", "word.banana":"🍌", "word.butterfly":"🦋",
        "word.cat":"🐈", "word.car":"🚗", "word.cake":"🎂", "word.cup":"☕️",
        "word.cow":"🐄", "word.cap":"🧢", "word.corn":"🌽", "word.carrot":"🥕",
        "word.castle":"🏰", "word.camel":"🐪", "word.caterpillar":"🐛", "word.crab":"🦀",
        "word.dog":"🐕", "word.duck":"🦆", "word.door":"🚪", "word.digger":"🚜",
        "word.doll":"🪆", "word.dinosaur":"🦕", "word.dolphin":"🐬", "word.dumptruck":"🚚",
        "word.deer":"🦌", "word.donkey":"🫏", "word.dice":"🎲", "word.drum":"🥁",
        "word.egg":"🥚", "word.elephant":"🐘", "word.elbow":"💪", "word.engine":"🚂",
        "word.envelope":"✉️", "word.excavator":"🚜", "word.escalator":"🛗", "word.elf":"🧝",
        "word.fish":"🐟", "word.fox":"🦊", "word.frog":"🐸", "word.fan":"🪭",
        "word.fork":"🍴", "word.flower":"🌸", "word.fire_engine":"🚒", "word.feather":"🪶",
        "word.goat":"🐐", "word.girl":"👧", "word.gift":"🎁", "word.grapes":"🍇",
        "word.guitar":"🎸", "word.goose":"🪿",
        "word.hat":"👒", "word.horse":"🐴", "word.house":"🏠", "word.hand":"✋",
        "word.helicopter":"🚁", "word.hen":"🐔", "word.hippo":"🦛"
    ]
    public static func contains(_ id: String) -> Bool { pictures[id] != nil }
}
