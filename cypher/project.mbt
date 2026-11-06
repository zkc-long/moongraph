// Projection, aggregation, ordering and result rendering.

///|
fn is_aggregate(expr : Expr) -> Bool {
  match expr {
    EFunc(name, _) =>
      name == "count" ||
      name == "sum" ||
      name == "avg" ||
      name == "min" ||
      name == "max" ||
      name == "collect"
    _ => false
  }
}

///|
pub fn QueryResult::column_index(self : QueryResult, name : String) -> Int32? {
  let mut i = 0
  for col in self.columns {
    if col == name {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
fn project(
  graph : @mg.Graph,
  query : Query,
  bindings : Array[Binding],
) -> QueryResult {
  let columns = query.items.map(fn(item) { item.col })
  let mut has_aggregate = false
  for item in query.items {
    if contains_aggregate(item.expr) {
      has_aggregate = true
    }
  }
  // Rows keep their binding so ORDER BY can reference variables that are not
  // part of the projection.
  let rows : Array[(Array[@mg.Value], Binding)] = []
  if has_aggregate {
    let groups = group_bindings(graph, query, bindings)
    for group in groups {
      rows.push(group)
    }
  } else {
    for binding in bindings {
      let values : Array[@mg.Value] = []
      for item in query.items {
        values.push(eval(item.expr, graph, binding))
      }
      rows.push((values, binding))
    }
  }
  let mut result_rows = rows
  if query.distinct {
    result_rows = dedupe(result_rows)
  }
  if query.order.length() > 0 {
    result_rows = sort_rows(graph, query, columns, result_rows)
  }
  // SKIP / LIMIT
  if query.skip is Some(offset) {
    let dropped : Array[(Array[@mg.Value], Binding)] = []
    let mut i = 0
    while i < result_rows.length() {
      if i >= offset {
        dropped.push(result_rows[i])
      }
      i = i + 1
    }
    result_rows = dropped
  }
  if query.limit is Some(limit) {
    let kept : Array[(Array[@mg.Value], Binding)] = []
    let mut i = 0
    while i < result_rows.length() && i < limit {
      kept.push(result_rows[i])
      i = i + 1
    }
    result_rows = kept
  }
  { columns, rows: result_rows.map(fn(row) { row.0 }), }
}

///|
fn dedupe(
  rows : Array[(Array[@mg.Value], Binding)],
) -> Array[(Array[@mg.Value], Binding)] {
  let seen : Map[String, Bool] = Map([])
  let out : Array[(Array[@mg.Value], Binding)] = []
  for row in rows {
    let key = row_key(row.0)
    if !seen.get(key).unwrap_or(false) {
      seen[key] = true
      out.push(row)
    }
  }
  out
}

///|
fn row_key(values : Array[@mg.Value]) -> String {
  let buf = StringBuilder()
  for value in values {
    buf.write_string(value.to_display())
    buf.write_string("\u{1}")
  }
  buf.to_string()
}

///|
/// Group rows by the non-aggregated projection items and fold the aggregates.
fn group_bindings(
  graph : @mg.Graph,
  query : Query,
  bindings : Array[Binding],
) -> Array[(Array[@mg.Value], Binding)] {
  // Group preserving first-seen order for deterministic output.
  let order : Array[String] = []
  let groups : Map[String, Array[Binding]] = Map([])
  let key_values : Map[String, Array[@mg.Value]] = Map([])
  if bindings.length() == 0 {
    // Aggregates over an empty input still produce one row (count = 0).
    let values : Array[@mg.Value] = []
    for item in query.items {
      values.push(eval_group(item.expr, graph, []))
    }
    return [(values, empty_binding())]
  }
  for binding in bindings {
    let values : Array[@mg.Value] = []
    for item in query.items {
      if !is_aggregate(item.expr) {
        values.push(eval(item.expr, graph, binding))
      }
    }
    let key = row_key(values)
    match groups.get(key) {
      Some(members) => members.push(binding)
      None => {
        groups[key] = [binding]
        key_values[key] = values
        order.push(key)
      }
    }
  }
  let out : Array[(Array[@mg.Value], Binding)] = []
  for key in order {
    let members = groups[key]
    let keys = key_values[key]
    let values : Array[@mg.Value] = []
    let mut ki = 0
    for item in query.items {
      if contains_aggregate(item.expr) {
        values.push(eval_group(item.expr, graph, members))
      } else {
        values.push(keys[ki])
        ki = ki + 1
      }
    }
    out.push((values, members[0]))
  }
  out
}

///|
fn fold(expr : Expr, graph : @mg.Graph, bindings : Array[Binding]) -> @mg.Value {
  match expr {
    EFunc(name, args) => {
      let values : Array[@mg.Value] = []
      for binding in bindings {
        match args {
          [arg] => values.push(eval(arg, graph, binding))
          _ => ()
        }
      }
      match name {
        "count" => {
          let mut n = 0
          for v in values {
            if !(v is @mg.VNull) {
              n = n + 1
            }
          }
          @mg.VInt(n.to_int64())
        }
        "sum" => {
          let sum = numeric_sum(values)
          @mg.VInt(sum.to_int64())
        }
        "avg" => {
          let mut total = 0.0
          let mut n = 0
          for v in values {
            if v.is_number() {
              total = total + v.as_double()
              n = n + 1
            }
          }
          if n == 0 {
            @mg.VNull
          } else {
            @mg.VDouble(total / n.to_double())
          }
        }
        "min" => extremum(values, true)
        "max" => extremum(values, false)
        "collect" => @mg.VList(values)
        _ => @mg.VNull
      }
    }
    _ => @mg.VNull
  }
}

///|
fn numeric_sum(values : Array[@mg.Value]) -> Double {
  let mut total = 0.0
  for v in values {
    if v.is_number() {
      total = total + v.as_double()
    }
  }
  total
}

///|
fn extremum(values : Array[@mg.Value], want_min : Bool) -> @mg.Value {
  let mut best = @mg.VNull
  let mut has = false
  for v in values {
    if v is @mg.VNull {
      continue
    }
    if !has {
      best = v
      has = true
      continue
    }
    let cmp = v.compare(best)
    if (want_min && cmp < 0) || (!want_min && cmp > 0) {
      best = v
    }
  }
  best
}

///|
fn sort_rows(
  graph : @mg.Graph,
  query : Query,
  columns : Array[String],
  rows : Array[(Array[@mg.Value], Binding)],
) -> Array[(Array[@mg.Value], Binding)] {
  // Pre-compute sort keys so the comparator stays cheap and total.
  let keyed : Array[(Array[@mg.Value], (Array[@mg.Value], Binding))] = []
  for row in rows {
    let keys : Array[@mg.Value] = []
    for order in query.order {
      keys.push(order_key(order.expr, graph, columns, row))
    }
    keyed.push((keys, row))
  }
  let sorted = merge_sort_by(keyed, query.order)
  sorted.map(fn(entry) { entry.1 })
}

///|
fn order_key(
  expr : Expr,
  graph : @mg.Graph,
  columns : Array[String],
  row : (Array[@mg.Value], Binding),
) -> @mg.Value {
  match expr {
    EVar(name) => {
      let mut i = 0
      for col in columns {
        if col == name {
          return row.0[i]
        }
        i = i + 1
      }
      eval(expr, graph, row.1)
    }
    _ => eval(expr, graph, row.1)
  }
}

///|
/// Stable insertion sort honouring per-key direction.
/// Result sets are small (they are already materialised); stability matters
/// more than asymptotics here, and every comparison is total.
fn merge_sort_by(
  rows : Array[(Array[@mg.Value], (Array[@mg.Value], Binding))],
  order : Array[OrderItem],
) -> Array[(Array[@mg.Value], (Array[@mg.Value], Binding))] {
  // Insertion sort over a freshly built array. Result sets are already
  // materialised and typically small; stability matters more than asymptotics,
  // and building the output explicitly keeps the comparator the only place
  // where ordering semantics live.
  let mut out : Array[(Array[@mg.Value], (Array[@mg.Value], Binding))] = []
  for row in rows {
    let next : Array[(Array[@mg.Value], (Array[@mg.Value], Binding))] = []
    let mut placed = false
    for existing in out {
      if !placed && compare_keys(row.0, existing.0, order) < 0 {
        next.push(row)
        placed = true
      }
      next.push(existing)
    }
    if !placed {
      next.push(row)
    }
    out = next
  }
  out
}

///|
fn compare_keys(
  a : Array[@mg.Value],
  b : Array[@mg.Value],
  order : Array[OrderItem],
) -> Int32 {
  let mut i = 0
  while i < a.length() && i < b.length() {
    let cmp = a[i].compare(b[i])
    if cmp != 0 {
      return if order[i].descending { -cmp } else { cmp }
    }
    i = i + 1
  }
  0
}

///|
/// Render the result as an aligned text table.
pub fn QueryResult::to_table(self : QueryResult) -> String {
  let widths : Array[Int32] = []
  for col in self.columns {
    widths.push(col.char_length())
  }
  let cells : Array[Array[String]] = []
  for row in self.rows {
    let rendered : Array[String] = []
    let mut i = 0
    for value in row {
      let text = value.to_display()
      rendered.push(text)
      if text.char_length() > widths[i] {
        widths[i] = text.char_length()
      }
      i = i + 1
    }
    cells.push(rendered)
  }
  let buf = StringBuilder()
  let line = fn() {
    buf.write_string("+")
    for width in widths {
      let mut k = 0
      while k < width + 2 {
        buf.write_char('-')
        k = k + 1
      }
      buf.write_string("+")
    }
    buf.write_string("\n")
  }
  line()
  buf.write_string("|")
  let mut c = 0
  for col in self.columns {
    buf.write_string(" " + col + " ")
    pad_to(buf, col.char_length(), widths[c])
    buf.write_string("|")
    c = c + 1
  }
  buf.write_string("\n")
  line()
  for row in cells {
    buf.write_string("|")
    let mut i = 0
    for text in row {
      buf.write_string(" " + text + " ")
      pad_to(buf, text.char_length(), widths[i])
      buf.write_string("|")
      i = i + 1
    }
    buf.write_string("\n")
  }
  line()
  buf.write_string("\{self.rows.length()} row(s)\n")
  buf.to_string()
}

///|
fn pad_to(buf : StringBuilder, width : Int32, target : Int32) -> Unit {
  let mut k = width
  while k < target {
    buf.write_char(' ')
    k = k + 1
  }
}

///|
/// Render the result as JSON for scripting.
pub fn QueryResult::to_json(self : QueryResult) -> String {
  let buf = StringBuilder()
  buf.write_string("{\"columns\":[")
  let mut first = true
  for col in self.columns {
    if !first {
      buf.write_string(",")
    }
    first = false
    buf.write_string("\"" + @mg.escape_json_string(col) + "\"")
  }
  buf.write_string("],\"rows\":[")
  first = true
  for row in self.rows {
    if !first {
      buf.write_string(",")
    }
    first = false
    buf.write_string("[")
    let mut first_cell = true
    for value in row {
      if !first_cell {
        buf.write_string(",")
      }
      first_cell = false
      buf.write_string(@mg.value_to_json(value).to_string())
    }
    buf.write_string("]")
  }
  buf.write_string("]}")
  buf.to_string()
}

///|
/// True when the expression contains an aggregate anywhere (e.g. `count(x) > 0`).
fn contains_aggregate(expr : Expr) -> Bool {
  match expr {
    EFunc(name, args) => {
      if is_aggregate_name(name) {
        return true
      }
      for arg in args {
        if contains_aggregate(arg) {
          return true
        }
      }
      false
    }
    EBin(_, l, r) => contains_aggregate(l) || contains_aggregate(r)
    ENot(e) => contains_aggregate(e)
    EIsNull(e, _) => contains_aggregate(e)
    EList(items) => {
      for item in items {
        if contains_aggregate(item) {
          return true
        }
      }
      false
    }
    EIndex(a, b) => contains_aggregate(a) || contains_aggregate(b)
    ESlice(a, b, c) =>
      contains_aggregate(a) ||
      (match b {
        Some(e) => contains_aggregate(e)
        None => false
      }) ||
      (match c {
        Some(e) => contains_aggregate(e)
        None => false
      })
    _ => false
  }
}

///|
fn is_aggregate_name(name : String) -> Bool {
  name == "count" ||
  name == "sum" ||
  name == "avg" ||
  name == "min" ||
  name == "max" ||
  name == "collect"
}

///|
/// Evaluate a projection item in the context of a group: aggregates fold over
/// the group, everything else recurses so `count(x) > 0` works.
fn eval_group(
  expr : Expr,
  graph : @mg.Graph,
  members : Array[Binding],
) -> @mg.Value {
  match expr {
    EFunc(name, _) =>
      if is_aggregate_name(name) {
        fold(expr, graph, members)
      } else {
        eval(expr, graph, sample(members))
      }
    EBin(op, l, r) =>
      apply_binop(op, eval_group(l, graph, members), eval_group(r, graph, members))
    ENot(e) =>
      match eval_group(e, graph, members) {
        @mg.VBool(b) => @mg.VBool(!b)
        _ => @mg.VNull
      }
    EIsNull(e, negated) => {
      let is_null = eval_group(e, graph, members) is @mg.VNull
      @mg.VBool(if negated { !is_null } else { is_null })
    }
    EList(items) => {
      let out : Array[@mg.Value] = []
      for item in items {
        out.push(eval_group(item, graph, members))
      }
      @mg.VList(out)
    }
    _ => eval(expr, graph, sample(members))
  }
}

///|
fn sample(members : Array[Binding]) -> Binding {
  if members.length() == 0 {
    empty_binding()
  } else {
    members[0]
  }
}