# managers.sh — the one place that knows how each package manager behaves.
#
# Everything else in this repo names a manager and a package; nothing else
# spells out `brew install` or `uv tool install` or `cargo install`. That is the
# whole point: adding a manager means adding a case branch here, and every
# caller — reconcile.sh's installer, jarvis's install/upgrade, the status
# table — picks it up without knowing anything new.
#
# Sourced by:
#   lib/reconcile.sh  (bash) to install what's missing and to upgrade
#   bin/jarvis        (zsh)  to install one named tool, and to upgrade
#
# Must stay valid in BOTH bash and zsh, because of those two callers. Quote
# every expansion, iterate arrays with `for x in "${arr[@]}"` rather than
# indexing (zsh indexes from 1), and don't reach for `declare -A`: the system
# bash on macOS is 3.2 and doesn't have it.
#
# Requires lib/common.sh already sourced, for have/ok/warn/skip/step.

[[ -n "${SETUP_MANAGERS_SOURCED:-}" ]] && return 0
SETUP_MANAGERS_SOURCED=1

# ── The registry of managers ─────────────────────────────────────────────────
# Order is display order, and it is also dependency order for upgrades: brew
# comes first because it is what installs several of the others.
#
# A "manager" here is anything that can put a tool on this machine, which is why
# the list runs past the real package managers into `repo` (scripts symlinked
# out of bin/), `zsh` (functions and aliases in zsh/rc.zsh) and `system` (things
# macOS already ships). Those three install nothing, but a tool has to be able
# to say where it came from, and the answer "it's a shell function" belongs in
# the same field as "it's a brew formula" — otherwise every caller grows a
# special case for the tools that aren't packages.
SETUP_MANAGERS=(brew cask uv cargo rustup juliaup pnpm npm repo zsh system)

# A manager spec is `manager:package`, e.g. brew:ripgrep, uv:httpie,
# repo:bin/netscan. The package half is optional for the managers that don't
# have one (zsh, system).
mgr_of()  { printf '%s' "${1%%:*}"; }
mgr_pkg() { case "$1" in *:*) printf '%s' "${1#*:}" ;; *) printf '' ;; esac; }

# Human-readable name, for tables and prose.
mgr_label() {
  case "$1" in
    brew) printf 'Homebrew' ;;
    cask) printf 'Homebrew cask' ;;
    uv) printf 'uv tool' ;;
    cargo) printf 'cargo' ;;
    rustup) printf 'rustup' ;;
    juliaup) printf 'juliaup' ;;
    pnpm) printf 'pnpm (global)' ;;
    npm) printf 'npm (global)' ;;
    repo) printf 'this repo' ;;
    zsh) printf 'zsh/rc.zsh' ;;
    system) printf 'macOS' ;;
    *) printf '%s' "$1" ;;
  esac
}

# Short tag for the list column, where width is scarce.
mgr_tag() {
  case "$1" in
    cask) printf 'brew' ;;
    repo) printf 'repo' ;;
    zsh) printf 'shell' ;;
    system) printf 'macos' ;;
    *) printf '%s' "$1" ;;
  esac
}

# Is this manager usable right now? `repo`/`zsh`/`system` are always true —
# nothing has to be installed for a symlinked script or a shell function to
# work, beyond the repo itself.
mgr_available() {
  case "$1" in
    brew | cask) have brew ;;
    uv) have uv ;;
    cargo | rustup) load_cargo && have "$1" ;;
    juliaup) have juliaup ;;
    pnpm) have pnpm ;;
    npm) have npm ;;
    repo | zsh | system) return 0 ;;
    *) return 1 ;;
  esac
}

# Can `jarvis install <tool>` target this manager? The three non-package
# managers can't install one thing on request — the answer for all of them is
# "run apply", which relinks the lot.
mgr_installable() {
  case "$1" in
    repo | zsh | system) return 1 ;;
    *) return 0 ;;
  esac
}

# ── Install ──────────────────────────────────────────────────────────────────
# mgr_install <manager> <package>
#
# One package per call rather than one batched command per manager, so a single
# formula that fails to build doesn't take the rest of the run down with it.
# Returns the installer's exit status; the caller decides what to print.
mgr_install() {
  local mgr="$1" pkg="$2"
  case "$mgr" in
    brew) brew install "$pkg" ;;
    cask) brew install --cask "$pkg" ;;
    uv) uv tool install "$pkg" ;;
    cargo) cargo install "$pkg" ;;
    pnpm) pnpm add --global "$pkg" ;;
    npm) npm install --global "$pkg" ;;
    rustup | juliaup)
      warn "$mgr installs toolchains, not packages; nothing to do for $pkg"
      return 1
      ;;
    repo | zsh)
      warn "$pkg comes from this repo — run 'apply' to link it"
      return 1
      ;;
    system)
      skip "$pkg ships with macOS"
      return 0
      ;;
    *)
      warn "don't know how to install with '$mgr'"
      return 1
      ;;
  esac
}

# ── Upgrade ──────────────────────────────────────────────────────────────────
# mgr_upgrade <manager>
#
# Upgrade everything this manager owns. Skips silently when the manager isn't
# installed, so callers can loop over the whole list without checking first.
mgr_upgrade() {
  local mgr="$1"
  mgr_available "$mgr" || {
    skip "$(mgr_label "$mgr") not installed"
    return 0
  }
  case "$mgr" in
    brew)
      # `brew upgrade` covers casks too, so the cask branch below is a no-op
      # rather than a second pass over the same work.
      brew update && brew upgrade
      ;;
    cask)
      # `brew upgrade` has covered casks as well as formulae for several
      # versions now, so the cask branch is a deliberate no-op rather than a
      # second pass over the same work.
      skip "casks come with 'jarvis upgrade brew'"
      return 0
      ;;
    uv) uv tool upgrade --all ;;
    rustup) rustup update ;;
    juliaup) juliaup update ;;
    cargo)
      # `cargo install` has no upgrade subcommand: it only ever installs the
      # latest, and refuses when that's what you already have. cargo-update
      # adds the missing `install-update`, which reads the list of installed
      # crates and reinstalls the ones that moved. Without it there is nothing
      # honest to do but say so — silently running `rustup update` here would
      # look like the crates were checked when they weren't.
      if have cargo-install-update; then
        cargo install-update -a
      else
        skip "crates not checked (cargo install install-update adds 'cargo install-update -a')"
        return 0
      fi
      ;;
    pnpm)
      # --latest crosses semver majors, which is what you want from an
      # explicit upgrade command and not what pnpm does by default.
      pnpm update --global --latest
      ;;
    npm) npm update --global ;;
    repo | zsh)
      # Both live in this repo, so "upgrade" is a pull plus a relink — which
      # is exactly what apply does, and what already ran if you got here
      # through `apply -u`.
      skip "tracked in this repo; 'apply' pulls and relinks them"
      return 0
      ;;
    system)
      skip "macOS ships these; Software Update owns them"
      return 0
      ;;
    *) return 0 ;;
  esac
}

# Upgrade every manager in turn, or just the ones named. The caller gets one
# step header per manager so a long `brew upgrade` isn't ambiguous about what
# it's doing.
#
# Two loops rather than one over `${@:-...}`: unquoted parameters word-split in
# bash and don't in zsh, so the usual default-value trick would iterate once
# over the whole string here and eleven times there.
mgr_upgrade_step() {
  step "$(mgr_label "$1")"
  mgr_upgrade "$1" || warn "$(mgr_label "$1") upgrade reported an error"
}

mgr_upgrade_all() {
  local mgr
  if (($# > 0)); then
    for mgr in "$@"; do mgr_upgrade_step "$mgr"; done
  else
    for mgr in "${SETUP_MANAGERS[@]}"; do mgr_upgrade_step "$mgr"; done
  fi
}
