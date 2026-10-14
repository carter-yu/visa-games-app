#!/usr/bin/env python3
"""Convert the approved 連一連 / Line Match SVG icons into Swift `CanvasArtwork` data.

Source of truth (design repo, Opus mockups):
  new-games/opus/icons-sheet.svg            21 picture icons (`ic-*`, 200×200 box each)
  new-games/opus/05i-line-match-numbers-star3.svg   count objects (chick, minifire, apple) + minitruck

Output: Sources/VisaCore/LineMatchArt.swift (generated; do not edit by hand).

The converter resolves SVG style inheritance (fill / stroke / width / caps / joins / opacity /
dashes), `clip-path` on groups, and `rotate()` / `translate()` transforms. Rotated ellipses are
baked into cubic path data; everything else keeps its primitive (circle / ellipse / rect / path).
It fails loudly on anything it does not understand, so a mockup change cannot be dropped silently.

Usage:
  python3 scripts/svg_to_canvasart.py [--design DIR] [--out FILE] [--preview DIR]

`--preview DIR` also writes `<name>.svg` re-built from the converted elements (and a PNG contact
sheet when cairosvg is installed) so the port can be compared with the mockups by eye.
"""
import argparse
import math
import os
import re
import sys
import xml.etree.ElementTree as ET

SVG = "{http://www.w3.org/2000/svg}"
XLINK = "{http://www.w3.org/1999/xlink}"

# icon key → (source file, element id). Order = order in the generated `all` list.
PICTURE_ICONS = [
    "eye", "ear", "mouth", "nose", "hand", "foot",
    "cat", "dog", "calf", "rabbit", "fawn", "monkey",
    "rat", "ox", "tiger", "dragon", "snake", "horse", "goat", "rooster", "pig",
]
# Objects drawn around (0, 0) in the mockup; the box moves them into positive space.
# (key, element id, minX, minY, width, height)
CENTRED_ICONS = [
    ("chick", "chick", -25, -27, 50, 50),
    ("minifire", "minifire", -28, -21, 56, 40),
    ("apple", "apple", -22, -27, 44, 48),
    ("minitruck", "minitruck", -106, -68, 210, 126),
]

INHERITED = ["fill", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin",
             "stroke-dasharray", "stroke-dashoffset"]


class ConvertError(Exception):
    pass


# ---------------------------------------------------------------- affine helpers

def identity():
    return (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)


def multiply(m, n):
    """m ∘ n (apply n first, then m). Matrices are (a, b, c, d, e, f) as in SVG."""
    a, b, c, d, e, f = m
    a2, b2, c2, d2, e2, f2 = n
    return (a * a2 + c * b2, b * a2 + d * b2,
            a * c2 + c * d2, b * c2 + d * d2,
            a * e2 + c * f2 + e, b * e2 + d * f2 + f)


def apply(m, x, y):
    a, b, c, d, e, f = m
    return (a * x + c * y + e, b * x + d * y + f)


def parse_transform(text):
    m = identity()
    if not text:
        return m
    for name, args in re.findall(r"(\w+)\s*\(([^)]*)\)", text):
        values = [float(v) for v in re.split(r"[\s,]+", args.strip()) if v]
        if name == "translate":
            tx = values[0]
            ty = values[1] if len(values) > 1 else 0.0
            step = (1.0, 0.0, 0.0, 1.0, tx, ty)
        elif name == "scale":
            sx = values[0]
            sy = values[1] if len(values) > 1 else sx
            step = (sx, 0.0, 0.0, sy, 0.0, 0.0)
        elif name == "rotate":
            angle = math.radians(values[0])
            cos, sin = math.cos(angle), math.sin(angle)
            rot = (cos, sin, -sin, cos, 0.0, 0.0)
            if len(values) == 3:
                cx, cy = values[1], values[2]
                step = multiply((1, 0, 0, 1, cx, cy), multiply(rot, (1, 0, 0, 1, -cx, -cy)))
            else:
                step = rot
        else:
            raise ConvertError("unsupported transform %s" % name)
        m = multiply(m, step)
    return m


def is_translation(m):
    a, b, c, d, _, _ = m
    return abs(a - 1) < 1e-9 and abs(d - 1) < 1e-9 and abs(b) < 1e-9 and abs(c) < 1e-9


# ---------------------------------------------------------------- path data

TOKEN = re.compile(r"[MmLlHhVvQqTtCcSsAaZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")


def translate_path(d, dx, dy):
    """Absolute-ise and translate SVG path data (M L H V Q T C S Z only)."""
    if dx == 0 and dy == 0:
        return " ".join(d.split())
    tokens = TOKEN.findall(d)
    out = []
    i = 0
    cmd = None
    cur = (0.0, 0.0)
    start = (0.0, 0.0)
    counts = {"M": 2, "L": 2, "H": 1, "V": 1, "Q": 4, "T": 2, "C": 6, "S": 4, "Z": 0}
    while i < len(tokens):
        tok = tokens[i]
        if re.match(r"[A-Za-z]", tok):
            cmd = tok
            i += 1
            if cmd in "Zz":
                out.append("Z")
                cur = start
                continue
        if cmd is None:
            raise ConvertError("path data without a command")
        upper = cmd.upper()
        if upper == "A":
            raise ConvertError("arc commands are not expected in the icons")
        n = counts[upper]
        nums = [float(t) for t in tokens[i:i + n]]
        if len(nums) != n:
            raise ConvertError("short path data: %s" % d)
        i += n
        rel = cmd.islower()
        if upper == "H":
            x = nums[0] + (cur[0] if rel else 0)
            out.append("L%s %s" % (fmt(x + dx), fmt(cur[1] + dy)))
            cur = (x, cur[1])
        elif upper == "V":
            y = nums[0] + (cur[1] if rel else 0)
            out.append("L%s %s" % (fmt(cur[0] + dx), fmt(y + dy)))
            cur = (cur[0], y)
        else:
            pts = []
            for k in range(0, n, 2):
                x = nums[k] + (cur[0] if rel else 0)
                y = nums[k + 1] + (cur[1] if rel else 0)
                pts.append((x, y))
            out.append(upper + " ".join("%s %s" % (fmt(x + dx), fmt(y + dy)) for x, y in pts))
            cur = pts[-1]
            if upper == "M":
                start = cur
                cmd = "l" if rel else "L"
    return " ".join(out)


def ellipse_path(cx, cy, rx, ry, m):
    """Ellipse as four cubic Béziers, transformed by `m`."""
    k = 0.5522847498307936
    pts = [
        (cx + rx, cy),
        (cx + rx, cy + k * ry), (cx + k * rx, cy + ry), (cx, cy + ry),
        (cx - k * rx, cy + ry), (cx - rx, cy + k * ry), (cx - rx, cy),
        (cx - rx, cy - k * ry), (cx - k * rx, cy - ry), (cx, cy - ry),
        (cx + k * rx, cy - ry), (cx + rx, cy - k * ry), (cx + rx, cy),
    ]
    t = [apply(m, x, y) for x, y in pts]
    parts = ["M%s %s" % (fmt(t[0][0]), fmt(t[0][1]))]
    for j in range(1, 13, 3):
        parts.append("C%s %s %s %s %s %s" % (fmt(t[j][0]), fmt(t[j][1]), fmt(t[j + 1][0]),
                                            fmt(t[j + 1][1]), fmt(t[j + 2][0]), fmt(t[j + 2][1])))
    parts.append("Z")
    return " ".join(parts)


def fmt(value):
    value = round(value, 2)
    if value == int(value):
        return str(int(value))
    return ("%.2f" % value).rstrip("0").rstrip(".")


# ---------------------------------------------------------------- styles

def parse_color(value):
    if value is None:
        return None
    value = value.strip()
    if value == "none":
        return "none"
    if re.fullmatch(r"#[0-9A-Fa-f]{6}", value):
        return value[1:].upper()
    if re.fullmatch(r"#[0-9A-Fa-f]{3}", value):
        return "".join(ch * 2 for ch in value[1:]).upper()
    named = {"white": "FFFFFF", "black": "000000"}
    if value in named:
        return named[value]
    raise ConvertError("unsupported colour %r" % value)


class Context:
    def __init__(self):
        self.style = {"fill": "#000000", "stroke": "none", "stroke-width": "1",
                      "stroke-linecap": "butt", "stroke-linejoin": "miter"}
        self.opacity = 1.0
        self.matrix = identity()
        self.clip = None  # geometry tuple in artwork space

    def child(self, node, clips):
        ctx = Context()
        ctx.style = dict(self.style)
        ctx.opacity = self.opacity
        ctx.matrix = multiply(self.matrix, parse_transform(node.get("transform")))
        ctx.clip = self.clip
        for key in INHERITED:
            if node.get(key) is not None:
                ctx.style[key] = node.get(key)
        if node.get("opacity") is not None:
            ctx.opacity *= float(node.get("opacity"))
        if node.get("clip-path"):
            ref = re.fullmatch(r"url\(#([^)]+)\)", node.get("clip-path").strip())
            if not ref or ref.group(1) not in clips:
                raise ConvertError("unknown clip %s" % node.get("clip-path"))
            if self.clip is not None:
                raise ConvertError("nested clips are not supported")
            shapes = list(clips[ref.group(1)])
            if len(shapes) != 1:
                raise ConvertError("clipPath %s must hold one shape" % ref.group(1))
            ctx.clip = geometry(shapes[0], ctx.matrix)
        return ctx


def geometry(node, matrix):
    """Geometry tuple of one shape in artwork space."""
    tag = node.tag.replace(SVG, "")
    m = multiply(matrix, parse_transform(node.get("transform")))
    num = lambda key, default=0.0: float(node.get(key, default))
    if tag == "path":
        if not is_translation(m):
            raise ConvertError("transformed <path> is not supported")
        return ("path", translate_path(node.get("d"), m[4], m[5]))
    if tag == "circle":
        if not is_translation(m):
            raise ConvertError("transformed <circle> is not supported")
        cx, cy = apply(m, num("cx"), num("cy"))
        return ("circle", cx, cy, num("r"))
    if tag == "ellipse":
        if is_translation(m):
            cx, cy = apply(m, num("cx"), num("cy"))
            return ("ellipse", cx, cy, num("rx"), num("ry"))
        return ("path", ellipse_path(num("cx"), num("cy"), num("rx"), num("ry"), m))
    if tag == "rect":
        if not is_translation(m):
            raise ConvertError("transformed <rect> is not supported")
        x, y = apply(m, num("x"), num("y"))
        rx = node.get("rx", node.get("ry", "0"))
        return ("rect", x, y, num("width"), num("height"), float(rx))
    raise ConvertError("unsupported shape <%s>" % tag)


def walk(node, ctx, clips, out):
    for child in node:
        tag = child.tag.replace(SVG, "")
        if tag == "g":
            walk(child, ctx.child(child, clips), clips, out)
            continue
        if tag in ("text", "tspan", "use", "clipPath", "defs", "title", "desc"):
            if tag in ("text", "use"):
                raise ConvertError("<%s> inside an icon is not supported" % tag)
            continue
        here = ctx.child(child, clips)
        geo = geometry(child, ctx.matrix)
        style = here.style
        fill = parse_color(style.get("fill"))
        stroke = parse_color(style.get("stroke"))
        width = float(style.get("stroke-width", "1"))
        if stroke == "none" or width <= 0:
            stroke = None
        if fill == "none":
            fill = None
        if fill is None and stroke is None:
            continue
        dash = []
        phase = 0.0
        if style.get("stroke-dasharray") and style.get("stroke-dasharray") != "none":
            dash = [float(v) for v in re.split(r"[\s,]+", style["stroke-dasharray"].strip()) if v]
            total = sum(dash) * (1 if len(dash) % 2 == 0 else 2)
            phase = float(style.get("stroke-dashoffset", "0")) % total if total > 0 else 0.0
        out.append({
            "geo": geo,
            "fill": fill,
            "stroke": stroke,
            "width": width if stroke else 0.0,
            "cap": style.get("stroke-linecap", "butt"),
            "join": style.get("stroke-linejoin", "miter"),
            "opacity": round(here.opacity, 3),
            "dash": dash,
            "phase": phase,
            "clip": here.clip,
        })


def load(path):
    tree = ET.parse(path)
    root = tree.getroot()
    by_id = {}
    clips = {}
    for node in root.iter():
        ident = node.get("id")
        if not ident:
            continue
        if node.tag.replace(SVG, "") == "clipPath":
            clips[ident] = node
        else:
            by_id[ident] = node
    return by_id, clips


def convert(node, clips, dx=0.0, dy=0.0):
    ctx = Context()
    ctx.matrix = (1.0, 0.0, 0.0, 1.0, dx, dy)
    ctx = ctx.child(node, clips)
    out = []
    walk(node, ctx, clips, out)
    if not out:
        raise ConvertError("icon %s produced no elements" % node.get("id"))
    return out


# ---------------------------------------------------------------- Swift output

def swift_geo(geo):
    kind = geo[0]
    if kind == "path":
        return '.path(LineMatchArtData.path("%s"))' % geo[1]
    if kind == "circle":
        return ".circle(cx: %s, cy: %s, r: %s)" % tuple(fmt(v) for v in geo[1:])
    if kind == "ellipse":
        return ".ellipse(cx: %s, cy: %s, rx: %s, ry: %s)" % tuple(fmt(v) for v in geo[1:])
    if kind == "rect":
        return ".rect(x: %s, y: %s, width: %s, height: %s, radius: %s)" % tuple(fmt(v) for v in geo[1:])
    raise ConvertError(kind)


def swift_element(el):
    args = []
    args.append("0x%s" % el["fill"] if el["fill"] else "nil")
    args.append("0x%s" % el["stroke"] if el["stroke"] else "nil")
    args.append(fmt(el["width"]))
    extra = []
    if el["stroke"]:
        if el["cap"] != "butt":
            extra.append("cap: .%s" % {"round": "round", "square": "butt"}.get(el["cap"], "butt"))
        if el["join"] != "miter":
            extra.append("join: .%s" % {"round": "round", "bevel": "round"}.get(el["join"], "miter"))
    if el["opacity"] != 1:
        extra.append("opacity: %s" % fmt(el["opacity"]))
    if el["dash"]:
        extra.append("dash: [%s]" % ", ".join(fmt(v) for v in el["dash"]))
        if el["phase"]:
            extra.append("dashPhase: %s" % fmt(el["phase"]))
    style = "LineMatchArtData.style(%s)" % ", ".join(args + extra)
    clip = ""
    if el["clip"] is not None:
        clip = ", clip: %s" % swift_geo(el["clip"])
    return "CanvasArtElement(geometry: %s, style: %s%s)" % (swift_geo(el["geo"]), style, clip)


def swift_identifier(key):
    return {"minifire": "miniFire", "minitruck": "miniTruck"}.get(key, key)


def render_swift(arts):
    lines = [
        "// GENERATED by scripts/svg_to_canvasart.py from the approved Opus mockups",
        "// (new-games/opus/icons-sheet.svg, 05i-line-match-numbers-star3.svg). Do not edit by hand:",
        "// change the SVG, re-run the script, and commit both.",
        "import Foundation",
        "",
        "/// 連一連 / Line Match vector art (design §6 素材清單, D10 A). Original icons only.",
        "/// Pictures share a 200 × 200 box; count objects and the mini truck keep their mockup size.",
        "public enum LineMatchArt {",
        "    /// Every artwork, pictures first. Names are `lineMatch.<key>`.",
        "    public static let all: [CanvasArtwork] = [",
        "        " + ", ".join(swift_identifier(k) for k, _, _, _ in arts),
        "    ]",
        "",
        "    /// Artwork for an icon key (`eye`, `rabbit`, `chick`, `minitruck` …). Nil for unknown keys.",
        "    public static func icon(_ key: String) -> CanvasArtwork? {",
        "        all.first { $0.name == \"lineMatch.\\(key)\" }",
        "    }",
        "",
    ]
    for key, width, height, elements in arts:
        lines.append("    public static let %s = CanvasArtwork(name: \"lineMatch.%s\", width: %s, height: %s, elements: ["
                     % (swift_identifier(key), key, fmt(width), fmt(height)))
        body = [("        " + swift_element(el)) for el in elements]
        lines.append(",\n".join(body))
        lines.append("    ])")
        lines.append("")
    lines += [
        "}",
        "",
        "/// Builders used by the generated tables (kept tiny so the type checker stays fast).",
        "enum LineMatchArtData {",
        "    static func path(_ data: String) -> [SVGPathCommand] {",
        "        // Unparsable data yields an empty path; LineMatchTests fails on any empty path.",
        "        (try? SVGPathData.parse(data)) ?? []",
        "    }",
        "",
        "    static func style(_ fill: UInt32?, _ stroke: UInt32?, _ width: Double,",
        "                      cap: CanvasArtStyle.LineCap = .butt, join: CanvasArtStyle.LineJoin = .miter,",
        "                      opacity: Double = 1, dash: [Double] = [], dashPhase: Double = 0) -> CanvasArtStyle {",
        "        CanvasArtStyle(fill: fill, stroke: stroke, lineWidth: width, dash: dash, lineCap: cap,",
        "                       lineJoin: join, opacity: opacity, dashPhase: dashPhase)",
        "    }",
        "}",
        "",
    ]
    return "\n".join(lines)


# ---------------------------------------------------------------- preview (round trip)

def preview_svg(key, width, height, elements):
    def geo_svg(geo):
        kind = geo[0]
        if kind == "path":
            return '<path d="%s"' % geo[1]
        if kind == "circle":
            return '<circle cx="%s" cy="%s" r="%s"' % tuple(fmt(v) for v in geo[1:])
        if kind == "ellipse":
            return '<ellipse cx="%s" cy="%s" rx="%s" ry="%s"' % tuple(fmt(v) for v in geo[1:])
        return '<rect x="%s" y="%s" width="%s" height="%s" rx="%s"' % tuple(fmt(v) for v in geo[1:])

    defs = []
    body = []
    for index, el in enumerate(elements):
        attrs = []
        attrs.append('fill="%s"' % ("#" + el["fill"] if el["fill"] else "none"))
        if el["stroke"]:
            attrs.append('stroke="#%s" stroke-width="%s"' % (el["stroke"], fmt(el["width"])))
            attrs.append('stroke-linecap="%s" stroke-linejoin="%s"' % (
                "round" if el["cap"] == "round" else "butt", "round" if el["join"] == "round" else "miter"))
            if el["dash"]:
                attrs.append('stroke-dasharray="%s" stroke-dashoffset="%s"' % (
                    " ".join(fmt(v) for v in el["dash"]), fmt(el["phase"])))
        if el["opacity"] != 1:
            attrs.append('opacity="%s"' % fmt(el["opacity"]))
        if el["clip"] is not None:
            defs.append('<clipPath id="c%d">%s/></clipPath>' % (index, geo_svg(el["clip"])))
            attrs.append('clip-path="url(#c%d)"' % index)
        body.append("%s %s/>" % (geo_svg(el["geo"]), " ".join(attrs)))
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s" width="%s" height="%s">'
            "<defs>%s</defs>%s</svg>" % (fmt(width), fmt(height), fmt(width * 2), fmt(height * 2),
                                         "".join(defs), "".join(body)))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser()
    parser.add_argument("--design", default=os.path.join(here, "..", "..", "visa-games-design", "new-games", "opus"))
    parser.add_argument("--out", default=os.path.join(here, "..", "Sources", "VisaCore", "LineMatchArt.swift"))
    parser.add_argument("--preview", default=None)
    args = parser.parse_args()

    sheet_ids, sheet_clips = load(os.path.join(args.design, "icons-sheet.svg"))
    numbers_ids, numbers_clips = load(os.path.join(args.design, "05i-line-match-numbers-star3.svg"))

    arts = []
    for key in PICTURE_ICONS:
        node = sheet_ids.get("ic-" + key)
        if node is None:
            raise ConvertError("icons-sheet.svg has no ic-%s" % key)
        arts.append((key, 200, 200, convert(node, sheet_clips)))
    for key, ident, min_x, min_y, width, height in CENTRED_ICONS:
        node = numbers_ids.get(ident)
        if node is None:
            raise ConvertError("05i has no #%s" % ident)
        arts.append((key, width, height, convert(node, numbers_clips, -min_x, -min_y)))

    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write(render_swift(arts))
    total = sum(len(e) for _, _, _, e in arts)
    print("wrote %s: %d artworks, %d elements" % (os.path.relpath(args.out), len(arts), total))

    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
        cells = []
        for key, width, height, elements in arts:
            svg = preview_svg(key, width, height, elements)
            with open(os.path.join(args.preview, key + ".svg"), "w", encoding="utf-8") as handle:
                handle.write(svg)
            cells.append((key, width, height, elements))
        try:
            import cairosvg  # noqa: F401
        except ImportError:
            print("cairosvg not installed: wrote preview SVGs only")
            return
        import cairosvg
        sheet = ['<svg xmlns="http://www.w3.org/2000/svg" width="1400" height="1000" viewBox="0 0 1400 1000">',
                 '<rect width="1400" height="1000" fill="#FFF9EC"/>']
        for index, (key, width, height, elements) in enumerate(cells):
            col, row = index % 7, index // 7
            scale = min(180 / width, 180 / height)
            inner = preview_svg(key, width, height, elements)
            inner = inner[inner.index(">") + 1:-len("</svg>")]
            sheet.append('<g transform="translate(%d %d) scale(%s)">%s</g>' % (
                col * 200 + 10, row * 240 + 10, fmt(scale), inner.replace('id="c', 'id="%s_c' % key)
                .replace("url(#c", "url(#%s_c" % key)))
            sheet.append('<text x="%d" y="%d" font-size="18" font-family="sans-serif">%s</text>' % (
                col * 200 + 20, row * 240 + 215, key))
        sheet.append("</svg>")
        cairosvg.svg2png(bytestring="".join(sheet).encode(), write_to=os.path.join(args.preview, "contact-sheet.png"))
        print("wrote %s" % os.path.join(args.preview, "contact-sheet.png"))


if __name__ == "__main__":
    try:
        main()
    except ConvertError as error:
        sys.stderr.write("svg_to_canvasart: %s\n" % error)
        sys.exit(1)
