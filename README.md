# device-setup

Bootstrap script for a macOS dev machine. One file does the work — `setup.sh` —
plus an `nvim/` overlay it copies over the LazyVim starter.

```sh
git clone git@github.com:<you>/device-setup.git
cd device-setup
./setup.sh
```

Safe to re-run. Every step checks for an existing install first, and every line
added to a shell config is added only once.

## What it installs

| | |
|---|---|
| Package managers | Homebrew, uv, rustup (cargo) |
| Shell | Oh My Zsh, atuin, zoxide, direnv, fzf |
| CLI | ripgrep, fd, jq, eza, gh, git, lazygit, wget, ast-grep |
| Editor | Neovim + LazyVim, node (for mason's npm-based LSP servers) |
| Other | `try` for scratch directories, JetBrainsMono Nerd Font |

It also writes PATH exports, `eza` aliases (`ls` / `lsa` / `lt` / `lta` / `ll`),
and tool init lines to `~/.zshrc`.

## The nvim/ overlay

The LazyVim starter on its own leaves a handful of `:LazyHealth` complaints.
`setup.sh` copies these four files over the top to clear them:

| File | Why |
|---|---|
| `lua/config/options.lua` | Disables the perl / python3 / ruby / node remote-plugin providers. Nothing here is a remote plugin, so they only ever surfaced as "install pynvim" warnings. |
| `lua/config/lazy.lua` | `rocks.enabled = false`. No plugin needs luarocks, so the hererocks bootstrap is skipped instead of sitting there half-installed and erroring. |
| `lua/plugins/conform.lua` | Drops LazyVim's `fish → fish_indent` mapping, rather than installing fish for a shell that isn't used. |
| `lua/plugins/catppuccin.lua` | `auto_integrations = false`. Catppuccin's plugin auto-detection calls `vim.pack.get()`, which on Neovim 0.12 creates an empty `site/pack/core/opt` directory as a side effect. Since `:LazyHealth` runs `Lazy! load all`, that fired on every health check and made **both** lazy.nvim and vim.pack warn. LazyVim already declares its catppuccin integrations explicitly, so nothing is lost. |

The overlay is reapplied on every run so this repo stays the source of truth.
Any file on disk that differs from the repo's copy is saved as
`<name>.bak-<timestamp>` before being replaced — your edits are never dropped
silently.

## One manual step

Installing a Nerd Font doesn't point your terminal at it, and that's the single
most common reason LazyVim renders as a grid of empty boxes.

Set your terminal font to **JetBrainsMono Nerd Font Mono**
(iTerm2: Settings → Profiles → Text → Font).

Pick the **Mono** variant: it constrains icon glyphs to a single cell, which is
what keeps the statusline and file tree aligned. `JetBrainsMonoNL Nerd Font
Mono` is the same thing without programming ligatures, if you prefer to see
`!=` and `->` as literal characters.

## Known remaining health warnings

These are expected and not worth chasing:

- **snacks.image** — iTerm2 doesn't implement the kitty graphics protocol, so
  inline images can't work regardless of what's installed. Switch to Ghostty,
  WezTerm, or Kitty if you want them.
- **mason** — Go, PHP, Composer, Java, Julia, luarocks "not available". Only
  matters if you install a mason package for one of those languages.
- **blink.cmp** and **which-key** — purely informational. which-key's own
  output says not to report its overlap warnings.
