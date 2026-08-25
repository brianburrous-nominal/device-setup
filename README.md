# device-setup

Bootstrap for a macOS dev machine, plus an `nvim/` overlay it copies over the
LazyVim starter.

On a machine with nothing on it, this is the whole command:

```sh
curl -fsSL https://raw.githubusercontent.com/brianburrous-nominal/device-setup/main/bootstrap.sh | bash
```

From then on it's `apply`, from anywhere.

Three pieces, with a clear division of labour:

| | |
|---|---|
| `bootstrap.sh` | gets the repo onto a bare machine: Xcode Command Line Tools, then the clone. Curled, because it runs before the repo exists. |
| `setup.sh` | installs what can't install itself — Homebrew, Oh My Zsh, rustup, the LazyVim starter — and needs sudo. Ends with the identity step. |
| `bin/apply` | reconciles a machine that already exists. No sudo, no prompts, cheap when there's nothing to do. |

`bootstrap.sh` exists because of a bootstrapping problem `setup.sh` can't solve
from inside the repo: `/usr/bin/git` on a bare Mac is a stub that opens a GUI
dialog and fails, so there's no way to clone anything until the Command Line
Tools are installed. It installs them headlessly — no dialog to click — clones,
and hands off. It needs nothing but what macOS already ships, and is bash-3.2
clean, because Homebrew's newer bash doesn't exist yet when it runs.

All three are safe to re-run: every step checks for an existing install first,
an existing checkout is updated rather than re-cloned, and every line added to a
shell config is added only once.

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

Nothing is needed for `trash` — macOS 15 added `/usr/bin/trash`, which is why
Homebrew's `trash` and `macos-trash` formulae are both keg-only now.

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
| `lib/identity.sh` | SSH key, GitHub auth, git identity. Interactive; not used by `apply` |
| `bootstrap.sh` | Command Line Tools + clone, for a machine without this repo |

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
| `bin/*` | `~/.local/bin/*` | standalone scripts — `apply`, `identity`, `mdget`, `netif`, `nomprofile` |
| `ssh/setup.conf` | `~/.ssh/config.d/setup.conf` | agent + keychain settings, pulled in by an `Include` |

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
curl -fsSL https://raw.githubusercontent.com/brianburrous-nominal/device-setup/main/bootstrap.sh | bash
```

Clone somewhere other than `~/dev/setup` by setting `SETUP_DIR` first.

After that, syncing a shell change is `git pull` — nothing to re-run, the
symlink already points at the updated file. Syncing a *package* change is
`apply`, which does the pull for you.

## Identity — SSH key, GitHub, git

The last step of `setup.sh`, and a command of its own afterwards:

```sh
identity           # every step; each is a no-op if already done
```

It generates an ed25519 key if there isn't one, loads it into the agent with the
passphrase in the macOS keychain, links this repo's `ssh/setup.conf` into
`~/.ssh/config.d/`, runs `gh auth login`, uploads the public key to GitHub, sets
`user.name` / `user.email`, and switches this repo's remote from HTTPS to SSH.

It runs last because it's the only interactive part — everything before it is
unattended, so the prompts are all in one place at the end rather than
scattered through a twenty-minute install. It is deliberately **not** part of
`apply`, whose contract is no sudo and no prompts.

**The git identity is guessed from this repo's own last commit**, not from the
GitHub API. That sounds circular and isn't: it's your repo, you wrote those
commits, and the machine has a full clone of them before this step runs. The
API is the worse source — plenty of accounts expose neither a name nor an
email, and the `@users.noreply.github.com` address that `gh` falls back to
would quietly start a second identity that matches nothing you've authored
before. The guess is only ever a *default*; you confirm it with return.

### `~/.ssh/config`

`ssh/setup.conf` is symlinked to `~/.ssh/config.d/setup.conf` and pulled in by
an `Include` written to the **first line** of `~/.ssh/config`. Both details are
load-bearing, and neither matches the intuition from shell config:

- An `Include` is evaluated inside whatever `Host` block is in scope where it
  appears. Appended to a file ending in a `Host myserver` block, it would apply
  to `myserver` and nothing else — `ssh -vvv` logs the rest as `parse only`.
- ssh keeps the **first** value it obtains for a keyword and ignores every later
  one. That's the opposite of zsh, where the last definition of an alias wins.

So unlike `~/.zshrc.local`, a host block lower down **cannot** override what
`setup.conf` sets. To override one of these for a specific host, put that block
*above* the `Include` line — there's a comment in the generated file saying so.
(`IdentityFile` is the exception: it accumulates rather than being overwritten,
so additional keys elsewhere are additive, with this one tried first.)

## Shell conveniences worth knowing

**`rm` moves to the Trash.** It's a function in `rc.zsh` wrapping
`/usr/bin/trash`, so it's recoverable in Finder with "Put Back". rm's flags are
dropped rather than forwarded — `rm -rf build` still works, because `trash`
needs neither `-r` (a directory moves whole) nor `-f` (it never prompts), and
would otherwise reject `-rf` as an unrecognized argument. Interactive shells
only: scripts, subprocesses, and `command rm` all still get the real `rm`. Use
`command rm` when you mean it — something too big for the Trash volume, or a
path that has to be gone now.

**`mdget <url>`** fetches a page as markdown via the r.jina.ai reader proxy —
nav, ads and script tags stripped. Good for reading docs in the terminal
(`mdget url | bat -l md`) and for piping a page into an LLM without 200KB of
markup around it. Anonymous requests are blocked by ASN on some networks, AT&T
included, so put a free key from <https://jina.ai/api-dashboard/> in
`~/.zshrc.local` as `export JINA_API_KEY=...`.

**`netif`** is an interactive viewer and editor for macOS network interfaces —
an fzf list of every device with its service, IPv4, mask, config method and link
state, and a detail view per interface. `enter` copies a field, `ctrl-e` edits
the rows marked `+`, `ctrl-d` puts a service back on DHCP. Edits go through
`networksetup`, so they're persistent and need sudo. Needs `fzf` and `gum`, both
already declared in `lib/packages.sh`.

It re-invokes itself to render the preview pane, resolving its own path with
`${0:A}` — which resolves symlinks, so it finds the repo copy rather than the
`~/.local/bin` symlink and keeps working under the link.

**`add_path`** is how `rc.zsh` builds `PATH`: prepend, but only if the directory
exists and isn't already there. Plain `PATH="$dir:$PATH"` lines duplicate every
entry when the file is sourced twice, which a nested shell does routinely.
`typeset -U path` alongside it cleans duplicates that arrived in the inherited
environment, keeping the first occurrence so precedence survives.

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
