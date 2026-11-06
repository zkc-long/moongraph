// The WITH clause: project the current row set and continue matching.
//
// `WITH` closes the previous pipeline stage. Variables mentioned in the
// projection survive; everything else is dropped. Node and relationship
// variables stay bound as structure (not just text) so a later MATCH can
// expand from them.

///|
/// Apply a WITH clause: project items, optionally aggregate, then filter.
fn apply_with(
  graph : @mg.Graph,
  clause : WithClause,
  bindings : Array[Binding],
) -> Array[Binding] {
  let projected = if has_aggregate_items(clause.items) {
    project_grouped(graph, clause.items, clause.distinct, bindings)
  } else {
    project_flat(graph, clause.items, clause.distinct, bindings)
  }
  match clause.where_ {
    Some(cond) => {
      let kept : Array[Binding] = []
      for binding in projected {
        if truthy(eval(cond, graph, binding)) {
          kept.push(binding)
        }
      }
      kept
    }
    None => projected
  }
}

///|
fn has_aggregate_items(items : Array[ReturnItem]) -> Bool {
  for item in items {
    if is_aggregate(item.expr) {
      return true
    }
  }
  false
}

///|
fn project_flat(
  graph : @mg.Graph,
  items : Array[ReturnItem],
  distinct : Bool,
  bindings : Array[Binding],
) -> Array[Binding] {
  let out : Array[Binding] = []
  let seen : Map[String, Bool] = Map([])
  for binding in bindings {
    let next = rebind(graph, items, binding, fn(expr) {
      eval(expr, graph, binding)
    })
    if distinct {
      let key = binding_key(next)
      if seen.get(key).unwrap_or(false) {
        continue
      }
      seen[key] = true
    }
    out.push(next)
  }
  out
}

///|
fn project_grouped(
  graph : @mg.Graph,
  items : Array[ReturnItem],
  distinct : Bool,
  bindings : Array[Binding],
) -> Array[Binding] {
  // Reuse the aggregation machinery by fabricating a query with only items.
  let pseudo : Query = {
    patterns: [],
    with_: None,
    post: [],
    post_where: None,
    write: None,
    has_return: true,
    where_: None,
    items,
    distinct,
    order: [],
    skip: None,
    limit: None,
  }
  let groups = group_bindings(graph, pseudo, bindings)
  let out : Array[Binding] = []
  for (values, representative) in groups {
    let next : Binding = {
      vals: Map([]),
      nodes: Map([]),
      rels: Map([]),
      paths: Map([]),
      path_lens: Map([]),
    }
    let mut i = 0
    for item in items {
      match item.expr {
        EVar(name) =>
          match representative.nodes.get(name) {
            Some(id) => next.nodes[item.col] = id
            None =>
              match representative.rels.get(name) {
                Some(id) => next.rels[item.col] = id
                None => next.vals[item.col] = values[i]
              }
          }
        _ => next.vals[item.col] = values[i]
      }
      i = i + 1
    }
    out.push(next)
  }
  out
}

///|
/// Build the next binding: node/relationship variables stay structural, other
/// expressions become scalar values under their column name.
fn rebind(
  graph : @mg.Graph,
  items : Array[ReturnItem],
  binding : Binding,
  evaluate : (Expr) -> @mg.Value,
) -> Binding {
  let next : Binding = {
    vals: Map([]),
    nodes: Map([]),
    rels: Map([]),
    paths: Map([]),
    path_lens: Map([]),
  }
  for item in items {
    match item.expr {
      EVar(name) =>
        match binding.nodes.get(name) {
          Some(id) => next.nodes[item.col] = id
          None =>
            match binding.rels.get(name) {
              Some(id) => next.rels[item.col] = id
              None => next.vals[item.col] = evaluate(item.expr)
            }
        }
      _ => next.vals[item.col] = evaluate(item.expr)
    }
  }
  next
}

///|
fn binding_key(binding : Binding) -> String {
  let buf = StringBuilder()
  let node_keys = Array::from_iter(binding.nodes.keys())
  node_keys.sort()
  for key in node_keys {
    buf.write_string(key)
    buf.write_string("=")
    buf.write_string(binding.nodes[key].to_string())
    buf.write_string(";")
  }
  let val_keys = Array::from_iter(binding.vals.keys())
  val_keys.sort()
  for key in val_keys {
    buf.write_string(key)
    buf.write_string("=")
    buf.write_string(binding.vals[key].to_display())
    buf.write_string(";")
  }
  buf.to_string()
}
