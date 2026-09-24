# Neovim through nvf.
{
  config,
  lib,
  ...
}: let
  cfg = config.programs.terminalKit;
in {
  config = lib.mkIf (cfg.enable && cfg.nvf.enable) {};
}
