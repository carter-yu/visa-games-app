# ADR 0024: Weekly report HTML (W4)

Date: 2026-10-27
Status: Draft PR, source implementation awaiting Mac verification

## Context

Slice W4 of the weekly report (`visa-games-design/weekly-report/design.md` §12) renders the W3 text model (ADR 0023, on main via #38, `ef766f1`), with the W2 analysis and the W1 model inside it, as one HTML document: fixed A4 page sections, charts C1, M1, C2a, C2b, C3 and C4 as inline SVG, and the CSS ported from `mockups/report.css` (§3, §8, §9.2, §9.5, §9.6). Acceptance is a golden HTML per fixture and a palette that passes `validate_palette.js` (adjacent, light). D2 (the PDF is made later by an off-screen WKWebView, W5) rules out scripts, URLs, web fonts and image files. D7 (the child's name), D8 (top 3 video titles, escaped), D10 (the video question on page 6) and D13 (App 改動 marked 「Carter 決定」) are locked. WKWebView, the PDF, the 表現 row, file writing and scheduling (W5, W5b) and the rewrite (W6) are later slices.

## Decision

`WeeklyReportHTML.render(_ report: WeeklyReportText, options: WeeklyReportHTMLOptions) -> String` is pure. The text model carries the W2 analysis and the W1 model, so it is the only data input. `WeeklyReportHTMLOptions(generatedAt:sampleWatermark:)` supplies the 「製作於」 time (the renderer never reads the clock) and the sample watermark (off by default). W1–W3 code and goldens are unchanged.

New VisaCore files:

- `WeeklyReportHTML.swift`: the document, the six pages and the footer.
- `WeeklyReportCharts.swift`: the SVG charts.
- `WeeklyReportLayout.swift`: text widths and the page-4 / page-6 height estimate.
- `WeeklyReportLabels.swift`: all static copy (177 entries, Chinese and English), weekdays, months and the glossary.
- `WeeklyReportCSS.swift`: the stylesheet.
- `WeeklyReportPalette.swift`: every colour.

The goldens come from `Tests/VisaCoreTests/Fixtures/weekly-ranking-5.6/reference_html.py`. It is an independent Python reading of these rules that consumes each fixture folder's `expected-metrics.json`, `expected-analysis.json` and `expected-text.json`. The Swift label table, stylesheet and palette were generated from its tables by script and compared again after the last edit (identical). Swift output must match the goldens byte for byte.

Choices where the design left room:

**Document and pages**

- **Page count.** Six pages for any week with countable play (W3 `empty` is nil), including a week with videos only. A week without countable play has page 1 only, numbered 「第 1 頁，共 1 頁」.
  - §3 omits page 3 when no game was played. The report keeps it (and page 4) with 「今個星期冇玩遊戲。」, so the page numbers the copy points to (「詳情喺第 5 頁」, the video question on page 6) stay right.
  - `testPageCountSix` checks six sections for the 11 weeks with play it renders and one for the two without.
- **Fixed sections.** Each page is a 794 × 1123 px section (210 × 297 mm in print) with 72 / 53 / 57 / 53 px padding, `overflow: hidden` and one page break; `@page { size: A4; margin: 0 }`.
  - The WeasyPrint-only parts of `report.css` (running header and footer, page counters, the fixed watermark) became absolutely placed blocks inside every section.
  - Layout uses flex and grid only. Font sizes are in px with explicit line heights, which the height estimate reads.
- **Header and footer.**
  - Header: 「VisaGames 每週學習報告 Weekly report · 2026年10月19–25日 · 家長版，只供家人參考 For parents, family use only」.
  - Footer line 1: the §9.6 provenance line in its Chinese form: 「VisaGames 週報 v1 · builder 1 · 資料截至 … HKT · 製作於 … HKT · App v… · 數據指紋 xxxxxxxx」. App versions are the first and last of the week ("v0.33.1–v0.34.0"), 「—」 without records.
  - Footer line 2: the counted-only line with the child's name. The page number reads 「第 n 頁，共 N 頁 · Page n of N」.
- **數據指紋.** FNV-1a 64 (`ActivityChoiceOrder.seedValue`) over the canonical W1 JSON (`WeeklyJSON`) of this week and last week, as an object with keys `current` and `previous`. §9.6's "canonical counted lines" is read as the counted metrics, so the fingerprint ignores file order, torn lines and the making time. `fingerprint(_:)` returns 16 lowercase hex digits; the footer prints 8.
- **Sample watermark.** An option, off for real reports. It is on for the §5.6 golden, which is the design's sample week (like `mockups/sample-report.html`): a faint rotated 「示例數據 EXAMPLE DATA」 on every page, a tag in the header, a note in the footer and 「（示例數據）」 in the `<title>`. The W1 fixture golden has it off.
- **Self-contained (D2).** One inline `<style>`; inline SVG without `xmlns` (no URL appears anywhere; HTML parsers do not need it); no script, image, link or font file. `<html lang="zh-Hant-HK">`, UTF-8 and the §9.5 font stack.
- **Escaping.** One rule for every interpolated string and attribute value: `&`, `<`, `>`, `"`, `'` become `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&#39;`. Video titles, the child's name and unknown kind ids are escaped and otherwise unchanged (D7, D8).
- **Numbers.** Chart geometry is computed in integer tenths of a px and printed as "12.3" or "12". Percents go through W3's `WeeklyFormat` (half up). No floating-point formatting and no locale.

**Page 1**

- **Cover.** The week range, 「資料截至 10月25日 21:00」 (「成個星期」 once the week is over) and the child's name.
- **Six tiles (3 × 2).** Days played (n / covered days), rounds, quiz right first time (with the lucky-guess level), practice smooth, game time (with minutes per round) and video time (「約」 when estimated, with the visa minutes earned).
  - Rates show last week and W2's four change words. Counts and minutes show only 「明顯多咗／少咗」, from W2's count change.
  - A rate tile with fewer than 5 rounds shows 「—」 and 「數據唔夠（n 局）」.
- **Notes under the tiles.** The first week gets `wr.baseline`; a previous week with fewer than 4 covered days gets `wr.partialPrev` (§3 "< 4 days"). Copy was written for both; W3 had none.
- **Wins and next steps.** The wins box (W3's first 3 wins) sits beside 「下星期可以試吓」 (the first 2 family items, else 「今個星期冇特別建議，照舊就得。」). Without wins the box is one column.
- **Counted-only note.** Excluded rounds, then app updates and changed settings with the page-5 pointer.

**Page 2 and C1**

- **C1.** Per day, a games column (quiz below practice, 2 px gap) and a video column, each 20 px wide with a 4 px rounded top, on one minutes axis.
  - Clean ticks: the first step of 5, 10, 15, 20, 30, 60, 90 … 360 minutes that gives at most 5 intervals.
  - Days after the cut-off, before the first record (W1 coverage) and without play draw no bars, only a label: 「未到」, 「未有紀錄」 or 「冇玩」. The cut-off day gets 「截至 HH:mm」.
  - When every day is zero, 「今個星期未有遊戲或睇片紀錄。」 replaces the chart.
- **Daily table.** Fixed column widths. A day without bars is one muted line. Notes: the first new game, 「同另外 n 個新遊戲」 and 「截至 HH:mm」. Then week totals, the ticket line, and the time-definition note with the cut-off, 「約」 and video-question pointers.

**Page 3 and M1**

- **Rows.** Grouped by area in §7.2 order, quiz before practice, W1 catalog order inside, with an area line above each group.
  - Badges: 答題 / 練習, 「新 New」, 「同一題」 (quiz only) and 「⚙ 設定改咗」.
  - Cells are k / n with the series colour at 12 %; blank without rounds; 「—」 when the rounds have nothing to score. Week total and ticket counts.
- **Fold.** More than 22 rows: the 21 rows with the most rounds stay (ties keep the earlier row). The rest fold into 「其他 n 個遊戲（共 m 局）：」 with up to 6 names and 「同另外 n 個遊戲」.
- **Glossary.** The mockup's 8 entries. It moves to page 6 when the matrix folds, and also when rows plus area lines pass 24 (no room under the table). The first-try entry says right first time without a wrong tap (hints do not change `first_try`).

**Page 4**

- **Ranked.** The two lists with W3's splits. Each row is name and badges | the fact and 「★6 ★★2 · 6 日 days」 | W3's page-4 `short` forms. Then 「其他都做得好」 / 「其他仲學緊」.
  - An empty still-learning list shows `wr.bottom.none` (copy written).
  - An empty going-well list shows W3's 「今個星期每個遊戲都仲學緊，慢慢嚟。」 under its head.
- **Not ranked.** W3's status line. No games: 「今個星期冇玩遊戲。」.
- **數據唔夠.** Full rows up to 6 entries, else two columns.
- **How we rank.** A short method note (copy written from §5).
- **Variants.** A deterministic height estimate picks the first variant that fits: normal; 數據唔夠 in two columns; dense; dense without the method note.
- **Not printed.** W3's long comment forms and the win candidates after the first 3. They stay in the text model.

**Page 5, C2a, C2b, C3 and C4**

- **C3 and C4** need 2 weeks; with 1 week the first-week note replaces both.
- **C3.** Stacked quiz (bottom) and practice per week, with the total on top.
  - Partial weeks are outlined in the series colours with 「部分 partial」 under their label; the current week is bold with 「今個星期 this week」.
  - Up to 4 weeks are labelled "10/12–18"; more weeks by start date, "10/12".
  - Clean ticks from 5, 10, 20, 25, 50 … 1000 rounds with at most 4 intervals.
- **C4.** One 0–100 % axis. A week with fewer than 5 rounds of a type has no point, and the line breaks there.
  - Every plotted week gets an 8 px dot with a 2 px white ring, hollow for a partial week. The design asks for end dots; a point between two gaps would otherwise be invisible.
  - End labels such as 「答題 89%」 sit above or below by height. Footnote: 「少過 5 局嘅星期唔畫點」.
- **C2a.** Quiz areas with answered rounds this week or last week (手眼・畫線 has no quiz games).
  - This week's bar; the lucky-guess band from 0 to the area's mean chance (whole percent); last week as ◇ when it had at least 5 rounds.
  - Labels 「78%（9 局） · 上星期 75%」 and 「亂估都有約 30%」.
  - Fewer than 5 rounds: no bar, 「數據唔夠（3 局）」. The design wrote "n=3"; 局 matches the tiles and W3.
- **C2b.** The same for practice families, without the band.
- **Clear changes.** Up to 3 of W2's clear changes, then 「仲有 n 個遊戲都有明顯變化。」. Then 「其他遊戲…」 or 「冇遊戲有明顯變化…」, and the ⚙ line with up to 3 names and 「同另外 n 個遊戲」. The first week shows the baseline note.
- **What changed in the app.**
  - Versions: one as 「用咗 app 版本 v…」, two with their days, more as a range.
  - W3's 「今個星期冇改設定」.
  - Settings old → new with the number of games affected, net star assignments and question-source changes: at most 2 lines, then 「仲有 n 項改動冇列出。」.
  - The game mix, then rounds not counted by reason and rounds still open at the cut-off.

**Page 6**

- Family items with 「因為：…」, the praise tip and the none line.
- 「App 改動（建議，Carter 決定）」: a 「Carter 決定」 tag on every item (D13), then 「因為：…　下星期睇：…」, and the setting lines in small grey monospace. Setting lines are engineering text, the same in both languages, so they are printed once. Then the none line.
- 「想問你哋」 with their notes (D10), the glossary when it moved, and the privacy line (copy written, §11).

**Text budgets (§9.2, §13 items 10–11)**

- **No truncation.** No text is cut. Published constants cap the lists instead: 22 matrix rows (21 kept), 6 fold names, 1 new-game name per day note, 3 clear changes, 3 ⚙ names, 2 listed versions, 2 change lines and 6 full 數據唔夠 rows. Pages 4 and 6 switch to denser variants.
- **Width rule.** `WeeklyReportHTML.emWidth` works in thousandths of an em: CJK and other non-ASCII 1, digits 0.56, space 0.28, m w M W % @ 0.86, narrow Latin 0.32, other capitals 0.68, other ASCII 0.54. Wrapped text fills 92 % of its box.
- **Height estimate.** Width rule plus the CSS line heights; a variant is used while its estimate stays at or under 960 px of the 994 px content box.
- **`testNoTextOverflowBudget` enforces,** over both goldens and the synthetic weeks:
  - every SVG label inside its viewBox;
  - one-line parts: the running head, the page number, tile values, badges and list-head splits;
  - matrix day, total and ticket cells on one line, names in two lines and English names in one;
  - table dates on one line, day notes in 4 lines and the footer in 4 lines.
- **Data-independent budgets** in the same check: C1 day labels within a day's slot; C3 / C4 week labels for 1–7 weeks; C2 row names left of the bars and the widest value labels inside the chart; every game title with every badge in the matrix name column.
- **Chrome measurement.** In headless Chrome on this box (local files only), the tallest page content of both goldens and the ten synthetic weeks ends at 1,026.5 of 1,066 px, and nothing overflows the page width. The estimate runs 1–4 % above Chrome. WebKit (W5) is the real target.
- **Fixed while deriving the budgets.** 「未有紀錄 No records yet」 was about 97 px wide in a 91 px C1 day slot; the English is now "No records".

**Palette (§8)**

- **Tokens.** `WeeklyReportPalette` is the only source of colour; `testHTMLPaletteTokens` requires every hex in the HTML to be one of its 23 tokens (22 distinct).
  - Series (slots 1–3 of the validated reference palette): quiz #2a78d6, video #eb6834, practice #1baf7a. Each entity keeps its colour in every chart, tile and matrix tint.
  - Ink #0b0b0b / #52514e / #898781; gridlines and the lucky-guess band #e1e0d9 (the same hex in §8); baseline #c3c2b7; page #ffffff.
  - Matrix tints #e5effa / #e4f5ef: each series colour at 12 % on white.
  - Page chrome from the app's `DesignTokens.Palette` (passport blue, paper, taxi and metro tickets), plus the mockup's stamp red, panel and badge colours.
- **Validator.** `validate_palette.js "#2a78d6,#eb6834,#1baf7a" --mode light --surface "#ffffff"`:
  - Adjacent pairs: lightness PASS (L 0.43–0.77), chroma PASS (≥ 0.1), CVD PASS (worst #1baf7a↔#eb6834 ΔE 9.2 deutan, tritan 32.7), normal vision PASS (worst ΔE 27.6), contrast WARN (#1baf7a is 2.82:1 on white, relief required). Result: ALL CHECKS PASS.
  - `--pairs all`: CVD worst ΔE 9.2 deutan (tritan 9.6), normal vision worst #1baf7a↔#2a78d6 ΔE 24.0, the same WARN. Result: ALL CHECKS PASS.
  - Relief: every chart value is direct-labelled or in the adjacent table. The JS is not run by the app.

**Copy written for gaps (Carter to review)**

- The W4 label table (177 entries, Chinese and English) holds all layout copy: headings, tile labels and units, table heads, axis and legend words, the empty and low-data notes (`wr.baseline`, `wr.partialPrev`, `wr.bottom.none`, `c1.empty`, `c2.noQuiz`, `c2.noPractice`, 「未到」, 「未有紀錄」), the page-5 lines, the method note, the privacy line and the footer. The glossary is the mockup's.
- English singular forms for a count of 1 (`*One` labels): "Last week: 1 day", "Not enough data (1 round)", "1 more game changed clearly", "1 more change not listed".

## Consequences

The slice is VisaCore code, `VisaCoreChecks`, fixtures and docs only. No screen, record, setting or version changes, so the version stays 0.34.0 / 70.

Nine checks are registered in `VisaCoreChecks`, with the PASS banner updated: `testHTMLGolden`, `testPageCountSix`, `testChartFallbacks`, `testNoTextOverflowBudget`, `testHTMLPaletteTokens`, `testHTMLSelfContained`, `testHTMLWellFormed`, `testW3StringsPresent` and `testHTMLTraditionalOnlyAndNoBannedWords`. They read both goldens and ten synthetic weeks built in the test file, which were mirrored in Python when the expectations were written.

W5 renders this HTML to the PDF in an off-screen WKWebView. WebKit's fonts and line breaks must be measured there. The page-2 worst case (a new long-titled game every day plus the cut-off note) is not covered by the height estimate.

Swift was not compiled or run here (Linux box, no toolchain). The goldens, the synthetic-week expectations and the budgets were produced and replayed with the Python reference; the Mac mini `sh scripts/test.sh` result is pending. The app-level kiosk remains subject to the macOS escape paths in `docs/phase-0-kiosk-checklist.md`; no kiosk boundary or device policy changed.
