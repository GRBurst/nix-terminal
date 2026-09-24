# S22–S25, R9, P14: `nix-terminal-mode` against a scratch state directory.
# The command is taken from the template configuration's packages, so the
# check also proves it is installed there.
#
#   auto        state `dark`, `auto`        → exit 0, no state file
#   repeat      `dark` twice                → exit 0 both times, same sha, `dark\n`
#   auto-empty  no state, `auto`            → exit 0, no state file
#   refuse      `foo`, no argument, two     → exit 64, stderr starts with
#               arguments; with and without    `usage:`, state sha unchanged
#               a state file                   (or still absent)
#   fallback    XDG_STATE_HOME unset        → $HOME/.local/state/my-theme/mode
{
  pkgs,
  lib,
  Ct,
}: let
  cmd = lib.findFirst (p: lib.getName p == "nix-terminal-mode") null Ct.home.packages;
in
  if cmd == null
  then
    pkgs.runCommand "mode-command" {} ''
      echo "mode-command: nix-terminal-mode is not in the template configuration's home.packages" >&2
      exit 1
    ''
  else
    pkgs.runCommand "mode-command" {nativeBuildInputs = [pkgs.coreutils];} ''
      # No `-e`: every case runs, and `fail` decides the exit status.
      set -uo pipefail
      fail=0
      mode=${cmd}/bin/nix-terminal-mode
      bad() { echo "mode-command $1: $2" >&2; fail=1; }

      fresh() { # $1: case name; sets XDG_STATE_HOME and $state
        export HOME=$TMPDIR/$1/home
        export XDG_STATE_HOME=$TMPDIR/$1/state
        state=$XDG_STATE_HOME/my-theme/mode
        mkdir -p "$HOME"
      }
      seed() { mkdir -p "''${state%/*}"; printf '%s\n' "$1" >"$state"; }
      run() { # $1: case name; rest: arguments. Sets $rc, $err.
        local c=$1; shift
        rc=0
        "$mode" "$@" >"$TMPDIR/$c.out" 2>"$TMPDIR/$c.err" || rc=$?
        err=$(cat "$TMPDIR/$c.err")
      }

      # auto (S22)
      fresh auto; seed dark
      run auto auto
      [ "$rc" -eq 0 ] || bad auto "exit $rc, expected 0 (stderr: $err)"
      [ ! -e "$state" ] || bad auto "state file still exists"

      # repeat (S23, P14)
      fresh repeat
      run repeat dark
      [ "$rc" -eq 0 ] || bad repeat "first run: exit $rc, expected 0 (stderr: $err)"
      h1=$(sha256sum "$state" 2>/dev/null | cut -d' ' -f1)
      run repeat dark
      [ "$rc" -eq 0 ] || bad repeat "second run: exit $rc, expected 0 (stderr: $err)"
      h2=$(sha256sum "$state" 2>/dev/null | cut -d' ' -f1)
      [ -n "$h1" ] && [ "$h1" = "$h2" ] || bad repeat "sha changed or missing: '$h1' -> '$h2'"
      [ "$(od -An -c "$state" 2>/dev/null | tr -s ' ')" = " d a r k \n" ] \
        || bad repeat "content is not 'dark\\n' (the my-style-switch format)"
      extra=$(find "''${state%/*}" -mindepth 1 ! -name mode 2>/dev/null)
      [ -z "$extra" ] || bad repeat "stray files next to the state file: $extra"

      # auto-empty (S24)
      fresh auto-empty
      run auto-empty auto
      [ "$rc" -eq 0 ] || bad auto-empty "exit $rc, expected 0 (stderr: $err)"
      [ ! -e "$state" ] || bad auto-empty "a state file exists"

      # refuse (S25): each argument vector, with and without a state file
      refuse() { # $1: label; rest: arguments
        local label=$1; shift
        fresh "refuse-$label-present"; seed light
        before=$(sha256sum "$state" | cut -d' ' -f1)
        run "refuse-$label-present" "$@"
        [ "$rc" -eq 64 ] || bad refuse "$label (state present): exit $rc, expected 64"
        case "$err" in usage:*) ;; *) bad refuse "$label: stderr does not start with 'usage:': $err" ;; esac
        after=$(sha256sum "$state" 2>/dev/null | cut -d' ' -f1)
        [ "$before" = "$after" ] || bad refuse "$label: state sha changed: $before -> $after"
        fresh "refuse-$label-absent"
        run "refuse-$label-absent" "$@"
        [ "$rc" -eq 64 ] || bad refuse "$label (no state): exit $rc, expected 64"
        [ ! -e "$state" ] || bad refuse "$label: a state file was created"
      }
      refuse foo foo
      refuse none
      refuse two dark light

      # fallback: without XDG_STATE_HOME the state lives under $HOME
      fresh fallback; unset XDG_STATE_HOME
      run fallback light
      [ "$rc" -eq 0 ] || bad fallback "exit $rc, expected 0 (stderr: $err)"
      [ "$(cat "$HOME/.local/state/my-theme/mode" 2>/dev/null)" = light ] \
        || bad fallback "no 'light' in \$HOME/.local/state/my-theme/mode"

      [ "$fail" -eq 0 ] || exit 1
      touch $out
    ''
