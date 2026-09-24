# S3, S4 (Snippet 6): interactive shells started through the entry files,
# in a fake $HOME built from the template configuration's Home Manager
# outputs (PD6).
#
# Home Manager's generated files embed eval-time absolute paths (HISTFILE,
# the zsh plugin directory, the entry files' targets). The fake $HOME
# must therefore be the configuration's home directory: `CtS` is Cₜ with
# `home.homeDirectory = "/build/home"` (a user.nix edit R17 allows), and
# the check refuses to run unless the sandbox build directory is /build
# (Nix's default `sandbox-build-dir`).
{
  pkgs,
  lib,
  templateHome,
}: let
  fakeHome = "/build/home";
  CtS =
    (templateHome.extendModules {
      modules = [{home.homeDirectory = lib.mkForce fakeHome;}];
    }).config;
  # S3: the literal list is the criterion.
  tools = ["starship" "fzf" "zoxide" "direnv" "nix-locate" "yazi" "bat" "btop" "lazygit" "git" "nvim"];
  # P17: derived.
  aliases = lib.attrNames CtS.programs.zsh.shellAliases;
  entryDir = ".config/terminal-kit";
  snippet = sh: ''if [ -r "$HOME/${entryDir}/init.${sh}" ]; then . "$HOME/${entryDir}/init.${sh}"; fi'';
in
  pkgs.runCommand "sourced-shell-smoke" {
    nativeBuildInputs = [pkgs.zsh pkgs.bashInteractive pkgs.coreutils pkgs.gnugrep pkgs.gawk];
  } ''
    set -euo pipefail
    if [ "$NIX_BUILD_TOP" != /build ]; then
      echo "sourced-shell-smoke: needs the sandbox build directory /build (got $NIX_BUILD_TOP)" >&2
      exit 1
    fi
    fail() { printf 'sourced-shell-smoke: %s\n' "$*" >&2; exit 1; }

    # A fake $HOME from the Home Manager outputs, plus the image's rc files
    # reduced to the one-time snippets.
    mkhome() {
      mkdir -p "$1"
      cp -rs --no-preserve=mode ${CtS.home-files}/. "$1"/
      ln -s ${CtS.home.path} "$1/.nix-profile"
      printf '%s\n' ${lib.escapeShellArg (snippet "zsh")} >"$1/.zshrc"
      printf '%s\n' ${lib.escapeShellArg (snippet "bash")} >"$1/.bashrc"
    }
    export HOME=${fakeHome} USER=${CtS.home.username}
    unset TERM ZDOTDIR
    mkhome "$HOME"
    cd "$HOME"

    zsh -n "$HOME/${entryDir}/init.zsh" || fail "zsh -n init.zsh"
    zsh -n "$HOME/${entryDir}/zsh/.zshrc" || fail "zsh -n <dotDir>/.zshrc"
    bash -n "$HOME/${entryDir}/init.bash" || fail "bash -n init.bash"
    bash -n "$HOME/${entryDir}/bash/bashrc" || fail "bash -n bashrc"

    # case silent (S4, P13)
    rc=0; zsh -ilc true >"$TMPDIR/out" 2>"$TMPDIR/err" || rc=$?
    if [ "$rc" -ne 0 ] || [ -s "$TMPDIR/out" ] || [ -s "$TMPDIR/err" ]; then
      echo "silent: zsh -ilc true: exit $rc; stdout, stderr:" >&2
      cat -v "$TMPDIR/out" "$TMPDIR/err" >&2
      exit 1
    fi

    # case resolve (S3, P17)
    for t in ${lib.escapeShellArgs tools}; do
      zsh -ic "type $t" >/dev/null 2>&1 || fail "resolve: $t"
    done
    for a in ${lib.escapeShellArgs aliases}; do
      zsh -ic "alias -- $a" >/dev/null 2>&1 || fail "resolve alias: $a"
    done
    [ -z "$(zsh -ic 'print -r -- ''${ZDOTDIR-}' 2>/dev/null)" ] || fail "resolve: ZDOTDIR is set"

    # case history (S5 proxy, P11): the history file's directory is
    # created under $HOME; the shell reports that path as HISTFILE.
    histfile=$(zsh -ic 'print hi >/dev/null; print -r -- $HISTFILE' 2>/dev/null)
    [ "$histfile" = ${lib.escapeShellArg CtS.programs.zsh.history.path} ] || fail "history: HISTFILE = $histfile"
    case $histfile in "$HOME"/*) ;; *) fail "history: $histfile is not under $HOME" ;; esac
    [ -d "$(dirname "$histfile")" ] || fail "history: $(dirname "$histfile") does not exist"

    # case nested (S6, P12, P13), zsh and bash: a child interactive shell
    # started from a parent one repeats no PATH entry more often than the
    # parent has it, and writes nothing to stderr. The loaded guard is not
    # exported, so the child runs its rc files again (`rerun`: a kit alias
    # in zsh, a Home Manager bash shopt in bash; neither is inherited).
    for sh in zsh bash; do
      case $sh in
        zsh) rerun='alias g' ;;
        bash) rerun='shopt -q globstar' ;;
      esac
      if $sh -ic 'env' 2>/dev/null | grep -q '^__tk_'; then fail "nested $sh: a loaded guard is exported"; fi
      parent=$($sh -ic 'printf %s "$PATH"' 2>/dev/null)
      $sh -ic "$sh -i -c '$rerun >/dev/null || printf NOT-RERUN; printf %s \"\$PATH\"' >$TMPDIR/child 2>$TMPDIR/childerr" 2>/dev/null
      if grep -q NOT-RERUN "$TMPDIR/child"; then fail "nested $sh: the child did not run the entry file ($rerun)"; fi
      # Without a controlling terminal, `bash -i` itself (also with
      # --norc) prints its two job-control lines; they are not the kit's.
      grep -v -e '^bash: cannot set terminal process group (' -e '^bash: no job control in this shell$' \
        "$TMPDIR/childerr" >"$TMPDIR/childerr.kit" || true
      if [ -s "$TMPDIR/childerr.kit" ]; then
        echo "nested $sh: child stderr:" >&2; cat -v "$TMPDIR/childerr.kit" >&2; exit 1
      fi
      tr : '\n' <"$TMPDIR/child" | sort | uniq -c >"$TMPDIR/cc"
      printf %s "$parent" | tr : '\n' | sort | uniq -c >"$TMPDIR/pc"
      while read -r n e; do
        p=$(awk -v e="$e" '$2 == e { print $1 }' "$TMPDIR/pc")
        [ "$n" -le "''${p:-0}" ] || fail "nested $sh: PATH entry $e appears $n times in the child, ''${p:-0} in the parent"
      done <"$TMPDIR/cc"
    done

    touch $out
  ''
