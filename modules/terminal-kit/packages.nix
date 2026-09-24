# The general and dev package sets.
{
  config,
  lib,
  ...
}: let
  cfg = config.programs.terminalKit;
in {
  config = lib.mkIf (cfg.enable && (cfg.packages.general.enable || cfg.packages.dev.enable)) {};
}
