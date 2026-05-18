#!/usr/bin/env python3
"""
Build assets/atomic-hyprland.ttf from assets/atomic-hyprland-logo_uniform.svg.

The TTF holds a single visible glyph at U+E901 plus the six letters of
"atomic" wired up as a GSUB ligature, so both of these render the logo
in any pango/freetype context with font='atomic-hyprland':

    <span font='atomic-hyprland'>&#xE901;</span>
    <span font='atomic-hyprland'>atomic</span>

Run from the repo root:

    python3 scripts/build-font.py

Requires fontTools (>=4.0). Re-run whenever the source SVG changes.
"""

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

# fontTools may live in user site-packages on some setups
for site in ("/home/oameye/.local/lib/python3.13/site-packages",
             "/home/oameye/.local/lib/python3.12/site-packages"):
    if Path(site).is_dir() and site not in sys.path:
        sys.path.insert(0, site)

from fontTools.fontBuilder import FontBuilder
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.misc.transform import Identity, Transform
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.svgLib.path import parse_path

REPO = Path(__file__).resolve().parent.parent
SVG = REPO / "assets" / "atomic-hyprland-logo_uniform.svg"
OUT = REPO / "assets" / "atomic-hyprland.ttf"

EM = 1024            # standard TTF em square
ASCENT = 800
DESCENT = -224
LIGATURE = "atomic"  # typing this renders the logo glyph
LIGATURE_GLYPHS = list(LIGATURE)
LOGO_CODEPOINT = 0xE901  # PUA — omarchy.ttf already claims U+E900
NS = {"svg": "http://www.w3.org/2000/svg"}


def parse_matrix(s):
    """Parse SVG transform="matrix(a,b,c,d,e,f)" into a 6-tuple."""
    s = s.strip()
    assert s.startswith("matrix("), s
    inner = s[len("matrix("):-1]
    parts = [float(p) for p in inner.replace(",", " ").split()]
    assert len(parts) == 6
    return tuple(parts)


def transform_from_matrix(s):
    """Parse SVG transform="matrix(a,b,c,d,e,f)" into a fontTools Transform.
    The parameter order matches: both encode the affine
    (x',y') = (a*x + c*y + e,  b*x + d*y + f)."""
    return Transform(*parse_matrix(s))


def collect_paths(svg_root):
    """Yield (path_d, composed_transform) for every path in the SVG, where
    composed_transform is a fontTools Transform that maps the path's local
    coordinates into SVG user space."""
    def walk(node, ctx):
        t = node.get("transform")
        if t:
            local = transform_from_matrix(t)
            ctx = ctx.transform(local)
        if node.tag == f"{{{NS['svg']}}}path":
            yield node.get("d"), ctx
        for child in node:
            yield from walk(child, ctx)
    yield from walk(svg_root, Identity)


def viewbox(svg_root):
    vb = svg_root.get("viewBox").split()
    return tuple(float(v) for v in vb)  # (x, y, w, h)


def empty_glyph():
    return TTGlyphPen(None).glyph()


def main():
    tree = ET.parse(SVG)
    root = tree.getroot()
    vbx, vby, vbw, vbh = viewbox(root)

    # Map SVG user-space onto a 1024x1024 em square: fit by max dimension,
    # flip Y (SVG is y-down, TrueType is y-up), and center.
    fit = EM / max(vbw, vbh)
    pad_x = (EM - vbw * fit) / 2
    pad_y = (EM - vbh * fit) / 2
    # (x, y) -> (x*fit + pad_x - vbx*fit,  EM - pad_y - (y - vby)*fit)
    svg_to_em = (
        Identity
        .translate(pad_x - vbx * fit, EM - pad_y + vby * fit)
        .scale(fit, -fit)
    )

    pen = TTGlyphPen(None)
    qpen = Cu2QuPen(pen, max_err=1.0, all_quadratic=True)
    for d, local_xform in collect_paths(root):
        if not d:
            continue
        final = svg_to_em.transform(local_xform)
        tpen = TransformPen(qpen, tuple(final))
        parse_path(d, tpen)
    logo_glyph = pen.glyph()

    glyph_order = [".notdef", "logo"] + LIGATURE_GLYPHS
    glyphs = {".notdef": empty_glyph(), "logo": logo_glyph}
    metrics = {".notdef": (EM, 0), "logo": (EM, 0)}
    for ch in LIGATURE_GLYPHS:
        glyphs[ch] = empty_glyph()
        metrics[ch] = (0, 0)
    cmap = {LOGO_CODEPOINT: "logo"}
    for ch in LIGATURE_GLYPHS:
        cmap[ord(ch)] = ch

    fb = FontBuilder(EM, isTTF=True)
    fb.setupGlyphOrder(glyph_order)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=ASCENT, descent=DESCENT)
    fb.setupOS2(
        sTypoAscender=ASCENT,
        sTypoDescender=DESCENT,
        usWinAscent=ASCENT,
        usWinDescent=-DESCENT,
    )
    fb.setupNameTable({
        "familyName": "atomic-hyprland",
        "styleName": "Regular",
        "uniqueFontIdentifier": "atomic-hyprland-1.0",
        "fullName": "atomic-hyprland",
        "psName": "atomic-hyprland",
        "version": "Version 1.0",
    })
    fb.setupPost()

    fea = (
        "languagesystem DFLT dflt;\n"
        "languagesystem latn dflt;\n"
        "feature liga {\n"
        f"    sub {' '.join(LIGATURE_GLYPHS)} by logo;\n"
        "} liga;\n"
    )
    addOpenTypeFeaturesFromString(fb.font, fea)

    fb.font.save(OUT)
    print(f"wrote {OUT.relative_to(REPO)} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
