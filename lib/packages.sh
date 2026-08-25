# packages.sh — the declarative package registry. The single source of truth
# for what should be installed on this machine.
#
# Three different things source this file, which is the entire point:
#
#   setup.sh    bootstraps a bare machine, then installs whatever is missing
#   bin/apply   reconciles a machine that already exists — the one you run
#               from then on
#   zsh/rc.zsh  notices at shell startup that something declared here isn't
#               installed, and says "run apply"
#
# Declaration is separated from installation. Sourcing this file only *probes*:
# it never installs, never touches the network, and never forks a process.
# Every probe is a `command -v` or a `[[ -e ]]` — both shell builtins — so an
# interactive shell can afford to run all of them on every startup. The install
# half lives in lib/reconcile.sh and runs only from setup.sh and apply.
#
# That split is what buys drift detection. Adding a tool is one line here; every
# other machine that pulls the repo says so on its next shell, instead of
# silently lacking it until someone remembers to re-run the installer.
#
# Must stay valid in BOTH bash and zsh. Quote every expansion, and iterate
# arrays with `for x in "${arr[@]}"` rather than indexing — zsh indexes from 1.

[[ -n "${SETUP_PACKAGES_SOURCED:-}" ]] && return 0
SETUP_PACKAGES_SOURCED=1

MISSING_BREW_FORMULAE=()
MISSING_BREW_CASKS=()
MISSING_UV_TOOLS=()
MISSING_CARGO_CRATES=()
MISSING_BREW_TAPS=()
SETUP_DECLARED_COUNT=0

# Homebrew's prefix without forking `brew --prefix`. .zprofile exports
# HOMEBREW_PREFIX for login shells; the fallback covers everything else.
SETUP_BREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"

# A probe is a command name, or — when the command name would find something
# other than what we mean (a /usr/bin copy of git, a font cask with no binary
# at all) — an absolute path to test for instead.
#
# Two implementations because this runs on every shell startup and the cost is
# not a rounding error: 27 `command -v` calls measure ~3.5ms, while zsh's
# $commands hash does the same lookups in ~0.04ms. bash parses the zsh branch
# without executing it, so the file stays valid in both.
#
# $commands also, correctly, does not match shell functions or aliases — a
# function named `bat` shouldn't count as bat being installed.
if [[ -n "${ZSH_VERSION:-}" ]]; then
  pkg_present() {
    case "$1" in
      /*) [[ -e "$1" ]] ;;
      *) (( ${+commands[$1]} )) ;;
    esac
  }
else
  pkg_present() {
    case "$1" in
      /*) [[ -e "$1" ]] ;;
      *) command -v "$1" >/dev/null 2>&1 ;;
    esac
  }
fi

# brew_formula <formula> [probe] [tap] [tap-url]
# probe defaults to the formula name. tap/tap-url are only for formulae that
# aren't in homebrew-core.
brew_formula() {
  local formula="$1" probe="${2:-$1}" tap="${3:-}" tap_url="${4:-}"
  SETUP_DECLARED_COUNT=$((SETUP_DECLARED_COUNT + 1))
  if pkg_present "$probe"; then
    return 0
  fi
  MISSING_BREW_FORMULAE+=("$formula")
  [[ -z "$tap" ]] || MISSING_BREW_TAPS+=("$tap${tap_url:+ $tap_url}")
}

# brew_cask <cask> [probe]
# Casks rarely put anything on PATH, so the default probe is the Caskroom entry
# Homebrew creates for every installed cask.
brew_cask() {
  local cask="$1" probe="${2:-$SETUP_BREW_PREFIX/Caskroom/$1}"
  SETUP_DECLARED_COUNT=$((SETUP_DECLARED_COUNT + 1))
  if pkg_present "$probe"; then
    return 0
  fi
  MISSING_BREW_CASKS+=("$cask")
}

# uv_tool <package> [probe]
uv_tool() {
  local tool="$1" probe="${2:-$1}"
  SETUP_DECLARED_COUNT=$((SETUP_DECLARED_COUNT + 1))
  if pkg_present "$probe"; then
    return 0
  fi
  MISSING_UV_TOOLS+=("$tool")
}

# cargo_crate <crate> <probe>
# The probe is mandatory here: crate name and binary name routinely differ.
cargo_crate() {
  local crate="$1" probe="$2"
  SETUP_DECLARED_COUNT=$((SETUP_DECLARED_COUNT + 1))
  if pkg_present "$probe"; then
    return 0
  fi
  MISSING_CARGO_CRATES+=("$crate")
}

# ── Homebrew formulae ────────────────────────────────────────────────────────
brew_formula uv                # fast Python package/project manager
brew_formula neovim nvim
brew_formula zoxide            # smarter cd
brew_formula ripgrep rg
brew_formula fd                # friendlier find
# Path-probed for the same reason as git below: macOS 26 ships /usr/bin/jq,
# so the bare name resolves on a machine that never got Homebrew's newer one.
brew_formula jq "$SETUP_BREW_PREFIX/bin/jq"
brew_formula eza               # modern ls (see rc.zsh's aliases)
brew_formula atuin             # searchable shell history in SQLite
brew_formula direnv            # per-directory env vars via .envrc
brew_formula gh                # GitHub CLI
# Same: /usr/bin/git always exists. LazyVim wants >= 2.19, which the system
# copy doesn't reliably satisfy, and the brew prefix comes first on PATH.
brew_formula git "$SETUP_BREW_PREFIX/bin/git"
brew_formula fzf               # LazyVim + general fuzzy finding
brew_formula lazygit           # LazyVim's git UI
brew_formula node              # npm-based LSP servers + formatters mason installs
brew_formula pnpm              # fast npm alternative (needs the node above)
brew_formula wget              # mason falls back to it when curl is unavailable
brew_formula ast-grep          # structural search/replace; grug-far.nvim's backend
brew_formula sd                # find-and-replace with plain regex instead of sed's
brew_formula scc               # line/complexity counts per language
brew_formula gum               # prompts/spinners/styling (bin/nomprofile needs it)
brew_formula bat               # syntax-highlighted cat; rgv's preview pane uses it
# Tobi Lütke's experiment-directory manager. Its tap lives in a repo that isn't
# named homebrew-try, so the URL has to be spelled out for `brew tap`.
brew_formula try try tobi/try https://github.com/tobi/try

# ── Homebrew casks ───────────────────────────────────────────────────────────
# LazyVim's icons render as empty boxes without a Nerd Font. Flip
# INSTALL_NERD_FONT=false before running setup.sh to opt out.
if [[ "${INSTALL_NERD_FONT:-true}" == true ]]; then
  brew_cask font-jetbrains-mono-nerd-font
fi

# ── Python CLI tools, via uv ─────────────────────────────────────────────────
# `uv tool install` rather than brew: each gets its own venv under
# ~/.local/share/uv/tools with a shim in ~/.local/bin, and
# `uv tool upgrade --all` updates them without touching project envs.
uv_tool ruff                   # Python linter + formatter
uv_tool jupyterlab jupyter-lab # notebooks; there is no bare `jupyter` shim
uv_tool httpie http            # friendlier curl; provides http/https/httpie

# ── Rust CLI tools, via cargo ────────────────────────────────────────────────
# Crates with no Homebrew formula. `cargo install` puts binaries in
# ~/.cargo/bin, which rc.zsh already has on PATH.
cargo_crate nominal-cli nomctl # Nominal CLI; backs the nomconfig/nomp aliases

SETUP_MISSING_COUNT=$((${#MISSING_BREW_FORMULAE[@]} + ${#MISSING_BREW_CASKS[@]} +
  ${#MISSING_UV_TOOLS[@]} + ${#MISSING_CARGO_CRATES[@]}))

return 0
