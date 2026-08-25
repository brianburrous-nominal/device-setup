#!/usr/bin/env bash
#
# bootstrap.sh — get this repo onto a Mac that has nothing, then run setup.sh.
#
#   curl -fsSL https://raw.githubusercontent.com/brianburrous-nominal/device-setup/main/bootstrap.sh | bash
#
# That one line is the whole new-machine command. It handles the two steps
# setup.sh structurally can't, because both have to happen before this repo
# exists on disk:
#
#   1. Xcode Command Line Tools. /usr/bin/git on a bare Mac is a stub that pops
#      a GUI dialog and returns failure, so `git clone` can't run until the real
#      tools are installed. Installed headlessly here — no dialog to click.
#   2. The clone itself.
#
# Then it hands off to setup.sh, which owns everything from Homebrew onward.
#
# Deliberately depends on nothing but what ships with macOS: /bin/bash (3.2),
# curl, and softwareupdate. It runs before Homebrew exists, so it cannot assume
# a modern bash, and must stay bash-3.2 clean — no associative arrays, no
# ${var^^}, no `mapfile`.
#
# Safe to re-run. Every step checks for an existing install first, and an
# existing checkout is updated rather than re-cloned.
#
# Override where it clones to:  SETUP_DIR=~/code/setup curl ... | bash
#

set -euo pipefail

REPO_URL="${SETUP_REPO_URL:-https://github.com/brianburrous-nominal/device-setup.git}"
SETUP_DIR="${SETUP_DIR:-$HOME/dev/setup}"
CLT_SENTINEL="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"

BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
step() { printf '\n%s==> %s%s\n' "$BOLD" "$1" "$RESET"; }
ok()   { printf '%s  ✓ %s%s\n' "$GREEN" "$1" "$RESET"; }
skip() { printf '  · %s\n' "$1"; }
warn() { printf '%s  ! %s%s\n' "$YELLOW" "$1" "$RESET"; }
die()  { printf '%s  ✗ %s%s\n' "$RED" "$1" "$RESET" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "This script is for macOS."

# Piped into bash, stdin is the script text, not the terminal. Anything that
# needs to ask the user something — sudo, git's credential prompt, setup.sh's
# own prompts — has to read the tty explicitly. Bail early with a clear message
# rather than hanging on a prompt nobody can answer.
if [[ ! -t 0 ]] && ! { : </dev/tty; } 2>/dev/null; then
  die "No terminal available. Run this from an interactive shell."
fi

printf '\n%sBootstrapping a new Mac%s\n' "$BOLD" "$RESET"
printf '  repo -> %s\n' "$SETUP_DIR"

# ---------------------------------------------------------------------------
# 1. Xcode Command Line Tools
#
#    `xcode-select --install` opens a GUI dialog and returns immediately, so a
#    piped script can't tell when — or whether — it finished. The sentinel file
#    below is the documented trick for avoiding that: with it present,
#    softwareupdate lists the CLT package as an installable update, which means
#    it can be installed headlessly and synchronously like any other update.
# ---------------------------------------------------------------------------
step "Xcode Command Line Tools"
if xcode-select -p >/dev/null 2>&1 && [[ -x /Library/Developer/CommandLineTools/usr/bin/git ]]; then
  skip "already installed ($(xcode-select -p))"
else
  echo "  Installing headlessly; this needs your password and takes a few minutes."
  sudo -v </dev/tty || die "sudo is required to install the Command Line Tools."

  touch "$CLT_SENTINEL"
  # softwareupdate lists candidates as "* Label: Command Line Tools for Xcode-26.0".
  # Take the last match: labels sort ascending, so that's the newest offered.
  CLT_LABEL="$(softwareupdate -l 2>/dev/null \
    | grep -E '^\s*\*\s*Label:.*Command Line Tools' \
    | sed -e 's/^[^:]*: *//' -e 's/[[:space:]]*$//' \
    | tail -1)"
  rm -f "$CLT_SENTINEL"

  if [[ -n "$CLT_LABEL" ]]; then
    echo "  Installing: $CLT_LABEL"
    sudo softwareupdate -i "$CLT_LABEL" --verbose </dev/tty \
      || warn "headless install failed; falling back to the GUI installer"
  else
    warn "softwareupdate offered no Command Line Tools package"
  fi

  # Fall back to the dialog if the headless path didn't produce a usable git.
  if [[ ! -x /Library/Developer/CommandLineTools/usr/bin/git ]]; then
    warn "falling back to the GUI installer — click through the dialog that opens"
    xcode-select --install 2>/dev/null || true
    printf '  waiting for the install to finish'
    until [[ -x /Library/Developer/CommandLineTools/usr/bin/git ]]; do
      printf '.'
      sleep 10
    done
    printf '\n'
  fi
  ok "installed"
fi

# ---------------------------------------------------------------------------
# 2. Clone
#    Over HTTPS on purpose: it needs no key material, so it works on a machine
#    that has never talked to GitHub. setup.sh's identity step is what sets up
#    SSH afterwards, and it switches this remote over to SSH once it has.
# ---------------------------------------------------------------------------
step "Repo"
if [[ -d "$SETUP_DIR/.git" ]]; then
  skip "$SETUP_DIR already a checkout"
  git -C "$SETUP_DIR" pull --rebase --autostash || warn "pull failed; using the checkout as-is"
elif [[ -e "$SETUP_DIR" ]]; then
  die "$SETUP_DIR exists but isn't a git checkout. Move it aside and re-run."
else
  mkdir -p "$(dirname "$SETUP_DIR")"
  git clone "$REPO_URL" "$SETUP_DIR" || die "clone failed: $REPO_URL"
  ok "cloned"
fi

# ---------------------------------------------------------------------------
# 3. Hand off
#    exec, not a plain call, so setup.sh replaces this process and owns the
#    terminal outright. stdin is redirected to the tty because ours is still
#    the curl pipe, and setup.sh prompts.
# ---------------------------------------------------------------------------
step "Handing off to setup.sh"
[[ -f "$SETUP_DIR/setup.sh" ]] || die "no setup.sh in $SETUP_DIR"
chmod +x "$SETUP_DIR/setup.sh"
cd "$SETUP_DIR"
exec ./setup.sh </dev/tty
