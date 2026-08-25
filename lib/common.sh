# common.sh — output helpers and file operations shared by setup.sh and bin/apply.
#
# Bash only. Nothing here is sourced by the interactive shell, so it is free to
# fork. Keep anything that rc.zsh needs in lib/packages.sh instead.

[[ -n "${SETUP_COMMON_SOURCED:-}" ]] && return 0
SETUP_COMMON_SOURCED=1

# One timestamp per run, so every backup a single run makes shares a suffix.
STAMP="${STAMP:-$(date +%Y%m%d-%H%M%S)}"

ZSHRC="$HOME/.zshrc"
ZPROFILE="$HOME/.zprofile"

# uv drops its tool shims in ~/.local/bin, and so does this repo's bin/. Future
# shells get this from rc.zsh; export it here so the rest of the run sees it.
export PATH="$HOME/.local/bin:$PATH"

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

# Put Homebrew on PATH for this process. Both entry points need it: setup.sh
# right after installing brew, apply because it may run from a context (cron,
# a non-login shell) where .zprofile never ran.
# Sets BREW_BIN as a side effect: setup.sh needs the literal path to write the
# shellenv line into ~/.zprofile.
load_brew() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    BREW_BIN=/opt/homebrew/bin/brew # Apple Silicon
  elif [[ -x /usr/local/bin/brew ]]; then
    BREW_BIN=/usr/local/bin/brew # Intel
  else
    return 1
  fi
  eval "$("$BREW_BIN" shellenv)"
}

# Same for the Rust toolchain: ~/.cargo/env is what rustup writes.
load_cargo() {
  # shellcheck source=/dev/null
  [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
  return 0
}
