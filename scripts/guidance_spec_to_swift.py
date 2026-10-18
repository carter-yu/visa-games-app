#!/usr/bin/env python3
"""Convert the 一架一架數 guidance build spec (Opus 5.5, approved by Carter 2026-10-18) into Swift.

Source: docs/tap-count-guidance-spec.json — copied verbatim from
visa-games-design/number-quantity/guidance/build/guidance-spec.json.
Output: Sources/VisaCore/TapCountGuideData.swift (generated; do not edit by hand).

Fails loudly when a numeral 1–10, a language, a level or a copy line is missing.
Usage: python3 scripts/guidance_spec_to_swift.py [--source FILE] [--out FILE]
"""
import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FEATURES = ["headlights", "cueSigns", "cueWords", "fadeLaterStrokes", "hop"]
COPY_LINES = ["watchFirst", "yourTurn", "trayDemo", "trayTrace", "trayStall", "legendDemoCar", "legendRoute",
              "legendHeadlights", "legendAhead", "legendStop", "legendStrokeOrder", "legendHop", "redemo"]
PARENT = ["title", "more", "standard", "less", "learnedNote", "moreShort", "standardShort", "lessShort"]


def fail(msg):
    sys.exit("guidance spec: " + msg)


def lit(s):
    if not isinstance(s, str):
        fail("expected a string, got %r" % (s,))
    out = s.replace("\\", "\\\\").replace('"', '\\"')
    if any(ord(c) < 32 for c in out):
        fail("control character in %r" % s)
    return '"%s"' % out


def num(v):
    if v is None:
        return "nil"
    if not isinstance(v, (int, float)):
        fail("expected a number, got %r" % (v,))
    return repr(float(v))


def colour(v):
    if not (isinstance(v, str) and v.startswith("#") and len(v) == 7):
        fail("bad colour %r" % (v,))
    return "0x" + v[1:].upper()


def line(d, where, need_sub=True):
    if not isinstance(d, dict):
        fail("%s: missing line" % where)
    for k in ("zh", "en"):
        if not d.get(k):
            fail("%s: missing %s" % (where, k))
    if need_sub and "zhSub" not in d:
        fail("%s: missing zhSub" % where)
    return "TapCountGuideLine(zh: %s, zhSub: %s, en: %s, enSub: %s)" % (
        lit(d["zh"]), lit(d.get("zhSub", "")), lit(d["en"]), lit(d.get("enSub", "")))


def point(d, where):
    if not isinstance(d, dict) or "point" not in d:
        fail("%s: bad point %r" % (where, d))
    x, y = d["point"]
    return "NumeralGuidePoint(x: %s, y: %s, pass: %d)" % (num(x), num(y), int(d.get("pass", 1)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default=os.path.join(ROOT, "docs", "tap-count-guidance-spec.json"))
    ap.add_argument("--out", default=os.path.join(ROOT, "Sources", "VisaCore", "TapCountGuideData.swift"))
    args = ap.parse_args()
    spec = json.load(open(args.source, encoding="utf-8"))

    t = spec["timing"]
    timing = ("TapCountGuideTiming(hopSeconds: %s, cuePauseSeconds: %s, mergeSeconds: %s, routeFadeSeconds: %s, "
              "cueLeadUnits: %s, headlightDots: %d, stallRingGhostSeconds: %s)") % (
        num(t["hopSeconds"]), num(t["cuePauseSeconds"]), num(t["mergeSeconds"]), num(t["routeFadeSeconds"]),
        num(t["cueLeadUnits"]), int(t["headlightDots"]), num(t["stallRingGhostSeconds"]))

    levels = []
    for name in ("more", "standard", "less"):
        lv = spec["levels"].get(name) or fail("missing level " + name)
        if lv["demo"] not in ("always", "untilLearned", "never"):
            fail("level %s: demo %r" % (name, lv["demo"]))
        feats = [f for f in FEATURES if lv.get(f)]
        keeps = lv.get("learnedKeeps", [])
        for k in keeps:
            if k not in FEATURES:
                fail("level %s: unknown learnedKeeps %r" % (name, k))
        levels.append(
            "        case .%s:\n            return TapCountGuideLevelSpec(demo: .%s, features: [%s], stallSeconds: %s,\n"
            "                                          ghostToEndSeconds: %s, redemoSeconds: %s, learnedKeeps: [%s])"
            % (name, lv["demo"], ", ".join("." + f for f in feats), num(lv.get("stallSeconds")),
               num(lv.get("ghostToEndSeconds")), num(lv.get("redemoSeconds")), ", ".join("." + k for k in keeps)))

    numerals = []
    for n in range(1, 11):
        d = spec["numerals"].get(str(n)) or fail("missing numeral %d" % n)
        beats = []
        for i, b in enumerate(d["beats"]):
            where = "numeral %d beat %d" % (n, i)
            until = b["until"]
            if isinstance(until, (int, float)):
                if float(until) != 1.0:
                    fail(where + ": numeric until must be 1.0 (stroke end)")
                until_s = "nil"
            else:
                until_s = point(until, where)
            if not b.get("seconds") or b["seconds"] <= 0:
                fail(where + ": seconds")
            beats.append("NumeralGuideBeatSpec(stroke: %d, until: %s, seconds: %s,\n                    line: %s)"
                         % (int(b["stroke"]), until_s, num(b["seconds"]), line(b, where)))
        if not beats:
            fail("numeral %d: no beats" % n)
        cues = []
        for i, c in enumerate(d.get("cues") or []):
            where = "numeral %d cue %d" % (n, i)
            if c["sign"] not in ("ahead", "stop"):
                fail(where + ": sign %r" % c["sign"])
            sx, sy = c["signAt"]
            cues.append("NumeralGuideCueSpec(stroke: %d, point: %s, sign: .%s,\n                    signAt: LineMatchPoint(x: %s, y: %s),\n                    line: %s)"
                        % (int(c["stroke"]), point(c, where), c["sign"], num(sx), num(sy), line(c, where)))
        hop = d.get("hop")
        side = d.get("hopArcSide")
        if side not in (None, "left", "right", "up", "down"):
            fail("numeral %d: hopArcSide %r" % (n, side))
        last = d.get("lastStroke")
        numerals.append(
            "        case %d:\n            return NumeralGuideSpec(numeral: %d, beats: [\n                %s\n            ], merge: %s,\n"
            "            cues: [%s],\n            hop: %s, hopSide: %s,\n            lastStroke: %s)"
            % (n, n, ",\n                ".join(beats), line(d["merge"], "numeral %d merge" % n),
               ("\n                " + ",\n                ".join(cues) + "\n            ") if cues else "",
               line(hop, "numeral %d hop" % n) if hop else "nil", ("." + side) if side else "nil",
               line(last, "numeral %d lastStroke" % n) if last else "nil"))

    c = spec["copy"]
    copy_args = [("%s: %s" % (k, line(c.get(k), "copy." + k))) for k in COPY_LINES]
    stop = c.get("stopWord") or fail("copy.stopWord")
    par = c.get("parent") or fail("copy.parent")
    for k in PARENT:
        if not par.get(k):
            fail("copy.parent." + k)
    parent = "TapCountGuideParentCopy(%s)" % ", ".join("%s: %s" % (k, lit(par[k])) for k in PARENT)
    copy = "TapCountGuideCopy(\n        %s,\n        stopWordZh: %s, stopWordEn: %s,\n        parent: %s)" % (
        ",\n        ".join(copy_args), lit(stop["zh"]), lit(stop["en"]), parent)

    st = spec["styles"]
    r, b, h, s, g = st["route"], st["beam"], st["hopArc"], st["stallRing"], st["litGlow"]
    styles = ("TapCountGuideStyles(routeGlow: %s, routeGlowWidth: %s, routeCore: %s, routeCoreWidth: %s, routeDash: [%s],\n"
              "        beamOuter: %s, beamOuterWidth: %s, beamInner: %s, beamInnerWidth: %s, beamInnerOpacity: %s,\n"
              "        hopArc: %s, hopArcWidth: %s, hopArcDash: [%s], fadedStrokeOpacity: %s,\n"
              "        stallRingRadius: %s, stallRingFill: %s, stallRingStroke: %s,\n"
              "        litGlow: %s, litGlowWidth: %s, litGlowOpacity: %s, litGlowSeconds: %s)") % (
        colour(r["glow"]), num(r["glowWidth"]), colour(r["core"]), num(r["coreWidth"]), ", ".join(num(x) for x in r["dash"]),
        colour(b["outer"]), num(b["outerWidth"]), colour(b["inner"]), num(b["innerWidth"]), num(b.get("innerOpacity", 1)),
        colour(h["stroke"]), num(h["width"]), ", ".join(num(x) for x in h["dash"]), num(st["fadedStrokeOpacity"]),
        num(s["radius"]), colour(s["fill"]), colour(s["stroke"]),
        colour(g["color"]), num(g["width"]), num(g["opacity"]), num(g["seconds"]))

    learned = spec["learned"]
    touch = spec.get("touchDuringDemo", "endsDemoNoPaint")
    if touch not in ("endsDemoNoPaint", "endsDemoAndPaints"):
        fail("touchDuringDemo %r" % touch)
    clean_means = ", ".join(lit(x) for x in learned.get("cleanMeans", []))

    out = """// GENERATED by scripts/guidance_spec_to_swift.py from docs/tap-count-guidance-spec.json
// (the Opus 5.5 guidance build spec, visa-games-design/number-quantity/guidance/build, approved by Carter
// 2026-10-18). Do not edit by hand: change the JSON, re-run the script, and commit both.
import Foundation

public enum TapCountGuideData {
    public static let timing = %(timing)s

    public static func level(_ level: TapCountGuidanceLevel) -> TapCountGuideLevelSpec {
        switch level {
%(levels)s
        }
    }

    /// 識咗 = this many clean traces of a numeral in a row.
    public static let cleanInARow = %(clean)d
    public static let cleanMeans: [String] = [%(cleanMeans)s]
    /// One 識咗 record per numeral for both card languages (writing an 8 is the same skill).
    public static let sharedAcrossLanguages = %(shared)s
    /// The first touch during the demo ends it; true = that touch does not paint (mockup 01).
    public static let touchEndsDemoWithoutPaint = %(touch)s

    public static func numeral(_ n: Int) -> NumeralGuideSpec? {
        switch n {
%(numerals)s
        default:
            return nil
        }
    }

    public static let copy = %(copy)s

    public static let styles = %(styles)s
}
""" % {
        "timing": timing, "levels": "\n".join(levels), "clean": int(learned["cleanInARow"]), "cleanMeans": clean_means,
        "shared": "true" if learned.get("sharedAcrossLanguages", True) else "false",
        "touch": "true" if touch == "endsDemoNoPaint" else "false",
        "numerals": "\n".join(numerals), "copy": copy, "styles": styles,
    }
    open(args.out, "w", encoding="utf-8").write(out)
    print("wrote", os.path.relpath(args.out, ROOT))


if __name__ == "__main__":
    main()
