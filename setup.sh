#!/usr/bin/env bash
#
# setup-mac.sh — bootstrap a macOS dev environment.
#
# Installs: Homebrew, Oh My Zsh, uv, Neovim + LazyVim, try, zoxide,
#           ripgrep (rg), fd, jq, and Rust/cargo via rustup.
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
  wget     # mason falls back to it when curl is unavailable
  ast-grep # structural search/replace backend for grug-far.nvim
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
# ---------------------------------------------------------------------------
step "Writing shell config to ~/.zshrc"
append_once '' "$ZSHRC"
append_once '# --- added by setup-mac.sh ---' "$ZSHRC"

# PATH and environment
append_once 'export PATH="$HOME/.local/bin:$PATH"' "$ZSHRC" # claude, pipx, etc.
append_once 'export PATH="$HOME/.cargo/bin:$PATH"' "$ZSHRC"
append_once "export TRY_PATH=\"$TRY_PATH_DIR\"" "$ZSHRC"
append_once 'export EDITOR="nvim"' "$ZSHRC"
append_once 'alias vim="nvim"' "$ZSHRC"

# eza aliases. These come after Oh My Zsh's own `ls` alias, so they win.
#   ls  - grid, dirs first, icons        lsa - same, plus dotfiles
#   lt  - tree, 2 levels deep            lta - same, plus dotfiles
# The tree views skip .git and node_modules so `lta` stays readable.
append_once "alias ls='eza --icons --group-directories-first'" "$ZSHRC"
append_once "alias lsa='eza --icons --group-directories-first --all'" "$ZSHRC"
append_once "alias lt='eza --icons --group-directories-first --tree --level=2 --ignore-glob=\".git|node_modules\"'" "$ZSHRC"
append_once "alias lta='eza --icons --group-directories-first --tree --level=2 --all --ignore-glob=\".git|node_modules\"'" "$ZSHRC"
append_once "alias ll='eza --icons --group-directories-first --long --git'" "$ZSHRC"

# Tool init. Order matters: fzf binds Ctrl-R, then atuin takes it over.
# Drop the atuin line if you'd rather keep fzf's history search.
append_once 'source <(fzf --zsh)' "$ZSHRC"
append_once 'export FZF_DEFAULT_COMMAND="fd --type f --hidden --exclude .git"' "$ZSHRC"
append_once 'export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"' "$ZSHRC"
append_once 'eval "$(zoxide init zsh)"' "$ZSHRC"
append_once 'eval "$(direnv hook zsh)"' "$ZSHRC"
append_once 'eval "$(atuin init zsh)"' "$ZSHRC"
append_once 'eval "$(try init)"' "$ZSHRC"
ok "done"

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
    try       $(try --version 2>/dev/null | head -1 || echo "installed")

  Next:
    1. Set your terminal font to 'JetBrainsMono NFM' (iTerm2: Settings >
       Profiles > Text > Font). Nothing else here installs it for you, and
       without it every LazyVim icon renders as an empty box.
    2. exec zsh              # or open a new terminal
    3. atuin import auto     # pull your existing shell history in
    4. gh auth login         # authenticate the GitHub CLI
    5. nvim                  # then :LazyHealth to check the setup
    6. ls / lsa / lt / lta, z <dir> to jump, try <name> for a scratch dir

EOF

if [[ -n "${OMZ_BACKED_UP:-}" ]]; then
  warn "Oh My Zsh replaced your .zshrc. Anything custom you had before is in:"
  printf '      %s\n' "$OMZ_BACKED_UP"
  printf '      Merge what you want back into ~/.zshrc.\n'
fi
