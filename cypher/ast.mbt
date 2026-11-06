// Cypher abstract syntax tree.

///|
pub enum Expr {
  ELit(@mg.Value)
  EVar(String)
  EProp(Expr, String)
  EBin(String, Expr, Expr)
  ENot(Expr)
  EIsNull(Expr, Bool) // Bool = negated, i.e. `IS NOT NULL`
  EFunc(String, Array[Expr])
  EList(Array[Expr])
  EIndex(Expr, Expr)
  ESlice(Expr, Expr?, Expr?)
  EHasLabel(Expr, Array[String])
  EListComp(String, Expr, Expr?, Expr)
  EMapProj(Expr, Array[(String, Expr?)])
}

///|
pub enum Dir {
  Out
  In
  Both
}

///|
pub struct NodePat {
  variable : String
  labels : Array[String]
  props : Array[(String, Expr)]
}

///|
pub struct RelPat {
  variable : String
  types : Array[String]
  props : Array[(String, Expr)]
  dir : Dir
  min_hops : Int32
  max_hops : Int32 // -1 means unbounded
}

///|
pub struct Hop {
  rel : RelPat
  node : NodePat
}

///|
pub struct PathPat {
  variable : String
  shortest : Bool
  start : NodePat
  hops : Array[Hop]
}

///|
pub struct ReturnItem {
  expr : Expr
  col : String
}

///|
pub struct OrderItem {
  expr : Expr
  descending : Bool
}

///|
pub struct WithClause {
  items : Array[ReturnItem]
  distinct : Bool
  where_ : Expr?
}

///|
pub struct Query {
  patterns : Array[PathPat]
  with_ : WithClause?
  post : Array[PathPat]
  post_where : Expr?
  write : WriteClause?
  has_return : Bool
  where_ : Expr?
  items : Array[ReturnItem]
  distinct : Bool
  order : Array[OrderItem]
  skip : Int32?
  limit : Int32?
}

///|
/// Render an expression back to Cypher-ish source; used for default column names.
pub fn expr_text(expr : Expr) -> String {
  match expr {
    ELit(v) => v.to_literal()
    EVar(name) => name
    EProp(base, key) => expr_text(base) + "." + key
    EBin(op, l, r) => expr_text(l) + " " + op + " " + expr_text(r)
    ENot(e) => "NOT " + expr_text(e)
    EIsNull(e, negated) =>
      expr_text(e) + (if negated { " IS NOT NULL" } else { " IS NULL" })
    EFunc(name, args) => {
      let buf = StringBuilder()
      buf.write_string(name)
      buf.write_string("(")
      let mut first = true
      for arg in args {
        if !first {
          buf.write_string(", ")
        }
        first = false
        buf.write_string(expr_text(arg))
      }
      buf.write_string(")")
      buf.to_string()
    }
    EList(items) => {
      let buf = StringBuilder()
      buf.write_string("[")
      let mut first = true
      for item in items {
        if !first {
          buf.write_string(", ")
        }
        first = false
        buf.write_string(expr_text(item))
      }
      buf.write_string("]")
      buf.to_string()
    }
    EIndex(base, index) => expr_text(base) + "[" + expr_text(index) + "]"
    ESlice(base, lo, hi) => {
      let low = match lo {
        Some(e) => expr_text(e)
        None => ""
      }
      let high = match hi {
        Some(e) => expr_text(e)
        None => ""
      }
      expr_text(base) + "[" + low + ".." + high + "]"
    }
    EHasLabel(base, labels) => {
      let buf = StringBuilder()
      buf.write_string(expr_text(base))
      for label in labels {
        buf.write_string(":")
        buf.write_string(label)
      }
      buf.to_string()
    }
    EListComp(variable, source, predicate, projection) => {
      let pred = match predicate {
        Some(e) => " WHERE " + expr_text(e)
        None => ""
      }
      "[" + variable + " IN " + expr_text(source) + pred + " | " + expr_text(projection) + "]"
    }
    EMapProj(base, entries) => {
      let parts : Array[String] = []
      for (key, value) in entries {
        match value {
          Some(e) => parts.push(key + ": " + expr_text(e))
          None => parts.push("." + key)
        }
      }
      expr_text(base) + " {" + join_text(parts) + "}"
    }
  }
}

///|
/// A single `SET target.key = expr` assignment.
pub struct SetItem {
  target : String
  key : String
  value : Expr
}

///|
/// The write clause of a query. MoonGraph keeps at most one write clause per
/// query, which covers the CREATE/MERGE/SET/DELETE forms used by the test suite.
pub enum WriteClause {
  WCreate(Array[PathPat])
  WMerge(Array[PathPat], Array[SetItem], Array[SetItem])
  WSet(Array[SetItem])
  WDelete(Array[String])
}

///|
fn join_text(parts : Array[String]) -> String {
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