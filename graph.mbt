// Property graph storage: dense node ids, adjacency lists and secondary indexes.
//
// Nodes are stored in a dense array so that a node id *is* its position. This
// keeps traversal cache friendly and removes the need for a hash lookup on the
// hot path of an expansion. Edges live in a separate array; adjacency lists
// store edge ids rather than neighbour ids so that an expansion can filter on
// the edge type without a second lookup.

///|
pub struct Node {
  id : Int32
  labels : Array[String]
  props : Map[String, Value]
}

///|
pub struct Edge {
  id : Int32
  etype : String
  src : Int32
  dst : Int32
  props : Map[String, Value]
}

///|
pub fn Node::id(self : Node) -> Int32 {
  self.id
}

///|
pub fn Node::has_label(self : Node, label : String) -> Bool {
  for l in self.labels {
    if l == label {
      return true
    }
  }
  false
}

///|
pub fn Node::prop(self : Node, key : String) -> Value {
  match self.props.get(key) {
    Some(v) => v
    None => VNull
  }
}

///|
pub fn Edge::prop(self : Edge, key : String) -> Value {
  match self.props.get(key) {
    Some(v) => v
    None => VNull
  }
}

///|
pub suberror GraphError {
  EdgeNodeMissing(Int32)
}

///|
/// A property graph with adjacency lists and secondary indexes.
/// Nodes and edges are tombstoned on delete so ids stay stable.
pub struct Graph {
  nodes : Array[Node]
  edges : Array[Edge]
  out_edges : Array[Array[Int32]]
  in_edges : Array[Array[Int32]]
  label_index : Map[String, Array[Int32]]
  prop_index : Map[String, Map[String, Array[Int32]]]
  alive_nodes : Array[Bool]
  alive_edges : Array[Bool]
  mut side_effects : Map[String, Int32]
  mut side_effect_keys : Map[String, Bool]
}

///|
pub fn Graph::new() -> Graph {
  {
    nodes: [],
    edges: [],
    out_edges: [],
    in_edges: [],
    label_index: Map([]),
    prop_index: Map([]),
    alive_nodes: [],
    alive_edges: [],
    side_effects: Map([]),
    side_effect_keys: Map([]),
  }
}

///|
pub fn Graph::node_count(self : Graph) -> Int32 {
  self.nodes.length()
}

///|
pub fn Graph::edge_count(self : Graph) -> Int32 {
  self.edges.length()
}

///|
pub fn Graph::node(self : Graph, id : Int32) -> Node {
  self.nodes[id]
}

///|
pub fn Graph::edge(self : Graph, id : Int32) -> Edge {
  self.edges[id]
}

///|
/// Add a node and return its dense id.
pub fn Graph::add_node(
  self : Graph,
  labels : Array[String],
  props : Map[String, Value],
) -> Int32 {
  let id = self.nodes.length()
  self.nodes.push({ id, labels, props, })
  self.alive_nodes.push(true)
  self.bump_effect("+nodes")
  self.out_edges.push([])
  self.in_edges.push([])
  for label in labels {
    self.note_effect("+labels", "L:" + label)
    match self.label_index.get(label) {
      Some(ids) => ids.push(id)
      None => self.label_index[label] = [id]
    }
  }
  for key, value in props {
    self.note_effect("+properties", "P:" + id.to_string() + ":" + key)
    let encoded = encode_index_key(value)
    if encoded != "" {
      let by_key = match self.prop_index.get(key) {
        Some(m) => m
        None => {
          let m : Map[String, Array[Int32]] = Map([])
          self.prop_index[key] = m
          m
        }
      }
      match by_key.get(encoded) {
        Some(ids) => ids.push(id)
        None => by_key[encoded] = [id]
      }
    }
  }
  id
}

///|
/// Add a directed edge; both endpoints must already exist.
pub fn Graph::add_edge(
  self : Graph,
  etype : String,
  src : Int32,
  dst : Int32,
  props : Map[String, Value],
) -> Int32 raise GraphError {
  let n = self.nodes.length()
  if src < 0 || src >= n {
    raise GraphError::EdgeNodeMissing(src)
  }
  if dst < 0 || dst >= n {
    raise GraphError::EdgeNodeMissing(dst)
  }
  let id = self.edges.length()
  self.edges.push({ id, etype, src, dst, props, })
  self.alive_edges.push(true)
  self.bump_effect("+relationships")
  for key, _value in props {
    self.note_effect("+properties", "R:" + id.to_string() + ":" + key)
  }
  self.out_edges[src].push(id)
  self.in_edges[dst].push(id)
  id
}

///|
pub fn Graph::out_edge_ids(self : Graph, node : Int32) -> Array[Int32] {
  self.out_edges[node]
}

///|
pub fn Graph::in_edge_ids(self : Graph, node : Int32) -> Array[Int32] {
  self.in_edges[node]
}

///|
/// Outgoing neighbours together with the edges that reach them.
pub fn Graph::out_neighbors(
  self : Graph,
  node : Int32,
) -> Array[(Int32, Int32)] {
  let result : Array[(Int32, Int32)] = []
  for edge_id in self.out_edges[node] {
    if self.is_alive_edge(edge_id) {
      result.push((self.edges[edge_id].dst, edge_id))
    }
  }
  result
}

///|
/// Incoming neighbours together with the edges that reach this node.
pub fn Graph::in_neighbors(self : Graph, node : Int32) -> Array[(Int32, Int32)] {
  let result : Array[(Int32, Int32)] = []
  for edge_id in self.in_edges[node] {
    if self.is_alive_edge(edge_id) {
      result.push((self.edges[edge_id].src, edge_id))
    }
  }
  result
}

///|
/// Node ids carrying `label`, in insertion order.
/// Falls back to a scan for labels that were never indexed.
pub fn Graph::nodes_with_label(self : Graph, label : String) -> Array[Int32] {
  match self.label_index.get(label) {
    Some(ids) => {
      let live : Array[Int32] = []
      for id in ids {
        if self.alive_nodes[id] {
          live.push(id)
        }
      }
      live
    }
    None => []
  }
}

///|
/// Candidate node ids for an equality predicate on a property.
/// Returns `None` when no index can answer the lookup.
pub fn Graph::lookup_property(
  self : Graph,
  key : String,
  value : Value,
) -> Array[Int32]? {
  let encoded = encode_index_key(value)
  if encoded == "" {
    return None
  }
  match self.prop_index.get(key) {
    None => None
    Some(by_key) =>
      match by_key.get(encoded) {
        None => Some([])
        Some(ids) => Some(ids.copy())
      }
  }
}

///|
/// All distinct labels known to the graph, sorted for deterministic output.
pub fn Graph::labels(self : Graph) -> Array[String] {
  // Only labels on live nodes count: the index keeps tombstones.
  let out : Array[String] = []
  for label, ids in self.label_index {
    let mut alive = false
    for id in ids {
      if self.alive_nodes[id] {
        alive = true
      }
    }
    if alive {
      out.push(label)
    }
  }
  out.sort()
  out
}

///|
/// All distinct edge types known to the graph, sorted for deterministic output.
pub fn Graph::edge_types(self : Graph) -> Array[String] {
  let seen : Map[String, Bool] = Map([])
  for edge in self.edges {
    seen[edge.etype] = true
  }
  let result = Array::from_iter(seen.keys())
  result.sort()
  result
}

///|
/// Index keys are restricted to scalar values; `null` and lists are not indexed.
fn encode_index_key(value : Value) -> String {
  match value {
    VStr(s) => "s:" + s
    VInt(i) => "i:\{i}"
    VBool(b) => "b:\{b}"
    VDouble(d) => "d:\{d}"
    _ => ""
  }
}

///|
/// Canonical Cypher text for a node: `(:Label {key: value})` with sorted labels
/// and sorted property keys, so two structurally equal nodes render identically.
pub fn node_text(labels : Array[String], props : Map[String, Value]) -> String {
  let sorted_labels = labels.copy()
  sorted_labels.sort()
  let buf = StringBuilder()
  buf.write_string("(:")
  let mut first = true
  for label in sorted_labels {
    if !first {
      buf.write_string(":")
    }
    first = false
    buf.write_string(label)
  }
  if props.length() > 0 {
    buf.write_string(" {")
    let keys = Array::from_iter(props.keys())
    keys.sort()
    let mut first_prop = true
    for key in keys {
      if !first_prop {
        buf.write_string(", ")
      }
      first_prop = false
      buf.write_string(key)
      buf.write_string(": ")
      buf.write_string(props[key].to_cypher())
    }
    buf.write_string("}")
  }
  buf.write_string(")")
  buf.to_string()
}

///|
pub fn Graph::node_text(self : Graph, id : Int32) -> String {
  node_text(self.node(id).labels, self.node(id).props)
}

///|
/// Canonical Cypher text for a relationship: `[:TYPE {key: value}]`.
pub fn rel_text(etype : String, props : Map[String, Value]) -> String {
  let buf = StringBuilder()
  buf.write_string("[:")
  buf.write_string(etype)
  if props.length() > 0 {
    buf.write_string(" {")
    let keys = Array::from_iter(props.keys())
    keys.sort()
    let mut first = true
    for key in keys {
      if !first {
        buf.write_string(", ")
      }
      first = false
      buf.write_string(key)
      buf.write_string(": ")
      buf.write_string(props[key].to_cypher())
    }
    buf.write_string("}")
  }
  buf.write_string("]")
  buf.to_string()
}

///|
pub fn Graph::rel_text(self : Graph, id : Int32) -> String {
  rel_text(self.edge(id).etype, self.edge(id).props)
}
