#!/usr/bin/env bash
# workspace-probe.sh: phase-0 measurements on a Coder workspace, before the
# terminal kit is installed (the H0 checklist of the design; baselines for
# the later re-check).
#
#   workspace-probe.sh baseline [private-repo-url]  H0.1 H0.2 H0.4 H0.6 H0.7
#   workspace-probe.sh terminal --label vscode      H0.3 H0.5, interactive
#   workspace-probe.sh compare <baseline-report> [private-repo-url]
#                                                   re-hash H0.6 and diff
#
# Every report goes to stdout and to
# ~/.cache/terminal-kit-probe/<cmd>-<label>-<timestamp>.txt. A report holds
# no environment values, URLs, host names or home paths: $HOME becomes ~,
# the user name <user>, and a repository URL only appears as a hash.
#
# The only change it makes outside that directory is H0.2's: one line is
# appended to ~/.zshrc and ~/.bashrc and removed again at once (restored
# from a backup, sha256-verified).
set -euo pipefail
shopt -s inherit_errexit

readonly VERSION=1

if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo "workspace-probe: needs bash >= 4" >&2
  exit 2
fi

usage() {
  cat <<'EOF'
usage: workspace-probe.sh [--label NAME] baseline [private-repo-url]
       workspace-probe.sh [--label NAME] terminal
       workspace-probe.sh [--label NAME] compare <baseline-report> [private-repo-url]
       workspace-probe.sh --compare <baseline-report> [private-repo-url]

baseline  nix and /nix (H0.1), rc files reach their end (H0.2), shell start
          time (H0.4), hashes of the rc files, claude, env names, git access
          (H0.6), the process name of nvim (H0.7). No terminal needed.
terminal  OSC 11 and DA1 replies (H0.3) and the OSC 52 clipboard (H0.5).
          Run it once per Windows path, e.g. --label vscode, --label
          alacritty-ssh, --label cmd.
compare   re-hash the H0.6 lines and diff them against a baseline report.
          Exits 1 if any differ.
EOF
}

die() {
  printf 'workspace-probe: %s\n' "$2" >&2
  exit "$1"
}

have() { command -v "$1" >/dev/null 2>&1; }

me=${USER:-$(id -un 2>/dev/null || true)}
host=$(uname -n 2>/dev/null || true)
probe_dir="$HOME/.cache/terminal-kit-probe"
label=nolabel
report=""
status=0

# --- scrubbing: no home path, user, host or URL reaches a report ---------
re_escape() { printf '%s' "$1" | sed 's/[][\/.^$*+?(){}|]/\\&/g'; }
scrub_args=(
  -e 's#[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]'"'"'"]*#<url>#g'
  -e 's#[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:[^[:space:]'"'"'"]*#<url>#g'
)
if [ "${#HOME}" -ge 2 ]; then scrub_args+=(-e "s/$(re_escape "$HOME")/~/g"); fi
if [ "${#me}" -ge 3 ]; then scrub_args+=(-e "s/\\b$(re_escape "$me")\\b/<user>/g"); fi
if [ "${#host}" -ge 3 ]; then scrub_args+=(-e "s/\\b$(re_escape "$host")\\b/<host>/g"); fi
scrub() { sed -E "${scrub_args[@]}"; }

say() {
  if [ -n "$report" ]; then
    printf '%s\n' "$*" | scrub | tee -a "$report"
  else
    printf '%s\n' "$*" | scrub
  fi
}

open_report() {
  local ts
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  mkdir -p "$probe_dir"
  chmod 700 "$probe_dir" 2>/dev/null || true
  report="$probe_dir/$1-$label-$ts.txt"
  : >"$report"
  say "# terminal-kit workspace probe v$VERSION: $1, label $label, $ts"
  say "# system: $(uname -srm 2>/dev/null || echo unknown), bash $BASH_VERSION"
}

sha() {
  if have sha256sum; then
    sha256sum -- "$1" | cut -d' ' -f1
  elif have shasum; then
    shasum -a 256 -- "$1" | cut -d' ' -f1
  else
    return 1
  fi
}
sha_stdin() {
  if have sha256sum; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi
}

rand() { od -An -N4 -tx1 /dev/urandom | tr -d ' \n'; }

# A probe must not hang on a slow or terminal-reading rc file.
# - setsid: a new session without a controlling terminal. Without it,
#   timeout(1) runs the command in a background process group, and an
#   interactive shell whose rc file touches the terminal is stopped by
#   SIGTTIN and never finishes.
# - timeout -k 5: an interactive shell ignores SIGTERM, so KILL follows.
# TK_PROBE_TIMEOUT overrides every timeout (used by the check).
tmo() {
  local s=${TK_PROBE_TIMEOUT:-$1}
  shift
  if have setsid && have timeout; then
    setsid -w timeout -k 5 "$s" "$@"
  elif have timeout; then
    timeout -k 5 "$s" "$@"
  else
    "$@"
  fi
}

now_us() {
  if [ -n "${EPOCHREALTIME:-}" ]; then
    local t=${EPOCHREALTIME/[.,]/}
    printf '%s\n' "$((10#$t))"
  else
    printf '%s\n' "$(($(date +%s%N) / 1000))"
  fi
}

# --- H0.1: nix, /nix, substitution ---------------------------------------
mount_line() {
  local p=$1 line target src fstype opts kept="" o parts
  [ -e "$p" ] || {
    say "H0.1 mount $p: absent"
    return 0
  }
  if have findmnt; then
    line=$(findmnt -n -T "$p" -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null | sed -n 1p || true)
  else
    line=$(df -P "$p" 2>/dev/null | awk 'NR==2 {print $6, $1, "?", "?"}' || true)
  fi
  [ -n "$line" ] || {
    say "H0.1 mount $p: unknown"
    return 0
  }
  read -r target src fstype opts <<<"$line"
  case $src in /dev/*) ;; *) src="<not a device>" ;; esac
  # options with a value (addr=, uid=, ...) may name hosts or ids
  IFS=, read -ra parts <<<"$opts"
  for o in "${parts[@]}"; do case $o in *=*) ;; *) kept+="${kept:+,}$o" ;; esac; done
  say "H0.1 mount $p: on $target, source $src, type $fstype, options $kept"
}

h01() {
  say ""
  say "== H0.1 (A1): nix and the /nix store"
  mount_line /nix
  mount_line /nix/store
  if [ -d /nix ] && have df; then
    say "H0.1 /nix free: $(df -Ph /nix 2>/dev/null | awk 'NR==2 {print $4}' || echo unknown)"
  fi
  if [ -d /nix/store ]; then
    say "H0.1 /nix/store owner: $(stat -c %U /nix/store 2>/dev/null || echo unknown)"
  fi
  if [ -S /nix/var/nix/daemon-socket/socket ]; then
    say "H0.1 nix daemon socket: present (multi-user install)"
  else
    say "H0.1 nix daemon socket: absent (single-user install or no nix)"
  fi
  if ! have nix; then
    say "H0.1 nix: missing (not on PATH); install it before the kit"
    return 0
  fi
  say "H0.1 nix: $(nix --version 2>&1 | sed -n 1p)"
  local xf=(--extra-experimental-features 'nix-command flakes')
  local feats
  feats=$(nix "${xf[@]}" config show experimental-features 2>/dev/null ||
    nix "${xf[@]}" show-config 2>/dev/null | sed -n 's/^experimental-features = //p' || true)
  case " $feats " in
    *" flakes "*) say "H0.1 flakes enabled: yes (experimental-features: $feats)" ;;
    *) say "H0.1 flakes enabled: no (experimental-features: ${feats:-none}); the kit needs nix-command flakes" ;;
  esac
  say "H0.1 store dir: $(nix "${xf[@]}" eval --raw --expr builtins.storeDir 2>/dev/null || echo unknown)"
  local subs n=0 official=no s
  subs=$(nix "${xf[@]}" config show substituters 2>/dev/null || true)
  for s in $subs; do
    case $s in https://cache.nixos.org | https://cache.nixos.org/) official=yes ;; *) n=$((n + 1)) ;; esac
  done
  say "H0.1 substituters: cache.nixos.org $official, $n other"
  say "  running: nix build --dry-run nixpkgs#hello (fetches the nixpkgs flake, builds nothing)"
  local out rc=0 built fetched names
  out=$(tmo 900 nix "${xf[@]}" build --dry-run --no-link nixpkgs#hello 2>&1) || rc=$?
  built=$(printf '%s\n' "$out" | awk '/will be built/ {f=1; next} /will be fetched/ {f=0} f && /^ +\// {n++} END {print n+0}')
  fetched=$(printf '%s\n' "$out" | awk '/will be fetched/ {f=1; next} /will be built/ {f=0} f && /^ +\// {n++} END {print n+0}')
  names=$(printf '%s\n' "$out" | awk '/will be built/ {f=1; next} /will be fetched/ {f=0} f && /^ +\// {print}' |
    sed -E 's#.*/[a-z0-9]{32}-##; s#\.drv$##' | sed -n 1,5p | tr '\n' ' ')
  if [ "$rc" != 0 ]; then
    say "H0.1 hello: error (exit $rc): $(printf '%s\n' "$out" | grep -v '^ ' | tail -n1)"
  elif [ "$built" -gt 0 ]; then
    say "H0.1 hello: would build ($built derivations: $names) — A1 fails if hello itself is built"
  elif [ "$fetched" -gt 0 ]; then
    say "H0.1 hello: substituted ($fetched paths to fetch, nothing to build)"
  else
    say "H0.1 hello: already in the store (nothing to fetch or build; inconclusive)"
  fi
  if tmo 120 nix "${xf[@]}" path-info --store https://cache.nixos.org nixpkgs#hello >/dev/null 2>&1; then
    say "H0.1 cache.nixos.org has this hello: yes (reachable)"
  else
    say "H0.1 cache.nixos.org has this hello: no or unreachable"
  fi
}

# --- H0.2: the end of ~/.zshrc and ~/.bashrc is reached ------------------
# Runs `$1 $2 -c true` for the shell and reports whether the marker printed.
h02_run() {
  local sh=$1 flags=$2 f=$3 marker=$4 o=$5 rc=0 extra
  HOME=$HOME tmo 60 "$sh" "$flags" -c true </dev/null >"$o" 2>&1 || rc=$?
  extra=$({ grep -vF -- "$marker" "$o" || true; } | wc -c | tr -d ' ')
  if grep -qF -- "$marker" "$o"; then
    say "H0.2 ~/${f##*/}: end reached by '$sh $flags' (other output: $extra bytes)"
  elif [ "$rc" = 124 ] || [ "$rc" = 137 ]; then
    say "H0.2 ~/${f##*/}: end NOT reached by '$sh $flags' (timed out after ${TK_PROBE_TIMEOUT:-60} s)"
  else
    say "H0.2 ~/${f##*/}: end NOT reached by '$sh $flags' (exit $rc, other output: $extra bytes)"
  fi
}

h02_one() {
  local sh=$1 f=$2 bakdir=$3 name=\~/"${2##*/}" r marker target orig now
  if ! have "$sh"; then
    say "H0.2 $name: skipped ($sh missing)"
    return 0
  fi
  if [ ! -e "$f" ] && [ ! -L "$f" ]; then
    say "H0.2 $name: absent (not created)"
    return 0
  fi
  if [ -L "$f" ]; then
    target=$(readlink -f -- "$f" || true)
    case $target in
      /nix/store/*)
        say "H0.2 $name: refused (a link into /nix/store; already managed)"
        return 0
        ;;
    esac
  fi
  if [ ! -f "$f" ] || [ ! -r "$f" ] || [ ! -w "$f" ]; then
    say "H0.2 $name: refused (not a readable, writable regular file)"
    return 0
  fi
  orig=$(sha "$f")
  local bak="$bakdir/${f##*/}"
  cp -p -- "$f" "$bak"
  if [ "$(sha "$bak")" != "$orig" ]; then
    say "H0.2 $name: refused (the backup does not match)"
    return 0
  fi
  r=$(rand)
  marker="TK_PROBE-$r"
  say "  $name: sha256 $orig; appending: printf '%s-%s\\n' TK_PROBE $r"
  (
    trap 'cat -- "$bak" >"$f"; touch -r "$bak" -- "$f"' EXIT
    trap 'exit 130' INT TERM HUP
    printf "\\nprintf '%%s-%%s\\\\n' TK_PROBE %s # terminal-kit probe, removed again at once\\n" "$r" >>"$f" || exit 1
    h02_run "$sh" -i "$f" "$marker" "$bakdir/out"
    h02_run "$sh" -il "$f" "$marker" "$bakdir/out"
  ) || true
  now=$(sha "$f")
  if [ "$now" = "$orig" ]; then
    say "H0.2 $name: restored, sha256 identical"
    rm -f -- "$bak" "$bakdir/out"
  else
    say "H0.2 $name: RESTORE FAILED (sha256 $now); the original is in $bak"
    status=3
  fi
}

h02() {
  say ""
  say "== H0.2 (A2): interactive shells reach the end of ~/.zshrc and ~/.bashrc"
  say "  What happens: each file is backed up, one printf line is appended, the"
  say "  shell runs 'true' as '-i' and as '-il' and must print the marker, then the"
  say "  file is restored from the backup (also on Ctrl+C) and its sha256 checked."
  say "  (A login bash reads ~/.bash_profile or ~/.profile, and reaches ~/.bashrc"
  say "  only if one of them sources it.)"
  if ! have sha256sum && ! have shasum; then
    say "H0.2: skipped (no sha256sum or shasum to verify the restore)"
    return 0
  fi
  if [ -n "${ZDOTDIR:-}" ] && [ "$ZDOTDIR" != "$HOME" ]; then
    say "H0.2 ZDOTDIR: set and not \$HOME; zsh reads its .zshrc from there, not ~/.zshrc"
  fi
  local bakdir
  bakdir=$(mktemp -d "$probe_dir/h02-backup.XXXXXX")
  h02_one zsh "$HOME/.zshrc" "$bakdir"
  h02_one bash "$HOME/.bashrc" "$bakdir"
  rmdir -- "$bakdir" 2>/dev/null || say "  backups kept in $bakdir"
}

# --- H0.4: shell start time ----------------------------------------------
h04() {
  say ""
  say "== H0.4 (K2): time zsh -ilc env >/dev/null, 3 runs"
  if ! have zsh; then
    say "H0.4 zsh: missing"
    return 0
  fi
  local t0 t1 runs=()
  for _ in 1 2 3; do
    t0=$(now_us)
    tmo 60 zsh -ilc env </dev/null >/dev/null 2>&1 || true
    t1=$(now_us)
    runs+=($(((t1 - t0) / 1000)))
  done
  local sorted
  mapfile -t sorted < <(printf '%s\n' "${runs[@]}" | sort -n)
  say "H0.4 zsh -ilc env: median ${sorted[1]} ms (runs: ${runs[*]} ms)"
}

# --- H0.6: baselines; the lines `compare` re-computes --------------------
# Prints unscrubbed lines "H0.6 <key> <value>"; the caller scrubs them.
h06_lines() {
  local url=${1:-} f p v envsha names uh
  for f in .zshrc .zshenv .zprofile .bashrc .profile .bash_profile .gitconfig .config/git/config; do
    if [ ! -e "$HOME/$f" ]; then
      echo "H0.6 sha ~/$f absent"
    elif v=$(sha "$HOME/$f" 2>/dev/null); then
      echo "H0.6 sha ~/$f $v"
    else
      echo "H0.6 sha ~/$f unreadable"
    fi
  done
  if p=$(command -v claude 2>/dev/null); then
    echo "H0.6 claude.path $p"
    v=$(tmo 30 claude --version </dev/null 2>&1 | sed -n 1p || true)
    echo "H0.6 claude.version ${v:-no output}"
  else
    echo "H0.6 claude.path missing"
    echo "H0.6 claude.version missing"
  fi
  envsha=$(env | { grep -E '^(ANTHROPIC|CLAUDE|AWS)_' || true; } | sort | sha_stdin)
  names=$(compgen -e | { grep -E '^(ANTHROPIC|CLAUDE|AWS)_' || true; } | sort | tr '\n' ' ')
  echo "H0.6 env.sha $envsha"
  echo "H0.6 env.names ${names:-(none)}"
  if [ -n "$url" ]; then
    uh=$(printf '%s' "$url" | sha_stdin | cut -c1-12)
    if ! have git; then
      echo "H0.6 lsremote $uh skipped (git missing)"
    elif GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND=${GIT_SSH_COMMAND:-ssh -o BatchMode=yes} \
      tmo 30 git ls-remote "$url" </dev/null >/dev/null 2>&1; then
      echo "H0.6 lsremote $uh ok"
    else
      echo "H0.6 lsremote $uh fail"
    fi
  fi
}

h06() {
  say ""
  say "== H0.6 (S7, S8, S10): baselines (env: names only, values hashed)"
  local line
  while IFS= read -r line; do say "$line"; done < <(h06_lines "${1:-}")
}

# --- H0.7: the process name of nvim --------------------------------------
h07() {
  say ""
  say "== H0.7 (A6): does 'pgrep -u \$USER nvim' see Neovim?"
  if ! have nvim; then
    say "H0.7 nvim: missing"
    return 0
  fi
  say "H0.7 nvim: $(nvim --version 2>/dev/null | sed -n 1p), at $(command -v nvim)"
  nvim --headless --clean </dev/null >/dev/null 2>&1 &
  local pid=$! comm children others
  sleep 1
  comm=$(cat "/proc/$pid/comm" 2>/dev/null || ps -o comm= -p "$pid" 2>/dev/null || echo unknown)
  say "H0.7 process name (comm): $comm"
  if have pgrep; then
    if pgrep -u "$me" nvim | grep -qx "$pid"; then
      say "H0.7 pgrep -u <user> nvim: matches the probe's nvim (pkill -USR1 would reach it)"
    else
      say "H0.7 pgrep -u <user> nvim: does NOT match the probe's nvim"
    fi
    children=$(pgrep -a -P "$pid" 2>/dev/null | cut -d' ' -f2- | tr '\n' ';' || true)
    say "H0.7 children: ${children:-none}"
    others=$(pgrep -u "$me" nvim | grep -vxc "$pid" || true)
    say "H0.7 other nvim processes of <user>: $others"
  else
    say "H0.7 pgrep: missing"
  fi
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

cmd_baseline() {
  local url=${1:-}
  case $url in -*) die 2 "not a repository URL: $url" ;; esac
  open_report baseline
  say "This probe reads files and runs nix, zsh, bash, claude, git and nvim briefly."
  say "It changes nothing outside $probe_dir except H0.2's temporary line."
  h01
  h02
  h04
  h06 "$url"
  h07
  say ""
  say "Report saved: $report"
  return "$status"
}

# --- compare: H0.6 now against a baseline report --------------------------
key_of() {
  local b c
  read -r _ b c _ <<<"$1"
  case $b in sha | lsremote) printf '%s %s\n' "$b" "$c" ;; *) printf '%s\n' "$b" ;; esac
}

cmd_compare() {
  local file=${1:-} url=${2:-} line k changed=0
  [ -n "$file" ] || die 2 "compare needs a baseline report"
  [ -r "$file" ] || die 2 "cannot read $file"
  declare -A base=()
  while IFS= read -r line; do
    case $line in "H0.6 "*) base[$(key_of "$line")]=$line ;; esac
  done <"$file"
  [ "${#base[@]}" -gt 0 ] || die 2 "no H0.6 lines in $file"
  open_report compare
  say "compared with: $file"
  local now
  mapfile -t now < <(h06_lines "$url" | scrub)
  for line in "${now[@]}"; do
    k=$(key_of "$line")
    if [ -z "${base[$k]+x}" ]; then
      say "new      $line"
    elif [ "${base[$k]}" = "$line" ]; then
      say "same     $line"
    else
      say "CHANGED  $k: ${base[$k]#"H0.6 $k "} -> ${line#"H0.6 $k "}"
      changed=1
    fi
    unset 'base[$k]'
  done
  for k in "${!base[@]}"; do
    say "not run  ${base[$k]}"
  done
  say ""
  if [ "$changed" = 1 ]; then
    say "Differences found. After the setup, ~/.zshrc and ~/.bashrc are expected to differ"
    say "by the appended snippet; anything else is a regression."
  else
    say "No differences."
  fi
  say "Report saved: $report"
  return "$changed"
}

# --- terminal: H0.3 and H0.5, interactive --------------------------------
tty_saved=""
tty_restore() { if [ -n "$tty_saved" ]; then stty "$tty_saved" <&3 2>/dev/null || true; fi; }

# Everything the terminal sends until it is silent for 1 s, cat -v style.
tty_read() { dd bs=1 count=4096 <&3 2>/dev/null | cat -v; }

ask() {
  local ans
  printf '%s' "$1" >&3
  IFS= read -r ans <&3 || ans=""
  case $ans in y | Y | yes) echo yes ;; n | N | no) echo no ;; *) echo "unsure ($ans)" ;; esac
}

nvim_minor() {
  local v maj min
  v=$(nvim --version 2>/dev/null | sed -n 1p | sed -nE 's/^NVIM v([0-9]+)\.([0-9]+).*/\1 \2/p')
  [ -n "$v" ] || return 1
  read -r maj min <<<"$v"
  [ "$maj" -gt 0 ] || [ "$min" -ge 10 ]
}

h05_nvim() {
  if ! have nvim; then
    say "H0.5 nvim: missing"
    return 0
  fi
  if ! nvim_minor; then
    say "H0.5 nvim: older than 0.10 ($(nvim --version 2>/dev/null | sed -n 1p)); skipped"
    return 0
  fi
  local tok tmp rc=0 feats
  tok="tk-nvim-$(rand)"
  tmp=$(mktemp -d)
  cat >"$tmp/probe.lua" <<EOF
require('vim.ui.clipboard.osc52').copy('+')({ '$tok' }, 'v')
vim.defer_fn(function()
  local f = assert(io.open([[$tmp/features]], 'w'))
  f:write((vim.inspect(vim.g.termfeatures):gsub('%s+', ' ')), '\n')
  f:close()
  vim.cmd('qa!')
end, 1000)
EOF
  say "  running: nvim --clean, copies '$tok' with OSC 52, quits after 1 s"
  if have timeout; then
    timeout --foreground 20 nvim --clean -c "luafile $tmp/probe.lua" <&3 >&3 2>&3 || rc=$?
  else
    nvim --clean -c "luafile $tmp/probe.lua" <&3 >&3 2>&3 || rc=$?
  fi
  if [ "$rc" != 0 ] || [ ! -s "$tmp/features" ]; then
    say "H0.5 nvim run: failed (exit $rc); do it by hand in nvim:"
    say "  :lua require('vim.ui.clipboard.osc52').copy('+')({'nvim-osc52'})"
    say "  then Ctrl+V in Notepad (expect nvim-osc52), and :lua =vim.g.termfeatures"
    rm -rf -- "$tmp"
    return 0
  fi
  feats=$(head -n1 "$tmp/features")
  rm -rf -- "$tmp"
  say "H0.5 nvim termfeatures: $feats"
  say "H0.5 nvim osc52 copy: $(ask "paste in Notepad (Ctrl+V): did you get $tok? [y/n] ")"
}

cmd_terminal() {
  if ! { exec 3<>/dev/tty; } 2>/dev/null; then
    die 2 "terminal needs a terminal (/dev/tty cannot be opened)"
  fi
  have stty || die 2 "terminal needs stty"
  open_report terminal
  say "TERM=${TERM:-unset} TERM_PROGRAM=${TERM_PROGRAM:-unset} COLORTERM=${COLORTERM:-unset} tmux: $([ -n "${TMUX:-}" ] && echo yes || echo no)"
  [ -z "${TMUX:-}" ] || say "  inside tmux: replies and OSC 52 depend on tmux, not the Windows terminal"
  say ""
  say "== H0.3 (F10): OSC 11 background query and DA1"
  tty_saved=$(stty -g <&3)
  trap tty_restore EXIT
  trap 'tty_restore; exit 130' INT TERM HUP
  stty -echo -icanon min 0 time 10 <&3
  # DA1 goes second: every terminal answers it, so its reply marks the end
  printf '\033]11;?\a\033[c' >&3
  local reply
  reply=$(tty_read)
  tty_restore
  say "H0.3 raw reply: ${reply:-(nothing within 1 s)}"
  if [[ $reply == *']11;rgb:'* ]]; then
    local rgb=${reply#*]11;}
    rgb=${rgb%%^*}
    say "H0.3 OSC 11: answered ($rgb)"
  else
    say "H0.3 OSC 11: no rgb reply"
  fi
  local da1
  da1=$(printf '%s' "$reply" | sed -nE 's/.*\^\[\[\?([0-9;]*)c.*/\1/p')
  if [ -z "$da1" ]; then
    say "H0.3 DA1: no reply"
  elif [[ ";$da1;" == *';52;'* ]]; then
    say "H0.3 DA1: $da1 (52 present: the terminal announces OSC 52)"
  else
    say "H0.3 DA1: $da1 (52 absent)"
  fi
  say ""
  say "== H0.5 (Q2 recipe): OSC 52 writes reach the Windows clipboard"
  local tok
  tok="tk-$(rand)"
  printf '\033]52;c;%s\a' "$(printf '%s' "$tok" | base64)" >&3
  say "  sent: OSC 52 with '$tok' (printf from the shell)"
  say "H0.5 shell osc52 copy: $(ask "paste in Notepad (Ctrl+V): did you get $tok? [y/n] ")"
  h05_nvim
  say ""
  say "Report saved: $report"
}

# --- main ----------------------------------------------------------------
cmd=""
args=()
while [ $# -gt 0 ]; do
  case $1 in
    --label)
      [ $# -ge 2 ] || die 2 "--label needs a value"
      label=$2
      shift 2
      ;;
    --label=*)
      label=${1#--label=}
      shift
      ;;
    --compare)
      [ $# -ge 2 ] || die 2 "--compare needs a baseline report"
      cmd=compare
      args+=("$2")
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*) die 2 "unknown option $1 (see --help)" ;;
    *)
      if [ -z "$cmd" ]; then cmd=$1; else args+=("$1"); fi
      shift
      ;;
  esac
done
label=$(printf '%s' "$label" | tr -c 'A-Za-z0-9._-' '_')
[ -n "$label" ] || label=nolabel

case ${cmd:-baseline} in
  baseline) cmd_baseline ${args[@]+"${args[@]}"} ;;
  terminal) cmd_terminal ;;
  compare) cmd_compare ${args[@]+"${args[@]}"} ;;
  *) die 2 "unknown command '$cmd' (see --help)" ;;
esac
