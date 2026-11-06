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
pub struct Query {
  patterns : Array[PathPat]
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
  WMerge(Array[PathPat])
  WSet(Array[SetItem])
  WDelete(Array[String])
}
