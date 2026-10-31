// qs-node.mjs - small Node checks used by the registry (no type checking, no network).
//   node qs-node.mjs syntax-ts <files...>       TypeScript parser diagnostics (JS/JSX/TS/TSX)
//   node qs-node.mjs syntax-graphql <files...>  graphql-js parse
//   node qs-node.mjs lint-sas <files...>        @sasjs/lint (errors fail, warnings are printed)
//   node qs-node.mjs syntax-stylus|syntax-sass|syntax-mdx|syntax-liquid|syntax-hbs <files...>
//        parse only (stylus, sass-parser, @mdx-js/mdx compile, @shopify/liquid-html-parser,
//        handlebars): imports/includes are never resolved, so missing modules are not errors
// Modules resolve from QS_NPM (default /opt/npm). Exit 1 if any file has a problem.
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";

const npm = process.env.QS_NPM || "/opt/npm";
const require = createRequire(path.join(npm, "package.json"));
const [mode, ...files] = process.argv.slice(2);
let failed = false;
const report = (f, line, col, msg) => {
  console.log(`${f}:${line}:${col}: ${msg}`);
  failed = true;
};

if (mode === "syntax-ts") {
  const ts = require("typescript");
  const kinds = { ".js": ts.ScriptKind.JS, ".mjs": ts.ScriptKind.JS, ".cjs": ts.ScriptKind.JS,
    ".jsx": ts.ScriptKind.JSX, ".ts": ts.ScriptKind.TS, ".mts": ts.ScriptKind.TS, ".cts": ts.ScriptKind.TS,
    ".tsx": ts.ScriptKind.TSX };
  for (const f of files) {
    const text = readFileSync(f, "utf8");
    const kind = kinds[path.extname(f).toLowerCase()] ?? ts.ScriptKind.TS;
    const sf = ts.createSourceFile(f, text, ts.ScriptTarget.Latest, true, kind);
    for (const d of sf.parseDiagnostics) {
      const { line, character } = sf.getLineAndCharacterOfPosition(d.start ?? 0);
      report(f, line + 1, character + 1, ts.flattenDiagnosticMessageText(d.messageText, " "));
    }
  }
} else if (mode === "syntax-graphql") {
  const { parse } = require("graphql");
  for (const f of files) {
    try {
      parse(readFileSync(f, "utf8"), { noLocation: true });
    } catch (e) {
      const loc = (e.locations && e.locations[0]) || { line: 1, column: 1 };
      report(f, loc.line, loc.column, e.message.split("\n")[0]);
    }
  }
} else if (mode === "lint-sas") {
  const { lintText } = require("@sasjs/lint");
  for (const f of files) {
    const diags = await lintText(readFileSync(f, "utf8"));
    for (const d of diags) {
      const msg = `${d.severity === 2 ? "error" : "warning"}: ${d.message}`;
      if (d.severity === 2) report(f, d.lineNumber, d.startColumnNumber, msg);
      else console.log(`${f}:${d.lineNumber}:${d.startColumnNumber}: ${msg}`);
    }
  }
} else if (mode === "syntax-stylus") {
  const stylus = require("stylus");
  for (const f of files) {
    let p;
    try {
      p = new stylus.Parser(readFileSync(f, "utf8"), { filename: f });
      p.parse();
    } catch (e) {
      report(f, e.lineno || p?.lexer?.lineno || 1, 1, String(e.message).split("\n")[0]);
    }
  }
} else if (mode === "syntax-sass") {
  const { sass } = require("sass-parser");
  for (const f of files) {
    try {
      sass.parse(readFileSync(f, "utf8"), { from: f });
    } catch (e) {
      const st = e.span?.start;
      report(f, st ? st.line + 1 : 1, st ? st.column + 1 : 1, String(e.message || e).split("\n")[0]);
    }
  }
} else if (mode === "syntax-mdx") {
  // why import(): @mdx-js/mdx is ESM-only and cannot be require()d
  const { compile } = await import(path.join(npm, "node_modules/@mdx-js/mdx/index.js"));
  for (const f of files) {
    try {
      await compile({ value: readFileSync(f, "utf8"), path: f });
    } catch (e) {
      const pos = e.place?.start ?? e.place ?? {};
      report(f, pos.line ?? 1, pos.column ?? 1, String(e.reason ?? e.message).split("\n")[0]);
    }
  }
} else if (mode === "syntax-liquid") {
  const { toLiquidHtmlAST } = require("@shopify/liquid-html-parser");
  for (const f of files) {
    try {
      toLiquidHtmlAST(readFileSync(f, "utf8"), { mode: "tolerant", allowUnclosedDocumentNode: false });
    } catch (e) {
      report(f, e.loc?.start?.line ?? 1, e.loc?.start?.column ?? 1, String(e.message).split("\n")[0]);
    }
  }
} else if (mode === "syntax-hbs") {
  const Handlebars = require("handlebars");
  for (const f of files) {
    try {
      Handlebars.parse(readFileSync(f, "utf8"));
    } catch (e) {
      const m = String(e.message).split("\n");
      const line = e.lineNumber || (/Parse error on line (\d+)/.exec(m[0]) || [])[1] || 1;
      report(f, line, 1, m[m.length - 1] || m[0]);
    }
  }
} else {
  console.error(`unknown mode: ${mode}`);
  process.exit(2);
}
process.exit(failed ? 1 : 0);
