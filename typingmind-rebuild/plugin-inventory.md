# Plugin Inventory — Where Every Integration Lives

> Canonical map of all TypingMind integrations. Updated 2026-10-29.
> If a crash wipes TypingMind, this file tells you what to re-add and where
> every credential is stored.

## MCP Connectors (browser-side, import from mcp-servers.json)

| Server | Version | Notes |
|---|---|---|
| chrome-devtools-mcp | **1.12.0** (pinned) | `--allow-unrestricted-paths` flag |
| mcp-gsc | **0.4.1** (pinned) | OAuth in Production mode (7-day expiry fixed) |
| quickbooks | local build | `C:\Users\shawn\qbo-mcp\dist\index.js` (not npx) |
| (others) | floating | filesystem, github, woo, desktop-commander, exa, win-cli, playwright, memory, etc. — see mcp-servers.json once captured |

## OpenAPI Plugin (the bootstrap — add this FIRST)

| Item | Value |
|---|---|
| URL | `http://127.0.0.1:8787/openapi.json` |
| Auth header | `x-tm-key` |
| Key source | Windows Credential Manager, entry `TMB:tmKey` (read via `credman.ps1 -Get -Name tmKey`) |
| Tools | 19 (shell, files, GitHub, Exa, Woo, QBO, Render, GSC, memory-graph, chrome-control) |

This plugin alone gives an AI assistant full machine access — it is the
recovery key for everything else.

## Native TypingMind Plugins (browser storage)

| Plugin | Key location |
|---|---|
| (fill in — OpenRouter, others) | (vault entry or re-enter from provider) |

## Secret Vault (Windows Credential Manager — survives browser crashes)

| Entry | Holds |
|---|---|
| `TMB:tmKey` | bridge auth key |
| `TMB:githubPat` | GitHub fine-grained PAT |
| `TMB:exaApiKey` | Exa API key |
| `TMB:renderToken` | Render API token |
| `TMB:wooKey` | WooCommerce key (adventuresofbuttholekitty.com) |
| `TMB:wooSecret` | WooCommerce secret |

Read any entry: `powershell -File C:\Users\shawn\tm-bridge\credman.ps1 -Get -Name <name>`

## Sources

Canonical copies live in `sources\` (this folder). Re-upload after a crash.
