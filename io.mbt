// Graph interchange: JSON Lines import/export and registry ingestion.
//
// The on-disk format is one JSON object per line:
//   {"kind":"node","id":"ada","labels":["Person"],"props":{"name":"Ada"}}
//   {"kind":"edge","from":"ada","to":"bob","type":"KNOWS","props":{}}
// Ids are strings on disk so that datasets stay readable and stable; they are
// mapped to dense integers on import.

///|
pub suberror LoadError {
  BadLine(Int, String)
  MissingNode(String)
}

///|
/// Drop a UTF-8 byte order mark, which Windows editors add by default.
fn strip_bom(text : String) -> String {
  if text.has_prefix("\u{FEFF}") {
    match text.get_view(start=1) {
      Some(view) => view.to_owned()
      None => text
    }
  } else {
    text
  }
}

///|
/// Parse a graph from JSON Lines text.
pub fn load_graph(text : String) -> Graph raise LoadError {
  let text = strip_bom(text)
  let graph = Graph::new()
  let ids : Map[String, Int] = Map([])
  let pending_edges : Array[(String, String, String, Map[String, Value])] = []
  let lines = text.split("\n")
  let mut line_no = 0
  for raw in lines {
    line_no = line_no + 1
    let line = raw.trim()
    if line == "" {
      continue
    }
    let json = Json::parse(line) catch {
      _ => raise LoadError::BadLine(line_no, "invalid JSON")
    }
    match json {
      JObj(fields) => {
        let kind = match fields.get("kind") {
          Some(JStr(k)) => k
          _ =>
            match fields.get("type") {
              Some(JStr(_)) => "edge"
              _ => "node"
            }
        }
        if kind == "node" {
          let id = field_string(fields, "id")
          let labels = field_strings(fields, "labels")
          let props = field_props(fields, "props")
          let dense = graph.add_node(labels, props)
          ids[id] = dense
        } else if kind == "edge" {
          let from = match fields.get("from") {
            Some(JStr(v)) => v
            _ => ""
          }
          let to = match fields.get("to") {
            Some(JStr(v)) => v
            _ => ""
          }
          let etype = match fields.get("type") {
            Some(JStr(v)) => v
            _ => ""
          }
          pending_edges.push((from, to, etype, field_props(fields, "props")))
        } else {
          raise LoadError::BadLine(line_no, "unknown record kind")
        }
      }
      _ => raise LoadError::BadLine(line_no, "record must be an object")
    }
  }
  for (from, to, etype, props) in pending_edges {
    let src = match ids.get(from) {
      Some(id) => id
      None => raise LoadError::MissingNode(from)
    }
    let dst = match ids.get(to) {
      Some(id) => id
      None => raise LoadError::MissingNode(to)
    }
    ignore(graph.add_edge(etype, src, dst, props)) catch {
      _ => raise LoadError::BadLine(0, "edge endpoints missing")
    }
  }
  graph
}

///|
fn field_string(fields : Map[String, Json], key : String) -> String {
  match fields.get(key) {
    Some(JStr(v)) => v
    Some(JInt(v)) => "\{v}"
    _ => ""
  }
}

///|
fn field_strings(fields : Map[String, Json], key : String) -> Array[String] {
  match fields.get(key) {
    Some(JList(items)) => {
      let out : Array[String] = []
      for item in items {
        match item {
          JStr(s) => out.push(s)
          _ => ()
        }
      }
      out
    }
    Some(JStr(s)) => [s]
    _ => []
  }
}

///|
fn field_props(fields : Map[String, Json], key : String) -> Map[String, Value] {
  let out : Map[String, Value] = Map([])
  match fields.get(key) {
    Some(JObj(obj)) =>
      for k, v in obj {
        out[k] = json_to_value(v)
      }
    _ => ()
  }
  out
}

///|
/// Serialise a graph back to JSON Lines, using positional ids.
pub fn dump_graph(graph : Graph) -> String {
  let buf = StringBuilder()
  let mut i = 0
  while i < graph.node_count() {
    let node = graph.node(i)
    buf.write_string("{\"kind\":\"node\",\"id\":\"n\{i}\",\"labels\":")
    buf.write_string(strings_to_json(node.labels))
    buf.write_string(",\"props\":")
    buf.write_string(props_to_json(node.props))
    buf.write_string("}\n")
    i = i + 1
  }
  let mut e = 0
  while e < graph.edge_count() {
    let edge = graph.edge(e)
    buf.write_string("{\"kind\":\"edge\",\"from\":\"n\{edge.src}\",\"to\":\"n\{edge.dst}\",\"type\":\"")
    buf.write_string(escape_json_string(edge.etype))
    buf.write_string("\",\"props\":")
    buf.write_string(props_to_json(edge.props))
    buf.write_string("}\n")
    e = e + 1
  }
  buf.to_string()
}

///|
fn strings_to_json(items : Array[String]) -> String {
  let buf = StringBuilder()
  buf.write_string("[")
  let mut first = true
  for item in items {
    if !first {
      buf.write_string(",")
    }
    first = false
    buf.write_string("\"" + escape_json_string(item) + "\"")
  }
  buf.write_string("]")
  buf.to_string()
}

///|
fn props_to_json(props : Map[String, Value]) -> String {
  let buf = StringBuilder()
  buf.write_string("{")
  let mut first = true
  for key, value in props {
    if !first {
      buf.write_string(",")
    }
    first = false
    buf.write_string("\"" + escape_json_string(key) + "\":")
    buf.write_string(value_to_json(value).to_string())
  }
  buf.write_string("}")
  buf.to_string()
}

///|
/// Convert mooncakes registry records (`modules/<owner>/<name>` responses) into
/// a dependency graph: one `Package` node per module and one `DEPENDS_ON` edge
/// from each dependent to the module it depends on.
pub fn load_registry_records(text : String) -> Graph raise LoadError {
  let graph = Graph::new()
  let ids : Map[String, Int] = Map([])
  let pending : Array[(String, String)] = []
  let lines = text.split("\n")
  let mut line_no = 0
  for raw in lines {
    line_no = line_no + 1
    let line = raw.trim()
    if line == "" {
      continue
    }
    let json = Json::parse(line) catch {
      _ => raise LoadError::BadLine(line_no, "invalid JSON")
    }
    match json {
      JObj(fields) => {
        let name = match fields.get("module") {
          Some(JStr(v)) => v
          _ => raise LoadError::BadLine(line_no, "record without module name")
        }
        let version = match fields.get("version") {
          Some(JStr(v)) => v
          _ => ""
        }
        let props : Map[String, Value] = Map([])
        props["name"] = VStr(name)
        props["version"] = VStr(version)
        let id = graph.add_node(["Package"], props)
        ids[name] = id
        match fields.get("dependents") {
          Some(JList(items)) =>
            for item in items {
              match item {
                JObj(dep) =>
                  match dep.get("name") {
                    Some(JStr(dep_name)) => pending.push((dep_name, name))
                    _ => ()
                  }
                _ => ()
              }
            }
          _ => ()
        }
      }
      _ => raise LoadError::BadLine(line_no, "record must be an object")
    }
  }
  // Materialise missing dependents as nodes so the graph stays complete.
  for (dependent, target) in pending {
    let src = match ids.get(dependent) {
      Some(id) => id
      None => {
        let props : Map[String, Value] = Map([])
        props["name"] = VStr(dependent)
        props["version"] = VStr("")
        let id = graph.add_node(["Package"], props)
        ids[dependent] = id
        id
      }
    }
    let dst = ids[target]
    ignore(graph.add_edge("DEPENDS_ON", src, dst, Map([]))) catch { _ => () }
  }
  graph
}
