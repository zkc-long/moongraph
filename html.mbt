// Self-contained HTML export with a force-directed graph view.
//
// The page embeds the graph as JSON and a small vanilla-JS layout so it can be
// opened from disk with no server, no build step and no external assets.

///|
/// Render the graph as a standalone HTML document.
pub fn to_html(graph : Graph, title : String) -> String {
  let buf = StringBuilder()
  buf.write_string(
    "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n",
  )
  buf.write_string("<title>")
  buf.write_string(escape_json_string(title))
  buf.write_string("</title>\n<style>\n")
  buf.write_string(
    "body{font-family:ui-sans-serif,system-ui,sans-serif;margin:0;background:#0f1115;color:#e6e6e6}\n",
  )
  buf.write_string(
    "header{padding:16px 20px;border-bottom:1px solid #262b36}\n",
  )
  buf.write_string("h1{font-size:16px;margin:0 0 4px 0;font-weight:600}\n")
  buf.write_string("#meta{font-size:12px;color:#8b93a7}\n")
  buf.write_string("svg{display:block;width:100vw;height:calc(100vh - 70px)}\n")
  buf.write_string("line{stroke:#3a4152;stroke-width:1}\n")
  buf.write_string("circle{fill:#4c8dff;stroke:#0f1115;stroke-width:1.5}\n")
  buf.write_string(
    "text{fill:#c9d1e3;font-size:9px;font-family:ui-monospace,monospace;paint-order:stroke;stroke:#0f1115;stroke-width:2px}\n",
  )
  buf.write_string("</style>\n</head>\n<body>\n<header>\n<h1>")
  buf.write_string(escape_json_string(title))
  buf.write_string(
    "</h1>\n<div id=\"meta\"></div>\n</header>\n<svg id=\"g\"></svg>\n<script>\n",
  )
  buf.write_string("const DATA = ")
  buf.write_string(graph_json(graph))
  buf.write_string(";\n")
  buf.write_string(layout_script())
  buf.write_string("</script>\n</body>\n</html>\n")
  buf.to_string()
}

///|
fn graph_json(graph : Graph) -> String {
  let buf = StringBuilder()
  buf.write_string("{\"nodes\":[")
  let mut first = true
  let mut i = 0
  while i < graph.node_count() {
    if graph.is_alive_node(i) {
      if !first {
        buf.write_string(",")
      }
      first = false
      let node = graph.node(i)
      let label = match node.props.get("name") {
        Some(VStr(name)) => name
        _ => "n\{i}"
      }
      buf.write_string("{\"id\":")
      buf.write_string(i.to_string())
      buf.write_string(",\"label\":\"")
      buf.write_string(escape_json_string(label))
      buf.write_string("\"}")
    }
    i = i + 1
  }
  buf.write_string("],\"edges\":[")
  first = true
  let mut e = 0
  while e < graph.edge_count() {
    if graph.is_alive_edge(e) {
      if !first {
        buf.write_string(",")
      }
      first = false
      let edge = graph.edge(e)
      buf.write_string("{\"source\":")
      buf.write_string(edge.src.to_string())
      buf.write_string(",\"target\":")
      buf.write_string(edge.dst.to_string())
      buf.write_string(",\"type\":\"")
      buf.write_string(escape_json_string(edge.etype))
      buf.write_string("\"}")
    }
    e = e + 1
  }
  buf.write_string("]}")
  buf.to_string()
}

///|
/// A small force-directed layout; no dependencies, deterministic seeding.
fn layout_script() -> String {
  // Note: kept as a single literal so the emitted file stays readable.
  "const W = window.innerWidth, H = window.innerHeight - 70;\n" +
  "const svg = document.getElementById('g');\n" +
  "document.getElementById('meta').textContent =\n" +
  "  DATA.nodes.length + ' nodes · ' + DATA.edges.length + ' relationships';\n" +
  "const byId = new Map(DATA.nodes.map((n, i) => [n.id, i]));\n" +
  "DATA.nodes.forEach((n, i) => {\n" +
  "  const a = (i / Math.max(1, DATA.nodes.length)) * Math.PI * 2;\n" +
  "  n.x = W / 2 + Math.cos(a) * Math.min(W, H) * 0.35 + (i % 7) * 3;\n" +
  "  n.y = H / 2 + Math.sin(a) * Math.min(W, H) * 0.35 + (i % 5) * 3;\n" +
  "  n.vx = 0; n.vy = 0;\n" +
  "});\n" +
  "const links = DATA.edges\n" +
  "  .filter(e => byId.has(e.source) && byId.has(e.target))\n" +
  "  .map(e => ({a: byId.get(e.source), b: byId.get(e.target), type: e.type}));\n" +
  "const N = DATA.nodes.length;\n" +
  "for (let tick = 0; tick < 260; tick++) {\n" +
  "  const k = tick < 200 ? 0.02 : 0.004;\n" +
  "  for (let i = 0; i < N; i++) {\n" +
  "    for (let j = i + 1; j < N; j++) {\n" +
  "      const a = DATA.nodes[i], b = DATA.nodes[j];\n" +
  "      let dx = a.x - b.x, dy = a.y - b.y;\n" +
  "      let d2 = dx * dx + dy * dy + 0.01;\n" +
  "      if (d2 > 90000) continue;\n" +
  "      const f = 2200 / d2;\n" +
  "      const d = Math.sqrt(d2);\n" +
  "      a.vx += (dx / d) * f; a.vy += (dy / d) * f;\n" +
  "      b.vx -= (dx / d) * f; b.vy -= (dy / d) * f;\n" +
  "    }\n" +
  "  }\n" +
  "  for (const l of links) {\n" +
  "    const a = DATA.nodes[l.a], b = DATA.nodes[l.b];\n" +
  "    const dx = b.x - a.x, dy = b.y - a.y;\n" +
  "    const d = Math.sqrt(dx * dx + dy * dy) + 0.01;\n" +
  "    const f = (d - 90) * 0.012;\n" +
  "    a.vx += (dx / d) * f; a.vy += (dy / d) * f;\n" +
  "    b.vx -= (dx / d) * f; b.vy -= (dy / d) * f;\n" +
  "  }\n" +
  "  for (const n of DATA.nodes) {\n" +
  "    n.vx += (W / 2 - n.x) * 0.002; n.vy += (H / 2 - n.y) * 0.002;\n" +
  "    n.x += n.vx * k; n.y += n.vy * k;\n" +
  "    n.vx *= 0.6; n.vy *= 0.6;\n" +
  "    n.x = Math.max(20, Math.min(W - 20, n.x));\n" +
  "    n.y = Math.max(20, Math.min(H - 20, n.y));\n" +
  "  }\n" +
  "}\n" +
  "const NS = 'http://www.w3.org/2000/svg';\n" +
  "for (const l of links) {\n" +
  "  const a = DATA.nodes[l.a], b = DATA.nodes[l.b];\n" +
  "  const ln = document.createElementNS(NS, 'line');\n" +
  "  ln.setAttribute('x1', a.x); ln.setAttribute('y1', a.y);\n" +
  "  ln.setAttribute('x2', b.x); ln.setAttribute('y2', b.y);\n" +
  "  svg.appendChild(ln);\n" +
  "}\n" +
  "for (const n of DATA.nodes) {\n" +
  "  const c = document.createElementNS(NS, 'circle');\n" +
  "  c.setAttribute('cx', n.x); c.setAttribute('cy', n.y); c.setAttribute('r', 4);\n" +
  "  svg.appendChild(c);\n" +
  "  const t = document.createElementNS(NS, 'text');\n" +
  "  t.setAttribute('x', n.x + 7); t.setAttribute('y', n.y + 3);\n" +
  "  t.textContent = n.label;\n" +
  "  svg.appendChild(t);\n" +
  "}\n"
}
