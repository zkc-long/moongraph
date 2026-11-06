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
/// An insert-only property graph with adjacency and secondary indexes.
pub struct Graph {
  nodes : Array[Node]
  edges : Array[Edge]
  out_edges : Array[Array[Int32]]
  in_edges : Array[Array[Int32]]
  label_index : Map[String, Array[Int32]]
  prop_index : Map[String, Map[String, Array[Int32]]]
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
  self.out_edges.push([])
  self.in_edges.push([])
  for label in labels {
    match self.label_index.get(label) {
      Some(ids) => ids.push(id)
      None => self.label_index[label] = [id]
    }
  }
  for key, value in props {
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
    result.push((self.edges[edge_id].dst, edge_id))
  }
  result
}

///|
/// Incoming neighbours together with the edges that reach this node.
pub fn Graph::in_neighbors(self : Graph, node : Int32) -> Array[(Int32, Int32)] {
  let result : Array[(Int32, Int32)] = []
  for edge_id in self.in_edges[node] {
    result.push((self.edges[edge_id].src, edge_id))
  }
  result
}

///|
/// Node ids carrying `label`, in insertion order.
/// Falls back to a scan for labels that were never indexed.
pub fn Graph::nodes_with_label(self : Graph, label : String) -> Array[Int32] {
  match self.label_index.get(label) {
    Some(ids) => ids.copy()
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
  let result = Array::from_iter(self.label_index.keys())
  result.sort()
  result
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
