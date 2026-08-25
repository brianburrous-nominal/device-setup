-- catppuccin's `auto_integrations` probes every package manager it knows about,
-- including `vim.pack.get()`. On Neovim 0.12 that call has a side effect: it
-- creates an empty `~/.local/share/nvim/site/pack/core/opt` directory. Because
-- :LazyHealth does `Lazy! load all`, catppuccin loads even though it isn't the
-- active colorscheme, the directory gets recreated on every health run, and
-- both lazy.nvim ("found existing packages") and vim.pack ("lockfile is
-- absent, plugin directory is present") then warn about it.
--
-- LazyVim already declares the integrations it wants explicitly, so turning the
-- auto-detection off costs nothing here.
return {
  {
    "catppuccin/nvim",
    opts = { auto_integrations = false },
  },
}
