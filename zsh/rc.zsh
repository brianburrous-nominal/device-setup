# rc.zsh — the portable half of the zsh config, tracked in this repo.
#
# ~/.zshrc sources this near its end, which is deliberate: Oh My Zsh has loaded
# by then, and the eza aliases below need to win over OMZ's own `ls` alias.
# Last definition wins, so this file has to come after it.
#
# Anything machine-specific or secret belongs in ~/.zshrc.local instead. That
# file is sourced right after this one and is never tracked here.
#
# setup.sh symlinks this to ~/.config/zsh/rc.zsh, so edits here are live in the
# next shell -- no need to re-run the script.

# ── PATH ─────────────────────────────────────────────────────────────────────
# Prepend a directory, but only if it exists and isn't already there. Straight
# `PATH="$dir:$PATH"` lines duplicate every entry when this file is sourced
# twice -- nesting a shell, or re-sourcing after an edit -- and leave a dead
# entry on a machine that never ran, say, `cargo install`.
add_path() {
  [[ -d "$1" ]] || return 0
  case ":$PATH:" in
    *":$1:"*) ;;
    *) PATH="$1:$PATH" ;;
  esac
}

# add_path only declines to add a duplicate; it can't clean one that arrived in
# the inherited environment, and by the time a terminal has nested a shell or
# two there are several. -U keeps the first occurrence of each, so this dedupes
# without disturbing precedence.
typeset -U path PATH

# pnpm keeps globally-installed binaries in $PNPM_HOME/bin. Set by hand rather
# than via `pnpm setup`, which appends its own unguarded block to .zshrc.
export PNPM_HOME="$HOME/Library/pnpm"

# Lowest priority last: each is prepended, so the FIRST line ends up deepest.
# This ordering reproduces what the three plain prepends here used to produce
# -- pnpm > cargo > .local/bin -- rather than quietly re-ranking them. Nothing
# is currently shadowed either way; the three directories share no filenames.
add_path "$HOME/.local/bin" # claude, uv tools, this repo's bin/ (apply, mdget)
add_path "$HOME/.cargo/bin" # rustup toolchain + `cargo install` bins
add_path "$PNPM_HOME/bin"
export PATH

# ── environment ──────────────────────────────────────────────────────────────
export EDITOR="nvim"
# Where `try` keeps experiment dirs. setup.sh creates this directory; if you
# change the path, change TRY_PATH_DIR there to match.
export TRY_PATH="$HOME/src/tries"
export FZF_DEFAULT_COMMAND="fd --type f --hidden --exclude .git"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

# ── aliases ──────────────────────────────────────────────────────────────────
alias vim="nvim"

# eza replaces ls. The tree views skip .git and node_modules so `lta` stays
# readable.
#   ls  - grid, dirs first, icons        lsa - same, plus dotfiles
#   lt  - tree, 2 levels deep            lta - same, plus dotfiles
#   ll  - long listing with git status
alias ls='eza --icons --group-directories-first'
alias lsa='eza --icons --group-directories-first --all'
alias lt='eza --icons --group-directories-first --tree --level=2 --ignore-glob=".git|node_modules"'
alias lta='eza --icons --group-directories-first --tree --level=2 --all --ignore-glob=".git|node_modules"'
alias ll='eza --icons --group-directories-first --long --git'

# Nominal CLI. `nomprofile` is this repo's bin/nomprofile -- a gum TUI wrapping
# the profile-add flow, which is otherwise a long line of flags to remember.
alias nomconfig='nomctl config profile'
alias nomp='nomprofile'

# `rm` moves things to the Trash instead of unlinking them. Nothing to install:
# macOS 15 added /usr/bin/trash, which is exactly why Homebrew's `trash` and
# `macos-trash` formulae are both keg-only now. Recoverable in Finder, "Put
# Back" included.
#
# A function, not an alias, and rc.zsh is only sourced by interactive shells --
# so scripts, subprocesses, and `command rm` all still get the real rm. Reach
# for `command rm` when you mean it: something too big for the Trash volume, or
# a path that has to be gone now rather than later.
if (( $+commands[trash] )); then
  rm() {
    emulate -L zsh
    local arg literal=0
    local -a paths

    # trash takes paths and nothing else -- it needs no -r (a directory moves
    # whole) and no -f (it never prompts). Dropping rm's flags instead of
    # forwarding them is what keeps `rm -rf build` working: trash would reject
    # -rf as an unrecognized argument, and then still exit 0.
    for arg in "$@"; do
      if (( literal )); then
        # Past a `--`, a leading dash belongs to the filename. trash has no
        # `--` of its own, so say the same thing the way it does understand.
        [[ "$arg" == -* ]] && arg="./$arg"
        paths+=("$arg")
      elif [[ "$arg" == "--" ]]; then
        literal=1
      elif [[ "$arg" == -?* ]]; then
        continue
      else
        paths+=("$arg")   # a bare "-" is a filename to rm, so it lands here
      fi
    done

    if (( ${#paths} == 0 )); then
      print -u2 "rm: no paths given (flags are dropped; 'command rm' for the real thing)"
      return 2
    fi
    trash "${paths[@]}"
  }
fi

# ── tool init ────────────────────────────────────────────────────────────────
# Order matters: fzf binds Ctrl-R, then atuin takes it over. Drop the atuin
# line if you'd rather keep fzf's history search.
source <(fzf --zsh)
eval "$(zoxide init zsh)"
eval "$(direnv hook zsh)"
eval "$(atuin init zsh)"

# `try init` reads from the terminal, so it hangs when there isn't one -- which
# is any non-interactive shell: scripts, `zsh -c`, editor and CI subshells.
if [[ -o interactive ]] && { : </dev/tty; } 2>/dev/null; then
  eval "$(try init)"
fi

# ── functions ────────────────────────────────────────────────────────────────

# rgv — ripgrep → fzf → nvim: search text under a directory, pick a match, edit it there.
#   rgv                  search $PWD, type the pattern live in fzf
#   rgv foo              start with "foo" as the pattern
#   rgv foo src/         search src/ instead
#   rgv src/             search src/, type the pattern live
# enter opens nvim at the line/column; tab multi-selects and opens a quickfix list.
rgv() {
  emulate -L zsh
  setopt local_options no_nomatch extended_glob

  local dir="." query=""
  if (( $# == 1 )) && [[ -d "$1" ]]; then
    dir="$1"
  else
    query="${1:-}"
    [[ -n "${2:-}" ]] && dir="$2"
  fi

  local rg_cmd="rg --column --line-number --no-heading --with-filename --color=always --smart-case --hidden --glob '!.git/*'"
  local reload="[ -z {q} ] || $rg_cmd -- {q} ${(q)dir} || true"

  local preview
  if (( $+commands[bat] )); then
    preview='bat --color=always --style=numbers --highlight-line {2} -- {1}'
  else
    preview='awk -v L={2} "NR>=L-10 && NR<=L+40 {printf \"%s%d: %s\n\", (NR==L ? \"> \" : \"  \"), NR, \$0}" {1}'
  fi

  local -a picks
  picks=("${(@f)$(
    fzf --ansi --disabled --multi --query="$query" \
        --delimiter : \
        --bind "start:reload:$reload" \
        --bind "change:reload:sleep 0.05; $reload" \
        --bind 'ctrl-/:toggle-preview' \
        --preview "$preview" \
        --preview-window 'right,55%,border-left,+{2}+3/3' \
        --prompt 'rgv> ' \
        --header 'enter: edit  ·  tab: select many  ·  ctrl-/: preview  ·  esc: cancel'
  )}")

  (( ${#picks} )) || return 0
  [[ -n "${picks[1]}" ]] || return 0

  # rg colors its output; strip the escape sequences before parsing file:line:col
  picks=("${(@)picks//$'\e'\[[0-9;]#[a-zA-Z]/}")

  if (( ${#picks} == 1 )); then
    local file="${picks[1]%%:*}" rest="${picks[1]#*:}"
    local line="${rest%%:*}"; rest="${rest#*:}"
    local col="${rest%%:*}"
    # -c flags must come BEFORE --, or nvim treats them as filenames
    nvim -c "call cursor(${line:-1}, ${col:-1})" -c 'normal! zz' -- "$file"
  else
    local qf="${TMPDIR:-/tmp}/rgv-qf.$$"
    print -l -- "${picks[@]}" > "$qf"
    nvim -q "$qf" -c 'copen' -c 'normal! zz'
    rm -f "$qf"
  fi
}

# ── package drift ────────────────────────────────────────────────────────────
# The other half of the declare/install split. lib/packages.sh in the setup repo
# is the single list of what should be installed; sourcing it here probes for
# each entry and counts what's absent. It never installs anything -- shell
# startup only ever *reports*, and `apply` is what acts.
#
# That's what makes adding a tool one line: declare it in lib/packages.sh on one
# machine, and every other machine says "run apply" the next time you open a
# shell, instead of silently lacking it until someone re-runs the installer.
#
# Cheap enough to do unconditionally: every probe is a builtin (zsh's $commands
# hash, or [[ -e ]] for the few things it can't see), which measures ~0.5ms for
# the whole file. Deliberately last in this file so the probes see the PATH set
# at the top.
#
# ${(%):-%N} is this file's own path; :A resolves the ~/.config/zsh/rc.zsh
# symlink back to the repo, so this works wherever the repo is cloned.
# The argument, not a local: %N inside a function is the *function* name, and
# for an anonymous one that's the literal string "(anon)".
() {
  local repo="$1"
  [[ -r "$repo/lib/packages.sh" ]] || return 0

  source "$repo/lib/packages.sh"
  (( SETUP_MISSING_COUNT == 0 )) || print -P \
    "%F{cyan}*%f ${SETUP_MISSING_COUNT} declared package(s) not installed — run %Bapply%b (or %Bjarvis status%b to see which)"

  # Sourced files leak their names into the interactive shell; don't make the
  # user tab-complete a DSL they'll never call by hand.
  unfunction pkg_present brew_formula brew_cask uv_tool cargo_crate declared \
    2>/dev/null
  unset SETUP_PACKAGES_SOURCED SETUP_BREW_PREFIX SETUP_DECLARED_COUNT \
    SETUP_MISSING_COUNT MISSING_BREW_FORMULAE MISSING_BREW_CASKS \
    MISSING_UV_TOOLS MISSING_CARGO_CRATES MISSING_BREW_TAPS \
    SETUP_DECLARED SETUP_DECLARED_TAPS
} "${${(%):-%N}:A:h:h}"
