# identity.sh — SSH key, GitHub auth, and git identity.
#
# The interactive half of a new-machine setup: the parts that need a human,
# because they involve a passphrase, a browser, and your own name.
#
# Sourced by setup.sh and by bin/identity. Deliberately NOT by bin/apply —
# apply's contract is "no sudo, no prompts", and everything here can prompt.
# That's also why every step checks first and returns early: on a machine
# that's already set up this is silent and costs nothing.
#
# Requires: lib/common.sh already sourced, and SETUP_REPO_DIR set.

[[ -n "${SETUP_IDENTITY_SOURCED:-}" ]] && return 0
SETUP_IDENTITY_SOURCED=1

SSH_KEY="$HOME/.ssh/id_ed25519"

# True when there's a human on the other end. Everything below is a prompt of
# some kind, so each step consults this rather than hanging in a context that
# can't answer — cron, CI, a piped shell.
identity_interactive() {
  [[ -t 0 ]] || return 1
  { : </dev/tty; } 2>/dev/null
}

# ── 1. SSH key ───────────────────────────────────────────────────────────────
# ed25519 rather than RSA: shorter, faster, and what GitHub recommends. No
# -N flag, so ssh-keygen asks for a passphrase itself — an empty one is two
# presses of return, and a real one is typed exactly once because the keychain
# holds it from then on.
identity_ssh_key() {
  step "SSH key"
  if [[ -f "$SSH_KEY" ]]; then
    skip "$SSH_KEY already exists"
  elif ! identity_interactive; then
    warn "no terminal for the passphrase prompt; skipping. Run 'identity' later."
    return 0
  else
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    echo "  Choose a passphrase, or press return twice for none."
    echo "  Either way you'll only ever type it once — it goes in the keychain."
    ssh-keygen -t ed25519 -C "$(identity_email_guess)" -f "$SSH_KEY" </dev/tty \
      || { warn "ssh-keygen failed or was cancelled"; return 0; }
    ok "generated $SSH_KEY"
  fi

  # Idempotent: re-adding a key already in the agent is a no-op.
  if [[ -f "$SSH_KEY" ]]; then
    ssh-add --apple-use-keychain "$SSH_KEY" >/dev/null 2>&1 \
      && ok "loaded into the agent, passphrase in the keychain" \
      || warn "could not add the key to the agent"
  fi
}

# A best-effort default for the key comment. The comment is cosmetic — it just
# labels the key in GitHub's UI — so any of these is fine and none is worth a
# prompt of its own.
identity_email_guess() {
  git config --global user.email 2>/dev/null \
    || printf '%s@%s' "$(id -un)" "$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
}

# ── 2. ~/.ssh/config ─────────────────────────────────────────────────────────
# The repo's ssh/setup.conf is symlinked into ~/.ssh/config.d/ and pulled in by
# an Include on the first line of ~/.ssh/config.
#
# It has to be the first line, for two separate reasons. An Include is
# evaluated inside whatever Host block is in scope where it appears, so one
# appended to a file that ends in a `Host foo` block would apply to foo alone —
# ssh logs the rest as "parse only" and it silently does nothing for every other
# host. And ssh keeps the first value it obtains for each keyword, ignoring
# later ones, so an Include further down would lose to anything above it.
#
# Line 1 avoids both. The trade-off is that these settings then win over the
# rest of the file, so the note written above the Include says where to put an
# override.
identity_ssh_config() {
  step "SSH config"
  local src="$SETUP_REPO_DIR/ssh/setup.conf"
  if [[ ! -f "$src" ]]; then
    warn "no ssh/setup.conf in $SETUP_REPO_DIR"
    return 0
  fi

  mkdir -p "$HOME/.ssh/config.d"
  chmod 700 "$HOME/.ssh" "$HOME/.ssh/config.d"
  link_file "$src" "$HOME/.ssh/config.d/setup.conf" "setup.conf"

  local cfg="$HOME/.ssh/config" include="Include config.d/*.conf"
  if [[ -f "$cfg" ]] && grep -qxF -- "$include" "$cfg"; then
    skip "Include line already present"
    return 0
  fi

  # Left in the file itself, because that's where someone will be standing when
  # they wonder why an override below isn't taking effect.
  local note="# Anything below is ignored for keywords already set by the Include above.
# Put host-specific overrides ABOVE this line."

  # Prepend rather than append — see the note above. Write via a temp file so a
  # failure can't leave a truncated ssh config behind.
  local tmp="$cfg.tmp-$STAMP"
  {
    printf '%s\n%s\n\n' "$include" "$note"
    [[ -f "$cfg" ]] && cat "$cfg"
  } >"$tmp"
  [[ -f "$cfg" ]] && cp "$cfg" "$cfg.bak-$STAMP" && warn "backed up ~/.ssh/config"
  mv "$tmp" "$cfg"
  chmod 600 "$cfg"
  ok "Include added at the top of ~/.ssh/config"
}

# ── 3. GitHub ────────────────────────────────────────────────────────────────
# gh's login flow handles the browser handshake and stores the token in the
# keychain, so there's no PAT to paste or keep anywhere. Uploading the public
# key here is what makes `git push` over SSH work without a second visit to
# github.com.
identity_github() {
  step "GitHub"
  if ! have gh; then
    warn "gh isn't installed yet; skipping. Run 'identity' after setup finishes."
    return 0
  fi

  if gh auth status >/dev/null 2>&1; then
    skip "already authenticated as $(gh api user --jq .login 2>/dev/null || echo '?')"
  elif ! identity_interactive; then
    warn "no terminal for the login flow; skipping. Run 'identity' later."
    return 0
  else
    echo "  A browser window will open to authorize the GitHub CLI."
    gh auth login --git-protocol ssh --web </dev/tty \
      || { warn "gh auth login failed or was cancelled"; return 0; }
    ok "authenticated"
  fi

  # Upload the public key if the account doesn't already have it. Compare on the
  # key body — the middle field — because the trailing comment is local-only and
  # GitHub stores its own title alongside it.
  if [[ -f "$SSH_KEY.pub" ]] && gh auth status >/dev/null 2>&1; then
    local body
    body="$(awk '{print $2}' "$SSH_KEY.pub")"
    if gh ssh-key list 2>/dev/null | grep -qF -- "$body"; then
      skip "public key already on the GitHub account"
    else
      gh ssh-key add "$SSH_KEY.pub" --title "$(scutil --get LocalHostName 2>/dev/null || hostname -s)" \
        && ok "public key uploaded" \
        || warn "could not upload the key (needs the admin:public_key scope)"
    fi
  fi
}

# ── 4. git identity ──────────────────────────────────────────────────────────
# Written to ~/.gitconfig, which is untracked and machine-local — the same role
# ~/.zshrc.local plays for the shell. Git reads ~/.config/git/config first and
# ~/.gitconfig second, and the later file wins, so this stays the override layer
# whatever else gets tracked later.
#
# The default is taken from this repo's own most recent commit, which is a
# better source than it first sounds: it's your repo, you wrote those commits,
# and the machine has a full clone of them before this step ever runs. That's
# what makes machine number two zero typing — and it keeps the identity
# consistent with the history you already have, which the GitHub API can't
# promise. Accounts with no public name or email are common, and the noreply
# address gh falls back to would quietly split your commits into a second
# identity that doesn't match anything you've authored before.
identity_git() {
  step "Git identity"
  local name email
  name="$(git config --global user.name 2>/dev/null || true)"
  email="$(git config --global user.email 2>/dev/null || true)"

  if [[ -n "$name" && -n "$email" ]]; then
    skip "already set ($name <$email>)"
    return 0
  fi

  # Candidates, best first: this repo's history, then the GitHub account, then
  # github's per-account noreply address so commits at least have something
  # valid and non-public.
  local cand_name cand_email
  if [[ -d "$SETUP_REPO_DIR/.git" ]]; then
    cand_name="$(git -C "$SETUP_REPO_DIR" log -1 --format=%an 2>/dev/null || true)"
    cand_email="$(git -C "$SETUP_REPO_DIR" log -1 --format=%ae 2>/dev/null || true)"
  fi
  if have gh && gh auth status >/dev/null 2>&1; then
    [[ -n "${cand_name:-}" ]]  || cand_name="$(gh api user --jq '.name // empty' 2>/dev/null || true)"
    [[ -n "${cand_email:-}" ]] || cand_email="$(gh api user --jq '.email // empty' 2>/dev/null || true)"
    if [[ -z "${cand_email:-}" ]]; then
      local login id
      login="$(gh api user --jq .login 2>/dev/null || true)"
      id="$(gh api user --jq .id 2>/dev/null || true)"
      [[ -n "$login" && -n "$id" ]] && cand_email="${id}+${login}@users.noreply.github.com"
    fi
  fi

  # Interactive: show the guess and take return as agreement. A guess is only
  # ever a default here, never a silent decision — getting this wrong means
  # every commit on the machine is misattributed, and it's one keypress to
  # confirm.
  if identity_interactive; then
    [[ -n "$name" ]] || {
      printf '  Name for git commits [%s]: ' "${cand_name:-}"
      IFS= read -r name </dev/tty
      [[ -n "$name" ]] || name="${cand_name:-}"
    }
    [[ -n "$email" ]] || {
      printf '  Email for git commits [%s]: ' "${cand_email:-}"
      IFS= read -r email </dev/tty
      [[ -n "$email" ]] || email="${cand_email:-}"
    }
  else
    [[ -n "$name" ]]  || name="${cand_name:-}"
    [[ -n "$email" ]] || email="${cand_email:-}"
  fi

  if [[ -z "$name" || -z "$email" ]]; then
    warn "git identity not set; run 'identity' from a terminal to set it"
    return 0
  fi

  git config --global user.name "$name"
  git config --global user.email "$email"
  ok "$name <$email>"
}

# ── 5. remote over SSH ───────────────────────────────────────────────────────
# bootstrap.sh clones over HTTPS, because on a bare machine there's no key yet.
# Now that there is one, move this repo's remote across so pushes use it.
identity_repo_remote() {
  step "Repo remote"
  [[ -d "$SETUP_REPO_DIR/.git" ]] || { skip "not a git checkout"; return 0; }

  local url
  url="$(git -C "$SETUP_REPO_DIR" remote get-url origin 2>/dev/null || true)"
  case "$url" in
    "") skip "no origin remote" ; return 0 ;;
    git@*|ssh://*) skip "already SSH" ; return 0 ;;
  esac

  # Only rewrite what we recognise, and only once SSH actually works — an
  # unreachable remote is worse than an HTTPS one that does.
  local path="${url#https://github.com/}"
  if [[ "$path" == "$url" ]]; then
    skip "origin isn't a github.com HTTPS URL; leaving it alone"
    return 0
  fi
  if ! ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
       git@github.com 2>&1 | grep -q 'successfully authenticated'; then
    skip "SSH to github.com not working yet; leaving the HTTPS remote"
    return 0
  fi
  git -C "$SETUP_REPO_DIR" remote set-url origin "git@github.com:$path"
  ok "origin now git@github.com:$path"
}

# Everything, in order. Each step is independently safe to re-run.
reconcile_identity() {
  identity_ssh_key
  identity_ssh_config
  identity_github
  identity_git
  identity_repo_remote
}
