// ============================================================
// erd.js - ERD Diagram renderer (elkjs layout + hand-drawn SVG)
// ============================================================
//
// The server (R/mod_erd.R) sends an ELK graph built by erd_elk_graph():
// one node per table (columns in node.properties) with ports pinned to the
// FK row (":out", east side) and the PK row (":in", west side). elkjs lays
// it out with orthogonal routing; this file draws the cards, the lines and
// the crow's-foot ends, and handles pan/zoom, hover, clicks and downloads.
//
// Crow's-foot ends (standard physical-ERD reading):
//   parent end (PK side)  ||  exactly one      |o  zero or one
//   child end  (FK side)  }o  zero or many     o|  zero or one
// Solid line = identifying (FK is part of the child's PK), dashed = not.
// Inferred, unconfirmed links are muted with a "?" chip.

(function () {
  "use strict";

  var MARKER = 16; // marker length, px (see dev/check_erd_geometry.js)
  var PAD = 20; // margin around the diagram
  var GUTTER = 44; // key-badge column width
  var MAX_FIT_ZOOM = 1.4; // Fit never enlarges a small diagram beyond this
  var MAX_EDGES = 600; // beyond this, ask the user to narrow the view first
  var SVGNS = "http://www.w3.org/2000/svg";
  var FONT = "'IBM Plex Sans', 'Helvetica Neue', Arial, sans-serif";

  var states = {}; // container id -> render state
  window.erdStates = states; // for tests

  // ── helpers ────────────────────────────────────────────────
  function el(tag, attrs, parent) {
    var e = document.createElementNS(SVGNS, tag);
    for (var k in attrs) {
      if (attrs[k] !== null && attrs[k] !== undefined) e.setAttribute(k, attrs[k]);
    }
    if (parent) parent.appendChild(e);
    return e;
  }
  function text(parent, x, y, str, attrs) {
    var t = el("text", Object.assign({ x: x, y: y }, attrs || {}), parent);
    t.textContent = str;
    return t;
  }
  function esc(s) {
    return String(s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }
  function fmt(n) {
    return n === null || n === undefined ? "" : Number(n).toLocaleString("en-US");
  }
  function cssVar(name, fallback) {
    var v = getComputedStyle(document.body).getPropertyValue(name).trim();
    return v || fallback;
  }
  function theme() {
    var light = document.body.classList.contains("light-mode");
    return {
      bg: cssVar("--bg-surface", light ? "#ffffff" : "#1e293b"),
      card: cssVar("--tbl-card-bg", light ? "#f8fafc" : "#0f172a"),
      zebra: cssVar("--tbl-row-hover", light ? "#f1f5f9" : "#1e293b"),
      text: cssVar("--text-primary", light ? "#0f172a" : "#e2e8f0"),
      type: cssVar("--text-secondary", light ? "#475569" : "#94a3b8"),
      muted: cssVar("--text-muted", "#64748b"),
      grid: cssVar("--border-sub", light ? "#e2e8f0" : "#334155"),
      border: light ? "#64748b" : "#64748b",
      accent: cssVar("--accent", light ? "#2563eb" : "#60a5fa"),
      pk: cssVar("--warn", light ? "#a16207" : "#facc15"),
      fk: cssVar("--accent", light ? "#2563eb" : "#60a5fa"),
      uk: cssVar("--success", light ? "#15803d" : "#4ade80"),
      light: light,
    };
  }
  function isVisible(node) {
    return !!node && node.offsetWidth > 0 && node.offsetHeight > 0;
  }

  // Layout-relevant part of the graph; equal signatures reuse the layout
  // (so confirming a link restyles it without moving anything)
  function signature(g) {
    return JSON.stringify({
      o: g.layoutOptions,
      n: g.children.map(function (n) {
        return [n.id, n.width, n.height, (n.ports || []).map(function (p) {
          return [p.id, p.x, p.y];
        })];
      }),
      e: g.edges.map(function (e) {
        return [e.id, e.sources[0], e.targets[0]];
      }),
    });
  }

  function markerKinds(pr) {
    return {
      child:
        pr.childMax === "one" ? "zeroOne" : pr.childMax === "many" ? "zeroMany" : "unknown",
      parent:
        pr.parentMin === "one" ? "one" : pr.parentMin === "zero" ? "zeroOne" : "unknown",
    };
  }

  // Crow's-foot marker at end point P. d = +1 when the card is to the
  // right of P, -1 when it is to the left. The spine is always solid.
  function drawMarker(g, P, d, kind, color, bg) {
    var m = el("g", { class: "erd-marker", stroke: color, "stroke-width": 1.4, fill: "none" }, g);
    var x = function (o) {
      return P.x + d * o;
    };
    var bar = function (o) {
      el("line", { x1: x(o), y1: P.y - 6, x2: x(o), y2: P.y + 6 }, m);
    };
    var circle = function (o) {
      el("circle", { cx: x(o), cy: P.y, r: 4, fill: bg }, m);
    };
    var crow = function () {
      el("line", { x1: x(0), y1: P.y - 6, x2: x(-8), y2: P.y }, m);
      el("line", { x1: x(0), y1: P.y + 6, x2: x(-8), y2: P.y }, m);
    };
    el("line", { x1: x(0), y1: P.y, x2: x(-MARKER), y2: P.y }, m);
    if (kind === "one") {
      bar(-5);
      bar(-9);
    } else if (kind === "zeroOne") {
      bar(-5);
      circle(-12);
    } else if (kind === "many") {
      crow();
      bar(-11);
    } else if (kind === "zeroMany") {
      crow();
      circle(-12);
    } else {
      // unknown cardinality (empty table): neutral open end
      el("circle", { cx: x(-6), cy: P.y, r: 2, fill: color }, m);
    }
    return m;
  }

  function pointAtHalf(pts) {
    var segs = [], total = 0;
    for (var i = 1; i < pts.length; i++) {
      var l = Math.hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y);
      segs.push(l);
      total += l;
    }
    var half = total / 2;
    for (var j = 0; j < segs.length; j++) {
      if (half <= segs[j] && segs[j] > 0) {
        var t = half / segs[j];
        return {
          x: pts[j].x + t * (pts[j + 1].x - pts[j].x),
          y: pts[j].y + t * (pts[j + 1].y - pts[j].y),
        };
      }
      half -= segs[j];
    }
    return pts[0];
  }

  function edgeColor(pr, th) {
    return pr.provenance === "inferred" ? th.muted : th.text;
  }

  // ── drawing ────────────────────────────────────────────────
  function drawCard(parent, n, th, props) {
    var pr = n.properties || {};
    var cols = pr.columns || [];
    var head = props.headerHeight || 28;
    var row = props.rowHeight || 20;
    var g = el("g", {
      class: "erd-node",
      "data-table": n.id,
      transform: "translate(" + n.x + "," + n.y + ")",
    }, parent);
    var title = el("title", {}, g);
    title.textContent =
      n.id + " — " + fmt(pr.rows) + " rows · " + pr.subjectArea +
      (pr.role && pr.role !== "entity" ? " · " + pr.role : "") +
      (pr.hiddenColumns ? " · " + pr.hiddenColumns + " columns hidden" : "");

    el("rect", {
      class: "erd-card",
      width: n.width, height: n.height, rx: 4,
      fill: th.card, stroke: th.border, "stroke-width": 1,
      "stroke-dasharray": pr.role === "junction" ? "5 3" : null,
    }, g);
    // Header (rounded top only when there are rows below)
    el("path", {
      class: "erd-header",
      d: cols.length || props.detail !== "names"
        ? "M0," + head + " V4 Q0,0 4,0 H" + (n.width - 4) + " Q" + n.width + ",0 " + n.width + ",4 V" + head + " Z"
        : "M0,4 Q0,0 4,0 H" + (n.width - 4) + " Q" + n.width + ",0 " + n.width + ",4 V" + (head - 4) +
          " Q" + n.width + "," + head + " " + (n.width - 4) + "," + head + " H4 Q0," + head + " 0," + (head - 4) + " Z",
      fill: pr.headerColor || "#1E3A5F",
    }, g);
    text(g, 8, head / 2 + 4, n.id, {
      fill: "#ffffff", "font-weight": 700, "font-size": 12, class: "erd-title",
    });
    var count = fmt(pr.rows) + (pr.hiddenColumns && cols.length ? " · +" + pr.hiddenColumns : "");
    if (n.id.length * 7.6 + count.length * 6 + 24 < n.width) {
      text(g, n.width - 8, head / 2 + 4, count, {
        fill: "#ffffff", "fill-opacity": 0.75, "font-size": 10, "text-anchor": "end",
      });
    }
    if (props.detail === "names") return g;

    var npk = 0;
    cols.forEach(function (c, i) {
      var y = head + i * row;
      if (c.pk) npk = i + 1;
      if (i % 2 === 1) {
        el("rect", { x: 1, y: y, width: n.width - 2, height: row, fill: th.zebra }, g);
      }
      var badges = [];
      if (c.pk) badges.push(["PK", th.pk]);
      if (c.fk) badges.push(["FK" + c.fk, th.fk]);
      if (c.uk && !c.pk) badges.push(["UK", th.uk]);
      var bx = 6;
      var badgeText = text(g, bx, y + 14, "", { "font-size": 9, "font-weight": 700 });
      badges.forEach(function (b, k) {
        var ts = el("tspan", { fill: b[1] }, badgeText);
        ts.textContent = (k ? "," : "") + b[0];
      });
      var name = text(g, GUTTER, y + 14, c.name, {
        fill: th.text, "font-size": 12, "font-weight": c.pk ? 600 : 400,
        "text-decoration": c.pk ? "underline" : null,
      });
      name.setAttribute("class", "erd-col");
      text(g, n.width - 8, y + 14, (c.type || "") + (c.nullable ? " ∅" : ""), {
        fill: th.type, "font-size": 10, "text-anchor": "end",
      });
    });
    if (!cols.length) {
      text(g, GUTTER, head + 14, pr.hiddenColumns ? "(" + pr.hiddenColumns + " columns hidden)" : "(no columns)", {
        fill: th.muted, "font-size": 11, "font-style": "italic",
      });
    }
    // Rule under the PK section
    if (npk > 0 && npk < cols.length) {
      el("line", {
        x1: 0, x2: n.width, y1: head + npk * row, y2: head + npk * row,
        stroke: th.border, "stroke-width": 1,
      }, g);
    }
    return g;
  }

  function drawEdge(parent, e, nodes, th) {
    var pr = e.properties || {};
    var color = edgeColor(pr, th);
    var g = el("g", {
      class: "erd-edge erd-prov-" + pr.provenance,
      "data-key": pr.key,
      "data-from": pr.fromTable,
      "data-to": pr.toTable,
    }, parent);
    var title = el("title", {}, g);
    title.textContent =
      pr.fromTable + "." + pr.fromCol + " → " + pr.toTable + "." + pr.toCol +
      " (" + pr.provenance + (pr.provenance === "inferred" && pr.confidence ? ", " + pr.confidence : "") + ")";
    var kinds = markerKinds(pr);
    var src = nodes[pr.fromTable], tgt = nodes[pr.toTable];
    (e.sections || []).forEach(function (s) {
      var pts = [s.startPoint].concat(s.bendPoints || [], [s.endPoint]);
      var ptsAttr = pts.map(function (p) { return p.x + "," + p.y; }).join(" ");
      el("polyline", {
        class: "erd-hit", points: ptsAttr, fill: "none",
        stroke: "transparent", "stroke-width": 10,
      }, g);
      el("polyline", {
        class: "erd-line", points: ptsAttr, fill: "none", stroke: color,
        "stroke-width": 1.4, "stroke-dasharray": pr.identifying ? null : "6 4",
      }, g);
      var into = function (P, n) {
        return n && Math.abs(P.x - n.x) < 1 ? 1 : -1;
      };
      drawMarker(g, pts[0], into(pts[0], src), kinds.child, color, th.bg);
      drawMarker(g, pts[pts.length - 1], into(pts[pts.length - 1], tgt), kinds.parent, color, th.bg);
      if (pr.provenance === "inferred") {
        var mid = pointAtHalf(pts);
        var chip = el("g", { class: "erd-chip" }, g);
        el("circle", { cx: mid.x, cy: mid.y, r: 7, fill: th.bg, stroke: color, "stroke-width": 1 }, chip);
        text(chip, mid.x, mid.y + 3.5, "?", {
          fill: color, "font-size": 10, "font-weight": 700, "text-anchor": "middle",
        });
      }
    });
    return g;
  }

  function drawLegend(st) {
    var box = document.getElementById(st.legendId);
    if (!box) return;
    var th = theme();
    function sample(kind) {
      var s = document.createElementNS(SVGNS, "svg");
      s.setAttribute("width", 44);
      s.setAttribute("height", 16);
      el("line", { x1: 0, y1: 8, x2: 30, y2: 8, stroke: th.text, "stroke-width": 1.4 }, s);
      el("rect", { x: 30, y: 0, width: 14, height: 16, fill: th.card, stroke: th.border }, s);
      drawMarker(s, { x: 30, y: 8 }, 1, kind, th.text, th.bg);
      return s.outerHTML;
    }
    function line(dash, color, chip) {
      return (
        '<svg width="44" height="16"><line x1="0" y1="8" x2="44" y2="8" stroke="' + color +
        '" stroke-width="1.4"' + (dash ? ' stroke-dasharray="6 4"' : "") + "/>" +
        (chip
          ? '<circle cx="22" cy="8" r="6" fill="' + th.bg + '" stroke="' + color +
            '"/><text x="22" y="11" font-size="9" font-weight="700" text-anchor="middle" fill="' + color + '">?</text>'
          : "") +
        "</svg>"
      );
    }
    var areas = {};
    (st.layout.children || []).forEach(function (n) {
      var p = n.properties || {};
      if (p.subjectArea) areas[p.subjectArea] = p.headerColor;
    });
    var item = function (icon, label) {
      return '<div class="erd-legend-item">' + icon + "<span>" + label + "</span></div>";
    };
    box.innerHTML =
      '<div class="erd-legend-group"><div class="erd-legend-head">Ends (read at the table they touch)</div>' +
      item(sample("one"), "exactly one") +
      item(sample("zeroOne"), "zero or one") +
      item(sample("zeroMany"), "zero or many") +
      item(sample("unknown"), "unknown (empty table)") +
      "</div>" +
      '<div class="erd-legend-group"><div class="erd-legend-head">Lines</div>' +
      item(line(false, th.text), "identifying (FK is part of the PK)") +
      item(line(true, th.text), "non-identifying") +
      item(line(false, th.muted, true), "inferred, not yet confirmed") +
      "</div>" +
      '<div class="erd-legend-group"><div class="erd-legend-head">Columns</div>' +
      item('<b style="color:' + th.pk + '">PK</b>', "primary key") +
      item('<b style="color:' + th.fk + '">FK1</b>', "foreign key (numbered)") +
      item('<b style="color:' + th.uk + '">UK</b>', "unique") +
      item("<b>∅</b>", "has missing values (nullable)") +
      item('<span class="erd-legend-junction"></span>', "junction table") +
      "</div>" +
      '<div class="erd-legend-group"><div class="erd-legend-head">Subject areas</div>' +
      Object.keys(areas).sort().map(function (a) {
        return item('<span class="erd-legend-swatch" style="background:' + esc(areas[a]) + '"></span>', esc(a));
      }).join("") +
      "</div>";
  }

  function draw(st) {
    var container = document.getElementById(st.id);
    if (!container || !st.layout) return;
    var keep = null;
    if (st.pz) {
      keep = { zoom: realZoom(st), pan: st.pz.getPan() };
      try { st.pz.destroy(); } catch (err) { /* already gone */ }
      st.pz = null;
    }
    var th = theme();
    var L = st.layout;
    var props = L.properties || {};
    var W = (L.width || 0) + 2 * PAD, H = (L.height || 0) + 2 * PAD;

    var svg = el("svg", {
      xmlns: SVGNS, class: "erd-svg", width: "100%", height: "100%",
      "font-family": FONT, "data-width": W, "data-height": H,
    });
    var vp = el("g", { class: "erd-viewport" }, svg);
    // Invisible backdrop so Fit keeps the margin (lines can run along the edge)
    el("rect", { class: "erd-backdrop", width: W, height: H, fill: "none" }, vp);
    var root = el("g", { transform: "translate(" + PAD + "," + PAD + ")" }, vp);
    var nodesG = el("g", { class: "erd-nodes" }, root);
    var edgesG = el("g", { class: "erd-edges" }, root);
    var nodes = {};
    (L.children || []).forEach(function (n) {
      nodes[n.id] = n;
      drawCard(nodesG, n, th, props);
    });
    (L.edges || []).forEach(function (e) {
      drawEdge(edgesG, e, nodes, th);
    });

    container.innerHTML = "";
    if (!(L.children || []).length) {
      container.innerHTML = '<div class="erd-empty">No tables match the current filters.</div>';
      drawLegend(st);
      return;
    }
    container.appendChild(svg);
    st.svg = svg;
    st.size = { width: W, height: H };
    wire(st, svg);
    markSelected(st);
    drawLegend(st);
    initPanZoom(st, keep);
  }

  function initPanZoom(st, keep) {
    var container = document.getElementById(st.id);
    if (!st.svg || !isVisible(container) || typeof svgPanZoom !== "function") {
      st.pendingFit = !keep;
      st.pendingKeep = keep;
      return;
    }
    // No built-in fit: zoom 1 is then real size, so zoom values mean the
    // same thing across redraws and the limits don't depend on diagram size
    st.pz = svgPanZoom(st.svg, {
      viewportSelector: ".erd-viewport",
      zoomScaleSensitivity: 0.25,
      minZoom: 0.02,
      maxZoom: 4,
      dblClickZoomEnabled: false,
      fit: false,
      center: false,
      controlIconsEnabled: false,
    });
    syncLimits(st);
    if (keep) {
      setRealZoom(st, keep.zoom);
      st.pz.pan(keep.pan);
    } else {
      fitView(st);
    }
    st.pendingFit = false;
    st.pendingKeep = null;
  }

  // Whole diagram in view; small diagrams are not blown up past MAX_FIT_ZOOM
  function fitView(st) {
    var s = st.pz.getSizes();
    var z = Math.min(s.width / st.size.width, s.height / st.size.height, MAX_FIT_ZOOM);
    setRealZoom(st, Math.max(z, 0.02));
    st.pz.center();
  }

  // svg-pan-zoom's zoom() is relative to a base that shifts on resize();
  // these work in real scale (1 = actual size)
  function realZoom(st) {
    return st.pz.getSizes().realZoom;
  }
  // Zoom limits in real scale, whatever base resize() left behind
  function syncLimits(st) {
    var base = st.pz.getSizes().realZoom / st.pz.getZoom();
    st.pz.setMinZoom(0.02 / base);
    st.pz.setMaxZoom(4 / base);
  }
  function setRealZoom(st, z) {
    st.pz.zoom((z * st.pz.getZoom()) / st.pz.getSizes().realZoom);
  }

  function markSelected(st) {
    if (!st.svg) return;
    st.svg.querySelectorAll(".erd-edge").forEach(function (g) {
      g.classList.toggle("erd-selected", g.getAttribute("data-key") === st.selectedRel);
    });
    st.svg.querySelectorAll(".erd-node").forEach(function (g) {
      g.classList.toggle("erd-selected", g.getAttribute("data-table") === st.selectedTable);
    });
  }

  function wire(st, svg) {
    var down = null;
    svg.addEventListener("mousedown", function (ev) {
      down = { x: ev.clientX, y: ev.clientY };
    });
    function isClick(ev) {
      return !down || Math.hypot(ev.clientX - down.x, ev.clientY - down.y) < 4;
    }
    function highlight(tables, keys) {
      svg.classList.add("erd-dim");
      svg.querySelectorAll(".erd-node").forEach(function (g) {
        g.classList.toggle("erd-hl", tables.indexOf(g.getAttribute("data-table")) >= 0);
      });
      svg.querySelectorAll(".erd-edge").forEach(function (g) {
        g.classList.toggle("erd-hl", keys.indexOf(g.getAttribute("data-key")) >= 0);
      });
    }
    function clear() {
      svg.classList.remove("erd-dim");
      svg.querySelectorAll(".erd-hl").forEach(function (g) {
        g.classList.remove("erd-hl");
      });
    }
    var edges = Array.prototype.slice.call(svg.querySelectorAll(".erd-edge"));
    svg.querySelectorAll(".erd-node").forEach(function (g) {
      var t = g.getAttribute("data-table");
      g.addEventListener("mouseenter", function () {
        var tables = [t], keys = [];
        edges.forEach(function (e) {
          var f = e.getAttribute("data-from"), to = e.getAttribute("data-to");
          if (f === t || to === t) {
            keys.push(e.getAttribute("data-key"));
            tables.push(f, to);
          }
        });
        highlight(tables, keys);
      });
      g.addEventListener("mouseleave", clear);
      g.addEventListener("click", function (ev) {
        if (!isClick(ev)) return;
        st.selectedTable = t;
        st.selectedRel = null;
        markSelected(st);
        if (window.Shiny && st.tableInput) {
          Shiny.setInputValue(st.tableInput, t, { priority: "event" });
        }
      });
    });
    edges.forEach(function (g) {
      var key = g.getAttribute("data-key");
      g.addEventListener("mouseenter", function () {
        highlight([g.getAttribute("data-from"), g.getAttribute("data-to")], [key]);
      });
      g.addEventListener("mouseleave", clear);
      g.addEventListener("click", function (ev) {
        if (!isClick(ev)) return;
        ev.stopPropagation();
        st.selectedRel = key;
        st.selectedTable = null;
        markSelected(st);
        if (window.Shiny && st.relInput) {
          Shiny.setInputValue(st.relInput, key, { priority: "event" });
        }
      });
    });
  }

  // ── message handler ────────────────────────────────────────
  // Layout runs in a Web Worker so large schemas don't freeze the page
  function workerUrl() {
    var tag = document.querySelector('script[src*="vendor/elkjs/elk-api.js"]');
    return tag ? tag.src.replace(/elk-api\.js.*$/, "elk-worker.min.js") : "tableexplorer/vendor/elkjs/elk-worker.min.js";
  }
  function makeElk() {
    return new ELK({ workerUrl: workerUrl() });
  }
  function stopWorker(st) {
    if (st.elk) {
      try { st.elk.terminateWorker(); } catch (err) { /* already stopped */ }
      st.elk = null;
    }
    st.busy = false;
  }

  window.erdDrawAnyway = function (id) {
    var st = states[id];
    if (!st || !st.pendingGraph) return;
    var msg = st.pendingGraph;
    st.pendingGraph = null;
    st.forceKey = signature(msg.graph);
    render(msg);
  };

  function render(msg) {
    var id = msg.container;
    var st = states[id] || (states[id] = { id: id, token: 0 });
    st.legendId = msg.legend;
    st.relInput = msg.relInput;
    st.tableInput = msg.tableInput;
    var graph = msg.graph;
    var sig = signature(graph);
    var token = ++st.token;

    if (st.layout && st.sig === sig) {
      // Same layout: carry the new styling data over and redraw in place
      var byId = {};
      graph.children.forEach(function (n) { byId[n.id] = n; });
      st.layout.children.forEach(function (n) {
        if (byId[n.id]) n.properties = byId[n.id].properties;
      });
      var eById = {};
      graph.edges.forEach(function (e) { eById[e.id] = e; });
      st.layout.edges.forEach(function (e) {
        if (eById[e.id]) e.properties = eById[e.id].properties;
      });
      st.layout.properties = graph.properties;
      draw(st);
      return Promise.resolve(st);
    }

    var container = document.getElementById(id);
    if (graph.edges.length > MAX_EDGES && st.forceKey !== sig) {
      // Hundreds of lines take long to lay out and can't be read anyway
      stopWorker(st);
      st.layout = null;
      st.sig = null;
      st.svg = null;
      if (st.pz) {
        try { st.pz.destroy(); } catch (err) { /* ignore */ }
        st.pz = null;
      }
      st.pendingGraph = msg;
      if (container) {
        container.innerHTML =
          '<div class="erd-empty"><p><b>' + graph.edges.length + " relationships</b> is too many to draw " +
          "legibly (limit " + MAX_EDGES + ").</p><p>Pick a focus table or a subject area above, " +
          "or raise the minimum confidence in the sidebar.</p>" +
          '<button class="btn-rel" onclick="erdDrawAnyway(\'' + id + '\')">Draw anyway (may be slow)</button></div>';
      }
      return Promise.resolve(st);
    }

    var props = graph.properties;
    var t0 = performance.now();
    if (container && !st.layout) container.innerHTML = '<div class="erd-empty">Laying out\u2026</div>';
    // A newer graph supersedes any layout still running; an idle worker is reused
    if (st.busy) stopWorker(st);
    var elk = st.elk || (st.elk = makeElk());
    st.busy = true;
    return elk
      .layout(JSON.parse(JSON.stringify(graph)))
      .then(function (out) {
        if (token !== st.token) return st; // a newer render superseded this one
        st.busy = false;
        out.properties = props;
        // Carry the drawing data over from the graph we sent
        var byId = {};
        graph.children.forEach(function (n) { byId[n.id] = n; });
        out.children.forEach(function (n) { n.properties = byId[n.id].properties; });
        var eById = {};
        graph.edges.forEach(function (e) { eById[e.id] = e; });
        out.edges.forEach(function (e) { e.properties = eById[e.id].properties; });
        st.layout = out;
        st.sig = sig;
        st.layoutMs = performance.now() - t0;
        if (st.pz) {
          // New layout: fit to view
          try { st.pz.destroy(); } catch (err) { /* ignore */ }
          st.pz = null;
        }
        draw(st);
        window.erdLast = { container: id, layout: out, ms: st.layoutMs };
        return st;
      })
      .catch(function (err) {
        if (token !== st.token) return st;
        st.busy = false;
        if (container) {
          container.innerHTML = '<div class="erd-empty">Could not lay out the diagram: ' + esc(err.message || err) + "</div>";
        }
        console.error("ERD layout failed", err);
      });
  }
  window.erdRender = render; // for tests

  // ── public: fit and download ───────────────────────────────
  window.erdFit = function (id) {
    var st = states[id];
    if (!st) return;
    if (!st.pz) return initPanZoom(st, null);
    st.pz.resize();
    syncLimits(st);
    fitView(st);
  };

  function exportSvg(st) {
    var W = st.size.width, H = st.size.height;
    var th = theme();
    var clone = st.svg.cloneNode(true);
    clone.classList.remove("erd-dim");
    clone.querySelectorAll(".erd-hl,.erd-selected").forEach(function (g) {
      g.classList.remove("erd-hl");
      g.classList.remove("erd-selected");
    });
    clone.querySelectorAll(".erd-hit").forEach(function (h) { h.remove(); });
    var vp = clone.querySelector(".erd-viewport");
    vp.removeAttribute("transform");
    vp.removeAttribute("style");
    clone.setAttribute("width", W);
    clone.setAttribute("height", H);
    clone.setAttribute("viewBox", "0 0 " + W + " " + H);
    clone.removeAttribute("style");
    clone.removeAttribute("class");
    var bg = document.createElementNS(SVGNS, "rect");
    bg.setAttribute("width", W);
    bg.setAttribute("height", H);
    bg.setAttribute("fill", th.bg);
    clone.insertBefore(bg, clone.firstChild);
    return '<?xml version="1.0" encoding="UTF-8"?>\n' + new XMLSerializer().serializeToString(clone);
  }
  window.erdExportSvg = function (id) {
    var st = states[id];
    return st && st.svg ? exportSvg(st) : null;
  };

  function save(blob, name) {
    var a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = name;
    document.body.appendChild(a);
    a.click();
    setTimeout(function () {
      URL.revokeObjectURL(a.href);
      a.remove();
    }, 1000);
  }

  window.erdDownload = function (id, format) {
    var st = states[id];
    if (!st || !st.svg) return;
    var src = exportSvg(st);
    if (format === "svg") {
      save(new Blob([src], { type: "image/svg+xml;charset=utf-8" }), "erd.svg");
      return;
    }
    var W = st.size.width, H = st.size.height;
    // Stay inside browser canvas limits on very large diagrams
    var scale = Math.min(2, 16000 / Math.max(W, H), Math.sqrt(1e8 / (W * H)));
    var img = new Image();
    img.onload = function () {
      var c = document.createElement("canvas");
      c.width = Math.round(W * scale);
      c.height = Math.round(H * scale);
      var ctx = c.getContext("2d");
      ctx.scale(scale, scale);
      ctx.drawImage(img, 0, 0, W, H);
      c.toBlob(function (b) {
        if (b) save(b, "erd.png");
      }, "image/png");
    };
    img.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(src);
  };

  // ── lifecycle ──────────────────────────────────────────────
  function refreshVisible() {
    Object.keys(states).forEach(function (id) {
      var st = states[id];
      var container = document.getElementById(id);
      if (st.svg && !st.pz && isVisible(container)) initPanZoom(st, st.pendingKeep);
      else if (st.pz && isVisible(container)) {
        // resize() resets the view; keep what the user was looking at
        var z = realZoom(st), pan = st.pz.getPan();
        st.pz.resize();
        syncLimits(st);
        setRealZoom(st, z);
        st.pz.pan(pan);
      }
    });
  }

  function register() {
    Shiny.addCustomMessageHandler("erd-render", render);
  }
  if (window.Shiny && Shiny.addCustomMessageHandler) register();
  else document.addEventListener("DOMContentLoaded", register);

  document.addEventListener("DOMContentLoaded", function () {
    // Tabs and conditional panels: set up pan/zoom once the diagram shows
    if (window.jQuery) {
      jQuery(document).on("shown.bs.tab shown", refreshVisible);
      jQuery(document).on("shiny:conditional", function () {
        setTimeout(refreshVisible, 0);
      });
    }
    window.addEventListener("resize", refreshVisible);
    // Theme toggle: redraw with the new colours, keeping pan/zoom
    new MutationObserver(function () {
      Object.keys(states).forEach(function (id) {
        if (states[id].layout) draw(states[id]);
      });
    }).observe(document.body, { attributes: true, attributeFilter: ["class"] });
  });
})();
