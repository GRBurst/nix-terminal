# `scripts/workspace-probe.sh` (phase-0 probe, Appendix C H0.1–H0.7):
# shellcheck-clean, parses, and runs of `baseline`, `compare` and
# `terminal` in fake homes without git, nvim, claude or network. `nix` is
# either missing or a stub (`stubNix`) that answers like a working
# single-user install; STUB_NIX_BUILD=build makes it report local builds.
#
# Every finding has a level (OK, INFO, HEADS-UP, BLOCKER). The run ends
# with a "== Summary" block, which is also the top of the saved report
# (right after its two "#" header lines):
#   all OK/INFO    "All checks passed — ready for setup." and INFO notes
#   otherwise      "<n> heads-up(s), <m> blocker(s):" and a numbered list,
#                  each item with a "why:" and a "do:" line
# Exit 1 only with a BLOCKER; 0 otherwise.
#
# Cases: no nix (BLOCKER), all OK, two forced HEADS-UPs (slow ~/.zshrc,
# local builds), an early `return` in ~/.zshrc (BLOCKER), compare against
# itself, after the snippet line (expected) and after another line
# (HEADS-UP with the diff on screen, not in the report), an rc file that
# reads the terminal or ignores SIGTERM under a pty (no hang), a store
# link (refused, INFO), and `terminal` under a pty answered "n" (OSC 52
# HEADS-UP, OSC 11 INFO). H0.2 must always leave the rc files identical.
{pkgs}: let
  script = ../scripts/workspace-probe.sh;
  stubNix = pkgs.writeShellScriptBin "nix" ''
    case " $* " in
      *" --version "*) echo "nix (Nix) 2.24.9" ;;
      *" config show experimental-features "*) echo "flakes nix-command" ;;
      *" config show substituters "*) echo "https://cache.nixos.org/" ;;
      *" eval "*) printf /nix/store ;;
      *" build "*)
        if [ "''${STUB_NIX_BUILD:-fetch}" = build ]; then
          printf 'these 2 derivations will be built:\n  /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-hello-2.12.2.drv\n  /nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-bash-5.2.drv\n' >&2
        else
          printf 'these 1 paths will be fetched (0.1 MiB download):\n  /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-hello-2.12.2\n' >&2
        fi
        ;;
      *" path-info "*) exit 0 ;;
      *) exit 1 ;;
    esac
  '';
  storeZshrc = pkgs.writeText "zshrc" "true\n";
in
  pkgs.runCommand "workspace-probe" {
    nativeBuildInputs = [
      pkgs.shellcheck
      pkgs.bashInteractive
      pkgs.zsh
      pkgs.coreutils
      pkgs.diffutils
      pkgs.findutils
      pkgs.procps
      pkgs.util-linux
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
    ];
  } ''
    set -euo pipefail
    fail() { printf 'workspace-probe: %s\n' "$*" >&2; exit 1; }
    show() { cat "$@" >&2 || true; }
    # keep NAME FILE: sample outputs, the check's result (for review)
    mkdir -p $out
    keep() { cp -- "$2" "$out/$1"; }

    shellcheck -x ${script} || fail "shellcheck"
    bash -n ${script} || fail "bash -n"
    if command -v nix >/dev/null || command -v git >/dev/null || command -v nvim >/dev/null; then
      fail "the smoke run needs a PATH without nix, git and nvim"
    fi
    export USER=tester
    nopath=$PATH
    withnix=${stubNix}/bin:$PATH

    # summary FILE: the "== Summary" block of an output (up to "Report saved")
    summary() { sed -n '/^== Summary$/,/^Report saved/p' "$1"; }
    # top REPORT: the saved report's summary, i.e. line 3 up to the first
    # empty line; it must start with "== Summary" and come before H0.x.
    top() {
      [ "$(sed -n 3p "$1")" = "== Summary" ] || { show "$1"; fail "$1: no summary at the top (line 3)"; }
      sed -n '3,/^$/p' "$1"
    }
    one_report() { # DIR PREFIX
      local r
      r=$(find "$1" -name "$2-*.txt")
      [ -n "$r" ] && [ "$(printf '%s\n' "$r" | wc -l)" = 1 ] && [ -s "$r" ] || fail "no single saved $2 report in $1"
      printf '%s\n' "$r"
    }
    newhome() {
      export HOME=$PWD/$1
      mkdir -p "$HOME"
      rm -rf "$HOME/.cache"
    }

    # --- no nix: BLOCKER, exit 1; H0.2 restores the files ------------------
    newhome fakehome
    export PATH=$nopath
    printf 'alias ll="ls -l"\n# no newline at the end' > "$HOME/.zshrc"
    printf '[ -z "$PS1" ] && return\nexport TK_X=1\n' > "$HOME/.bashrc"
    printf 'export TK_ENV=1\n' > "$HOME/.profile"
    before=$(cd "$HOME" && sha256sum .zshrc .bashrc .profile)

    rc=0; bash ${script} baseline </dev/null >out 2>err || rc=$?
    after=$(cd "$HOME" && sha256sum .zshrc .bashrc .profile)
    [ "$before" = "$after" ] || { show out err; fail "baseline changed the rc files"; }
    [ "$rc" = 1 ] || { show out err; fail "baseline without nix exited $rc, expected 1 (BLOCKER)"; }
    [ "$(cd "$HOME" && echo .[!.]*)" = ".bashrc .cache .profile .zshrc" ] ||
      fail "baseline left files in \$HOME: $(cd "$HOME" && echo .[!.]*)"

    grep -q '^H0.1 nix: missing' out || { show out; fail "nix not reported missing"; }
    grep -q '^H0.2 ~/.zshrc: end reached' out || { show out err; fail "zshrc end not reached"; }
    grep -q '^H0.2 ~/.bashrc: end reached' out || { show out err; fail "bashrc end not reached"; }
    grep -q '^H0.2 ~/.zshrc: restored, sha256 identical' out || fail "zshrc restore not verified"
    grep -q '^H0.4 zsh -ilc env: median ' out || { show out; fail "no H0.4 median"; }
    grep -q '^H0.6 sha ~/.gitconfig absent$' out || { show out; fail "absent file not reported"; }
    grep -q '^H0.7 nvim: missing' out || { show out; fail "nvim not reported missing"; }
    grep -q -- '-> BLOCKER: ' out || { show out; fail "no inline BLOCKER verdict"; }
    grep -q -- '-> OK: ' out || { show out; fail "no inline OK verdict"; }
    summary out > sum
    grep -qx '0 heads-up(s), 1 blocker(s):' sum || { show sum; fail "no-nix summary count"; }
    grep -qE '^ +1\. BLOCKER: .*nix' sum || { show sum; fail "no-nix: item 1 is not the nix BLOCKER"; }
    keep baseline-no-nix.txt out
    grep -q 'single-user' sum || { show sum; fail "no-nix: no install advice"; }

    report=$(one_report "$HOME/.cache/terminal-kit-probe" baseline)
    ! grep -qF "$HOME" "$report" || fail "the report contains \$HOME"
    ! grep -qw tester "$report" || fail "the report contains \$USER"
    top "$report" > top
    grep -qx '0 heads-up(s), 1 blocker(s):' top || { show top; fail "no-nix: summary count not at the top of the report"; }
    [ "$(grep -c '^== Summary$' "$report")" = 1 ] || fail "the summary is in the report more than once"

    # --- all OK: exit 0, "All checks passed", INFO notes -------------------
    newhome okhome
    export PATH=$withnix
    printf 'alias ll="ls -l"\n' > "$HOME/.zshrc"
    printf '[ -z "$PS1" ] && return\nexport TK_X=1\n' > "$HOME/.bashrc"
    rc=0; bash ${script} baseline </dev/null >out 2>err || rc=$?
    [ "$rc" = 0 ] || { show out err; fail "all-OK baseline exited $rc"; }
    grep -q '^H0.1 hello: substituted' out || { show out; fail "stub nix: hello not substituted"; }
    summary out > sum
    grep -qx 'All checks passed — ready for setup.' sum || { show sum; fail "all-OK: no 'All checks passed'"; }
    grep -qx 'Notes:' sum || { show sum; fail "all-OK: INFO lines not listed as notes"; }
    grep -q 'claude' sum || { show sum; fail "all-OK: claude missing not in the notes"; }
    ! grep -q 'HEADS-UP\|BLOCKER' sum || { show sum; fail "all-OK summary names a HEADS-UP or BLOCKER"; }
    keep baseline-all-ok.txt out
    okreport=$(one_report "$HOME/.cache/terminal-kit-probe" baseline)
    top "$okreport" > top
    grep -qx 'All checks passed — ready for setup.' top || { show top; fail "all-OK: not at the top of the report"; }

    # rc copies for compare: mode 700 / 600, never named in the report
    rcdir=$(find "$HOME/.cache/terminal-kit-probe" -maxdepth 1 -type d -name 'rc-*')
    [ -n "$rcdir" ] && [ -f "$rcdir/.zshrc" ] && [ -f "$rcdir/.bashrc" ] || fail "baseline kept no rc copies"
    [ "$(stat -c %a "$rcdir")" = 700 ] || fail "rc copy dir mode $(stat -c %a "$rcdir")"
    [ "$(stat -c %a "$rcdir/.zshrc")" = 600 ] || fail "rc copy mode $(stat -c %a "$rcdir/.zshrc")"
    ! grep -qF 'ls -l' "$okreport" || fail "the report contains rc file content"

    # --- compare ----------------------------------------------------------
    rc=0; bash ${script} compare "$okreport" </dev/null >cmp 2>&1 || rc=$?
    [ "$rc" = 0 ] || { show cmp; fail "compare against itself exited $rc"; }
    summary cmp | grep -q '^All checks passed' || { show cmp; fail "compare against itself: not all passed"; }

    # the snippet line alone: expected
    # shellcheck disable=SC2016
    printf '%s\n' 'if [ -r "$HOME/.config/terminal-kit/init.zsh" ]; then . "$HOME/.config/terminal-kit/init.zsh"; fi' >> "$HOME/.zshrc"
    rc=0; bash ${script} compare "$okreport" </dev/null >cmp 2>&1 || rc=$?
    [ "$rc" = 0 ] || { show cmp; fail "compare after the snippet exited $rc"; }
    grep -q '~/.zshrc: only the snippet line was added — expected' cmp || { show cmp; fail "snippet line not recognised as expected"; }
    keep compare-snippet.txt cmp
    summary cmp | grep -q '^All checks passed' || { show cmp; fail "compare after the snippet: not all passed"; }

    # anything else: HEADS-UP, the diff on screen, not in the report
    echo 'echo changed' >> "$HOME/.zshrc"
    rc=0; bash ${script} compare "$okreport" </dev/null >cmp 2>&1 || rc=$?
    [ "$rc" = 0 ] || { show cmp; fail "compare with a change exited $rc, expected 0 (HEADS-UP)"; }
    grep -q 'CHANGED.*~/.zshrc' cmp || { show cmp; fail "compare did not name ~/.zshrc"; }
    grep -qx '+echo changed' cmp || { show cmp; fail "compare did not print the diff"; }
    summary cmp > sum
    grep -qx '1 heads-up(s), 0 blocker(s):' sum || { show sum; fail "compare change: summary count"; }
    grep -qE '^ +1\. HEADS-UP: .*~/.zshrc' sum || { show sum; fail "compare change: item 1"; }
    keep compare-changed.txt cmp
    cmpreport=$(find "$HOME/.cache/terminal-kit-probe" -name 'compare-*.txt' -newer "$okreport" | sort | tail -n1)
    ! grep -q 'echo changed' "$cmpreport" || fail "the compare report contains the diff"
    top "$cmpreport" | grep -qx '1 heads-up(s), 0 blocker(s):' || fail "compare: summary not at the top"

    # --- forced HEADS-UPs: slow ~/.zshrc (K2), local builds (A1) -----------
    newhome slowhome
    printf 'sleep 1.2\n' > "$HOME/.zshrc"
    rc=0; STUB_NIX_BUILD=build bash ${script} baseline </dev/null >out 2>err || rc=$?
    [ "$rc" = 0 ] || { show out err; fail "heads-up baseline exited $rc, expected 0"; }
    summary out > sum
    grep -qx '2 heads-up(s), 0 blocker(s):' sum || { show sum; fail "heads-up: summary count"; }
    grep -qE '^ +1\. HEADS-UP: ' sum && grep -qE '^ +2\. HEADS-UP: ' sum || { show sum; fail "heads-up: numbered list"; }
    [ "$(grep -cE '^ +why: ' sum)" = 2 ] && [ "$(grep -cE '^ +do: ' sum)" = 2 ] || { show sum; fail "heads-up: each item needs why: and do:"; }
    grep -q 'K2' sum || { show sum; fail "heads-up: slow shell (K2) missing"; }
    keep baseline-heads-up.txt out
    grep -q 'A1' sum || { show sum; fail "heads-up: local builds (A1) missing"; }
    top "$(one_report "$HOME/.cache/terminal-kit-probe" baseline)" | grep -qx '2 heads-up(s), 0 blocker(s):' ||
      fail "heads-up: summary not at the top of the report"

    # --- BLOCKER: ~/.zshrc returns early (K1) -----------------------------
    newhome earlyhome
    printf 'return 0\n' > "$HOME/.zshrc"
    before=$(sha256sum "$HOME/.zshrc")
    rc=0; bash ${script} baseline </dev/null >out 2>err || rc=$?
    [ "$rc" = 1 ] || { show out err; fail "early-return baseline exited $rc, expected 1"; }
    [ "$before" = "$(sha256sum "$HOME/.zshrc")" ] || fail "early return: ~/.zshrc changed"
    summary out > sum
    grep -qx '0 heads-up(s), 1 blocker(s):' sum || { show sum; fail "early return: summary count"; }
    grep -qE '^ +1\. BLOCKER: ~/.zshrc' sum || { show sum; fail "early return: item 1"; }
    keep baseline-blocker.txt out
    grep -q 'K1' sum && grep -qF '~/.zshenv' sum && grep -qF '[[ -o interactive ]]' sum ||
      { show sum; fail "early return: no K1 fallback advice"; }

    # --- under a pty: no hang (user report, H0.2 hung) ---------------------
    # A controlling terminal as on a workspace. An rc file that touches the
    # terminal must not stop the probe (background process group + SIGTTIN),
    # and one that ignores SIGTERM (as an interactive shell does) must still
    # be ended. TK_PROBE_TIMEOUT shortens the per-shell timeout for the test;
    # the outer `timeout -s KILL` turns a hang into a failure.
    newhome ttyhome
    printf 'true\n' > "$HOME/.zshrc"
    printf 'read -r -t 300 _ </dev/tty 2>/dev/null || true\n' > "$HOME/.bashrc"
    before=$(cd "$HOME" && sha256sum .zshrc .bashrc)
    rc=0
    TK_PROBE_TIMEOUT=3 timeout -s KILL 120 \
      script -qec "bash ${script} baseline" /dev/null </dev/null >ttyout 2>&1 || rc=$?
    [ "$rc" = 0 ] || { show ttyout; fail "baseline under a pty exited $rc (137 = hung, killed)"; }
    grep -q 'H0.2 ~/.bashrc: end reached' ttyout || { show ttyout; fail "pty: bashrc end not reached"; }
    [ "$before" = "$(cd "$HOME" && sha256sum .zshrc .bashrc)" ] || fail "pty: rc files changed"

    newhome ttyhome2
    printf 'true\n' > "$HOME/.zshrc"
    printf 'trap "" TERM; sleep 300\n' > "$HOME/.bashrc"
    before=$(cd "$HOME" && sha256sum .zshrc .bashrc)
    rc=0
    TK_PROBE_TIMEOUT=3 timeout -s KILL 120 \
      script -qec "bash ${script} baseline" /dev/null </dev/null >ttyout 2>&1 || rc=$?
    [ "$rc" = 0 ] || { show ttyout; fail "baseline with a TERM-ignoring rc exited $rc (137 = hung, killed)"; }
    grep -q 'H0.2 ~/.bashrc: end NOT reached .*timed out' ttyout || { show ttyout; fail "TERM-ignoring rc: no timeout reported"; }
    [ "$before" = "$(cd "$HOME" && sha256sum .zshrc .bashrc)" ] || fail "TERM-ignoring rc: rc files changed"
    top "$(one_report "$HOME/.cache/terminal-kit-probe" baseline)" > top
    grep -qx '1 heads-up(s), 0 blocker(s):' top || { show top; fail "TERM-ignoring bashrc: not one HEADS-UP"; }
    grep -qE '^ +1\. HEADS-UP: ~/.bashrc' top || { show top; fail "TERM-ignoring bashrc: item 1"; }

    # --- a .zshrc owned by the store is refused, left alone, INFO ---------
    newhome storehome
    ln -s ${storeZshrc} "$HOME/.zshrc"
    rc=0; bash ${script} baseline </dev/null >out 2>err || rc=$?
    [ "$rc" = 0 ] || { show out err; fail "baseline (store link) exited $rc"; }
    grep -q '^H0.2 ~/.zshrc: refused' out || { show out; fail "store link not refused"; }
    [ "$(readlink "$HOME/.zshrc")" = ${storeZshrc} ] || fail "store link touched"
    summary out > sum
    grep -qx 'All checks passed — ready for setup.' sum || { show sum; fail "store link: not all passed"; }
    grep -q 'owned' sum || { show sum; fail "store link: no shellIntegration note"; }

    # --- terminal under a pty, the paste answered "n" ----------------------
    # No terminal emulator answers OSC 11 or DA1 here; the answer arrives
    # after the 1 s reply window.
    newhome termhome
    rc=0
    { sleep 4; printf 'n\n'; sleep 3; } |
      timeout -s KILL 60 script -qec "bash ${script} terminal --label pty" /dev/null >termout 2>&1 || rc=$?
    [ "$rc" = 0 ] || { show termout; fail "terminal under a pty exited $rc"; }
    treport=$(one_report "$HOME/.cache/terminal-kit-probe" terminal-pty)
    grep -q '^H0.3 OSC 11: no rgb reply' "$treport" || { show "$treport"; fail "terminal: OSC 11 not reported"; }
    grep -q '^H0.5 shell osc52 copy: no' "$treport" || { show "$treport"; fail "terminal: the answer n was not read"; }
    top "$treport" > top
    keep terminal-report.txt "$treport"
    grep -qx '1 heads-up(s), 0 blocker(s):' top || { show top; fail "terminal: summary count"; }
    grep -qE '^ +1\. HEADS-UP: .*OSC 52' top || { show top; fail "terminal: item 1 is not OSC 52"; }
    grep -q 'K3' top && grep -q 'nix-terminal-mode' top || { show top; fail "terminal: no K3 note"; }

  ''
