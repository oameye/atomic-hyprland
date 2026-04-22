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
