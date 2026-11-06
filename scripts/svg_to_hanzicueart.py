#!/usr/bin/env python3
"""Convert the Hanzi cue-art sprite into Swift `CanvasArtwork` data (Hanzi H2, 0.38.0 / 83).

Source: docs/hanzi-cue-art/illustrations.svg + illustration-style.css (byte copies of
visa-games-design/hanzi-tap/v2/assets, design D8: one shared SVG token style).
Output: Sources/VisaCore/HanziCueArt.swift (generated; do not edit by hand).

Reuses the 一架一架數 converter (scripts/svg_to_tapcountart.py) for geometry and Swift output, and adds:
  * colours, outlines, caps, joins and opacity come from the token sheet's class rules, applied in sheet
    order, with `var(--token)` resolved per element;
  * an inline `style` may only set custom properties (`left-hand-2`'s second skin tone, `car-top`'s outline
    widths); they cascade into everything below, including <use> clones;
  * <use> is inlined (transform kept); a <symbol> used inside another symbol must share its viewBox, so it maps
    one to one;
  * transforms are baked into the geometry; stroke widths scale by sqrt(|det|), so the bridge's
    `scale(1 1.4)` gives its outlines the geometric mean, not SVG's anisotropic stroke;
  * comments are dropped. Anything else fails loudly.
The output records an FNV-1a 64 fingerprint of both source files; HanziFindTests checks it, so a sprite edit
without a re-run fails the box tests.

Usage: python3 scripts/svg_to_hanzicueart.py [--sprite FILE] [--css FILE] [--out FILE] [--preview DIR]
"""
import argparse
import copy
import os
import re
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import svg_to_canvasart as base  # noqa: E402
import svg_to_tapcountart as tapcount  # noqa: E402

SVG = base.SVG
XLINK = "{http://www.w3.org/1999/xlink}href"
fmt = base.fmt
INHERITED = ["fill", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin"]
ELEMENT_ONLY = ["opacity"]
SHAPES = ("path", "circle", "ellipse", "rect")


def tag(node):
    return node.tag.replace(SVG, "")


def fnv1a64(data):
    value = 0xCBF29CE484222325
    for byte in data:
        value ^= byte
        value = (value * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return value


# ---------------------------------------------------------------- token sheet

def parse_css(text):
    """(:root custom properties, [(class name, [(property, value)])] in sheet order)."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    root_vars, rules = {}, []
    for selectors, body in re.findall(r"([^{}]+)\{([^{}]*)\}", text):
        decls = []
        for part in body.split(";"):
            if not part.strip():
                continue
            if ":" not in part:
                raise base.ConvertError("bad declaration %r" % part)
            name, value = part.split(":", 1)
            decls.append((name.strip(), value.strip()))
        selectors = [s.strip() for s in selectors.split(",")]
        if selectors == [":root"]:
            for name, value in decls:
                if not name.startswith("--"):
                    raise base.ConvertError(":root may only hold custom properties: %s" % name)
                root_vars[name] = value
            continue
        names = set()
        for selector in selectors:
            match = re.fullmatch(r"(?:\.ill\s*\.|\.ill\.|\.)([\w-]+)", selector)
            if not match:
                raise base.ConvertError("unsupported selector %r" % selector)
            names.add(match.group(1))
        if len(names) != 1:
            raise base.ConvertError("one class per rule: %s" % selectors)
        rules.append((names.pop(), decls))
    return root_vars, rules


def resolve(value, variables):
    def swap(match):
        name = match.group(1)
        if name not in variables:
            raise base.ConvertError("undefined %s" % name)
        return variables[name]
    for _ in range(4):
        value = re.sub(r"var\((--[\w-]+)\)", swap, value)
    if "var(" in value:
        raise base.ConvertError("unresolved %s" % value)
    return value


def colour(value):
    if value is None:
        return None
    value = value.strip()
    if value == "none":
        return None
    parsed = base.parse_color(value)
    return None if parsed == "none" else parsed


# ---------------------------------------------------------------- tree

class Context:
    def __init__(self, variables):
        self.style = {"fill": "#000000", "stroke": "none", "stroke-width": "1",
                      "stroke-linecap": "butt", "stroke-linejoin": "miter"}
        self.variables = dict(variables)
        self.opacity = 1.0
        self.matrix = base.identity()

    def child(self, node, rules):
        ctx = Context(self.variables)
        ctx.style = dict(self.style)
        ctx.opacity = self.opacity
        ctx.matrix = base.multiply(self.matrix, base.parse_transform(node.get("transform")))
        inline = node.get("style")
        if inline:
            for part in inline.split(";"):
                if not part.strip():
                    continue
                name, value = [p.strip() for p in part.split(":", 1)]
                if not name.startswith("--"):
                    raise base.ConvertError("inline style may only set custom properties: %r" % inline)
                ctx.variables[name] = value
        for key in INHERITED:
            if node.get(key) is not None:
                ctx.style[key] = node.get(key)
        element_opacity = float(node.get("opacity", "1"))
        classes = set((node.get("class") or "").split())
        for name, decls in rules:
            if name not in classes:
                continue
            for prop, value in decls:
                value = resolve(value, ctx.variables)
                if prop in INHERITED:
                    ctx.style[prop] = value
                elif prop == "opacity":
                    element_opacity = float(value)
                elif prop != "overflow":
                    raise base.ConvertError("unsupported property %s in .%s" % (prop, name))
        ctx.opacity *= element_opacity
        return ctx


def expand(node, by_id, host_view_box):
    """Inline every <use> below `node` (deep copies); nested symbols must share the host viewBox."""
    for index, child in enumerate(list(node)):
        t = tag(child)
        if t == "use":
            ref = child.get(XLINK) or child.get("href")
            if not ref or not ref.startswith("#") or ref[1:] not in by_id:
                raise base.ConvertError("unknown <use> %s" % ref)
            for key in child.attrib:
                if key not in (XLINK, "href", "transform"):
                    raise base.ConvertError("<use> attribute %s is not supported" % key)
            clone = copy.deepcopy(by_id[ref[1:]])
            clone.attrib.pop("id", None)
            if tag(clone) == "symbol":
                if clone.get("viewBox") != host_view_box:
                    raise base.ConvertError("nested symbol %s viewBox %s" % (ref, clone.get("viewBox")))
                clone.tag = SVG + "g"
                clone.attrib.pop("viewBox")
            wrapper = ET.Element(SVG + "g")
            if child.get("transform"):
                wrapper.set("transform", child.get("transform"))
            wrapper.append(clone)
            node[index] = wrapper
            child = wrapper
        expand(child, by_id, host_view_box)


def walk(node, ctx, rules, out):
    for child in node:
        t = tag(child)
        if t == "g":
            walk(child, ctx.child(child, rules), rules, out)
            continue
        if t not in SHAPES:
            raise base.ConvertError("<%s> is not supported" % t)
        here = ctx.child(child, rules)
        geo = tapcount.geometry(child, ctx.matrix)
        style = here.style
        fill = colour(style.get("fill"))
        stroke = colour(style.get("stroke"))
        m = base.multiply(ctx.matrix, base.parse_transform(child.get("transform")))
        width = float(style.get("stroke-width", "1")) * tapcount.matrix_scale(m)
        if stroke is None or width <= 0:
            stroke, width = None, 0.0
        if fill is None and stroke is None:
            continue
        out.append({"geo": geo, "fill": fill, "stroke": stroke, "width": width,
                    "cap": style.get("stroke-linecap", "butt"), "join": style.get("stroke-linejoin", "miter"),
                    "opacity": round(here.opacity, 3), "dash": [], "phase": 0.0, "clip": None})


def convert_symbol(symbol, by_id, root_vars, rules):
    view_box = symbol.get("viewBox")
    numbers = [float(v) for v in (view_box or "").split()]
    if len(numbers) != 4 or numbers[0] != 0 or numbers[1] != 0:
        raise base.ConvertError("symbol %s needs a 0 0 w h viewBox" % symbol.get("id"))
    tree = copy.deepcopy(symbol)
    expand(tree, by_id, view_box)
    out = []
    walk(tree, Context(root_vars).child(tree, rules), rules, out)
    if not out:
        raise base.ConvertError("symbol %s produced no elements" % symbol.get("id"))
    return numbers[2], numbers[3], out


def swift_name(ident):
    head, *rest = ident.split("-")
    return head + "".join(part[:1].upper() + part[1:] for part in rest)


def render(arts, sprite_hash, css_hash):
    lines = [
        "// GENERATED by scripts/svg_to_hanzicueart.py from docs/hanzi-cue-art/illustrations.svg and",
        "// illustration-style.css (design hanzi-tap v2 D8, six-target addendum). Do not edit by hand: change the",
        "// design sprite, copy it here, re-run the script, and commit both.",
        "import Foundation",
        "",
        "/// 中文字 cue pictures (Hanzi H2): one shared token style for every picture and mascot (D8). Each artwork",
        "/// keeps its symbol's 240 × 200 viewBox; names are `hanziCue.<symbol id>`.",
        "public enum HanziCueArt {",
        "    /// FNV-1a 64 of the sprite and the token sheet this file was generated from (checked by HanziFindTests).",
        "    public static let sourceFingerprint: (sprite: UInt64, stylesheet: UInt64) = (0x%016X, 0x%016X)"
        % (sprite_hash, css_hash),
        "",
        "    /// Every symbol in sprite order.",
        "    public static let all: [CanvasArtwork] = [",
        "        " + ", ".join(swift_name(a["id"]) for a in arts),
        "    ]",
        "",
        "    /// The artwork for a pack cue-picture ID (`person-standing`, `tree-2` …). Nil for an unknown ID: nothing",
        "    /// falls back to another picture.",
        "    public static func picture(_ id: String) -> CanvasArtwork? {",
        "        all.first { $0.name == \"hanziCue.\\(id)\" }",
        "    }",
        "",
    ]
    for a in arts:
        lines.append("    public static let %s = CanvasArtwork(name: \"hanziCue.%s\", width: %s, height: %s, elements: ["
                     % (swift_name(a["id"]), a["id"], fmt(a["w"]), fmt(a["h"])))
        lines.append(",\n".join("        " + base.swift_element(el) for el in a["elements"]))
        lines.append("    ])")
        lines.append("")
    lines += ["}", ""]
    return "\n".join(lines)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    art = os.path.join(here, "..", "docs", "hanzi-cue-art")
    parser = argparse.ArgumentParser()
    parser.add_argument("--sprite", default=os.path.join(art, "illustrations.svg"))
    parser.add_argument("--css", default=os.path.join(art, "illustration-style.css"))
    parser.add_argument("--out", default=os.path.join(here, "..", "Sources", "VisaCore", "HanziCueArt.swift"))
    parser.add_argument("--preview", default=None)
    args = parser.parse_args()
    with open(args.sprite, "rb") as handle:
        sprite_bytes = handle.read()
    with open(args.css, "rb") as handle:
        css_bytes = handle.read()
    root_vars, rules = parse_css(css_bytes.decode("utf-8"))
    root = ET.fromstring(sprite_bytes)
    by_id = {n.get("id"): n for n in root.iter() if n.get("id")}
    arts = []
    for symbol in root:
        if tag(symbol) != "symbol":
            if tag(symbol) != "defs":
                raise base.ConvertError("unexpected top-level <%s>" % tag(symbol))
            continue
        width, height, elements = convert_symbol(symbol, by_id, root_vars, rules)
        arts.append({"id": symbol.get("id"), "w": width, "h": height, "elements": elements})
    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write(render(arts, fnv1a64(sprite_bytes), fnv1a64(css_bytes)))
    print("wrote %s: %d artworks, %d elements" % (
        os.path.relpath(args.out), len(arts), sum(len(a["elements"]) for a in arts)))
    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
        try:
            import cairosvg
        except ImportError:
            cairosvg = None
        for a in arts:
            body = base.preview_svg(a["id"], a["w"], a["h"], a["elements"])
            path = os.path.join(args.preview, a["id"] + ".svg")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(body)
            if cairosvg:
                cairosvg.svg2png(bytestring=body.encode(), write_to=path[:-4] + ".png")


if __name__ == "__main__":
    try:
        main()
    except base.ConvertError as error:
        sys.stderr.write("svg_to_hanzicueart: %s\n" % error)
        sys.exit(1)
