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
  self.bump_effect("-nodes")
  for label in self.nodes[id].labels {
    self.note_label_removed(label)
  }
  for key, _value in self.nodes[id].props {
    self.note_effect("-properties", "P:" + id.to_string() + ":" + key)
  }
}

///|
pub fn Graph::delete_edge(self : Graph, id : Int32) -> Unit {
  if id < 0 || id >= self.alive_edges.length() {
    return
  }
  self.alive_edges[id] = false
  self.bump_effect("-relationships")
  for key, _value in self.edges[id].props {
    self.note_effect("-properties", "R:" + id.to_string() + ":" + key)
  }
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
  if value is VNull {
    if node.props.get(key) is Some(_) {
      self.note_effect("-properties", "P:" + id.to_string() + ":" + key)
    }
    ignore(node.props.remove(key))
    return
  }
  if node.props.get(key) is Some(existing) && !(existing is VNull) {
    self.note_effect("-properties", "P:" + id.to_string() + ":" + key)
  }
  self.note_effect("+properties", "P:" + id.to_string() + ":" + key)
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
  nodes : Int32
  relationships : Int32
  properties : Int32
  labels : Int32
}

///|
pub fn Graph::stats(self : Graph) -> GraphStats {
  let mut nodes = 0
  let mut properties = 0
  let mut relational = 0
  let mut i = 0
  while i < self.node_count() {
    if self.is_alive_node(i) {
      let node = self.node(i)
      nodes = nodes + 1
      properties = properties + node.props.length()
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
  // TCK counts distinct label *names* added, not label assignments.
  let labels = self.labels().length()
  { nodes, relationships: relational, properties, labels, }
}

///|
/// Reset the write counters so the next query reports its own side effects.
pub fn Graph::reset_side_effects(self : Graph) -> Unit {
  self.side_effects = Map([])
  self.side_effect_keys = Map([])
  self.baseline_labels = Map([])
  for label, ids in self.label_index {
    for id in ids {
      if self.alive_nodes[id] {
        self.baseline_labels[label] = true
      }
    }
  }
}

///|
/// The TCK counts +labels as label *names* that the graph did not have
/// before the query, not as label assignments to nodes.
pub fn Graph::note_label_added(self : Graph, label : String) -> Unit {
  if self.baseline_labels.get(label).unwrap_or(false) {
    return
  }
  self.note_effect("+labels", label)
}

///|
pub fn Graph::note_label_removed(self : Graph, label : String) -> Unit {
  for id, alive in self.alive_nodes {
    if alive && self.nodes[id].labels.contains(label) {
      return
    }
  }
  self.note_effect("-labels", label)
}

///|
/// Side-effect counters keyed like the TCK tables: `+nodes`, `-properties`, ...
pub fn Graph::effect_count(self : Graph, name : String) -> Int32 {
  match self.side_effects.get(name) {
    Some(n) => n
    None => 0
  }
}

///|
pub fn Graph::bump_effect(self : Graph, name : String) -> Unit {
  let current = self.effect_count(name)
  self.side_effects[name] = current + 1
}

///|
/// Count an effect at most once per dedupe key, which is how the TCK treats
/// label names and (entity, property) pairs.
pub fn Graph::note_effect(self : Graph, name : String, dedupe : String) -> Unit {
  let dedupe_key = name + "|" + dedupe
  if self.side_effect_keys.get(dedupe_key).unwrap_or(false) {
    return
  }
  self.side_effect_keys[dedupe_key] = true
  self.bump_effect(name)
}
