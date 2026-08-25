# catalog.sh — what every tool on this machine is, and how to use it.
#
# The registry in lib/packages.sh answers "should this be installed?". It is
# sourced on every shell startup, so it is allowed to know nothing else. This
# file answers "what is it, and what do I type?", and is read only by `jarvis`.
#
# The split is deliberate, and it is not just about startup cost. This catalog
# is a strict superset of the package registry: a third of what's below is not
# a package at all. `ls` is an eza alias, `rm` is a function that calls trash,
# `netscan` is a script in bin/, `trash` ships with macOS. None of those can be
# declared in packages.sh, because nothing installs them — but all of them are
# things you type, so all of them belong here. Folding this into packages.sh
# would mean teaching the installer about tools it can't install.
#
# `jarvis doctor` reconciles the two lists in both directions, so a package
# declared without a catalog entry (or the reverse) is reported rather than
# quietly missed.
#
# Must stay valid in BOTH bash and zsh: bin/jarvis is zsh, and nothing stops a
# bash caller from wanting the list. So: quote every expansion, iterate with
# `for x in "${arr[@]}"`, and no associative arrays (the system bash is 3.2).
#
# ── Adding a tool ────────────────────────────────────────────────────────────
#
#   tool <name> <category> <manager>:<package> \
#     -s "one line, lowercase, no trailing period — this is the list column" \
#     -d "the longer explanation; say why you'd reach for it over the obvious
#         alternative, not just what it does" \
#     -x "the command"        "what that does" \
#     -l "https://homepage"
#
#   -s  summary   required; one line
#   -d  detail    optional; free text, newlines fine
#   -x  example   repeatable; always two arguments, command then note
#   -p  probe     how to test presence, if not the tool's own name. An absolute
#                 path tests for the file instead (see packages.sh on why).
#   -l  link      homepage
#   -r  related   space-separated tool names
#   -n  note      why this tool ISN'T in lib/packages.sh, for the handful that
#                 something other than the registry installs. Suppresses the
#                 "declare it" warning from `jarvis doctor`, so only use it
#                 where the reason is real and worth writing down.
#
# If the tool is also installed by this repo, declare it in lib/packages.sh too.

[[ -n "${JARVIS_CATALOG_SOURCED:-}" ]] && return 0
JARVIS_CATALOG_SOURCED=1

# Field and example separators. ASCII 0x1f/0x1e exist for exactly this and can't
# occur in any of the text below, so records survive being passed through awk,
# fzf and command substitution without an escaping scheme.
JARVIS_FS=$'\037'
JARVIS_RS=$'\036'
# A literal newline in its own parameter: $'\n' is only special as a standalone
# token, so writing it inside the double-quoted append below would join examples
# with four literal characters instead of a line break.
JARVIS_NL=$'\n'

# Same fallback as lib/packages.sh: .zprofile exports HOMEBREW_PREFIX for login
# shells, and the literal covers everything else. Two tools below are probed by
# absolute path rather than by name, because the bare name finds the macOS copy.
JARVIS_BREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"

JARVIS_CATALOG=()
JARVIS_CATEGORIES=()

# category <key> <title> <blurb>
category() {
  JARVIS_CATEGORIES+=("$1$JARVIS_FS$2$JARVIS_FS${3:-}")
}

tool() {
  local name="$1" cat="$2" mgr="$3"
  shift 3
  local probe="" summary="" detail="" examples="" link="" related="" note=""
  while (($# > 0)); do
    case "$1" in
      -s)
        summary="$2"
        shift 2
        ;;
      -d)
        detail="$2"
        shift 2
        ;;
      -x)
        examples="${examples}${examples:+$JARVIS_NL}$2$JARVIS_RS$3"
        shift 3
        ;;
      -p)
        probe="$2"
        shift 2
        ;;
      -l)
        link="$2"
        shift 2
        ;;
      -r)
        related="$2"
        shift 2
        ;;
      -n)
        note="$2"
        shift 2
        ;;
      *)
        printf 'catalog: unknown flag "%s" on tool "%s"\n' "$1" "$name" >&2
        shift
        ;;
    esac
  done
  JARVIS_CATALOG+=("$name$JARVIS_FS$cat$JARVIS_FS$mgr$JARVIS_FS$probe$JARVIS_FS$summary$JARVIS_FS$detail$JARVIS_FS$examples$JARVIS_FS$link$JARVIS_FS$related$JARVIS_FS$note")
}

# Declaration order is display order, for both categories and the tools inside
# them. Within a category the rough rule is most-reached-for first.

# ── This repo ────────────────────────────────────────────────────────────────
category repo "This repo" "The commands device-setup adds to every machine"

tool jarvis repo repo:bin/jarvis \
  -s "browse every tool on this machine, and install or upgrade across managers" \
  -d "What you are looking at. Every tool this repo puts on the machine is in
one list with its docs and examples, whatever installed it — a brew formula, a
uv tool, a cargo crate, a script in bin/, or an alias in zsh/rc.zsh all look the
same here.

The install and upgrade subcommands take the same view: name a tool and jarvis
works out which manager owns it. 'jarvis upgrade' walks every manager on the
machine in turn, so there is one command to run instead of five to remember.

In the browser:

  type          filter the list
  enter         the full page for the highlighted tool
  tab           put one of that tool's examples on a real shell prompt, ready
                to edit and run. Nothing runs until you press enter, and it's
                your interactive shell, so aliases and functions work
  ctrl-y        copy the first example to the clipboard
  ctrl-o        open the tool's homepage
  ctrl-r        re-probe what's installed
  esc           quit

On the full page, esc, backspace and q all go back, and tab does the same thing
it does in the list." \
  -x "jarvis" "the browser: type to filter, enter for full docs" \
  -x "jarvis show rg" "docs and examples for one tool" \
  -x "jarvis list search" "everything in the search category, plain text" \
  -x "jarvis status" "what's installed, what's missing, per manager" \
  -x "jarvis install" "install everything declared but missing" \
  -x "jarvis install rg" "install one tool, whichever manager owns it" \
  -x "jarvis upgrade" "upgrade every manager on the machine" \
  -x "jarvis upgrade brew uv" "upgrade only those" \
  -x "jarvis doctor" "check the catalog, the registry and the machine agree" \
  -r "apply identity"

tool apply repo repo:bin/apply \
  -s "pull this repo and reconcile the machine against it" \
  -d "The command you run from then on, after setup.sh has run once. It pulls,
re-execs the version it just pulled, installs anything declared in
lib/packages.sh but missing, reapplies the nvim overlay, and relinks the shell
config and everything in bin/.

No sudo and no prompts, and cheap when there's nothing to do — so it's safe to
run on a hunch. 'apply -u' additionally upgrades what's already installed,
which is the same work as 'jarvis upgrade'." \
  -x "apply" "install anything newly declared" \
  -x "apply -u" "...and upgrade everything first" \
  -x "apply --skip-pull" "reconcile the working tree without pulling" \
  -r "jarvis identity"

tool identity repo repo:bin/identity \
  -s "set up the SSH key, GitHub auth and git identity" \
  -d "The interactive part of a new machine: generates an ed25519 key, adds it
to the agent and the keychain, authenticates gh, uploads the public key, and
sets git user.name and user.email.

setup.sh runs it as its last step, so a new machine needs nothing by hand. It
stays a separate command because it's the one part that can be needed again —
a new key, or a re-auth after a token expires. Deliberately not part of apply,
whose contract is no sudo and no prompts." \
  -x "identity" "run every step; each is a no-op if already done" \
  -r "apply gh"

# ── Search & navigation ──────────────────────────────────────────────────────
category search "Search & navigation" "Finding files, text, and code shapes"

tool rg search brew:ripgrep \
  -s "recursive grep that respects .gitignore and skips binaries" \
  -d "The default for finding a name. Recursive, parallel and gitignore-aware,
so the hits are the files that actually matter with no --exclude-dir
boilerplate, and it skips binaries on its own.

Use -F for a literal string containing regex metacharacters, and -w for
whole-word matches — those two cut most false positives." \
  -x "rg createSession" "search every tracked file, recursively" \
  -x "rg -t py 'def handle_'" "restrict to one language" \
  -x "rg -n --hidden -g '!node_modules' foo" "include dotfiles, still prune noise" \
  -x "rg -l TODO" "just the filenames" \
  -x "rg -A3 -B3 'panic!'" "three lines of context either side" \
  -l "https://github.com/BurntSushi/ripgrep" \
  -r "fd ast-grep rgv"

tool fd search brew:fd \
  -s "find files by name, with sane defaults" \
  -d "Substring or regex match on the filename, gitignore-aware and parallel.
No -name / -type f / -print0 incantation, and the output is already usable.

Hidden and ignored files are excluded by default, which is usually right and
occasionally not — -H and -I put them back." \
  -x "fd config" "any path whose name contains \"config\"" \
  -x "fd -e ts -e tsx" "by extension" \
  -x "fd -H -I '\\.env'" "include hidden and gitignored files" \
  -x "fd -t d migrations" "directories only" \
  -x "fd -e py -x ruff check" "run a command per match" \
  -l "https://github.com/sharkdp/fd" \
  -r "rg fzf"

tool ast-grep search brew:ast-grep \
  -s "structural search and rewrite that understands syntax, not text" \
  -d "Use it when the pattern is about the shape of the code rather than its
characters — a call, a signature, an expression — so formatting, line breaks
and variable names stop mattering. rg can't do this without a brittle regex.

Rule of thumb: rg to find a name, ast-grep to find a construct or to refactor
one mechanically. Prefer the ast-grep binary; the sg alias is deprecated and
prints a warning." \
  -x "ast-grep -p 'console.log(\$\$\$)' -l ts" "every console.log, any arguments" \
  -x "ast-grep -p 'except: pass' -l py" "bare swallowed exceptions" \
  -x "ast-grep -p 'useEffect(\$A, [])' -l tsx" "mount-only effects" \
  -x "ast-grep -p 'foo(\$X)' -r 'bar(\$X)' -l js -U" "structural rewrite, in place" \
  -l "https://ast-grep.github.io" \
  -r "rg sd"

tool rgv search zsh:function \
  -s "ripgrep into fzf into nvim: search, pick a match, edit it there" \
  -d "A function in zsh/rc.zsh. Type the pattern live and the result list
reloads as you type; the preview pane shows the hit in context through bat.
Enter opens nvim at the line and column, tab multi-selects and the selection
becomes a quickfix list.

This is the one to reach for when the search is a step towards an edit, which
is most of the time." \
  -x "rgv" "search \$PWD, type the pattern live" \
  -x "rgv foo" "start with \"foo\" as the pattern" \
  -x "rgv foo src/" "search src/ instead" \
  -x "rgv src/" "search src/, type the pattern live" \
  -r "rg fzf bat"

tool fzf search brew:fzf \
  -s "fuzzy finder that turns any list into a picker" \
  -d "Used directly, and used underneath — rgv, netif and jarvis are all fzf
front-ends. It binds Ctrl-T for files and Alt-C for cd; Ctrl-R would be history
but atuin takes that over further down rc.zsh.

FZF_DEFAULT_COMMAND is set to fd in rc.zsh, so its file lists are gitignore-
aware too." \
  -x "vim \$(fzf)" "pick a file, open it" \
  -x "git branch | fzf" "pick from any list on stdin" \
  -x "fzf --preview 'bat --color=always {}'" "with a preview pane" \
  -l "https://github.com/junegunn/fzf" \
  -r "rgv zoxide bat"

tool z search brew:zoxide \
  -s "cd to a directory by a fragment of its name, ranked by how often you go there" \
  -p zoxide \
  -d "Tracks the directories you visit and jumps to the best match, so a deep
path becomes a few characters. The database builds itself — nothing to seed.

zi opens the matches in fzf when the ranking guesses wrong." \
  -x "z setup" "jump to the best-matching directory containing \"setup\"" \
  -x "z dev setup" "match on several fragments in order" \
  -x "zi" "pick from the matches interactively" \
  -x "z -" "back to the previous directory" \
  -l "https://github.com/ajeetdsouza/zoxide" \
  -r "fzf try"

tool scc search brew:scc \
  -s "line and complexity counts per language, fast" \
  -d "How to orient in a repo you haven't seen: what it's written in, how big
it is, and where the complexity actually lives — in one command. Faster than
cloc and it estimates complexity per file, which wc -l can't." \
  -x "scc" "summary table by language" \
  -x "scc --by-file --sort complexity" "hottest files first" \
  -x "scc src/ --exclude-dir vendor,dist" "scope it down" \
  -l "https://github.com/boyter/scc"

# ── Files & text ─────────────────────────────────────────────────────────────
category files "Files & text" "Listing, reading, editing and parsing"

tool ls files zsh:alias \
  -s "eza with icons and directories first — plus lsa, lt, lta and ll" \
  -p eza \
  -d "Five aliases in zsh/rc.zsh, all eza underneath. They're defined after Oh
My Zsh loads so they win over its own ls alias.

  ls   grid, directories first, icons
  lsa  the same, plus dotfiles
  lt   tree, two levels deep
  lta  the same, plus dotfiles
  ll   long listing with git status per file

The tree views skip .git and node_modules, which is what keeps lta readable in
a JavaScript project." \
  -x "ls" "grid, directories first, icons" \
  -x "lsa" "include dotfiles" \
  -x "lt" "tree, two levels deep" \
  -x "ll" "long listing with git status" \
  -r "eza"

tool eza files brew:eza \
  -s "a modern ls: icons, git status, tree mode" \
  -d "Installed for the ls/lsa/lt/lta/ll aliases above, and worth calling
directly when you want a flag the aliases don't set." \
  -x "eza --long --git --header" "long listing with a header row" \
  -x "eza --tree --level=3" "three levels deep" \
  -x "eza --sort=modified --reverse" "newest last" \
  -l "https://github.com/eza-community/eza" \
  -r "ls bat"

tool bat files brew:bat \
  -s "cat with syntax highlighting, line numbers and git gutters" \
  -d "Also the preview renderer inside rgv and jarvis. Pipe into it with -l to
force a language when the content has no filename to infer from." \
  -x "bat src/main.rs" "highlighted, with line numbers" \
  -x "mdget example.com | bat -l md" "force a language for piped input" \
  -x "bat -p file.txt" "plain: no line numbers or decorations" \
  -x "bat --style=numbers --highlight-line 42 f.py" "call out one line" \
  -l "https://github.com/sharkdp/bat" \
  -r "eza mdget"

tool jq files brew:jq \
  -s "a real query language over JSON" \
  -p "$JARVIS_BREW_PREFIX/bin/jq" \
  -d "Never parse JSON with grep, sed or awk — quoting, nesting and escaping
make that wrong in ways that fail silently. jq queries the document and
round-trips valid JSON back out.

-r for raw strings when feeding another command, -e to make a check scriptable,
and --arg / --argjson rather than interpolating shell variables into the filter.

Path-probed rather than name-probed: macOS 26 ships a /usr/bin/jq, so the bare
name resolves even on a machine that never got Homebrew's newer one." \
  -x "jq '.dependencies | keys' package.json" "navigate and transform" \
  -x "jq -r '.items[].name' data.json" "raw strings, no quotes" \
  -x "jq '.[] | select(.status == \"failed\")' r.json" "filter" \
  -x "jq --arg v \"\$VER\" '.version = \$v' p.json" "inject a shell variable safely" \
  -x "jq -e '.version' pkg.json >/dev/null" "exit nonzero if null or missing" \
  -l "https://jqlang.github.io/jq/manual/" \
  -r "yq gh"

tool yq files brew:yq \
  -s "jq's syntax applied to YAML — and TOML, XML and CSV" \
  -d "Use it for CI configs, k8s manifests, docker-compose.yml and Helm values
instead of hand-rolled line matching. Same filters as jq, plus format
conversion, and -i edits in place while preserving comments.

This is mikefarah's Go yq (v4), not the older v3 and not the Python wrapper of
the same name — so it's 'yq .foo file', not 'yq -r .foo < file'. For
multi-document YAML, which is the norm in k8s, use 'yq ea' so the documents are
evaluated together rather than one at a time." \
  -x "yq '.jobs | keys' .github/workflows/ci.yml" "navigate a CI config" \
  -x "yq '.services.web.image' docker-compose.yml" "one value" \
  -x "yq -o=json '.' config.yaml" "YAML to JSON, then pipe to jq" \
  -x "yq -i '.version = \"2.0\"' chart.yaml" "edit in place, comments preserved" \
  -x "yq ea '[.]' *.yaml" "evaluate a multi-document stream as one" \
  -l "https://mikefarah.gitbook.io/yq/" \
  -r "jq"

tool sd files brew:sd \
  -s "find and replace with plain regex instead of sed's dialect" \
  -d "sed's escaping rules are their own language; sd takes the regex you
already know and the replacement syntax you'd expect. In-place by default when
given files." \
  -x "sd 'foo' 'bar' file.txt" "replace in one file" \
  -x "sd 'v(\\d+)' 'version\$1' *.md" "capture groups as \$1, not \\1" \
  -x "fd -e py -x sd 'old_name' 'new_name'" "across every match" \
  -l "https://github.com/chmln/sd" \
  -r "ast-grep rg"

tool rm files zsh:function \
  -p trash \
  -s "moves to the Trash instead of unlinking — recoverable in Finder" \
  -d "A function in zsh/rc.zsh wrapping /usr/bin/trash, so deletions are
recoverable with Finder's \"Put Back\".

rm's flags are dropped rather than forwarded, which is what keeps 'rm -rf build'
working: trash needs neither -r (a directory moves whole) nor -f (it never
prompts), and would otherwise reject -rf as unrecognised and still exit 0.

Interactive shells only — scripts, subprocesses and 'command rm' all still get
the real rm. Reach for 'command rm' when you mean it: something too big for the
Trash volume, or a path that has to be gone now rather than later." \
  -x "rm build/" "moves it to the Trash" \
  -x "command rm -rf build/" "the real rm, when you mean it" \
  -r "trash"

tool trash files system: \
  -s "move files to the Trash from the command line — ships with macOS 15+" \
  -d "Nothing installs this: macOS 15 added /usr/bin/trash, which is exactly
why Homebrew's trash and macos-trash formulae are both keg-only now. The rm
function above is a wrapper around it." \
  -x "trash old-file.txt" "straight to the Trash" \
  -r "rm"

# ── Git & GitHub ─────────────────────────────────────────────────────────────
category git "Git & GitHub" "Version control, and the GitHub side of it"

tool git git brew:git \
  -s "Homebrew's git, which is newer than the one macOS ships" \
  -p "$JARVIS_BREW_PREFIX/bin/git" \
  -d "Declared because /usr/bin/git always exists but is often too old —
LazyVim wants 2.19 or newer, which the system copy doesn't reliably satisfy.
The Homebrew prefix comes first on PATH, so the newer one wins.

Path-probed for that exact reason: probing the bare name would always succeed
and the newer git would never get installed." \
  -x "git --version" "confirm you're on the Homebrew one" \
  -x "command -v git" "should be under \$HOMEBREW_PREFIX/bin" \
  -r "gh lazygit"

tool gh git brew:gh \
  -s "GitHub from the terminal: PRs, issues, releases, the API" \
  -d "Also what 'identity' authenticates and uses to upload your SSH key.

Its --json flag emits real JSON for most subcommands, which is the right way to
script against it — scraping the human-readable output breaks on the next
release." \
  -x "gh pr create --fill" "open a PR from the current branch" \
  -x "gh pr list --json number,title" "machine-readable, ready for jq" \
  -x "gh pr checkout 42" "check out someone else's PR" \
  -x "gh run watch" "follow the current CI run" \
  -x "gh api repos/:owner/:repo/releases" "raw API calls" \
  -l "https://cli.github.com/manual/" \
  -r "git jq identity"

tool lazygit git brew:lazygit \
  -s "a full-screen git UI for staging, rebasing and history" \
  -d "Where interactive rebases and partial staging stop being fiddly. Also
LazyVim's git interface — <leader>gg opens it inside the editor with the same
keys." \
  -x "lazygit" "open it on the current repo" \
  -l "https://github.com/jesseduffield/lazygit" \
  -r "git nvim"

# ── Shell & environment ──────────────────────────────────────────────────────
category shell "Shell & environment" "History, directories, prompts and env vars"

tool atuin shell brew:atuin \
  -s "shell history in SQLite, searchable and synced across machines" \
  -d "Takes over Ctrl-R from fzf — rc.zsh initialises fzf first and atuin
after, so the last binding wins. Drop the atuin init line if you'd rather keep
fzf's history search.

On a new machine 'atuin import auto' pulls in the existing history file, which
is worth doing before the old one gets rotated away." \
  -x "atuin import auto" "seed it from your existing shell history" \
  -x "atuin search docker" "search without the interactive UI" \
  -x "atuin stats" "what you actually run" \
  -l "https://atuin.sh" \
  -r "fzf"

tool direnv shell brew:direnv \
  -s "per-directory environment variables, loaded on cd" \
  -d "Put an .envrc in a project and its variables exist inside that directory
and nowhere else. Every new or changed .envrc has to be approved with 'direnv
allow' before it runs — that prompt is the security model, so don't reflexively
dismiss it in a repo you don't trust." \
  -x "echo 'export API_URL=...' > .envrc" "declare it" \
  -x "direnv allow" "approve the file so it loads" \
  -x "direnv status" "why isn't it loading?" \
  -l "https://direnv.net" \
  -r "try"

tool try shell brew:try \
  -s "a scratch directory per experiment, named and dated" \
  -d "For the code you write to answer a question rather than to keep. Each
call makes a directory under \$TRY_PATH (~/src/tries, created by setup.sh) and
cds into it, so throwaway work stops accumulating in ~/Downloads or on the
Desktop.

From tobi/try, which is why it needs its own tap." \
  -x "try parse-csv" "new scratch dir, and cd into it" \
  -x "try" "list what's there and pick one" \
  -l "https://github.com/tobi/try" \
  -r "z direnv"

tool gum shell brew:gum \
  -s "prompts, spinners and styled output for shell scripts" \
  -d "What makes a bash script feel like an application: choosers, filters,
confirmations, spinners and styled text, each a command that reads stdin and
writes stdout. bin/nomprofile and bin/netif are both built on it, and so is
jarvis's confirmation step." \
  -x "gum choose one two three" "a picker; the choice goes to stdout" \
  -x "gum confirm 'Proceed?' && echo yes" "exit status is the answer" \
  -x "gum spin --title Working -- sleep 3" "spinner around a slow command" \
  -x "gum style --border rounded --padding '1 2' hi" "styled output" \
  -l "https://github.com/charmbracelet/gum" \
  -r "fzf nomprofile"

tool add_path shell zsh:function \
  -s "prepend to PATH, but only if the directory exists and isn't already there" \
  -d "How rc.zsh builds PATH. Plain PATH=\"\$dir:\$PATH\" lines duplicate every
entry when the file is sourced twice — which a nested shell does routinely —
and leave a dead entry on a machine that never ran, say, cargo install.

'typeset -U path' alongside it cleans duplicates that arrived in the inherited
environment, keeping the first occurrence so precedence survives. Each call
prepends, so the first line in rc.zsh ends up deepest: .local/bin, then
.cargo/bin, then pnpm." \
  -x "add_path \"\$HOME/.local/bin\"" "no-op if absent or already present"

# ── Network & web ────────────────────────────────────────────────────────────
category net "Network & web" "What's on the wire, and what's on the web"

tool netscan net repo:bin/netscan \
  -s "every device on the local subnet: address, hostname, MAC and vendor" \
  -d "About three seconds for a /24, with no root and no scanner binary — ping,
arp and dig all ship with macOS.

A parallel ICMP sweep followed by a read of the ARP cache. The sweep is really
there to force ARP resolution: a device that drops pings still has to answer
the ARP who-has to stay on the network, so the cache is a superset of the ping
replies. That's what the VIA column records, and 'arp' there is a real signal —
the host is up but filtering ICMP, not absent.

Hostnames come from reverse DNS first, then multicast DNS for whatever unicast
DNS didn't answer, which is where Macs, phones, printers and Pis announce
themselves. Vendors are read out of nmap's bundled IEEE OUI table; nothing runs
nmap. A MAC with the locally-administered bit set is labelled (randomized) —
every current phone rotates one per network, so there is no vendor to find." \
  -x "netscan" "the subnet behind the default route" \
  -x "netscan -i en1" "a specific interface's subnet" \
  -x "netscan 192.168.4.0/24" "an explicit range (a bare IP means /24)" \
  -x "netscan -A" "skip the sweep, just print the ARP cache — instant" \
  -x "netscan -n" "skip hostname lookups" \
  -x "netscan --json | jq ." "the same rows as objects" \
  -r "netif nmap jq"

tool netif net repo:bin/netif \
  -s "interactive viewer and editor for macOS network interfaces" \
  -d "An fzf list of every interface with its service, IPv4, mask, config
method and link state, and a detail view per interface. Enter copies a field,
ctrl-e edits the rows marked +, ctrl-d puts a service back on DHCP. Edits go
through networksetup, so they persist and need sudo.

The IPv4 rows show the stored config, not the live address off ifconfig — so an
unplugged adapter still shows the static IP you gave it and stays editable, and
a separate Active IPv4 row carries the live value. Blanking the router bounces
the service through DHCP, which is the only way networksetup will clear one." \
  -x "netif" "the interface list" \
  -r "netscan"

tool mdget net repo:bin/mdget \
  -s "fetch a URL as markdown, with the nav and ads stripped" \
  -d "Wraps the r.jina.ai reader proxy: prefix any URL with it and you get the
page's main content back as markdown, without the navigation, cookie banners
and script tags. Good for reading docs in the terminal, and for piping a page
into an LLM without 200KB of markup wrapped around it.

Anonymous requests are rate-limited and whole networks are blocked by ASN — AT&T
is one — so this usually needs a key on a home connection. Free keys are at
jina.ai/api-dashboard; put it in ~/.zshrc.local as 'export JINA_API_KEY=...'." \
  -x "mdget https://example.com/docs" "straight to the terminal" \
  -x "mdget example.com/docs | bat -l md" "highlighted" \
  -x "mdget https://example.com/docs | pbcopy" "onto the clipboard" \
  -r "bat http"

tool http net uv:httpie \
  -s "a friendlier curl: JSON by default, coloured output" \
  -d "Installed as the httpie package, which provides http, https and httpie.
Request bodies are key=value pairs rather than hand-written JSON, and responses
are formatted and highlighted without piping anywhere.

Reach for curl when you need its exact flags or you're writing something
portable; reach for http when you're exploring an API by hand." \
  -x "http example.com/api/users" "GET, formatted and coloured" \
  -x "http POST example.com/api name=jane age:=30" ":= for non-string JSON" \
  -x "http -A bearer -a \"\$TOKEN\" example.com/api" "bearer auth" \
  -x "http --print=Hh example.com" "headers only, request and response" \
  -l "https://httpie.io/docs/cli" \
  -r "mdget jq wget"

tool wget net brew:wget \
  -s "download over HTTP, with resume and recursion" \
  -d "Declared mostly because mason (Neovim's LSP installer) falls back to it
when curl is unavailable, but it earns its place for -c and for mirroring." \
  -x "wget -c https://example.com/big.iso" "resume a partial download" \
  -x "wget -r -np -k https://example.com/docs/" "mirror a docs tree" \
  -r "http mdget"

tool nmap net brew:nmap \
  -s "port scanner — and the IEEE OUI table netscan reads for MAC vendors" \
  -d "netscan never runs nmap; it only reads the vendor database nmap ships,
which is why nmap is declared. That table beats arp-scan's ieee-oui.txt, whose
snapshot is years old and missing Raspberry Pi and half of Ubiquiti.

Scan only networks you're responsible for." \
  -x "nmap -sn 192.168.1.0/24" "host discovery, no port scan" \
  -x "nmap -p 22,80,443 192.168.1.10" "specific ports on one host" \
  -x "nmap -A 192.168.1.10" "service and OS detection" \
  -l "https://nmap.org/book/man.html" \
  -r "netscan"

tool arp-scan net brew:arp-scan \
  -s "layer-2 ARP sweep — asks the wire directly, and needs root" \
  -d "Where netscan infers a host list from an ICMP sweep plus whatever landed
in the ARP cache, this sends the ARP requests itself. That makes it the more
authoritative answer on a local segment — nothing on the network can decline to
answer an ARP who-has and still be reachable — and it's faster, because it never
waits on ping timeouts.

The cost is root: raw sockets, so every run is 'sudo arp-scan'. Reach for
netscan when you want a quick unprivileged look, and for this when you need to
be sure nothing was missed.

Vendor names are the one place nmap's table still wins. arp-scan 1.10.0 ships
an ieee-oui.txt generated in December 2022, about 4,700 registrations behind
nmap's — which is why bin/netscan reads nmap's instead. You can't simply point
--ouifile at nmap's file to close the gap: arp-scan wants tab-separated
prefix/vendor pairs and nmap's table is space-separated, so the two aren't
interchangeable.

Scan only networks you're responsible for." \
  -x "sudo arp-scan --localnet" "every host on the interface's own subnet" \
  -x "sudo arp-scan -I en1 --localnet" "a specific interface" \
  -x "sudo arp-scan 192.168.4.0/24" "an explicit range" \
  -x "sudo arp-scan --localnet --plain" "addresses and MACs only, for scripting" \
  -l "https://github.com/royhills/arp-scan" \
  -r "netscan nmap netif"

# ── Languages & editors ──────────────────────────────────────────────────────
category dev "Languages & editors" "Writing and running code"

tool nvim dev brew:neovim \
  -s "Neovim, configured as LazyVim with this repo's overlay on top" \
  -d "setup.sh clones the LazyVim starter into ~/.config/nvim and copies the
four files under nvim/ over the top; those exist only to clear :LazyHealth
warnings, and each carries a comment saying why. The overlay is reapplied on
every apply, so this repo stays the source of truth — anything on disk that
differs is backed up first, never clobbered.

The one manual step nothing here can do for you: set the terminal font to
'JetBrainsMono NFM', or every LazyVim icon renders as an empty box." \
  -x "nvim" "the dashboard" \
  -x "nvim -c 'lua vim.cmd.checkhealth()'" ":LazyHealth from outside" \
  -x "vim file.txt" "aliased to nvim in rc.zsh" \
  -l "https://www.lazyvim.org/keymaps" \
  -r "lazygit rgv ruff"

tool node dev brew:node \
  -s "Node.js — and npm, which mason uses for LSP servers and formatters" \
  -d "Declared for Neovim's sake more than for JavaScript's: mason installs
most of its language servers and formatters from npm, so nothing in the editor
works without it." \
  -x "node --version" "" \
  -x "npm install -g typescript-language-server" "what mason does under the hood" \
  -r "pnpm nvim"

tool ruff dev uv:ruff \
  -s "Python linter and formatter, fast enough to run on save" \
  -d "Replaces flake8, isort, pyupgrade and black with one binary. Installed as
a uv tool, so it gets its own venv and never collides with a project's
dependencies." \
  -x "ruff check ." "lint" \
  -x "ruff check --fix ." "lint and apply the safe fixes" \
  -x "ruff format ." "format" \
  -x "fd -e py -x ruff check" "one invocation per file" \
  -l "https://docs.astral.sh/ruff/rules/" \
  -r "uv nvim"

tool jupyter-lab dev uv:jupyterlab \
  -s "JupyterLab notebooks — note the hyphen, there is no bare 'jupyter'" \
  -d "Launch it as 'jupyter-lab', not 'jupyter lab'. 'uv tool install' only
shims the entry points of the package you named, and the bare jupyter
dispatcher belongs to jupyter-core, a dependency, so it never gets one.
Installing jupyter-core separately would shim jupyter — into its own venv, with
no view of JupyterLab, which is worse." \
  -x "jupyter-lab" "start the server and open a browser" \
  -x "jupyter-lab --no-browser --port 8889" "for an SSH tunnel" \
  -l "https://jupyterlab.readthedocs.io" \
  -r "uv julia"

tool julia dev juliaup: \
  -s "Julia, version-managed by juliaup" \
  -d "juliaup rather than the julia formula, for the same reason rustup is
preferred over 'brew install rust': it multiplexes versions and handles the
upgrade. The two brew formulae conflict — both provide a julia binary — so only
one may ever be installed.

'Installed' has two levels here: juliaup itself, then a channel. That's why it
lives in reconcile.sh rather than as a one-line declaration in packages.sh." \
  -x "julia" "the REPL" \
  -x "juliaup status" "which channels are installed" \
  -x "juliaup update" "update the channels" \
  -l "https://docs.julialang.org" \
  -r "juliaup"

tool nerd-font dev cask:font-jetbrains-mono-nerd-font \
  -p "$JARVIS_BREW_PREFIX/Caskroom/font-jetbrains-mono-nerd-font" \
  -s "JetBrainsMono Nerd Font — without it every LazyVim icon is an empty box" \
  -d "The one step nothing here can finish for you. Installing the font is half
the job; the terminal has to be pointed at it, and no script can do that.

Set the terminal font to 'JetBrainsMono NFM' — iTerm2: Settings > Profiles >
Text > Font. Recent Nerd Fonts releases register short family names, so the
picker lists 'JetBrainsMono NFM' rather than 'JetBrains Mono Nerd Font'. NFM is
the Mono variant, which keeps icon glyphs to one cell — that's what stops
LazyVim's statusline and file tree from drifting out of alignment.

Set INSTALL_NERD_FONT=false before running setup.sh to opt out. Probed by its
Caskroom directory rather than by a command name, because a font cask puts
nothing on PATH." \
  -x "brew list --cask font-jetbrains-mono-nerd-font" "confirm it's installed" \
  -r "nvim"

tool just dev brew:just \
  -s "project-scoped command runner — a Makefile without the make" \
  -d "A justfile holds the commands a project needs — build, test, deploy,
seed-db — under names anyone can discover with 'just --list'. It's what a
Makefile gets used as, without the parts that make that painful: no tab
significance, no implicit rules, no phony targets, and recipes are just shell.

Recipes take parameters and can be written in any language with a shebang line.
It looks up the justfile from the current directory upwards, so it works from
anywhere inside a project." \
  -x "just --list" "every recipe, with its doc comment" \
  -x "just test" "run a recipe" \
  -x "just deploy staging" "recipes take parameters" \
  -x "just --fmt --unstable" "format the justfile" \
  -l "https://just.systems/man/en/" \
  -r "direnv"

tool shellcheck dev brew:shellcheck \
  -s "static analysis for shell scripts — it catches the quoting bugs" \
  -d "What lints the scripts in this repo. Most of what it flags is real:
unquoted expansions that word-split, [ vs [[, and the read-in-a-pipeline
subshell trap.

It has no zsh support at all — bin/jarvis and bin/netif get SC1071 and nothing
else, so those two are checked with 'zsh -n' instead. Use -s bash for the files
under lib/, which are sourced and have no shebang to tell it. Silence a
deliberate exception with a '# shellcheck disable=SCxxxx' comment on the line
above, rather than by rewriting around it." \
  -x "shellcheck bin/apply" "lint one script" \
  -x "shellcheck -s bash lib/*.sh" "the sourced files, which have no shebang" \
  -x "shellcheck -x bin/apply" "follow the files it sources" \
  -x "zsh -n bin/jarvis" "the zsh scripts, which shellcheck won't read" \
  -l "https://www.shellcheck.net/wiki/" \
  -r "gum"

# ── Nominal ──────────────────────────────────────────────────────────────────
category nominal "Nominal" "The Nominal CLI and its profiles"

tool nomctl nominal cargo:nominal-cli \
  -s "the Nominal CLI" \
  -d "Installed with 'cargo install' from the nominal-cli crate, so the binary
lands in ~/.cargo/bin — which rc.zsh already has on PATH. There's no Homebrew
formula for it.

Note that cargo has no upgrade command of its own; see 'jarvis upgrade cargo'
for what that means in practice." \
  -x "nomctl --version" "" \
  -x "nomctl config profile list" "the profiles you have" \
  -x "nomconfig" "aliased to 'nomctl config profile'" \
  -r "nomprofile nomconfig cargo"

tool nomprofile nominal repo:bin/nomprofile \
  -s "a gum TUI for adding a nomctl profile, aliased to nomp" \
  -d "'nomctl config profile add' is a long line of flags to remember; this
prompts for each one instead, with the API URL prefilled. Needs a token.

'nomp' is the alias for it in rc.zsh." \
  -x "nomp" "the short form" \
  -x "nomprofile" "the same thing" \
  -r "nomctl gum"

tool nomconfig nominal zsh:alias \
  -s "alias for 'nomctl config profile'" \
  -p nomctl \
  -d "One of two Nominal aliases in rc.zsh: nomconfig for the profile
subcommand, and nomp for this repo's nomprofile TUI." \
  -x "nomconfig list" "list profiles" \
  -x "nomconfig use dev" "switch profile" \
  -r "nomctl nomprofile"

# ── Package managers ─────────────────────────────────────────────────────────
category managers "Package managers" "The things that install everything else"

tool brew managers brew: \
  -s "Homebrew — most of what's on this machine" \
  -d "Installed by setup.sh, because it can't install itself from a registry
entry. Everything declared with brew_formula or brew_cask in lib/packages.sh
goes through it.

'jarvis upgrade brew' runs update then upgrade, which covers casks too." \
  -x "brew leaves --installed-on-request" "what you asked for, not the dependencies" \
  -x "brew info ripgrep" "what a formula is and what it needs" \
  -x "brew uses --installed ripgrep" "what would break if you removed it" \
  -x "brew autoremove" "drop dependencies nothing needs any more" \
  -l "https://docs.brew.sh" \
  -r "jarvis apply"

tool uv managers brew:uv \
  -s "Python package and project manager — and how the Python CLIs get installed" \
  -d "Two jobs. As a project manager it replaces pip, venv, pip-tools and
pyenv. As a tool installer, 'uv tool install' gives each CLI its own venv under
~/.local/share/uv/tools with a shim in ~/.local/bin — which is why ruff,
JupyterLab and httpie are uv tools rather than brew formulae, and why upgrading
them can't disturb any project environment.

'uv run script.py' with inline PEP 723 dependencies is the fastest way to run a
one-off Python script with third-party imports." \
  -x "uv tool list" "the CLIs uv has installed" \
  -x "uv tool install ruff" "a CLI in its own venv" \
  -x "uv tool upgrade --all" "what 'jarvis upgrade uv' runs" \
  -x "uv run script.py" "run a script in an ephemeral env" \
  -x "uv add requests" "add a dependency to the current project" \
  -l "https://docs.astral.sh/uv/" \
  -r "ruff jupyter-lab http"

tool cargo managers rustup:cargo \
  -s "Rust's build tool and package manager — installs nomctl" \
  -d "Comes from rustup, installed by setup.sh rather than 'brew install rust'
so you get toolchain management, clippy and rustfmt. Binaries land in
~/.cargo/bin, which rc.zsh has on PATH.

The gap worth knowing: 'cargo install' has no upgrade command. It only ever
installs the latest and refuses when that's what you already have, so nothing
re-checks installed crates. 'cargo install cargo-update' adds
'cargo install-update -a', and jarvis will use it if it's there." \
  -x "cargo install-update -a" "upgrade installed crates (needs cargo-update)" \
  -x "cargo install --list" "which crates are installed" \
  -x "rustup update" "the toolchain itself" \
  -l "https://doc.rust-lang.org/cargo/" \
  -r "rustup nomctl"

tool rustup managers rustup: \
  -s "the Rust toolchain installer — rustc, cargo, clippy, rustfmt" \
  -d "Installed by setup.sh with --no-modify-path; rc.zsh puts ~/.cargo/bin on
PATH instead, so nothing appends an unguarded block to your shell config." \
  -x "rustup update" "update every installed toolchain" \
  -x "rustup show" "what's installed and what's default" \
  -x "rustup component add clippy" "add a component" \
  -l "https://rust-lang.github.io/rustup/" \
  -r "cargo"

tool pnpm managers brew:pnpm \
  -s "a faster npm, with a content-addressed store instead of nested copies" \
  -d "Global binaries go in \$PNPM_HOME/bin (~/Library/pnpm/bin), set by hand in
rc.zsh rather than via 'pnpm setup' — which appends its own unguarded block to
.zshrc. Needs the node formula above.

'jarvis upgrade pnpm' runs 'pnpm update --global --latest', which crosses
semver majors: that's what you want from an explicit upgrade and not what pnpm
does by default." \
  -x "pnpm install" "install a project's dependencies" \
  -x "pnpm list --global --depth 0" "what's installed globally" \
  -x "pnpm add --global some-cli" "a global CLI" \
  -x "pnpm dlx create-vite" "run a package without installing it" \
  -l "https://pnpm.io/cli/add" \
  -r "node"

tool juliaup managers brew:juliaup \
  -n "reconcile_julia in lib/reconcile.sh installs it, because it conflicts with the julia formula and needs a channel added afterwards" \
  -s "Julia version manager — installs and multiplexes channels" \
  -d "The julia and juliaup formulae conflict, since both provide a julia
binary; reconcile.sh checks for that and refuses rather than fighting it.

After juliaup itself there's a second step nothing else has: a channel has to
be added before there is any Julia to run. setup.sh does 'juliaup add release'
on a fresh machine." \
  -x "juliaup status" "channels, and which is default" \
  -x "juliaup add lts" "add another channel" \
  -x "juliaup update" "update them all" \
  -l "https://github.com/JuliaLang/juliaup" \
  -r "julia"

return 0
