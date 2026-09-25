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
# from a backup, sha256-verified). `baseline` also keeps copies of the
# shell rc files in ~/.cache/terminal-kit-probe/rc-<timestamp>/ (mode 700
# and 600) so that `compare` can show their exact diff on screen; the
# copies and the diff never go into a report.
#
# Every finding gets a level: OK, INFO, HEADS-UP or BLOCKER. A "Summary"
# block ends the output and is also the top of the saved report: either
# "All checks passed" with the INFO lines as notes, or a numbered list of
# the heads-ups and blockers, each with why it matters and what to do.
#
# Exit status: 0 with OK, INFO and HEADS-UP findings only; 1 with a
# BLOCKER; 2 for a usage error; 3 when H0.2 could not restore an rc file.
#
# Test-only hook: TK_PROBE_TIMEOUT overrides every timeout (in seconds).
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
compare   re-hash the H0.6 lines and diff them against a baseline report;
          shows the diff of each changed rc file on screen.

Every finding is OK, INFO, HEADS-UP or BLOCKER; the summary at the end
(and at the top of the saved report) lists what to do. Exit status: 0
without a BLOCKER, 1 with one, 2 for a usage error, 3 when an rc file
could not be restored.
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
report_ts=""
status=0
# the shell rc files: hashed (H0.6), copied by baseline, diffed by compare
rc_files=(.zshrc .zshenv .zprofile .bashrc .profile .bash_profile)
# the entry path every one-time snippet names (PD13)
snippet_mark=.config/terminal-kit/init.

# --- scrubbing: no home path, user, host or URL reaches a report ---------
re_escape() { printf '%s' "$1" | sed 's/[][\/.^$*+?(){}|]/\\&/g'; }
# The official cache is public and named in advice; it survives the URL rule.
scrub_args=(
  -e 's#https://cache\.nixos\.org#TK_OFFICIAL_CACHE#g'
  -e 's#[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]'"'"'"]*#<url>#g'
  -e 's#[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:[^[:space:]'"'"'"]*#<url>#g'
)
if [ "${#HOME}" -ge 2 ]; then scrub_args+=(-e "s/$(re_escape "$HOME")/~/g"); fi
if [ "${#me}" -ge 3 ]; then scrub_args+=(-e "s/\\b$(re_escape "$me")\\b/<user>/g"); fi
if [ "${#host}" -ge 3 ]; then scrub_args+=(-e "s/\\b$(re_escape "$host")\\b/<host>/g"); fi
scrub_args+=(-e 's#TK_OFFICIAL_CACHE#https://cache.nixos.org#g')
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
  report_ts=$ts
  mkdir -p "$probe_dir"
  chmod 700 "$probe_dir" 2>/dev/null || true
  report="$probe_dir/$1-$label-$ts.txt"
  : >"$report"
  say "# terminal-kit workspace probe v$VERSION: $1, label $label, $ts"
  say "# system: $(uname -srm 2>/dev/null || echo unknown), bash $BASH_VERSION"
}

# --- verdicts ------------------------------------------------------------
# finding LEVEL FOUND [WHY DO]: LEVEL is OK, INFO, HEADS-UP or BLOCKER.
# Printed at once, and kept for the summary. WHY is one line naming the
# kit behaviour at stake, DO a concrete command or setting.
f_level=()
f_found=()
f_why=()
f_do=()
finding() {
  f_level+=("$1")
  f_found+=("$2")
  f_why+=("${3:-}")
  f_do+=("${4:-}")
  say "  -> $1: $2"
}

count_level() {
  local n=0 lv
  for lv in ${f_level[@]+"${f_level[@]}"}; do [ "$lv" != "$1" ] || n=$((n + 1)); done
  echo "$n"
}

# The summary block, unscrubbed; $1 completes "All checks passed — ".
# It holds no empty line: the report's copy ends at the first one.
summary_block() {
  local heads blocks i n=0 lv notes=0
  heads=$(count_level HEADS-UP)
  blocks=$(count_level BLOCKER)
  echo "== Summary"
  if [ "$heads" = 0 ] && [ "$blocks" = 0 ]; then
    echo "All checks passed — $1"
  else
    echo "$heads heads-up(s), $blocks blocker(s):"
    for lv in BLOCKER HEADS-UP; do
      for i in ${f_level[@]+"${!f_level[@]}"}; do
        [ "${f_level[$i]}" = "$lv" ] || continue
        n=$((n + 1))
        printf '  %d. %s: %s\n     why: %s\n     do:  %s\n' "$n" "$lv" \
          "${f_found[$i]}" "${f_why[$i]}" "${f_do[$i]}"
      done
    done
  fi
  for i in ${f_level[@]+"${!f_level[@]}"}; do
    [ "${f_level[$i]}" = INFO ] || continue
    [ "$notes" = 1 ] || echo "Notes:"
    notes=1
    printf '  - %s\n' "${f_found[$i]}"
    if [ -n "${f_why[$i]}" ]; then printf '    %s → %s\n' "${f_why[$i]}" "${f_do[$i]}"; fi
  done
}

# Prints the summary, puts it at the top of the report (after the two
# header lines), and returns the exit status.
finish() {
  local s
  s=$(summary_block "$1" | scrub)
  printf '\n%s\n' "$s"
  if [ -n "$report" ]; then
    { sed -n 1,2p "$report"; printf '%s\n\n' "$s"; sed -n '3,$p' "$report"; } >"$report.tmp"
    mv -f -- "$report.tmp" "$report"
  fi
  say ""
  say "Report saved: $report"
  [ "$status" = 0 ] || return "$status"
  [ "$(count_level BLOCKER)" = 0 ] || return 1
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
    finding BLOCKER "nix is not installed (not on PATH)" \
      "F9: the kit is a Home Manager flake; without Nix nothing can be installed" \
      "install single-user Nix (the installer from nixos.org/download, with --no-daemon), open a new shell, re-run the probe"
    return 0
  fi
  say "H0.1 nix: $(nix --version 2>&1 | sed -n 1p)"
  local xf=(--extra-experimental-features 'nix-command flakes')
  local feats
  feats=$(nix "${xf[@]}" config show experimental-features 2>/dev/null ||
    nix "${xf[@]}" show-config 2>/dev/null | sed -n 's/^experimental-features = //p' || true)
  case " $feats " in
    *" flakes "*)
      say "H0.1 flakes enabled: yes (experimental-features: $feats)"
      finding OK "flakes are enabled"
      ;;
    *)
      say "H0.1 flakes enabled: no (experimental-features: ${feats:-none}); the kit needs nix-command flakes"
      finding BLOCKER "flakes are not enabled (experimental-features: ${feats:-none})" \
        "the template is a flake: 'nix flake init' and 'home-manager switch --flake' fail without them" \
        "add this line to ~/.config/nix/nix.conf: experimental-features = nix-command flakes"
      ;;
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
  local subst_do="check that 'nix config show substituters' lists https://cache.nixos.org and that 'nix path-info --store https://cache.nixos.org nixpkgs#hello' works (network, proxy, trusted-public-keys)"
  if [ "$rc" != 0 ]; then
    say "H0.1 hello: error (exit $rc): $(printf '%s\n' "$out" | grep -v '^ ' | tail -n1)"
    finding HEADS-UP "'nix build --dry-run nixpkgs#hello' failed (exit $rc)" \
      "A1 is untested: Nix could not say whether the kit's packages would be fetched or built" \
      "run 'nix build --dry-run nixpkgs#hello' and fix the error it prints (often network or nix.conf)"
  elif [ "$built" -gt 0 ]; then
    say "H0.1 hello: would build ($built derivations: $names) — A1 fails if hello itself is built"
    finding HEADS-UP "nixpkgs#hello would build $built derivations locally (${names% })" \
      "A1: substitutes do not work, so every package of the kit builds from source on the workspace" \
      "$subst_do"
  elif [ "$fetched" -gt 0 ]; then
    say "H0.1 hello: substituted ($fetched paths to fetch, nothing to build)"
    finding OK "nixpkgs#hello is substituted, nothing builds locally"
  else
    say "H0.1 hello: already in the store (nothing to fetch or build; inconclusive)"
    finding INFO "nixpkgs#hello is already in the store; substitution was not exercised" \
      "A1 stays unverified by this run" \
      "nothing, if earlier installs were fetched rather than built"
  fi
  if tmo 120 nix "${xf[@]}" path-info --store https://cache.nixos.org nixpkgs#hello >/dev/null 2>&1; then
    say "H0.1 cache.nixos.org has this hello: yes (reachable)"
    finding OK "cache.nixos.org is reachable"
  else
    say "H0.1 cache.nixos.org has this hello: no or unreachable"
    finding HEADS-UP "cache.nixos.org is unreachable (or lacks this nixpkgs' hello)" \
      "A1: without the official cache every package of the kit builds locally" \
      "$subst_do"
  fi
}

# --- H0.2: the end of ~/.zshrc and ~/.bashrc is reached ------------------
# Runs `$1 $2 -c true` for the shell and reports whether the marker printed.
# Appends "<flags> yes" or "<flags> no <detail>" to $6: the caller runs it
# in a subshell and draws the verdicts after the restore.
h02_run() {
  local sh=$1 flags=$2 f=$3 marker=$4 o=$5 res=$6 rc=0 extra detail
  HOME=$HOME tmo 60 "$sh" "$flags" -c true </dev/null >"$o" 2>&1 || rc=$?
  extra=$({ grep -vF -- "$marker" "$o" || true; } | wc -c | tr -d ' ')
  if grep -qF -- "$marker" "$o"; then
    say "H0.2 ~/${f##*/}: end reached by '$sh $flags' (other output: $extra bytes)"
    echo "$flags yes" >>"$res"
    return 0
  elif [ "$rc" = 124 ] || [ "$rc" = 137 ]; then
    detail="timed out after ${TK_PROBE_TIMEOUT:-60} s"
  else
    detail="exit $rc, other output: $extra bytes"
  fi
  say "H0.2 ~/${f##*/}: end NOT reached by '$sh $flags' ($detail)"
  echo "$flags no $detail" >>"$res"
}

# The verdicts of one rc file, from h02_run's results.
h02_verdict() {
  local sh=$1 name=$2 res=$3 ri rl
  ri=$(sed -n 's/^-i //p' "$res")
  rl=$(sed -n 's/^-il //p' "$res")
  case $sh:$ri in
    zsh:yes) ;;
    zsh:*)
      finding BLOCKER "$name: 'zsh -i' does not reach its end (${ri#no })" \
        "K1: the one-time snippet appended to $name would never run, so zsh never loads the kit" \
        "remove the early exit/return/exec in $name, or put the snippet in ~/.zshenv, guarded: [[ -o interactive ]] && if [ -r \"\$HOME/${snippet_mark}zsh\" ]; then . \"\$HOME/${snippet_mark}zsh\"; fi"
      return 0
      ;;
    bash:yes) ;;
    bash:*)
      finding HEADS-UP "$name: 'bash -i' does not reach its end (${ri#no })" \
        "the one-time snippet appended to $name would never run, so interactive bash stays without the kit" \
        "move the early return/exit in $name below the snippet, or append the snippet before it"
      return 0
      ;;
  esac
  case $sh:$rl in
    *:yes) finding OK "$name: '$sh -i' and '$sh -il' reach its end" ;;
    zsh:*)
      finding HEADS-UP "$name: only 'zsh -i' reaches its end, 'zsh -il' does not (${rl#no })" \
        "K2: login shells (ssh, VS Code's 'zsh -ilc env' probe) would start without the kit" \
        "look for an exit, return or exec in ~/.zprofile and ~/.zshenv, which a login zsh reads first"
      ;;
    bash:*)
      finding INFO "$name: a login bash does not reach it" \
        "a login bash reads ~/.bash_profile or ~/.profile, and ~/.bashrc only if one of them sources it" \
        "nothing, unless you start login bash shells; then source ~/.bashrc from ~/.bash_profile"
      ;;
  esac
}

h02_one() {
  local sh=$1 f=$2 bakdir=$3 name=\~/"${2##*/}" r marker target orig now
  if ! have "$sh"; then
    say "H0.2 $name: skipped ($sh missing)"
    if [ "$sh" = zsh ]; then
      finding HEADS-UP "zsh is not installed; ~/.zshrc and the shell start time are untested" \
        "F9: the kit expects the image's login shell /bin/zsh to load it from ~/.zshrc" \
        "check 'echo \$SHELL'; with bash as the login shell only the ~/.bashrc snippet matters"
    else
      finding INFO "bash is not installed; ~/.bashrc is untested" \
        "only the zsh snippet can load the kit" "nothing"
    fi
    return 0
  fi
  if [ ! -e "$f" ] && [ ! -L "$f" ]; then
    say "H0.2 $name: absent (not created)"
    finding INFO "$name does not exist" \
      "the one-time snippet needs a file to go in" \
      "create $name with the snippet home-manager prints, or put the snippet in the shell's other rc file"
    return 0
  fi
  if [ -L "$f" ]; then
    target=$(readlink -f -- "$f" || true)
    case $target in
      /nix/store/*)
        say "H0.2 $name: refused (a link into /nix/store; already managed)"
        finding INFO "$name is a link into /nix/store (already managed by Home Manager)" \
          "the one-time snippet cannot be appended to a store file" \
          "use shellIntegration = \"owned\" in user.nix, or stop managing $name elsewhere first"
        return 0
        ;;
    esac
  fi
  if [ ! -f "$f" ] || [ ! -r "$f" ] || [ ! -w "$f" ]; then
    say "H0.2 $name: refused (not a readable, writable regular file)"
    finding HEADS-UP "$name is not a readable, writable regular file; untested" \
      "K1: the one-time snippet cannot be appended to it" \
      "check 'ls -l $name'; make it a writable file, or use shellIntegration = \"owned\""
    return 0
  fi
  orig=$(sha "$f")
  local bak="$bakdir/${f##*/}" res="$bakdir/res"
  cp -p -- "$f" "$bak"
  if [ "$(sha "$bak")" != "$orig" ]; then
    say "H0.2 $name: refused (the backup does not match)"
    finding HEADS-UP "$name could not be backed up; untested" \
      "A2/K1: whether $name reaches its end is unknown" \
      "check the free space under ~/.cache and re-run the probe"
    return 0
  fi
  r=$(rand)
  marker="TK_PROBE-$r"
  : >"$res"
  say "  $name: sha256 $orig; appending: printf '%s-%s\\n' TK_PROBE $r"
  (
    trap 'cat -- "$bak" >"$f"; touch -r "$bak" -- "$f"' EXIT
    trap 'exit 130' INT TERM HUP
    printf "\\nprintf '%%s-%%s\\\\n' TK_PROBE %s # terminal-kit probe, removed again at once\\n" "$r" >>"$f" || exit 1
    h02_run "$sh" -i "$f" "$marker" "$bakdir/out" "$res"
    h02_run "$sh" -il "$f" "$marker" "$bakdir/out" "$res"
  ) || true
  now=$(sha "$f")
  if [ "$now" = "$orig" ]; then
    say "H0.2 $name: restored, sha256 identical"
    rm -f -- "$bak" "$bakdir/out"
    h02_verdict "$sh" "$name" "$res"
    rm -f -- "$res"
  else
    say "H0.2 $name: RESTORE FAILED (sha256 $now); the original is in $bak"
    finding BLOCKER "$name was NOT restored after H0.2; the original is in $bak" \
      "the probe's temporary printf line may still be in $name" \
      "cp -p $bak $name, then check with 'tail -n 3 $name'"
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
    finding HEADS-UP "H0.2 skipped: no sha256sum or shasum to verify the restore" \
      "A2/K1: whether ~/.zshrc and ~/.bashrc reach their end is unknown" \
      "check by hand: append 'echo TK_PROBE' to ~/.zshrc, open a new shell, see TK_PROBE, remove the line"
    return 0
  fi
  if [ -n "${ZDOTDIR:-}" ] && [ "$ZDOTDIR" != "$HOME" ]; then
    say "H0.2 ZDOTDIR: set and not \$HOME; zsh reads its .zshrc from there, not ~/.zshrc"
    finding HEADS-UP "ZDOTDIR is set and not \$HOME" \
      "zsh reads \$ZDOTDIR/.zshrc, not ~/.zshrc: a snippet in ~/.zshrc would never run" \
      "put the snippet in \$ZDOTDIR/.zshrc instead of ~/.zshrc"
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
  local ms=${sorted[1]}
  say "H0.4 zsh -ilc env: median $ms ms (runs: ${runs[*]} ms)"
  local prof="profile it: 'zmodload zsh/zprof' at the top of ~/.zshenv, 'zprof' at the end of ~/.zshrc, then 'zsh -ilc true'"
  if [ "$ms" -gt 5000 ]; then
    finding BLOCKER "'zsh -ilc env' takes $ms ms (median), over 5000 ms" \
      "K2: VS Code's environment probe runs 'zsh -ilc env' at every connect; this slow, it times out and the connection fails" \
      "$prof"
  elif [ "$ms" -gt 1000 ]; then
    finding HEADS-UP "'zsh -ilc env' takes $ms ms (median), over 1000 ms" \
      "K2: VS Code's environment probe runs 'zsh -ilc env' at every connect, and the kit adds its own start time" \
      "$prof"
  else
    finding OK "'zsh -ilc env' takes $ms ms (median)"
  fi
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
  while IFS= read -r line; do
    say "$line"
    case $line in
      "H0.6 claude.path missing")
        finding INFO "claude is not on PATH" \
          "S8 compares Claude Code before and after the setup; there is nothing to compare" \
          "nothing, unless Claude Code should be here"
        ;;
      "H0.6 claude.path "*) finding OK "claude is on PATH" ;;
      "H0.6 lsremote "*" ok") finding OK "git ls-remote on the given repository works" ;;
      "H0.6 lsremote "*" fail")
        finding HEADS-UP "git ls-remote on the given repository fails before the setup" \
          "git auth does not work even before setup, so S10 (git auth survives the setup, K12) cannot be compared" \
          "see the error with 'GIT_TERMINAL_PROMPT=0 git ls-remote <url>', fix access, or pass a repository you can read"
        ;;
      "H0.6 lsremote "*" skipped "*)
        finding INFO "git is not installed; git access is untested" \
          "S10 needs a git access baseline" \
          "the kit installs git; run compare with the URL after the setup"
        ;;
    esac
  done < <(h06_lines "${1:-}")
  if [ -z "${1:-}" ]; then
    finding INFO "no private repository URL given; git auth is untested" \
      "S10/K12: whether git authentication survives the setup can only be compared with a baseline" \
      "pass a private repo URL to verify that git auth survives the setup: workspace-probe.sh baseline <url>"
  fi
}

# Copies of the shell rc files for compare's diff; never in a report.
save_rc_copies() {
  local d="$probe_dir/rc-$report_ts"
  (
    umask 077
    mkdir -p -- "$d"
    for f in "${rc_files[@]}"; do
      if [ -f "$HOME/$f" ] && [ -r "$HOME/$f" ]; then cp -L -- "$HOME/$f" "$d/$f"; fi
    done
  )
  chmod 700 "$d"
  find "$d" -type f -exec chmod 600 {} +
  say "  rc files copied to $d for compare's diff (their content stays out of reports)"
}

# --- H0.7: the process name of nvim --------------------------------------
h07() {
  say ""
  say "== H0.7 (A6): does 'pgrep -u \$USER nvim' see Neovim?"
  if ! have nvim; then
    say "H0.7 nvim: missing"
    finding INFO "nvim is not installed; A6 is untested" \
      "the kit brings its own Neovim" \
      "nothing; after the setup, 'pgrep -u \$USER nvim' should list a running nvim"
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
      finding OK "'pgrep -u \$USER nvim' finds a running Neovim"
    else
      say "H0.7 pgrep -u <user> nvim: does NOT match the probe's nvim"
      finding HEADS-UP "'pgrep -u \$USER nvim' does not find a running Neovim (process name: $comm)" \
        "A6: nix-terminal-mode's signal (pkill -USR1 nvim) would not reach Neovim, so its theme would not switch" \
        "report the process name above; until then restart nvim after 'nix-terminal-mode light|dark'"
    fi
    children=$(pgrep -a -P "$pid" 2>/dev/null | cut -d' ' -f2- | tr '\n' ';' || true)
    say "H0.7 children: ${children:-none}"
    others=$(pgrep -u "$me" nvim | grep -vxc "$pid" || true)
    say "H0.7 other nvim processes of <user>: $others"
  else
    say "H0.7 pgrep: missing"
    finding INFO "pgrep is not installed; A6 is untested" \
      "nix-terminal-mode signals Neovim with pkill" \
      "nothing, if the image ships procps; otherwise the theme switch does not reach running nvims"
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
  save_rc_copies
  h07
  finish "ready for setup."
}

# --- compare: H0.6 now against a baseline report --------------------------
key_of() {
  local b c
  read -r _ b c _ <<<"$1"
  case $b in sha | lsremote) printf '%s %s\n' "$b" "$c" ;; *) printf '%s\n' "$b" ;; esac
}

# A changed shell rc file: its diff against baseline's copy, on screen only.
# Expected is exactly one added non-empty line naming the snippet's entry
# path, and nothing removed.
compare_rc() {
  local f=$1 dir=$2 old=$3 new="$HOME/$1" name=\~/"$1" src d body removed plus
  local why="S7: the setup appends one snippet line to ~/$f and changes nothing else in it"
  local tail_do="check with 'tail -n 3 ~/$f' that only the snippet line home-manager printed was added"
  if [ ! -e "$new" ]; then
    finding HEADS-UP "$name was removed since the baseline" "$why" \
      "restore it (baseline copy: $dir/$f, if present)"
    return 0
  fi
  if [ -f "$dir/$f" ]; then
    src=$dir/$f
  elif [ "$old" = absent ]; then
    src=/dev/null
  else
    finding HEADS-UP "$name changed since the baseline (no baseline copy to diff against)" "$why" "$tail_do"
    return 0
  fi
  if ! have diff; then
    finding HEADS-UP "$name changed since the baseline (diff is not installed to show how)" "$why" "$tail_do"
    return 0
  fi
  d=$(diff -u --label "baseline ~/$f" --label "now ~/$f" -- "$src" "$new" || true)
  printf '%s\n' "$d"
  say "  (the diff above is on screen only, not in the report)"
  body=$(printf '%s\n' "$d" | sed 1,2d)
  removed=$(printf '%s\n' "$body" | grep -c '^-' || true)
  plus=$(printf '%s\n' "$body" | grep '^+' | grep -v '^+[[:space:]]*$' || true)
  if [ "$removed" = 0 ] && [ "$(printf '%s' "$plus" | grep -c '')" = 1 ] && [[ $plus == *"$snippet_mark"* ]]; then
    finding OK "$name: only the snippet line was added — expected"
  else
    finding HEADS-UP "$name changed beyond the snippet line ($(printf '%s' "$plus" | grep -c '') lines added, $removed removed)" \
      "$why" "review the diff printed above and undo what you did not add (baseline copy: $dir/$f)"
  fi
}

# compare_changed KEY OLD NEW RCDIR: the verdict for one CHANGED line.
compare_changed() {
  local k=$1 old=$2 v=$3 dir=$4 rel f
  case $k in
    "sha ~/"*)
      rel=${k#"sha ~/"}
      for f in "${rc_files[@]}"; do
        if [ "$f" = "$rel" ]; then
          compare_rc "$rel" "$dir" "$old"
          return 0
        fi
      done
      finding HEADS-UP "${k#sha } changed since the baseline" \
        "K12: the kit's git configuration (credential.helper = cache) can change git authentication" \
        "run compare with the private repo URL to confirm that 'git ls-remote' still works (S10)"
      ;;
    claude.path | claude.version)
      finding HEADS-UP "$k changed: $old -> $v" \
        "S8/R6: the setup must not change which Claude Code runs (K6: the dev set's nodejs can shadow it)" \
        "check 'type -a claude node'; if one resolves into the Nix profile, set packages.dev.enable = false"
      ;;
    env.sha | env.names)
      finding HEADS-UP "the ANTHROPIC_/CLAUDE_/AWS_ variables changed ($k)" \
        "S8: Claude Code is configured by the variables the Coder agent injects; the kit must not change them" \
        "compare 'compgen -e | grep -E \"^(ANTHROPIC|CLAUDE|AWS)_\"' with the baseline's env.names; look for them in home.sessionVariables"
      ;;
    lsremote*)
      finding HEADS-UP "git ls-remote on the repository: $old -> $v" \
        "K12/A8: git authentication changed with the setup (the kit sets credential.helper = cache)" \
        "check 'git config --show-origin --get-all credential.helper' and 'GIT_TERMINAL_PROMPT=0 git ls-remote <url>'"
      ;;
    *)
      finding HEADS-UP "$k changed: $old -> $v" "the baseline differs" "check what changed it"
      ;;
  esac
}

cmd_compare() {
  local file=${1:-} url=${2:-} line k changed=0 base_ts rcdir had_ls=no
  [ -n "$file" ] || die 2 "compare needs a baseline report"
  [ -r "$file" ] || die 2 "cannot read $file"
  declare -A base=()
  while IFS= read -r line; do
    case $line in "H0.6 "*) base[$(key_of "$line")]=$line ;; esac
    case $line in "H0.6 lsremote "*) had_ls=yes ;; esac
  done <"$file"
  [ "${#base[@]}" -gt 0 ] || die 2 "no H0.6 lines in $file"
  base_ts=${file##*/}
  base_ts=${base_ts%.txt}
  base_ts=${base_ts##*-}
  rcdir="$(dirname -- "$file")/rc-$base_ts"
  open_report compare
  say "compared with: $file"
  local now
  mapfile -t now < <(h06_lines "$url" | scrub)
  for line in "${now[@]}"; do
    k=$(key_of "$line")
    if [ -z "${base[$k]+x}" ]; then
      say "new      $line"
      finding INFO "not in the baseline: ${line#H0.6 }" \
        "the baseline report comes from an older probe or run" "nothing"
    elif [ "${base[$k]}" = "$line" ]; then
      say "same     $line"
    else
      say "CHANGED  $k: ${base[$k]#"H0.6 $k "} -> ${line#"H0.6 $k "}"
      compare_changed "$k" "${base[$k]#"H0.6 $k "}" "${line#"H0.6 $k "}" "$rcdir"
      changed=1
    fi
    unset 'base[$k]'
  done
  for k in "${!base[@]}"; do
    say "not run  ${base[$k]}"
    case $k in
      lsremote*)
        finding INFO "git access was not re-checked" \
          "S10: the baseline checked git ls-remote on a repository" \
          "pass the same repository URL: workspace-probe.sh compare <report> <url>"
        ;;
      *) finding INFO "not re-checked: ${base[$k]#H0.6 }" "this run did not produce it" "nothing" ;;
    esac
  done
  if [ -z "$url" ] && [ "$had_ls" = no ]; then
    finding INFO "no private repository URL given; git auth is untested" \
      "S10/K12: whether git authentication survives the setup is only visible with a URL" \
      "pass a private repo URL to verify that git auth survives the setup (to baseline and compare)"
  fi
  say ""
  if [ "$changed" = 1 ]; then
    say "Differences found. After the setup, ~/.zshrc and ~/.bashrc are expected to differ"
    say "by the appended snippet line only; see the verdicts above."
  else
    say "No differences."
  fi
  finish "the setup left the baselines intact."
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

# paste_verdict WHO ANSWER: the verdict for one OSC 52 paste test.
paste_verdict() {
  if [ "$2" = yes ]; then
    finding OK "OSC 52 copy from $1 reaches the Windows clipboard"
  else
    finding HEADS-UP "OSC 52 copy from $1 did not reach the Windows clipboard (answer: $2)" \
      "R15/K9: OSC 52 is unsupported on this path, so copying from nvim or zsh won't reach Windows" \
      "use VS Code or Windows Terminal for this workspace, or re-run with a clear y/n if unsure"
  fi
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
    finding INFO "nvim is not installed; its OSC 52 copy is untested" \
      "the kit brings its own Neovim" "nothing; after the setup, H11.13 tests yanks by hand"
    return 0
  fi
  if ! nvim_minor; then
    say "H0.5 nvim: older than 0.10 ($(nvim --version 2>/dev/null | sed -n 1p)); skipped"
    finding INFO "nvim is older than 0.10; its OSC 52 copy is untested" \
      "the kit brings its own, newer Neovim" "nothing; after the setup, H11.13 tests yanks by hand"
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
    finding HEADS-UP "the nvim OSC 52 step failed (exit $rc)" \
      "R15: whether yanks in Neovim reach the Windows clipboard on this path is untested" \
      "in nvim: :lua require('vim.ui.clipboard.osc52').copy('+')({'nvim-osc52'}), then Ctrl+V in Notepad"
    return 0
  fi
  feats=$(head -n1 "$tmp/features")
  rm -rf -- "$tmp"
  say "H0.5 nvim termfeatures: $feats"
  local ans
  ans=$(ask "paste in Notepad (Ctrl+V): did you get $tok? [y/n] ")
  say "H0.5 nvim osc52 copy: $ans"
  paste_verdict nvim "$ans"
}

cmd_terminal() {
  if ! { exec 3<>/dev/tty; } 2>/dev/null; then
    die 2 "terminal needs a terminal (/dev/tty cannot be opened)"
  fi
  have stty || die 2 "terminal needs stty"
  open_report terminal
  say "TERM=${TERM:-unset} TERM_PROGRAM=${TERM_PROGRAM:-unset} COLORTERM=${COLORTERM:-unset} tmux: $([ -n "${TMUX:-}" ] && echo yes || echo no)"
  if [ -n "${TMUX:-}" ]; then
    say "  inside tmux: replies and OSC 52 depend on tmux, not the Windows terminal"
    finding INFO "the probe runs inside tmux" \
      "replies and OSC 52 depend on tmux, not on the Windows terminal" \
      "run it outside tmux for the terminal's own result"
  fi
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
    finding OK "the terminal answers OSC 11 (the theme follows its background)"
  else
    say "H0.3 OSC 11: no rgb reply"
    finding INFO "no OSC 11 reply on this path" \
      "K3: the theme stays light on this path" \
      "set it by hand: nix-terminal-mode light|dark"
  fi
  local da1
  da1=$(printf '%s' "$reply" | sed -nE 's/.*\^\[\[\?([0-9;]*)c.*/\1/p')
  if [ -z "$da1" ]; then
    say "H0.3 DA1: no reply"
    finding INFO "no DA1 reply" \
      "informational: DA1 only announces features" "nothing; the OSC 52 paste test decides"
  elif [[ ";$da1;" == *';52;'* ]]; then
    say "H0.3 DA1: $da1 (52 present: the terminal announces OSC 52)"
    finding OK "DA1 announces OSC 52"
  else
    say "H0.3 DA1: $da1 (52 absent)"
    finding INFO "DA1 does not announce OSC 52" \
      "informational: many terminals support OSC 52 without announcing it" "nothing; the OSC 52 paste test decides"
  fi
  say ""
  say "== H0.5 (Q2 recipe): OSC 52 writes reach the Windows clipboard"
  local tok
  tok="tk-$(rand)"
  printf '\033]52;c;%s\a' "$(printf '%s' "$tok" | base64)" >&3
  say "  sent: OSC 52 with '$tok' (printf from the shell)"
  local ans
  ans=$(ask "paste in Notepad (Ctrl+V): did you get $tok? [y/n] ")
  say "H0.5 shell osc52 copy: $ans"
  paste_verdict "the shell" "$ans"
  h05_nvim
  finish "ready for setup."
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
