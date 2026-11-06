// The TCK standard fixture graph, used by `Given any graph`.
//
// Vendored from openCypher `tck/graphs/binary-tree-1/binary-tree-1.cypher`
// (Apache-2.0). The definition is a tree of depth three plus a ring of
// `:FRIEND` edges between the second level, which is what the TCK relies on
// when a scenario says "any graph".

///|
struct FixtureNode {
  name : String
  label : String
}

///|
struct FixtureEdge {
  from : String
  to : String
  rtype : String
}

///|
fn fixture_nodes() -> Array[FixtureNode] {
  [
    { name: "a", label: "A", },
    { name: "b1", label: "X", },
    { name: "b2", label: "X", },
    { name: "b3", label: "X", },
    { name: "b4", label: "X", },
    { name: "c11", label: "X", },
    { name: "c12", label: "X", },
    { name: "c21", label: "X", },
    { name: "c22", label: "X", },
    { name: "c31", label: "X", },
    { name: "c32", label: "X", },
    { name: "c41", label: "X", },
    { name: "c42", label: "X", },
  ]
}

///|
fn fixture_edges() -> Array[FixtureEdge] {
  [
    { from: "a", to: "b1", rtype: "KNOWS", },
    { from: "a", to: "b2", rtype: "KNOWS", },
    { from: "a", to: "b3", rtype: "FOLLOWS", },
    { from: "a", to: "b4", rtype: "FOLLOWS", },
    { from: "b1", to: "c11", rtype: "FRIEND", },
    { from: "b1", to: "c12", rtype: "FRIEND", },
    { from: "b2", to: "c21", rtype: "FRIEND", },
    { from: "b2", to: "c22", rtype: "FRIEND", },
    { from: "b3", to: "c31", rtype: "FRIEND", },
    { from: "b3", to: "c32", rtype: "FRIEND", },
    { from: "b4", to: "c41", rtype: "FRIEND", },
    { from: "b4", to: "c42", rtype: "FRIEND", },
    { from: "b1", to: "b2", rtype: "FRIEND", },
    { from: "b2", to: "b3", rtype: "FRIEND", },
    { from: "b3", to: "b4", rtype: "FRIEND", },
    { from: "b4", to: "b1", rtype: "FRIEND", },
  ]
}

///|
/// Build the `binary-tree-1` graph: 13 nodes, 16 relationships.
fn build_fixture() -> @mg.Graph {
  let graph = @mg.Graph::new()
  let ids : Map[String, Int32] = Map([])
  for node in fixture_nodes() {
    let props : Map[String, @mg.Value] = Map([])
    props["name"] = @mg.VStr(node.name)
    ids[node.name] = graph.add_node([node.label], props)
  }
  for edge in fixture_edges() {
    let src = ids[edge.from]
    let dst = ids[edge.to]
    ignore(graph.add_edge(edge.rtype, src, dst, Map([]))) catch {
      _ => ()
    }
  }
  graph
}
