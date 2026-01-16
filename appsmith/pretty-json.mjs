#!/usr/bin/env node
/**
 * pretty-json.mjs
 *
 * Post-process an Appsmith/Airtable-style JSON export that is minified (single line)
 * into a diff-friendly pretty JSON file.
 *
 * Default behavior:
 * - Preserves key insertion order from the source JSON (best for re-import compatibility)
 * - Formats with 2-space indentation
 * - Ensures trailing newline
 *
 * Options:
 *   --in <path>            Input JSON file (required)
 *   --out <path>           Output JSON file (required)
 *   --indent <n>           Indentation spaces (default 2)
 *   --sort-keys            Recursively sort object keys (more stable diffs, but changes key order)
 *   --crlf                 Write CRLF line endings (default is LF)
 */

import fs from "node:fs";
import path from "node:path";
import process from "node:process";

function usage(exitCode = 1) {
  const msg = `
Usage:
  node pretty-json.mjs --in "AppsmithExport.json" --out "AppsmithExport.pretty.json" [--indent 2] [--sort-keys] [--crlf]

Notes:
  - Default preserves key order from the source JSON.
  - Use --sort-keys if you want maximum diff stability across exports.
`;
  console.error(msg.trim());
  process.exit(exitCode);
}

function parseArgs(argv) {
  const args = {
    inPath: null,
    outPath: null,
    indent: 2,
    sortKeys: false,
    crlf: false,
  };

  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--in") args.inPath = argv[++i];
    else if (a === "--out") args.outPath = argv[++i];
    else if (a === "--indent") args.indent = Number(argv[++i]);
    else if (a === "--sort-keys") args.sortKeys = true;
    else if (a === "--crlf") args.crlf = true;
    else if (a === "-h" || a === "--help") usage(0);
    else {
      console.error(`Unknown arg: ${a}`);
      usage(1);
    }
  }

  if (!args.inPath || !args.outPath) usage(1);
  if (!Number.isFinite(args.indent) || args.indent < 0 || args.indent > 10) {
    throw new Error("--indent must be a number between 0 and 10");
  }

  return args;
}

function sortKeysDeep(value) {
  if (Array.isArray(value)) return value.map(sortKeysDeep);
  if (value && typeof value === "object") {
    const out = {};
    for (const k of Object.keys(value).sort()) {
      out[k] = sortKeysDeep(value[k]);
    }
    return out;
  }
  return value;
}

function main() {
  const args = parseArgs(process.argv);

  const raw = fs.readFileSync(args.inPath, "utf8");

  let obj;
  try {
    obj = JSON.parse(raw);
  } catch (e) {
    // Help pinpoint errors for huge single-line JSON files
    const msg = e?.message || String(e);
    throw new Error(`Failed to parse JSON from "${args.inPath}": ${msg}`);
  }

  const toWrite = args.sortKeys ? sortKeysDeep(obj) : obj;

  let pretty = JSON.stringify(toWrite, null, args.indent) + "\n";
  if (args.crlf) pretty = pretty.replace(/\n/g, "\r\n");

  fs.mkdirSync(path.dirname(args.outPath), { recursive: true });
  fs.writeFileSync(args.outPath, pretty, "utf8");

  console.log(`Wrote: ${args.outPath}`);
}

try {
  main();
} catch (err) {
  console.error(err?.stack || String(err));
  process.exit(1);
}
