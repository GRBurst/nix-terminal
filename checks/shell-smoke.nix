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
    nativeBuildInputs = [pkgs.zsh pkgs.bashInteractive pkgs.coreutils pkgs.gnugrep];
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

    touch $out
  ''
