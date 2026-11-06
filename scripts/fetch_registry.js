#!/usr/bin/env node
// Fetch a slice of the mooncakes registry and emit one JSON record per module.
//
// Usage: node scripts/fetch_registry.js [limit] > examples/mooncakes.registry.jsonl
//
// This is a data preparation script, not part of the engine: the engine itself
// is pure MoonBit. It is checked in so the sample dataset can be regenerated.

const https = require("https");

const LIMIT = Number(process.argv[2] || 120);

function get(url) {
  return new Promise((resolve, reject) => {
    https
      .get(url, { headers: { "user-agent": "moongraph-dataset/0.1" } }, (res) => {
        let body = "";
        res.on("data", (d) => (body += d));
        res.on("end", () => {
          if (res.statusCode !== 200) return reject(new Error(`${url} -> ${res.statusCode}`));
          try {
            resolve(JSON.parse(body));
          } catch (e) {
            reject(e);
          }
        });
      })
      .on("error", reject);
  });
}

const KEYWORDS = [
  "json", "http", "parser", "cli", "test", "graph", "sql", "yaml", "regex",
  "encoding", "crypto", "web", "ui", "wasm", "async", "socket", "image",
  "markdown", "data", "math",
];

async function main() {
  const names = new Set();
  for (const kw of KEYWORDS) {
    try {
      const hits = await get(`https://mooncakes.io/api/v0/search?kw=${encodeURIComponent(kw)}`);
      for (const hit of hits) names.add(hit.name);
    } catch (e) {
      process.stderr.write(`skip ${kw}: ${e.message}\n`);
    }
  }
  const selected = Array.from(names).slice(0, LIMIT);
  process.stderr.write(`selected ${selected.length} modules\n`);
  const out = [];
  for (const name of selected) {
    try {
      const meta = await get(`https://mooncakes.io/api/v0/modules/${name}`);
      const record = {
        module: meta.module,
        version: meta.version || "",
        dependents: (meta.dependents || []).map((d) => ({ name: d.name })),
      };
      out.push(JSON.stringify(record));
    } catch (e) {
      process.stderr.write(`skip ${name}: ${e.message}\n`);
    }
  }
  process.stdout.write(out.join("\n") + "\n");
}

main().catch((e) => {
  process.stderr.write(String(e) + "\n");
  process.exit(1);
});
