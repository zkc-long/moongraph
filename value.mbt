// The dynamically typed value model used for node and edge properties.

///|
/// A property value attached to a node or an edge.
///
/// Cypher types are mapped onto this closed set: `null`, booleans, integers
/// (`Int64`), floating point numbers, strings and lists of values.
pub(all) enum Value {
  VNull
  VBool(Bool)
  VInt(Int64)
  VDouble(Double)
  VStr(String)
  VList(Array[Value])
}

///|
pub fn Value::null() -> Value {
  VNull
}

///|
pub fn Value::of_int(i : Int64) -> Value {
  VInt(i)
}

///|
pub fn Value::of_str(s : String) -> Value {
  VStr(s)
}

///|
pub fn Value::is_null(self : Value) -> Bool {
  match self {
    VNull => true
    _ => false
  }
}

///|
pub fn Value::is_number(self : Value) -> Bool {
  match self {
    VInt(_) | VDouble(_) => true
    _ => false
  }
}

///|
/// Numeric view of a value, used by arithmetic and ordering.
pub fn Value::as_double(self : Value) -> Double {
  match self {
    VInt(i) => i.to_double()
    VDouble(d) => d
    _ => 0.0
  }
}

///|
pub fn Value::as_int64(self : Value) -> Int64 {
  match self {
    VInt(i) => i
    VDouble(d) => d.to_int64()
    _ => 0L
  }
}

///|
pub fn Value::as_string(self : Value) -> String {
  match self {
    VStr(s) => s
    VInt(i) => "\{i}"
    VDouble(d) => "\{d}"
    VBool(b) => "\{b}"
    VNull => "null"
    VList(_) => "[list]"
  }
}

///|
/// Human facing rendering used by the CLI table output.
/// Strings are printed bare, everything else in its literal form.
pub fn Value::to_display(self : Value) -> String {
  match self {
    VNull => "null"
    VBool(b) => "\{b}"
    VInt(i) => "\{i}"
    VDouble(d) => format_double(d)
    VStr(s) => s
    VList(items) => {
      let buf = StringBuilder()
      buf.write_string("[")
      let mut first = true
      for item in items {
        if !first {
          buf.write_string(", ")
        }
        first = false
        buf.write_string(item.to_display())
      }
      buf.write_string("]")
      buf.to_string()
    }
  }
}

///|
/// Round-trip friendly rendering: strings are quoted and escaped.
pub fn Value::to_literal(self : Value) -> String {
  match self {
    VStr(s) => "\"" + escape_json_string(s) + "\""
    _ => self.to_display()
  }
}

///|
/// Stable formatting for doubles: integral values keep a trailing `.0`.
fn format_double(d : Double) -> String {
  if d.is_nan() {
    "NaN"
  } else if d == 0.0 {
    "0.0"
  } else {
    "\{d}"
  }
}

///|
/// Total order over values, used by `ORDER BY`.
/// Numbers are compared numerically regardless of their concrete variant.
pub fn Value::compare(self : Value, other : Value) -> Int32 {
  if self.is_number() && other.is_number() {
    let a = self.as_double()
    let b = other.as_double()
    return if a < b {
      -1
    } else if a > b {
      1
    } else {
      0
    }
  }
  let ra = self.rank()
  let rb = other.rank()
  if ra != rb {
    return ra - rb
  }
  match (self, other) {
    (VNull, VNull) => 0
    (VBool(a), VBool(b)) =>
      if a == b {
        0
      } else if a {
        1
      } else {
        -1
      }
    (VStr(a), VStr(b)) => {
      if a == b {
        0
      } else if a < b {
        -1
      } else {
        1
      }
    }
    (VList(a), VList(b)) => {
      let n = if a.length() < b.length() { a.length() } else { b.length() }
      let mut i = 0
      let mut result = 0
      while i < n && result == 0 {
        result = a[i].compare(b[i])
        i = i + 1
      }
      if result != 0 {
        result
      } else {
        a.length() - b.length()
      }
    }
    _ => 0
  }
}

///|
/// Type ordering: null < bool < number < string < list.
fn Value::rank(self : Value) -> Int32 {
  match self {
    VNull => 0
    VBool(_) => 1
    VInt(_) => 2
    VDouble(_) => 2
    VStr(_) => 3
    VList(_) => 4
  }
}

///|
/// Structural equality; numbers compare numerically.
pub fn Value::equal_value(self : Value, other : Value) -> Bool {
  self.compare(other) == 0
}
