# reconcile.sh — the install half of the declare/install split.
#
# lib/packages.sh says what should be installed; this says how, and reapplies
# the symlinks and the nvim overlay on top. Sourced only by setup.sh and
# bin/apply, never by the interactive shell, so it is free to fork, hit the
# network, and take its time.
#
# Requires: lib/common.sh and lib/packages.sh already sourced, and
# SETUP_REPO_DIR pointing at the repo root.

[[ -n "${SETUP_RECONCILE_SOURCED:-}" ]] && return 0
SETUP_RECONCILE_SOURCED=1

# ── Packages ─────────────────────────────────────────────────────────────────

# Install everything lib/packages.sh probed and found absent. Idempotent by
# construction: if nothing is missing this is a no-op that costs no subprocess.
install_missing_packages() {
  step "Packages"

  if ((SETUP_MISSING_COUNT == 0)); then
    skip "all $SETUP_DECLARED_COUNT declared packages present"
    return 0
  fi
  printf '  %s of %s declared packages missing\n' \
    "$SETUP_MISSING_COUNT" "$SETUP_DECLARED_COUNT"

  # Taps first — `brew install try` can't resolve until tobi/try is tapped.
  local entry tap url
  for entry in ${MISSING_BREW_TAPS[@]+"${MISSING_BREW_TAPS[@]}"}; do
    tap="${entry%% *}"
    url="${entry#* }"
    [[ "$url" != "$tap" ]] || url=""
    if brew tap "$tap" ${url:+"$url"} >/dev/null 2>&1; then
      ok "tapped $tap"
    else
      warn "could not tap $tap"
    fi
  done

  # One `brew install` per formula rather than one batched call, so a single
  # formula that fails to build doesn't take the whole run down with it.
  local pkg
  for pkg in ${MISSING_BREW_FORMULAE[@]+"${MISSING_BREW_FORMULAE[@]}"}; do
    if brew install "$pkg"; then ok "$pkg"; else warn "$pkg failed"; fi
  done

  for pkg in ${MISSING_BREW_CASKS[@]+"${MISSING_BREW_CASKS[@]}"}; do
    if brew install --cask "$pkg"; then ok "$pkg"; else warn "$pkg failed"; fi
  done

  if ((${#MISSING_UV_TOOLS[@]} > 0)); then
    if have uv; then
      for pkg in "${MISSING_UV_TOOLS[@]}"; do
        if uv tool install "$pkg"; then ok "$pkg"; else warn "$pkg failed"; fi
      done
    else
      warn "uv is missing, so ${MISSING_UV_TOOLS[*]} were skipped; run ./setup.sh"
    fi
  fi

  if ((${#MISSING_CARGO_CRATES[@]} > 0)); then
    load_cargo
    if have cargo; then
      for pkg in "${MISSING_CARGO_CRATES[@]}"; do
        if cargo install "$pkg"; then ok "$pkg"; else warn "$pkg failed"; fi
      done
    else
      warn "cargo is missing, so ${MISSING_CARGO_CRATES[*]} were skipped; run ./setup.sh"
    fi
  fi
}

# Upgrade what's already installed. Separate from the above and opt-in: filling
# a gap is safe to do on every run, moving every version out from under you is
# not.
upgrade_everything() {
  step "Upgrades"
  if have brew; then
    brew update && brew upgrade
    ok "brew"
  fi
  if have uv; then
    uv tool upgrade --all
    ok "uv tools"
  fi
  load_cargo
  if have rustup; then
    rustup update
    ok "rust toolchain"
  fi
  if have juliaup; then
    juliaup update
    ok "julia"
  fi
}

# Julia is its own function rather than a registry line because "installed" has
# two levels here: juliaup is a plain formula, but it ships no Julia of its own
# until a channel is added. The two brew formulae also conflict — `julia` and
# `juliaup` both provide a `julia` binary — so only one may ever be present.
reconcile_julia() {
  step "Julia / juliaup"
  if brew list --formula juliaup >/dev/null 2>&1; then
    skip "juliaup already installed"
  elif brew list --formula julia >/dev/null 2>&1; then
    warn "the 'julia' formula is installed and conflicts with juliaup; skipping"
    return 0
  else
    brew install juliaup && ok "juliaup installed"
  fi
  # Version numbers only ever appear in the status table's rows, never its
  # header, so a digit is a reliable "some channel is installed" test.
  if have juliaup; then
    if juliaup status 2>/dev/null | grep -qE '[0-9]+\.[0-9]'; then
      skip "a Julia channel is already installed"
    else
      juliaup add release && ok "Julia release channel"
    fi
  fi
}

# ── Configuration ────────────────────────────────────────────────────────────

# ~/.zshrc gets exactly two source lines from us and nothing else. Oh My Zsh
# keeps owning that file (its installer rewrites it, and it holds the theme and
# plugin settings), while everything portable — PATH, aliases, tool init,
# functions — lives in this repo's zsh/rc.zsh.
#
# The source line goes through ~/.config/zsh/rc.zsh rather than pointing at the
# repo directly, so .zshrc doesn't care where you cloned this.
link_shell_config() {
  step "Shell config"
  if [[ -f "$SETUP_REPO_DIR/zsh/rc.zsh" ]]; then
    link_file "$SETUP_REPO_DIR/zsh/rc.zsh" "$HOME/.config/zsh/rc.zsh" "rc.zsh"
  else
    warn "no zsh/rc.zsh found in $SETUP_REPO_DIR"
  fi

  append_once '' "$ZSHRC"
  # Marker text kept as-is even though the script was renamed: append_once
  # matches whole lines, so changing it would leave a second stale marker
  # behind on every machine that already ran the old version.
  append_once '# --- added by setup-mac.sh ---' "$ZSHRC"
  append_once '[[ -f "$HOME/.config/zsh/rc.zsh" ]] && source "$HOME/.config/zsh/rc.zsh"' "$ZSHRC"
  # Machine-specific values and secrets go here. Never tracked; sourced last so
  # it can override anything rc.zsh set.
  append_once '[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"' "$ZSHRC"
  ok "~/.zshrc source lines present"
}

# Scripts in bin/ are symlinked into ~/.local/bin (already on PATH via rc.zsh)
# so they travel with this repo instead of living only on the machine they were
# written on. `apply` itself is one of them.
link_repo_bin() {
  step "Scripts from bin/"
  if [[ ! -d "$SETUP_REPO_DIR/bin" ]]; then
    skip "no bin/ directory"
    return 0
  fi
  shopt -s nullglob
  local src
  for src in "$SETUP_REPO_DIR"/bin/*; do
    [[ -f "$src" ]] || continue
    chmod +x "$src"
    link_file "$src" "$HOME/.local/bin/$(basename "$src")" "$(basename "$src")"
  done
  shopt -u nullglob
}

# The LazyVim starter on its own produces a handful of :LazyHealth warnings.
# The files under nvim/ fix those; each one carries a comment explaining why it
# exists. Reapplied on every run so this repo stays the source of truth.
# Anything already on disk that differs is backed up rather than clobbered.
apply_nvim_overlay() {
  step "Neovim config overlay"
  if [[ ! -d "$SETUP_REPO_DIR/nvim" ]]; then
    warn "no nvim/ overlay found in $SETUP_REPO_DIR"
    return 0
  fi
  if [[ ! -d "$HOME/.config/nvim" ]]; then
    warn "~/.config/nvim doesn't exist yet; run ./setup.sh to clone the starter"
    return 0
  fi
  local src rel dst
  while IFS= read -r src; do
    rel="${src#"$SETUP_REPO_DIR/nvim/"}"
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
  done < <(find "$SETUP_REPO_DIR/nvim" -type f ! -name '.DS_Store')
}
