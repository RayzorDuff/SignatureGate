#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const argv = process.argv.slice(2);
function arg(name, fallback = null) {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : fallback;
}
const source = path.resolve(arg("--source", process.env.APPSMITH_SOURCE ?? "../SignatureGate-Appsmith"));
const output = path.resolve(arg("--output", "appsmith/Rooted Psyche Membership Ops.json"));

function readJson(file) { return JSON.parse(fs.readFileSync(file, "utf8")); }
function exists(file) { return fs.existsSync(file); }
function listDirs(dir) {
  if (!exists(dir)) return [];
  return fs.readdirSync(dir, { withFileTypes: true }).filter(e => e.isDirectory()).map(e => e.name).sort((a,b) => a.localeCompare(b));
}
function clone(v) { return v == null ? v : JSON.parse(JSON.stringify(v)); }
function readBody(dir, name) {
  for (const file of [path.join(dir, name + ".txt"), path.join(dir, "body.txt"), path.join(dir, name + ".js")]) {
    if (exists(file)) return fs.readFileSync(file, "utf8");
  }
  return null;
}
function hydrateAction(dir) {
  if (!exists(path.join(dir, "metadata.json"))) return null;
  const meta = readJson(path.join(dir, "metadata.json"));
  const action = clone(meta.unpublishedAction ?? meta.publishedAction);
  if (!action) return null;
  const body = readBody(dir, action.name ?? path.basename(dir));
  if (body !== null) { action.actionConfiguration ??= {}; action.actionConfiguration.body = body; }
  return { deleted:false, gitSyncId:meta.gitSyncId, id:meta.id, pluginId:meta.pluginId, pluginType:meta.pluginType, publishedAction:clone(action), unpublishedAction:action };
}
function hydrateCollection(dir) {
  if (!exists(path.join(dir, "metadata.json"))) return null;
  const meta = readJson(path.join(dir, "metadata.json"));
  const collection = clone(meta.unpublishedCollection ?? meta.publishedCollection);
  if (!collection) return null;
  const body = readBody(dir, collection.name ?? path.basename(dir));
  if (body !== null) collection.body = body;
  return { deleted:false, gitSyncId:meta.gitSyncId, id:meta.id, publishedCollection:clone(collection), unpublishedCollection:collection };
}
function collectWidgets(dir) {
  if (!exists(dir)) return [];
  const result = [];
  for (const file of fs.readdirSync(dir).sort()) {
    const full = path.join(dir, file);
    if (fs.statSync(full).isDirectory()) result.push(...collectWidgets(full));
    else if (file.endsWith(".json")) {
      const widget = readJson(full);
      if (widget.widgetName) result.push(widget);
    }
  }
  return result;
}
function buildPage(pageDir) {
  const files = fs.readdirSync(pageDir).filter(f => f.endsWith(".json") && f !== "metadata.json");
  const pageFile = files.find(f => f.toLowerCase().includes(path.basename(pageDir).toLowerCase())) ?? files[0];
  if (!pageFile) return null;
  const page = readJson(path.join(pageDir, pageFile));
  const unpublished = clone(page.unpublishedPage ?? page.publishedPage);
  if (!unpublished) return null;
  const widgets = collectWidgets(path.join(pageDir, "widgets"));
  const byParent = new Map();
  for (const widget of widgets) {
    const parent = widget.parentId ?? "0";
    if (!byParent.has(parent)) byParent.set(parent, []);
    byParent.get(parent).push(widget);
  }
  function attach(widget) {
    const children = byParent.get(widget.widgetId);
    if (children?.length) widget.children = children.sort((a,b) => (a.topRow ?? 0) - (b.topRow ?? 0) || (a.leftColumn ?? 0) - (b.leftColumn ?? 0)).map(attach);
    return widget;
  }
  for (const layout of unpublished.layouts ?? []) {
    const dsl = layout.dsl;
    if (dsl) dsl.children = (byParent.get(dsl.widgetId ?? "0") ?? byParent.get("0") ?? []).sort((a,b) => (a.topRow ?? 0) - (b.topRow ?? 0) || (a.leftColumn ?? 0) - (b.leftColumn ?? 0)).map(attach);
  }
  return { deleted:false, gitSyncId:page.gitSyncId, publishedPage:clone(unpublished), unpublishedPage:unpublished };
}

const application = readJson(path.join(source, "application.json"));
const metadata = readJson(path.join(source, "metadata.json"));
const theme = exists(path.join(source, "theme.json")) ? readJson(path.join(source, "theme.json")) : null;
const pageRoot = path.join(source, "pages");
const pageList = listDirs(pageRoot).map(name => buildPage(path.join(pageRoot, name))).filter(Boolean);
const datasourceRoot = path.join(source, "datasources");
const datasourceList = listDirs(datasourceRoot).map(name => {
  const file = path.join(datasourceRoot, name + ".json");
  return exists(file) ? readJson(file) : null;
}).filter(Boolean);

const actionList = [];
for (const pageName of listDirs(pageRoot)) {
  const root = path.join(pageRoot, pageName, "queries");
  for (const name of listDirs(root)) {
    const action = hydrateAction(path.join(root, name));
    if (action) actionList.push(action);
  }
}
const actionCollectionList = [];
for (const pageName of listDirs(pageRoot)) {
  const root = path.join(pageRoot, pageName, "jsobjects");
  for (const name of listDirs(root)) {
    const collection = hydrateCollection(path.join(root, name));
    if (collection) actionCollectionList.push(collection);
  }
}
const customJSLibRoot = path.join(source, "customJSLibs");
const customJSLibList = listDirs(customJSLibRoot).map(name => {
  const file = path.join(customJSLibRoot, name + ".json");
  return exists(file) ? readJson(file) : null;
}).filter(Boolean);

const result = {
  actionCollectionList, actionList,
  artifactJsonType: metadata.artifactJsonType ?? "APPLICATION",
  clientSchemaVersion: metadata.clientSchemaVersion,
  customJSLibList, datasourceList,
  editModeTheme: theme,
  exportedApplication: application,
  pageList,
  publishedTheme: theme,
  serverSchemaVersion: metadata.serverSchemaVersion
};
fs.mkdirSync(path.dirname(output), { recursive:true });
fs.writeFileSync(output, JSON.stringify(result, null, 2) + "\n");
console.log(JSON.stringify({output, pages:pageList.length, datasources:datasourceList.length, actions:actionList.length, actionCollections:actionCollectionList.length, customJSLibs:customJSLibList.length, serverSchemaVersion:result.serverSchemaVersion, clientSchemaVersion:result.clientSchemaVersion}, null, 2));
