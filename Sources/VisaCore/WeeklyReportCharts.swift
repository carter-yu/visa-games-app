import Foundation

// Weekly report W4 (weekly-report design §8): the inline SVG charts C1, C2a, C2b, C3 and C4. One SVG unit is one
// CSS px; every coordinate is computed in integer tenths of a px and printed by `t(_:)`, so the text never
// depends on floating-point formatting or the host locale. Marks follow the series colours of
// `WeeklyReportPalette`; text wears the ink tokens only; every value is direct-labelled or in the page's table.
// Keep in step with `reference_html.py`.

private typealias P = WeeklyReportPalette

extension WeeklyReportHTML {
    enum LegendMark {
        case swatch(String)
        case diamond
        case band
    }

    /// One row of C2a / C2b: this week k1 / n1, last week k0 / n0, the lucky-guess level in whole percent.
    struct BarRow {
        let words: WeeklyWords
        let k1: Int
        let n1: Int
        let k0: Int
        let n0: Int
        let chance: Int?
    }

    static let c1Steps = [5, 10, 15, 20, 30, 60, 90, 120, 180, 240, 300, 360]
    static let c3Steps = [5, 10, 20, 25, 50, 100, 200, 250, 500, 1000]
    static let percentTicks = [0, 25, 50, 75, 100]

    // MARK: Primitives (tenths of a px)

    static func svgOpen(_ width: Int, _ height: Int) -> String {
        "<svg viewBox=\"0 0 " + String(width) + " " + String(height) + "\" role=\"img\">\n"
    }

    static func svgText(_ x: Int, _ y: Int, _ text: String, size: Int, fill: String, anchor: String = "start",
                        bold: Bool = false) -> String {
        var out = "<text" + attr("x", t(x)) + attr("y", t(y)) + attr("font-size", t(size))
        out += attr("fill", fill) + attr("text-anchor", anchor)
        if bold {
            out += attr("font-weight", "700")
        }
        out += ">" + esc(text) + "</text>\n"
        return out
    }

    static func svgLine(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int, stroke: String, width: Int) -> String {
        var out = "<line" + attr("x1", t(x1)) + attr("y1", t(y1)) + attr("x2", t(x2)) + attr("y2", t(y2))
        out += attr("stroke", stroke) + attr("stroke-width", t(width)) + "/>\n"
        return out
    }

    static func svgRect(_ x: Int, _ y: Int, _ width: Int, _ height: Int, fill: String, extra: String = "") -> String {
        var out = "<rect" + attr("x", t(x)) + attr("y", t(y)) + attr("width", t(width)) + attr("height", t(height))
        out += attr("fill", fill) + extra + "/>\n"
        return out
    }

    /// Column with a 4 px rounded data end (top) and a square base.
    static func column(_ x: Int, _ top: Int, _ width: Int, _ base: Int, fill: String, extra: String = "") -> String {
        let r = min(40, base - top, width / 2)
        let parts: [String] = [
            "M" + t(x), t(base), "V" + t(top + r), "Q" + t(x), t(top), t(x + r), t(top), "H" + t(x + width - r),
            "Q" + t(x + width), t(top), t(x + width), t(top + r), "V" + t(base), "Z"
        ]
        return "<path" + attr("d", parts.joined(separator: " ")) + attr("fill", fill) + extra + "/>\n"
    }

    /// Horizontal bar: square at the baseline (left), 4 px rounded data end (right).
    static func hbar(_ x0: Int, _ yc: Int, _ length: Int, _ height: Int, fill: String) -> String {
        let r = min(40, length, height / 2)
        let y0 = yc - height / 2
        let y1 = yc + height / 2
        let x1 = x0 + length
        let parts: [String] = [
            "M" + t(x0), t(y0), "H" + t(x1 - r), "Q" + t(x1), t(y0), t(x1), t(y0 + r), "V" + t(y1 - r), "Q" + t(x1),
            t(y1), t(x1 - r), t(y1), "H" + t(x0), "Z"
        ]
        return "<path" + attr("d", parts.joined(separator: " ")) + attr("fill", fill) + "/>\n"
    }

    /// Hollow last-week marker ◇, 10 px wide, centred on (x, yc).
    static func diamond(_ x: Int, _ yc: Int) -> String {
        let d = "M" + t(x) + " " + t(yc - 50) + " l5 5 l-5 5 l-5 -5 Z"
        return "<path" + attr("d", d) + attr("fill", P.surface) + attr("stroke", P.ink2) + attr("stroke-width", "1.5") + "/>\n"
    }

    /// Legend items in a row from `x`, text baseline at `y`.
    static func legend(_ items: [(mark: LegendMark, words: WeeklyWords)], x startX: Int, y: Int) -> String {
        var out = ""
        var x = startX
        for item in items {
            let swatchWidth: Int
            switch item.mark {
            case .diamond:
                out += diamond(x + 50, y - 50)
                swatchWidth = 120
            case .band:
                out += svgRect(x, y - 90, 160, 100, fill: P.guessBand)
                swatchWidth = 200
            case .swatch(let color):
                out += svgRect(x, y - 80, 90, 90, fill: color, extra: attr("rx", "2"))
                swatchWidth = 130
            }
            out += svgText(x + swatchWidth, y, item.words.zh, size: 95, fill: P.ink, bold: true)
            let englishX = x + swatchWidth + textWidth(item.words.zh, 95) + 40
            out += svgText(englishX, y, item.words.en, size: 85, fill: P.ink2)
            x = englishX + textWidth(item.words.en, 85) + 180
        }
        return out
    }

    /// The first step giving at most `intervals` intervals up to `maximum` (clean ticks).
    static func niceStep(_ maximum: Int, _ steps: [Int], _ intervals: Int) -> Int {
        for step in steps where (maximum + step - 1) / step <= intervals {
            return step
        }
        var step = steps[steps.count - 1]
        while (maximum + step - 1) / step > intervals {
            step *= 2
        }
        return step
    }

    // MARK: C1 minutes per day (page 2)

    /// Games (quiz below practice, a 2 px gap) and videos per day on one minutes axis; nil when every day is zero.
    static func chartC1(_ c: WeeklyHTMLContext) -> String? {
        let days = c.current.days
        var maxMs = 0
        for day in days {
            maxMs = max(maxMs, day.quizMs + day.practiceMs, day.videoMs)
        }
        guard maxMs > 0 else { return nil }
        let left = 460
        let right = 6830
        let top = 360
        let base = 1860
        let plot = base - top
        let maxMinutes = (maxMs + 59_999) / 60_000
        let step = niceStep(maxMinutes, c1Steps, 5)
        let vmax = step * ((maxMinutes + step - 1) / step)
        var out = svgOpen(688, 240)
        let items: [(mark: LegendMark, words: WeeklyWords)] = [
            (mark: .swatch(P.quiz), words: label("legend.quizGames")),
            (mark: .swatch(P.practice), words: label("legend.practiceGames")),
            (mark: .swatch(P.video), words: label("legend.videos"))
        ]
        out += legend(items, x: left, y: 140)
        var tick = 0
        while tick <= vmax {
            let y = base - scale(tick, plot, vmax)
            out += svgLine(left, y, right, y, stroke: tick == 0 ? P.baseline : P.grid, width: tick == 0 ? 10 : 8)
            out += svgText(left - 60, y + 35, String(tick), size: 90, fill: P.muted, anchor: "end")
            tick += step
        }
        let axis = label("axis.minutes")
        out += svgText(left - 60, top - 100, axis.zh + " " + axis.en, size: 85, fill: P.muted, anchor: "end")
        let slot = (right - left) / 7
        let full = vmax * 60_000
        for index in 0..<WeeklyWindow.dayCount {
            let day = days[index]
            let cx = left + index * slot + slot / 2
            let english = WeeklyFormat.dayNamesEN[index] + " " + String(ymd(c.stamps[index]).day)
            out += svgText(cx, base + 150, WeeklyFormat.dayNamesZH[index], size: 95, fill: P.ink, anchor: "middle", bold: true)
            out += svgText(cx, base + 270, english, size: 85, fill: P.muted, anchor: "middle")
            let quiet = c.quiet(index)
            if quiet {
                let words = label(c.quietLabel(index))
                out += svgText(cx, base - 80, words.zh + " " + words.en, size: 90, fill: P.muted, anchor: "middle")
            }
            if c.cutDay == index {
                let words = label("day.upTo", ["time": same(c.cutClock)])
                out += svgText(cx, base + 390, words.zh + " / " + words.en, size: 80, fill: P.muted, anchor: "middle")
            }
            if quiet { continue }
            let quizHeight = scale(day.quizMs, plot, full)
            let practiceHeight = scale(day.practiceMs, plot, full)
            let videoHeight = scale(day.videoMs, plot, full)
            let gamesX = cx - 230
            if quizHeight > 0 {
                if practiceHeight > 0 {
                    out += svgRect(gamesX, base - quizHeight, 200, quizHeight, fill: P.quiz)
                } else {
                    out += column(gamesX, base - quizHeight, 200, base, fill: P.quiz)
                }
            }
            if practiceHeight > 0 {
                let bottom = base - quizHeight - (quizHeight > 0 ? 20 : 0)
                out += column(gamesX, bottom - practiceHeight, 200, bottom, fill: P.practice)
            }
            if videoHeight > 0 {
                out += column(cx + 30, base - videoHeight, 200, base, fill: P.video)
            }
        }
        out += "</svg>\n"
        return out
    }

    // MARK: C2a / C2b by quiz area and practice family (page 5)

    /// This week's rate as a bar, the lucky-guess band from 0 to the chance (C2a), last week as a hollow ◇ (with
    /// ≥ 5 rounds), labels at the bar end. Under 5 rounds this week: no bar, 「數據唔夠（n 局）」.
    static func chartBars(_ rows: [BarRow], color: String, guess: Bool) -> String {
        let count = rows.count
        let x0 = 1860
        let track = 3300
        let top = 280
        let rowHeight = 240
        var out = svgOpen(688, 44 + 24 * count)
        var items: [(mark: LegendMark, words: WeeklyWords)] = [
            (mark: .swatch(color), words: label("legend.thisWeek")),
            (mark: .diamond, words: label("legend.lastWeek"))
        ]
        if guess {
            items.append((mark: .band, words: label("legend.guess")))
        }
        out += legend(items, x: 0, y: 130)
        let gridTop = top - 40
        let gridBottom = top + rowHeight * count - 40
        for tick in percentTicks {
            let x = x0 + scale(tick, track, 100)
            out += svgLine(x, gridTop, x, gridBottom, stroke: tick == 0 ? P.baseline : P.grid, width: tick == 0 ? 10 : 8)
            out += svgText(x, gridBottom + 120, String(tick) + "%", size: 85, fill: P.muted, anchor: "middle")
        }
        for (index, row) in rows.enumerated() {
            let yc = top + index * rowHeight + 80
            out += svgText(0, yc - 10, row.words.zh, size: 100, fill: P.ink, bold: true)
            out += svgText(0, yc + 90, row.words.en, size: 85, fill: P.muted)
            if row.n1 < minimumRounds {
                let words = label(row.n1 == 1 ? "c2.notEnoughOne" : "c2.notEnough", ["n": num(row.n1)])
                out += svgText(x0 + 40, yc + 40, words.zh + " " + words.en, size: 90, fill: P.muted)
                continue
            }
            let chance = guess ? row.chance : nil
            if let chance, chance > 0 {
                out += svgRect(x0, yc - 90, scale(chance, track, 100), 180, fill: P.guessBand)
            }
            let length = scale(row.k1, track, row.n1)
            if length > 0 {
                out += hbar(x0, yc, length, 120, fill: color)
            }
            var reach = length
            let last = row.n0 >= minimumRounds
            if last {
                let px = x0 + scale(row.k0, track, row.n0)
                out += diamond(px, yc)
                reach = max(reach, px - x0 + 50)
            }
            let labelX = x0 + reach + 100
            var value = label("c2.value", ["p": num(WeeklyFormat.percent(row.k1, of: row.n1)), "n": num(row.n1)]).zh
            if last {
                value += label("c2.last", ["p": num(WeeklyFormat.percent(row.k0, of: row.n0))]).zh
            }
            out += svgText(labelX, yc + 40, value, size: 95, fill: P.ink)
            if let chance {
                let words = label("c2.guess", ["c": num(chance)])
                out += svgText(labelX, yc + 120, words.zh + " · " + words.en, size: 80, fill: P.muted)
            }
        }
        out += "</svg>\n"
        return out
    }

    /// Quiz areas with answered rounds this week or last week (not 手眼・畫線, which has no quiz games).
    static func areaRows(_ c: WeeklyHTMLContext) -> [BarRow] {
        var rows: [BarRow] = []
        let comparison = c.analysis.comparison
        for area in WeeklyArea.allCases where area != .pen {
            let change = comparison.areas[area] ?? WeeklyRateComparison(k1: 0, n1: 0, k0: 0, n0: 0)
            guard change.n1 > 0 || change.n0 > 0 else { continue }
            let mean = (c.current.areas[area] ?? WeeklyGroupMetrics()).chanceMean
            var chance: Int?
            if let mean {
                chance = WeeklyFormat.percent(mean)
            }
            rows.append(BarRow(words: WeeklyWords(area.zh, area.en), k1: change.k1, n1: change.n1, k0: change.k0,
                               n0: change.n0, chance: chance))
        }
        return rows
    }

    /// Practice families with smooth-defined rounds this week or last week.
    static func familyRows(_ c: WeeklyHTMLContext) -> [BarRow] {
        var rows: [BarRow] = []
        let comparison = c.analysis.comparison
        for family in WeeklyPracticeFamily.allCases {
            let change = comparison.families[family] ?? WeeklyRateComparison(k1: 0, n1: 0, k0: 0, n0: 0)
            guard change.n1 > 0 || change.n0 > 0 else { continue }
            rows.append(BarRow(words: label("family." + family.rawValue), k1: change.k1, n1: change.n1, k0: change.k0,
                               n0: change.n0, chance: nil))
        }
        return rows
    }

    // MARK: C3 / C4 per week (page 5)

    static func weekX(_ left: Int, _ right: Int, _ index: Int, _ count: Int) -> Int {
        left + scale(2 * index + 1, right - left, 2 * count)
    }

    /// Week labels; the current week (bold) and partial weeks get a line in each language below.
    static func weekAxis(_ weeks: [WeeklyWeekTotals], _ left: Int, _ right: Int, _ base: Int, _ zone: TimeZone) -> String {
        var out = ""
        let short = weeks.count > 4
        for (index, week) in weeks.enumerated() {
            let cx = weekX(left, right, index, weeks.count)
            let text = weekLabel(week.weekStart, short: short, timeZone: zone)
            out += svgText(cx, base + 140, text, size: 90, fill: P.ink, anchor: "middle", bold: week.isCurrent)
            let id: String
            if week.isCurrent {
                id = "week.this"
            } else if week.partial {
                id = "week.partial"
            } else {
                continue
            }
            let words = label(id)
            out += svgText(cx, base + 250, words.zh, size: 80, fill: P.muted, anchor: "middle")
            out += svgText(cx, base + 350, words.en, size: 80, fill: P.muted, anchor: "middle")
        }
        return out
    }

    /// C3: rounds per week, quiz below practice; partial weeks hollow-outlined (「部分」); totals on the caps.
    static func chartC3(_ weeks: [WeeklyWeekTotals], _ zone: TimeZone) -> String {
        let left = 340
        let right = 3220
        let top = 280
        let base = 1300
        let plot = base - top
        var totals: [Int] = []
        for week in weeks {
            totals.append(week.totals.quizRounds + week.totals.practiceRounds)
        }
        let highest = totals.max() ?? 0
        let step = niceStep(highest, c3Steps, 4)
        let vmax = step * max(1, (highest + step - 1) / step)
        var out = svgOpen(330, 182)
        let items: [(mark: LegendMark, words: WeeklyWords)] = [
            (mark: .swatch(P.quiz), words: label("legend.quiz")),
            (mark: .swatch(P.practice), words: label("legend.practice"))
        ]
        out += legend(items, x: left, y: 130)
        var tick = 0
        while tick <= vmax {
            let y = base - scale(tick, plot, vmax)
            out += svgLine(left, y, right, y, stroke: tick == 0 ? P.baseline : P.grid, width: tick == 0 ? 10 : 8)
            out += svgText(left - 50, y + 35, String(tick), size: 85, fill: P.muted, anchor: "end")
            tick += step
        }
        for (index, week) in weeks.enumerated() {
            let cx = weekX(left, right, index, weeks.count)
            let bx = cx - 120
            let quizHeight = scale(week.totals.quizRounds, plot, vmax)
            let practiceHeight = scale(week.totals.practiceRounds, plot, vmax)
            let quizFill = week.partial ? P.surface : P.quiz
            let practiceFill = week.partial ? P.surface : P.practice
            let quizExtra = week.partial ? attr("stroke", P.quiz) + attr("stroke-width", "1.5") : ""
            let practiceExtra = week.partial ? attr("stroke", P.practice) + attr("stroke-width", "1.5") : ""
            if quizHeight > 0 {
                if practiceHeight > 0 {
                    out += svgRect(bx, base - quizHeight, 240, quizHeight, fill: quizFill, extra: quizExtra)
                } else {
                    out += column(bx, base - quizHeight, 240, base, fill: quizFill, extra: quizExtra)
                }
            }
            var topY = base - quizHeight
            if practiceHeight > 0 {
                let bottom = base - quizHeight - (quizHeight > 0 ? 20 : 0)
                out += column(bx, bottom - practiceHeight, 240, bottom, fill: practiceFill, extra: practiceExtra)
                topY = bottom - practiceHeight
            }
            out += svgText(cx, topY - 50, String(totals[index]), size: 95, fill: P.ink, anchor: "middle", bold: true)
        }
        out += weekAxis(weeks, left, right, base, zone)
        out += "</svg>\n"
        return out
    }

    /// One plotted week of C4.
    struct RatePoint {
        let week: Int
        let x: Int
        let y: Int
        let percent: Int
        let partial: Bool
    }

    /// C4: quiz right-first-time and practice smooth per week on one 0–100 % axis; a week with < 5 rounds of a
    /// type is a gap, not a zero; dots with a 2 px ring (hollow for partial weeks); direct end labels.
    static func chartC4(_ weeks: [WeeklyWeekTotals], _ zone: TimeZone) -> String {
        let left = 340
        let right = 2900
        let top = 280
        let base = 1300
        let plot = base - top
        var out = svgOpen(330, 182)
        let items: [(mark: LegendMark, words: WeeklyWords)] = [
            (mark: .swatch(P.quiz), words: label("legend.quiz")),
            (mark: .swatch(P.practice), words: label("legend.practice"))
        ]
        out += legend(items, x: left, y: 130)
        for tick in percentTicks {
            let y = base - scale(tick, plot, 100)
            out += svgLine(left, y, right, y, stroke: tick == 0 ? P.baseline : P.grid, width: tick == 0 ? 10 : 8)
            out += svgText(left - 50, y + 35, String(tick) + "%", size: 85, fill: P.muted, anchor: "end")
        }
        var ends: [(point: RatePoint, name: String)] = []
        for quiz in [true, false] {
            let color = quiz ? P.quiz : P.practice
            var points: [RatePoint] = []
            for (index, week) in weeks.enumerated() {
                let n = quiz ? week.totals.answered : week.totals.smoothDefined
                let k = quiz ? week.totals.firstTry : week.totals.smooth
                guard n >= minimumRounds else { continue }
                points.append(RatePoint(week: index, x: weekX(left, right, index, weeks.count), y: base - scale(k, plot, n),
                                        percent: WeeklyFormat.percent(k, of: n), partial: week.partial))
            }
            var start = 0
            while start < points.count {
                var end = start
                while end + 1 < points.count && points[end + 1].week == points[end].week + 1 {
                    end += 1
                }
                if end > start {
                    var coordinates: [String] = []
                    for point in points[start...end] {
                        coordinates.append(t(point.x) + "," + t(point.y))
                    }
                    out += "<polyline" + attr("points", coordinates.joined(separator: " ")) + attr("fill", "none")
                    out += attr("stroke", color) + attr("stroke-width", "2") + attr("stroke-linejoin", "round")
                    out += attr("stroke-linecap", "round") + "/>\n"
                }
                start = end + 1
            }
            for point in points {
                let centre = attr("cx", t(point.x)) + attr("cy", t(point.y))
                out += "<circle" + centre + attr("r", "6") + attr("fill", P.surface) + "/>\n"
                if point.partial {
                    out += "<circle" + centre + attr("r", "4") + attr("fill", P.surface) + attr("stroke", color)
                    out += attr("stroke-width", "2") + "/>\n"
                } else {
                    out += "<circle" + centre + attr("r", "4") + attr("fill", color) + "/>\n"
                }
            }
            if let last = points.last {
                ends.append((point: last, name: label(quiz ? "legend.quiz" : "legend.practice").zh))
            }
        }
        // The higher end point is labelled above it, the lower one below.
        var offsets = [-40]
        if ends.count == 2 {
            offsets = ends[1].point.y < ends[0].point.y ? [120, -40] : [-40, 120]
        }
        for (index, end) in ends.enumerated() where index < offsets.count {
            let text = end.name + " " + String(end.point.percent) + "%"
            out += svgText(end.point.x + 90, end.point.y + offsets[index], text, size: 90, fill: P.ink, bold: true)
        }
        out += weekAxis(weeks, left, right, base, zone)
        let note = label("c4.note", ["min": num(minimumRounds)])
        out += svgText(left, 1790, note.zh + " · " + note.en, size: 76, fill: P.muted)
        out += "</svg>\n"
        return out
    }
}
