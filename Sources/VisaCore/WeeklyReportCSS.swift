import Foundation

// Weekly report W4 (weekly-report design §3, §8, §9.2, §9.5): the print stylesheet, ported from the design's
// `mockups/report.css` for fixed 794 × 1123 px page sections in WebKit. WeasyPrint-only features (running
// header and footer, page counters, fixed watermark) became absolutely placed blocks inside each section.
// Colours come from `WeeklyReportPalette` only; `.dense` holds the denser page-4 and page-6 variants that
// `WeeklyReportHTML` picks from its layout estimate. Keep in step with `reference_html.py`.

private typealias P = WeeklyReportPalette

enum WeeklyReportCSS {
    /// The stylesheet, without a final newline.
    static let text = """
        @page { size: A4; margin: 0; }
        html { font-family: "PingFang HK", "Noto Sans CJK HK", sans-serif; color: \(P.ink); font-size: 12px; line-height: 1.38; -webkit-text-size-adjust: none; overflow-wrap: break-word; }
        body { margin: 0; background: \(P.surface); }
        p { margin: 0; }
        section.page { position: relative; box-sizing: border-box; width: 794px; height: 1123px; overflow: hidden; padding: 72px 53px 57px 53px; background: \(P.surface); break-after: page; page-break-after: always; }
        section.page:last-of-type { break-after: auto; page-break-after: auto; }
        @media print { section.page { width: 210mm; height: 297mm; } }
        .runhead { position: absolute; left: 53px; right: 53px; top: 0; height: 62px; box-sizing: border-box; display: flex; justify-content: space-between; align-items: flex-end; border-bottom: 0.8px solid \(P.grid); padding-bottom: 4px; }
        .runhead .rh-left { font-size: 9.6px; color: \(P.ink2); white-space: nowrap; }
        .runhead .rh-left b { color: \(P.brand); font-weight: 700; }
        .runhead .rh-tag { font-size: 9.3px; font-weight: 700; color: \(P.stamp); border: 1px solid \(P.stamp); border-radius: 7px; padding: 0 7px; white-space: nowrap; }
        .runfoot { position: absolute; left: 53px; right: 53px; top: 1073px; display: flex; justify-content: space-between; align-items: flex-start; font-size: 8.3px; color: \(P.muted); line-height: 1.35; }
        .runfoot .pageno { font-size: 8.8px; white-space: nowrap; margin-left: 12px; }
        .wm { position: absolute; top: 446px; left: -45px; width: 794px; text-align: center; transform: rotate(-32deg); font-size: 53px; font-weight: 700; color: \(P.stamp); opacity: 0.1; letter-spacing: 2.7px; white-space: nowrap; }
        .en { color: \(P.ink2); font-size: 9.9px; line-height: 1.3; }
        .zh { font-size: 12px; }
        .pair { margin: 0 0 6px 0; }
        .pair .en { display: block; margin-top: 1px; }
        h1 { font-size: 26.7px; line-height: 35px; margin: 0; color: \(P.brand); font-weight: 700; letter-spacing: 0.7px; }
        h1 .en { font-size: 14px; color: \(P.ink2); font-weight: 400; letter-spacing: 0; margin-left: 8px; }
        h2 { font-size: 17px; line-height: 23px; margin: 0 0 6px 0; color: \(P.brand); font-weight: 700; }
        h2 .en { font-size: 11.5px; color: \(P.ink2); font-weight: 400; margin-left: 6px; }
        h3 { font-size: 13px; line-height: 18px; margin: 0 0 5px 0; font-weight: 700; }
        h3 .en { font-size: 10px; color: \(P.ink2); font-weight: 400; margin-left: 5px; }
        .cover { border-left: 8px solid \(P.brand); padding: 2px 0 2px 15px; margin-bottom: 14px; }
        .cover .meta { margin-top: 6px; font-size: 12px; color: \(P.ink2); }
        .cover .meta .en { display: block; font-size: 9.9px; }
        .highlights { background: \(P.paper); border-radius: 11px; padding: 13px 17px 7px 17px; margin-bottom: 14px; }
        .highlights .pair { margin-bottom: 8px; }
        .highlights .zh { font-size: 13px; }
        .highlights .en { font-size: 10.4px; }
        .tiles { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin-bottom: 14px; }
        .tile { border: 0.8px solid \(P.grid); border-radius: 10px; padding: 9px 11px 8px 11px; }
        .tile .lbl { font-size: 10.7px; color: \(P.ink2); line-height: 1.25; }
        .tile .lbl .en { display: block; font-size: 8.8px; color: \(P.muted); }
        .tile .val { font-size: 22.7px; font-weight: 700; margin: 2px 0 1px 0; line-height: 1.15; white-space: nowrap; }
        .tile .val small { font-size: 12px; font-weight: 400; color: \(P.ink2); }
        .tile .val.na { color: \(P.muted); }
        .tile .cmp { font-size: 9.9px; color: \(P.ink2); line-height: 1.3; }
        .tile .cmp .en { font-size: 8.7px; color: \(P.muted); display: block; }
        .sw { display: inline-block; width: 8px; height: 8px; border-radius: 2px; margin-right: 5px; vertical-align: 1px; }
        .sw.q { background: \(P.quiz); }
        .sw.p { background: \(P.practice); }
        .sw.v { background: \(P.video); }
        .pair.key { margin-bottom: 4px; }
        .key .zh { font-size: 10.7px; }
        .key .en { font-size: 9px; }
        .tilenote { margin: -6px 0 12px 0; }
        .tilenote .zh { font-size: 10.7px; color: \(P.ink2); }
        .tilenote .en { font-size: 9px; color: \(P.muted); }
        .twocol { display: grid; grid-template-columns: 1fr 1fr; gap: 19px; }
        .box { border-radius: 10px; padding: 11px 14px 4px 14px; }
        .box.wins { background: \(P.ticket); }
        .box.next { background: \(P.metro); }
        ul.items { list-style: none; padding: 0; margin: 0; }
        ul.items li { margin: 0 0 7px 0; padding-left: 16px; position: relative; }
        ul.items li::before { content: "✓"; position: absolute; left: 0; top: 0; color: \(P.brand); font-weight: 700; font-size: 11.3px; }
        ul.items.dots li::before { content: "•"; font-size: 13.3px; top: -2px; }
        ul.items li .en { display: block; }
        .note { font-size: 9.9px; color: \(P.ink2); margin-top: 11px; line-height: 1.4; }
        .note .en { display: block; font-size: 9px; color: \(P.muted); }
        .chart { margin: 0 0 6px 0; }
        .chart svg { display: block; width: 100%; height: auto; }
        .charttitle { font-size: 12.3px; font-weight: 700; margin-bottom: 4px; }
        .charttitle .en { font-size: 9.6px; font-weight: 400; margin-left: 5px; }
        .chartnote { font-size: 10.7px; color: \(P.ink2); border: 0.8px solid \(P.grid); border-radius: 10px; padding: 9px 12px; margin: 0 0 10px 0; }
        .chartnote .en { display: block; font-size: 9px; color: \(P.muted); }
        table { border-collapse: collapse; width: 100%; table-layout: fixed; }
        table.daily { font-size: 10.7px; margin-top: 4px; }
        table.daily th { font-size: 9.3px; font-weight: 700; color: \(P.ink2); text-align: right; padding: 4px 4px 5px 4px; border-bottom: 1px solid \(P.baseline); vertical-align: bottom; line-height: 1.25; }
        table.daily th .en { display: block; font-weight: 400; font-size: 8.3px; color: \(P.muted); }
        table.daily th.l, table.daily td.l { text-align: left; }
        table.daily td { padding: 5px 4px; border-bottom: 0.7px solid \(P.grid); text-align: right; font-variant-numeric: tabular-nums; vertical-align: top; }
        table.daily td .en { display: block; font-size: 8.5px; color: \(P.muted); }
        table.daily tr.total td { font-weight: 700; border-top: 1px solid \(P.baseline); border-bottom: none; }
        table.daily td.muted { color: \(P.muted); }
        table.daily td.note-cell { font-size: 9.6px; }
        table.matrix { font-size: 10.1px; }
        table.matrix th { font-size: 9px; color: \(P.ink2); font-weight: 700; padding: 2px 2px 3px 2px; border-bottom: 1px solid \(P.baseline); text-align: center; line-height: 1.2; vertical-align: bottom; }
        table.matrix th .en { display: block; font-weight: 400; font-size: 8px; color: \(P.muted); }
        table.matrix th.name { text-align: left; }
        table.matrix td { padding: 2px 2px; border-bottom: 0.7px solid \(P.grid); text-align: center; font-variant-numeric: tabular-nums; vertical-align: middle; }
        table.matrix td.name { text-align: left; padding-left: 3px; line-height: 1.15; }
        table.matrix td.name .en { display: block; font-size: 8.1px; color: \(P.muted); }
        table.matrix td.q { background: \(P.quizTint); }
        table.matrix td.p { background: \(P.practiceTint); }
        table.matrix td.na { color: \(P.muted); }
        table.matrix td.tot { font-weight: 700; }
        table.matrix td.stars { color: \(P.ink2); font-size: 9px; }
        table.matrix tr.area td { background: \(P.panel); font-size: 9.3px; font-weight: 700; color: \(P.ink2); padding: 3px 3px; text-align: left; }
        table.matrix tr.area td .en { font-weight: 400; color: \(P.muted); margin-left: 4px; font-size: 8.3px; }
        table.matrix tr.fold td { text-align: left; color: \(P.ink2); font-size: 9.3px; padding: 4px 3px; }
        table.matrix tr.fold td .en { display: block; font-size: 8.1px; color: \(P.muted); }
        .badge { display: inline-block; font-size: 8px; font-weight: 700; border-radius: 4px; padding: 0 4px; margin-right: 3px; vertical-align: 1px; line-height: 1.35; color: \(P.ink); white-space: nowrap; }
        .badge.q { background: \(P.quizTint); border: 0.7px solid \(P.badgeQuizLine); }
        .badge.p { background: \(P.practiceTint); border: 0.7px solid \(P.badgePracticeLine); }
        .badge.new { background: \(P.badgeNew); border: 0.7px solid \(P.badgeNewLine); }
        .badge.fixed { background: \(P.badgeGrey); border: 0.7px solid \(P.baseline); color: \(P.ink2); font-weight: 400; }
        .badge.cfg { background: \(P.badgeGrey); border: 0.7px solid \(P.baseline); color: \(P.ink2); }
        .rank { margin-bottom: 10px; }
        .rank .head { display: flex; justify-content: space-between; align-items: baseline; border-bottom: 1.2px solid \(P.brand); padding-bottom: 3px; margin-bottom: 4px; }
        .rank .head h3 { margin: 0; color: \(P.brand); }
        .rank .head .split { font-size: 9.9px; color: \(P.ink2); white-space: nowrap; }
        .row { display: grid; grid-template-columns: 196px 155px 1fr; gap: 11px; padding: 4px 0; border-bottom: 0.7px solid \(P.grid); }
        .row .nm { font-size: 12px; line-height: 15px; font-weight: 700; }
        .row .nm .en { display: block; font-weight: 400; font-size: 9.2px; line-height: 12px; }
        .fact { font-size: 11.2px; line-height: 14.5px; }
        .fact .en { display: block; font-size: 9px; line-height: 12px; }
        .fact .stars { display: block; font-size: 8.8px; line-height: 11.5px; color: \(P.muted); }
        .cm { font-size: 10.9px; line-height: 14.4px; }
        .cm .en { display: block; font-size: 8.9px; line-height: 11.6px; }
        .status { font-size: 11.5px; line-height: 15.8px; margin: 2px 0 6px 0; }
        .status .en { display: block; font-size: 9.3px; line-height: 12.1px; }
        .also { font-size: 10.4px; line-height: 14.5px; margin: 6px 0 0 0; }
        .also .en { display: block; font-size: 9px; line-height: 12px; color: \(P.ink2); }
        .insuff .row { grid-template-columns: 196px 1fr; }
        .insuff .cols { display: grid; grid-template-columns: 1fr 1fr; column-gap: 19px; }
        .insuff .item { padding: 3px 0; border-bottom: 0.7px solid \(P.grid); }
        .insuff .item .nm { font-size: 10.7px; line-height: 13.4px; font-weight: 700; }
        .insuff .item .nm .en { display: inline; font-weight: 400; font-size: 8.8px; line-height: 13.4px; margin-left: 4px; }
        .insuff .item .cm { font-size: 9.9px; line-height: 12.9px; }
        .insuff .item .cm .en { font-size: 8.5px; line-height: 11px; }
        .method { background: \(P.panel); border-radius: 9px; padding: 8px 12px 6px 12px; font-size: 9.9px; line-height: 13.8px; margin-top: 8px; }
        .method .en { display: block; font-size: 8.8px; line-height: 11.4px; color: \(P.ink2); margin-bottom: 4px; }
        .dense .rank { margin-bottom: 6px; }
        .dense .row { padding: 2px 0; }
        .dense .row .nm { font-size: 11px; line-height: 13.5px; }
        .dense .row .nm .en { font-size: 8.6px; line-height: 11px; }
        .dense .fact { font-size: 10.2px; line-height: 13px; }
        .dense .fact .en { font-size: 8.4px; line-height: 11px; }
        .dense .fact .stars { font-size: 8.2px; line-height: 10.5px; }
        .dense .cm { font-size: 10px; line-height: 13px; }
        .dense .cm .en { font-size: 8.2px; line-height: 10.6px; }
        .dense .also { font-size: 9.6px; line-height: 13px; }
        .dense .also .en { font-size: 8.4px; line-height: 11px; }
        .grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 19px; }
        .panel { border: 0.8px solid \(P.grid); border-radius: 10px; padding: 10px 13px 3px 13px; margin-top: 8px; }
        .panel ul.items li { margin-bottom: 6px; }
        .rec { padding: 5px 0; border-bottom: 0.7px solid \(P.grid); }
        .rec .t { font-size: 12px; line-height: 16px; font-weight: 700; }
        .rec .t .en { display: block; font-weight: 400; font-size: 9.6px; line-height: 12.5px; color: \(P.ink2); }
        .rec .why { font-size: 10px; line-height: 13.5px; color: \(P.ink2); margin-top: 2px; }
        .rec .why .en { display: block; font-size: 9px; line-height: 12px; color: \(P.muted); }
        .rec .param { font-size: 9.3px; line-height: 12.5px; color: \(P.muted); margin-top: 2px; font-family: Menlo, "Noto Sans Mono CJK HK", monospace; }
        .rec .decide { font-size: 8.5px; font-weight: 700; color: \(P.brand); border: 0.8px solid \(P.brand); border-radius: 4px; padding: 0 4px; margin-left: 5px; vertical-align: 1px; white-space: nowrap; }
        .sec { margin-top: 11px; }
        .howto { margin-top: 10px; border-top: 1.1px solid \(P.brand); padding-top: 7px; }
        .gloss { display: grid; grid-template-columns: 1fr 1fr; gap: 3px 23px; font-size: 10px; line-height: 13.5px; margin-top: 4px; }
        .gloss b { font-weight: 700; }
        .gloss .en { display: block; font-size: 8.8px; line-height: 11.5px; color: \(P.ink2); }
        .dense .rec { padding: 3px 0; }
        .dense .rec .t { font-size: 11px; line-height: 14.5px; }
        .dense .rec .t .en { font-size: 9px; line-height: 11.5px; }
        .dense .rec .why { font-size: 9.4px; line-height: 12.5px; }
        .dense .rec .why .en { font-size: 8.4px; line-height: 11px; }
        .dense .rec .param { font-size: 8.6px; line-height: 11.5px; }
        .dense .sec { margin-top: 7px; }
        .dense .howto { margin-top: 8px; padding-top: 6px; }
        .dense .gloss { gap: 2px 23px; font-size: 9.4px; line-height: 12.5px; }
        .dense .gloss .en { font-size: 8.2px; line-height: 10.5px; }
        .privacy { margin-top: 11px; font-size: 9.6px; line-height: 13px; color: \(P.ink2); border-top: 0.8px solid \(P.grid); padding-top: 8px; }
        .privacy .en { display: block; font-size: 8.8px; line-height: 11.5px; color: \(P.muted); }
        """
}
