-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Disable the optional remote-plugin providers. Nothing in this config is a
-- remote plugin, so these only ever show up as :checkhealth warnings about
-- missing `pynvim` / `neovim-ruby-host` / `Neovim::Ext` / `npm i -g neovim`.
-- If you ever install a plugin that needs one, drop its line and install the
-- corresponding host package.
vim.g.loaded_perl_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_node_provider = 0
