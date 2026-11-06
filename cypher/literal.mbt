// Parsing of expected node/relationship literals.
//
// The TCK writes expected values in Cypher surface syntax, e.g. `(:A {name: 'x'})`
// or `[:KNOWS]`. This module turns that text into labels/types plus literal
// properties, so callers can compare it against a stored node without needing a
// second textual parser.

///|
/// Evaluate a literal expression (no variables, no function calls).
fn literal_value(expr : Expr) -> @mg.Value? {
  match expr {
    ELit(v) => Some(v)
    EList(items) => {
      let values : Array[@mg.Value] = []
      for item in items {
        match literal_value(item) {
          Some(v) => values.push(v)
          None => return None
        }
      }
      Some(@mg.VList(values))
    }
    // Negative literals parse as `0 - n`.
    EBin("-", ELit(@mg.VInt(0L)), inner) =>
      match literal_value(inner) {
        Some(@mg.VInt(n)) => Some(@mg.VInt(-n))
        Some(@mg.VDouble(d)) => Some(@mg.VDouble(-d))
        _ => None
      }
    _ => None
  }
}

///|
/// Parse `(:A:B {k: v})` into labels and properties.
pub fn parse_node_expected(
  text : String,
) -> (Array[String], Map[String, @mg.Value])? {
  let query = parse_query("MATCH " + text + " RETURN 1") catch {
    _ => return None
  }
  if query.patterns.length() != 1 || query.patterns[0].hops.length() != 0 {
    return None
  }
  let pattern = query.patterns[0].start
  let props : Map[String, @mg.Value] = Map([])
  for (key, expr) in pattern.props {
    match literal_value(expr) {
      Some(value) => props[key] = value
      None => return None
    }
  }
  Some((pattern.labels, props))
}

///|
/// Parse `[:KNOWS {k: v}]` into a type and properties.
pub fn parse_rel_expected(text : String) -> (String, Map[String, @mg.Value])? {
  let query = parse_query("MATCH ()-" + text + "->() RETURN 1") catch {
    _ => return None
  }
  if query.patterns.length() != 1 || query.patterns[0].hops.length() != 1 {
    return None
  }
  let rel = query.patterns[0].hops[0].rel
  let props : Map[String, @mg.Value] = Map([])
  for (key, expr) in rel.props {
    match literal_value(expr) {
      Some(value) => props[key] = value
      None => return None
    }
  }
  let name = if rel.types.length() > 0 { rel.types[0] } else { "" }
  Some((name, props))
}
