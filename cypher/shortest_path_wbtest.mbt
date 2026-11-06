// shortestPath tests (cypher package).

///|
test "shortestPath/returns-hop-count" {
  let g = @mg.Graph::new()
  let a = g.add_node(["N"], Map([]))
  let b = g.add_node(["N"], Map([]))
  let c = g.add_node(["N"], Map([]))
  ignore(g.add_edge("R", a, b, Map([])) catch { _ => -1 })
  ignore(g.add_edge("R", b, c, Map([])) catch { _ => -1 })
  let result = run(
    g, "MATCH (x:N), (y:N) WHERE id(x) = 0 AND id(y) = 2 RETURN shortestPath(x, y) AS d",
  ) catch {
    _ => abort("bad query")
  }
  assert_eq(result.rows[0][0].as_string(), "2")
}

///|
test "shortestPath/unreachable-is-null" {
  let g = @mg.Graph::new()
  ignore(g.add_node(["N"], Map([])))
  ignore(g.add_node(["N"], Map([])))
  let result = run(
    g, "MATCH (x:N), (y:N) WHERE id(x) = 0 AND id(y) = 1 RETURN shortestPath(x, y) AS d",
  ) catch {
    _ => abort("bad query")
  }
  assert_true(result.rows[0][0] is @mg.VNull)
}

///|
test "shortestPath/is-undirected" {
  let g = @mg.Graph::new()
  let a = g.add_node(["N"], Map([]))
  let b = g.add_node(["N"], Map([]))
  ignore(g.add_edge("R", a, b, Map([])) catch { _ => -1 })
  let result = run(
    g, "MATCH (x:N), (y:N) WHERE id(x) = 1 AND id(y) = 0 RETURN shortestPath(x, y) AS d",
  ) catch {
    _ => abort("bad query")
  }
  assert_eq(result.rows[0][0].as_string(), "1")
}
