#!/usr/bin/env python3
"""Draw the diagrams in docs/internals.md as standalone SVG files.

Run from anywhere: python3 docs/diagrams/generate.py
Each file carries its own styles (light, and dark under
prefers-color-scheme) because GitHub shows SVGs as images, where page CSS
and web fonts don't reach. Edit the coordinates below and re-run when the
mechanisms they draw change.
"""
import html
import os

OUT = os.path.dirname(os.path.abspath(__file__))
E = html.escape

STYLE = """
svg { --bg:#ffffff; --fg:#18212c; --muted:#5a6776; --node:#ffffff; --state:#e6eef8; --file:#f3f1ea;
  --priv:#9f3a2c; --priv-bg:#f8e7e3; --shown:#2f6b45; --shown-bg:#e3f1e7; --accent:#b25a00; }
@media (prefers-color-scheme: dark) {
  svg { --bg:#161d26; --fg:#e3e8ee; --muted:#93a0ae; --node:#1a222d; --state:#18283b; --file:#242219;
    --priv:#f09a8a; --priv-bg:#3a1f1b; --shown:#8fd3a5; --shown-bg:#173024; --accent:#f0a346; }
}
.bg { fill: var(--bg); }
.t { font: 13px "IBM Plex Sans", -apple-system, "Segoe UI", Helvetica, Arial, sans-serif; fill: var(--fg); }
.t.mono, .mono { font-family: "IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 12.5px; }
.t.small { font-size: 11.5px; }
.t.head { font: 600 13px "IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; letter-spacing: .04em; fill: var(--muted); }
.muted { fill: var(--muted); }
rect { stroke-width: 1.3; }
.node, .q { fill: var(--node); stroke: var(--fg); }
.q { stroke-width: 1.6; }
.state { fill: var(--state); stroke: var(--fg); }
.file { fill: var(--file); stroke: var(--fg); stroke-dasharray: 4 3; }
.priv { fill: var(--priv-bg); stroke: var(--priv); }
.priv-t { fill: var(--priv); font-weight: 600; }
.shown { fill: var(--shown-bg); stroke: var(--shown); }
.shown-t { fill: var(--shown); font-weight: 600; }
.priv-t.small, .shown-t.small { font-weight: 400; }
.edge { stroke: var(--fg); stroke-width: 1.3; opacity: .75; }
.edge-l { fill: var(--muted); }
.edge-accent { stroke: var(--accent); stroke-width: 2; }
.edge-accent-l, .accent-t { fill: var(--accent); }
.stopbar { stroke: var(--accent); stroke-width: 3; }
.ah { fill: var(--fg); }
.ah-accent { fill: var(--accent); }
"""

class Fig:
    def __init__(s, w, h, label):
        s.w, s.h, s.label, s.parts = w, h, label, []
    def box(s, x, y, w, h, lines, cls="node", mono=False, sub=None):
        s.parts.append(f'<rect class="{cls}" x="{x}" y="{y}" width="{w}" height="{h}" rx="6"/>')
        n = len(lines) + (1 if sub else 0)
        lh = 15
        y0 = y + h/2 - (n-1)*lh/2 + 4
        for i, t in enumerate(lines):
            c = "t mono" if mono else "t"
            s.parts.append(f'<text class="{c} {cls}-t" x="{x+w/2}" y="{y0+i*lh}" text-anchor="middle">{E(t)}</text>')
        if sub:
            s.parts.append(f'<text class="t small {cls}-t" x="{x+w/2}" y="{y0+len(lines)*lh}" text-anchor="middle">{E(sub)}</text>')
    def arrow(s, pts, label=None, lx=None, ly=None, cls="edge", anchor="middle", marker="arrow"):
        d = " ".join(f"{x},{y}" for x, y in pts)
        mk = f' marker-end="url(#{marker}-{s.mid})"' if marker else ""
        s.parts.append(f'<polyline class="{cls}" points="{d}" fill="none"{mk}/>')
        if label:
            if lx is None:
                (x1, y1), (x2, y2) = pts[0], pts[1]
                lx, ly = (x1+x2)/2, (y1+y2)/2 - 6
            s.parts.append(f'<text class="t small {cls}-l" x="{lx}" y="{ly}" text-anchor="{anchor}">{E(label)}</text>')
    def text(s, x, y, t, cls="t small", anchor="start"):
        s.parts.append(f'<text class="{cls}" x="{x}" y="{y}" text-anchor="{anchor}">{E(t)}</text>')
    def stop(s, x, y):
        s.parts.append(f'<line class="stopbar" x1="{x}" y1="{y-9}" x2="{x}" y2="{y+9}"/>')
    def render(s, mid):
        s.mid = mid
        return s
    def svg(s):
        m = s.mid
        defs = (f'<defs>'
                f'<marker id="arrow-{m}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" class="ah"/></marker>'
                f'<marker id="accent-{m}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" class="ah-accent"/></marker>'
                f'</defs>')
        return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {s.w} {s.h}" width="{s.w}" height="{s.h}" '
                f'role="img" aria-label="{E(s.label)}"><title>{E(s.label)}</title><style>{STYLE}</style>{defs}'
                f'<rect class="bg" x="0" y="0" width="{s.w}" height="{s.h}" rx="8"/>' + "".join(s.parts) + '</svg>\n')

# ---------- Figure 1: privacy decision ----------
f1 = Fig(780, 560, "Decision path for one column's privacy: your Private choice, then your Not private choice if the data is unchanged, then name patterns, then the automatic flag and your review of it.").render("f1")
QX, QW, QH = 30, 300, 50
OX, OW = 560, 200
rows = [30, 120, 210, 300, 390]
qs = [["Marked Private by you,", "or restricted in an imported file?"],
      ["Marked Not private by you", "for this exact data?"],
      ["Matches one of your", "private name patterns?"],
      ["Flagged automatically?", "(name word or value pattern)"],
      ["Your review of the flag"]]
for y, q in zip(rows, qs):
    f1.box(QX, y, QW, QH, q, cls="q")
cy = lambda y: y + QH/2
# outcomes
f1.box(OX, rows[0], OW, QH, ["private"], cls="priv", sub="set by you / from file")
f1.box(OX, rows[1], OW, QH, ["shown"], cls="shown", sub="examples and range")
f1.box(OX, rows[2], OW, QH, ["private"], cls="priv", sub="name pattern")
f1.box(OX, rows[3], OW, QH, ["shown"], cls="shown", sub="not flagged")
f1.arrow([(QX+QW, cy(rows[0])), (OX, cy(rows[0]))], "yes")
f1.arrow([(QX+QW, cy(rows[1])), (OX, cy(rows[1]))], "yes, data hash matches")
f1.arrow([(QX+QW, cy(rows[2])), (OX, cy(rows[2]))], "yes")
f1.arrow([(QX+QW, cy(rows[3])), (OX, cy(rows[3]))], "no")
# downs
for i, lab in enumerate(["no", None, "no", "yes"]):
    y1 = rows[i] + QH; y2 = rows[i+1]
    if i == 1:
        continue
    f1.arrow([(QX+QW/2, y1), (QX+QW/2, y2)], lab, lx=QX+QW/2+8, ly=(y1+y2)/2+4, anchor="start")
y1 = rows[1] + QH; y2 = rows[2]
f1.arrow([(QX+QW/2, y1), (QX+QW/2, y2)], "no, or the data has changed since", lx=QX+QW/2+8, ly=(y1+y2)/2+4, anchor="start", cls="edge-accent", marker="accent")
# review outcomes
ry = rows[4]
outs = [(ry-20, "private", "confirmed", "priv", "confirmed"),
        (ry+40, "shown", "not personal, same data", "shown", "not personal"),
        (ry+100, "private", "until you review", "priv", "not reviewed, or data changed")]
for oy, t, sub, cls, lab in outs:
    f1.box(OX, oy, OW, 44, [t], cls=cls, sub=sub)
xs = QX+QW
tx = xs + 40
f1.arrow([(xs, cy(ry)), (tx, cy(ry))], marker=None)
f1.parts.append(f'<line class="edge" x1="{tx}" y1="{ry+2}" x2="{tx}" y2="{ry+62}"/>')
f1.parts.append(f'<line class="edge-accent" x1="{tx}" y1="{ry+62}" x2="{tx}" y2="{ry+122}"/>')
f1.arrow([(tx, ry+2), (OX, ry+2)], "confirmed", lx=tx+12, ly=ry-4, anchor="start")
f1.arrow([(tx, ry+62), (OX, ry+62)], "not personal, same data", lx=tx+12, ly=ry+56, anchor="start")
f1.arrow([(tx, ry+122), (OX, ry+122)], "not reviewed, or data changed", lx=tx+12, ly=ry+116, anchor="start", cls="edge-accent", marker="accent")

# ---------- Figure 2: data-dict round trip ----------
f2 = Fig(860, 470, "What an export to data-dict YAML and a re-import into a fresh app carry across, and what stops on the way.").render("f2")
C = [(20, 230), (315, 230), (610, 230)]
heads = ["This app, with data", "data-dict.yaml", "A fresh app, no rows yet"]
for (x, w), h in zip(C, heads):
    f2.text(x + w/2, 26, h, "t head", "middle")
items = [
    ("Tables, column types", "tables[].columns[].type", "empty tables of that type", True),
    ("Primary keys", "constraints: [primary_key]", "declared keys", True),
    ("Declared, manual, confirmed links", "relationships: join", "declared links", True),
    ("Labels, descriptions, units", "label / description / units", "dictionary, empty fields only", True),
    ("Private columns", "display: restricted", "private, unless you chose", True),
    ("Real example values", "placeholders + todo", None, False),
    ("Unconfirmed or non-key links", "todo", None, False),
    ("Tables with no columns", "todo", None, False),
]
y = 46; RH = 34; GAP = 12
for a, b, c, passes in items:
    f2.box(C[0][0], y, C[0][1], RH, [a], cls="node")
    f2.box(C[1][0], y, C[1][1], RH, [b], cls="file", mono=True)
    f2.arrow([(C[0][0]+C[0][1], y+RH/2), (C[1][0], y+RH/2)])
    if passes:
        f2.box(C[2][0], y, C[2][1], RH, [c], cls="node")
        f2.arrow([(C[1][0]+C[1][1], y+RH/2), (C[2][0], y+RH/2)])
    else:
        x0 = C[1][0]+C[1][1]
        f2.arrow([(x0, y+RH/2), (x0+34, y+RH/2)], cls="edge-accent", marker=None)
        f2.stop(x0+34, y+RH/2)
        f2.text(x0+44, y+RH/2+4, "not imported", "t small accent-t")
    y += RH + GAP
f2.text(C[0][0], y+10, "An import never overwrites your own Private / Not private choice.", "t small muted")

# ---------- Figure 3: primary key precedence ----------
f3 = Fig(860, 330, "Primary keys stated by schema files, data-dict files and databases override detection unless the loaded data contradicts them.").render("f3")
srcs = [("Schema JSON / YAML", "primary_key: true"), ("data-dict file", "constraints: [primary_key]"), ("Database connection", "PRIMARY KEY constraints")]
for i, (a, b) in enumerate(srcs):
    f3.box(20, 30 + i*62, 200, 48, [a], cls="node", sub=b)
f3.box(290, 92, 150, 48, ["declared_pks_rv"], cls="state", mono=True, sub="saved with session")
for i in range(3):
    f3.arrow([(220, 54 + i*62), (255, 54+i*62), (255, 116), (290, 116)], None)
f3.box(290, 230, 150, 48, ["detect_pks()"], cls="node", mono=True, sub="names + uniqueness")
f3.box(510, 150, 130, 48, ["pk_map_rv"], cls="state", mono=True)
f3.arrow([(440, 116), (475, 116), (475, 166), (510, 166)], "overrides", lx=478, ly=110, anchor="start")
f3.arrow([(440, 254), (475, 254), (475, 184), (510, 184)], "candidates", lx=478, ly=270, anchor="start")
f3.box(700, 80, 145, 58, ["declared key"], cls="shown", sub="data agrees with it")
f3.box(700, 210, 145, 58, ["detected key"], cls="node", sub="data contradicts it")
f3.text(575, 216, "checked in erd_model()", "t small muted mono", "middle")
f3.arrow([(640, 166), (670, 166), (670, 109), (700, 109)])
f3.arrow([(640, 184), (670, 184), (670, 239), (700, 239)], cls="edge-accent", marker="accent")
f3.text(772, 286, "duplicates or NA", "t small accent-t", "middle")
f3.text(20, 312, "A data-dict table with no key stays keyless only while it has no rows.", "t small muted")

# ---------- Figure 4: app data flow ----------
f4 = Fig(900, 400, "How inputs write the app's shared state, how state is derived, and which tabs read it.").render("f4")
IX, IW = 20, 150
SX, SW = 250, 170
DX, DW = 500, 160
VX, VW = 740, 140
for x, w, t in [(IX, IW, "Inputs"), (SX, SW, "Shared state"), (DX, DW, "Derived"), (VX, VW, "Tabs")]:
    f4.text(x + w/2, 24, t, "t head", "middle")
c = lambda y: y + 20
BUS = 222
ins = [(40, "Upload files", None, "tables"), (110, "Import Schema", 1, "tables, links, keys, labels"),
       (180, "Database", 1, "tables, links, keys"), (280, "Remove / Clear all", None, "resets “not private”"),
       (340, "Restore session", 1, "replaces all state")]
for y, t, lab, sub in ins:
    f4.box(IX, y, IW, 40, [t], cls="node", sub=sub)
st = [(40, "all_tables_rv"), (100, "schema_rels_rv"), (160, "declared_pks_rv"), (220, "manual + confirmed"), (280, "dictionary_rv")]
for y, t in st:
    f4.box(SX, y, SW, 40, [t], cls="state", mono=True)
# bus from multi-target inputs to every state box
f4.parts.append(f'<line class="edge" x1="{BUS}" y1="{c(40)+8}" x2="{BUS}" y2="{c(340)}"/>')
for y, _ in st[1:]:
    f4.arrow([(BUS, c(y)-6 if y == 280 else c(y)), (SX, c(y)-6 if y == 280 else c(y))])
f4.arrow([(BUS, c(40)+8), (SX, c(40)+8)])
for y, t, lab, sub in ins:
    if lab:
        f4.arrow([(IX+IW, c(y)), (BUS, c(y))], marker=None)
f4.arrow([(IX+IW, c(40)), (SX, c(40))])
f4.arrow([(IX+IW, c(280)+6), (SX, c(280)+6)], None, cls="edge-accent", marker="accent")
# derived
dv = [(70, "pk_map_rv", True), (160, "detection", False), (250, "relationships", False)]
for y, t, m in dv:
    f4.box(DX, y, DW, 40, [t], cls="state" if m else "node", mono=m)
SR = SX + SW
f4.arrow([(SR, c(40)-6), (460, c(40)-6), (460, c(70)-6), (DX, c(70)-6)])
f4.arrow([(SR, c(160)), (475, c(160)), (475, c(70)+6), (DX, c(70)+6)])
f4.text(481, 140, "overrides", "t small edge-l")
f4.arrow([(SR, c(40)+6), (448, c(40)+6), (448, c(160)-8), (DX, c(160)-8)])
f4.arrow([(DX+DW/2, 110), (DX+DW/2, 160)])
f4.arrow([(DX+DW/2, 200), (DX+DW/2, 250)], "detected", lx=DX+DW/2+8, ly=230, anchor="start")
f4.arrow([(SR, c(100)), (436, c(100)), (436, c(250)-6), (DX, c(250)-6)])
f4.arrow([(SR, c(220)), (DX, c(250)+6)])
# tabs
vw = [(40, "ERD"), (110, "Relationships"), (180, "Data Dictionary"), (250, "Export")]
for y, t in vw:
    f4.box(VX, y, VW, 40, [t], cls="node")
DR = DX + DW
f4.parts.append(f'<line class="edge" x1="{DR}" y1="{c(250)}" x2="700" y2="{c(250)}"/>')
f4.parts.append(f'<line class="edge" x1="700" y1="{c(40)}" x2="700" y2="{c(250)}"/>')
for y, _ in vw:
    f4.arrow([(700, c(y)-4 if y >= 180 else c(y)), (VX, c(y)-4 if y >= 180 else c(y))])
# dictionary route underneath
f4.arrow([(SX+SW/2, 320), (SX+SW/2, 372), (720, 372), (720, c(180)+6), (VX, c(180)+6)], "labels, privacy", lx=560, ly=366)
f4.arrow([(720, c(250)+6), (VX, c(250)+6)])

for name, fig in [("privacy-decision", f1), ("data-dict-round-trip", f2),
                  ("primary-keys", f3), ("app-data-flow", f4)]:
    with open(os.path.join(OUT, name + ".svg"), "w", encoding="utf-8") as fh:
        fh.write(fig.svg())
