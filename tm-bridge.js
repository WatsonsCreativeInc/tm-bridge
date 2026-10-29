const http = require("http");
const fs = require("fs");
const path = require("path");
const os = require("os");
const { exec } = require("child_process");

// [tm-bridge hardening 2026-10-29] Survive stray async/parse errors instead
// of dying: a bridge must log-and-continue. Task Scheduler restarts the
// process only if it actually exits, so these handlers prevent the
// "crashed, had to restart by hand" failure mode from routine errors.
process.on("uncaughtException", (e) => console.error("[tm-bridge] UNCAUGHT:", e && e.stack || e));
process.on("unhandledRejection", (e) => console.error("[tm-bridge] UNHANDLED_REJECTION:", e && (e.stack || e)));
const PORT = process.env.TM_BRIDGE_PORT || 8787;
const HOME = os.homedir();
const BASE_DIR = HOME;
const CFG_DIR = path.join(HOME, ".tm-bridge");
const CFG_FILE = path.join(CFG_DIR, "config.json");
// [2026-10-29] Secrets live in Windows Credential Manager as "TMB:<name>".
// config.json may reference them as "vault:<name>"; this resolver swaps the
// reference for the real value BEFORE the server starts listening, so there
// is no window where the bridge is up with unresolved credentials.
// Uses execSync + -EncodedCommand: synchronous (no startup race) and
// immune to cmd.exe quoting/newline issues.
function readVaultSecret(name) {
  const ps = [
    "$ErrorActionPreference='Stop'",
    "$s=@\"",
    "using System;using System.Runtime.InteropServices;public static class CM{",
    "[StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]public struct C{public int Flags;public int Type;public string TargetName;public string Comment;public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;public int CredentialBlobSize;public IntPtr CredentialBlob;public int Persist;public int AttributeCount;public IntPtr Attributes;public string TargetAlias;public string UserName;}",
    "[DllImport(\"advapi32.dll\",CharSet=CharSet.Unicode,EntryPoint=\"CredReadW\")]public static extern bool R(string t,int ty,int f,out IntPtr p);",
    "[DllImport(\"advapi32.dll\", EntryPoint=\"CredFree\")]public static extern void F(IntPtr c);}",
    "\"@",
    "Add-Type -TypeDefinition $s",
    "$p=[IntPtr]::Zero",
    "if(-not [CM]::R('TMB:" + name + "',1,0,[ref]$p)){exit 1}",
    "try{",
    "$c=[Runtime.InteropServices.Marshal]::PtrToStructure($p,[type][CM+C])",
    "$b=New-Object byte[] $c.CredentialBlobSize",
    "[Runtime.InteropServices.Marshal]::Copy($c.CredentialBlob,$b,0,$c.CredentialBlobSize)",
    "[Console]::Out.Write([Text.Encoding]::Unicode.GetString($b))",
    "}finally{[CM]::F($p)}"
  ].join("\r\n");
  const encoded = Buffer.from(ps, "utf16le").toString("base64");
  const { execSync } = require("child_process");
  try {
    return execSync("powershell.exe -NoProfile -EncodedCommand " + encoded,
      { encoding: "utf8", windowsHide: true, timeout: 20000 }).trim();
  } catch (e) {
    console.error("[tm-bridge] vault read failed for TMB:" + name + ":", (e && e.message || e).split("\n")[0]);
    return "";
  }
}
function resolveCfgSecrets(cfg) {
  const ref = (v) => typeof v === "string" && v.startsWith("vault:");
  let resolved = 0;
  if (ref(cfg.tmKey)) { cfg.tmKey = readVaultSecret("tmKey"); resolved++; }
  if (ref(cfg.githubPat)) { cfg.githubPat = readVaultSecret("githubPat"); resolved++; }
  if (ref(cfg.exaApiKey)) { cfg.exaApiKey = readVaultSecret("exaApiKey"); resolved++; }
  if (ref(cfg.renderToken)) { cfg.renderToken = readVaultSecret("renderToken"); resolved++; }
  if (cfg.woo && ref(cfg.woo.key)) { cfg.woo.key = readVaultSecret("wooKey"); resolved++; }
  if (cfg.woo && ref(cfg.woo.secret)) { cfg.woo.secret = readVaultSecret("wooSecret"); resolved++; }
  return resolved;
}
let CFG = {};
try { CFG = JSON.parse(fs.readFileSync(CFG_FILE, "utf8")); } catch (e) {}
try {
  const n = resolveCfgSecrets(CFG);
  console.log("[tm-bridge] vault secrets resolved: " + n + " of 6");
} catch (e) {
  console.error("[tm-bridge] vault resolve error:", e && e.message || e);
}
const cap = (s, n) => String(s == null ? "" : s).slice(0, n || 100000);

const ALLOWED_ORIGINS = new Set([
  "https://YOUR-REAL-ORIGIN"
]);
function cors(res) {
  const o = (res.req && res.req.headers && res.req.headers.origin) || "";
  res.setHeader("Access-Control-Allow-Origin", ALLOWED_ORIGINS.has(o) ? o : "null");
  res.setHeader("Vary", "Origin");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  res.setHeader("Access-Control-Allow-Private-Network", "true");
}
function send(res, code, obj) { res.writeHead(code, { "Content-Type": "application/json" }); res.end(JSON.stringify(obj)); }
function readBody(req) { return new Promise((resolve) => { let d = ""; req.on("data", (c) => (d += c)); req.on("end", () => { try { resolve(JSON.parse(d || "{}")); } catch (e) { resolve({}); } }); }); }
const sh = (cmd) => new Promise((resolve) => exec(cmd, { encoding: "utf8", maxBuffer: 20 * 1024 * 1024, windowsHide: true, cwd: BASE_DIR, timeout: 180000 }, (err, stdout, stderr) => resolve({ ok: !err, stdout: cap(stdout, 200000), stderr: cap(stderr, 20000), code: err ? (err.code || 1) : 0 })));
const safePath = (p) => { const full = path.resolve(BASE_DIR, p || "."); if (!full.toLowerCase().startsWith(BASE_DIR.toLowerCase())) throw new Error("Path outside home dir blocked"); return full; };

async function woo(args) {
  const a = args || {};
  const site = (CFG.woo && CFG.woo.siteUrl) || "https://adventuresofbuttholekitty.com";
  const key = CFG.woo && CFG.woo.key, sec = CFG.woo && CFG.woo.secret;
  if (!key || !sec) return { error: "Missing woo keys in " + CFG_FILE };
  const url = new URL(site.replace(/\/$/, "") + "/wp-json/wc/v3/" + String(a.endpoint || "products").replace(/^\//, ""));
  if (a.query) for (const k of Object.keys(a.query)) url.searchParams.set(k, a.query[k]);
  const auth = "Basic " + Buffer.from(key + ":" + sec).toString("base64");
  const r = await fetch(url, { method: a.method || "GET", headers: { Authorization: auth, "Content-Type": "application/json" }, body: a.body ? JSON.stringify(a.body) : undefined });
  return { status: r.status, body: cap(await r.text(), 150000) };
}

async function qbo(args) {
  const a = args || {};
  const q = CFG.qbo || {};
  if (!q.realmId || !q.clientId || !q.clientSecret || !q.refreshToken) return { error: "Add a qbo block to " + CFG_FILE + " with realmId, clientId, clientSecret, refreshToken, environment" };
  const rr = await fetch("https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json" }, body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: q.refreshToken, client_id: q.clientId, client_secret: q.clientSecret }) });
  const jt = await rr.json();
  if (!jt.access_token) return { error: "QBO token refresh failed - re-auth needed", detail: jt };
  const host = q.environment === "sandbox" ? "https://sandbox-quickbooks.api.intuit.com" : "https://quickbooks.api.intuit.com";
  let url, opts = { method: a.method || "GET", headers: { Authorization: "Bearer " + jt.access_token, Accept: "application/json" } };
  if (a.sql) { url = host + "/v3/company/" + q.realmId + "/query?query=" + encodeURIComponent(a.sql); opts.method = "GET"; }
  else { url = host + "/v3/company/" + q.realmId + "/" + String(a.endpoint || "query").replace(/^\//, ""); opts.method = a.method || "POST"; opts.body = (typeof a.body === "string") ? a.body : (a.body == null ? undefined : JSON.stringify(a.body)); opts.headers["Content-Type"] = "application/json"; }
  const r = await fetch(url, opts);
  return { status: r.status, body: cap(await r.text(), 150000) };
}

async function render(args) {
  const a = args || {};
  const t = CFG.renderToken;
  if (!t) return { error: "Missing renderToken in " + CFG_FILE };
  const r = await fetch("https://api.render.com/v1" + (a.endpoint || ""), { method: a.method || "GET", headers: { Authorization: "Bearer " + t, Accept: "application/json", "Content-Type": "application/json" }, body: a.body ? JSON.stringify(a.body) : undefined });
  return { status: r.status, body: cap(await r.text(), 100000) };
}

async function gsc(args) {
  const a = args || {};
  const tokPath = path.join(BASE_DIR, ".mcp", "client_secret_338680529222-siq546io38v9b7gh63gsn2gre6ilf8bc.apps.googleusercontent.com_token.json");
  let tok;
  try { tok = JSON.parse(fs.readFileSync(tokPath, "utf8")); } catch (e) { return { error: "Token file missing: " + e.message }; }
  const clientSecret = tok.client_secret || (tok.installed && tok.installed.client_secret) || CFG.gscClientSecret;
  if (!tok.refresh_token || !clientSecret) return { error: "Need refresh_token + client_secret (re-run GSC OAuth once)" };
  const rr = await fetch("https://oauth2.googleapis.com/token", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ client_id: "338680529222-siq546io38v9b7gh63gsn2gre6ilf8bc.apps.googleusercontent.com", client_secret: clientSecret, refresh_token: tok.refresh_token, grant_type: "refresh_token" }) });
  const jt = await rr.json();
  if (!jt.access_token) return { error: "invalid_grant - re-auth GSC in browser", detail: jt };
  const r = await fetch("https://www.googleapis.com/webmasters/v3" + (a.endpoint || "/sites"), { method: a.method || "GET", headers: { Authorization: "Bearer " + jt.access_token, "Content-Type": "application/json" }, body: a.body ? JSON.stringify(a.body) : undefined });
  return { status: r.status, body: cap(await r.text(), 100000) };
}

async function fsSearch(args) {
  const a = args || {};
  const root = safePath(a.dirPath || ".");
  const out = [];
  const q = String(a.query || "").toLowerCase();
  const maxResults = a.maxResults || 30;
  const SKIP = new Set(["node_modules", ".git", ".next", "dist", "AppData"]);
  const walk = (d, depth) => {
    if (out.length >= maxResults || depth > 6) return;
    let ents;
    try { ents = fs.readdirSync(d, { withFileTypes: true }); } catch (e) { return; }
    for (const e of ents) {
      if (out.length >= maxResults) return;
      const full = path.join(d, e.name);
      if (e.isDirectory()) { if (!SKIP.has(e.name)) walk(full, depth + 1); continue; }
      try {
        const st = fs.statSync(full);
        if (st.size > 2 * 1024 * 1024) continue;
        const txt = fs.readFileSync(full, "utf8");
        const lower = txt.toLowerCase();
        let idx = 0, line = 1, found = 0;
        while ((idx = lower.indexOf(q, idx)) !== -1 && found < 3) {
          line = txt.slice(0, idx).split("\n").length;
          out.push({ file: full.replace(BASE_DIR, "~"), line: line, snippet: cap(txt.slice(Math.max(0, idx - 60), idx + 80).replace(/\s+/g, " "), 160) });
          idx += q.length;
          found++;
        }
      } catch (e) {}
    }
  };
  walk(root, 0);
  return { matches: out.length, results: out };
}

async function fsEditBlock(args) {
  const a = args || {};
  const p = safePath(a.filePath);
  const txt = fs.readFileSync(p, "utf8");
  const count = txt.split(a.find).length - 1;
  if (count === 0) return { ok: false, error: "find text not found" };
  if (count > 1 && !a.replaceAll) return { ok: false, error: "find text matches " + count + " times - pass replaceAll:true or use more context" };
  let out;
  if (a.replaceAll) { const re = new RegExp(a.find.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "g"); out = txt.replace(re, () => a.replace); }
  else { out = txt.replace(a.find, a.replace); }
  fs.writeFileSync(p, out);
  return { ok: true, replaced: a.replaceAll ? count : 1 };
}

const tools = {
  run_command: async (a) => await sh(a.command),
  proc_list: async () => await sh("tasklist"),
  proc_kill: async (a) => await sh(a.name ? 'taskkill /IM "' + a.name + '" /F' : "taskkill /PID " + a.pid + " /F"),
  fs_list: async (a) => { const p = safePath(a.dirPath); const ents = fs.readdirSync(p, { withFileTypes: true }); return ents.slice(0, 500).map((e) => { let size = 0; try { size = e.isDirectory() ? 0 : fs.statSync(path.join(p, e.name)).size; } catch (x) {} return { name: e.name, dir: e.isDirectory(), size: size }; }); },
  fs_read_text: async (a) => { const p = safePath(a.filePath); const limit = Math.min(a.maxBytes || 200000, 1000000); const fd = fs.openSync(p, "r"); const buf = Buffer.alloc(limit); const n = fs.readSync(fd, buf, 0, limit, 0); fs.closeSync(fd); return { content: buf.slice(0, n).toString("utf8"), truncated: n >= limit }; },
  fs_write_text: async (a) => { const p = safePath(a.filePath); fs.mkdirSync(path.dirname(p), { recursive: true }); if (a.append) fs.appendFileSync(p, a.content || ""); else fs.writeFileSync(p, a.content || ""); return { ok: true, bytes: Buffer.byteLength(a.content || "") }; },
  fs_edit_block: fsEditBlock,
  fs_search: fsSearch,
  fs_delete: async (a) => { fs.rmSync(safePath(a.filePath), { recursive: true, force: true }); return { ok: true }; },
  fs_mkdir: async (a) => { fs.mkdirSync(safePath(a.dirPath), { recursive: true }); return { ok: true }; },
  github_api: async (a) => {
    const t = CFG.githubPat;
    if (!t) return { error: "Missing githubPat in " + CFG_FILE };
    const r = await fetch("https://api.github.com" + a.endpoint, { method: a.method || "GET", headers: { Authorization: "Bearer " + t, Accept: "application/vnd.github+json", "Content-Type": "application/json", "User-Agent": "tm-bridge" }, body: a.body ? JSON.stringify(a.body) : undefined });
    return { status: r.status, body: cap(await r.text(), 100000) };
  },
  web_search_exa: async (a) => {
    const k = CFG.exaApiKey;
    if (!k) return { error: "Missing exaApiKey in " + CFG_FILE };
    const r = await fetch("https://api.exa.ai/search", { method: "POST", headers: { "x-api-key": k, "Content-Type": "application/json" }, body: JSON.stringify({ query: a.query, numResults: a.numResults || 6, contents: { text: { maxCharacters: 1500 } } }) });
    return { status: r.status, body: cap(await r.text(), 100000) };
  },
  woo_api: woo,
  qbo_api: qbo,
  render_api: render,
  gsc_refresh_and_call: gsc,
  knowledge_graph_write: async (a) => {
    const f = path.join(CFG_DIR, "kg.json");
    let g = { entities: [], relations: [] };
    try { g = JSON.parse(fs.readFileSync(f, "utf8")); } catch (e) {}
    if (a.subject && g.entities.indexOf(a.subject) === -1) g.entities.push(a.subject);
    if (a.object && g.entities.indexOf(a.object) === -1) g.entities.push(a.object);
    g.relations.push({ subject: a.subject, relation: a.relation, object: a.object, at: new Date().toISOString() });
    fs.writeFileSync(f, JSON.stringify(g, null, 1));
    return { ok: true, totalRelations: g.relations.length };
  },
  knowledge_graph_search: async (a) => {
    const f = path.join(CFG_DIR, "kg.json");
    let g = { relations: [] };
    try { g = JSON.parse(fs.readFileSync(f, "utf8")); } catch (e) {}
    const q = String(a.query || "").toLowerCase();
    const hits = g.relations.filter((r) => (r.subject || "").toLowerCase().indexOf(q) !== -1 || (r.object || "").toLowerCase().indexOf(q) !== -1 || (r.relation || "").toLowerCase().indexOf(q) !== -1);
    return { hits: hits.slice(-50) };
  },
  chrome_control: async (a) => {
    let target;
    try { target = (await (await fetch("http://127.0.0.1:9222/json")).json())[0]; } catch (e) { return { error: "No Chrome with --remote-debugging-port=9222 running" }; }
    if (typeof WebSocket === "undefined") return { error: "Node 22+ required for chrome_control" };
    const ws = new WebSocket(target.webSocketDebuggerUrl);
    const result = await new Promise((resolve) => {
      ws.onopen = () => {
        const s = (id, m, p) => ws.send(JSON.stringify({ id: id, method: m, params: p || {} }));
        if (a.action === "navigate") { s(1, "Page.navigate", { url: a.url }); setTimeout(() => s(2, "Runtime.evaluate", { expression: "document.title" }), 2500); }
        else if (a.action === "evaluate") s(1, "Runtime.evaluate", { expression: a.expression, returnByValue: true });
        else if (a.action === "screenshot") { s(1, "Page.enable"); s(2, "Page.captureScreenshot", { format: "jpeg", quality: 70 }); }
        else resolve({ error: "action: navigate | evaluate | screenshot" });
      };
      ws.onmessage = (ev) => { const m = JSON.parse(ev.data); if (m.id === (a.action === "navigate" ? 2 : 1)) resolve(m.result); };
      setTimeout(() => resolve({ error: "timeout" }), 15000);
    });
    try { ws.close(); } catch (e) {}
    return result;
  }
};

const spec = {
  openapi: "3.0.0",
  info: { title: "Local Tools Bridge v2", version: "2.0.0", description: "Shell, processes, files, GitHub, Exa, WooCommerce, QuickBooks, Render, GSC, memory graph, Chrome." },
  servers: [{ url: "http://127.0.0.1:" + PORT }],
  paths: { "/call": { post: { operationId: "callTool", summary: "Call a local tool", requestBody: { required: true, content: { "application/json": { schema: { type: "object", required: ["tool"], properties: { tool: { type: "string", enum: Object.keys(tools) }, args: { type: "object" } } } } } }, responses: { "200": { description: "Result" } } } } }
};

const server = http.createServer(async (req, res) => {
  cors(res);
  if (req.method === "OPTIONS") { res.writeHead(204); return res.end(); }
; // [tm-bridge hardening patch] localhost-only gate: blocks cross-origin browser calls + DNS rebinding
{
  const HOST_OK = new Set([`127.0.0.1:${PORT}`, `localhost:${PORT}`, `[::1]:${PORT}`]);
  const hh = String(req.headers.host || "").toLowerCase();
  if (!HOST_OK.has(hh)) return send(res, 403, { error: "blocked: bad Host header" });
  if (req.headers.origin) {
    try {
      if (!HOST_OK.has(new URL(req.headers.origin).host.toLowerCase()))
        return send(res, 403, { error: "blocked: cross-origin request" });
    } catch { return send(res, 403, { error: "blocked: malformed Origin" }); }
  }
  const TM_KEY = process.env.TM_BRIDGE_KEY || CFG.tmKey;
  if (TM_KEY && req.url === "/call" && req.headers["x-tm-key"] !== TM_KEY)
    return send(res, 401, { error: "unauthorized: missing x-tm-key header" });
}
  if (req.url === "/openapi.json") return send(res, 200, spec);
  if (req.url === "/health") return send(res, 200, { ok: true, version: "2.0", tools: Object.keys(tools) });
  if (req.url === "/call" && req.method === "POST") {
    const b = await readBody(req);
    const fn = tools[b.tool];
    if (!fn) return send(res, 400, { error: "Unknown tool: " + b.tool, available: Object.keys(tools) });
    try { return send(res, 200, await fn(b.args || {})); } catch (e) { return send(res, 200, { error: e.message }); }
  }
  res.writeHead(404);
  res.end("not found");
});
server.on("error", (e) => { console.error("TM Bridge failed to start:", e.message); if (e.code === "EADDRINUSE") console.error("Port busy - another instance is probably running."); process.exit(1); });
server.listen(PORT, "127.0.0.1", () => console.log("TM Bridge v2 ready on http://127.0.0.1:" + PORT + " | " + Object.keys(tools).length + " tools"));
