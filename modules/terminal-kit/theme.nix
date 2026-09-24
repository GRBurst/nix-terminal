# The enfocado theme and its mode sources.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.terminalKit;

  # R9: the manual override of the `terminal` mode source. The state file
  # path and format are the ones my-style-switch writes (D9): one word and
  # a newline. The temp file and `mv` make the write atomic; the bytes are
  # the same.
  modeCommand = pkgs.writeShellApplication {
    name = "nix-terminal-mode";
    runtimeInputs = [pkgs.coreutils pkgs.procps];
    text = ''
      state="''${XDG_STATE_HOME:-$HOME/.local/state}/my-theme/mode"
      usage() {
        echo "usage: nix-terminal-mode light|dark|auto" >&2
        exit 64
      }
      [ "$#" -eq 1 ] || usage
      case "$1" in
        light | dark)
          mkdir -p "''${state%/*}"
          tmp=$(mktemp "$state.XXXXXX")
          printf '%s\n' "$1" >"$tmp"
          mv -f "$tmp" "$state"
          ;;
        auto) rm -f "$state" ;;
        *) usage ;;
      esac
      # Only the invoking user's Neovim processes (R9). Never `pkill -x`:
      # the process is named `.nvim-wrapped`, and an unanchored pattern is
      # what matches it.
      pkill -USR1 -u "$(id -u)" nvim || true
    '';
  };
in {
  config = lib.mkIf (cfg.enable && cfg.theme.enable) {
    home.packages = lib.optional (cfg.theme.modeSource == "terminal") modeCommand;
  };
}
