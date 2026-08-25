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
export PATH="$HOME/.local/bin:$PATH" # claude, uv tools, this repo's bin/
export PATH="$HOME/.cargo/bin:$PATH" # rustup toolchain + `cargo install` bins
# pnpm keeps globally-installed binaries in $PNPM_HOME/bin. Set by hand rather
# than via `pnpm setup`, which appends its own unguarded block to .zshrc.
export PNPM_HOME="$HOME/Library/pnpm"
export PATH="$PNPM_HOME/bin:$PATH"

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
