# S13, S14, R7, PD13: `terminal-kit-check-snippet` against a fake $HOME.
# The command is taken from the template configuration's packages, and
# its activation entry from the template's home.activation (absent in the
# owned configuration).
#
#   zsh      .zshrc lacks the snippet, .bashrc has it   → names .zshrc only
#   bash     .bashrc lacks it, .zshrc has it            → names .bashrc only
#   present  both have it (one in another spelling:     → prints nothing
#            the entry path is what counts, PD13)
#   absent   neither rc file exists                     → names both
#
# Every case: exit 0, stdout exactly the expected text, both rc files
# byte-identical afterwards (or still absent).
{
  pkgs,
  lib,
  Ct,
  Co,
}: let
  name = "terminal-kit-check-snippet";
  cmd = lib.findFirst (p: lib.getName p == name) null Ct.home.packages;
  entry = sh: ".config/terminal-kit/init.${sh}";
  # PD13, as the README gives it: the criterion.
  snippet = sh: ''if [ -r "$HOME/${entry sh}" ]; then . "$HOME/${entry sh}"; fi'';
  act = Ct.home.activation.terminalKitSnippet or null;
  noCtx = builtins.unsafeDiscardStringContext;
  problems =
    lib.optional (cmd == null) "${name} is not in the template configuration's home.packages"
    ++ lib.optional (act == null) "Ct has no home.activation.terminalKitSnippet"
    ++ lib.optional (act != null && cmd != null && !(lib.hasInfix (noCtx "${cmd}/bin/${name}") (noCtx act.data))) "Ct's activation entry does not run ${name}"
    ++ lib.optional (act != null && !(lib.elem "writeBoundary" act.after)) "Ct's activation entry is not after writeBoundary"
    ++ lib.optional (Co.home.activation ? terminalKitSnippet) "Co (owned) has the activation entry";
in
  if problems != []
  then
    pkgs.runCommand "snippet-check" {} ''
      printf 'snippet-check: %s\n' ${lib.escapeShellArgs problems} >&2
      exit 1
    ''
  else
    pkgs.runCommand "snippet-check" {nativeBuildInputs = [pkgs.coreutils];} ''
      set -uo pipefail
      fail=0
      bad() { echo "snippet-check $1: $2" >&2; fail=1; }
      block() { # $1: rc file, $2: shell — the text printed for a missing snippet
        printf 'terminal-kit: append this line to %s:\n' "$1"
        case $2 in
          zsh) printf '  %s\n' ${lib.escapeShellArg (snippet "zsh")} ;;
          bash) printf '  %s\n' ${lib.escapeShellArg (snippet "bash")} ;;
        esac
      }
      sums() { for f in "$HOME/.zshrc" "$HOME/.bashrc"; do if [ -e "$f" ]; then sha256sum "$f"; else echo "absent $f"; fi; done; }
      run() { # $1: case name; $HOME prepared; $TMPDIR/$1.want holds the expected stdout
        before=$(sums)
        rc=0; ${cmd}/bin/${name} >"$TMPDIR/$1.out" 2>"$TMPDIR/$1.err" || rc=$?
        [ "$rc" -eq 0 ] || bad "$1" "exit $rc, expected 0"
        [ ! -s "$TMPDIR/$1.err" ] || bad "$1" "stderr: $(cat "$TMPDIR/$1.err")"
        cmp -s "$TMPDIR/$1.out" "$TMPDIR/$1.want" || bad "$1" "stdout differs:
      $(diff "$TMPDIR/$1.want" "$TMPDIR/$1.out")"
        [ "$(sums)" = "$before" ] || bad "$1" "rc files changed:
      $before
      $(sums)"
      }
      fresh() { export HOME=$TMPDIR/$1/home; mkdir -p "$HOME"; }

      fresh zsh
      printf '# image zshrc\n' >"$HOME/.zshrc"
      printf '# image bashrc\n%s\n' ${lib.escapeShellArg (snippet "bash")} >"$HOME/.bashrc"
      block "$HOME/.zshrc" zsh >"$TMPDIR/zsh.want"
      run zsh

      fresh bash
      printf '%s\n# image zshrc\n' ${lib.escapeShellArg (snippet "zsh")} >"$HOME/.zshrc"
      printf '# image bashrc\n' >"$HOME/.bashrc"
      block "$HOME/.bashrc" bash >"$TMPDIR/bash.want"
      run bash

      fresh present
      printf '%s\n' ${lib.escapeShellArg (snippet "zsh")} >"$HOME/.zshrc"
      printf 'source ~/%s\n' ${lib.escapeShellArg (entry "bash")} >"$HOME/.bashrc"
      : >"$TMPDIR/present.want"
      run present

      fresh absent
      { block "$HOME/.zshrc" zsh; block "$HOME/.bashrc" bash; } >"$TMPDIR/absent.want"
      run absent

      [ "$fail" -eq 0 ] || exit 1
      touch $out
    ''
