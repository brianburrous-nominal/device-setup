#!/usr/bin/env bash
#
# setup.sh — bootstrap a macOS dev environment from nothing.
#
# Run this once, on a bare machine. Run `apply` from then on.
#
#   setup.sh   installs the things that can't install themselves — Homebrew,
#              Oh My Zsh, rustup, the LazyVim starter — and needs sudo to do it.
#              Then it hands off to the same reconcile code apply uses.
#   apply      pulls this repo and installs anything newly declared. No sudo,
#              no prompts. bin/apply, symlinked into ~/.local/bin below.
#
# What gets installed is not in this file. It's declared in lib/packages.sh,
# which setup.sh, apply, and the interactive shell all read — so adding one line
# there makes every machine notice on its next shell that it's behind.
#
#   lib/packages.sh   what should be installed (declaration only; never installs)
#   lib/reconcile.sh  how to install it, plus the symlinks and the nvim overlay
#   lib/common.sh     output helpers shared by setup.sh and apply
#
# Shell config lives in zsh/rc.zsh in this repo, symlinked into place. ~/.zshrc
# only ever gets two source lines from us, so Oh My Zsh keeps owning that file
# and this repo stays the source of truth for everything portable.
#
# Safe to re-run: every step checks for an existing install first, and
# every line added to a shell config is added only once.
#
# Usage:  chmod +x setup.sh && ./setup.sh
#
# On a machine that doesn't have this repo yet, don't start here -- start with
# bootstrap.sh, which installs the Xcode Command Line Tools, clones the repo,
# and then runs this script:
#
#   curl -fsSL https://raw.githubusercontent.com/brianburrous-nominal/device-setup/main/bootstrap.sh | bash
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Options — flip these before running if you want to skip something.
# ---------------------------------------------------------------------------
# Read by lib/packages.sh, which declares the font cask, so it has to be set
# before that file is sourced further down.
INSTALL_NERD_FONT=true
TRY_PATH_DIR="$HOME/src/tries" # where `try` keeps experiment dirs

SETUP_REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# step/ok/skip/warn/die, have, append_once, link_file, load_brew, load_cargo,
# and the STAMP every backup in this run is suffixed with.
# shellcheck source=lib/common.sh
source "$SETUP_REPO_DIR/lib/common.sh"

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

# Put brew on PATH for the rest of this script and for future shells. load_brew
# is shared with apply, which needs it because it may run from a context where
# .zprofile never did; it sets BREW_BIN to the path we write out below.
load_brew || die "brew not found after install."
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
# 3. Rust toolchain (cargo) via rustup
#    rustup rather than `brew install rust` so you get toolchain management,
#    rustc/clippy/rustfmt, and `rustup update`.
#
#    Before the package step rather than after it: lib/packages.sh declares
#    cargo crates too, and installing those needs cargo already on PATH.
# ---------------------------------------------------------------------------
step "Rust / cargo"
if have cargo || [[ -x "$HOME/.cargo/bin/cargo" ]]; then
  skip "already installed"
else
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs |
    sh -s -- -y --no-modify-path
  ok "installed"
fi
load_cargo

# ---------------------------------------------------------------------------
# 4. Packages
#    Everything installable by a single package-manager command — brew formulae
#    and casks, uv tools, cargo crates — is declared in lib/packages.sh and
#    installed by lib/reconcile.sh. Nothing about the list lives in this file,
#    which is exactly what lets apply and the interactive shell read the same
#    list without duplicating it.
#
#    Sourcing lib/packages.sh only probes. It works out what's missing and
#    installs nothing; install_missing_packages is what acts on that.
# ---------------------------------------------------------------------------
# shellcheck source=lib/packages.sh
source "$SETUP_REPO_DIR/lib/packages.sh"
# shellcheck source=lib/reconcile.sh
source "$SETUP_REPO_DIR/lib/reconcile.sh"
# shellcheck source=lib/identity.sh
source "$SETUP_REPO_DIR/lib/identity.sh"

install_missing_packages

# `try` keeps its experiment dirs here; rc.zsh exports the same path as
# TRY_PATH. Move one and you have to move the other.
mkdir -p "$TRY_PATH_DIR"

# Installing the font is only half the job -- the terminal has to be pointed
# at it. Print this on every run, not just on first install: a re-run finds the
# cask already there, and the reminder would never show.
# Recent Nerd Fonts releases register short family names, so the terminal's
# font picker lists "JetBrainsMono NFM", not "JetBrains Mono Nerd Font".
# NFM is the Mono variant: it keeps icon glyphs to one cell, which is what
# stops LazyVim's statusline and file tree from drifting out of alignment.
if [[ "$INSTALL_NERD_FONT" == true ]]; then
  warn "set your terminal font to 'JetBrainsMono NFM' or LazyVim icons render as boxes"
fi

# `uv tool install` only shims the named package's own entry points, and the
# bare `jupyter` command belongs to jupyter-core (a dependency). So the habitual
# `jupyter lab` isn't available -- use `jupyter-lab`. Installing jupyter-core as
# its own tool would shim `jupyter`, but in a separate venv that can't see
# JupyterLab, which is worse.
if have jupyter-lab; then
  warn "launch notebooks with 'jupyter-lab' (no bare 'jupyter' shim; see comment above)"
fi

# ---------------------------------------------------------------------------
# 5. Julia via juliaup
#    juliaup rather than the `julia` formula for the same reason we use rustup
#    over `brew install rust`: it multiplexes versions and `juliaup update`
#    handles upgrades. It lives in lib/reconcile.sh rather than the registry
#    because "installed" has two levels here -- the tool, then a channel -- so
#    it isn't a one-line declaration.
# ---------------------------------------------------------------------------
reconcile_julia

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
# 7. Neovim config overlay
#    The LazyVim starter on its own leaves a handful of :LazyHealth warnings.
#    The files under nvim/ clear them; each carries a comment saying why it
#    exists. Reapplied on every run, backing up anything on disk that differs.
# ---------------------------------------------------------------------------
apply_nvim_overlay

# Pre-install plugins so the first real launch is fast. Non-fatal if it fails.
# Only on a fresh install -- a re-run shouldn't silently update every plugin.
if [[ "$FRESH_NVIM" == yes ]]; then
  echo "  syncing plugins (this takes a minute)..."
  nvim --headless "+Lazy! sync" +qa 2>/dev/null || warn "headless sync skipped; just run nvim"
fi

# ---------------------------------------------------------------------------
# 8. Shell config and bin/ scripts
#    Both are symlinks, so afterwards a `git pull` is enough to pick up a change
#    -- nothing to re-run. `apply` itself lands in ~/.local/bin from bin/ here,
#    which is what makes it a bare word on the next shell.
# ---------------------------------------------------------------------------
link_shell_config
link_repo_bin

# ---------------------------------------------------------------------------
# 9. Identity — SSH key, GitHub auth, git user.name/user.email
#    Last, because it's the only interactive part: everything above can run
#    unattended, and putting the prompts at the end means you can walk away for
#    the long middle. Re-runnable on its own afterwards as `identity`.
# ---------------------------------------------------------------------------
reconcile_identity

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
    4. nomp                  # set up a nomctl profile (needs a token)
    5. nvim                  # then :LazyHealth to check the setup
    6. ls / lsa / lt / lta, z <dir> to jump, try <name> for a scratch dir
       rgv <pattern> to search-and-edit, jupyter-lab for notebooks

  Your SSH key, GitHub login, and git identity are already done -- the step
  above set them up. Re-run just that part any time with \`identity\`.

  From here on the command is \`apply\`, not this script. It pulls the repo and
  installs anything newly declared in lib/packages.sh; \`apply -u\` upgrades
  what's already there. Adding a tool is one line in lib/packages.sh -- every
  machine that pulls it then says so at the next shell prompt.

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
