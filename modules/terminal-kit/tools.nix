# bat, btop, lazygit, fzf, starship, zoxide, direnv, nix-index; each behind cfg.tools.<name>.enable.
{
  config,
  lib,
  ...
}: let
  cfg = config.programs.terminalKit;
in {
  config = lib.mkIf (cfg.enable) {};
}
