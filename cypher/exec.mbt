// Query execution: a small Volcano-style pipeline over bindings.
//
// A binding maps variable names to node ids, relationship ids or scalar values.
// Patterns are matched left to right; each hop expands the current binding set.
// The pipeline is materialising (arrays between operators) rather than lazy:
// graphs that fit in memory are the target use case, and materialising keeps
// ORDER BY / DISTINCT simple.

///|
pub struct Binding {
  vals : Map[String, @mg.Value]
  nodes : Map[String, Int32]
  rels : Map[String, Int32]
  paths : Map[String, String]
  path_lens : Map[String, Int32]
}

///|
fn empty_binding() -> Binding {
  {
    vals: Map([]),
    nodes: Map([]),
    rels: Map([]),
    paths: Map([]),
    path_lens: Map([]),
  }
}

///|
fn Binding::clone(self : Binding) -> Binding {
  {
    vals: self.vals.copy(),
    nodes: self.nodes.copy(),
    rels: self.rels.copy(),
    paths: self.paths.copy(),
    path_lens: self.path_lens.copy(),
  }
}

///|
pub struct QueryResult {
  columns : Array[String]
  rows : Array[Array[@mg.Value]]
}

///|
pub fn QueryResult::row_count(self : QueryResult) -> Int32 {
  self.rows.length()
}

///|
pub fn QueryResult::column_count(self : QueryResult) -> Int32 {
  self.columns.length()
}

///|
/// Run a query against a graph. Parsing errors are the only failure mode:
/// the evaluator is total (type mismatches yield `null`, like Cypher).
pub fn run(graph : @mg.Graph, source : String) -> QueryResult raise ParseError {
  let query = parse_query(source)
  let (_, result) = execute(graph, query, [empty_binding()])
  result
}

///|
/// Run a script of statements, carrying variable bindings from one statement
/// to the next. The TCK having executed: blocks rely on this: a node created
/// in one statement is referenced by name in the next.
pub fn run_script(graph : @mg.Graph, statements : Array[String]) -> Unit raise ParseError {
  let mut bindings : Array[Binding] = [empty_binding()]
  for statement in statements {
    let query = parse_query(statement)
    let (next, _) = execute(graph, query, bindings)
    bindings = next
  }
}

///|
fn execute(
  graph : @mg.Graph,
  query : Query,
  initial : Array[Binding],
) -> (Array[Binding], QueryResult) {
  let mut bindings : Array[Binding] = initial
  for pattern in query.patterns {
    let next : Array[Binding] = []
    for binding in bindings {
      for matched in match_pattern(graph, pattern, binding) {
        next.push(matched)
      }
    }
    bindings = next
  }
  match query.where_ {
    Some(cond) => {
      let kept : Array[Binding] = []
      for binding in bindings {
        if truthy(eval(cond, graph, binding)) {
          kept.push(binding)
        }
      }
      bindings = kept
    }
    None => ()
  }
  let after_with = match query.with_ {
    Some(clause) => apply_with(graph, clause, bindings)
    None => bindings
  }
  // A second MATCH may run after WITH, expanding from the surviving variables.
  let mut reported : Array[Binding] = after_with
  for pattern in query.post {
    let next : Array[Binding] = []
    for binding in reported {
      for matched in match_pattern(graph, pattern, binding) {
        next.push(matched)
      }
    }
    reported = next
  }
  match query.post_where {
    Some(cond) => {
      let kept : Array[Binding] = []
      for binding in reported {
        if truthy(eval(cond, graph, binding)) {
          kept.push(binding)
        }
      }
      reported = kept
    }
    None => ()
  }
  let bindings = match query.write {
    Some(clause) => apply_write(graph, clause, reported)
    None => reported
  }
  if !query.has_return {
    return (bindings, { columns: [], rows: [], })
  }
  (bindings, project(graph, query, bindings))
}

///|
fn match_pattern(
  graph : @mg.Graph,
  pattern : PathPat,
  binding : Binding,
) -> Array[Binding] {
  if pattern.shortest {
    return match_shortest(graph, pattern, binding)
  }
  let results : Array[Binding] = []
  let candidates = start_candidates(graph, pattern.start, binding)
  for node in candidates {
    match bind_node(pattern.start, node, binding, graph) {
      Some(next) =>
        expand_hops(
          graph,
          pattern.hops,
          0,
          node,
          next,
          graph.node_text(node),
          0,
          pattern.variable,
          results,
        )
      None => ()
    }
  }
  results
}

///|
/// `shortestPath((a)-[:T*]-(b))`: both endpoints must already be bound.
fn match_shortest(
  graph : @mg.Graph,
  pattern : PathPat,
  binding : Binding,
) -> Array[Binding] {
  let from = match binding.nodes.get(pattern.start.variable) {
    Some(id) => id
    None => return []
  }
  if pattern.hops.length() != 1 {
    return []
  }
  let hop = pattern.hops[0]
  let to = match binding.nodes.get(hop.node.variable) {
    Some(id) => id
    None => return []
  }
  if from == to && hop.rel.min_hops > 0 {
    return []
  }
  match shortest_path_text(graph, from, to, hop.rel) {
    Some((text, hops_count)) => {
      if hops_count < hop.rel.min_hops {
        return []
      }
      if hop.rel.max_hops >= 0 && hops_count > hop.rel.max_hops {
        return []
      }
      let next = binding.clone()
      if pattern.variable != "" {
        next.paths[pattern.variable] = text
        next.path_lens[pattern.variable] = hops_count
      }
      [next]
    }
    None => []
  }
}

///|
fn expand_hops(
  graph : @mg.Graph,
  hops : Array[Hop],
  index : Int32,
  current : Int32,
  binding : Binding,
  path_text : String,
  path_len : Int32,
  path_var : String,
  out : Array[Binding],
) -> Unit {
  if index >= hops.length() {
    let mut result = binding
    if path_var != "" {
      result = result.clone()
      result.paths[path_var] = path_text
      result.path_lens[path_var] = path_len
    }
    out.push(result)
    return
  }
  let hop = hops[index]
  for (target, rel_ids) in follow(graph, current, hop.rel) {
    let mut next = binding
    if hop.rel.variable != "" {
      next = next.clone()
      // Variable length relationships bind the last relationship id; the
      // full path is available through `length()` on the node pair.
      next.rels[hop.rel.variable] = rel_ids[rel_ids.length() - 1]
    }
    let rel_ok = if hop.rel.props.length() == 0 {
      true
    } else {
      let last = rel_ids[rel_ids.length() - 1]
      let edge = graph.edge(last)
      let mut ok = true
      for (key, expr) in hop.rel.props {
        if !edge.prop(key).equal_value(eval(expr, graph, next)) {
          ok = false
        }
      }
      ok
    }
    if rel_ok {
      let extended = path_text +
        rel_step_text(hop.rel, rel_ids[rel_ids.length() - 1], graph) +
        graph.node_text(target)
      match bind_node(hop.node, target, next, graph) {
        Some(bound) =>
          expand_hops(
            graph,
            hops,
            index + 1,
            target,
            bound,
            extended,
            path_len + rel_ids.length(),
            path_var,
            out,
          )
        None => ()
      }
    }
  }
}

///|
/// Follow one relationship pattern from `node`, returning `(target, rel_ids)`.
/// `rel_ids` has one entry for a single hop and one per traversed edge for a
/// variable length hop.
fn follow(
  graph : @mg.Graph,
  node : Int32,
  rel : RelPat,
) -> Array[(Int32, Array[Int32])] {
  let single = rel.min_hops == 1 && rel.max_hops == 1
  if single {
    let edges = neighbors(graph, node, rel)
    let result : Array[(Int32, Array[Int32])] = []
    for (target, edge_id) in edges {
      result.push((target, [edge_id]))
    }
    return result
  }
  // Variable length: breadth first, bounded by max_hops (-1 = unbounded but
  // still bounded by the node count to guarantee termination).
  let limit = if rel.max_hops < 0 { graph.node_count() } else { rel.max_hops }
  let result : Array[(Int32, Array[Int32])] = []
  let mut frontier : Array[(Int32, Array[Int32])] = [(node, [])]
  let mut depth = 0
  while depth < limit && frontier.length() > 0 {
    let next : Array[(Int32, Array[Int32])] = []
    for (current, path) in frontier {
      for (target, edge_id) in neighbors(graph, current, rel) {
        let new_path = path.copy()
        new_path.push(edge_id)
        if depth + 1 >= rel.min_hops {
          result.push((target, new_path))
        }
        next.push((target, new_path))
      }
    }
    frontier = next
    depth = depth + 1
  }
  result
}

///|
fn neighbors(
  graph : @mg.Graph,
  node : Int32,
  rel : RelPat,
) -> Array[(Int32, Int32)] {
  let result : Array[(Int32, Int32)] = []
  let add = fn(pairs : Array[(Int32, Int32)]) {
    for (target, edge_id) in pairs {
      if rel.types.length() == 0 || type_matches(graph, edge_id, rel.types) {
        result.push((target, edge_id))
      }
    }
  }
  match rel.dir {
    Out => add(graph.out_neighbors(node))
    In => add(graph.in_neighbors(node))
    Both => {
      add(graph.out_neighbors(node))
      add(graph.in_neighbors(node))
    }
  }
  result
}

///|
fn type_matches(
  graph : @mg.Graph,
  edge_id : Int32,
  types : Array[String],
) -> Bool {
  let etype = graph.edge(edge_id).etype
  for t in types {
    if t == etype {
      return true
    }
  }
  false
}

///|
fn start_candidates(
  graph : @mg.Graph,
  node : NodePat,
  binding : Binding,
) -> Array[Int32] {
  match binding.nodes.get(node.variable) {
    Some(id) => [id]
    None =>
      if node.labels.length() > 0 {
        let result : Array[Int32] = []
        let seen : Map[Int32, Bool] = Map([])
        for label in node.labels {
          for id in graph.nodes_with_label(label) {
            if !seen.get(id).unwrap_or(false) {
              seen[id] = true
              result.push(id)
            }
          }
        }
        result
      } else {
        let result : Array[Int32] = []
        let mut i = 0
        while i < graph.node_count() {
          result.push(i)
          i = i + 1
        }
        result
      }
  }
}

///|
fn bind_node(
  node : NodePat,
  id : Int32,
  binding : Binding,
  graph : @mg.Graph,
) -> Binding? {
  let mut next = binding
  if node.variable != "" {
    match binding.nodes.get(node.variable) {
      Some(existing) => if existing != id { return None }
      None => {
        next = next.clone()
        next.nodes[node.variable] = id
      }
    }
  }
  let data = graph.node(id)
  for label in node.labels {
    if !data.has_label(label) {
      return None
    }
  }
  for (key, expr) in node.props {
    let expected = eval(expr, graph, next)
    if !data.prop(key).equal_value(expected) {
      return None
    }
  }
  Some(next)
}

///|
fn truthy(value : @mg.Value) -> Bool {
  match value {
    @mg.VBool(b) => b
    @mg.VNull => false
    _ => true
  }
}

///|
/// Three valued logic: comparisons involving `null` evaluate to `null`.
fn eval(expr : Expr, graph : @mg.Graph, binding : Binding) -> @mg.Value {
  match expr {
    ELit(v) => v
    EVar(name) =>
      match binding.vals.get(name) {
        Some(v) => v
        None =>
          match binding.nodes.get(name) {
            Some(id) => @mg.VStr(graph.node_text(id))
            None =>
              match binding.rels.get(name) {
                Some(id) => @mg.VStr(graph.rel_text(id))
                None =>
                  match binding.paths.get(name) {
                    Some(text) => @mg.VStr(text)
                    None => @mg.VNull
                  }
              }
          }
      }
    EProp(base, key) =>
      match base {
        EVar(name) =>
          match binding.nodes.get(name) {
            Some(id) => graph.node(id).prop(key)
            None =>
              match binding.rels.get(name) {
                Some(id) => graph.edge(id).prop(key)
                None => @mg.VNull
              }
          }
        _ => @mg.VNull
      }
    ENot(inner) =>
      match eval(inner, graph, binding) {
        @mg.VBool(b) => @mg.VBool(!b)
        _ => @mg.VNull
      }
    EIsNull(inner, negated) => {
      let is_null = eval(inner, graph, binding) is @mg.VNull
      @mg.VBool(if negated { !is_null } else { is_null })
    }
    EList(items) =>
      @mg.VList(items.map(fn(item) { eval(item, graph, binding) }))
    EBin(op, left, right) => eval_binary(op, left, right, graph, binding)
    EFunc(name, args) => eval_function(name, args, graph, binding)
    EIndex(base, index) => {
      let container = eval(base, graph, binding)
      index_value(container, eval(index, graph, binding))
    }
    ESlice(base, lo, hi) => {
      let container = eval(base, graph, binding)
      let from = match lo {
        Some(e) => eval(e, graph, binding)
        None => @mg.VNull
      }
      let upto = match hi {
        Some(e) => eval(e, graph, binding)
        None => @mg.VNull
      }
      slice_value(container, from, upto)
    }
    EHasLabel(base, labels) =>
      match base {
        EVar(name) =>
          match binding.nodes.get(name) {
            Some(id) => {
              let node = graph.node(id)
              let mut ok = true
              for label in labels {
                if !node.has_label(label) {
                  ok = false
                }
              }
              @mg.VBool(ok)
            }
            None => @mg.VBool(false)
          }
        _ => @mg.VBool(false)
      }
    EListComp(variable, source, predicate, projection) => {
      let src = eval(source, graph, binding)
      match src {
        @mg.VList(items) => {
          let out : Array[@mg.Value] = []
          for item in items {
            let inner = binding.clone()
            inner.vals[variable] = item
            let keep = match predicate {
              Some(pred) => truthy(eval(pred, graph, inner))
              None => true
            }
            if keep {
              out.push(eval(projection, graph, inner))
            }
          }
          @mg.VList(out)
        }
        _ => @mg.VNull
      }
    }
    EMapProj(base, entries) => map_projection_value(base, entries, graph, binding)
  }
}

///|
fn index_value(container : @mg.Value, index : @mg.Value) -> @mg.Value {
  match (container, index) {
    (@mg.VList(items), @mg.VInt(i)) => {
      let n = items.length()
      let mut idx = i.to_int()
      if idx < 0 {
        idx = n + idx
      }
      if idx < 0 || idx >= n {
        @mg.VNull
      } else {
        items[idx]
      }
    }
    (@mg.VStr(s), @mg.VInt(i)) => {
      let chars = Array::from_iter(s.iter())
      let n = chars.length()
      let mut idx = i.to_int()
      if idx < 0 {
        idx = n + idx
      }
      if idx < 0 || idx >= n {
        @mg.VNull
      } else {
        @mg.VStr(String::from_array([chars[idx]]))
      }
    }
    _ => @mg.VNull
  }
}

///|
fn slice_value(
  container : @mg.Value,
  from : @mg.Value,
  upto : @mg.Value,
) -> @mg.Value {
  match container {
    @mg.VList(items) => {
      let n = items.length()
      let start = match from {
        @mg.VInt(i) => normalize_index(i.to_int(), n)
        _ => 0
      }
      let stop = match upto {
        @mg.VInt(i) => normalize_index(i.to_int(), n)
        _ => n
      }
      let out : Array[@mg.Value] = []
      let mut i = start
      while i < stop && i < n {
        out.push(items[i])
        i = i + 1
      }
      @mg.VList(out)
    }
    _ => @mg.VNull
  }
}

///|
fn normalize_index(index : Int, length : Int) -> Int {
  let mut i = index
  if i < 0 {
    i = length + i
  }
  if i < 0 {
    0
  } else if i > length {
    length
  } else {
    i
  }
}

///|
/// `n {.name, alias: expr}` rendered as canonical map text.
fn map_projection_value(
  base : Expr,
  entries : Array[(String, Expr?)],
  graph : @mg.Graph,
  binding : Binding,
) -> @mg.Value {
  let node_id = match base {
    EVar(name) =>
      match binding.nodes.get(name) {
        Some(id) => Some(id)
        None => None
      }
    _ => None
  }
  match node_id {
    None => @mg.VNull
    Some(id) => {
      let node = graph.node(id)
      let parts : Array[String] = []
      for (key, value) in entries {
        if key == "*" {
          let keys = Array::from_iter(node.props.keys())
          keys.sort()
          for k in keys {
            parts.push(k + ": " + node.props[k].to_cypher())
          }
          continue
        }
        let rendered = match value {
          Some(expr) => eval(expr, graph, binding)
          None => node.prop(key)
        }
        parts.push(key + ": " + rendered.to_cypher())
      }
      @mg.VStr("{" + join_strings(parts) + "}")
    }
  }
}

///|
fn join_strings(parts : Array[String]) -> String {
  let buf = StringBuilder()
  let mut first = true
  for part in parts {
    if !first {
      buf.write_string(", ")
    }
    first = false
    buf.write_string(part)
  }
  buf.to_string()
}

///|
fn eval_binary(
  op : String,
  left : Expr,
  right : Expr,
  graph : @mg.Graph,
  binding : Binding,
) -> @mg.Value {
  // AND / OR short circuit with three valued logic.
  if op == "AND" {
    let l = truthy(eval(left, graph, binding))
    if !l {
      return @mg.VBool(false)
    }
    return eval(right, graph, binding)
  }
  if op == "OR" {
    let l = truthy(eval(left, graph, binding))
    if l {
      return @mg.VBool(true)
    }
    return eval(right, graph, binding)
  }
  let l = eval(left, graph, binding)
  let r = eval(right, graph, binding)
  apply_binop(op, l, r)
}

///|
/// Value-level binary operator; shared by scalar evaluation and aggregate
/// expressions such as count(x) > 0.
fn apply_binop(op : String, l : @mg.Value, r : @mg.Value) -> @mg.Value {
  match op {
    "=" => bool_or_null(l, r, fn(a, b) { a.equal_value(b) })
    "<>" => bool_or_null(l, r, fn(a, b) { !a.equal_value(b) })
    "<" => bool_or_null(l, r, fn(a, b) { a.compare(b) < 0 })
    "<=" => bool_or_null(l, r, fn(a, b) { a.compare(b) <= 0 })
    ">" => bool_or_null(l, r, fn(a, b) { a.compare(b) > 0 })
    ">=" => bool_or_null(l, r, fn(a, b) { a.compare(b) >= 0 })
    "+" => arith_plus(l, r)
    "-" => arith(l, r, fn(a, b) { a - b })
    "*" => arith(l, r, fn(a, b) { a * b })
    "/" => arith(l, r, fn(a, b) { if b == 0.0 { 0.0 } else { a / b } })
    "%" => arith(l, r, fn(a, b) { a % b })
    "IN" =>
      match r {
        @mg.VList(items) => {
          let mut found = false
          for item in items {
            if l.equal_value(item) {
              found = true
            }
          }
          @mg.VBool(found)
        }
        _ => @mg.VNull
      }
    "CONTAINS" =>
      match (l, r) {
        (@mg.VStr(a), @mg.VStr(b)) => @mg.VBool(a.contains(b))
        _ => @mg.VNull
      }
    "STARTS WITH" =>
      match (l, r) {
        (@mg.VStr(a), @mg.VStr(b)) => @mg.VBool(a.has_prefix(b))
        _ => @mg.VNull
      }
    "ENDS WITH" =>
      match (l, r) {
        (@mg.VStr(a), @mg.VStr(b)) => @mg.VBool(a.has_suffix(b))
        _ => @mg.VNull
      }
    _ => @mg.VNull
  }
}

///|
fn bool_or_null(
  l : @mg.Value,
  r : @mg.Value,
  predicate : (@mg.Value, @mg.Value) -> Bool,
) -> @mg.Value {
  if l is @mg.VNull || r is @mg.VNull {
    @mg.VNull
  } else {
    @mg.VBool(predicate(l, r))
  }
}

///|
fn arith(
  l : @mg.Value,
  r : @mg.Value,
  op : (Double, Double) -> Double,
) -> @mg.Value {
  if l is @mg.VNull || r is @mg.VNull {
    return @mg.VNull
  }
  if !l.is_number() || !r.is_number() {
    return @mg.VNull
  }
  let result = op(l.as_double(), r.as_double())
  if l is @mg.VInt(_) && r is @mg.VInt(_) {
    @mg.VInt(result.to_int64())
  } else {
    @mg.VDouble(result)
  }
}

///|
fn arith_plus(l : @mg.Value, r : @mg.Value) -> @mg.Value {
  match (l, r) {
    (@mg.VList(a), @mg.VList(b)) => {
      let out : Array[@mg.Value] = []
      for item in a {
        out.push(item)
      }
      for item in b {
        out.push(item)
      }
      @mg.VList(out)
    }
    (@mg.VStr(a), _) => @mg.VStr(a + r.to_display())
    (_, @mg.VStr(b)) => @mg.VStr(l.to_display() + b)
    _ => arith(l, r, fn(a, b) { a + b })
  }
}

///|
fn eval_function(
  name : String,
  args : Array[Expr],
  graph : @mg.Graph,
  binding : Binding,
) -> @mg.Value {
  match name {
    "id" =>
      match args {
        [EVar(var_name)] =>
          match resolve_binding_id(binding, var_name) {
            Some((_, id)) => @mg.VInt(id.to_int64())
            None => @mg.VNull
          }
        _ => @mg.VNull
      }
    "labels" =>
      match args {
        [EVar(var_name)] =>
          match binding.nodes.get(var_name) {
            Some(id) =>
              @mg.VList(graph.node(id).labels.map(fn(l) { @mg.VStr(l) }))
            None => @mg.VNull
          }
        _ => @mg.VNull
      }
    "type" =>
      match args {
        [EVar(var_name)] =>
          match binding.rels.get(var_name) {
            Some(id) => @mg.VStr(graph.edge(id).etype)
            None => @mg.VNull
          }
        _ => @mg.VNull
      }
    "coalesce" => {
      let mut result = @mg.VNull
      for arg in args {
        let v = eval(arg, graph, binding)
        if !(v is @mg.VNull) {
          result = v
          break
        }
      }
      result
    }
    "toUpper" =>
      match args {
        [arg] =>
          match eval(arg, graph, binding) {
            @mg.VStr(s) => @mg.VStr(s.to_upper())
            _ => @mg.VNull
          }
        _ => @mg.VNull
      }
    "toLower" =>
      match args {
        [arg] =>
          match eval(arg, graph, binding) {
            @mg.VStr(s) => @mg.VStr(s.to_lower())
            _ => @mg.VNull
          }
        _ => @mg.VNull
      }
    "length" =>
      match args {
        [EVar(name)] =>
          match binding.path_lens.get(name) {
            Some(n) => @mg.VInt(n.to_int64())
            None => @mg.VNull
          }
        _ => @mg.VNull
      }
    "size" | "length" =>
      match args {
        [arg] =>
          match eval(arg, graph, binding) {
            @mg.VStr(s) => @mg.VInt(s.char_length().to_int64())
            @mg.VList(items) => @mg.VInt(items.length().to_int64())
            _ => @mg.VNull
          }
        _ => @mg.VNull
      }
    "abs" =>
      match args {
        [arg] =>
          match eval(arg, graph, binding) {
            @mg.VInt(i) => @mg.VInt(if i < 0L { -i } else { i })
            @mg.VDouble(d) => @mg.VDouble(if d < 0.0 { -d } else { d })
            _ => @mg.VNull
          }
        _ => @mg.VNull
      }
    // Aggregates are handled in `project`; outside a projection they are null.
    "shortestPath" =>
      match args {
        [EVar(from_name), EVar(to_name)] =>
          match (binding.nodes.get(from_name), binding.nodes.get(to_name)) {
            (Some(src), Some(dst)) => shortest_path_length(graph, src, dst)
            _ => @mg.VNull
          }
        _ => @mg.VNull
      }
    "count" | "sum" | "avg" | "min" | "max" | "collect" => @mg.VNull
    _ => @mg.VNull
  }
}

///|
/// Resolve a variable to `(kind, id)` where kind 0 is a node and 1 a
/// relationship. Used by `id()`, `labels()` and `type()`.
fn resolve_binding_id(binding : Binding, name : String) -> (Int32, Int32)? {
  match binding.nodes.get(name) {
    Some(id) => Some((0, id))
    None =>
      match binding.rels.get(name) {
        Some(id) => Some((1, id))
        None => None
      }
  }
}

///|
/// Breadth-first hop distance treating relationships as undirected.
/// Returns `null` when the two nodes are not connected.
fn shortest_path_length(
  graph : @mg.Graph,
  from : Int32,
  to : Int32,
) -> @mg.Value {
  if from == to {
    return @mg.VInt(0L)
  }
  let dist : Map[Int32, Int32] = Map([])
  dist[from] = 0
  let queue : Array[Int32] = [from]
  let mut head = 0
  while head < queue.length() {
    let node = queue[head]
    head = head + 1
    let depth = dist[node]
    let neighbours : Array[(Int32, Int32)] = []
    for pair in graph.out_neighbors(node) {
      neighbours.push(pair)
    }
    for pair in graph.in_neighbors(node) {
      neighbours.push(pair)
    }
    for (next, _) in neighbours {
      if next == to {
        return @mg.VInt((depth + 1).to_int64())
      }
      if dist.get(next) is None {
        dist[next] = depth + 1
        queue.push(next)
      }
    }
  }
  @mg.VNull
}

///|
/// `-[:TYPE]->` / `<-[:TYPE]-` / `-[:TYPE]-` for one step of a path.
fn rel_step_text(rel : RelPat, edge_id : Int32, graph : @mg.Graph) -> String {
  let etype = if rel.types.length() > 0 {
    rel.types[0]
  } else {
    graph.edge(edge_id).etype
  }
  let body = if etype == "" { "[]" } else { "[:\{etype}]" }
  match rel.dir {
    Out => "-" + body + "->"
    In => "<-" + body + "-"
    Both => "-" + body + "-"
  }
}

///|
/// Shortest path between two bound nodes, honouring the relationship type
/// filter. Returns the canonical path text and its hop count.
fn shortest_path_text(
  graph : @mg.Graph,
  from : Int32,
  to : Int32,
  rel : RelPat,
) -> (String, Int32)? {
  if from == to {
    return Some((graph.node_text(from), 0))
  }
  // BFS with predecessors: node -> (previous node, edge id)
  let prev : Map[Int32, (Int32, Int32)] = Map([])
  let seen : Map[Int32, Bool] = Map([])
  seen[from] = true
  let queue : Array[Int32] = [from]
  let mut head = 0
  let mut found = false
  while head < queue.length() && !found {
    let node = queue[head]
    head = head + 1
    let candidates : Array[(Int32, Int32)] = []
    match rel.dir {
      In =>
        for pair in graph.in_neighbors(node) {
          candidates.push(pair)
        }
      Out =>
        for pair in graph.out_neighbors(node) {
          candidates.push(pair)
        }
      Both => {
        for pair in graph.out_neighbors(node) {
          candidates.push(pair)
        }
        for pair in graph.in_neighbors(node) {
          candidates.push(pair)
        }
      }
    }
    for (next, edge_id) in candidates {
      if !type_ok(graph, edge_id, rel) {
        continue
      }
      if seen.get(next).unwrap_or(false) {
        continue
      }
      seen[next] = true
      prev[next] = (node, edge_id)
      if next == to {
        found = true
        break
      }
      queue.push(next)
    }
  }
  if !found {
    return None
  }
  // Reconstruct backwards.
  let steps : Array[(Int32, Int32)] = []
  let mut cursor = to
  while cursor != from {
    match prev.get(cursor) {
      Some((parent, edge_id)) => {
        steps.push((parent, edge_id))
        cursor = parent
      }
      None => return None
    }
  }
  let buf = StringBuilder()
  buf.write_string(graph.node_text(from))
  let mut i = steps.length() - 1
  while i >= 0 {
    let (parent, edge_id) = steps[i]
    let target = if i == 0 { to } else { steps[i - 1].0 }
    ignore(parent)
    buf.write_string(rel_step_text(rel, edge_id, graph))
    buf.write_string(graph.node_text(target))
    i = i - 1
  }
  Some((buf.to_string(), steps.length()))
}

///|
fn type_ok(graph : @mg.Graph, edge_id : Int32, rel : RelPat) -> Bool {
  if rel.types.length() == 0 {
    return true
  }
  let etype = graph.edge(edge_id).etype
  for t in rel.types {
    if t == etype {
      return true
    }
  }
  false
}
