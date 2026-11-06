// A small, dependency-free JSON reader/writer.
//
// MoonGraph uses JSON as its interchange format for importing graphs
// (JSON Lines) and for human readable snapshots. The reader is a strict
// recursive descent parser with a configurable nesting limit, so that a
// malformed import cannot blow the stack.

///|
pub suberror JsonError {
  JsonUnexpected(String, Int32)
  JsonEof
  JsonDepth
}

///|
pub(all) enum Json {
  JNull
  JBool(Bool)
  JInt(Int64)
  JDouble(Double)
  JStr(String)
  JList(Array[Json])
  JObj(Map[String, Json])
}

///|
pub struct JsonParser {
  chars : Array[Char]
  mut pos : Int32
  depth_limit : Int32
}

///|
pub fn Json::parse(text : StringView) -> Json raise JsonError {
  let parser = {
    chars: Array::from_iter(text.iter()),
    pos: 0,
    depth_limit: 128,
  }
  parser.skip_ws()
  let value = parser.parse_value(0)
  parser.skip_ws()
  if parser.pos < parser.chars.length() {
    raise JsonError::JsonUnexpected("trailing characters", parser.pos)
  }
  value
}

///|
fn JsonParser::skip_ws(self : JsonParser) -> Unit {
  while self.pos < self.chars.length() {
    match self.chars[self.pos] {
      ' ' | '\t' | '\n' | '\r' => self.pos = self.pos + 1
      _ => break
    }
  }
}

///|
fn JsonParser::peek(self : JsonParser) -> Char raise JsonError {
  if self.pos >= self.chars.length() {
    raise JsonError::JsonEof
  }
  self.chars[self.pos]
}

///|
fn JsonParser::parse_value(
  self : JsonParser,
  depth : Int32,
) -> Json raise JsonError {
  if depth > self.depth_limit {
    raise JsonError::JsonDepth
  }
  match self.peek() {
    '{' => self.parse_object(depth)
    '[' => self.parse_array(depth)
    '"' => JStr(self.parse_string())
    't' => {
      self.expect_literal("true")
      JBool(true)
    }
    'f' => {
      self.expect_literal("false")
      JBool(false)
    }
    'n' => {
      self.expect_literal("null")
      JNull
    }
    _ => self.parse_number()
  }
}

///|
fn JsonParser::parse_object(
  self : JsonParser,
  depth : Int32,
) -> Json raise JsonError {
  self.pos = self.pos + 1
  let map : Map[String, Json] = Map([])
  self.skip_ws()
  if self.peek() == '}' {
    self.pos = self.pos + 1
    return JObj(map)
  }
  while true {
    self.skip_ws()
    let key = self.parse_string()
    self.skip_ws()
    if self.peek() != ':' {
      raise JsonError::JsonUnexpected("expected ':'", self.pos)
    }
    self.pos = self.pos + 1
    self.skip_ws()
    let value = self.parse_value(depth + 1)
    map[key] = value
    self.skip_ws()
    match self.peek() {
      ',' => self.pos = self.pos + 1
      '}' => {
        self.pos = self.pos + 1
        break
      }
      _ => raise JsonError::JsonUnexpected("expected ',' or '}'", self.pos)
    }
  }
  JObj(map)
}

///|
fn JsonParser::parse_array(
  self : JsonParser,
  depth : Int32,
) -> Json raise JsonError {
  self.pos = self.pos + 1
  let items : Array[Json] = []
  self.skip_ws()
  if self.peek() == ']' {
    self.pos = self.pos + 1
    return JList(items)
  }
  while true {
    self.skip_ws()
    items.push(self.parse_value(depth + 1))
    self.skip_ws()
    match self.peek() {
      ',' => self.pos = self.pos + 1
      ']' => {
        self.pos = self.pos + 1
        break
      }
      _ => raise JsonError::JsonUnexpected("expected ',' or ']'", self.pos)
    }
  }
  JList(items)
}

///|
fn JsonParser::parse_string(self : JsonParser) -> String raise JsonError {
  if self.peek() != '"' {
    raise JsonError::JsonUnexpected("expected string", self.pos)
  }
  self.pos = self.pos + 1
  let buf = StringBuilder()
  while true {
    if self.pos >= self.chars.length() {
      raise JsonError::JsonEof
    }
    let c = self.chars[self.pos]
    self.pos = self.pos + 1
    match c {
      '"' => break
      '\\' => {
        let esc = self.next_char()
        match esc {
          '"' => buf.write_char('"')
          '\\' => buf.write_char('\\')
          '/' => buf.write_char('/')
          'b' => buf.write_char('\u{8}')
          'f' => buf.write_char('\u{c}')
          'n' => buf.write_char('\n')
          'r' => buf.write_char('\r')
          't' => buf.write_char('\t')
          'u' => {
            let code = self.parse_hex4()
            buf.write_char(code)
          }
          _ => raise JsonError::JsonUnexpected("bad escape", self.pos)
        }
      }
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn JsonParser::next_char(self : JsonParser) -> Char raise JsonError {
  if self.pos >= self.chars.length() {
    raise JsonError::JsonEof
  }
  let c = self.chars[self.pos]
  self.pos = self.pos + 1
  c
}

///|
fn JsonParser::parse_hex4(self : JsonParser) -> Char raise JsonError {
  let mut value = 0
  let mut i = 0
  while i < 4 {
    let c = self.next_char()
    let digit = match c {
      '0'..<='9' => c.to_int() - '0'.to_int()
      'a'..<='f' => c.to_int() - 'a'.to_int() + 10
      'A'..<='F' => c.to_int() - 'A'.to_int() + 10
      _ => raise JsonError::JsonUnexpected("bad unicode escape", self.pos)
    }
    value = value * 16 + digit
    i = i + 1
  }
  Int32::unsafe_to_char(value)
}

///|
fn JsonParser::parse_number(self : JsonParser) -> Json raise JsonError {
  let start = self.pos
  let mut is_float = false
  while self.pos < self.chars.length() {
    match self.chars[self.pos] {
      '-' | '+' | '.' | 'e' | 'E' => {
        if self.chars[self.pos] == '.' ||
          self.chars[self.pos] == 'e' ||
          self.chars[self.pos] == 'E' {
          is_float = true
        }
        self.pos = self.pos + 1
      }
      c => if c >= '0' && c <= '9' { self.pos = self.pos + 1 } else { break }
    }
  }
  if self.pos == start {
    raise JsonError::JsonUnexpected("expected number", self.pos)
  }
  let raw = String::from_array(self.chars[start:self.pos])
  if is_float {
    JDouble(@string.parse_double(raw) catch { _ => 0.0 })
  } else {
    JInt(@string.parse_int64(raw) catch { _ => 0L })
  }
}

///|
fn JsonParser::expect_literal(
  self : JsonParser,
  lit : String,
) -> Unit raise JsonError {
  let chars = Array::from_iter(lit.iter())
  for expected in chars {
    if self.next_char() != expected {
      raise JsonError::JsonUnexpected("expected literal \{lit}", self.pos)
    }
  }
}

///|
/// Four digit lowercase hex encoding of a code unit.
fn hex4(value : Int32) -> String {
  let digits = Array::from_iter("0123456789abcdef".iter())
  let buf = StringBuilder()
  let mut shift = 12
  while shift >= 0 {
    let digit = (value >> shift) & 0xF
    buf.write_char(digits[digit])
    shift = shift - 4
  }
  buf.to_string()
}

///|
/// Escape a string so it can be embedded in a JSON document.
pub fn escape_json_string(s : String) -> String {
  let buf = StringBuilder()
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      c =>
        if c.to_int() < 32 {
          buf.write_string("\\u")
          buf.write_string(hex4(c.to_int()))
        } else {
          buf.write_char(c)
        }
    }
  }
  buf.to_string()
}

///|
pub fn Json::to_string(self : Json) -> String {
  match self {
    JNull => "null"
    JBool(b) => "\{b}"
    JInt(i) => "\{i}"
    JDouble(d) => "\{d}"
    JStr(s) => "\"" + escape_json_string(s) + "\""
    JList(items) => {
      let buf = StringBuilder()
      buf.write_string("[")
      let mut first = true
      for item in items {
        if !first {
          buf.write_string(",")
        }
        first = false
        buf.write_string(item.to_string())
      }
      buf.write_string("]")
      buf.to_string()
    }
    JObj(map) => {
      let buf = StringBuilder()
      buf.write_string("{")
      let mut first = true
      for key in map.keys() {
        if !first {
          buf.write_string(",")
        }
        first = false
        buf.write_string("\"" + escape_json_string(key) + "\":")
        buf.write_string(map[key].to_string())
      }
      buf.write_string("}")
      buf.to_string()
    }
  }
}

///|
/// Convert a JSON value into a property value.
pub fn json_to_value(json : Json) -> Value {
  match json {
    JNull => VNull
    JBool(b) => VBool(b)
    JInt(i) => VInt(i)
    JDouble(d) => VDouble(d)
    JStr(s) => VStr(s)
    JList(items) => VList(items.map(json_to_value))
    JObj(_) => VStr(json.to_string())
  }
}

///|
/// Convert a property value into a JSON value.
pub fn value_to_json(value : Value) -> Json {
  match value {
    VNull => JNull
    VBool(b) => JBool(b)
    VInt(i) => JInt(i)
    VDouble(d) => JDouble(d)
    VStr(s) => JStr(s)
    VList(items) => JList(items.map(value_to_json))
  }
}
