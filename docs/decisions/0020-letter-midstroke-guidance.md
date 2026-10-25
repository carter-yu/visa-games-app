# ADR 0020: Letter mid-stroke guidance

Date: 2026-10-25
Status: Draft PR, source implementation awaiting Mac verification

## Context

Carter's 2026-10-25 UAT photos showed Count & draw digit 7 with a spoken beat, three headlights and a STOP sign at a pause, while Find & write letter e had only static copy at its self-junction. Find & write used the StrokeOrder demo but never ran the live TapCountGuideCoach. ADR 0019 keeps StrokeOrder for the demo/glance boundary; it does not supply live beat and cue data.

## Decision

The locked letter spec is copied verbatim to `docs/letter-tap-guidance-spec.json` and generates `LetterGuideData.swift`. The resolved `NumeralGuide`, demo timeline, guide run and coach now accept Latin glyph paths as well as numeral paths. Find & write uses the same shared 多啲 / 標準 / 少啲 tracing-help level and the same stroke-order setting for the learned pen glance. Letter progress remains per glyph. The ahead sign follows the tangent of the route 24 units after its cue, including numeral 6 and 10.

Carter locked all six design section 10 defaults at 10:59 HKT: LWT-only for a, b and d; no ball-stick pack; e's AHEAD sign ships with the tangent fix; letter car scale 0.6; the "Round like a c" beats stay; and one shared tracing-help level serves numbers and letters. Unsupported letters keep the existing no-guide path. The child copy is English only. Parent copy in the locked spec uses Hong Kong Traditional Chinese and English.

## Consequences

A clean letter trace now includes the coach's help record. Stall, ghost-to-end, re-demo, wrong-start and reverse-direction help prevent the two-clean learned streak. The first touch during a car demo or stroke glance ends it without painting. The letter board uses the shared vector art, with the engine bubble below the left word card. Reduce Motion uses the existing coach pose behavior: fixed step poses, a steady sign and ring, and no pop animation.

This source slice has no Mac mini or TV validation. The app-level kiosk remains subject to the macOS escape paths in `docs/phase-0-kiosk-checklist.md`; no device policy changed here.
