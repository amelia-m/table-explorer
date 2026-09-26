#!/usr/bin/env node
// ============================================================
// check_erd_geometry.js - verify ERD edge/marker alignment
// ============================================================
//
// Lays out ELK graph JSON (the app's "ELK graph (.json)" export, or
// generate_elk_json()) with elkjs and checks every relationship end:
//   - the port sits on its column's row (|dy| < 1 px)
//   - the line ends on the card border
//   - the final segment is perpendicular to the border and at least one
//     crow's-foot marker long, so markers never sit on a bend
// Optionally writes an SVG preview with crow's-foot markers drawn at the
// ends, for a visual check.
//
// Usage:
//   npm install elkjs            (once, anywhere on NODE_PATH)
//   node dev/check_erd_geometry.js erd.elk.json [more.json] [--svg out.svg]
// Exit code 1 if any end fails.

const fs = require("fs");
const ELK = require("elkjs");

const MARKER = 16; // crow's-foot marker length, px

function portRows(node) {
  const g = node.properties || {};
  const cols = g.columns || [];
  return { cols, find: (name) => cols.findIndex((c) => c.name === name) };
}

async function layout(file) {
  const graph = JSON.parse(fs.readFileSync(file, "utf8"));
  const out = await new ELK().layout(graph);
  out.properties = graph.properties || {};
  return out;
}

function check(out) {
  const head = out.properties.headerHeight || 28;
  const row = out.properties.rowHeight || 20;
  const ports = {};
  for (const n of out.children) {
    const { find } = portRows(n);
    for (const p of n.ports || []) {
      const col = p.id.slice(n.id.length + 1).replace(/:(in|out)$/, "");
      ports[p.id] = { node: n, rowCentre: head + (find(col) + 0.5) * row };
    }
  }
  const fails = [];
  let ends = 0;
  for (const e of out.edges) {
    for (const s of e.sections || []) {
      const pts = [s.startPoint, ...(s.bendPoints || []), s.endPoint];
      const sides = [
        [pts[0], pts[1], e.sources[0]],
        [pts[pts.length - 1], pts[pts.length - 2], e.targets[0]],
      ];
      for (const [P, Q, pid] of sides) {
        ends++;
        const { node: n, rowCentre } = ports[pid];
        const dy = Math.abs(P.y - n.y - rowCentre);
        const onBorder =
          Math.min(Math.abs(P.x - n.x), Math.abs(P.x - n.x - n.width)) < 1;
        const perpendicular = Math.abs(Q.y - P.y) < 0.5;
        const len = Math.hypot(Q.x - P.x, Q.y - P.y);
        const problems = [];
        if (dy >= 1) problems.push(`port ${dy.toFixed(1)}px off row`);
        if (!onBorder) problems.push("not on card border");
        if (!perpendicular) problems.push("not perpendicular");
        if (len < MARKER + 4) problems.push(`final segment ${len.toFixed(1)}px`);
        if (problems.length) fails.push(`${e.id} ${pid}: ${problems.join(", ")}`);
      }
    }
  }
  return { ends, fails };
}

// ── SVG preview ─────────────────────────────────────────────
function esc(s) {
  return String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
}

// Marker drawn at end point P, pointing into the card along direction d
// (+1 = card to the right of P, -1 = card to the left). kind: one of
// "one", "zeroOne", "many", "zeroMany", "unknown".
function marker(P, d, kind) {
  const x = (o) => P.x + d * o;
  const bar = (o) => `<line x1="${x(o)}" y1="${P.y - 6}" x2="${x(o)}" y2="${P.y + 6}"/>`;
  const circle = (o) => `<circle cx="${x(o)}" cy="${P.y}" r="4" fill="white"/>`;
  const crow = () =>
    `<line x1="${x(0)}" y1="${P.y - 6}" x2="${x(-8)}" y2="${P.y}"/>` +
    `<line x1="${x(0)}" y1="${P.y + 6}" x2="${x(-8)}" y2="${P.y}"/>`;
  // Marker spine: always solid, whatever the line style
  const spine = `<line x1="${x(0)}" y1="${P.y}" x2="${x(-MARKER)}" y2="${P.y}"/>`;
  const parts = {
    one: bar(-5) + bar(-9),
    zeroOne: bar(-5) + circle(-12),
    many: crow() + bar(-11),
    zeroMany: crow() + circle(-12),
    unknown: "",
  }[kind] || "";
  return `<g class="marker">${spine}${parts}</g>`;
}

function svg(out) {
  const head = out.properties.headerHeight || 28;
  const row = out.properties.rowHeight || 20;
  const nodes = Object.fromEntries(out.children.map((n) => [n.id, n]));
  let body = "";
  for (const n of out.children) {
    const cols = (n.properties && n.properties.columns) || [];
    body += `<g transform="translate(${n.x},${n.y})">`;
    body += `<rect width="${n.width}" height="${n.height}" fill="white" stroke="#334155"/>`;
    body += `<rect width="${n.width}" height="${head}" fill="${esc((n.properties || {}).headerColor || "#1E3A5F")}"/>`;
    body += `<text x="8" y="${head - 9}" fill="white" font-weight="700">${esc(n.id)}</text>`;
    cols.forEach((c, i) => {
      const y = head + i * row;
      const badge = [c.pk ? "PK" : "", c.fk ? `FK${c.fk}` : "", c.uk ? "UK" : ""].filter(Boolean).join(",");
      body += `<text x="6" y="${y + 14}" font-size="10" fill="#b45309">${badge}</text>`;
      body += `<text x="48" y="${y + 14}">${esc(c.name)}</text>`;
      body += `<text x="${n.width - 8}" y="${y + 14}" text-anchor="end" fill="#64748b">${esc(c.type)}${c.nullable ? " ∅" : ""}</text>`;
      if (i > 0) body += `<line x1="0" y1="${y}" x2="${n.width}" y2="${y}" stroke="#e2e8f0"/>`;
    });
    body += "</g>";
  }
  for (const e of out.edges) {
    const pr = e.properties || {};
    const dash = pr.identifying ? "" : ' stroke-dasharray="6 4"';
    for (const s of e.sections || []) {
      const pts = [s.startPoint, ...(s.bendPoints || []), s.endPoint];
      body += `<polyline fill="none" points="${pts.map((p) => `${p.x},${p.y}`).join(" ")}"${dash}/>`;
      const src = nodes[e.sources[0].split(".")[0]];
      const tgt = nodes[e.targets[0].split(".")[0]];
      const dirInto = (P, n) => (Math.abs(P.x - n.x) < 1 ? 1 : -1);
      const childKind = pr.childMax === "one" ? "zeroOne" : pr.childMax === "many" ? "zeroMany" : "unknown";
      const parentKind = pr.parentMin === "one" ? "one" : pr.parentMin === "zero" ? "zeroOne" : "unknown";
      body += marker(pts[0], dirInto(pts[0], src), childKind);
      body += marker(pts[pts.length - 1], dirInto(pts[pts.length - 1], tgt), parentKind);
    }
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${out.width + 40}" height="${out.height + 40}" font-family="sans-serif" font-size="12"><style>text{stroke:none}</style><g transform="translate(20,20)" stroke="#0f172a" stroke-width="1.4">${body}</g></svg>`;
}

(async () => {
  const args = process.argv.slice(2);
  const svgAt = args.indexOf("--svg");
  const svgOut = svgAt >= 0 ? args.splice(svgAt, 2)[1] : null;
  let failed = 0;
  for (const f of args) {
    const out = await layout(f);
    const { ends, fails } = check(out);
    console.log(`${f}: ${ends} relationship ends, ${fails.length} failing`);
    fails.slice(0, 20).forEach((m) => console.log("  " + m));
    failed += fails.length;
    if (svgOut) fs.writeFileSync(args.length > 1 ? `${f}.svg` : svgOut, svg(out));
  }
  process.exit(failed ? 1 : 0);
})().catch((e) => {
  console.error(e);
  process.exit(2);
});
