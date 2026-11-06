// Mutation: the write side of the graph.
//
// Deletion is logical: nodes and edges are tombstoned rather than removed from
// the arrays, so ids stay stable and in-flight query bindings cannot dangle.
// Scans and index lookups filter dead entries, and re-adding a property appends
// to the index (the old entry stays but is skipped because the value differs).

///|
pub fn Graph::is_alive_node(self : Graph, id : Int32) -> Bool {
  if id < 0 || id >= self.alive_nodes.length() {
    return false
  }
  self.alive_nodes[id]
}

///|
pub fn Graph::is_alive_edge(self : Graph, id : Int32) -> Bool {
  if id < 0 || id >= self.alive_edges.length() {
    return false
  }
  self.alive_edges[id]
}

///|
pub fn Graph::alive_node_count(self : Graph) -> Int32 {
  let mut n = 0
  for alive in self.alive_nodes {
    if alive {
      n = n + 1
    }
  }
  n
}

///|
pub fn Graph::alive_edge_count(self : Graph) -> Int32 {
  let mut n = 0
  for alive in self.alive_edges {
    if alive {
      n = n + 1
    }
  }
  n
}

///|
/// Tombstone a node together with every relationship incident to it.
pub fn Graph::delete_node(self : Graph, id : Int32) -> Unit {
  if !self.is_alive_node(id) {
    return
  }
  for edge_id in self.out_edges[id] {
    self.delete_edge(edge_id)
  }
  for edge_id in self.in_edges[id] {
    self.delete_edge(edge_id)
  }
  self.alive_nodes[id] = false
}

///|
pub fn Graph::delete_edge(self : Graph, id : Int32) -> Unit {
  if id < 0 || id >= self.alive_edges.length() {
    return
  }
  self.alive_edges[id] = false
}

///|
/// Add a node with a caller supplied id slot. Used by importers that need
/// stable ids across a merge.
pub fn Graph::ensure_node(
  self : Graph,
  labels : Array[String],
  props : Map[String, Value],
) -> Int32 {
  self.add_node(labels, props)
}

///|
pub fn Graph::set_node_prop(
  self : Graph,
  id : Int32,
  key : String,
  value : Value,
) -> Unit {
  if !self.is_alive_node(id) {
    return
  }
  let node = self.nodes[id]
  node.props[key] = value
  self.index_property(id, key, value)
}

///|
pub fn Graph::remove_node_prop(self : Graph, id : Int32, key : String) -> Unit {
  if !self.is_alive_node(id) {
    return
  }
  ignore(self.nodes[id].props.remove(key))
}

///|
pub fn Graph::set_edge_prop(
  self : Graph,
  id : Int32,
  key : String,
  value : Value,
) -> Unit {
  if !self.is_alive_edge(id) {
    return
  }
  self.edges[id].props[key] = value
}

///|
pub fn Graph::add_node_label(self : Graph, id : Int32, label : String) -> Unit {
  if !self.is_alive_node(id) {
    return
  }
  let node = self.nodes[id]
  if node.has_label(label) {
    return
  }
  node.labels.push(label)
  match self.label_index.get(label) {
    Some(ids) => ids.push(id)
    None => self.label_index[label] = [id]
  }
}

///|
/// Record a node id under a property value in the secondary index.
fn Graph::index_property(
  self : Graph,
  id : Int32,
  key : String,
  value : Value,
) -> Unit {
  let encoded = encode_index_key(value)
  if encoded == "" {
    return
  }
  let by_key = match self.prop_index.get(key) {
    Some(m) => m
    None => {
      let m : Map[String, Array[Int32]] = Map([])
      self.prop_index[key] = m
      m
    }
  }
  match by_key.get(encoded) {
    Some(ids) =>
      // Avoid duplicate ids when a property is rewritten to the same value.
      if !ids.contains(id) {
        ids.push(id)
      }
    None => by_key[encoded] = [id]
  }
}

///|
/// Aggregate counts used by the TCK side-effect assertions and by `info`.
pub struct GraphStats {
  nodes : Int
  relationships : Int
  properties : Int
  labels : Int
}

///|
pub fn Graph::stats(self : Graph) -> GraphStats {
  let mut nodes = 0
  let mut properties = 0
  let mut labels = 0
  let mut relational = 0
  let mut i = 0
  while i < self.node_count() {
    if self.is_alive_node(i) {
      let node = self.node(i)
      nodes = nodes + 1
      properties = properties + node.props.length()
      labels = labels + node.labels.length()
    }
    i = i + 1
  }
  let mut e = 0
  while e < self.edge_count() {
    if self.is_alive_edge(e) {
      let edge = self.edge(e)
      relational = relational + 1
      properties = properties + edge.props.length()
    }
    e = e + 1
  }
  { nodes, relationships: relational, properties, labels }
}