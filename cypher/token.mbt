// Cypher lexer: turns query text into a flat token stream.
//
// The lexer is intentionally hand written: Cypher's relationship arrows
// (`-[r:T*1..3]->`) and string escapes make a generated lexer more trouble than
// it is worth, and a hand written scanner can report the offending offset.

///|
#derive(Eq)
pub enum TokKind {
  Ident
  Str
  Int
  Float
  LParen
  RParen
  LBracket
  RBracket
  LBrace
  RBrace
  Colon
  Comma
  Dot
  Pipe
  Semicolon
  Percent
  Plus
  Minus
  Star
  Slash
  Eq
  Neq
  Lt
  Le
  Gt
  Ge
  ArrowRight
  ArrowLeft
  Eof
  KwMatch
  KwWhere
  KwReturn
  KwOrder
  KwBy
  KwSkip
  KwLimit
  KwAs
  KwDistinct
  KwAnd
  KwOr
  KwNot
  KwIn
  KwIs
  KwNull
  KwTrue
  KwFalse
  KwAsc
  KwDesc
  KwStartsWith
  KwEndsWith
  KwContains
  KwCreate
  KwMerge
  KwSet
  KwDelete
  KwDetach
  KwWith
}

///|
pub struct Token {
  kind : TokKind
  text : String
  pos : Int32
}

///|
pub suberror LexError {
  UnexpectedChar(Char, Int32)
  UnterminatedString(Int32)
  BadNumber(String, Int32)
}

///|
fn keyword_kind(word : String) -> TokKind {
  match word {
    "MATCH" => KwMatch
    "WHERE" => KwWhere
    "RETURN" => KwReturn
    "ORDER" => KwOrder
    "BY" => KwBy
    "SKIP" => KwSkip
    "LIMIT" => KwLimit
    "AS" => KwAs
    "DISTINCT" => KwDistinct
    "AND" => KwAnd
    "OR" => KwOr
    "NOT" => KwNot
    "IN" => KwIn
    "IS" => KwIs
    "NULL" => KwNull
    "TRUE" => KwTrue
    "FALSE" => KwFalse
    "ASC" => KwAsc
    "DESC" => KwDesc
    "STARTS" => KwStartsWith
    "ENDS" => KwEndsWith
    "CONTAINS" => KwContains
    "CREATE" => KwCreate
    "MERGE" => KwMerge
    "SET" => KwSet
    "DELETE" => KwDelete
    "DETACH" => KwDetach
    "WITH" => KwWith
    _ => Ident
  }
}

///|
fn is_ident_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
fn is_ident_part(c : Char) -> Bool {
  is_ident_start(c) || (c >= '0' && c <= '9')
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// Tokenize a Cypher query.
pub fn tokenize(source : String) -> Array[Token] raise LexError {
  let chars = Array::from_iter(source.iter())
  let tokens : Array[Token] = []
  let mut i = 0
  let n = chars.length()
  while i < n {
    let c = chars[i]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      i = i + 1
      continue
    }
    let start = i
    if is_ident_start(c) {
      let mut j = i
      while j < n && is_ident_part(chars[j]) {
        j = j + 1
      }
      let word = String::from_array(chars[i:j])
      tokens.push({ kind: keyword_kind(word), text: word, pos: start, })
      i = j
      continue
    }
    if is_digit(c) {
      let mut j = i
      let mut is_float = false
      while j < n && is_digit(chars[j]) {
        j = j + 1
      }
      if j + 1 < n && chars[j] == '.' && is_digit(chars[j + 1]) {
        is_float = true
        j = j + 1
        while j < n && is_digit(chars[j]) {
          j = j + 1
        }
      }
      let text = String::from_array(chars[i:j])
      tokens.push({
        kind: if is_float {
          Float
        } else {
          Int
        },
        text,
        pos: start,
      })
      i = j
      continue
    }
    if c == '\'' || c == '"' {
      let quote = c
      let mut j = i + 1
      let buf = StringBuilder()
      let mut closed = false
      while j < n {
        let ch = chars[j]
        if ch == '\\' && j + 1 < n {
          let esc = chars[j + 1]
          match esc {
            'n' => buf.write_char('\n')
            't' => buf.write_char('\t')
            'r' => buf.write_char('\r')
            '\\' => buf.write_char('\\')
            '\'' => buf.write_char('\'')
            '"' => buf.write_char('"')
            _ => buf.write_char(esc)
          }
          j = j + 2
          continue
        }
        if ch == quote {
          closed = true
          j = j + 1
          break
        }
        buf.write_char(ch)
        j = j + 1
      }
      if !closed {
        raise LexError::UnterminatedString(start)
      }
      tokens.push({ kind: Str, text: buf.to_string(), pos: start, })
      i = j
      continue
    }
    match c {
      '(' => {
        tokens.push({ kind: LParen, text: "(", pos: start, })
        i = i + 1
      }
      ')' => {
        tokens.push({ kind: RParen, text: ")", pos: start, })
        i = i + 1
      }
      '[' => {
        tokens.push({ kind: LBracket, text: "[", pos: start, })
        i = i + 1
      }
      ']' => {
        tokens.push({ kind: RBracket, text: "]", pos: start, })
        i = i + 1
      }
      '{' => {
        tokens.push({ kind: LBrace, text: "{", pos: start, })
        i = i + 1
      }
      '}' => {
        tokens.push({ kind: RBrace, text: "}", pos: start, })
        i = i + 1
      }
      ':' => {
        tokens.push({ kind: Colon, text: ":", pos: start, })
        i = i + 1
      }
      ',' => {
        tokens.push({ kind: Comma, text: ",", pos: start, })
        i = i + 1
      }
      '.' =>
        // `..` is the range separator inside variable length relationships.
        if i + 1 < n && chars[i + 1] == '.' {
          tokens.push({ kind: Dot, text: "..", pos: start, })
          i = i + 2
        } else {
          tokens.push({ kind: Dot, text: ".", pos: start, })
          i = i + 1
        }
      '|' => {
        tokens.push({ kind: Pipe, text: "|", pos: start, })
        i = i + 1
      }
      ';' => {
        tokens.push({ kind: Semicolon, text: ";", pos: start, })
        i = i + 1
      }
      '%' => {
        tokens.push({ kind: Percent, text: "%", pos: start, })
        i = i + 1
      }
      '+' => {
        tokens.push({ kind: Plus, text: "+", pos: start, })
        i = i + 1
      }
      '*' => {
        tokens.push({ kind: Star, text: "*", pos: start, })
        i = i + 1
      }
      '/' => {
        tokens.push({ kind: Slash, text: "/", pos: start, })
        i = i + 1
      }
      '-' =>
        if i + 1 < n && chars[i + 1] == '>' {
          tokens.push({ kind: ArrowRight, text: "->", pos: start, })
          i = i + 2
        } else {
          tokens.push({ kind: Minus, text: "-", pos: start, })
          i = i + 1
        }
      '<' =>
        if i + 1 < n && chars[i + 1] == '-' {
          tokens.push({ kind: ArrowLeft, text: "<-", pos: start, })
          i = i + 2
        } else if i + 1 < n && chars[i + 1] == '=' {
          tokens.push({ kind: Le, text: "<=", pos: start, })
          i = i + 2
        } else if i + 1 < n && chars[i + 1] == '>' {
          tokens.push({ kind: Neq, text: "<>", pos: start, })
          i = i + 2
        } else {
          tokens.push({ kind: Lt, text: "<", pos: start, })
          i = i + 1
        }
      '>' =>
        if i + 1 < n && chars[i + 1] == '=' {
          tokens.push({ kind: Ge, text: ">=", pos: start, })
          i = i + 2
        } else {
          tokens.push({ kind: Gt, text: ">", pos: start, })
          i = i + 1
        }
      '=' => {
        tokens.push({ kind: Eq, text: "=", pos: start, })
        i = i + 1
      }
      '!' =>
        if i + 1 < n && chars[i + 1] == '=' {
          tokens.push({ kind: Neq, text: "!=", pos: start, })
          i = i + 2
        } else {
          raise LexError::UnexpectedChar(c, start)
        }
      _ => raise LexError::UnexpectedChar(c, start)
    }
  }
  tokens.push({ kind: Eof, text: "", pos: n, })
  tokens
}
