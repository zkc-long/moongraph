// Write clauses: CREATE, MERGE, SET and DELETE.
//
// Writes are applied per binding after matching and filtering, in binding order,
// which keeps the observable result deterministic. There is no rollback: a query
// that fails halfway leaves the graph partially modified, and the CLI documents
// that. This is an in-process analytics engine, not a transactional database.

///|
/// Apply a write clause to every binding and return the bindings that survived
/// (MERGE can bind new variables, DELETE removes rows).
fn apply_write(
  graph : @mg.Graph,
  clause : WriteClause,
  bindings : Array[Binding],
) -> Array[Binding] {
  match clause {
    WCreate(patterns) => {
      let out : Array[Binding] = []
      for binding in bindings {
        let mut current = binding
        for pattern in patterns {
          current = create_pattern(graph, pattern, current)
        }
        out.push(current)
      }
      out
    }
    WMerge(patterns) => {
      let out : Array[Binding] = []
      for binding in bindings {
        let mut current = binding
        for pattern in patterns {
          let matched = match_pattern(graph, pattern, current)
          if matched.length() > 0 {
            current = matched[0]
          } else {
            current = create_pattern(graph, pattern, current)
          }
        }
        out.push(current)
      }
      out
    }
    WSet(items) => {
      for binding in bindings {
        for item in items {
          let value = eval(item.value, graph, binding)
          match binding.nodes.get(item.target) {
            Some(id) => graph.set_node_prop(id, item.key, value)
            None =>
              match binding.rels.get(item.target) {
                Some(id) => graph.set_edge_prop(id, item.key, value)
                None => ()
              }
          }
        }
      }
      bindings
    }
    WDelete(targets) => {
      // Collect first so that deleting one binding cannot invalidate another.
      let doomed_nodes : Array[Int] = []
      let doomed_edges : Array[Int] = []
      for binding in bindings {
        for target in targets {
          match binding.nodes.get(target) {
            Some(id) => doomed_nodes.push(id)
            None =>
              match binding.rels.get(target) {
                Some(id) => doomed_edges.push(id)
                None => ()
              }
          }
        }
      }
      for id in doomed_edges {
        graph.delete_edge(id)
      }
      for id in doomed_nodes {
        graph.delete_node(id)
      }
      []
    }
  }
}

///|
/// Create the nodes and relationships described by a pattern and bind them.
/// Already bound variables are reused rather than recreated.
fn create_pattern(
  graph : @mg.Graph,
  pattern : PathPat,
  binding : Binding,
) -> Binding {
  let mut current = binding
  let mut current_node = match resolve_node(pattern.start, current) {
    Some(id) => id
    None => {
      let labels = pattern.start.labels.copy()
      let props : Map[String, @mg.Value] = Map([])
      for (key, expr) in pattern.start.props {
        props[key] = eval(expr, graph, current)
      }
      let id = graph.add_node(labels, props)
      current = current.clone()
      if pattern.start.variable != "" {
        current.nodes[pattern.start.variable] = id
      }
      id
    }
  }
  for hop in pattern.hops {
    let target = match resolve_node(hop.node, current) {
      Some(id) => id
      None => {
        let labels = hop.node.labels.copy()
        let props : Map[String, @mg.Value] = Map([])
        for (key, expr) in hop.node.props {
          props[key] = eval(expr, graph, current)
        }
        let id = graph.add_node(labels, props)
        current = current.clone()
        if hop.node.variable != "" {
          current.nodes[hop.node.variable] = id
        }
        id
      }
    }
    let etype = if hop.rel.types.length() > 0 {
      hop.rel.types[0]
    } else {
      "RELATED"
    }
    let props : Map[String, @mg.Value] = Map([])
    let (src, dst) = match hop.rel.dir {
      In => (target, current_node)
      _ => (current_node, target)
    }
    let edge_id = graph.add_edge(etype, src, dst, props) catch { _ => -1 }
    if edge_id >= 0 && hop.rel.variable != "" {
      current = current.clone()
      current.rels[hop.rel.variable] = edge_id
    }
    current_node = target
  }
  current
}

///|
fn resolve_node(pattern : NodePat, binding : Binding) -> Int? {
  if pattern.variable == "" {
    return None
  }
  binding.nodes.get(pattern.variable)
}
