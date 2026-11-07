// Recursive-descent parser for the supported Cypher subset.
//
// Grammar (informal):
//   query   := MATCH pattern (',' pattern)* [WHERE expr] RETURN [DISTINCT] item
//              (',' item)* [ORDER BY order (',' order)*] [SKIP n] [LIMIT n] [';']
//   pattern := node (rel node)*
//   node    := '(' [var] (':' label)* ['{' props '}'] ')'
//   rel     := ('-' | '<-') ['[' [var] (':' type ('|' type)*) ['*' range] ']'] ('-' | '->')
//   item    := expr ['AS' var]
//   order   := expr ['ASC' | 'DESC']

///|
pub suberror ParseError {
  UnexpectedToken(String, Int32)
  UnexpectedEnd
  BadRange(Int32)
}

///|
pub struct Parser {
  tokens : Array[Token]
  mut pos : Int32
}

///|
/// Parse a Cypher query. Lexer failures are reported as parse errors so that
/// callers only have to deal with a single error type.
pub fn parse_query(source : String) -> Query raise ParseError {
  let tokens = tokenize(source) catch {
    LexError::UnexpectedChar(c, pos) =>
      raise ParseError::UnexpectedToken("unexpected character \{c}", pos)
    LexError::UnterminatedString(pos) =>
      raise ParseError::UnexpectedToken("unterminated string", pos)
    LexError::BadNumber(_, pos) =>
      raise ParseError::UnexpectedToken("bad number", pos)
  }
  let parser : Parser = { tokens, pos: 0, }
  parser.query()
}

///|
fn Parser::peek(self : Parser) -> Token {
  self.tokens[self.pos]
}

///|
fn Parser::at(self : Parser, kind : TokKind) -> Bool {
  self.peek().kind == kind
}

///|
fn Parser::advance(self : Parser) -> Unit {
  if self.peek().kind != Eof {
    self.pos = self.pos + 1
  }
}

///|
/// Consume the current token and return it.
fn Parser::take(self : Parser) -> Token {
  let token = self.tokens[self.pos]
  self.advance()
  token
}

///|
fn Parser::expect(
  self : Parser,
  kind : TokKind,
  what : String,
) -> Unit raise ParseError {
  let token = self.peek()
  if token.kind == kind {
    self.advance()
  } else {
    raise ParseError::UnexpectedToken(what, token.pos)
  }
}

///|
/// Expect a token and return its text (used for identifiers and labels).
fn Parser::expect_text(
  self : Parser,
  kind : TokKind,
  what : String,
) -> String raise ParseError {
  self.expect(kind, what)
  self.tokens[self.pos - 1].text
}

///|
fn Parser::query(self : Parser) -> Query raise ParseError {
  let patterns : Array[PathPat] = []
  let mut where_ : Expr? = None
  // A query may start with MATCH or with a write clause (`CREATE (n)`).
  while self.at(KwMatch) {
    self.advance()
    patterns.push(self.pattern())
    while self.at(Comma) {
      self.advance()
      patterns.push(self.pattern())
    }
    if self.at(KwWhere) {
      self.advance()
      let condition = self.expr()
      where_ = match where_ {
        Some(previous) => Some(EBin("AND", previous, condition))
        None => Some(condition)
      }
    }
  }
  let mut with_ : WithClause? = None
  let post : Array[PathPat] = []
  let mut post_where : Expr? = None
  if self.at(KwWith) {
    self.advance()
    let with_distinct = if self.at(KwDistinct) {
      self.advance()
      true
    } else {
      false
    }
    let with_items : Array[ReturnItem] = []
    with_items.push(self.return_item())
    while self.at(Comma) {
      self.advance()
      with_items.push(self.return_item())
    }
    let with_where = if self.at(KwWhere) {
      self.advance()
      Some(self.expr())
    } else {
      None
    }
    with_ = Some({
      items: with_items,
      distinct: with_distinct,
      where_: with_where,
    })
    if self.at(KwMatch) {
      self.advance()
      post.push(self.pattern())
      while self.at(Comma) {
        self.advance()
        post.push(self.pattern())
      }
      if self.at(KwWhere) {
        self.advance()
        post_where = Some(self.expr())
      }
    }
  }
  let unwinds : Array[(Expr, String)] = []
  while self.at(KwUnwind) {
    self.advance()
    let source = self.expr()
    self.expect(KwAs, "AS")
    let variable = self.expect_text(Ident, "variable")
    unwinds.push((source, variable))
  }
  let writes : Array[WriteClause] = []
  while self.at(KwCreate) ||
        self.at(KwMerge) ||
        self.at(KwSet) ||
        self.at(KwDelete) ||
        self.at(KwDetach) {
    match self.write_clause() {
      Some(clause) => writes.push(clause)
      None => break
    }
  }
  let has_return = self.at(KwReturn)
  if !has_return && writes.length() == 0 {
    raise ParseError::UnexpectedToken("RETURN", self.peek().pos)
  }
  let mut distinct = false
  let items : Array[ReturnItem] = []
  if has_return {
    self.advance()
    distinct = if self.at(KwDistinct) {
      self.advance()
      true
    } else {
      false
    }
    items.push(self.return_item())
    while self.at(Comma) {
      self.advance()
      items.push(self.return_item())
    }
  }
  let order : Array[OrderItem] = []
  if self.at(KwOrder) {
    self.advance()
    self.expect(KwBy, "BY")
    order.push(self.order_item())
    while self.at(Comma) {
      self.advance()
      order.push(self.order_item())
    }
  }
  let skip = if self.at(KwSkip) {
    self.advance()
    Some(self.int_literal())
  } else {
    None
  }
  let limit = if self.at(KwLimit) {
    self.advance()
    Some(self.int_literal())
  } else {
    None
  }
  if self.at(Semicolon) {
    self.advance()
  }
  if !self.at(Eof) {
    raise ParseError::UnexpectedToken("end of query", self.peek().pos)
  }
  {
    patterns,
    where_,
    with_,
    post,
    post_where,
    writes,
    unwinds,
    has_return,
    items,
    distinct,
    order,
    skip,
    limit,
  }
}

///|
/// Parse an optional write clause: CREATE / MERGE / SET / DELETE.
fn Parser::write_clause(self : Parser) -> WriteClause? raise ParseError {
  if self.at(KwCreate) || self.at(KwMerge) {
    let is_create = self.at(KwCreate)
    self.advance()
    let patterns : Array[PathPat] = []
    patterns.push(self.pattern())
    while self.at(Comma) {
      self.advance()
      patterns.push(self.pattern())
    }
    if is_create {
      return Some(WCreate(patterns))
    }
    let on_create : Array[SetItem] = []
    let on_match : Array[SetItem] = []
    while self.peek().kind == Ident && self.peek().text.to_upper() == "ON" {
      self.advance()
      if self.at(KwCreate) {
        self.advance()
        self.expect(KwSet, "SET")
        on_create.push(self.set_item())
        while self.at(Comma) {
          self.advance()
          on_create.push(self.set_item())
        }
      } else if self.at(KwMatch) {
        self.advance()
        self.expect(KwSet, "SET")
        on_match.push(self.set_item())
        while self.at(Comma) {
          self.advance()
          on_match.push(self.set_item())
        }
      } else {
        raise ParseError::UnexpectedToken("CREATE or MATCH", self.peek().pos)
      }
    }
    return Some(WMerge(patterns, on_create, on_match))
  }
  if self.at(KwSet) {
    let items = self.set_clause()
    return Some(WSet(items))
  }
  if self.at(KwDetach) || self.at(KwDelete) {
    if self.at(KwDetach) {
      self.advance()
    }
    self.expect(KwDelete, "DELETE")
    let targets : Array[String] = []
    targets.push(self.expect_text(Ident, "variable"))
    while self.at(Comma) {
      self.advance()
      targets.push(self.expect_text(Ident, "variable"))
    }
    return Some(WDelete(targets))
  }
  None
}

///|
fn Parser::set_item(self : Parser) -> SetItem raise ParseError {
  let target = self.set_target()
  self.expect(Dot, ".")
  let key = self.expect_text(Ident, "property name")
  self.expect(Eq, "=")
  { target, key, value: self.expr(), }
}

///|
/// `n` or `(n)` as the target of an assignment.
fn Parser::set_target(self : Parser) -> String raise ParseError {
  if self.at(LParen) {
    self.advance()
    let name = self.expect_text(Ident, "variable")
    self.expect(RParen, ")")
    name
  } else {
    self.expect_text(Ident, "variable")
  }
}

///|
/// Parse a SET clause into individual assignments. `SET n = {a: 1, b: 2}` is
/// expanded into one assignment per key, and `+=` behaves the same way for the
/// keys it mentions.
fn Parser::set_clause(self : Parser) -> Array[SetItem] raise ParseError {
  self.expect(KwSet, "SET")
  let items : Array[SetItem] = []
  let mut more = true
  while more {
    let target = self.set_target()
    if self.at(Dot) {
      self.advance()
      let key = self.expect_text(Ident, "property name")
      self.expect(Eq, "=")
      items.push({ target, key, value: self.expr(), })
    } else if self.at(Plus) {
      self.advance()
      self.expect(Eq, "=")
      items.append(self.map_assignments(target))
    } else if self.at(Eq) {
      self.advance()
      items.append(self.map_assignments(target))
    } else {
      raise ParseError::UnexpectedToken("'.', '=' or '+='", self.peek().pos)
    }
    if self.at(Comma) {
      self.advance()
    } else {
      more = false
    }
  }
  items
}

///|
fn Parser::map_assignments(
  self : Parser,
  target : String,
) -> Array[SetItem] raise ParseError {
  if self.at(LBrace) {
    let entries = self.map_literal()
    let items : Array[SetItem] = []
    for (key, value) in entries {
      items.push({ target, key, value, })
    }
    items
  } else {
    // `SET n = null` clears every property; approximated by clearing nothing.
    ignore(self.expr())
    []
  }
}

///|
fn Parser::int_literal(self : Parser) -> Int32 raise ParseError {
  let token = self.peek()
  match token.kind {
    Int => {
      self.advance()
      @string.parse_int(token.text) catch {
        _ => raise ParseError::UnexpectedToken("integer", token.pos)
      }
    }
    _ => raise ParseError::UnexpectedToken("integer", token.pos)
  }
}

///|
fn Parser::return_item(self : Parser) -> ReturnItem raise ParseError {
  let expr = self.expr()
  let col = if self.at(KwAs) {
    self.advance()
    self.expect_text(Ident, "alias")
  } else {
    expr_text(expr)
  }
  { expr, col, }
}

///|
fn Parser::order_item(self : Parser) -> OrderItem raise ParseError {
  let expr = self.expr()
  let descending = if self.at(KwDesc) {
    self.advance()
    true
  } else if self.at(KwAsc) {
    self.advance()
    false
  } else {
    false
  }
  { expr, descending, }
}

///|
fn Parser::pattern(self : Parser) -> PathPat raise ParseError {
  // Optional `p =` prefix, and the `shortestPath(...)` wrapper.
  let mut variable = ""
  let mut shortest = false
  if self.at(Ident) && self.tokens[self.pos + 1].kind == Eq {
    variable = self.take().text
    self.advance()
  }
  if self.at(Ident) && self.peek().text.to_upper() == "SHORTESTPATH" {
    self.advance()
    self.expect(LParen, "(")
    shortest = true
    let start = self.node_pattern()
    let hops : Array[Hop] = []
    while self.at(Minus) || self.at(ArrowLeft) {
      let (rel, node) = self.rel_and_node()
      hops.push({ rel, node, })
    }
    self.expect(RParen, ")")
    return { variable, shortest, start, hops, }
  }
  let start = self.node_pattern()
  let hops : Array[Hop] = []
  while self.at(Minus) || self.at(ArrowLeft) {
    let (rel, node) = self.rel_and_node()
    hops.push({ rel, node, })
  }
  { variable, shortest, start, hops, }
}

///|
fn Parser::node_pattern(self : Parser) -> NodePat raise ParseError {
  self.expect(LParen, "(")
  let variable = if self.at(Ident) { self.take().text } else { "" }
  let labels : Array[String] = []
  while self.at(Colon) {
    self.advance()
    labels.push(self.expect_text(Ident, "label"))
  }
  let props = if self.at(LBrace) { self.map_literal() } else { [] }
  self.expect(RParen, ")")
  { variable, labels, props, }
}

///|
fn Parser::map_literal(self : Parser) -> Array[(String, Expr)] raise ParseError {
  self.expect(LBrace, "{")
  let entries : Array[(String, Expr)] = []
  if self.at(RBrace) {
    self.advance()
    return entries
  }
  while true {
    let key = match self.peek().kind {
      Ident => self.take().text
      Str => self.take().text
      _ => raise ParseError::UnexpectedToken("property key", self.peek().pos)
    }
    self.expect(Colon, ":")
    entries.push((key, self.expr()))
    if self.at(Comma) {
      self.advance()
      continue
    }
    break
  }
  self.expect(RBrace, "}")
  entries
}

///|
fn Parser::rel_and_node(self : Parser) -> (RelPat, NodePat) raise ParseError {
  let leading = self.take() // Minus or ArrowLeft
  let mut variable = ""
  let types : Array[String] = []
  let mut rel_props : Array[(String, Expr)] = []
  let mut min_hops = 1
  let mut max_hops = 1
  if self.at(LBracket) {
    self.advance()
    if self.at(Ident) && !self.at(KwNot) {
      variable = self.take().text
    }
    if self.at(Colon) {
      self.advance()
      types.push(self.expect_text(Ident, "relationship type"))
      while self.at(Pipe) {
        self.advance()
        if self.at(Colon) {
          self.advance()
        }
        types.push(self.expect_text(Ident, "relationship type"))
      }
    }
    if self.at(LBrace) {
      rel_props = self.map_literal()
    }
    if self.at(Star) {
      self.advance()
      let (lo, hi) = self.varlen_range()
      min_hops = lo
      max_hops = hi
    }
    self.expect(RBracket, "]")
  }
  let dir = match leading.kind {
    ArrowLeft =>
      // `<--` and `<-->` differ only in the trailing arrow; `<-->` lexes as
      // ArrowLeft followed by ArrowRight.
      if self.at(ArrowRight) {
        self.advance()
        Both
      } else {
        self.expect(Minus, "-")
        if self.at(Gt) {
          self.advance()
          Both
        } else {
          In
        }
      }
    _ =>
      match self.peek().kind {
        ArrowRight => {
          self.advance()
          Out
        }
        Minus => {
          self.advance()
          Both
        }
        _ => raise ParseError::UnexpectedToken("'-' or '->'", self.peek().pos)
      }
  }
  let node = self.node_pattern()
  ({ variable, types, props: rel_props, dir, min_hops, max_hops, }, node)
}

///|
/// Parse the `*`, `*n`, `*a..b`, `*a..`, `*..b` range after a star.
fn Parser::varlen_range(self : Parser) -> (Int32, Int32) raise ParseError {
  let mut lo = 1
  let mut hi = -1
  if self.at(Int) {
    lo = self.int_literal()
    hi = lo
  }
  if self.at(Dot) && self.peek().text == ".." {
    self.advance()
    if self.at(Int) {
      hi = self.int_literal()
    } else {
      hi = -1
    }
  }
  if lo < 0 || (hi != -1 && hi < lo) {
    raise ParseError::BadRange(self.peek().pos)
  }
  (lo, hi)
}

///|
fn Parser::expr(self : Parser) -> Expr raise ParseError {
  self.or_expr()
}

///|
fn Parser::or_expr(self : Parser) -> Expr raise ParseError {
  let mut left = self.and_expr()
  while self.at(KwOr) {
    self.advance()
    let right = self.and_expr()
    left = EBin("OR", left, right)
  }
  left
}

///|
fn Parser::and_expr(self : Parser) -> Expr raise ParseError {
  let mut left = self.not_expr()
  while self.at(KwAnd) {
    self.advance()
    let right = self.not_expr()
    left = EBin("AND", left, right)
  }
  left
}

///|
fn Parser::not_expr(self : Parser) -> Expr raise ParseError {
  if self.at(KwNot) {
    self.advance()
    ENot(self.not_expr())
  } else {
    self.comparison()
  }
}

///|
fn Parser::comparison(self : Parser) -> Expr raise ParseError {
  let left = self.additive()
  // `STARTS WITH` / `ENDS WITH` are two keywords, consume both.
  if self.at(KwStartsWith) || self.at(KwEndsWith) {
    let op = if self.at(KwStartsWith) { "STARTS WITH" } else { "ENDS WITH" }
    self.advance()
    let token = self.peek()
    if (token.kind == Ident || token.kind == KwWith) &&
      token.text.to_upper() == "WITH" {
      self.advance()
    } else {
      raise ParseError::UnexpectedToken("WITH", token.pos)
    }
    return EBin(op, left, self.additive())
  }
  let op = match self.peek().kind {
    Eq => "="
    Neq => "<>"
    Lt => "<"
    Le => "<="
    Gt => ">"
    Ge => ">="
    KwIn => "IN"
    KwContains => "CONTAINS"
    KwIs => {
      self.advance()
      let negated = if self.at(KwNot) {
        self.advance()
        true
      } else {
        false
      }
      self.expect(KwNull, "NULL")
      return EIsNull(left, negated)
    }
    _ => return left
  }
  self.advance()
  EBin(op, left, self.additive())
}

///|
fn Parser::additive(self : Parser) -> Expr raise ParseError {
  let mut left = self.multiplicative()
  while self.at(Plus) || self.at(Minus) {
    let op = if self.at(Plus) { "+" } else { "-" }
    self.advance()
    let right = self.multiplicative()
    left = EBin(op, left, right)
  }
  left
}

///|
fn Parser::multiplicative(self : Parser) -> Expr raise ParseError {
  let mut left = self.unary()
  while self.at(Star) || self.at(Slash) || self.at(Percent) {
    let op = match self.peek().kind {
      Star => "*"
      Slash => "/"
      _ => "%"
    }
    self.advance()
    let right = self.unary()
    left = EBin(op, left, right)
  }
  left
}

///|
fn Parser::unary(self : Parser) -> Expr raise ParseError {
  if self.at(Minus) {
    self.advance()
    return EBin("-", ELit(@mg.VInt(0L)), self.unary())
  }
  self.postfix()
}

///|
fn Parser::postfix(self : Parser) -> Expr raise ParseError {
  let mut expr = self.primary()
  while true {
    if self.at(Dot) && self.peek().text == "." {
      self.advance()
      let key = self.expect_text(Ident, "property name")
      expr = EProp(expr, key)
      continue
    }
    if self.at(LBracket) {
      self.advance()
      // Slice forms: [..hi], [lo..hi], [lo..]
      if self.at(Dot) && self.peek().text == ".." {
        self.advance()
        let hi = self.expr()
        self.expect(RBracket, "]")
        expr = ESlice(expr, None, Some(hi))
        continue
      }
      let lo = self.expr()
      if self.at(Dot) && self.peek().text == ".." {
        self.advance()
        let hi = if self.at(RBracket) { None } else { Some(self.expr()) }
        self.expect(RBracket, "]")
        expr = ESlice(expr, Some(lo), hi)
        continue
      }
      self.expect(RBracket, "]")
      expr = EIndex(expr, lo)
      continue
    }
    if self.at(Colon) {
      self.advance()
      let labels : Array[String] = []
      labels.push(self.expect_text(Ident, "label"))
      while self.at(Colon) {
        self.advance()
        labels.push(self.expect_text(Ident, "label"))
      }
      expr = EHasLabel(expr, labels)
      continue
    }
    if self.at(LBrace) {
      let entries = self.map_projection()
      expr = EMapProj(expr, entries)
      continue
    }
    break
  }
  expr
}

///|
/// `{key: expr, ...}` map literal.
fn Parser::map_entries(self : Parser) -> Array[(String, Expr)] raise ParseError {
  self.expect(LBrace, "{")
  let entries : Array[(String, Expr)] = []
  while !self.at(RBrace) {
    let key = match self.peek().kind {
      Ident => self.take().text
      Str => self.take().text
      _ => raise ParseError::UnexpectedToken("map key", self.peek().pos)
    }
    self.expect(Colon, ":")
    entries.push((key, self.expr()))
    if self.at(Comma) {
      self.advance()
    } else {
      break
    }
  }
  self.expect(RBrace, "}")
  entries
}

///|
/// `n {.name, .*, alias: expr}` projection entries.
fn Parser::map_projection(
  self : Parser,
) -> Array[(String, Expr?)] raise ParseError {
  self.expect(LBrace, "{")
  let entries : Array[(String, Expr?)] = []
  while !self.at(RBrace) {
    if self.at(Dot) {
      self.advance()
      if self.at(Star) {
        self.advance()
        entries.push(("*", None))
      } else {
        let key = self.expect_text(Ident, "property name")
        entries.push((key, None))
      }
    } else {
      let key = self.expect_text(Ident, "property name")
      self.expect(Colon, ":")
      entries.push((key, Some(self.expr())))
    }
    if self.at(Comma) {
      self.advance()
    } else {
      break
    }
  }
  self.expect(RBrace, "}")
  entries
}

///|
fn Parser::primary(self : Parser) -> Expr raise ParseError {
  let token = self.peek()
  match token.kind {
    LParen => {
      self.advance()
      let inner = self.expr()
      self.expect(RParen, ")")
      inner
    }
    Str => {
      self.advance()
      ELit(@mg.VStr(token.text))
    }
    Int => {
      self.advance()
      let value = @string.parse_int64(token.text) catch {
        _ => raise ParseError::UnexpectedToken("integer", token.pos)
      }
      ELit(@mg.VInt(value))
    }
    Float => {
      self.advance()
      let value = @string.parse_double(token.text) catch {
        _ => raise ParseError::UnexpectedToken("number", token.pos)
      }
      ELit(@mg.VDouble(value))
    }
    KwTrue => {
      self.advance()
      ELit(@mg.VBool(true))
    }
    KwFalse => {
      self.advance()
      ELit(@mg.VBool(false))
    }
    KwNull => {
      self.advance()
      ELit(@mg.VNull)
    }
    Star => {
      // `count(*)`: the star is a placeholder argument.
      ignore(self.advance())
      EVar("*")
    }
    LBrace => {
      let entries = self.map_entries()
      EMapLit(entries)
    }
    LBracket => {
      self.advance()
      // List comprehension: [x IN list WHERE pred | projection]
      if self.at(Ident) && self.tokens[self.pos + 1].kind == KwIn {
        let variable = self.take().text
        self.advance()
        let source = self.expr()
        let predicate = if self.at(KwWhere) {
          self.advance()
          Some(self.expr())
        } else {
          None
        }
        let projection = if self.at(Pipe) {
          self.advance()
          self.expr()
        } else {
          EVar(variable)
        }
        self.expect(RBracket, "]")
        return EListComp(variable, source, predicate, projection)
      }
      let items : Array[Expr] = []
      if !self.at(RBracket) {
        items.push(self.expr())
        while self.at(Comma) {
          self.advance()
          items.push(self.expr())
        }
      }
      self.expect(RBracket, "]")
      EList(items)
    }
    Ident => {
      self.advance()
      if self.at(LParen) {
        self.advance()
        let args : Array[Expr] = []
        if !self.at(RParen) {
          args.push(self.expr())
          while self.at(Comma) {
            self.advance()
            args.push(self.expr())
          }
        }
        self.expect(RParen, ")")
        EFunc(token.text, args)
      } else {
        EVar(token.text)
      }
    }
    _ => raise ParseError::UnexpectedToken("expression", token.pos)
  }
}
