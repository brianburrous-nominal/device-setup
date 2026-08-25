#!/usr/bin/env bash
#
# setup-mac.sh — bootstrap a macOS dev environment.
#
# Installs: Homebrew, Oh My Zsh, uv, Neovim + LazyVim, try, zoxide,
#           ripgrep (rg), fd, jq, gum, bat, sd, scc, ruff, httpie, pnpm,
#           JupyterLab, Julia via juliaup, nomctl, and Rust/cargo via rustup.
#
# Shell config lives in zsh/rc.zsh in this repo, symlinked into place. ~/.zshrc
# only ever gets two source lines from us, so Oh My Zsh keeps owning that file
# and this repo stays the source of truth for everything portable.
#
# Also copies this repo's nvim/ overlay over the LazyVim starter. That overlay
# is what makes `:LazyHealth` come back clean; each file explains itself.
#
# Safe to re-run: every step checks for an existing install first, and
# every line added to a shell config is added only once.
#
# Usage:  chmod +x setup-mac.sh && ./setup-mac.sh
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Options — flip these before running if you want to skip something.
# ---------------------------------------------------------------------------
INSTALL_NERD_FONT=true         # LazyVim's icons look broken without one
TRY_PATH_DIR="$HOME/src/tries" # where `try` keeps experiment dirs

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ZSHRC="$HOME/.zshrc"
ZPROFILE="$HOME/.zprofile"
STAMP="$(date +%Y%m%d-%H%M%S)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
BOLD=$'\033[1m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
RESET=$'\033[0m'

step() { printf '\n%s==> %s%s\n' "$BOLD" "$1" "$RESET"; }
ok() { printf '%s  ✓ %s%s\n' "$GREEN" "$1" "$RESET"; }
skip() { printf '  · %s\n' "$1"; }
warn() { printf '%s  ! %s%s\n' "$YELLOW" "$1" "$RESET"; }
die() {
  printf '%s  ✗ %s%s\n' "$RED" "$1" "$RESET" >&2
  exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

# Append a line to a file only if that exact line isn't already there.
append_once() {
  local line="$1" file="$2"
  [[ -f "$file" ]] || touch "$file"
  if grep -qxF -- "$line" "$file"; then
    return 0
  fi
  printf '%s\n' "$line" >>"$file"
}

# Symlink src -> dst, moving anything already at dst out of the way. Symlinks
# rather than copies so edits in this repo are live without a re-run.
link_file() {
  local src="$1" dst="$2" label="${3:-$(basename "$2")}"
  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    skip "$label already linked"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  if [[ -e "$dst" || -L "$dst" ]]; then
    mv "$dst" "$dst.bak-$STAMP"
    warn "$label existed; moved aside to $(basename "$dst").bak-$STAMP"
  fi
  ln -s "$src" "$dst"
  ok "$label linked"
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
[[ "$(uname -s)" == "Darwin" ]] || die "This script is for macOS."

step "Preflight"
echo "  Some steps need your password (Homebrew creates dirs as root)."
sudo -v || die "sudo is required."
# Keep the sudo timestamp alive while the script runs.
while true; do
  sudo -n true
  sleep 60
  kill -0 "$$" 2>/dev/null || exit
done 2>/dev/null &
SUDO_KEEPALIVE=$!
trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null || true' EXIT
ok "sudo cached"

# ---------------------------------------------------------------------------
# 1. Homebrew
# ---------------------------------------------------------------------------
step "Homebrew"
if have brew; then
  skip "already installed ($(brew --version | head -1))"
else
  # NONINTERACTIVE skips the "press RETURN to continue" prompt.
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ok "installed"
fi

# Put brew on PATH for the rest of this script and for future shells.
if [[ -x /opt/homebrew/bin/brew ]]; then
  BREW_BIN=/opt/homebrew/bin/brew # Apple Silicon
elif [[ -x /usr/local/bin/brew ]]; then
  BREW_BIN=/usr/local/bin/brew # Intel
else
  die "brew not found after install."
fi
eval "$("$BREW_BIN" shellenv)"
append_once "eval \"\$($BREW_BIN shellenv)\"" "$ZPROFILE"
ok "brew on PATH (prefix: $(brew --prefix))"

# ---------------------------------------------------------------------------
# 2. Oh My Zsh
#    Done BEFORE we write to .zshrc: the installer replaces .zshrc with its
#    own template and moves the old one to .zshrc.pre-oh-my-zsh.
# ---------------------------------------------------------------------------
step "Oh My Zsh"
if [[ -d "$HOME/.oh-my-zsh" ]]; then
  skip "already installed"
  OMZ_BACKED_UP=""
else
  [[ -f "$ZSHRC" ]] && HAD_ZSHRC=yes || HAD_ZSHRC=no
  # RUNZSH=no  -> don't drop us into a new shell and halt this script
  # CHSH=no    -> don't change the login shell (macOS already defaults to zsh)
  RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    "" --unattended
  ok "installed"
  if [[ "$HAD_ZSHRC" == "yes" ]]; then
    OMZ_BACKED_UP="$(ls -t "$HOME"/.zshrc.pre-oh-my-zsh* 2>/dev/null | head -1 || true)"
    [[ -n "$OMZ_BACKED_UP" ]] && warn "your old .zshrc was moved to $OMZ_BACKED_UP"
  else
    OMZ_BACKED_UP=""
  fi
fi

# ---------------------------------------------------------------------------
# 3. CLI tools via Homebrew
# ---------------------------------------------------------------------------
step "CLI tools"
BREW_FORMULAE=(
  uv # fast Python package/project manager
  neovim
  zoxide   # smarter cd
  ripgrep  # rg
  fd       # friendlier find
  jq       # JSON wrangling
  eza      # modern ls (see aliases below)
  atuin    # searchable shell history in SQLite
  direnv   # per-directory env vars via .envrc
  gh       # GitHub CLI
  git      # LazyVim wants >= 2.19
  fzf      # LazyVim + general fuzzy finding
  lazygit  # LazyVim's git UI
  node     # npm-based LSP servers + formatters that mason installs
  pnpm     # fast npm alternative (needs the node above)
  wget     # mason falls back to it when curl is unavailable
  ast-grep # structural search/replace backend for grug-far.nvim
  sd       # find-and-replace with plain regex syntax instead of sed's
  scc      # line/complexity counts per language
  gum      # prompts/spinners/styling for shell scripts (bin/nomprofile needs it)
  bat      # syntax-highlighted cat; rgv's preview pane uses it
)
for f in "${BREW_FORMULAE[@]}"; do
  if brew list --formula "$f" >/dev/null 2>&1; then
    skip "$f already installed"
  else
    brew install "$f" && ok "$f"
  fi
done

if [[ "$INSTALL_NERD_FONT" == true ]]; then
  if brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1; then
    skip "nerd font already installed"
  else
    brew install --cask font-jetbrains-mono-nerd-font && ok "JetBrainsMono Nerd Font"
  fi
  # Installing the font is only half the job -- the terminal has to be pointed
  # at it. Print this on every run, not just on first install: a re-run takes
  # the "already installed" branch, where the reminder would never show.
  # Recent Nerd Fonts releases register short family names, so the terminal's
  # font picker lists "JetBrainsMono NFM", not "JetBrains Mono Nerd Font".
  # NFM is the Mono variant: it keeps icon glyphs to one cell, which is what
  # stops LazyVim's statusline and file tree from drifting out of alignment.
  warn "set your terminal font to 'JetBrainsMono NFM' or LazyVim icons render as boxes"
fi

# ---------------------------------------------------------------------------
# 3b. Python CLI tools via uv
#     `uv tool install` rather than brew: each tool gets its own isolated venv
#     under ~/.local/share/uv/tools with a shim in ~/.local/bin, and
#     `uv tool upgrade --all` updates them without touching project envs.
# ---------------------------------------------------------------------------
step "Python CLI tools (uv)"
# uv drops its shims here. Future shells get this from .zshrc below; export it
# now so the rest of this script (the summary block) can see the tools too.
export PATH="$HOME/.local/bin:$PATH"
UV_TOOLS=(
  ruff       # Python linter + formatter
  jupyterlab # notebooks; launches as `jupyter-lab`, see note below
  httpie     # friendlier curl; provides http/https/httpie
)
for t in "${UV_TOOLS[@]}"; do
  if uv tool list 2>/dev/null | grep -q "^$t "; then
    skip "$t already installed"
  else
    uv tool install "$t" && ok "$t"
  fi
done

# `uv tool install` only shims the named package's own entry points, and the
# bare `jupyter` command belongs to jupyter-core (a dependency). So the habitual
# `jupyter lab` isn't available -- use `jupyter-lab`. Installing jupyter-core as
# its own tool would shim `jupyter`, but in a separate venv that can't see
# JupyterLab, which is worse.
if uv tool list 2>/dev/null | grep -q "^jupyterlab "; then
  warn "launch notebooks with 'jupyter-lab' (no bare 'jupyter' shim; see comment above)"
fi

# ---------------------------------------------------------------------------
# 4. try (Tobi Lütke's experiment-directory manager)
# ---------------------------------------------------------------------------
step "try"
if have try; then
  skip "already installed"
else
  brew tap tobi/try https://github.com/tobi/try
  brew install try
  ok "installed"
fi
mkdir -p "$TRY_PATH_DIR"

# ---------------------------------------------------------------------------
# 5. Rust toolchain (cargo) via rustup
#    rustup rather than `brew install rust` so you get toolchain management,
#    rustc/clippy/rustfmt, and `rustup update`.
# ---------------------------------------------------------------------------
step "Rust / cargo"
if have cargo || [[ -x "$HOME/.cargo/bin/cargo" ]]; then
  skip "already installed"
else
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs |
    sh -s -- -y --no-modify-path
  ok "installed"
fi
# shellcheck source=/dev/null
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# ---------------------------------------------------------------------------
# 5a. Rust CLI tools via cargo
#     Crates with no Homebrew formula. `cargo install` puts binaries in
#     ~/.cargo/bin, which zsh/rc.zsh already has on PATH.
# ---------------------------------------------------------------------------
step "Rust CLI tools (cargo)"
# crate name -> binary it provides, since the two differ for nominal-cli.
CARGO_TOOLS=(
  "nominal-cli:nomctl" # Nominal CLI; backs the nomconfig/nomp aliases
)
for entry in "${CARGO_TOOLS[@]}"; do
  crate="${entry%%:*}" bin="${entry##*:}"
  if have "$bin"; then
    skip "$bin already installed"
  else
    cargo install "$crate" && ok "$bin (from $crate)"
  fi
done

# ---------------------------------------------------------------------------
# 5b. Julia via juliaup
#     juliaup rather than the `julia` formula for the same reason we use rustup
#     over `brew install rust`: it multiplexes versions and `juliaup update`
#     handles upgrades. The two brew formulae conflict -- both ship a `julia`
#     binary -- so only one may be installed.
# ---------------------------------------------------------------------------
step "Julia / juliaup"
if brew list --formula juliaup >/dev/null 2>&1; then
  skip "juliaup already installed"
elif brew list --formula julia >/dev/null 2>&1; then
  warn "the 'julia' formula is installed and conflicts with juliaup; skipping"
else
  brew install juliaup && ok "juliaup installed"
fi
# juliaup ships no Julia of its own; `add release` fetches the current stable.
# Version numbers only ever appear in the table's rows, never its header, so a
# digit is a reliable "some channel is installed" test.
if have juliaup; then
  if juliaup status 2>/dev/null | grep -qE '[0-9]+\.[0-9]'; then
    skip "a Julia channel is already installed"
  else
    juliaup add release && ok "Julia release channel"
  fi
fi

# ---------------------------------------------------------------------------
# 6. LazyVim
# ---------------------------------------------------------------------------
step "LazyVim"
if [[ -f "$HOME/.config/nvim/lua/config/lazy.lua" ]]; then
  skip "LazyVim config already present at ~/.config/nvim"
  FRESH_NVIM=no
else
  FRESH_NVIM=yes
  # Back up anything already there rather than clobbering it.
  for d in "$HOME/.config/nvim" "$HOME/.local/share/nvim" \
    "$HOME/.local/state/nvim" "$HOME/.cache/nvim"; do
    if [[ -e "$d" ]]; then
      mv "$d" "$d.bak-$STAMP"
      warn "moved $d -> $d.bak-$STAMP"
    fi
  done
  mkdir -p "$HOME/.config"
  git clone https://github.com/LazyVim/starter "$HOME/.config/nvim"
  rm -rf "$HOME/.config/nvim/.git" # so you can put it in your own dotfiles repo
  ok "starter cloned"
fi

# ---------------------------------------------------------------------------
# 6b. Neovim config overlay
#     The LazyVim starter on its own produces a handful of :LazyHealth
#     warnings -- unused remote-plugin providers, a luarocks bootstrap nothing
#     needs, a fish formatter with no fish, and a catppuccin option that keeps
#     recreating an empty site/pack/core directory. The files under nvim/ fix
#     those; each one carries a comment explaining why it exists.
#
#     Reapplied on every run so this repo stays the source of truth. Anything
#     already on disk that differs is backed up rather than clobbered.
# ---------------------------------------------------------------------------
step "Neovim config overlay"
if [[ -d "$SCRIPT_DIR/nvim" ]]; then
  while IFS= read -r src; do
    rel="${src#"$SCRIPT_DIR/nvim/"}"
    dst="$HOME/.config/nvim/$rel"
    if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
      skip "$rel already current"
      continue
    fi
    mkdir -p "$(dirname "$dst")"
    if [[ -f "$dst" ]]; then
      cp "$dst" "$dst.bak-$STAMP"
      warn "$rel differed; your copy saved as $rel.bak-$STAMP"
    fi
    cp "$src" "$dst"
    ok "$rel"
  done < <(find "$SCRIPT_DIR/nvim" -type f ! -name '.DS_Store')
else
  warn "no nvim/ overlay found next to this script ($SCRIPT_DIR)"
fi

# Pre-install plugins so the first real launch is fast. Non-fatal if it fails.
# Only on a fresh install -- a re-run shouldn't silently update every plugin.
if [[ "$FRESH_NVIM" == yes ]]; then
  echo "  syncing plugins (this takes a minute)..."
  nvim --headless "+Lazy! sync" +qa 2>/dev/null || warn "headless sync skipped; just run nvim"
fi

# ---------------------------------------------------------------------------
# 7. Shell config
#     ~/.zshrc gets exactly two source lines from us and nothing else. Oh My Zsh
#     keeps owning that file (its installer rewrites it, and it holds the theme
#     and plugin settings), while everything portable -- PATH, aliases, tool
#     init, functions -- lives in this repo's zsh/rc.zsh.
#
#     The source line goes through ~/.config/zsh/rc.zsh rather than pointing at
#     the repo directly, so .zshrc doesn't care where you cloned this.
#
#     Sourced near the end of .zshrc, which the eza aliases depend on: OMZ
#     defines its own `ls`, and the last definition wins.
# ---------------------------------------------------------------------------
step "Shell config"
if [[ -f "$SCRIPT_DIR/zsh/rc.zsh" ]]; then
  link_file "$SCRIPT_DIR/zsh/rc.zsh" "$HOME/.config/zsh/rc.zsh" "rc.zsh"
else
  warn "no zsh/rc.zsh found next to this script ($SCRIPT_DIR)"
fi

append_once '' "$ZSHRC"
append_once '# --- added by setup-mac.sh ---' "$ZSHRC"
append_once '[[ -f "$HOME/.config/zsh/rc.zsh" ]] && source "$HOME/.config/zsh/rc.zsh"' "$ZSHRC"
# Machine-specific values and secrets go here. Never tracked; sourced last so
# it can override anything rc.zsh set.
append_once '[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"' "$ZSHRC"
ok "done"

# ---------------------------------------------------------------------------
# 7b. Scripts from bin/
#     Symlinked into ~/.local/bin (already on PATH via rc.zsh) so they travel
#     with this repo instead of living only on the machine they were written on.
# ---------------------------------------------------------------------------
step "Scripts from bin/"
if [[ -d "$SCRIPT_DIR/bin" ]]; then
  shopt -s nullglob
  for src in "$SCRIPT_DIR"/bin/*; do
    [[ -f "$src" ]] || continue
    chmod +x "$src"
    link_file "$src" "$HOME/.local/bin/$(basename "$src")" "$(basename "$src")"
  done
  shopt -u nullglob
else
  skip "no bin/ directory"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
step "Finished"
cat <<EOF

  Installed:
    brew      $(brew --version | head -1 | awk '{print $2}')
    uv        $(uv --version 2>/dev/null | awk '{print $2}')
    nvim      $(nvim --version 2>/dev/null | head -1 | awk '{print $2}')
    cargo     $(cargo --version 2>/dev/null | awk '{print $2}')
    rg        $(rg --version 2>/dev/null | head -1 | awk '{print $2}')
    fd        $(fd --version 2>/dev/null | awk '{print $2}')
    jq        $(jq --version 2>/dev/null)
    zoxide    $(zoxide --version 2>/dev/null | awk '{print $2}')
    eza       $(eza --version 2>/dev/null | sed -n 2p | awk '{print $1}')
    atuin     $(atuin --version 2>/dev/null | awk '{print $2}')
    direnv    $(direnv version 2>/dev/null)
    gh        $(gh --version 2>/dev/null | head -1 | awk '{print $3}')
    gum       $(gum --version 2>/dev/null | awk '{print $3}')
    bat       $(bat --version 2>/dev/null | awk '{print $2}')
    sd        $(sd --version 2>/dev/null | awk '{print $2}')
    scc       $(scc --version 2>/dev/null | awk '{print $3}')
    httpie    $(http --version 2>/dev/null)
    nomctl    $(nomctl --version 2>/dev/null | awk '{print $2}')
    julia     $(julia --version 2>/dev/null | awk '{print $3}')
    jupyter   $(jupyter-lab --version 2>/dev/null)
    pnpm      $(pnpm --version 2>/dev/null)
    ruff      $(ruff --version 2>/dev/null | awk '{print $2}')
    try       $(try --version 2>/dev/null | head -1 || echo "installed")

  Next:
    1. Set your terminal font to 'JetBrainsMono NFM' (iTerm2: Settings >
       Profiles > Text > Font). Nothing else here installs it for you, and
       without it every LazyVim icon renders as an empty box.
    2. exec zsh              # or open a new terminal
    3. atuin import auto     # pull your existing shell history in
    4. gh auth login         # authenticate the GitHub CLI
    5. nomp                  # set up a nomctl profile (needs a token)
    6. nvim                  # then :LazyHealth to check the setup
    7. ls / lsa / lt / lta, z <dir> to jump, try <name> for a scratch dir
       rgv <pattern> to search-and-edit, jupyter-lab for notebooks

  Shell config is zsh/rc.zsh in this repo, symlinked to ~/.config/zsh/rc.zsh.
  Edit it there and the change is live next shell -- then commit and pull it
  down on your other machines. Machine-specific or secret values belong in
  ~/.zshrc.local, which is sourced after it and never tracked.

EOF

if [[ -n "${OMZ_BACKED_UP:-}" ]]; then
  warn "Oh My Zsh replaced your .zshrc. Anything custom you had before is in:"
  printf '      %s\n' "$OMZ_BACKED_UP"
  printf '      Merge what you want back into ~/.zshrc.\n'
fi
