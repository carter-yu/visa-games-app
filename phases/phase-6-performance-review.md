# Phase 6 — D10 performance records and review

ADR 0008. Three PRs, each with Mac mini + TV UAT before the next.

| Version | Scope | Child-visible |
| --- | --- | --- |
| v0.20.0 Record | Append-only JSONL events (rounds, answers, picker pages, picks, plays, stop reasons, resume), parent tagging (🧪 家長測試中, 「唔計呢段」, playtest / 試播 / test visa actors), 90-day retention + daily summaries, CSV export, 「清除表現紀錄」 | No |
| v0.21.0 Review | 表現 segment (遊戲 / 影片 tabs) in Parent controls, labels per design §3.5 / §7 | No |
| v0.22.0 Adapt | 出題方式 (default 自動): ≤ 1 practise-more deal in any 4, same boost on every star, 7-day half-life | Deal order only |

## v0.20.0 exit evidence

- `sh scripts/test.sh` PASS with **18 performance-log** checks (schema round trip, tolerant
  decoder, HKT day files, clear vs visa reset, round / play trackers, slots vs presented order for
  every kind, confusion tags, actor rule and exclusions, 🧪 auto-off, session clock, picker
  placement, CSV, retention, prune idempotence, Traditional-only strings).
- `sh scripts/bundle.sh` + `sh scripts/install-mac-mini.sh` → `/Applications/Visa Games.app`
  0.20.0 / 42.
- TV UAT checklist in the v0.20.0 PR.
