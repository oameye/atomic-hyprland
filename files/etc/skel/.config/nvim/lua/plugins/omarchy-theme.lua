-- Load omarchy's per-theme Neovim plugin spec live. Each omarchy theme ships
-- a `neovim.lua` that returns `{ <colorscheme plugin>, LazyVim opts }`; the
-- `current/` symlink points at whichever theme is active, so swapping themes
-- via `omarchy-menu theme` changes which spec is picked up on next nvim
-- launch. No Neovim restart logic needed — colorscheme switches happen at
-- session start.
local theme = vim.fn.expand("~/.config/omarchy/current/theme/neovim.lua")
if vim.fn.filereadable(theme) == 1 then
  return dofile(theme)
end
return {}
