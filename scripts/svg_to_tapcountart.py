#!/usr/bin/env python3
"""Convert the 一架一架數 art source into Swift `CanvasArtwork` data (v0.28.0, ADR 0017).

Source: docs/art-tap-count-source.svg — elements copied verbatim from the approved Opus mockups in
visa-games-design/number-quantity/mockups 01–10 plus the Opus scene kit (see the comment at its top).
Output: Sources/VisaCore/TapCountArt.swift (generated; do not edit by hand).

Reuses the 連一連 converter (scripts/svg_to_canvasart.py) for colours, styles and Swift output, and adds:
  * <use> is inlined (x/y/transform kept); `style="color:#RRGGBB"` resolves currentColor,
    an unresolved currentColor becomes the tint sentinel #C0FFEE (TapCountArt.tinted swaps it);
  * transforms of any affine kind are baked into the geometry, stroke widths and dashes scale with them;
  * <line>/<polygon>/<polyline> become paths; S/T/H/V/A path commands are normalised;
  * shapes filled with a radialGradient become TapCountGlow records (drawn under the artwork);
  * <text> is dropped: the app draws every word and numeral itself.
Anything else still fails loudly.

Usage: python3 scripts/svg_to_tapcountart.py [--source FILE] [--out FILE] [--preview DIR]
"""
import argparse
import copy
import math
import os
import re
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import svg_to_canvasart as base  # noqa: E402

SVG = base.SVG
XLINK = "{http://www.w3.org/1999/xlink}href"
SENTINEL = "#C0FFEE"
fmt = base.fmt

# (swift name, svg id). Origin (0, 0) of the def is the anchor the app places on a stage point.
CENTRED = [
    ("tram", "tram"), ("fireEngine", "fire-engine"), ("digger", "digger"), ("mixer", "mixer"),
    ("dumper", "dumper"), ("dozer", "dozer"), ("roller", "roller"), ("craneTruck", "crane-truck"),
    ("plane", "plane"), ("bus", "bus"), ("miniCar", "mini-car"),
    ("lampOn", "lamp-on"), ("fireEngineLit", "fe-lit"), ("beaconOn", "beacon-on"),
    ("planeLit", "plane-lit"), ("busLit", "bus-lit"),
    ("glow", "glow"), ("bayGlow", "bay-glow"), ("spark", "spark"), ("sparkle", "sparkle"),
    ("ding", "ding"), ("honk", "honk"), ("note", "note"), ("speaker", "speaker"), ("star", "star"),
    ("go", "go"), ("end", "end"), ("paintCar", "paint-car"), ("tickSmall", "tick-s"),
    ("chevron", "chev"), ("goSmall", "go-s"), ("endSmall", "end-s"), ("ringSmall", "ring-s"),
    ("stopSmall", "stop-s"),
    ("eraserButton", "btn-eraser"), ("okButton", "btn-ok-on"), ("tile", "tile-bg"),
    ("iconAll", "icon-all"), ("iconTrace", "icon-trace"), ("iconPick", "icon-pick"),
    # v0.30.0 numeral-formation guidance (guidance mockups 01–03)
    ("guideGhostCar", "guide-ghost-car"), ("guideChev", "guide-chev"), ("guideAhead", "guide-ahead"),
    ("guideStop", "guide-stop"), ("guideEye", "guide-eye"), ("guidePop", "guide-pop"), ("guideHopHead", "guide-hop-head"), ("guidePen", "guide-pen"), ("guideStartDot", "guide-start-dot"),
]
SCENES = ["tramDepot", "fireStation", "site", "airport", "busTerminus"]
# Stage backdrops from the Opus scene kit (1280 × 720, origin top-left) and its bottom-centred symbols.
KIT_STAGE = [("%s_%s" % (layout, scene), "%s-%s" % (layout, scene)) for layout in ("row", "yard", "strip") for scene in SCENES]
KIT_SYMBOLS = [("%s_%s" % (kind.replace("-", ""), scene), "%s-%s" % (kind, scene)) for kind in ("bay-post", "empty") for scene in SCENES]


def tag(node):
    return node.tag.replace(SVG, "")


# ---------------------------------------------------------------- path normalisation

TOKEN = re.compile(r"[MmLlHhVvQqTtCcSsAaZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")
COUNTS = {"M": 2, "L": 2, "H": 1, "V": 1, "Q": 4, "T": 2, "C": 6, "S": 4, "A": 7, "Z": 0}


def arc_to_cubics(p0, rx, ry, phi, large, sweep, p1):
    """SVG endpoint arc → list of cubic control triples (absolute)."""
    if rx == 0 or ry == 0 or p0 == p1:
        return [(p0, p1, p1)]
    rx, ry = abs(rx), abs(ry)
    cp, sp = math.cos(math.radians(phi)), math.sin(math.radians(phi))
    dx, dy = (p0[0] - p1[0]) / 2, (p0[1] - p1[1]) / 2
    x1p, y1p = cp * dx + sp * dy, -sp * dx + cp * dy
    lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    co = math.sqrt(max(0.0, num / den)) * (-1 if large == sweep else 1)
    cxp, cyp = co * rx * y1p / ry, -co * ry * x1p / rx
    cx = cp * cxp - sp * cyp + (p0[0] + p1[0]) / 2
    cy = sp * cxp + cp * cyp + (p0[1] + p1[1]) / 2

    def ang(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a
    t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not sweep and dt > 0:
        dt -= 2 * math.pi
    elif sweep and dt < 0:
        dt += 2 * math.pi
    n = max(1, int(math.ceil(abs(dt) / (math.pi / 2) - 1e-9)))
    step = dt / n
    k = 4 / 3 * math.tan(step / 4)
    out = []

    def pt(t):
        return (cx + rx * math.cos(t) * cp - ry * math.sin(t) * sp, cy + rx * math.cos(t) * sp + ry * math.sin(t) * cp)

    def dpt(t):
        return (-rx * math.sin(t) * cp - ry * math.cos(t) * sp, -rx * math.sin(t) * sp + ry * math.cos(t) * cp)
    for i in range(n):
        a, b = t1 + i * step, t1 + (i + 1) * step
        pa, pb, da, db = pt(a), pt(b), dpt(a), dpt(b)
        out.append(((pa[0] + k * da[0], pa[1] + k * da[1]), (pb[0] - k * db[0], pb[1] - k * db[1]), pb))
    return out


def normalise(d):
    """Absolute M / L / Q / C / Z segments: [(cmd, [points])]."""
    tokens = TOKEN.findall(d)
    segs = []
    i, cmd = 0, None
    cur = start = (0.0, 0.0)
    last_c = last_q = None
    while i < len(tokens):
        tok = tokens[i]
        if re.match(r"[A-Za-z]", tok):
            cmd = tok
            i += 1
            if cmd in "Zz":
                segs.append(("Z", []))
                cur = start
                last_c = last_q = None
                continue
        if cmd is None:
            raise base.ConvertError("path data without a command")
        up = cmd.upper()
        n = COUNTS[up]
        nums = [float(t) for t in tokens[i:i + n]]
        if len(nums) != n:
            raise base.ConvertError("short path data: %s" % d)
        i += n
        rel = cmd.islower()
        ox, oy = (cur if rel else (0.0, 0.0))
        if up == "M":
            cur = start = (nums[0] + ox, nums[1] + oy)
            segs.append(("M", [cur]))
            cmd = "l" if rel else "L"
            last_c = last_q = None
        elif up in "LHV":
            if up == "L":
                p = (nums[0] + ox, nums[1] + oy)
            elif up == "H":
                p = (nums[0] + (cur[0] if rel else 0), cur[1])
            else:
                p = (cur[0], nums[0] + (cur[1] if rel else 0))
            segs.append(("L", [p]))
            cur = p
            last_c = last_q = None
        elif up in "CS":
            if up == "C":
                c1 = (nums[0] + ox, nums[1] + oy)
                rest = nums[2:]
            else:
                c1 = (2 * cur[0] - last_c[0], 2 * cur[1] - last_c[1]) if last_c else cur
                rest = nums
            c2 = (rest[0] + ox, rest[1] + oy)
            p = (rest[2] + ox, rest[3] + oy)
            segs.append(("C", [c1, c2, p]))
            last_c, last_q, cur = c2, None, p
        elif up in "QT":
            if up == "Q":
                c = (nums[0] + ox, nums[1] + oy)
                p = (nums[2] + ox, nums[3] + oy)
            else:
                c = (2 * cur[0] - last_q[0], 2 * cur[1] - last_q[1]) if last_q else cur
                p = (nums[0] + ox, nums[1] + oy)
            segs.append(("Q", [c, p]))
            last_q, last_c, cur = c, None, p
        elif up == "A":
            p = (nums[5] + ox, nums[6] + oy)
            for c1, c2, q in arc_to_cubics(cur, nums[0], nums[1], nums[2], int(nums[3]), int(nums[4]), p):
                segs.append(("C", [c1, c2, q]))
            cur = p
            last_c = last_q = None
    return segs


def affine_path(d, m):
    parts = []
    for cmd, pts in normalise(d):
        if cmd == "Z":
            parts.append("Z")
            continue
        tp = [base.apply(m, x, y) for x, y in pts]
        parts.append(cmd + " ".join("%s %s" % (fmt(x), fmt(y)) for x, y in tp))
    return " ".join(parts)


def rect_path(x, y, w, h, r):
    r = min(r, w / 2, h / 2)
    if r <= 0:
        return "M%s %s H%s V%s H%s Z" % (x, y, x + w, y + h, x)
    k = 0.5522847498307936 * r
    return ("M{a} {y} L{b} {y} C{bk} {y} {r2} {yk} {r2} {c} L{r2} {d} C{r2} {dk} {bk} {yb} {b} {yb} "
            "L{a} {yb} C{ak} {yb} {x} {dk} {x} {d} L{x} {c} C{x} {yk} {ak} {y} {a} {y} Z").format(
        a=x + r, b=x + w - r, y=y, bk=x + w - r + k, r2=x + w, yk=y + r - k, c=y + r, d=y + h - r,
        dk=y + h - r + k, yb=y + h, ak=x + r - k, x=x)


def is_axis(m):
    return abs(m[1]) < 1e-9 and abs(m[2]) < 1e-9


def geometry(node, matrix):
    t = tag(node)
    m = base.multiply(matrix, base.parse_transform(node.get("transform")))
    num = lambda key, default=0.0: float(node.get(key, default))
    if t == "path":
        return ("path", affine_path(node.get("d"), m))
    if t == "circle":
        cx, cy = base.apply(m, num("cx"), num("cy"))
        if is_axis(m) and abs(abs(m[0]) - abs(m[3])) < 1e-9:
            return ("circle", cx, cy, num("r") * abs(m[0]))
        if is_axis(m):
            return ("ellipse", cx, cy, num("r") * abs(m[0]), num("r") * abs(m[3]))
        return ("path", base.ellipse_path(num("cx"), num("cy"), num("r"), num("r"), m))
    if t == "ellipse":
        if is_axis(m):
            cx, cy = base.apply(m, num("cx"), num("cy"))
            return ("ellipse", cx, cy, num("rx") * abs(m[0]), num("ry") * abs(m[3]))
        return ("path", base.ellipse_path(num("cx"), num("cy"), num("rx"), num("ry"), m))
    if t == "rect":
        r = float(node.get("rx", node.get("ry", "0")))
        if is_axis(m) and m[0] > 0 and abs(m[0] - m[3]) < 1e-9:
            x, y = base.apply(m, num("x"), num("y"))
            return ("rect", x, y, num("width") * m[0], num("height") * m[0], r * m[0])
        return ("path", affine_path(rect_path(num("x"), num("y"), num("width"), num("height"), r), m))
    raise base.ConvertError("unsupported shape <%s>" % t)


base.geometry = geometry  # Context.child resolves clip shapes through the module global.


def matrix_scale(m):
    return math.sqrt(abs(m[0] * m[3] - m[1] * m[2]))


# ---------------------------------------------------------------- tree preprocessing

def points_to_path(node, closed):
    nums = [float(v) for v in re.split(r"[\s,]+", node.get("points", "").strip()) if v]
    pts = list(zip(nums[0::2], nums[1::2]))
    if not pts:
        raise base.ConvertError("empty <%s>" % tag(node))
    d = "M%s %s " % pts[0] + " ".join("L%s %s" % p for p in pts[1:]) + (" Z" if closed else "")
    return d


def preprocess(root):
    pristine = {n.get("id"): copy.deepcopy(n) for n in root.iter() if n.get("id")}
    grads = {}
    for n in root.iter():
        if tag(n) == "radialGradient":
            stops = []
            for s in n:
                stops.append((float(s.get("offset", "0")), base.parse_color(s.get("stop-color")),
                              float(s.get("stop-opacity", "1"))))
            grads[n.get("id")] = stops

    def fix(node, colour):
        st = node.get("style")
        if st is not None:
            mm = re.fullmatch(r"\s*color:\s*(#[0-9A-Fa-f]{6})\s*;?\s*", st)
            if not mm:
                raise base.ConvertError("unsupported style %r" % st)
            colour = mm.group(1)
            del node.attrib["style"]
        if node.get("color"):
            colour = node.get("color")
            del node.attrib["color"]
        for key in ("fill", "stroke"):
            if node.get(key) == "currentColor":
                node.set(key, colour or SENTINEL)
        t = tag(node)
        if t == "line":
            node.tag = SVG + "path"
            node.set("d", "M%s %s L%s %s" % tuple(node.attrib.pop(k, "0") for k in ("x1", "y1", "x2", "y2")))
        elif t in ("polygon", "polyline"):
            d = points_to_path(node, t == "polygon")
            node.attrib.pop("points")
            node.tag = SVG + "path"
            node.set("d", d)
        return colour

    def expand(parent, colour):
        new = []
        for child in list(parent):
            t = tag(child)
            if t in ("text", "tspan", "title", "desc"):
                continue
            if t == "use":
                ref = child.get(XLINK) or child.get("href")
                if not ref or ref[1:] not in pristine:
                    raise base.ConvertError("unknown <use> %s" % ref)
                g = ET.Element(SVG + "g")
                for k, v in child.attrib.items():
                    if k not in (XLINK, "href", "x", "y", "transform", "width", "height", "id"):
                        g.set(k, v)
                tr = (child.get("transform", "") + " translate(%s %s)" % (child.get("x", "0"), child.get("y", "0"))).strip()
                g.set("transform", tr)
                clone = copy.deepcopy(pristine[ref[1:]])
                clone.attrib.pop("id", None)
                g.append(clone)
                child = g
            c = fix(child, colour)
            expand(child, c)
            new.append(child)
        parent[:] = new

    return grads, fix, expand


def build(node, grads, fix, expand):
    node = copy.deepcopy(node)
    colour = fix(node, None)
    wrapper = ET.Element(SVG + "g")
    wrapper.append(node)
    expand(node, colour)
    return wrapper


# ---------------------------------------------------------------- walk (base.walk + scaling + glows)

def walk(node, ctx, clips, out, glows, grads):
    for child in node:
        t = tag(child)
        if t == "g":
            walk(child, ctx.child(child, clips), clips, out, glows, grads)
            continue
        if t in ("clipPath", "defs", "linearGradient", "radialGradient", "stop"):
            continue
        if t in ("text", "use", "image", "filter", "mask"):
            raise base.ConvertError("<%s> is not supported" % t)
        here = ctx.child(child, clips)
        m = base.multiply(ctx.matrix, base.parse_transform(child.get("transform")))
        geo = geometry(child, ctx.matrix)
        style = here.style
        k = matrix_scale(m)
        raw_fill = (style.get("fill") or "").strip()
        ref = re.fullmatch(r"url\(#([^)]+)\)", raw_fill)
        if ref:
            if ref.group(1) not in grads:
                raise base.ConvertError("only radial gradients are supported: %s" % raw_fill)
            if geo[0] not in ("circle", "ellipse"):
                raise base.ConvertError("gradient fill on <%s>" % t)
            cx, cy = geo[1], geo[2]
            rx = geo[3]
            ry = geo[4] if geo[0] == "ellipse" else geo[3]
            glows.append({"cx": cx, "cy": cy, "rx": rx, "ry": ry, "opacity": round(here.opacity, 3),
                          "stops": grads[ref.group(1)]})
            continue
        fill = base.parse_color(style.get("fill"))
        stroke = base.parse_color(style.get("stroke"))
        width = float(style.get("stroke-width", "1")) * k
        if stroke == "none" or width <= 0:
            stroke = None
        if fill == "none":
            fill = None
        if fill is None and stroke is None:
            continue
        dash, phase = [], 0.0
        if style.get("stroke-dasharray") and style.get("stroke-dasharray") != "none":
            dash = [float(v) * k for v in re.split(r"[\s,]+", style["stroke-dasharray"].strip()) if v]
            total = sum(dash) * (1 if len(dash) % 2 == 0 else 2)
            phase = float(style.get("stroke-dashoffset", "0")) * k % total if total > 0 else 0.0
        out.append({"geo": geo, "fill": fill, "stroke": stroke, "width": width if stroke else 0.0,
                    "cap": style.get("stroke-linecap", "butt"), "join": style.get("stroke-linejoin", "miter"),
                    "opacity": round(here.opacity, 3), "dash": dash, "phase": phase, "clip": here.clip})


def convert(node, clips, grads, dx=0.0, dy=0.0):
    ctx = base.Context()
    ctx.matrix = (1.0, 0.0, 0.0, 1.0, dx, dy)
    out, glows = [], []
    walk(node, ctx, clips, out, glows, grads)
    if not out and not glows:
        raise base.ConvertError("art produced no elements")
    return out, glows


def bounds(elements, glows):
    xs, ys = [], []
    for el in elements:
        geo, pad = el["geo"], el["width"] / 2 + 1
        if geo[0] == "path":
            for cmd, pts in normalise(geo[1]):
                for x, y in pts:
                    xs += [x - pad, x + pad]
                    ys += [y - pad, y + pad]
        elif geo[0] == "circle":
            xs += [geo[1] - geo[3] - pad, geo[1] + geo[3] + pad]
            ys += [geo[2] - geo[3] - pad, geo[2] + geo[3] + pad]
        elif geo[0] == "ellipse":
            xs += [geo[1] - geo[3] - pad, geo[1] + geo[3] + pad]
            ys += [geo[2] - geo[4] - pad, geo[2] + geo[4] + pad]
        else:
            xs += [geo[1] - pad, geo[1] + geo[3] + pad]
            ys += [geo[2] - pad, geo[2] + geo[4] + pad]
    for g in glows:
        xs += [g["cx"] - g["rx"], g["cx"] + g["rx"]]
        ys += [g["cy"] - g["ry"], g["cy"] + g["ry"]]
    return math.floor(min(xs)), math.floor(min(ys)), math.ceil(max(xs)), math.ceil(max(ys))


# ---------------------------------------------------------------- Swift output

def swift_glow(g):
    stops = ", ".join("TapCountGlowStop(offset: %s, color: 0x%s, opacity: %s)" % (fmt(o), c, fmt(a))
                      for o, c, a in g["stops"])
    return ("TapCountGlow(cx: %s, cy: %s, rx: %s, ry: %s, opacity: %s, stops: [%s])"
            % (fmt(g["cx"]), fmt(g["cy"]), fmt(g["rx"]), fmt(g["ry"]), fmt(g["opacity"]), stops))


def render(arts, kit_present):
    lines = [
        "// GENERATED by scripts/svg_to_tapcountart.py from docs/art-tap-count-source.svg",
        "// (copied from the approved Opus mockups, visa-games-design/number-quantity/mockups 01–10,",
        "// and the Opus scene kit). Do not edit by hand: change the SVG, re-run the script, and commit both.",
        "import Foundation",
        "",
        "/// One stop of a radial glow (SVG radialGradient in the mockups).",
        "public struct TapCountGlowStop: Equatable, Sendable {",
        "    public let offset: Double",
        "    public let color: UInt32",
        "    public let opacity: Double",
        "}",
        "",
        "/// A radial glow under an artwork, in the artwork's own box.",
        "public struct TapCountGlow: Equatable, Sendable {",
        "    public let cx: Double",
        "    public let cy: Double",
        "    public let rx: Double",
        "    public let ry: Double",
        "    public let opacity: Double",
        "    public let stops: [TapCountGlowStop]",
        "}",
        "",
        "/// 一架一架數 / Tap & Count vector art (design §6, ADR 0017). Original art only.",
        "public enum TapCountArt {",
        "    /// The body colour placeholder (SVG currentColor). `tinted(_:body:)` swaps it for a palette colour.",
        "    public static let bodySentinel: UInt32 = 0xC0FFEE",
        "    /// True once the Opus scene kit (row / yard / strip backdrops) is part of the source.",
        "    public static let hasSceneKit = %s" % ("true" if kit_present else "false"),
        "",
        "    /// Every artwork. Names are `tapCount.<name>`.",
        "    public static let all: [CanvasArtwork] = [",
        "        " + ", ".join(a["name"] for a in arts),
        "    ]",
        "",
        "    /// Artwork by short name (`tram`, `row_site`, `empty_airport` …).",
        "    public static func named(_ name: String) -> CanvasArtwork? {",
        "        all.first { $0.name == \"tapCount.\\(name)\" }",
        "    }",
        "",
        "    /// Where the art's origin (its mockup anchor) sits inside its box.",
        "    public static func anchor(_ artwork: CanvasArtwork) -> LineMatchPoint {",
        "        anchors[artwork.name] ?? LineMatchPoint(x: 0, y: 0)",
        "    }",
        "",
        "    /// Radial glows drawn under the artwork (lamp halos, sparks, beacons).",
        "    public static func glows(_ artwork: CanvasArtwork) -> [TapCountGlow] {",
        "        glowTable[artwork.name] ?? []",
        "    }",
        "",
        "    /// The artwork with every sentinel fill / stroke replaced by `body` (0xRRGGBB).",
        "    public static func tinted(_ artwork: CanvasArtwork, body: UInt32) -> CanvasArtwork {",
        "        CanvasArtwork(name: artwork.name, width: artwork.width, height: artwork.height,",
        "                      elements: artwork.elements.map { element in",
        "                          var style = element.style",
        "                          if style.fill == bodySentinel { style.fill = body }",
        "                          if style.stroke == bodySentinel { style.stroke = body }",
        "                          return CanvasArtElement(geometry: element.geometry, style: style, clip: element.clip)",
        "                      })",
        "    }",
        "",
        "    static let anchors: [String: LineMatchPoint] = [",
        ",\n".join('        "tapCount.%s": LineMatchPoint(x: %s, y: %s)' % (a["name"], fmt(a["ax"]), fmt(a["ay"])) for a in arts),
        "    ]",
        "",
        "    static let glowTable: [String: [TapCountGlow]] = [",
    ]
    glow_lines = ['        "tapCount.%s": [%s]' % (a["name"], ", ".join(swift_glow(g) for g in a["glows"]))
                  for a in arts if a["glows"]]
    lines.append(",\n".join(glow_lines) if glow_lines else "        :")
    lines += ["    ]", ""]
    for a in arts:
        lines.append("    public static let %s = CanvasArtwork(name: \"tapCount.%s\", width: %s, height: %s, elements: ["
                     % (a["name"], a["name"], fmt(a["w"]), fmt(a["h"])))
        lines.append(",\n".join("        " + base.swift_element(el) for el in a["elements"]))
        lines.append("    ])")
        lines.append("")
    lines += ["}", ""]
    return "\n".join(lines)


def preview(arts, directory):
    os.makedirs(directory, exist_ok=True)
    try:
        import cairosvg
    except ImportError:
        cairosvg = None
    for a in arts:
        body = base.preview_svg(a["name"], a["w"], a["h"], a["elements"])
        glow_defs, glow_body = [], []
        for i, g in enumerate(a["glows"]):
            stops = "".join('<stop offset="%s" stop-color="#%s" stop-opacity="%s"/>' % (fmt(o), c, fmt(o2)) for o, c, o2 in g["stops"])
            glow_defs.append('<radialGradient id="g%d">%s</radialGradient>' % (i, stops))
            glow_body.append('<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="url(#g%d)" opacity="%s"/>' % (
                fmt(g["cx"]), fmt(g["cy"]), fmt(g["rx"]), fmt(g["ry"]), i, fmt(g["opacity"])))
        body = body.replace("<defs>", "<defs>" + "".join(glow_defs), 1).replace("</defs>", "</defs>" + "".join(glow_body), 1)
        path = os.path.join(directory, a["name"] + ".svg")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(body)
        if cairosvg:
            cairosvg.svg2png(bytestring=body.encode(), write_to=path[:-4] + ".png")


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default=os.path.join(here, "..", "docs", "art-tap-count-source.svg"))
    parser.add_argument("--out", default=os.path.join(here, "..", "Sources", "VisaCore", "TapCountArt.swift"))
    parser.add_argument("--preview", default=None)
    args = parser.parse_args()
    root = ET.parse(args.source).getroot()
    by_id = {n.get("id"): n for n in root.iter() if n.get("id")}
    clips = {i: n for i, n in by_id.items() if tag(n) == "clipPath"}
    grads, fix, expand = preprocess(root)
    kit_present = all(ident in by_id for _, ident in KIT_STAGE + KIT_SYMBOLS)
    wanted = [(n, i, False) for n, i in CENTRED]
    if kit_present:
        wanted += [(n, i, True) for n, i in KIT_STAGE] + [(n, i, False) for n, i in KIT_SYMBOLS]
    arts = []
    for name, ident, stage in wanted:
        node = by_id.get(ident)
        if node is None:
            raise base.ConvertError("art source has no #%s" % ident)
        tree = build(node, grads, fix, expand)
        if stage:
            elements, glows = convert(tree, clips, grads)
            arts.append({"name": name, "w": 1280, "h": 720, "ax": 0, "ay": 0, "elements": elements, "glows": glows})
            continue
        elements, glows = convert(tree, clips, grads)
        x0, y0, x1, y1 = bounds(elements, glows)
        elements, glows = convert(tree, clips, grads, -x0, -y0)
        arts.append({"name": name, "w": x1 - x0, "h": y1 - y0, "ax": -x0, "ay": -y0, "elements": elements, "glows": glows})
    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write(render(arts, kit_present))
    print("wrote %s: %d artworks, %d elements, scene kit %s" % (
        os.path.relpath(args.out), len(arts), sum(len(a["elements"]) for a in arts), "yes" if kit_present else "no"))
    if args.preview:
        preview(arts, args.preview)


if __name__ == "__main__":
    try:
        main()
    except base.ConvertError as error:
        sys.stderr.write("svg_to_tapcountart: %s\n" % error)
        sys.exit(1)
