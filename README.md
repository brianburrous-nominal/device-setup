# device-setup

Bootstrap for a macOS dev machine, plus an `nvim/` overlay it copies over the
LazyVim starter.

Two commands, with a clear division of labour:

```sh
git clone git@github.com:<you>/device-setup.git
cd device-setup
./setup.sh     # once, on a machine that has nothing
apply          # from then on, from anywhere
```

`setup.sh` installs the things that can't install themselves — Homebrew, Oh My
Zsh, rustup, the LazyVim starter — and needs sudo to do it. `apply` pulls this
repo and installs anything newly declared. No sudo, no prompts, cheap when
there's nothing to do. It's `bin/apply`, symlinked into `~/.local/bin`.

Both are safe to re-run: every step checks for an existing install first, and
every line added to a shell config is added only once.

## What it installs

| | |
|---|---|
| Package managers | Homebrew, uv, rustup (cargo), pnpm, juliaup |
| Shell | Oh My Zsh, atuin, zoxide, direnv, fzf |
| CLI | ripgrep, fd, jq, eza, bat, sd, scc, gh, git, lazygit, wget, ast-grep, gum |
| Python | ruff, JupyterLab, httpie — installed with `uv tool install` (isolated venv, shim in `~/.local/bin`) |
| Julia | current stable release, via `juliaup add release` |
| Editor | Neovim + LazyVim, node (for mason's npm-based LSP servers) |
| Nominal | `nomctl` (the `nominal-cli` crate, via `cargo install`) |
| Other | `try` for scratch directories, JetBrainsMono Nerd Font |

It also links the shell config and the scripts in `bin/` into place — see
[Shell config](#shell-config) below.

## Adding a tool

One line in `lib/packages.sh`:

```sh
brew_formula hyperfine        # benchmarking
uv_tool     pre-commit
cargo_crate some-crate  itsbinary
```

Commit it, and every other machine says so at its next shell prompt:

```
* 1 declared package(s) not installed — run apply
```

That notice is the point of the layout. `lib/packages.sh` is the single list of
what should be installed, and three different things read it:

| | |
|---|---|
| `setup.sh` | bootstraps a bare machine, then installs whatever is missing |
| `bin/apply` | reconciles a machine that already exists |
| `zsh/rc.zsh` | notices at startup that something isn't installed, and says so |

**Declaration is separated from installation.** Sourcing `lib/packages.sh` only
*probes* — it never installs, never touches the network, and never forks a
process. Every probe is a shell builtin (zsh's `$commands` hash, or `[[ -e ]]`
for the handful of things it can't see), so the whole file costs about 0.5ms and
an interactive shell can afford to run it on every startup. The install half
lives in `lib/reconcile.sh` and runs only from `setup.sh` and `apply`.

Without that split, an installer that only ever ran once is the only record of
what a machine should have — so a tool added on the laptop is just quietly
absent on the desktop until someone remembers to re-run it.

| File | Holds |
|---|---|
| `lib/packages.sh` | what should be installed. Declaration only; bash- and zsh-safe |
| `lib/reconcile.sh` | how to install it, plus the symlinks and the nvim overlay |
| `lib/common.sh` | output helpers shared by `setup.sh` and `apply` |

A few tools aren't one-line declarations and live in `lib/reconcile.sh` instead:
`juliaup`, because "installed" has two levels there — the tool, then a channel.

### Probes

The default probe for a package is its own name. Two entries override it with an
absolute path, because macOS ships its own copy under `/usr/bin` and the bare
name would resolve on a machine that never got Homebrew's newer one:

```sh
brew_formula git "$SETUP_BREW_PREFIX/bin/git"   # /usr/bin/git always exists
brew_formula jq  "$SETUP_BREW_PREFIX/bin/jq"    # macOS 26 ships jq 1.7.1-apple
```

Casks get the same treatment by default — they rarely put anything on `PATH`, so
the probe is the Caskroom entry Homebrew creates for every installed cask.

## apply

```sh
apply              # pull, then install anything declared but missing
apply -u           # ...and upgrade what's already installed first
apply --skip-pull  # leave git alone
```

`apply` re-execs itself after the pull. Without that, a run that fetched a
change to `apply`, `lib/packages.sh`, or `lib/reconcile.sh` would go on using
the code that was on disk when it started, and the change wouldn't take effect
until the *next* run.

A failed pull — dirty tree, unreachable remote — is a warning, not an abort. It
still reconciles against the checkout you have.

## Shell config

Shell config is tracked here and symlinked into place, so it syncs across
machines by `git pull` rather than by copy-paste.

| Path in repo | Symlinked to | Holds |
|---|---|---|
| `zsh/rc.zsh` | `~/.config/zsh/rc.zsh` | PATH, exports, aliases, tool init, functions (`rgv`) |
| `bin/*` | `~/.local/bin/*` | standalone scripts, e.g. `nomprofile` |

`setup.sh` adds exactly two lines to `~/.zshrc` and nothing else:

```sh
[[ -f "$HOME/.config/zsh/rc.zsh" ]] && source "$HOME/.config/zsh/rc.zsh"
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
```

Three deliberate choices there:

- **`.zshrc` itself isn't tracked.** Oh My Zsh owns that file — its installer
  rewrites it on a fresh machine, and it carries the theme and plugin settings.
  Tracking it would mean vendoring OMZ's template and re-merging on every
  upstream change.
- **Sourced near the end**, after OMZ has loaded. The `eza` aliases need to
  come after OMZ's own `ls` alias, since the last definition wins.
- **Via `~/.config/zsh/`, not the repo path.** `.zshrc` doesn't need to know
  where you cloned this, so the same file works on a machine that keeps it
  somewhere else.

Symlinks rather than copies: edits to `zsh/rc.zsh` are live in the next shell,
and they show up in `git status` immediately instead of drifting out of sync
with the repo.

### `~/.zshrc.local`

Anything machine-specific or secret goes here. It's untracked, and sourced
last so it can override anything `rc.zsh` set. Use it for API tokens, per-host
PATH entries, work-vs-personal differences — anything you don't want in a
GitHub repo.

### Adding to another machine

```sh
git clone <this repo> ~/dev/setup && cd ~/dev/setup && ./setup.sh
```

After that, syncing a shell change is `git pull` — nothing to re-run, the
symlink already points at the updated file. Syncing a *package* change is
`apply`, which does the pull for you.

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

## Launching JupyterLab

Use `jupyter-lab`, not `jupyter lab`. `uv tool install` only creates shims for
the entry points of the package you named, and the bare `jupyter` dispatcher
belongs to `jupyter-core` — a dependency — so it never gets one. Installing
`jupyter-core` separately would shim `jupyter`, but into its own venv with no
view of JupyterLab.

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
- **mason** — Go, PHP, Composer, Java, luarocks "not available". Only
  matters if you install a mason package for one of those languages.
  (Julia used to be on this list; `juliaup` now satisfies it.)
- **blink.cmp** and **which-key** — purely informational. which-key's own
  output says not to report its overlap warnings.
