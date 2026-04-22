# VSCode Projects — Walker/Elephant Menu

**Date:** 2026-04-22
**Status:** Design approved, pending implementation plan
**Inspired by:** [Merrit/vscode-runner](https://github.com/Merrit/vscode-runner) (KRunner plugin)

## Problem

Walker is the launcher, but there's no quick way to jump to a recent VSCode project. Today you open VSCode first, then `Ctrl+R`. The goal: a walker-invoked menu that lists recent projects and launches `code <path>` on Enter, without opening VSCode as an intermediate step.

## Scope

**In:** A single elephant menu provider that surfaces VSCode's previously-opened workspaces, ordered by recency, invokable via `walker --provider menus:vscodeprojects`.

**Out:**

- Directory scanning (e.g. globbing `~/Projects/`) — recent-only, per agreement.
- VSCode Insiders / VSCodium support — only stable `code` is installed.
- Remote workspaces (`vscode-remote://`, `vscode-vfs://`) — single-machine setup.
- A keybinding — owned by the user's `hypr/` config (per CLAUDE.md: no patching `config/` that the user can do post-login).
- A ujust recipe / auto-install for existing accounts — one-time manual copy is acceptable.
- Secondary actions (Shift+Enter to open dir in file manager) — one `activate` per elephant entry; a second menu provider would be needed.

## Data source

VSCode writes `~/.config/Code/User/workspaceStorage/<hash>/workspace.json` for every workspace it's ever opened. Each is plain JSON:

```json
{ "folder": "file:///home/oameye/Documents/KeldyshContraction.jl" }
```

`.code-workspace` files appear as:

```json
{ "workspace": { "id": "...", "configPath": "file:///.../foo.code-workspace" } }
```

**Chosen over** `~/.config/Code/User/globalStorage/state.vscdb` (SQLite, what vscode-runner uses) because:

| | sqlite | workspaceStorage |
|---|---|---|
| Package deps | needs `sqlite` pkg added | none (`jq` already installed) |
| Entries | VSCode's capped recent list (~15-30) | every workspace ever opened (144 on current system) |
| Order | VSCode's recency order, for free | sort by `workspace.json` mtime (proxy — updates on open) |
| Stale entries | VSCode prunes | linger after project delete (accepted; one failed `code` call) |

The mtime proxy is sufficient: `workspace.json` is touched when VSCode opens the workspace.

## Components

**One new file.**

### `files/etc/skel/.config/elephant/menus/atomic_hyprland_vscode_projects.lua`

Elephant auto-discovers any `.lua` under `~/.config/elephant/menus/` at service start. File is a standard elephant menu module exposing `Name`, `NamePretty`, `HideFromProviderlist`, and `GetEntries()`.

```lua
-- Dynamic VSCode recent-projects menu for Elephant/Walker.
-- Reads ~/.config/Code/User/workspaceStorage/*/workspace.json in mtime-desc
-- order and exposes each as a "code <path>" launch.
Name = "vscodeprojects"
NamePretty = "VSCode Projects"
HideFromProviderlist = true

local MAX_ENTRIES = 30

local function url_decode(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function shq(s) return "'" .. s:gsub("'", [['\'']]) .. "'" end

function GetEntries()
  local home = os.getenv("HOME") or ""
  local storage = home .. "/.config/Code/User/workspaceStorage"

  local cmd = string.format(
    "find %s -mindepth 2 -maxdepth 2 -name workspace.json -printf '%%T@\\t%%p\\n' 2>/dev/null"
      .. " | sort -rn | cut -f2- | xargs -r jq -r '.folder // .workspace.configPath // empty' 2>/dev/null",
    shq(storage)
  )

  local handle = io.popen(cmd)
  if not handle then return {} end

  local entries, seen = {}, {}

  for uri in handle:lines() do
    if #entries >= MAX_ENTRIES then break end
    if uri:match("^file://") and not seen[uri] then
      seen[uri] = true
      local path = url_decode(uri:sub(8))
      local name = path:match("([^/]+)/*$") or path
      table.insert(entries, {
        Text = name,
        Actions = { activate = "code " .. shq(path) },
      })
    end
  end
  handle:close()
  return entries
end
```

### Design choices inside the Lua

- **Single shell pipeline** via one `io.popen` — mirrors `omarchy_themes.lua`. `find | sort | cut | xargs jq` processes all workspace.json files in one jq invocation, mtime-desc order preserved through `xargs` argument order.
- **`jq -r '.folder // .workspace.configPath // empty'`** handles folder workspaces and `.code-workspace` files in one query. Missing keys fall through to `empty`.
- **Launch with `code '<path>'`** (positional, not `--folder-uri`). Works uniformly for folders, files, and `.code-workspace` files. Shell-quoted via `shq` for paths containing spaces / quotes (single-quote escape via `'\''`).
- **`file://` filter** drops remote URIs silently.
- **`seen` dedupe** — same project may have multiple workspaceStorage hashes over time.
- **`MAX_ENTRIES = 30`** — walker does fuzzy search; more than 30 dilutes signal.
- **Display basename only** via `path:match("([^/]+)/*$")`. The full path is still used for `activate`, so launching is unambiguous even when two projects share a basename (e.g. `/home/user/foo` and `/var/home/user/foo` both activate correctly; Fedora Atomic's `/var/home` bind-mount of `/home` can produce such pairs). If a user routinely sees duplicate names and wants to distinguish them visually, that is a follow-up.

## Non-goals handled by omission

- **No existence check.** If the project has been deleted, `code` fails silently when activated; cheaper than stat-ing every path on every menu open.
- **No preview/icon.** `Text` (basename) alone is fine for the list.
- **No custom sort beyond mtime.** VSCode's in-sqlite recency order is slightly better but not worth the package dep.

## Invocation

Three entry points, in order of how the user will actually reach the menu:

1. **Keybinding in `~/.config/hypr/bindings.conf`** (user-owned, not shipped):
   `bindd = SUPER, V, VSCode projects, exec, walker --provider menus:vscodeprojects`
2. **Ad-hoc shell:** `walker --provider menus:vscodeprojects`.
3. **Not from walker's default provider list** — `HideFromProviderlist = true` keeps it out of generic queries, matching omarchy convention.

## Build & delivery

- **Containerfile/build scripts:** no changes. The static overlay `files/` is copied wholesale by the existing build step.
- **Elephant service:** already runs as a systemd user unit ([files/usr/lib/systemd/user/elephant.service](../../../files/usr/lib/systemd/user/elephant.service)); auto-discovers the new menu at start.
- **Skel caveat:** `/etc/skel/` contents only populate new user accounts. Existing `oameye` home won't pick it up automatically on rebase. One-time post-rebase step:
  ```sh
  mkdir -p ~/.config/elephant/menus
  cp /etc/skel/.config/elephant/menus/atomic_hyprland_vscode_projects.lua ~/.config/elephant/menus/
  systemctl --user restart elephant.service
  ```
- **Testability without rebuild:** copy the Lua to `~/.config/elephant/menus/`, restart elephant user service, run `walker --provider menus:vscodeprojects`.

## Risks

- **Elephant Lua API drift.** Menu format (`Name`, `NamePretty`, `GetEntries`, entry fields `Text` / `Actions.activate`) is taken from elephant v2.21.0 as shipped. If elephant's menu provider API changes in a future source-build bump, this file needs revising. Low likelihood — omarchy's `omarchy_themes.lua` uses the same surface and is stable.
- **`workspace.json` format change.** VSCode has used `.folder` / `.workspace.configPath` for years; unlikely to change silently. Broken parse just yields an empty menu.
- **Arg list too long.** `xargs jq` receives all workspace.json paths as args. With the current 144 files ARG_MAX is nowhere near. `xargs` would split automatically if it ever exceeded.

## Follow-ups (not in scope now)

- If stale entries become a nuisance, add an existence filter (single shell step before `xargs`).
- If the 30 cap is frequently hit, make it a top-level const or drop the cap entirely.
- If remote/codespaces workspaces ever land on this machine, extend the `file://` filter to pass remote URIs through via `code --folder-uri`.
