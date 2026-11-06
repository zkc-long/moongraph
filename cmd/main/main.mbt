// MoonGraph command line interface.
//
//   moongraph query <graph.jsonl> <cypher> [--json]
//   moongraph info <graph.jsonl>
//   moongraph import <graph.jsonl>
//   moongraph registry <records.jsonl>
//   moongraph bench <graph.jsonl> <cypher> [--iters N]
//
// The CLI is a thin shell around the library: parsing, planning and execution
// all live in the `moongraph` packages, so the same engine is usable from
// tests and from other MoonBit programs.

///|
fn usage() -> Unit {
  println("MoonGraph - a property graph database with a Cypher subset")
  println("")
  println("Usage:")
  println("  moongraph query    <graph.jsonl> <cypher> [--json]")
  println("  moongraph info     <graph.jsonl>")
  println("  moongraph import   <graph.jsonl>")
  println("  moongraph registry <records.jsonl>")
  println("  moongraph bench    <graph.jsonl> <cypher> [--iters N]")
}

///|
async fn read_graph(path : String) -> @mg.Graph? {
  let text = @fs.read_text(path) catch {
    _ => {
      println("error: cannot read " + path)
      return None
    }
  }
  let graph = @mg.load_graph(text) catch {
    @mg.LoadError::BadLine(line, why) => {
      println("error: bad record on line \{line}: " + why)
      return None
    }
    @mg.LoadError::MissingNode(id) => {
      println("error: edge references unknown node '" + id + "'")
      return None
    }
  }
  Some(graph)
}

///|
fn run_query(graph : @mg.Graph, source : String, as_json : Bool) -> Unit {
  let result = @cypher.run(graph, source) catch {
    @cypher.ParseError::UnexpectedToken(what, pos) => {
      println("parse error at offset \{pos}: expected " + what)
      return
    }
    @cypher.ParseError::BadRange(pos) => {
      println("parse error at offset \{pos}: bad path range")
      return
    }
    _ => {
      println("parse error: invalid query")
      return
    }
  }
  if as_json {
    println(result.to_json())
  } else {
    println(result.to_table())
  }
}

///|
async fn main {
  let args = @env.args()
  if args.length() < 2 {
    usage()
    return
  }
  let command = args[1]
  match command {
    "query" => {
      if args.length() < 4 {
        usage()
        return
      }
      match read_graph(args[2]) {
        Some(graph) => {
          let as_json = args.any(fn(a) { a == "--json" })
          run_query(graph, args[3], as_json)
        }
        None => ()
      }
    }
    "info" => {
      if args.length() < 3 {
        usage()
        return
      }
      match read_graph(args[2]) {
        Some(graph) => println(info_text(graph))
        None => ()
      }
    }
    "import" => {
      if args.length() < 3 {
        usage()
        return
      }
      match read_graph(args[2]) {
        Some(graph) => {
          // Re-serialising validates the whole file end to end.
          let text = @mg.dump_graph(graph)
          let lines = text.split("\n").length() - 1
          println("ok: \{graph.node_count()} nodes, \{graph.edge_count()} edges (\{lines} records)")
        }
        None => ()
      }
    }
    "registry" => {
      if args.length() < 3 {
        usage()
        return
      }
      let text = @fs.read_text(args[2]) catch {
        _ => {
          println("error: cannot read " + args[2])
          return
        }
      }
      let graph = @mg.load_registry_records(text) catch {
        _ => {
          println("error: bad registry record file")
          return
        }
      }
      println(@mg.dump_graph(graph))
    }
    "bench" => {
      if args.length() < 4 {
        usage()
        return
      }
      let iterations = parse_iters(args)
      match read_graph(args[2]) {
        Some(graph) => {
          println("rows=run-parity check")
          let result = @cypher.run(graph, args[3]) catch {
            _ => {
              println("parse error")
              return
            }
          }
          let rows = result.row_count()
          let start = @bench.monotonic_clock_start()
          let mut i = 0L
          while i < iterations {
            ignore(@cypher.run(graph, args[3]) catch { _ => abort("bad query") })
            i = i + 1
          }
          let elapsed = @bench.monotonic_clock_end(start)
          println(
            "\{iterations} iterations, \{rows} rows, \{elapsed} us total, \{elapsed / iterations.to_double()} us/iter",
          )
        }
        None => ()
      }
    }
    _ => usage()
  }
}

///|
fn parse_iters(args : Array[String]) -> Int64 {
  let mut i = 0
  while i < args.length() {
    if args[i] == "--iters" && i + 1 < args.length() {
      return @string.parse_int64(args[i + 1]) catch { _ => 100L }
    }
    i = i + 1
  }
  100L
}

///|
fn info_text(graph : @mg.Graph) -> String {
  let buf = StringBuilder()
  buf.write_string("nodes: \{graph.node_count()}\n")
  buf.write_string("edges: \{graph.edge_count()}\n")
  buf.write_string("labels:\n")
  for label in graph.labels() {
    buf.write_string("  \{label}: \{graph.nodes_with_label(label).length()}\n")
  }
  buf.write_string("edge types:\n")
  for etype in graph.edge_types() {
    let mut count = 0
    let mut i = 0
    while i < graph.edge_count() {
      if graph.edge(i).etype == etype {
        count = count + 1
      }
      i = i + 1
    }
    buf.write_string("  \{etype}: \{count}\n")
  }
  buf.to_string()
}
