# `scripts/workspace-probe.sh` (phase-0 probe, Appendix C H0.1–H0.7):
# shellcheck-clean, parses, and a smoke run of `baseline` and `compare` in
# a fake $HOME without nix, git, nvim, claude or network. The probe must
# still exit 0, report nix as missing, reach the end of both rc files, and
# leave them byte-identical (H0.2 restores them from a trap). A `.zshrc`
# that links into the store is refused and left alone.
{pkgs}: let
  script = ../scripts/workspace-probe.sh;
in
  pkgs.runCommand "workspace-probe" {
    nativeBuildInputs = [
      pkgs.shellcheck
      pkgs.bashInteractive
      pkgs.zsh
      pkgs.coreutils
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

    shellcheck -x ${script} || fail "shellcheck"
    bash -n ${script} || fail "bash -n"
    if command -v nix >/dev/null || command -v git >/dev/null || command -v nvim >/dev/null; then
      fail "the smoke run needs a PATH without nix, git and nvim"
    fi

    export HOME=$PWD/fakehome USER=tester
    mkdir -p "$HOME"
    printf 'alias ll="ls -l"\n# no newline at the end' > "$HOME/.zshrc"
    printf '[ -z "$PS1" ] && return\nexport TK_X=1\n' > "$HOME/.bashrc"
    printf 'export TK_ENV=1\n' > "$HOME/.profile"
    before=$(cd "$HOME" && sha256sum .zshrc .bashrc .profile)

    rc=0; bash ${script} baseline </dev/null >out 2>err || rc=$?
    after=$(cd "$HOME" && sha256sum .zshrc .bashrc .profile)
    [ "$before" = "$after" ] || { cat out err; fail "baseline changed the rc files"; }
    [ "$rc" = 0 ] || { cat out err; fail "baseline exited $rc"; }
    [ "$(cd "$HOME" && echo .[!.]*)" = ".bashrc .cache .profile .zshrc" ] ||
      fail "baseline left files in \$HOME: $(cd "$HOME" && echo .[!.]*)"

    grep -q '^H0.1 nix: missing' out || { cat out; fail "nix not reported missing"; }
    grep -q '^H0.2 ~/.zshrc: end reached' out || { cat out err; fail "zshrc end not reached"; }
    grep -q '^H0.2 ~/.bashrc: end reached' out || { cat out err; fail "bashrc end not reached"; }
    grep -q '^H0.2 ~/.zshrc: restored, sha256 identical' out || fail "zshrc restore not verified"
    grep -q '^H0.4 zsh -ilc env: median ' out || { cat out; fail "no H0.4 median"; }
    grep -q '^H0.6 sha ~/.gitconfig absent$' out || { cat out; fail "absent file not reported"; }
    grep -q '^H0.7 nvim: missing' out || { cat out; fail "nvim not reported missing"; }

    report=$(find "$HOME/.cache/terminal-kit-probe" -name 'baseline-*.txt')
    [ "$(printf '%s\n' "$report" | wc -l)" = 1 ] && [ -s "$report" ] || fail "no single saved report"
    ! grep -qF "$HOME" "$report" || fail "the report contains \$HOME"
    ! grep -qw tester "$report" || fail "the report contains \$USER"

    bash ${script} compare "$report" </dev/null >cmp 2>&1 || { cat cmp; fail "compare against itself failed"; }
    echo changed >> "$HOME/.zshrc"
    if bash ${script} compare "$report" </dev/null >cmp 2>&1; then cat cmp; fail "compare missed a change"; fi
    grep -q 'CHANGED.*~/.zshrc' cmp || { cat cmp; fail "compare did not name ~/.zshrc"; }

    # a .zshrc owned by the store is refused and left alone
    export HOME=$PWD/storehome
    mkdir -p "$HOME"
    ln -s ${pkgs.writeText "zshrc" "true\n"} "$HOME/.zshrc"
    rc=0; bash ${script} baseline </dev/null >out 2>err || rc=$?
    [ "$rc" = 0 ] || { cat out err; fail "baseline (store link) exited $rc"; }
    grep -q '^H0.2 ~/.zshrc: refused' out || { cat out; fail "store link not refused"; }
    [ "$(readlink "$HOME/.zshrc")" = ${pkgs.writeText "zshrc" "true\n"} ] || fail "store link touched"

    touch $out
  ''
